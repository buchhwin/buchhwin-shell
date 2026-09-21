#!/usr/bin/env python3
"""NetworkManager actions for buchhwin-shell that need secrets.

Secrets are read from stdin (first line) so they never appear in process
arguments. Every command prints exactly one JSON object on stdout.

  network-helper.py check
  network-helper.py connect --ssid SSID [--hidden] [--dry-run]   < password
  network-helper.py hotspot-start --ssid SSID [--dry-run]         < password
  network-helper.py hotspot-stop
  network-helper.py hotspot-status
"""

import argparse
import json
import sys
import time
import uuid

try:
    import dbus
except ImportError:  # pragma: no cover - environment check
    print(json.dumps({"ok": False, "error": "python3-dbus is missing"}))
    sys.exit(1)

NM = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
PROPS = "org.freedesktop.DBus.Properties"
HOTSPOT_ID = "buchhwin-hotspot"

DEVICE_TYPE_WIFI = 2
AP_FLAGS_PRIVACY = 0x1
KEY_MGMT_PSK = 0x100
KEY_MGMT_8021X = 0x200
KEY_MGMT_SAE = 0x400
ACTIVE_ACTIVATED = 2
ACTIVE_DEACTIVATED = 4

# NMDeviceStateReason values that mean "the secret was wrong or missing".
SECRET_REASONS = {7, 8, 9, 10, 11}


def result(**values):
    print(json.dumps(values, ensure_ascii=False))
    return 0 if values.get("ok") else 1


def read_secret():
    line = sys.stdin.readline()
    return line.rstrip("\r\n")


def prop(bus, path, interface, name):
    return bus.get_object(NM, path).Get(interface, name, dbus_interface=PROPS)


def wifi_device(bus):
    manager = dbus.Interface(bus.get_object(NM, NM_PATH), NM)
    for path in manager.GetDevices():
        if int(prop(bus, path, NM + ".Device", "DeviceType")) == DEVICE_TYPE_WIFI:
            return path
    return None


def access_point(bus, device, ssid):
    wireless = dbus.Interface(bus.get_object(NM, device), NM + ".Device.Wireless")
    best, best_strength = None, -1
    for path in wireless.GetAllAccessPoints():
        raw = prop(bus, path, NM + ".AccessPoint", "Ssid")
        if bytes(bytearray(raw)).decode("utf-8", "replace") != ssid:
            continue
        strength = int(prop(bus, path, NM + ".AccessPoint", "Strength"))
        if strength > best_strength:
            best, best_strength = path, strength
    return best


def security_for(bus, ap):
    """Return (key_mgmt or None for open, error)."""
    if ap is None:
        return "wpa-psk", None
    flags = int(prop(bus, ap, NM + ".AccessPoint", "Flags"))
    wpa = int(prop(bus, ap, NM + ".AccessPoint", "WpaFlags"))
    rsn = int(prop(bus, ap, NM + ".AccessPoint", "RsnFlags"))
    combined = wpa | rsn
    if combined & KEY_MGMT_8021X:
        return None, "enterprise"
    if combined & KEY_MGMT_PSK:
        return "wpa-psk", None
    if combined & KEY_MGMT_SAE:
        return "sae", None
    if flags & AP_FLAGS_PRIVACY:
        return "none", None  # WEP
    return None, None


