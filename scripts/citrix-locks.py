#!/usr/bin/env python3
"""Moves Citrix Workspace's stale pid locks aside, once per login.

Citrix's daemons (AuthManagerDaemon, ServiceRecord, UtilDaemon, selfservice
itself) each write their pid into a lock in ~/.ICAClient/.tmp
(.CtxAuthManager.lock and so on: four bytes, the pid as a native int) and do
not remove it when they are killed - at a logout, or after the five seconds
systemd/citrix-stop.conf gives them at a shutdown. A lock whose pid is gone,
or after a reboot belongs to some other process, starts no daemon: Citrix
Workspace stays white and waits on their pipes for good (27.10.).
scripts/session-init.sh runs this before anything can start Citrix. A lock
held by a running Citrix process stays.

  citrix-locks.py [--dir DIR] [--dest DIR]

The locks go to $XDG_STATE_HOME/buchhwin-shell/citrix-stale-locks, where they
replace the copies of the login before; nothing in ~/.ICAClient is deleted.
Prints one line per lock moved.
"""

import os
import pathlib
import shutil
import struct
import sys

ICAROOT = os.environ.get("ICAROOT", "/opt/Citrix/ICAClient")


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


def citrix_process(pid, proc="/proc"):
    """Whether `pid` runs a program from Citrix's install directory."""
    try:
        exe = os.readlink(os.path.join(proc, str(pid), "exe"))
    except OSError:
        try:
            exe = pathlib.Path(proc, str(pid), "cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
        except OSError:
            return False
    return exe.startswith(ICAROOT.rstrip("/") + "/")


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
    while args:
        flag = args.pop(0)
        if flag in ("--dir", "--dest") and args:
            if flag == "--dir":
                directory = args.pop(0)
            else:
                dest = args.pop(0)
        else:
            print("usage: citrix-locks.py [--dir DIR] [--dest DIR]", file=sys.stderr)
            return 2
    for path in move_aside(stale_locks(directory), dest):
        print("moved aside: %s" % os.path.basename(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
