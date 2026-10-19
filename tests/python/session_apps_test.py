#!/usr/bin/env python3
"""scripts/session-apps.py: the kept windows (joined with Hyprland's floating
state and geometry by address, relative to their screen, never a title), the
state file (atomic, 0600, also over an older one with other modes), the
offer's mark, forgetting, and the wait for the login's wallet step - on a
stand-in hyprctl and a temporary timeline, never the session's."""

import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "session-apps.py"
spec = importlib.util.spec_from_file_location("session_apps", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


WINDOWS = [
    {"address": "0x55aa01", "app": "org.kde.dolphin", "cls": "org.kde.dolphin", "monitor": "Example Monitor A",
     "monitorName": "DP-10", "workspace": 3, "local": True, "title": "Secret mail subject"},
    {"address": "55AA02", "app": "", "cls": "Probe-App", "monitor": "", "monitorName": "eDP-1", "workspace": 12, "local": False},
    {"address": "0x55aa03", "app": "gone", "cls": "gone", "monitorName": "DP-10", "workspace": 2},
    {"address": "not-hex", "cls": "x", "workspace": 1},
    {"address": "0x55aa04", "cls": "", "workspace": 1},
    {"address": "0x55aa05", "cls": "special", "workspace": -99},
    "nonsense",
]
CLIENTS = [
    {"address": "0x55aa01", "floating": True, "at": [2404, 140], "size": [900, 700], "monitor": 1,
     "title": "Secret mail subject", "class": "org.kde.dolphin"},
    {"address": "0x55aa02", "floating": False, "at": [0, 0], "size": [1920, 1200], "monitor": 0},
]
MONITORS = [{"id": 0, "name": "eDP-1", "x": 0, "y": 0}, {"id": 1, "name": "DP-10", "x": 2304, "y": 0}]

kept = module.entries(WINDOWS, CLIENTS, MONITORS)
check([entry["cls"] for entry in kept] == ["org.kde.dolphin", "probe-app"],
      "only windows Hyprland still lists, with an address, a class and a real workspace: %r" % kept)
check(kept[0] == {"app": "org.kde.dolphin", "cls": "org.kde.dolphin", "monitor": "Example Monitor A", "monitorName": "DP-10",
                  "workspace": 3, "local": True, "floating": True, "x": 100, "y": 140, "width": 900, "height": 700},
      "a floating window: its spot relative to its screen and its size: %r" % kept[0])
check(kept[1] == {"app": "", "cls": "probe-app", "monitor": "", "monitorName": "eDP-1", "workspace": 12, "local": False,
                  "floating": False}, "a tiled window of no known app: its class and place: %r" % kept[1])
check(all("title" not in entry and "address" not in entry for entry in kept), "no title and no address is ever kept")
unanswered = module.entries(WINDOWS, None, None)
check(len(unanswered) == 3 and not any(entry["floating"] for entry in unanswered),
      "Hyprland silent: every window kept as tiled: %r" % unanswered)
check(module.entries("nonsense", CLIENTS, MONITORS) == [], "no list, nothing kept")
many = [{"address": "0x%x" % (index + 1), "cls": "a", "workspace": 1} for index in range(80)]
check(len(module.entries(many, None, None)) == module.MAX_ENTRIES, "at most %d windows" % module.MAX_ENTRIES)

check([module.login_done(text) for text in (
    "06:55:44 +  958ms kwallet unlocked: open (already)\n",
    "06:55:44 +  958ms kwallet LOCKED: dismissed - applications ...\n",
    "06:55:44 +  958ms kwallet NOT available: no service\n",
    "06:55:44 +  958ms kwallet: scripts/wallet-unlock.sh missing, wallet state unknown\n",
    "06:55:44 + 1590ms session-init finished\n",
    "06:55:43 +  290ms kwallet handed the login\n06:55:43 +  296ms shell started\n",
    "")] == [True, True, True, True, True, False, False],
      "the wallet step's marks end the wait, the hand-over before it does not")

with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    bin_dir = base / "bin"
    bin_dir.mkdir()
    (base / "clients.json").write_text(json.dumps(CLIENTS))
    (base / "monitors.json").write_text(json.dumps(MONITORS))
    stand_in = bin_dir / "hyprctl"
    stand_in.write_text("#!/bin/sh\n[ \"$1\" = -j ] || exit 3\ncat \"%s/$2.json\"\n" % base)
    stand_in.chmod(0o755)
    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""))
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    state = base / "state" / "buchhwin-shell" / "session-apps.json"

    def run(*args):
        return subprocess.run([sys.executable, str(SCRIPT)] + list(args), env=env, capture_output=True, text=True,
                              timeout=30, check=False)

    done = run("snapshot", str(state), json.dumps(WINDOWS))
    check(done.returncode == 0 and state.exists(), "snapshot writes the file: %s" % done.stderr)
    mode = stat.S_IMODE(state.stat().st_mode)
    check(mode == 0o600, "the file is the user's alone: %o" % mode)
    data = json.loads(state.read_text())
    check(data["version"] == 1 and data["offered"] is False and len(data["entries"]) == 2
          and data["savedAt"].endswith("Z"), "version, time, not offered, two windows: %r" % data)
    check("Secret" not in state.read_text(), "no title in the file")
    check(not [name for name in os.listdir(state.parent) if name.startswith(".session-apps.")],
          "no temporary file left beside it")

    state.chmod(0o644)
    done = run("mark-offered", str(state))
    check(done.returncode == 0 and json.loads(state.read_text())["offered"] is True, "marked as offered")
    check(stat.S_IMODE(state.stat().st_mode) == 0o600, "a rewrite is 0600 again, whatever the old file was")
    check(len(json.loads(state.read_text())["entries"]) == 2, "the mark keeps the windows")

    done = run("snapshot", str(state), "not json")
    check(done.returncode == 0 and json.loads(state.read_text())["entries"] == [],
          "an unreadable list keeps nothing - and replaces the old session's: %s" % done.stderr)

    (base / "clients.json").write_text("not json")
    done = run("snapshot", str(state), json.dumps(WINDOWS))
    check(done.returncode == 0 and len(json.loads(state.read_text())["entries"]) == 3,
          "Hyprland's answer unreadable: the shell's list kept as tiled")

    blocked = base / "blocked"
    blocked.write_text("a file where the directory should be")
    done = run("snapshot", str(blocked / "session-apps.json"), json.dumps(WINDOWS))
    check(done.returncode == 0 and "not kept" in done.stderr, "a failed write says so and still exits 0: %r" % done.stderr)

    done = run("forget", str(state))
    check(done.returncode == 0 and not state.exists(), "forget removes it")
    check(run("forget", str(state)).returncode == 0, "forgetting nothing is no error")
    check(run("mark-offered", str(state)).returncode == 0 and not state.exists(), "nothing to mark, nothing written")

    log = base / "startup.log"
    log.write_text("06:55:43 +  290ms kwallet handed the login\n")
    clock = {"now": 0.0}

    def tick(seconds):
        clock["now"] += seconds
        if clock["now"] >= 1.0 and "unlocked" not in log.read_text():
            log.write_text(log.read_text() + "06:55:44 +  958ms kwallet unlocked: open (already)\n")

    check(module.wait_login(str(log), 10, 0.5, tick, lambda: clock["now"]) == 0 and clock["now"] < 2,
          "the wait ends at the wallet's mark")
    log.write_text("06:55:43 +  290ms kwallet handed the login\n")
    clock["now"] = 0.0
    check(module.wait_login(str(log), 2, 0.5, lambda s: clock.__setitem__("now", clock["now"] + s),
                            lambda: clock["now"]) == 2, "and gives up after its time")
    clock["now"] = 0.0
    check(module.wait_login(str(base / "missing.log"), 60, 0.5, lambda s: clock.__setitem__("now", clock["now"] + s),
                            lambda: clock["now"]) == 2 and clock["now"] < 4, "no timeline: a short grace, then on")

    check(run("bogus").returncode == 2 and run().returncode == 2, "unknown commands are refused")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED session_apps_test (%d)" % len(failures))
    sys.exit(1)
print("TESTS PASSED session_apps_test")
