#!/usr/bin/env python3
"""BlueZ pairing agent for buchhwin-shell.

The shell starts this process and talks to it with JSON lines:

  stdout  {"kind": "ready"}
          {"id": 3, "kind": "confirm", "name": "Headphones", "passkey": "123456"}
          {"id": 4, "kind": "pin" | "passkey" | "authorize" | "service", "name": ...}
          {"kind": "display", "name": ..., "passkey": "123456", "device": PATH}   (no answer)
          {"kind": "cancel"}
  stdin   {"id": 3, "accept": true, "value": "0000"}

Requests the shell does not answer within the timeout are rejected. Accepted
pairings mark the device as trusted so it can reconnect without asking, and so
does a service allowed for a device that is paired already. A code to display
names its device's object path, so the shell can take the code down once that
device is paired: BlueZ sends no Cancel for a code it only showed.

  bluetooth-agent.py [--no-default] [--timeout SECONDS]
"""

import argparse
import ctypes
import json
import os
import signal
import sys
import traceback

import dbus
import dbus.mainloop.glib
import dbus.service

BUS_NAME = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_PATH = "/org/buchhwin/shell/bluetooth_agent"
CAPABILITY = "KeyboardDisplay"


def emit(**values):
    sys.stdout.write(json.dumps(values, ensure_ascii=False) + "\n")
    sys.stdout.flush()


_SOURCE_FUNC = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)
_FD_FUNC = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_void_p)


class GLibLoop:
    """GLib's default main loop, driven through ctypes.

    dbus-python's DBusGMainLoop attaches to GLib's default context, and
    whatever runs that context serves the bus. PyGObject (`from gi.repository
    import GLib`) did, and brought asyncio, ssl, pycairo, fontconfig and
    libX11 along into a Bluetooth agent - 5 of its 16 MB PSS, for the
    handful of calls below (measured: 16.2 MB with PyGObject, 11.0 without).
    libglib-2.0 is in the process anyway (_dbus_glib_bindings links it), so
    this loads nothing new.

    Every callback stays referenced for as long as its source can call it: a
    CFUNCTYPE object collected while GLib still holds its pointer would crash
    the agent. Python's own signal handlers only run when the interpreter gets
    control, which it does not while the C loop sleeps, so SIGTERM and SIGINT
    go through g_unix_signal_add.
    """

    IO_IN = 1
    IO_HUP = 16

    def __init__(self, library="libglib-2.0.so.0"):
        glib = ctypes.CDLL(library)
        glib.g_main_loop_new.restype = ctypes.c_void_p
        glib.g_main_loop_new.argtypes = [ctypes.c_void_p, ctypes.c_int]
        glib.g_main_loop_run.argtypes = [ctypes.c_void_p]
        glib.g_main_loop_quit.argtypes = [ctypes.c_void_p]
        glib.g_timeout_add_seconds.restype = ctypes.c_uint
        glib.g_timeout_add_seconds.argtypes = [ctypes.c_uint, _SOURCE_FUNC, ctypes.c_void_p]
        glib.g_source_remove.restype = ctypes.c_int
        glib.g_source_remove.argtypes = [ctypes.c_uint]
        glib.g_unix_fd_add.restype = ctypes.c_uint
        glib.g_unix_fd_add.argtypes = [ctypes.c_int, ctypes.c_uint, _FD_FUNC, ctypes.c_void_p]
        glib.g_unix_signal_add.restype = ctypes.c_uint
        glib.g_unix_signal_add.argtypes = [ctypes.c_int, _SOURCE_FUNC, ctypes.c_void_p]
        self.glib = glib
        self.loop = glib.g_main_loop_new(None, 0)
        self.callbacks = {}  # source id -> the CFUNCTYPE object GLib calls
        # Callbacks of sources that are gone. They are let go only while no
        # callback of this loop runs: one that ended its own source is still
        # on the stack when it says so.
        self.retired = []
        self.depth = 0

    def _wrap(self, function, args, with_fd):
        source = []

        def call(*c_args):
            self.depth += 1
            try:
                again = bool(function(*c_args[:2], *args) if with_fd else function(*args))
            except Exception:  # noqa: BLE001 - one failing callback must not stop the loop
                traceback.print_exc(file=sys.stderr)
                again = False
            finally:
                self.depth -= 1
            if not again and source:
                self._retire(source[0])
            return 1 if again else 0

        return (_FD_FUNC if with_fd else _SOURCE_FUNC)(call), source

    def _keep(self, tag, callback, source):
        if not self.depth:
            self.retired.clear()
        source.append(tag)
        self.callbacks[tag] = callback
        return tag

    def _retire(self, tag):
        callback = self.callbacks.pop(tag, None)
        if callback is not None:
            self.retired.append(callback)

    def timeout_add_seconds(self, seconds, function, *args):
        """function(*args) after `seconds`, and again while it returns True."""
        callback, source = self._wrap(function, args, False)
        return self._keep(self.glib.g_timeout_add_seconds(int(seconds), callback, None), callback, source)

    def source_remove(self, tag):
        if tag in self.callbacks:
            self.glib.g_source_remove(tag)
            self._retire(tag)

    def fd_add(self, fd, condition, function, *args):
        """function(fd, condition, *args) when `fd` is ready, while it returns True."""
        callback, source = self._wrap(function, args, True)
        return self._keep(self.glib.g_unix_fd_add(fd, condition, callback, None), callback, source)

    def signal_add(self, signum, function, *args):
        """function(*args) on `signum` (SIGTERM, SIGINT, SIGHUP, ...), while it returns True."""
        callback, source = self._wrap(function, args, False)
        return self._keep(self.glib.g_unix_signal_add(signum, callback, None), callback, source)

    def run(self):
        self.glib.g_main_loop_run(self.loop)

    def quit(self):
        self.glib.g_main_loop_quit(self.loop)


