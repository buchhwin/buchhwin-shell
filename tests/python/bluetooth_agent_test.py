#!/usr/bin/env python3
"""Unit test for scripts/bluetooth-agent.py without a system bus."""

import importlib.util
import io
import json
import pathlib
import sys

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
check(display[0] == {"kind": "display", "name": "00:11:22:33:44:55", "passkey": "000007", "entered": 0}, "display passkey")

for failure in failures:
    print("FAIL bluetooth_agent_test:", failure)
print("TESTS %s bluetooth_agent_test" % ("FAILED" if failures else "PASSED"))
sys.exit(1 if failures else 0)
