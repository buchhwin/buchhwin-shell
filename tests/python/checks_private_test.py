#!/usr/bin/env python3
"""Unit test for `checks.py private`: what counts as private data in a file.

The samples are put together from pieces, so this file itself holds none of
what it looks for and passes the check it tests."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

failures = []


def kinds(text, homes=()):
    return [kind for _line, kind in checks.private_findings(text, homes)]


def expect(text, found, message, homes=()):
    actual = kinds(text, homes)
    if actual != found:
        failures.append(f"{message}: expected {found}, got {actual}")


def j(*parts):
    return "".join(parts)


# Places: the shapes the shell itself writes (settings.json, Open-Meteo).
expect(j('{ "weather": { "lat": 48.', '5734, "lon": 13.', '4597 } }'), ["a coordinate", "a coordinate"],
       "lat/lon keys in a settings.json")
expect(j('"latitude": 48.', '573,\n"longitude": 13.', '459'), ["a coordinate", "a coordinate"],
       "three decimals under latitude/longitude, over two lines")
expect(j("lat=48.", "573&lon=13.", "459"), ["a coordinate", "a coordinate"], "in a URL")
expect(j('{ "lat": 48.', '57, "lon": 13.', '46 }'), [], "two decimals, as invented fixtures keep them")
expect(j("48.", "1234, 13.", "1234"), ["coordinates"], "a pair written side by side")
expect(j("Qt.rgba(0.", "075, 0.", "086, 0.114)"), [], "short decimal pairs in code")
expect("readonly property real notchEpsilon: 0.25", [], "a name that ends in -lon is no longitude")
expect(j("latitude: 52.", "52437, longitude: 13.", "41053"), [], "a public place listed as one")
expect(j('"lat": 48.', '5734  // private-data: invented'), [], "a line marked as invented")
# Keys and tokens.
expect(j("-----BEGIN OPENSSH ", "PRIVATE KEY-----"), ["a private key"], "a PEM private key")
expect(j("-----BEGIN ", "PRIVATE KEY-----"), ["a private key"], "a PKCS#8 one")
expect(j("-----BEGIN PUBLIC", " KEY-----"), [], "a public key is fine")
expect(j("token=gh", "p_", "a1B2" * 9), ["a GitHub token"], "a GitHub token")
expect(j("Private", "Key = ", "A" * 43, "="), ["a WireGuard private key"], "a WireGuard private key")
expect(j("Public", "Key = ", "A" * 43, "="), [], "a WireGuard public key is fine")
# Addresses.
expect(j("mail me: jane.doe", "@", "uni-somewhere.de"), ["an e-mail address"], "an e-mail address")
expect(j("someone", "@", "example.org and ci", "@", "example.invalid"), [], "reserved domains name no one")
expect(j("app-x", "@", "autostart.service"), [], "a systemd unit is no address")
expect(j("git", "@", "github.com:owner/repo.git"), [], "an SSH remote is no address")
expect(j("sudo.x86_64", "@", "1.9.17-3.p2.fc"), [], "a package version is no address")
# This user's home.
home = "/home/" + "jane"
expect(f"cp {home}/x.png .", ["this user's home directory"], "this user's home", homes=[home])
expect(f"cp {home}doe/x.png .", [], "another directory that starts the same", homes=[home])
expect("cp /home/u/x.png .", [], "a fixture's home", homes=[home])
# Where.
found = checks.private_findings(j("one\ntwo\n", '"lon": 13.', "4597\n"))
if found != [(3, "a coordinate")]:
    failures.append(f"the line is named: {found}")
if not isinstance(checks.own_homes(), list):
    failures.append("own_homes is a list")

if failures:
    for failure in failures:
        print("FAIL checks private:", failure)
    print(f"TESTS FAILED checks_private ({len(failures)})")
    sys.exit(1)
print("TESTS PASSED checks_private")