glib = GLibLoop()


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


class Agent(dbus.service.Object):
    def __init__(self, bus, timeout, export=True):
        super().__init__(bus if export else None, AGENT_PATH if export else None)
        self.bus = bus
        self.timeout = timeout
        self.next_id = 1
        self.pending = {}  # id -> (reply, error, kind, device, timer)

    # ---- helpers -----------------------------------------------------------
    def properties(self, device):
        return dbus.Interface(bluez_object(self.bus, device), "org.freedesktop.DBus.Properties")

    def device_name(self, device):
        try:
            return str(self.properties(device).Get("org.bluez.Device1", "Alias"))
        except Exception:  # noqa: BLE001 - unknown device or no bus (tests)
            return str(device).rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")

    def paired(self, device):
        try:
            return bool(self.properties(device).Get("org.bluez.Device1", "Paired"))
        except Exception:  # noqa: BLE001 - device vanished or no bus (tests)
            return False

    def trust(self, device):
        try:
            # A variant on the wire, as Properties.Set takes it ("ssv"): the
            # proxy is not introspected, so the type is spelled out here.
            self.properties(device).Set("org.bluez.Device1", "Trusted", dbus.Boolean(True, variant_level=1))
        except Exception:  # noqa: BLE001 - device vanished or no bus (tests)
            pass

    def ask(self, kind, device, reply, error, **extra):
        request_id = self.next_id
        self.next_id += 1
        timer = glib.timeout_add_seconds(self.timeout, self.expire, request_id)
        self.pending[request_id] = (reply, error, kind, device, timer)
        emit(id=request_id, kind=kind, name=self.device_name(device), **extra)

    def expire(self, request_id):
        entry = self.pending.pop(request_id, None)
        if entry:
            entry[1](Canceled("No answer"))
            emit(kind="cancel", id=request_id)
        return False

    def answer(self, message):
        if not isinstance(message, dict):
            return
        entry = self.pending.pop(message.get("id"), None)
        if not entry:
            return
        reply, error, kind, device, timer = entry
        glib.source_remove(timer)
        if not message.get("accept"):
            error(Rejected("Rejected"))
            return
        value = str(message.get("value", ""))
        try:
            if kind == "pin":
                if not value:
                    raise ValueError
                reply(dbus.String(value))
            elif kind == "passkey":
                reply(dbus.UInt32(int(value)))
            else:
                reply()
        except (ValueError, OverflowError):
            error(Rejected("Invalid input"))
            return
        # A service allowed for a paired device is the device the user
        # wants: without the trust BlueZ asks again on every reconnect (a pair
        # made elsewhere, or a Just Works one that never came here). An
        # unpaired device asking for a service is allowed this once only.
        if kind in ("confirm", "pin", "passkey", "authorize") or (kind == "service" and self.paired(device)):
            self.trust(device)

    def cancel_all(self):
        for request_id in list(self.pending):
            reply, error, kind, device, timer = self.pending.pop(request_id)
            glib.source_remove(timer)
            error(Canceled("Canceled"))

    # ---- org.bluez.Agent1 --------------------------------------------------
    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self):
        self.cancel_all()

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="s", async_callbacks=("reply", "error"))
    def RequestPinCode(self, device, reply, error):
        self.ask("pin", device, reply, error)

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        emit(kind="display", name=self.device_name(device), passkey=str(pincode), device=str(device))

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u", async_callbacks=("reply", "error"))
    def RequestPasskey(self, device, reply, error):
        self.ask("passkey", device, reply, error)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit(kind="display", name=self.device_name(device), passkey="%06d" % int(passkey), entered=int(entered),
             device=str(device))

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="", async_callbacks=("reply", "error"))
    def RequestConfirmation(self, device, passkey, reply, error):
        self.ask("confirm", device, reply, error, passkey="%06d" % int(passkey))

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="", async_callbacks=("reply", "error"))
    def RequestAuthorization(self, device, reply, error):
        self.ask("authorize", device, reply, error)

    # BlueZ only asks for untrusted devices, so every request goes to the user.
    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="", async_callbacks=("reply", "error"))
    def AuthorizeService(self, device, uuid, reply, error):
        self.ask("service", device, reply, error, uuid=str(uuid))

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Cancel(self):
        self.cancel_all()
        emit(kind="cancel")