def wait_active(bus, active_path, device, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            state = int(prop(bus, active_path, NM + ".Connection.Active", "State"))
        except dbus.DBusException:
            state = ACTIVE_DEACTIVATED
        if state == ACTIVE_ACTIVATED:
            return True, 0
        if state == ACTIVE_DEACTIVATED:
            break
        time.sleep(0.25)
    reason = 0
    try:
        reason = int(prop(bus, device, NM + ".Device", "StateReason")[1])
    except dbus.DBusException:
        pass
    return False, reason


def delete_connection(bus, path):
    try:
        dbus.Interface(bus.get_object(NM, path), NM + ".Settings.Connection").Delete()
    except dbus.DBusException:
        pass


def cmd_check(bus, _args):
    device = wifi_device(bus)
    return result(ok=True, wifiDevice=device is not None)


def cmd_connect(bus, args):
    device = wifi_device(bus)
    if device is None:
        return result(ok=False, error="No Wi-Fi device found")
    ap = None if args.hidden else access_point(bus, device, args.ssid)
    if ap is None and not args.hidden:
        return result(ok=False, error="Network is no longer in range")
    key_mgmt, problem = security_for(bus, ap)
    if problem == "enterprise":
        return result(ok=False, error="enterprise", message="Enterprise Wi-Fi: please connect in the KDE dialog")
    secret = read_secret() if key_mgmt else ""
    if key_mgmt in ("wpa-psk", "sae") and not 8 <= len(secret) <= 63:
        return result(ok=False, error="The password must be 8 to 63 characters long")
    if args.dry_run:
        return result(ok=True, dryRun=True, security=key_mgmt or "open")

    settings = {
        "connection": {"type": "802-11-wireless", "id": args.ssid, "uuid": str(uuid.uuid4()), "autoconnect": True},
        "802-11-wireless": {"ssid": dbus.ByteArray(args.ssid.encode("utf-8")), "mode": "infrastructure",
                            "hidden": bool(args.hidden)},
        "ipv4": {"method": "auto"},
        "ipv6": {"method": "auto"},
    }
    if key_mgmt == "none":
        settings["802-11-wireless-security"] = {"key-mgmt": "none", "wep-key0": secret, "wep-key-type": dbus.UInt32(2)}
    elif key_mgmt:
        settings["802-11-wireless-security"] = {"key-mgmt": key_mgmt, "psk": secret}

    manager = dbus.Interface(bus.get_object(NM, NM_PATH), NM)
    try:
        connection, active = manager.AddAndActivateConnection(settings, device, ap or "/")
    except dbus.DBusException as error:
        return result(ok=False, error="NetworkManager refused the connection", detail=error.get_dbus_name())
    ok, reason = wait_active(bus, active, device, args.timeout)
    if ok:
        return result(ok=True)
    # Do not keep a profile with a wrong password.
    delete_connection(bus, connection)
    if reason in SECRET_REASONS:
        return result(ok=False, error="Wrong password", reason=reason)
    return result(ok=False, error="Connection failed", reason=reason)


def find_connection(bus, connection_id):
    settings = dbus.Interface(bus.get_object(NM, NM_PATH + "/Settings"), NM + ".Settings")
    for path in settings.ListConnections():
        data = dbus.Interface(bus.get_object(NM, path), NM + ".Settings.Connection").GetSettings()
        if str(data.get("connection", {}).get("id", "")) == connection_id:
            return path
    return None


def active_hotspot(bus):
    for path in prop(bus, NM_PATH, NM, "ActiveConnections"):
        try:
            if str(prop(bus, path, NM + ".Connection.Active", "Id")) == HOTSPOT_ID:
                return path
        except dbus.DBusException:
            continue
    return None


def cmd_hotspot_start(bus, args):
    device = wifi_device(bus)
    if device is None:
        return result(ok=False, error="No Wi-Fi device found")
    secret = read_secret()
    if not 8 <= len(secret) <= 63:
        return result(ok=False, error="The password must be 8 to 63 characters long")
    if not args.ssid.strip():
        return result(ok=False, error="Name is missing")
    if args.dry_run:
        return result(ok=True, dryRun=True)
    existing = find_connection(bus, HOTSPOT_ID)
    if existing:
        delete_connection(bus, existing)
    settings = {
        "connection": {"type": "802-11-wireless", "id": HOTSPOT_ID, "uuid": str(uuid.uuid4()), "autoconnect": False},
        "802-11-wireless": {"ssid": dbus.ByteArray(args.ssid.encode("utf-8")), "mode": "ap", "band": "bg"},
        "802-11-wireless-security": {"key-mgmt": "wpa-psk", "psk": secret, "proto": ["rsn"],
                                     "pairwise": ["ccmp"], "group": ["ccmp"]},
        "ipv4": {"method": "shared"},
        "ipv6": {"method": "ignore"},
    }
    manager = dbus.Interface(bus.get_object(NM, NM_PATH), NM)
    try:
        _connection, active = manager.AddAndActivateConnection(settings, device, "/")
    except dbus.DBusException as error:
        return result(ok=False, error="NetworkManager refused the hotspot", detail=error.get_dbus_name())
    ok, reason = wait_active(bus, active, device, args.timeout)
    return result(ok=True) if ok else result(ok=False, error="Hotspot could not start", reason=reason)


def cmd_hotspot_stop(bus, _args):
    active = active_hotspot(bus)
    if active is None:
        return result(ok=True, active=False)
    dbus.Interface(bus.get_object(NM, NM_PATH), NM).DeactivateConnection(active)
    return result(ok=True, active=False)


def cmd_hotspot_status(bus, _args):
    return result(ok=True, active=active_hotspot(bus) is not None)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    connect = sub.add_parser("connect")
    connect.add_argument("--ssid", required=True)
    connect.add_argument("--hidden", action="store_true")
    connect.add_argument("--dry-run", action="store_true")
    connect.add_argument("--timeout", type=float, default=30)
    hotspot = sub.add_parser("hotspot-start")
    hotspot.add_argument("--ssid", required=True)
    hotspot.add_argument("--dry-run", action="store_true")
    hotspot.add_argument("--timeout", type=float, default=30)
    sub.add_parser("hotspot-stop")
    sub.add_parser("hotspot-status")
    args = parser.parse_args(argv)
    try:
        bus = dbus.SystemBus()
        handler = {
            "check": cmd_check, "connect": cmd_connect, "hotspot-start": cmd_hotspot_start,
            "hotspot-stop": cmd_hotspot_stop, "hotspot-status": cmd_hotspot_status,
        }[args.command]
        return handler(bus, args)
    except dbus.DBusException as error:
        return result(ok=False, error="NetworkManager is not reachable", detail=error.get_dbus_name())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
