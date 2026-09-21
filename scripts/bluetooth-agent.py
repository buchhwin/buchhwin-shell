#!/usr/bin/env python3
"""BlueZ pairing agent for buchhwin-shell.

The shell starts this process and talks to it with JSON lines:

  stdout  {"kind": "ready"}
          {"id": 3, "kind": "confirm", "name": "Headphones", "passkey": "123456"}
          {"id": 4, "kind": "pin" | "passkey" | "authorize" | "service", "name": ...}
          {"kind": "display", "name": ..., "passkey": "123456"}   (no answer)
          {"kind": "cancel"}
  stdin   {"id": 3, "accept": true, "value": "0000"}

Requests the shell does not answer within the timeout are rejected. Accepted
pairings mark the device as trusted so it can reconnect without asking.

  bluetooth-agent.py [--no-default] [--timeout SECONDS]
"""

import argparse
import json
import os
import signal
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_PATH = "/org/buchhwin/shell/bluetooth_agent"
CAPABILITY = "KeyboardDisplay"


def emit(**values):
    sys.stdout.write(json.dumps(values, ensure_ascii=False) + "\n")
    sys.stdout.flush()


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
    def device_name(self, device):
        try:
            props = dbus.Interface(self.bus.get_object(BUS_NAME, device), "org.freedesktop.DBus.Properties")
            return str(props.Get("org.bluez.Device1", "Alias"))
        except Exception:  # noqa: BLE001 - unknown device or no bus (tests)
            return str(device).rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")

    def trust(self, device):
        try:
            props = dbus.Interface(self.bus.get_object(BUS_NAME, device), "org.freedesktop.DBus.Properties")
            props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
        except Exception:  # noqa: BLE001 - device vanished or no bus (tests)
            pass

    def ask(self, kind, device, reply, error, **extra):
        request_id = self.next_id
        self.next_id += 1
        timer = GLib.timeout_add_seconds(self.timeout, self.expire, request_id)
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
        GLib.source_remove(timer)
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
        if kind in ("confirm", "pin", "passkey", "authorize"):
            self.trust(device)

    def cancel_all(self):
        for request_id in list(self.pending):
            reply, error, kind, device, timer = self.pending.pop(request_id)
            GLib.source_remove(timer)
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
        emit(kind="display", name=self.device_name(device), passkey=str(pincode))

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u", async_callbacks=("reply", "error"))
    def RequestPasskey(self, device, reply, error):
        self.ask("passkey", device, reply, error)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit(kind="display", name=self.device_name(device), passkey="%06d" % int(passkey), entered=int(entered))

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


def register(bus, make_default):
    manager = dbus.Interface(bus.get_object(BUS_NAME, "/org/bluez"), "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, CAPABILITY)
    if make_default:
        manager.RequestDefaultAgent(AGENT_PATH)


def unregister(bus):
    try:
        manager = dbus.Interface(bus.get_object(BUS_NAME, "/org/bluez"), "org.bluez.AgentManager1")
        manager.UnregisterAgent(AGENT_PATH)
    except dbus.DBusException:
        pass


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
    loop = GLib.MainLoop()

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

    # Re-register when bluetoothd restarts.
    def owner_changed(name, old, new):
        if name == BUS_NAME and new:
            try_register()
    bus.add_signal_receiver(owner_changed, "NameOwnerChanged", "org.freedesktop.DBus")

    # Read raw bytes: a buffered readline() can keep a second answer in
    # Python's buffer where GLib never reports it as readable.
    buffer = bytearray()

    def on_stdin(fd, _condition):
        chunk = os.read(fd, 4096)
        if not chunk:
            loop.quit()
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
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_stdin)

    def stop(*_args):
        loop.quit()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        loop.run()
    finally:
        agent.cancel_all()
        unregister(bus)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
