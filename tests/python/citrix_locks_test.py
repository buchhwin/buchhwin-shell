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

# --before-start: a fake /proc of the user's processes and a fake systemctl.
# Nothing here asks the machine's systemd or looks at its Citrix.
WS = "app.slice/app-buchhwin-citrix\\x2dworkspace-%d.scope"
DESK = "app.slice/app-buchhwin-Citrix_subscribed_Desk-%d.scope"


def process(proc, pid, exe, unit, deleted=False):
    path = proc / str(pid)
    path.mkdir(parents=True)
    os.symlink(exe + (" (deleted)" if deleted else ""), path / "exe")
    (path / "cgroup").write_text("0::/user.slice/user-1000.slice/user@1000.service/%s\n" % unit)


def daemons(proc):
    """Two Workspace starts' daemons, a subscribed desktop's, one in a terminal's
    scope, and one in a Workspace scope that also holds a browser."""
    process(proc, 5100, module.ICAROOT + "/AuthManagerDaemon", WS % 5000)
    process(proc, 5101, module.ICAROOT + "/icasessionmgr", WS % 5000, deleted=True)
    process(proc, 5200, module.ICAROOT + "/ServiceRecord", DESK % 5199)
    process(proc, 5300, module.ICAROOT + "/UtilDaemon", "app.slice/app-buchhwin-Alacritty-5299.scope")
    process(proc, 5400, module.ICAROOT + "/UtilDaemon", WS % 5390)
    process(proc, 5401, "/usr/bin/brave", WS % 5390)
    process(proc, 5500, "/usr/bin/bash", "app.slice/app-buchhwin-Alacritty-5299.scope")


class Systemctl:
    """Records its calls; a stop ends the scopes' processes in the fake /proc
    unless `hang`, which runs into the timeout instead."""

    def __init__(self, proc, hang=False):
        self.proc, self.hang, self.calls = proc, hang, []

    def __call__(self, args, timeout):
        self.calls.append((args, timeout))
        if self.hang and args[0] == "stop":
            raise module.subprocess.TimeoutExpired(["systemctl"] + args, timeout)
        units = args[args.index("--") + 1 :]
        for pid in list(self.proc.iterdir()):
            if module.unit_of(pid.name, str(self.proc)) in units:
                for name in pid.iterdir():
                    name.unlink()
                pid.rmdir()


with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    proc, locks, dest = tmp / "proc", tmp / ".tmp", tmp / "state"
    locks.mkdir()
    daemons(proc)
    old = lock(locks, ".CtxAuthManager.lock", 5100)
    kept = lock(locks, ".UtilDaemon.lock", 5400)
    check(module.unit_of(5100, str(proc)) == "app-buchhwin-citrix\\x2dworkspace-5000.scope", "the unit from the cgroup's path")
    check(module.program(5101, str(proc)) == module.ICAROOT + "/icasessionmgr", "a program an update replaced is still Citrix's")
    check(module.processes(str(proc), uid=os.getuid() + 1) == [], "another user's processes are not looked at")

    # A running Workspace, session or session start: nothing is stopped or moved.
    for pid, name in ((5600, "selfservice"), (5601, "wfica"), (5602, "storebrowse")):
        process(proc, pid, module.ICAROOT + "/" + name, "app.slice/app-buchhwin-other-1.scope")
        systemctl = Systemctl(proc)
        with contextlib.redirect_stderr(io.StringIO()):
            lines = module.before_start(str(locks), str(dest), str(proc), systemctl)
        check(lines == [] and systemctl.calls == [] and os.path.exists(old), "%s runs: nothing is touched (%s)" % (name, systemctl.calls))
        for path in (proc / str(pid)).iterdir():
            path.unlink()
        (proc / str(pid)).rmdir()

    systemctl = Systemctl(proc)
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        lines = module.before_start(str(locks), str(dest), str(proc), systemctl)
    stopped = ["app-buchhwin-Citrix_subscribed_Desk-5199.scope", "app-buchhwin-citrix\\x2dworkspace-5000.scope"]
    check(systemctl.calls == [(["stop", "--"] + stopped, module.STOP_SECONDS)],
          "exactly the Citrix scopes with nothing but Citrix in them, with a timeout: %s" % systemctl.calls)
    check("app-buchhwin-citrix\\x2dworkspace-5390.scope stays" in err.getvalue(), "a scope with a browser in it stays, and says so")
    check(lines == ["stopped: " + unit for unit in stopped] + ["moved aside: .CtxAuthManager.lock"], "what it prints: %s" % lines)
    check(not os.path.exists(old) and os.path.exists(kept), "the stopped daemon's lock goes, the running one's stays")
    check((proc / "5300").exists() and (proc / "5500").exists(), "the terminal and its Citrix program go on")

with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    proc = tmp / "proc"
    daemons(proc)
    systemctl = Systemctl(proc, hang=True)
    with contextlib.redirect_stderr(io.StringIO()):
        module.before_start(str(tmp / ".tmp"), str(tmp / "state"), str(proc), systemctl)
    check([args[0] for args, _ in systemctl.calls] == ["stop", "kill"] and systemctl.calls[1][0][1] == "--signal=SIGKILL",
          "a stop that runs into its timeout is followed by SIGKILL: %s" % systemctl.calls)

    def missing(args, timeout):
        raise FileNotFoundError("systemctl")

    daemons(tmp / "proc2")
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        module.before_start(str(tmp / ".tmp"), str(tmp / "state"), str(tmp / "proc2"), missing)
    check("not stopped" in err.getvalue(), "no systemctl: said so, and the start goes on")

    # main hands --before-start its directories.
    seen = []
    real, module.before_start = module.before_start, lambda directory, dest: seen.append((directory, dest)) or ["x"]
    with contextlib.redirect_stdout(io.StringIO()):
        code = module.main(["--before-start", "--dir", "/d", "--dest", "/s"])
    module.before_start = real
    check(code == 0 and seen == [("/d", "/s")], "main runs --before-start: %s" % seen)

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED citrix_locks_test")
    sys.exit(1)
print("TESTS PASSED citrix_locks_test")