def bluez_object(bus, path):
    # Not introspected: that was one more round trip per call, and every
    # argument below carries its D-Bus type itself (an ObjectPath, a variant).
    return bus.get_object(BUS_NAME, path, introspect=False)


def register(bus, make_default):
    manager = dbus.Interface(bluez_object(bus, "/org/bluez"), "org.bluez.AgentManager1")
    manager.RegisterAgent(dbus.ObjectPath(AGENT_PATH), CAPABILITY)
    if make_default:
        manager.RequestDefaultAgent(dbus.ObjectPath(AGENT_PATH))


def unregister(bus):
    try:
        manager = dbus.Interface(bluez_object(bus, "/org/bluez"), "org.bluez.AgentManager1")
        manager.UnregisterAgent(dbus.ObjectPath(AGENT_PATH))
    except dbus.DBusException:
        pass


# The way out (SIGTERM from the shell, stdin closed). **Only while bluetoothd
# is there:** dbus-python's get_object asks the bus to start a name that has
# no owner (StartServiceByName), and org.bluez is activatable - after a
# `systemctl stop bluetooth` the agent's goodbye started bluetoothd again, the
# shell saw the adapter come back and started the agent, and the stop was
# undone within a second (the same trap as testing.md pitfall 27). NameHasOwner
# never starts anything, and a gone bluetoothd has no agent to forget.
def shutdown(agent, bus):
    agent.cancel_all()
    try:
        there = bus.name_has_owner(BUS_NAME)
    except dbus.DBusException:  # the bus is going too: nobody to say goodbye to
        there = False
    if there:
        unregister(bus)


# Re-register when bluetoothd (re)starts. The bus filters by the name
# (arg0): unfiltered, every client that joined or left the system bus -
# each nmcli, systemctl or busctl - woke the agent twice for nothing.
def subscribe(bus, on_owner):
    def owner_changed(name, old, new):
        if name == BUS_NAME and new:
            on_owner()
    return bus.add_signal_receiver(owner_changed, "NameOwnerChanged", "org.freedesktop.DBus",
                                   bus_name="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                                   arg0=BUS_NAME)


# Answers from the shell on stdin; its end (the shell gone) ends the agent.
def watch_stdin(fd, agent, done):
    # Read raw bytes: a buffered readline() can keep a second answer in
    # Python's buffer where GLib never reports it as readable.
    buffer = bytearray()

    def on_stdin(_fd, _condition):
        chunk = os.read(fd, 4096)
        if not chunk:
            done()
            return False
        buffer.extend(chunk)
        while b"\n" in buffer:
            line, _, rest = bytes(buffer).partition(b"\n")
            buffer[:] = rest
            try:
                agent.answer(json.loads(line.decode("utf-8")))
            except Exception:  # noqa: BLE001 - one bad line must not stop the agent
                pass
        return True
    return glib.fd_add(fd, glib.IO_IN | glib.IO_HUP, on_stdin)


def stop_on_signals(done):
    # Kept after the first one, so a second SIGTERM during the goodbye is
    # one more quit and not the default death halfway through it.
    def stop():
        done()
        return True
    for signum in (signal.SIGTERM, signal.SIGINT):
        glib.signal_add(signum, stop)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-default", action="store_true", help="register without becoming the default agent")
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--check", action="store_true", help="register, unregister and exit (never as default agent)")
    args = parser.parse_args(argv)
    if args.check:
        args.no_default = True

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    agent = Agent(bus, args.timeout)

    def try_register():
        try:
            register(bus, not args.no_default)
            emit(kind="ready")
        except dbus.DBusException as error:
            emit(kind="error", error=error.get_dbus_name())

    try_register()
    if args.check:
        unregister(bus)
        return 0

    subscribe(bus, try_register)
    watch_stdin(sys.stdin.fileno(), agent, glib.quit)
    stop_on_signals(glib.quit)

    try:
        glib.run()
    finally:
        shutdown(agent, bus)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
