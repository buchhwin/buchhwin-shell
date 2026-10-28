#!/usr/bin/env python3
"""What the first start after an update says (start-shell.sh runs it beside the shell).

    updates-after-start.py --shell-dir DIR --log FILE --state-dir DIR [--pid PID]
                           [--config-dir DIR] [--settle SECONDS] [--server-wait SECONDS]
                           [--dry-run]

Two questions, both against what the start before this one saw, kept in
STATE/versions.json ({"version": 1, "quickshell", "hyprland", "qt", "head"}):

1. The shell's foundation. Arch is rolling, and the shell leans on quirks of
   Quickshell 0.3.2 and Hyprland 0.56: a -Syu can change them under the user
   without a word. When `quickshell --version`, the running Hyprland's
   version or the Qt the shell runs on differs (a Qt minor upgrade keeps
   Quickshell's version string), the shell is watched for its first minute (--settle): its
   log (errors, TypeErrors, binding loops, a crash) and whether it answers on
   its IPC targets. updates.coreCheck in settings.json says what is told:
   "problems" (the default: only when the minute found some), "always" (also
   "the shell started cleanly"), "off". The versions are kept only once the
   minute is over, so a start that is stopped before it (a deploy, a reload)
   leaves the check to the next one.
2. The shell's own checkout. When its HEAD moved (a deploy, an update),
   updates.whatsNew (off by default) posts one quiet notice with up to ten
   commit subjects - written as sentences a user reads - and a button to
   Settings > About.

The first run of all only writes the record: there is nothing to compare yet.
Notices go to the shell's own notification server and only once it owns
org.freedesktop.Notifications (asked with --auto-start=no: a notify-send
before that would start Plasma's server, which has a service file on Arch).
A shell that never got that far - the case the check is for - has no server:
then its problems go to the compositor (`hyprctl notify`, one line naming
the log, as start-shell.sh does when the shell could not start).
Each decision is a JSON line on stdout (start-shell.sh keeps the last
start's in STATE/after-start.log); --dry-run puts the notice it would send
there instead of sending it (tests, and nested sessions, where the host's
server must not hear from a sandbox).
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

STATE_VERSION = 1
CORE_CHECKS = ("off", "problems", "always")
# What counts as a problem in the shell's log, as the smoke test reads it
# (scripts/smoke-session.sh), and what it knows to be harmless there.
PROBLEM = re.compile(r"ERROR|CRIT|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign"
                     r"|Binding loop detected|died on signal|could not start")
# start-shell.sh's own lines for a shell that ended by a fault, not by a stop.
FAILED = ("died on signal", "could not start")
KNOWN = re.compile(r"quickshell\.desktopentry|Could not register notification server|Registration will be attempted again"
                   r"|channelVolumes and channelMap are not the same size|QSettings::value: Empty key passed|playerctld"
                   r"|qt\.qml\.propertyCache\.append|qt\.svg: |QWaylandTextInputv3::")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
VERSION = re.compile(r"(\d+\.\d+(?:\.\d+)?)")
HEAD = re.compile(r"^[0-9a-f]{7,40}$")
QT_CORE = re.compile(r"libQt6Core\.so\.(\d+\.\d+\.\d+)")
MAX_SUBJECTS = 10


def run(argv, timeout=10):
    """stdout of a command, "" when it cannot run or fails."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=timeout, text=True)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout if done.returncode == 0 else ""


# ---- pure parts (tests/python/updates_after_start_test.py) ----------------------

def parse_version(text):
    """"Quickshell 0.3.2 (revision , distributed by Arch Linux)" -> "0.3.2"."""
    match = VERSION.search(str(text or ""))
    return match.group(1) if match else ""


def hyprland_version(json_text, plain_text=""):
    """The running Hyprland's version from `hyprctl version -j` ("version", or
    an older "tag" like "v0.41.2"), else from `Hyprland --version`."""
    try:
        data = json.loads(json_text or "")
    except ValueError:
        data = None
    if isinstance(data, dict):
        for key in ("version", "tag"):
            found = parse_version(data.get(key) if isinstance(data.get(key), str) else "")
            if found:
                return found
    return parse_version(str(plain_text or "").split("\n", 1)[0])


def qt_version(maps_text, libraries=()):
    """The Qt the shell runs on: the libQt6Core.so.6.X.Y its process maps
    (/proc/PID/maps), else the one a libQt6Core.so.6 symlink names now."""
    for text in [maps_text] + [os.path.realpath(path) for path in libraries]:
        match = QT_CORE.search(str(text or ""))
        if match:
            return match.group(1)
    return ""


def read_state(text):
    try:
        data = json.loads(text or "")
    except ValueError:
        return None
    if not isinstance(data, dict) or data.get("version") != STATE_VERSION:
        return None
    clean = {}
    for key in ("quickshell", "hyprland", "qt", "head"):
        value = data.get(key)
        clean[key] = value if isinstance(value, str) and len(value) <= 64 else ""
    return clean


