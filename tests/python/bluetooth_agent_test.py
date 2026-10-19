#!/usr/bin/env python3
"""Unit test for scripts/bluetooth-agent.py without a system bus."""

import importlib.util
import io
import json
import os
import pathlib
import signal
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("agent", ROOT / "scripts" / "bluetooth-agent.py")
agent_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def capture(callable_):
    buffer = io.StringIO()
    old, sys.stdout = sys.stdout, buffer
    try:
        callable_()
    finally:
        sys.stdout = old
    return [json.loads(line) for line in buffer.getvalue().splitlines() if line.strip()]


class Recorder:
    def __init__(self):
        self.replies = []
        self.errors = []

    def reply(self, *values):
        self.replies.append(values)

    def error(self, exception):
        self.errors.append(exception.get_dbus_name())


agent = agent_module.Agent(None, 60, export=False)
trusted = []
agent.trust = lambda device: trusted.append(device)
device = "/org/bluez/hci0/dev_00_11_22_33_44_55"

rec = Recorder()
out = capture(lambda: agent.RequestConfirmation(device, 42, rec.reply, rec.error))
check(out and out[0]["kind"] == "confirm" and out[0]["passkey"] == "000042", "confirmation request printed with padded passkey")
check(out[0]["name"] == "00:11:22:33:44:55", "device name falls back to the address")
agent.answer({"id": out[0]["id"], "accept": True})
check(rec.replies == [()] and not rec.errors and trusted == [device], "accepted confirmation replies and trusts")

rec = Recorder()
out = capture(lambda: agent.RequestPinCode(device, rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True, "value": "0000"})
check(rec.replies == [("0000",)], "pin reply carries the value")

rec = Recorder()
out = capture(lambda: agent.RequestPinCode(device, rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True, "value": ""})
check(rec.errors == ["org.bluez.Error.Rejected"], "empty pin rejected")

rec = Recorder()
out = capture(lambda: agent.RequestPasskey(device, rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True, "value": "abc"})
check(rec.errors == ["org.bluez.Error.Rejected"], "invalid passkey rejected")

rec = Recorder()
out = capture(lambda: agent.RequestPasskey(device, rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True, "value": "4711"})
check(rec.replies == [(4711,)], "numeric passkey accepted")

