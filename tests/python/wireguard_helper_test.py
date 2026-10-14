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

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED wireguard_helper_test")
    sys.exit(1)
print("TESTS PASSED wireguard_helper_test")