def settings_of(text):
    """(coreCheck, whatsNew) from settings.json, the defaults for anything else."""
    try:
        data = json.loads(text or "")
    except ValueError:
        data = None
    updates = data.get("updates") if isinstance(data, dict) else None
    updates = updates if isinstance(updates, dict) else {}
    check = updates.get("coreCheck")
    return (check if check in CORE_CHECKS else "problems", updates.get("whatsNew") is True)


def changes(before, now):
    """"Quickshell 0.3.2 → 0.3.3" for each part that changed between two records."""
    found = []
    for key, label in (("quickshell", "Quickshell"), ("hyprland", "Hyprland"), ("qt", "Qt")):
        old, new = before.get(key, ""), now.get(key, "")
        if old and new and old != new:
            found.append("%s %s → %s" % (label, old, new))
    return found


def problems(log_text):
    """The log's problem lines, ANSI colour taken out, the known ones left out."""
    found = []
    for line in ANSI.sub("", str(log_text or "")).splitlines():
        if PROBLEM.search(line) and not KNOWN.search(line):
            found.append(line.strip())
    return found


def count_targets(show_text):
    return sum(1 for line in str(show_text or "").splitlines() if line.startswith("target "))


def core_notice(changed, found, targets, mode):
    """(title, body, with_log_button) or None, by updates.coreCheck."""
    if not changed or mode == "off":
        return None
    head = ", ".join(changed)
    trouble = list(found)
    if targets == 0:
        trouble.append("the shell does not answer on IPC")
    if trouble:
        shown = [line if len(line) <= 120 else line[:117] + "…" for line in trouble[:3]]
        noun = "problem" if len(trouble) == 1 else "problems"
        return ("%s: the shell found %d %s" % (head, len(trouble), noun),
                "\n".join(shown) + "\nIts log has the rest.", True)
    if mode != "always":
        return None
    return ("%s: the shell started cleanly" % head,
            "No errors in its log during the first minute, and it answers on %d IPC targets." % targets, False)


def compositor_line(title, log, home):
    """The one line `hyprctl notify` shows for a problem notice, the log's
    place under the home written with ~."""
    shown = str(log)
    if home and shown.startswith(home.rstrip("/") + "/"):
        shown = "~" + shown[len(home.rstrip("/")):]
    return "%s - see %s" % (title, shown)


def whats_new_notice(subjects, total):
    """(title, body) for the moved checkout, or None without a subject."""
    if not subjects:
        return None
    count = total if total and total >= len(subjects) else len(subjects)
    title = "buchhwin-shell updated: %d %s" % (count, "change" if count == 1 else "changes")
    body = "\n".join("· " + subject for subject in subjects[:MAX_SUBJECTS])
    if count > len(subjects[:MAX_SUBJECTS]):
        body += "\n… and %d more in Settings > About" % (count - len(subjects[:MAX_SUBJECTS]))
    return (title, body)


# ---- the machine ---------------------------------------------------------------

def current_versions(shell_dir, pid=None):
    head = run(["git", "-C", str(shell_dir), "rev-parse", "--short=7", "HEAD"]).strip()
    try:
        maps = pathlib.Path("/proc/%d/maps" % pid).read_text(errors="replace") if pid is not None else ""
    except OSError:
        maps = ""
    return {
        "quickshell": parse_version(run(["quickshell", "--version"])),
        "hyprland": hyprland_version(run(["hyprctl", "version", "-j"]), run(["Hyprland", "--version"])),
        "qt": qt_version(maps, sorted(str(path) for path in pathlib.Path("/usr").glob("lib*/libQt6Core.so.6"))),
        "head": head if HEAD.match(head) else "",
    }


def subjects_since(shell_dir, old, new):
    """Up to ten subjects of old..new and how many commits that range holds;
    ([], 0) when old is not in this checkout (a rewritten history)."""
    if not old or not new:
        return [], 0
    try:
        known = subprocess.call(["git", "-C", str(shell_dir), "cat-file", "-e", old + "^{commit}"],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=10) == 0
    except (OSError, subprocess.SubprocessError):
        known = False
    if not known:
        return [], 0
    span = old + ".." + new
    lines = run(["git", "-C", str(shell_dir), "log", "--format=%s", "--max-count=%d" % MAX_SUBJECTS, span]).splitlines()
    total = run(["git", "-C", str(shell_dir), "rev-list", "--count", span]).strip()
    return [line.strip() for line in lines if line.strip()], int(total) if total.isdigit() else 0