rec = Recorder()
trusted.clear()
out = capture(lambda: agent.RequestAuthorization(device, rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": False})
check(rec.errors == ["org.bluez.Error.Rejected"] and not trusted, "declined authorization rejected without trust")

agent.answer({"id": 999, "accept": True})
rec = Recorder()
out = capture(lambda: agent.RequestAuthorization(device, rec.reply, rec.error))
expired = capture(lambda: agent.expire(out[0]["id"]))
check(rec.errors == ["org.bluez.Error.Canceled"] and expired[0]["kind"] == "cancel", "expired request canceled")

rec = Recorder()
capture(lambda: agent.RequestConfirmation(device, 1, rec.reply, rec.error))
cancel = capture(agent.Cancel)
check(rec.errors == ["org.bluez.Error.Canceled"] and cancel[-1]["kind"] == "cancel" and not agent.pending, "Cancel clears pending requests")

agent.answer([1, 2])
agent.answer("text")
check(True, "non-object answers are ignored")

rec = Recorder()
out = capture(lambda: agent.AuthorizeService(device, "0000110b-0000-1000-8000-00805f9b34fb", rec.reply, rec.error))
check(out and out[0]["kind"] == "service", "service authorization always asks")
agent.answer({"id": out[0]["id"], "accept": False})

display = capture(lambda: agent.DisplayPasskey(device, 7, 0))
check(display[0] == {"kind": "display", "name": "00:11:22:33:44:55", "passkey": "000007", "entered": 0, "device": device},
      "display passkey, with the device it is for")
display = capture(lambda: agent.DisplayPinCode(device, "0000"))
check(display[0] == {"kind": "display", "name": "00:11:22:33:44:55", "passkey": "0000", "device": device},
      "display PIN, with the device it is for")

# A service allowed for a paired device trusts it, so BlueZ stops asking on
# every reconnect; for a device that is not paired it is allowed this once.
paired = {"value": True}
agent.paired = lambda _device: paired["value"]
trusted.clear()
rec = Recorder()
out = capture(lambda: agent.AuthorizeService(device, "0000110b-0000-1000-8000-00805f9b34fb", rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True})
check(rec.replies == [()] and trusted == [device], "an allowed service of a paired device trusts it")
paired["value"] = False
trusted.clear()
rec = Recorder()
out = capture(lambda: agent.AuthorizeService(device, "0000110b-0000-1000-8000-00805f9b34fb", rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": True})
check(rec.replies == [()] and not trusted, "an allowed service of an unpaired device does not")
paired["value"] = True
rec = Recorder()
out = capture(lambda: agent.AuthorizeService(device, "0000110b-0000-1000-8000-00805f9b34fb", rec.reply, rec.error))
agent.answer({"id": out[0]["id"], "accept": False})
check(rec.errors == ["org.bluez.Error.Rejected"] and not trusted, "a declined service trusts nothing")


# The way out must never start bluetoothd: dbus-python's get_object asks the
# bus to activate a name without an owner, and org.bluez is activatable.
class StubBus:
    def __init__(self, owner):
        self.owner = owner
        self.objects = []
        self.receivers = []

    def name_has_owner(self, name):
        return self.owner and name == agent_module.BUS_NAME

    def get_object(self, name, path, **keywords):
        if not self.owner:
            failures.append("get_object(%s, %s) while bluetoothd is gone would start it" % (name, path))
        self.objects.append((name, path, keywords))
        raise agent_module.dbus.DBusException("stub")

    def start_service_by_name(self, name, flags=0):
        failures.append("start_service_by_name(%s)" % name)

    def add_signal_receiver(self, handler, *args, **keywords):
        self.receivers.append((handler, args, keywords))


exit_agent = agent_module.Agent(None, 60, export=False)
rec = Recorder()
capture(lambda: exit_agent.RequestConfirmation(device, 5, rec.reply, rec.error))
gone = StubBus(False)
agent_module.shutdown(exit_agent, gone)
check(rec.errors == ["org.bluez.Error.Canceled"] and not exit_agent.pending and not gone.objects,
      "with bluetoothd gone the goodbye cancels and asks nothing of the bus")
there = StubBus(True)
agent_module.shutdown(exit_agent, there)
check([(name, path) for name, path, _ in there.objects] == [("org.bluez", "/org/bluez")]
      and there.objects[0][2].get("introspect") is False,
      "with bluetoothd there it unregisters, without an introspection round trip (%r)" % there.objects)


class BrokenBus(StubBus):
    def name_has_owner(self, name):
        raise agent_module.dbus.DBusException("org.freedesktop.DBus.Error.NoReply")


broken = BrokenBus(False)
try:
    agent_module.shutdown(exit_agent, broken)
    check(not broken.objects, "a bus that cannot answer any more: the goodbye asks nothing more of it")
except agent_module.dbus.DBusException as error:
    check(False, "a bus that cannot answer any more ends the goodbye with an error (%s)" % error)

# Only bluetoothd's own comings and goings wake the agent: the bus filters
# NameOwnerChanged by arg0.
registered = []
agent_module.subscribe(there, lambda: registered.append(True))
check(len(there.receivers) == 1 and there.receivers[0][2].get("arg0") == "org.bluez"
      and there.receivers[0][1][:2] == ("NameOwnerChanged", "org.freedesktop.DBus"),
      "NameOwnerChanged is matched on arg0 org.bluez (%r)" % (there.receivers,))
handler = there.receivers[0][0]
handler("org.bluez", "", ":1.5")
handler("org.bluez", ":1.5", "")
handler(":1.9", "", ":1.9")
check(registered == [True], "and only a new owner of org.bluez registers again")

check("gi" not in sys.modules, "no PyGObject: the loop is GLib's own through ctypes")

# The loop itself, in a process of its own (its signal handling is GLib's
# and would stay with this test): SIGTERM ends it, so does stdin's end, and
# an answer on stdin reaches the agent.
LOOP_PROBE = r"""
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("agent", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
answers = []
class Agent:
    def answer(self, message): answers.append(message)
module.watch_stdin(0, Agent(), module.glib.quit)
module.stop_on_signals(module.glib.quit)
gave_up = []
def give_up():
    gave_up.append(True)
    module.glib.quit()
    return False
module.glib.timeout_add_seconds(5, give_up)
print("running", flush=True)
module.glib.run()
print(json.dumps({"answers": answers, "gaveUp": bool(gave_up), "gi": "gi" in sys.modules}), flush=True)
"""
script = str(ROOT / "scripts" / "bluetooth-agent.py")


def run_loop(stop):
    probe = subprocess.Popen([sys.executable, "-c", LOOP_PROBE, script], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        first = probe.stdout.readline().strip()
        probe.stdin.write(json.dumps({"id": 1, "accept": True}) + "\n")
        probe.stdin.flush()
        time.sleep(0.2)
        stop(probe)
        out, err = probe.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        probe.kill()
        out, err = probe.communicate()
        return None, "timed out: " + err
    lines = [line for line in out.splitlines() if line.strip()]
    try:
        return (first, probe.returncode, json.loads(lines[-1])), err
    except (IndexError, ValueError):
        return None, out + err


def by_signal(probe):
    probe.send_signal(signal.SIGTERM)


def by_eof(probe):
    probe.stdin.close()


for name, stop in (("SIGTERM", by_signal), ("stdin's end", by_eof)):
    result, err = run_loop(stop)
    check(result is not None and result[0] == "running" and result[1] == 0
          and result[2]["answers"] == [{"id": 1, "accept": True}] and not result[2]["gi"]
          and not result[2]["gaveUp"],
          "%s ends the loop, after the answer reached the agent (%r %s)" % (name, result, err.strip()[-300:]))

for failure in failures:
    print("FAIL bluetooth_agent_test:", failure)
print("TESTS %s bluetooth_agent_test" % ("FAILED" if failures else "PASSED"))
sys.exit(1 if failures else 0)
