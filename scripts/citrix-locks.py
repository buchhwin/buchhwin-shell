#!/usr/bin/env python3
"""Moves Citrix Workspace's stale pid locks aside, once per login and before
each start of Workspace.

Citrix's daemons (AuthManagerDaemon, ServiceRecord, UtilDaemon, selfservice
itself) each write their pid into a lock in ~/.ICAClient/.tmp
(.CtxAuthManager.lock and so on: four bytes, the pid as a native int) and do
not remove it when they are killed - at a logout, or after the five seconds
systemd/citrix-stop.conf gives them at a shutdown. A lock whose pid is gone,
or after a reboot belongs to some other process, starts no daemon: Citrix
Workspace stays white and waits on their pipes for good (27.10.).
scripts/session-init.sh runs this before anything can start Citrix. A lock
held by a running Citrix process stays.

  citrix-locks.py [--before-start] [--dir DIR] [--dest DIR]

The locks go to $XDG_STATE_HOME/buchhwin-shell/citrix-stale-locks, where they
replace the copies of the login before; nothing in ~/.ICAClient is deleted.
Prints one line per lock moved.

--before-start: scripts/launch-app.sh runs it before Citrix Workspace starts.
Daemons of an earlier start had outlived it (Workspace closed, no session);
the new Workspace started a second AuthManagerDaemon next to the old one,
ServiceRecord crashed and Workspace hung on its loading screen (27.10.). While
no selfservice, wfica or storebrowse of the user runs - nothing then needs the
daemons - the Citrix scopes they run in are stopped first, and then the locks
are moved aside; one line per scope stopped. While one runs, nothing is
stopped: that would end a session. A scope with anything but Citrix's
programs in it stays.
"""

import os
import pathlib
import shutil
import struct
import subprocess
import sys

ICAROOT = os.environ.get("ICAROOT", "/opt/Citrix/ICAClient")
# A running Workspace, a session, and a session being started.
IN_USE = ("selfservice", "wfica", "storebrowse")
# The scopes scripts/launch-app.sh starts Workspace and the subscribed
# desktops in (app-buchhwin-<escaped desktop id>-<pid>.scope).
SCOPES = ("app-buchhwin-citrix\\x2dworkspace-", "app-buchhwin-Citrix_subscribed_")
# systemd/citrix-stop.conf gives Workspace's scope five seconds before
# SIGKILL; a subscribed desktop's scope has systemd's 90.
STOP_SECONDS = 8


def lock_pid(path):
    """The pid in a Citrix lock, or None for a file that is no such lock."""
    try:
        data = pathlib.Path(path).read_bytes()
    except OSError:
        return None
    if len(data) != 4:
        return None
    pid = struct.unpack("=i", data)[0]
    return pid if pid > 0 else None


