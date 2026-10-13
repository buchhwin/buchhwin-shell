#!/usr/bin/env python3
"""WireGuard tunnels in NetworkManager for buchhwin-shell.

A tunnel is added as a NetworkManager connection owned by the user
(connection.permissions user:<name>), which NetworkManager lets the user add
without an administrator password, and which Plasma's network applet lists
like any other: there is one NetworkManager, so both sessions see the same
tunnels. Keys never appear in process arguments: a configuration comes on
stdin or from a file, and every command prints exactly one JSON object.

  wireguard-helper.py genkey                       -> {"ok", "private", "public"}
  wireguard-helper.py pubkey                       < private key -> {"ok", "public"}
  wireguard-helper.py add --name NAME --ifname IF  < wg-quick config
  wireguard-helper.py add --name NAME --ifname IF --file PATH
  wireguard-helper.py delete --uuid UUID
  add takes --dry-run: it prints the settings it would add, keys masked.
"""

import argparse
import getpass
import ipaddress
import json
import os
import re
import subprocess
import sys
import uuid as uuidlib

IFNAME = re.compile(r"^[A-Za-z0-9_.+=-]{1,15}$")
KEY = re.compile(r"^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$")


def answer(**fields):
    print(json.dumps(fields))
    return 0 if fields.get("ok") else 1


def split_list(value):
    return [item.strip() for item in str(value or "").split(",") if item.strip()]


def parse_conf(text):
    """A wg-quick configuration as {"interface": {...}, "peers": [{...}]}.

    Keys are case-insensitive, comments (# and ;) and blank lines are skipped,
    and anything wg-quick itself runs (PostUp, PreDown, Table, SaveConfig) is
    refused rather than silently dropped: NetworkManager would not run it, and
    a tunnel that depends on it would look set up and not work.
    """
    interface, peers, section = {}, [], None
    for raw in str(text).splitlines():
        line = raw.split("#", 1)[0].split(";", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1].strip().lower()
            if name == "interface":
                section = interface
            elif name == "peer":
                section = {}
                peers.append(section)
            else:
                raise ValueError("unknown section [%s]" % line[1:-1])
            continue
        if "=" not in line or section is None:
            raise ValueError("not a WireGuard line: %s" % line)
        key, value = line.split("=", 1)
        key, value = key.strip().lower(), value.strip()
        if key in ("postup", "postdown", "preup", "predown", "table", "saveconfig"):
            raise ValueError("%s is a wg-quick script setting that NetworkManager does not run" % key)
        if key in ("address", "dns", "allowedips") and key in section:
            section[key] = section[key] + ", " + value
        else:
            section[key] = value
    return {"interface": interface, "peers": peers}


def check(conf):
    """The errors in a parsed configuration, as a list of words."""
    errors = []
    interface = conf.get("interface", {})
    if not KEY.match(interface.get("privatekey", "")):
        errors.append("the private key is not a WireGuard key")
    addresses = split_list(interface.get("address"))
    if not addresses:
        errors.append("the interface has no address")
    for address in addresses:
        try:
            ipaddress.ip_interface(address)
        except ValueError:
            errors.append("%s is not an address" % address)
    for server in split_list(interface.get("dns")):
        try:
            ipaddress.ip_address(server)
        except ValueError:
            errors.append("%s is not a DNS server address" % server)
    if not conf.get("peers"):
        errors.append("there is no [Peer]")
    for peer in conf.get("peers", []):
        if not KEY.match(peer.get("publickey", "")):
            errors.append("a peer's public key is not a WireGuard key")
        if peer.get("presharedkey") and not KEY.match(peer["presharedkey"]):
            errors.append("a peer's preshared key is not a WireGuard key")
        if not split_list(peer.get("allowedips")):
            errors.append("a peer has no AllowedIPs")
        for network in split_list(peer.get("allowedips")):
            try:
                ipaddress.ip_network(network, strict=False)
            except ValueError:
                errors.append("%s is not a network" % network)
        keepalive = peer.get("persistentkeepalive", "")
        if keepalive and not (keepalive.isdigit() and int(keepalive) <= 65535):
            errors.append("PersistentKeepalive is not a number of seconds")
    return errors


def settings(conf, name, ifname, user, connection_uuid=None):
    """NetworkManager settings for the tunnel, as plain Python values."""
    interface = conf["interface"]
    addresses = [ipaddress.ip_interface(a) for a in split_list(interface.get("address"))]
    v4 = [a for a in addresses if a.version == 4]
    v6 = [a for a in addresses if a.version == 6]
    peers = []
    for peer in conf["peers"]:
        entry = {"public-key": peer["publickey"],
                 "allowed-ips": split_list(peer.get("allowedips"))}
        if peer.get("endpoint"):
            entry["endpoint"] = peer["endpoint"]
        if peer.get("persistentkeepalive"):
            entry["persistent-keepalive"] = int(peer["persistentkeepalive"])
        if peer.get("presharedkey"):
            entry["preshared-key"] = peer["presharedkey"]
            entry["preshared-key-flags"] = 0
        peers.append(entry)
    wireguard = {"private-key": interface["privatekey"], "private-key-flags": 0, "peers": peers}
    if interface.get("listenport", "").isdigit():
        wireguard["listen-port"] = int(interface["listenport"])
    if interface.get("mtu", "").isdigit():
        wireguard["mtu"] = int(interface["mtu"])
    return {
        "connection": {"id": name, "uuid": connection_uuid or str(uuidlib.uuid4()), "type": "wireguard",
                       "interface-name": ifname, "autoconnect": False, "permissions": ["user:" + user]},
        "wireguard": wireguard,
        "ipv4": {"method": "manual" if v4 else "disabled",
                 "address-data": [{"address": str(a.ip), "prefix": a.network.prefixlen} for a in v4]},
        "ipv6": {"method": "manual" if v6 else "disabled",
                 "address-data": [{"address": str(a.ip), "prefix": a.network.prefixlen} for a in v6]},
    }