def server_up(wait):
    """Whether the shell owns the notification name, waiting up to `wait` s."""
    deadline = time.monotonic() + max(0, wait)
    while True:
        answer = run(["busctl", "--user", "--auto-start=no", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.Notifications"], timeout=5)
        if answer.strip() == "b true":
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(1)


def notify(title, body, action, low):
    """One notice; returns the action key the user chose ("" for none). Ten
    minutes at most, like every waiting notice of the shell (pitfall 78)."""
    argv = ["timeout", "10m", "notify-send", "--app-name=Updates", "--icon=system-software-update"]
    if low:
        argv.append("--urgency=low")
    if action:
        argv.append("--action=%s=%s" % action)
    argv += ["--", title, body]
    return run(argv, timeout=620).strip()


def write_state(state_dir, record):
    path = pathlib.Path(state_dir) / "versions.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=str(path.parent), prefix=".versions.")
    with os.fdopen(handle, "w") as out:
        json.dump(dict(record, version=STATE_VERSION), out, indent=2)
        out.write("\n")
    os.replace(temporary, path)


def alive(pid):
    return pid is not None and os.path.isdir("/proc/%d" % pid)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--shell-dir", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--config-dir", default=os.path.join(os.environ.get("XDG_CONFIG_HOME") or
                                                             os.path.expanduser("~/.config"), "buchhwin-shell"))
    parser.add_argument("--pid", type=int, default=None)
    parser.add_argument("--settle", type=float, default=60)
    parser.add_argument("--server-wait", type=float, default=30)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    started = time.monotonic()

    def say(kind, **values):
        print(json.dumps(dict(values, kind=kind), ensure_ascii=False), flush=True)

    state_path = pathlib.Path(args.state_dir) / "versions.json"
    try:
        before = read_state(state_path.read_text(encoding="utf-8"))
    except OSError:
        before = None
    now = current_versions(args.shell_dir, args.pid)
    try:
        mode, whats_new = settings_of((pathlib.Path(args.config_dir) / "settings.json").read_text(encoding="utf-8"))
    except OSError:
        mode, whats_new = "problems", False
    if before is None:
        write_state(args.state_dir, now)
        say("recorded", **now)
        return 0

    record = dict(before)
    # The checkout first: it answers at once, and the minute below may never end.
    if now["head"] and before.get("head") and now["head"] != before["head"]:
        if whats_new:
            subjects, total = subjects_since(args.shell_dir, before["head"], now["head"])
            notice = whats_new_notice(subjects, total)
            if notice:
                if args.dry_run:
                    say("whatsNew", title=notice[0], body=notice[1])
                elif server_up(args.server_wait):
                    if notify(notice[0], notice[1], ("about", "Show in Settings"), True) == "about":
                        run(["quickshell", "ipc", "--path", str(args.shell_dir), "call", "settings", "open", "about"])
    record["head"] = now["head"] or before.get("head", "")
    write_state(args.state_dir, record)

    changed = changes(before, now)
    if not changed:
        record.update(quickshell=now["quickshell"] or before.get("quickshell", ""),
                      hyprland=now["hyprland"] or before.get("hyprland", ""),
                      qt=now["qt"] or before.get("qt", ""))
        write_state(args.state_dir, record)
        say("unchanged", **now)
        return 0
    if mode == "off":
        record.update(quickshell=now["quickshell"], hyprland=now["hyprland"], qt=now["qt"])
        write_state(args.state_dir, record)
        say("checkOff", changes=changed)
        return 0
    # The shell's first minute.
    remaining = args.settle - (time.monotonic() - started)
    if remaining > 0:
        time.sleep(remaining)
    try:
        log_text = pathlib.Path(args.log).read_text(encoding="utf-8", errors="replace")
    except OSError:
        log_text = ""
    found = problems(log_text)
    if args.pid is not None and not alive(args.pid) and not any(mark in line for line in found for mark in FAILED):
        # Stopped on purpose within the minute (a reload, a deploy): the next
        # start watches again, so the versions are not taken as seen. A shell
        # that crashed or could not start (start-shell.sh says which) is
        # what this check is for, and is told.
        say("stopped", changes=changed)
        return 0
    targets = count_targets(run(["quickshell", "ipc", "--path", str(args.shell_dir), "show"]))
    record.update(quickshell=now["quickshell"], hyprland=now["hyprland"], qt=now["qt"])
    write_state(args.state_dir, record)
    notice = core_notice(changed, found, targets, mode)
    if not notice:
        say("clean", changes=changed, targets=targets)
        return 0
    if args.dry_run:
        say("core", title=notice[0], body=notice[1], problems=len(found), targets=targets)
        return 0
    if not server_up(args.server_wait):
        # No server: the shell is down or broken. Its problems go to the
        # compositor, ten minutes on screen; a clean start can wait.
        if notice[2] and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            line = compositor_line(notice[0], args.log, os.path.expanduser("~"))
            run(["hyprctl", "notify", "0", "600000", "0", line])
            say("compositor", text=line)
        return 0
    if notice[2]:
        if notify(notice[0], notice[1], ("log", "Open log"), False) == "log":
            run(["xdg-open", str(args.log)])
    else:
        notify(notice[0], notice[1], None, True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
