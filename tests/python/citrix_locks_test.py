#!/usr/bin/env python3
"""Unit test for scripts/citrix-locks.py: which of Citrix's pid locks are
stale and where they go - in a temporary directory, with invented pids."""

import contextlib
import importlib.util
import io
import os
import pathlib
import struct
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("citrix_locks", ROOT / "scripts" / "citrix-locks.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def lock(directory, name, pid):
    path = pathlib.Path(directory) / name
    path.write_bytes(struct.pack("=i", pid))
    return str(path)


with tempfile.TemporaryDirectory() as tmp:
    tmpdir = pathlib.Path(tmp) / ".tmp"
    tmpdir.mkdir()
    dead = lock(tmpdir, ".CtxAuthManager.lock", 4100)
    alive = lock(tmpdir, ".CtxServiceRecord.lock", 4200)
    reused = lock(tmpdir, ".UtilDaemon.lock", 4300)
    (tmpdir / ".selfserv.lock").write_bytes(b"\x01\x02")
    (tmpdir / "notes.lock").write_bytes(struct.pack("=i", 4100))
    (tmpdir / ".SR_BEACON_LINUXRead").write_bytes(struct.pack("=i", 4100))
    (tmpdir / ".zero.lock").write_bytes(struct.pack("=i", 0))
    os.symlink(dead, tmpdir / ".link.lock")

    # 4200 is a running Citrix daemon, 4300 a pid some other program got after a reboot.
    citrix = {4200}
    stale = module.stale_locks(str(tmpdir), running=lambda pid: pid in citrix)
    check(stale == [dead, reused], "dead and reused pids are stale, nothing else: %s" % stale)
    check(module.lock_pid(alive) == 4200, "the pid as Citrix writes it")
    check(module.lock_pid(str(tmpdir / ".selfserv.lock")) is None, "a file of another size is no lock")
    check(module.lock_pid(str(tmpdir / ".zero.lock")) is None, "pid 0 is none")
    check(module.stale_locks(str(pathlib.Path(tmp) / "missing")) == [], "no directory, no locks")

    # A fake /proc: one Citrix daemon, one other program, one without exe access.
    proc = pathlib.Path(tmp) / "proc"
    (proc / "4200").mkdir(parents=True)
    os.symlink(module.ICAROOT + "/ServiceRecord", proc / "4200" / "exe")
    (proc / "4300").mkdir()
    os.symlink("/usr/bin/bash", proc / "4300" / "exe")
    (proc / "4400").mkdir()
    (proc / "4400" / "cmdline").write_bytes(module.ICAROOT.encode() + b"/UtilDaemon\0")
    check(module.citrix_process(4200, str(proc)), "a daemon from Citrix's directory")
    check(not module.citrix_process(4300, str(proc)), "another program with the same pid")
    check(module.citrix_process(4400, str(proc)), "the command line when exe is not readable")
    check(not module.citrix_process(4100, str(proc)), "a pid that is gone")

    dest = pathlib.Path(tmp) / "state" / "citrix-stale-locks"
    (dest).mkdir(parents=True)
    (dest / ".UtilDaemon.lock").write_bytes(b"old!")
    moved = module.move_aside(stale, str(dest))
    check(moved == stale, "both moved: %s" % moved)
    check(sorted(p.name for p in dest.iterdir()) == [".CtxAuthManager.lock", ".UtilDaemon.lock"], "into the folder")
    check(module.lock_pid(str(dest / ".UtilDaemon.lock")) == 4300, "replacing the last login's copy")
    check(os.path.exists(alive) and not os.path.exists(dead), "the running daemon's lock stays")

    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = module.main(["--dir", str(tmpdir), "--dest", str(dest)])
    check(code == 0, "main runs")
    with contextlib.redirect_stderr(io.StringIO()):
        check(module.main(["--nonsense"]) == 2, "an unknown flag says how to call it")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED citrix_locks_test")
    sys.exit(1)
print("TESTS PASSED citrix_locks_test")
