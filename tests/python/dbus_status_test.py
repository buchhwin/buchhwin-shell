#!/usr/bin/env python3
"""scripts/accounts-status.sh and scripts/kdeconnect-status.sh against a stand-in busctl.

Both ask the bus whether their daemon runs (NameHasOwner, which starts
nothing) instead of reading all of /proc with pgrep. The accounts script also
has a status poll (`--status ID...`) that reads only what changes while an
account exists, so the page's 10-second poll costs a third of the calls. The
stand-in answers from a table and logs every call; nothing reaches a real bus.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


# Two resources (one type each), one internal agent of a type without the
# Resource capability.
AGENTS = ["akonadi_ical_resource_0", "akonadi_indexing_agent", "akonadi_imap_resource_0"]
TYPES = {"akonadi_ical_resource_0": "akonadi_ical_resource", "akonadi_indexing_agent": "akonadi_indexing_agent",
         "akonadi_imap_resource_0": "akonadi_imap_resource"}
CAPS = {"akonadi_ical_resource": ["Resource"], "akonadi_imap_resource": ["Resource"],
        "akonadi_indexing_agent": ["Unique", "Autostart"]}

STUB = r'''#!/usr/bin/env python3
import json, os, sys
args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
with open(os.environ["BUSCTL_LOG"], "a") as log:
    log.write(" ".join(args) + "\n")
plain = "--json=short" not in sys.argv
if args[:5] == ["call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner"]:
    print("b true" if args[6] in os.environ.get("BUSCTL_OWNED", "").split() else "b false")
    sys.exit(0)
table = json.loads(os.environ["BUSCTL_TABLE"])
method = args[4] if len(args) > 4 else ""
value = table.get(method + " " + " ".join(args[6:]), table.get(method))
if value is None:
    sys.exit(1)
print(json.dumps(value, separators=(",", ":")))
'''


def table():
    result = {"agentInstances": {"type": "as", "data": [AGENTS]}}
    for agent, kind in TYPES.items():
        result[f"agentInstanceType {agent}"] = {"type": "s", "data": [kind]}
        result[f"agentInstanceName {agent}"] = {"type": "s", "data": [f"Name of {agent}"]}
        result[f"agentInstanceStatus {agent}"] = {"type": "i", "data": [1 if "imap" in agent else 0]}
        result[f"agentInstanceStatusMessage {agent}"] = {"type": "s", "data": ["Ready"]}
        result[f"agentInstanceOnline {agent}"] = {"type": "b", "data": [True]}
        result[f"agentInstanceProgress {agent}"] = {"type": "u", "data": [0]}
    for kind, caps in CAPS.items():
        result[f"agentCapabilities {kind}"] = {"type": "as", "data": [caps]}
        for method in ("agentName", "agentComment", "agentIcon"):
            result[f"{method} {kind}"] = {"type": "s", "data": [f"{method} of {kind}"]}
        result[f"agentMimeTypes {kind}"] = {"type": "as", "data": [["text/calendar"]]}
    return result


with tempfile.TemporaryDirectory() as scratch:
    scratch = pathlib.Path(scratch)
    stubs = scratch / "bin"
    stubs.mkdir()
    (stubs / "busctl").write_text(STUB.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1))
    (stubs / "busctl").chmod(0o755)
    # pgrep would read the real /proc: a call to it is a failure here.
    (stubs / "pgrep").write_text(f"#!/bin/sh\necho pgrep >> \"{scratch / 'pgrep.log'}\"\nexit 1\n")
    (stubs / "pgrep").chmod(0o755)
    log = scratch / "calls.log"

    def run(script, *args, owned=""):
        log.write_text("")
        env = dict(os.environ, PATH=f"{stubs}:{os.environ.get('PATH', '')}", BUSCTL_LOG=str(log),
                   BUSCTL_OWNED=owned, BUSCTL_TABLE=json.dumps(table()))
        result = subprocess.run(["bash", str(ROOT / "scripts" / script), *args], capture_output=True, text=True,
                                env=env, timeout=60)
        return result, log.read_text().splitlines()

    # ---- accounts ----------------------------------------------------------
    result, calls = run("accounts-status.sh")
    check(result.returncode == 0, f"accounts, stopped: status {result.returncode}")
    check("@server stopped" in result.stdout.splitlines(), "no Akonadi bus name: the server is stopped")
    check(calls == ["call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s "
                    "org.freedesktop.Akonadi.Control"], f"and nothing but the name is asked: {calls}")

    result, calls = run("accounts-status.sh", owned="org.freedesktop.Akonadi.Control")
    lines = result.stdout.splitlines()
    check("@server running" in lines, "the bus name owned: running")
    check("@agents " + " ".join(AGENTS) in lines, f"the whole snapshot lists every agent instance: {lines[:4]}")
    check([line for line in lines if line.startswith("@type ")] == ["@type akonadi_ical_resource", "@type akonadi_imap_resource"],
          "only resource types become @type sections")
    check([line for line in lines if line.startswith("@instance ")] == ["@instance akonadi_ical_resource_0",
                                                                        "@instance akonadi_imap_resource_0"],
          "only resource instances become @instance sections")
    check(any(line.startswith("type ") for line in lines), "an instance names its type in the whole snapshot")
    whole = len(calls)

    result, calls = run("accounts-status.sh", "--status", "akonadi_ical_resource_0", "akonadi_imap_resource_0",
                        "bad;id", "akonadi_gone_resource_0", owned="org.freedesktop.Akonadi.Control")
    lines = result.stdout.splitlines()
    check(not any(line.startswith(("@tools", "@type", "type ")) for line in lines),
          f"the status poll reads no tools, types or instance types: {lines}")
    check("@agents " + " ".join(AGENTS) in lines, "but lists the agents, so the shell sees one come or go")
    check([line for line in lines if line.startswith("@instance ")] == ["@instance akonadi_ical_resource_0",
                                                                        "@instance akonadi_imap_resource_0"],
          "the asked instances that exist; an invalid or gone id is skipped")
    check({line.split(" ", 1)[0] for line in lines if not line.startswith("@")} == {"name", "status", "message", "online", "progress"},
          "five values per instance")
    check(len(calls) == 2 + 5 * 2, f"one name check, one agent list and five calls per instance: {len(calls)}")
    check(len(calls) * 2 < whole, f"well under the whole snapshot's {whole} calls")

    result, calls = run("accounts-status.sh", "--status", owned="org.freedesktop.Akonadi.Control")
    check(result.stdout.splitlines() == ["@server running", "@agents " + " ".join(AGENTS)],
          f"a poll without accounts still notices new ones: {result.stdout!r}")
    result, calls = run("accounts-status.sh", "--status", "akonadi_ical_resource_0")
    check(result.stdout.splitlines() == ["@server stopped"] and len(calls) == 1, "a poll while Akonadi is stopped")

    # ---- KDE Connect -------------------------------------------------------
    result, calls = run("kdeconnect-status.sh")
    check(result.stdout.splitlines() == ["@daemon stopped"], f"kdeconnect, no bus name: stopped: {result.stdout!r}")
    check(calls == ["call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.kde.kdeconnect"],
          f"and nothing else is asked: {calls}")
    result, calls = run("kdeconnect-status.sh", owned="org.kde.kdeconnect")
    check(result.stdout.splitlines()[:1] == ["@daemon running"], "the bus name owned: running")
    check(any("selfId" in call for call in calls), "and the daemon is read")
    check(not (scratch / "pgrep.log").exists(), "neither script runs pgrep")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED dbus_status_test")
    sys.exit(1)
print("TESTS PASSED dbus_status_test")
