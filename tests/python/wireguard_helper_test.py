#!/usr/bin/env python3
"""Unit test for scripts/wireguard-helper.py: parsing, checking and the
NetworkManager settings it builds, with invented keys and no bus."""

import contextlib
import importlib.util
import io
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("wireguard_helper", ROOT / "scripts" / "wireguard-helper.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


PRIVATE = "A" * 43 + "="
PUBLIC = "B" * 42 + "A="
CONF = """# a tunnel
[Interface]
PrivateKey = %s
Address = 10.0.0.2/32, fd00::2/128
DNS = 10.0.0.1
[Peer]
PublicKey = %s
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
PersistentKeepalive = 25
""" % (PRIVATE, PUBLIC)

conf = module.parse_conf(CONF)
check(conf["interface"]["privatekey"] == PRIVATE, "the private key is read")
check(module.split_list(conf["peers"][0]["allowedips"]) == ["0.0.0.0/0", "::/0"], "repeated AllowedIPs add up")
check(module.check(conf) == [], "a whole configuration has no errors: %s" % module.check(conf))

built = module.settings(conf, "Office", "wg-office", "someone", "00000000-0000-0000-0000-000000000001")
check(built["connection"]["permissions"] == ["user:someone"], "the tunnel is the user's own, so no password is asked")
check(built["connection"]["autoconnect"] is False, "a new tunnel does not start by itself")
check(built["ipv4"]["address-data"] == [{"address": "10.0.0.2", "prefix": 32}], "the IPv4 address")
check(built["ipv6"]["method"] == "manual", "and the IPv6 one")
check(built["wireguard"]["peers"][0]["persistent-keepalive"] == 25, "keepalive as a number")
check(module.dns_of(conf) == (["10.0.0.1"], []), "DNS split by family")
check(module.masked(built)["wireguard"]["private-key"] == "<key>", "a dry run never prints a key")

bad = module.parse_conf("[Interface]\nPrivateKey = nope\nAddress = 10.0.0.300/32\n")
errors = module.check(bad)
check(any("private key" in e for e in errors) and any("10.0.0.300" in e for e in errors) and any("[Peer]" in e for e in errors),
      "a broken configuration says what is wrong: %s" % errors)
# What a real export carries: search domains among the DNS entries, a routing
# table. Both have a NetworkManager meaning and are kept, not refused.
extra = module.parse_conf(CONF.replace("[Interface]", "[Interface]\nTable = off\nDNS = corp.example, 10.0.0.53"))
check(module.check(extra) == [], "search domains and Table = off are accepted: %s" % module.check(extra))
check(module.search_of(extra) == ["corp.example"], "a DNS entry that is no address is a search domain")
check("corp.example" not in module.dns_of(extra)[0], "and is not a DNS server")
check(module.settings(extra, "x", "wg-x", "someone")["wireguard"]["peer-routes"] is False, "Table = off: no routes for AllowedIPs")
numbered = module.parse_conf(CONF.replace("[Interface]", "[Interface]\nTable = 1234"))
check(module.settings(numbered, "x", "wg-x", "someone")["ipv4"]["route-table"] == 1234, "Table = N: that routing table")
odd = module.parse_conf(CONF.replace("[Interface]", "[Interface]\nTable = main-ish\nDNS = not a domain!"))
check(len(module.check(odd)) == 2, "a Table word or a DNS entry that means nothing is still an error: %s" % module.check(odd))
# wg(8) spells "no keepalive" as off too; that is no keepalive, not an error.
for word in ("off", "Off"):
    quiet = module.parse_conf(CONF.replace("PersistentKeepalive = 25", "PersistentKeepalive = " + word))
    check(module.check(quiet) == [], "PersistentKeepalive = %s is accepted: %s" % (word, module.check(quiet)))
    check("persistent-keepalive" not in module.settings(quiet, "x", "wg-x", "someone")["wireguard"]["peers"][0],
          "PersistentKeepalive = %s sets no keepalive" % word)
noisy = module.parse_conf(CONF.replace("PersistentKeepalive = 25", "PersistentKeepalive = often"))
check(module.check(noisy) == ["PersistentKeepalive is not a number of seconds"], "another word is still an error")
for script in ("PostUp = iptables -A x", "SaveConfig = true"):
    try:
        module.parse_conf("[Interface]\n" + script + "\n")
        check(False, "%s is refused" % script)
    except ValueError:
        pass

# The command itself, as a dry run: one JSON object, keys masked.
out = io.StringIO()
sys.stdin = io.StringIO(CONF)
with contextlib.redirect_stdout(out):
    code = module.main(["add", "--name", "Office", "--ifname", "wg-office", "--dry-run"])
result = json.loads(out.getvalue())
check(code == 0 and result["ok"] and PRIVATE not in out.getvalue(), "a dry run adds nothing and shows no key")
out = io.StringIO()
with contextlib.redirect_stdout(out):
    code = module.main(["add", "--name", "x", "--ifname", "this-name-is-too-long", "--dry-run"])
check(code == 1 and not json.loads(out.getvalue())["ok"], "an interface name past 15 characters is refused")

out = io.StringIO()
with contextlib.redirect_stdout(out):
    code = module.main(["show", "--uuid", "not-a-uuid"])
check(code == 1 and "uuid" in json.loads(out.getvalue())["error"], "show checks the uuid before the bus")


# Editing a tunnel (show, update): what NetworkManager hands out, as the form's
# fields and back. A stand-in for dbus-python's types: plain values.
class FakeDbus:
    String = str
    UInt32 = int
    Boolean = bool

    @staticmethod
    def Array(items, signature=None):
        return list(items)

    @staticmethod
    def Dictionary(items, signature=None):
        return dict(items)


SHARED = "C" * 42 + "A="
UUID = "00000000-0000-0000-0000-000000000002"


def current():
    """A tunnel as GetSettings returns it, with what a user set in KDE's
    editor (a listen port, autoconnect, search domains, a route)."""
    return {
        "connection": {"id": "Home", "uuid": UUID, "type": "wireguard", "interface-name": "wg-home",
                       "autoconnect": True, "permissions": ["user:someone:"], "timestamp": 1792491971},
        "wireguard": {"listen-port": 51999,
                      "peers": [{"public-key": PUBLIC, "endpoint": "old.example.org:1", "preshared-key-flags": 0,
                                 "persistent-keepalive": 25, "allowed-ips": ["192.168.2.0/24"]}]},
        "ipv4": {"method": "manual", "address-data": [{"address": "10.200.200.5", "prefix": 24}],
                 "addresses": [[97044490, 24, 0]], "dns-search": ["corp.example"], "dns-priority": -77,
                 "route-data": [{"dest": "10.1.0.0", "prefix": 16}], "routes": [[256, 16, 0, 0]]},
        "ipv6": {"method": "disabled", "address-data": [], "addresses": []},
    }


SECRETS = {"connection": {}, "wireguard": {"private-key": PRIVATE,
                                           "peers": [{"public-key": PUBLIC, "preshared-key": SHARED}]}}

home = module.with_secrets(current(), SECRETS)
check(home["wireguard"]["private-key"] == PRIVATE and home["wireguard"]["peers"][0]["preshared-key"] == SHARED,
      "the keys come from GetSecrets, the preshared one by its peer's public key")
check(module.editable(home) == "", "a tunnel NetworkManager keeps the keys of can be edited")
fields = module.form_of(home, ["10.0.0.1"], ["fd00::1"])
check(fields == {"name": "Home", "ifname": "wg-home", "address": "10.200.200.5/24", "dns": "10.0.0.1, fd00::1",
                 "privateKey": PRIVATE, "peerKey": PUBLIC, "presharedKey": SHARED, "endpoint": "old.example.org:1",
                 "allowedIps": "192.168.2.0/24", "keepalive": "25"}, "the tunnel as the form's fields: %s" % fields)
check(module.form_of({"connection": {"id": "x"}, "wireguard": {}}, [], [])["peerKey"] == "",
      "a tunnel without a server gives empty server fields")

two = current()
two["wireguard"]["peers"].append(dict(two["wireguard"]["peers"][0]))
check("2 servers" in module.editable(two), "two servers are left to KDE's editor")
wallet = current()
wallet["wireguard"]["private-key-flags"] = 1
check("wallet" in module.editable(wallet), "keys in the wallet are left to KDE's editor")
check(module.editable({"connection": {"type": "vpn"}}) != "", "only WireGuard")
quiet = current()
quiet["wireguard"]["peers"][0]["preshared-key-flags"] = 4
check(module.editable(quiet) == "", "a preshared key that is not required is no reason to refuse")

edited = module.parse_conf("""[Interface]
PrivateKey = %s
Address = 10.200.200.6/24, fd00::6/64
[Peer]
PublicKey = %s
Endpoint = new.example.org:51820
AllowedIPs = 0.0.0.0/0
""" % (PRIVATE, PUBLIC))
read = module.with_secrets(current(), SECRETS)
saved = module.merged(read, edited, "Office", FakeDbus)
check(saved["connection"]["id"] == "Office", "the new name")
check(saved["connection"]["interface-name"] == "wg-home" and saved["connection"]["autoconnect"] is True
      and saved["connection"]["uuid"] == UUID, "the interface, autoconnect and the uuid stay")
check(saved["wireguard"]["listen-port"] == 51999, "a listen port set elsewhere stays")
peer = saved["wireguard"]["peers"][0]
check(peer == {"public-key": PUBLIC, "allowed-ips": ["0.0.0.0/0"], "endpoint": "new.example.org:51820"},
      "the server as the form has it - no keepalive, no preshared key and no flag of the old key: %s" % peer)
check(saved["ipv4"]["address-data"] == [{"address": "10.200.200.6", "prefix": 24}] and "addresses" not in saved["ipv4"],
      "the new address, without the old form NetworkManager would read instead")
check(saved["ipv4"]["route-data"] == [{"dest": "10.1.0.0", "prefix": 16}] and "routes" not in saved["ipv4"],
      "routes stay, in their new form only")
check(saved["ipv4"]["dns-search"] == ["corp.example"] and saved["ipv4"]["dns-priority"] == -77,
      "search domains and the DNS priority stay")
check(saved["ipv6"]["method"] == "manual" and saved["ipv6"]["address-data"] == [{"address": "fd00::6", "prefix": 64}],
      "an IPv6 address switches IPv6 on")
check(read["ipv4"]["addresses"] == [[97044490, 24, 0]] and read["connection"]["id"] == "Home",
      "the connection read is not changed in place")
v4only = module.parse_conf(CONF.replace("Address = 10.0.0.2/32, fd00::2/128", "Address = 10.0.0.2/32"))
off = module.merged(module.with_secrets(dict(current(), ipv6={"method": "manual", "address-data": [{"address": "fd00::6", "prefix": 64}],
                                                             "dns-data": ["fd00::1"], "dns-search": ["six.example"]}), SECRETS),
                    v4only, "Home", FakeDbus)
check(off["ipv6"]["method"] == "disabled" and not any(k.startswith("dns") and k != "dns-priority" for k in off["ipv6"]),
      "no IPv6 address left: IPv6 off, and its DNS with it (NetworkManager refuses DNS on a disabled family): %s" % off["ipv6"])
shared = module.merged(module.with_secrets(current(), SECRETS),
                       module.parse_conf(CONF.replace("PersistentKeepalive = 25", "PresharedKey = " + SHARED)), "Home", FakeDbus)
check(shared["wireguard"]["peers"][0]["preshared-key"] == SHARED and shared["wireguard"]["peers"][0]["preshared-key-flags"] == 0,
      "a preshared key is stored by NetworkManager (flags 0)")
check(SHARED not in json.dumps(module.masked(shared)) and PRIVATE not in json.dumps(module.masked(shared)),
      "a dry run of an update shows no key either")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED wireguard_helper_test")
    sys.exit(1)
print("TESTS PASSED wireguard_helper_test")