def program(pid, proc="/proc"):
    """The path of the program `pid` runs, "" when it cannot be read."""
    try:
        exe = os.readlink(os.path.join(proc, str(pid), "exe"))
    except OSError:
        try:
            exe = pathlib.Path(proc, str(pid), "cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
        except OSError:
            return ""
    # A program an update replaced while it ran.
    return exe[: -len(" (deleted)")] if exe.endswith(" (deleted)") else exe


def is_citrix(path):
    return path.startswith(ICAROOT.rstrip("/") + "/")


def citrix_process(pid, proc="/proc"):
    """Whether `pid` runs a program from Citrix's install directory."""
    return is_citrix(program(pid, proc))


def unit_of(pid, proc="/proc"):
    """The unit `pid` runs in: the last part of its cgroup's path."""
    try:
        lines = pathlib.Path(proc, str(pid), "cgroup").read_text(errors="replace").splitlines()
    except OSError:
        return ""
    for line in lines:
        if line.startswith("0::"):
            return line[3:].rstrip("/").rsplit("/", 1)[-1]
    return ""


def processes(proc="/proc", uid=None):
    """(pid, program, unit) of each of the user's processes."""
    uid = os.getuid() if uid is None else uid
    try:
        names = os.listdir(proc)
    except OSError:
        return []
    found = []
    for name in names:
        if not name.isdigit():
            continue
        try:
            if os.stat(os.path.join(proc, name)).st_uid != uid:
                continue
        except OSError:
            continue
        found.append((int(name), program(name, proc), unit_of(name, proc)))
    return found


def leftover_scopes(procs):
    """(scopes to stop, scopes that stay) with Citrix daemons nothing uses,
    or None while Workspace or a session runs."""
    if any(os.path.basename(path) in IN_USE for _, path, _ in procs):
        return None
    ours = {unit for _, path, unit in procs if is_citrix(path) and unit.startswith(SCOPES) and unit.endswith(".scope")}
    # Another program would go with the scope; "" is one that just ended.
    mixed = {unit for _, path, unit in procs if unit in ours and path and not is_citrix(path)}
    return sorted(ours - mixed), sorted(mixed)


def run_systemctl(args, timeout):
    subprocess.run(["systemctl", "--user"] + args, stdin=subprocess.DEVNULL, timeout=timeout, check=False)


def stop_scopes(units, run=run_systemctl):
    """Stops `units`; what has not ended after STOP_SECONDS is killed."""
    try:
        run(["stop", "--"] + units, STOP_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass
    except (OSError, subprocess.SubprocessError) as error:
        print("citrix-locks: not stopped: %s" % error, file=sys.stderr)
        return
    try:
        run(["kill", "--signal=SIGKILL", "--"] + units, STOP_SECONDS)
    except (OSError, subprocess.SubprocessError) as error:
        print("citrix-locks: not killed: %s" % error, file=sys.stderr)


def before_start(directory, dest, proc="/proc", run=run_systemctl):
    """--before-start: the lines it prints."""
    scopes = leftover_scopes(processes(proc))
    if scopes is None:
        return []
    stop, stay = scopes
    for unit in stay:
        print("citrix-locks: %s stays: it runs more than Citrix" % unit, file=sys.stderr)
    if stop:
        stop_scopes(stop, run)
    moved = move_aside(stale_locks(directory, running=lambda pid: citrix_process(pid, proc)), dest)
    return ["stopped: %s" % unit for unit in stop] + ["moved aside: %s" % os.path.basename(path) for path in moved]


def stale_locks(directory, running=citrix_process):
    """The locks in `directory` whose pid is no running Citrix process."""
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return []
    found = []
    for name in names:
        path = os.path.join(directory, name)
        if not (name.startswith(".") and name.endswith(".lock")) or os.path.islink(path) or not os.path.isfile(path):
            continue
        pid = lock_pid(path)
        if pid is not None and not running(pid):
            found.append(path)
    return found


def move_aside(paths, dest):
    moved = []
    for path in paths:
        try:
            os.makedirs(dest, mode=0o700, exist_ok=True)
            shutil.move(path, os.path.join(dest, os.path.basename(path)))
            moved.append(path)
        except OSError as error:
            print("citrix-locks: %s stays: %s" % (path, error), file=sys.stderr)
    return moved


def main(argv=None):
    args = sys.argv[1:] if argv is None else list(argv)
    home = pathlib.Path.home()
    state = os.environ.get("XDG_STATE_HOME") or str(home / ".local" / "state")
    directory = str(home / ".ICAClient" / ".tmp")
    dest = os.path.join(state, "buchhwin-shell", "citrix-stale-locks")
    starting = False
    while args:
        flag = args.pop(0)
        if flag == "--before-start":
            starting = True
        elif flag in ("--dir", "--dest") and args:
            if flag == "--dir":
                directory = args.pop(0)
            else:
                dest = args.pop(0)
        else:
            print("usage: citrix-locks.py [--before-start] [--dir DIR] [--dest DIR]", file=sys.stderr)
            return 2
    if starting:
        for line in before_start(directory, dest):
            print(line)
        return 0
    for path in move_aside(stale_locks(directory), dest):
        print("moved aside: %s" % os.path.basename(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