def dns_of(conf):
    servers = split_list(conf["interface"].get("dns"))
    return ([s for s in servers if ipaddress.ip_address(s).version == 4],
            [s for s in servers if ipaddress.ip_address(s).version == 6])


def masked(value):
    """Settings with every key replaced, for --dry-run and the tests."""
    if isinstance(value, dict):
        return {k: ("<key>" if k in ("private-key", "preshared-key") else masked(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [masked(v) for v in value]
    return value


def to_dbus(value, dbus):
    """Plain values as the a{sa{sv}} NetworkManager takes."""
    def variant(key, item):
        if key in ("peers", "address-data"):
            return dbus.Array([dbus.Dictionary({k: variant(k, v) for k, v in entry.items()}, signature="sv")
                               for entry in item], signature="a{sv}")
        if isinstance(item, bool):
            return dbus.Boolean(item)
        if isinstance(item, int):
            return dbus.UInt32(item)
        if isinstance(item, list):
            return dbus.Array([dbus.String(v) for v in item], signature="s")
        return dbus.String(item)
    return dbus.Dictionary({group: dbus.Dictionary({k: variant(k, v) for k, v in entries.items()}, signature="sv")
                            for group, entries in value.items()}, signature="sa{sv}")


def nmcli():
    return os.environ.get("BUCHHWIN_NMCLI", "nmcli")


def wg(args, data):
    result = subprocess.run(["wg"] + args, input=data, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def command_add(options):
    if not IFNAME.match(options.ifname):
        return answer(ok=False, error="the interface name may have 15 letters, digits and . _ + = -")
    name = options.name.strip()
    if not name:
        return answer(ok=False, error="the tunnel needs a name")
    try:
        if options.file:
            with open(options.file, encoding="utf-8") as handle:
                text = handle.read()
        else:
            text = sys.stdin.read()
        conf = parse_conf(text)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        return answer(ok=False, error=str(error))
    errors = check(conf)
    if errors:
        return answer(ok=False, error="; ".join(errors))
    user = getpass.getuser()
    wanted = settings(conf, name, options.ifname, user)
    v4, v6 = dns_of(conf)
    if options.dry_run:
        return answer(ok=True, settings=masked(wanted), dns4=v4, dns6=v6)
    try:
        import dbus
    except ImportError:
        return answer(ok=False, error="python3-dbus is missing")
    try:
        bus = dbus.SystemBus()
        manager = dbus.Interface(bus.get_object("org.freedesktop.NetworkManager",
                                                "/org/freedesktop/NetworkManager/Settings"),
                                 "org.freedesktop.NetworkManager.Settings")
        manager.AddConnection(to_dbus(wanted, dbus))
    except dbus.DBusException as error:
        return answer(ok=False, error=error.get_dbus_message() or str(error))
    uuid = wanted["connection"]["uuid"]
    # DNS through nmcli: the D-Bus form of a server list differs between
    # NetworkManager versions, the command line's does not. The tunnel is the
    # user's own, so this needs no password either.
    if v4 or v6:
        args = [nmcli(), "connection", "modify", "uuid", uuid]
        if v4:
            args += ["ipv4.dns", ",".join(v4), "ipv4.dns-priority", "-50"]
        if v6:
            args += ["ipv6.dns", ",".join(v6), "ipv6.dns-priority", "-50"]
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            return answer(ok=True, uuid=uuid, warning="added, but its DNS servers were not set: " + result.stderr.strip())
    return answer(ok=True, uuid=uuid)


def main(argv=None):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("genkey")
    sub.add_parser("pubkey")
    add = sub.add_parser("add")
    add.add_argument("--name", required=True)
    add.add_argument("--ifname", required=True)
    add.add_argument("--file")
    add.add_argument("--dry-run", action="store_true")
    delete = sub.add_parser("delete")
    delete.add_argument("--uuid", required=True)
    options = parser.parse_args(argv)

    try:
        if options.command == "genkey":
            private = wg(["genkey"], "")
            return answer(ok=True, private=private, public=wg(["pubkey"], private + "\n"))
        if options.command == "pubkey":
            private = sys.stdin.readline().strip()
            if not KEY.match(private):
                return answer(ok=False, error="not a WireGuard key")
            return answer(ok=True, public=wg(["pubkey"], private + "\n"))
    except (OSError, subprocess.CalledProcessError):
        return answer(ok=False, error="wg is missing (package wireguard-tools)")
    if options.command == "add":
        return command_add(options)
    if not re.match(r"^[0-9a-fA-F-]{36}$", options.uuid):
        return answer(ok=False, error="not a connection uuid")
    result = subprocess.run([nmcli(), "connection", "delete", "uuid", options.uuid], capture_output=True, text=True)
    if result.returncode != 0:
        return answer(ok=False, error=result.stderr.strip() or "nmcli failed")
    return answer(ok=True)


if __name__ == "__main__":
    sys.exit(main())
