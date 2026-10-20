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
  wireguard-helper.py show --uuid UUID             -> {"ok", "tunnel": {the form's fields}, "public"}
  wireguard-helper.py update --uuid UUID --name NAME  < wg-quick config
  add and update take --dry-run: they print the settings they would send,
  keys masked.
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


DOMAIN = re.compile(r"^(?=.{1,253}$)([A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?\.?)+$")


def is_address(text):
    try:
        ipaddress.ip_address(text)
        return True
    except ValueError:
        return False


def keepalive_of(peer):
    """A peer's PersistentKeepalive, "" when there is none: wg(8) also
    spells that "off"."""
    value = peer.get("persistentkeepalive", "")
    return "" if value.lower() == "off" else value


def parse_conf(text):
    """A wg-quick configuration as {"interface": {...}, "peers": [{...}]}.

    Keys are case-insensitive, comments (# and ;) and blank lines are skipped,
    and the scripts wg-quick itself runs (PostUp, PreDown, SaveConfig) are
    refused rather than silently dropped: NetworkManager would not run them,
    and a tunnel that depends on them would look set up and not work. Table
    has a NetworkManager meaning and is kept (see `settings`).
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
        if key in ("postup", "postdown", "preup", "predown", "saveconfig"):
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
    # wg-quick reads a DNS entry that is not an address as a search domain.
    for entry in split_list(interface.get("dns")):
        if not is_address(entry) and not DOMAIN.match(entry):
            errors.append("%s is neither a DNS server address nor a search domain" % entry)
    table = interface.get("table", "auto").lower()
    if table not in ("auto", "off") and not (table.isdigit() and 0 < int(table) < 2 ** 32):
        errors.append("Table = %s is not auto, off or a table number" % interface.get("table"))
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
        keepalive = keepalive_of(peer)
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
        if keepalive_of(peer):
            entry["persistent-keepalive"] = int(keepalive_of(peer))
        if peer.get("presharedkey"):
            entry["preshared-key"] = peer["presharedkey"]
            entry["preshared-key-flags"] = 0
        peers.append(entry)
    wireguard = {"private-key": interface["privatekey"], "private-key-flags": 0, "peers": peers}
    # Table = off: wg-quick adds no routes for AllowedIPs; NetworkManager's
    # word for that is peer-routes. A number is the routing table to use.
    table = interface.get("table", "auto").lower()
    if table == "off":
        wireguard["peer-routes"] = False
    if interface.get("listenport", "").isdigit():
        wireguard["listen-port"] = int(interface["listenport"])
    if interface.get("mtu", "").isdigit():
        wireguard["mtu"] = int(interface["mtu"])
    routing = {"route-table": int(table)} if table.isdigit() else {}
    return {
        "connection": {"id": name, "uuid": connection_uuid or str(uuidlib.uuid4()), "type": "wireguard",
                       "interface-name": ifname, "autoconnect": False, "permissions": ["user:" + user]},
        "wireguard": wireguard,
        "ipv4": dict({"method": "manual" if v4 else "disabled",
                      "address-data": [{"address": str(a.ip), "prefix": a.network.prefixlen} for a in v4]}, **routing),
        "ipv6": dict({"method": "manual" if v6 else "disabled",
                      "address-data": [{"address": str(a.ip), "prefix": a.network.prefixlen} for a in v6]}, **routing),
    }


def dns_of(conf):
    servers = [s for s in split_list(conf["interface"].get("dns")) if is_address(s)]
    return ([s for s in servers if ipaddress.ip_address(s).version == 4],
            [s for s in servers if ipaddress.ip_address(s).version == 6])


def search_of(conf):
    """The DNS entries that are search domains, not servers."""
    return [s for s in split_list(conf["interface"].get("dns")) if not is_address(s)]


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


# What the form shows of a tunnel's one server; the rest of the peer is kept
# when the form is saved. The preshared key's flags go with the key: 0 with
# one (settings), none without - NetworkManager's default for a peer is "not
# required", and a 0 kept from a removed key made it wait for one that no
# agent had ("No agents were available" on the next GetSecrets).
FORM_PEER = ("public-key", "preshared-key", "preshared-key-flags", "endpoint", "allowed-ips", "persistent-keepalive")
# GetSettings hands out the old form of some properties next to the new one,
# and NetworkManager reads the old one when both come back: new addresses
# beside the old "addresses" would be ignored.
DEPRECATED = (("addresses", "address-data"), ("routes", "route-data"), ("dns", "dns-data"))


def editable(current):
    """Why the form cannot edit this connection (GetSettings), or ""."""
    if current.get("connection", {}).get("type") != "wireguard":
        return "it is not a WireGuard tunnel"
    wireguard = current.get("wireguard", {})
    peers = wireguard.get("peers", [])
    if len(peers) > 1:
        return "it has %d servers and the form shows one" % len(peers)
    # Agent-owned (1) or not saved (2): the keys are in the wallet or asked
    # for at each start, and GetSecrets would not hand them to the form.
    flags = [wireguard.get("private-key-flags", 0)] + [peer.get("preshared-key-flags", 0) for peer in peers]
    if any(int(flag) & 3 for flag in flags):
        return "its keys are kept in the wallet, not by NetworkManager"
    return ""


def with_secrets(current, secrets):
    """GetSettings leaves the keys out; GetSecrets has them, the preshared
    keys by the public key of their peer."""
    found = secrets.get("wireguard", {})
    wireguard = current["wireguard"]
    if "private-key" in found:
        wireguard["private-key"] = found["private-key"]
    shared = {str(peer.get("public-key")): peer for peer in found.get("peers", [])}
    for peer in wireguard.get("peers", []):
        extra = shared.get(str(peer.get("public-key")), {})
        if "preshared-key" in extra:
            peer["preshared-key"] = extra["preshared-key"]
    return current


def form_of(current, dns4, dns6):
    """A connection (with its secrets) as the fields of WireguardForm.qml."""
    connection = current.get("connection", {})
    wireguard = current.get("wireguard", {})
    peer = (wireguard.get("peers") or [{}])[0]
    addresses = ["%s/%s" % (entry["address"], entry["prefix"])
                 for family in ("ipv4", "ipv6") for entry in current.get(family, {}).get("address-data", [])]
    keepalive = int(peer.get("persistent-keepalive", 0))
    return {"name": str(connection.get("id", "")), "ifname": str(connection.get("interface-name", "")),
            "address": ", ".join(addresses), "dns": ", ".join(dns4 + dns6),
            "privateKey": str(wireguard.get("private-key", "")), "peerKey": str(peer.get("public-key", "")),
            "presharedKey": str(peer.get("preshared-key", "")), "endpoint": str(peer.get("endpoint", "")),
            "allowedIps": ", ".join(str(network) for network in peer.get("allowed-ips", [])),
            "keepalive": str(keepalive) if keepalive else ""}


def merged(current, conf, name, dbus):
    """The connection as NetworkManager has it (secrets included), with what
    the form shows replaced: the name, the private key, the addresses and the
    server. The rest - the interface name, autoconnect, a listen port, routes
    or search domains set in KDE's editor - stays as it was."""
    connection = current["connection"]
    fresh = to_dbus(settings(conf, name, str(connection.get("interface-name", "")), "-", str(connection["uuid"])), dbus)
    result = dbus.Dictionary({group: dbus.Dictionary(dict(entries), signature="sv") for group, entries in current.items()},
                             signature="sa{sv}")
    result["connection"]["id"] = fresh["connection"]["id"]
    wireguard = result["wireguard"]
    wireguard["private-key"] = fresh["wireguard"]["private-key"]
    old = (current["wireguard"].get("peers") or [{}])[0]
    peer = {key: value for key, value in old.items() if key not in FORM_PEER}
    peer.update(fresh["wireguard"]["peers"][0])
    wireguard["peers"] = dbus.Array([dbus.Dictionary(peer, signature="sv")], signature="a{sv}")
    for family in ("ipv4", "ipv6"):
        if family not in result:
            result[family] = dbus.Dictionary({}, signature="sv")
        group = result[family]
        addresses = fresh[family]["address-data"]
        if addresses:
            group["method"] = dbus.String("manual")
        elif str(group.get("method", "manual")) == "manual":
            group["method"] = dbus.String("disabled")
        group["address-data"] = addresses
        # A family switched off may have no DNS: NetworkManager refuses the
        # update ("ipv6.dns: this property is not allowed for 'method=disabled'").
        if str(group["method"]) == "disabled":
            for key in ("dns", "dns-data", "dns-search", "dns-options"):
                group.pop(key, None)
        for old_key, new_key in DEPRECATED:
            if new_key in group:
                group.pop(old_key, None)
    return result


def connection_of(dbus, uuid):
    bus = dbus.SystemBus()
    manager = dbus.Interface(bus.get_object("org.freedesktop.NetworkManager",
                                            "/org/freedesktop/NetworkManager/Settings"),
                             "org.freedesktop.NetworkManager.Settings")
    path = manager.GetConnectionByUuid(uuid)
    return dbus.Interface(bus.get_object("org.freedesktop.NetworkManager", path),
                          "org.freedesktop.NetworkManager.Settings.Connection")


def dns_now(uuid):
    """The tunnel's DNS servers as (v4, v6), or None: through nmcli, which
    writes them too (command_add)."""
    try:
        result = subprocess.run([nmcli(), "-g", "ipv4.dns,ipv6.dns", "connection", "show", "uuid", uuid],
                                capture_output=True, text=True)
    except OSError:
        return None
    if result.returncode != 0:
        return None
    lines = (result.stdout.splitlines() + ["", ""])[:2]
    # -g escapes the colons of IPv6 addresses.
    return tuple(split_list(line.replace("\\:", ":").replace("\\\\", "\\")) for line in lines)


def read_tunnel(dbus, uuid):
    """(connection interface, settings with secrets), or an error in words."""
    connection = connection_of(dbus, uuid)
    current = connection.GetSettings()
    why = editable(current)
    if why:
        return None, "This tunnel cannot be edited here (%s): KDE's editor can (Edit VPN and connections)" % why
    return connection, with_secrets(current, connection.GetSecrets("wireguard"))


def command_show(options):
    try:
        import dbus
    except ImportError:
        return answer(ok=False, error="python3-dbus is missing")
    try:
        connection, current = read_tunnel(dbus, options.uuid)
    except dbus.DBusException as error:
        return answer(ok=False, error=error.get_dbus_message() or str(error))
    if connection is None:
        return answer(ok=False, error=current)
    dns = dns_now(options.uuid)
    if dns is None:
        return answer(ok=False, error="nmcli could not read the tunnel's DNS servers")
    tunnel = form_of(current, *dns)
    public = ""
    if KEY.match(tunnel["privateKey"]):
        try:
            public = wg(["pubkey"], tunnel["privateKey"] + "\n")
        except (OSError, subprocess.CalledProcessError):
            pass
    return answer(ok=True, tunnel=tunnel, public=public)


def command_update(options):
    name = options.name.strip()
    if not name:
        return answer(ok=False, error="the tunnel needs a name")
    try:
        conf = parse_conf(sys.stdin.read())
    except (UnicodeDecodeError, ValueError) as error:
        return answer(ok=False, error=str(error))
    errors = check(conf)
    if len(conf["peers"]) > 1:
        errors.append("the form has one server")
    if errors:
        return answer(ok=False, error="; ".join(errors))
    try:
        import dbus
    except ImportError:
        return answer(ok=False, error="python3-dbus is missing")
    try:
        connection, current = read_tunnel(dbus, options.uuid)
        if connection is None:
            return answer(ok=False, error=current)
        wanted = merged(current, conf, name, dbus)
    except dbus.DBusException as error:
        return answer(ok=False, error=error.get_dbus_message() or str(error))
    before = dns_now(options.uuid)
    if before is None:
        return answer(ok=False, error="nmcli could not read the tunnel's DNS servers")
    # The form's DNS field holds servers only; search domains stay as they are.
    # A first server gets the priority add gives one.
    changes = []
    for family, servers, old in zip(("ipv4", "ipv6"), dns_of(conf), before):
        if servers != old:
            changes += [family + ".dns", ",".join(servers)]
            if servers and not old and "dns-priority" not in current.get(family, {}):
                changes += [family + ".dns-priority", "-50"]
    if options.dry_run:
        return answer(ok=True, settings=masked(wanted), dns=changes)
    try:
        connection.Update(wanted)
    except dbus.DBusException as error:
        return answer(ok=False, error=error.get_dbus_message() or str(error))
    if changes:
        result = subprocess.run([nmcli(), "connection", "modify", "uuid", options.uuid] + changes,
                                capture_output=True, text=True)
        if result.returncode != 0:
            return answer(ok=True, uuid=options.uuid,
                          warning="saved, but its DNS servers were not changed: " + result.stderr.strip())
    return answer(ok=True, uuid=options.uuid)


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
    search = search_of(conf)
    if options.dry_run:
        return answer(ok=True, settings=masked(wanted), dns4=v4, dns6=v6, search=search)
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
    if v4 or v6 or search:
        args = [nmcli(), "connection", "modify", "uuid", uuid]
        if v4:
            args += ["ipv4.dns", ",".join(v4), "ipv4.dns-priority", "-50"]
        if v6:
            args += ["ipv6.dns", ",".join(v6), "ipv6.dns-priority", "-50"]
        if search:
            args += ["ipv4.dns-search" if v4 or not v6 else "ipv6.dns-search", ",".join(search)]
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
    show = sub.add_parser("show")
    show.add_argument("--uuid", required=True)
    update = sub.add_parser("update")
    update.add_argument("--uuid", required=True)
    update.add_argument("--name", required=True)
    update.add_argument("--dry-run", action="store_true")
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
    if options.command == "show":
        return command_show(options)
    if options.command == "update":
        return command_update(options)
    result = subprocess.run([nmcli(), "connection", "delete", "uuid", options.uuid], capture_output=True, text=True)
    if result.returncode != 0:
        return answer(ok=False, error=result.stderr.strip() or "nmcli failed")
    return answer(ok=True)


if __name__ == "__main__":
    sys.exit(main())
