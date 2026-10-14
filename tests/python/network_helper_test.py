#!/usr/bin/env python3
"""Unit test for scripts/network-helper.py: choosing the access point, against
a stand-in for the `dbus` module. No system bus, no NetworkManager."""

import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import types

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


class DBusException(Exception):
    def get_dbus_name(self):
        return "org.freedesktop.DBus.Error.UnknownMethod"


# The helper imports dbus at the top; this one is all it gets.
fake_dbus = types.ModuleType("dbus")
fake_dbus.DBusException = DBusException
fake_dbus.Interface = lambda proxy, _interface=None: proxy
fake_dbus.ByteArray = bytes
fake_dbus.UInt32 = int
sys.modules["dbus"] = fake_dbus

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("network_helper", ROOT / "scripts" / "network-helper.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

DEVICE = "/org/freedesktop/NetworkManager/Devices/3"


class Proxy:
    def __init__(self, bus, path):
        self.bus, self.path = bus, path

    # An object NetworkManager no longer has, or a property it no longer
    # answers, is a D-Bus error - which is how a vanished access point looks.
    def Get(self, _interface, name, dbus_interface=None):
        values = self.bus.objects.get(self.path)
        if values is None or name not in values:
            raise DBusException("gone: " + self.path)
        return values[name]

    def GetDevices(self):
        return [DEVICE]

    def GetAllAccessPoints(self):
        return list(self.bus.access_points)


class Bus:
    def __init__(self, access_points, objects):
        self.access_points = access_points
        self.objects = dict(objects, **{DEVICE: {"DeviceType": module.DEVICE_TYPE_WIFI}})

    def get_object(self, _service, path):
        return Proxy(self, path)


def ap(ssid, strength, **extra):
    return dict({"Ssid": list(ssid.encode()), "Strength": strength, "Flags": 1, "WpaFlags": 0,
                 "RsnFlags": module.KEY_MGMT_PSK}, **extra)


# One access point is listed but gone by the time it is read. It is skipped,
# and the strongest of the rest with the name is the one.
bus = Bus(["/ap/1", "/ap/2", "/ap/3", "/ap/4"],
          {"/ap/1": ap("Office", 40), "/ap/3": ap("Office", 70), "/ap/4": ap("Elsewhere", 99)})
check(module.access_point(bus, DEVICE, "Office") == "/ap/3", "a vanished access point is skipped, the strongest named one wins")
check(module.access_point(bus, DEVICE, "Nowhere") is None, "no access point with the name")
gone = Bus(["/ap/2"], {})
check(module.access_point(gone, DEVICE, "Office") is None, "every access point gone is none, not an error")


def connect(bus, *argv, stdin=""):
    fake_dbus.SystemBus = lambda: bus
    sys.stdin = io.StringIO(stdin)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = module.main(["connect"] + list(argv))
    return code, json.loads(out.getvalue())


code, answer = connect(bus, "--ssid", "Office", "--dry-run", stdin="password123\n")
check(code == 0 and answer.get("security") == "wpa-psk", "a dry run past a vanished access point: %s" % answer)
# The chosen one goes between choosing and reading its security: that is a
# network out of range, not a NetworkManager out of reach.
half = Bus(["/ap/1"], {"/ap/1": {"Ssid": list(b"Office"), "Strength": 50}})
code, answer = connect(half, "--ssid", "Office", "--dry-run", stdin="password123\n")
check(code == 1 and answer.get("error") == "Network is no longer in range", "the chosen one gone too: %s" % answer)

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED network_helper_test")
    sys.exit(1)
print("TESTS PASSED network_helper_test")
