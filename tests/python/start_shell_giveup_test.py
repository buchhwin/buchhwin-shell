#!/usr/bin/env python3
"""scripts/start-shell.sh when it gives up, and the start after that.

Five crashes in a minute used to end in a log line only. Now the compositor
draws a notice (`hyprctl notify`, naming the key that starts the shell again,
moved or not), and a fallback swayidle keeps the lock before sleep and the
idle lock until a shell is back; the next start ends it and takes the notice
off the screen. All of it on stand-ins in a sandbox: a quickshell that
crashes (exit 139, no real coredump - pitfall 58), a hyprctl that records, a
swayidle that records and waits, a compositor socket and a display socket of
the sandbox's own. Nothing here reaches the session that runs the test.
"""

import json
import os
import pathlib
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "start-shell.sh"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


def unix_socket(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    holder = socket.socket(socket.AF_UNIX)
    holder.bind(str(path))
    return holder


def alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    # A zombie is gone for this purpose.
    try:
        return pathlib.Path("/proc/%d/status" % pid).read_text().find("State:\tZ") < 0
    except OSError:
        return False


with tempfile.TemporaryDirectory(prefix="buchhwin-giveup.") as base:
    sb = pathlib.Path(base).resolve()
    bin_dir, run_dir, cfg = sb / "bin", sb / "run", sb / "cfg"
    config_home, state_home = sb / "config", sb / "state"
    write(cfg / "shell.qml", "")
    # The configuration's own lock command, as IdleService names it.
    write(cfg / "scripts" / "session-action.sh", "#!/bin/sh\nexit 0\n", 0o755)
    sockets = [unix_socket(run_dir / "hypr" / "sig-test" / ".socket.sock"), unix_socket(run_dir / "wayland-giveup")]
    write(run_dir / "hypr" / "sig-test" / "hyprland.lock", "1\nwayland-giveup\n")
    write(config_home / "buchhwin-shell" / "shortcut-keys.txt", "SUPER + B = SUPER + W\nSUPER + CTRL + R = SUPER + ALT + R\n")
    settings = config_home / "buchhwin-shell" / "settings.json"
    write(settings, json.dumps({"power": {"lockBeforeSleep": True, "battery": {"lockMinutes": 5},
                                          "ac": {"lockMinutes": 0}}}))
    # quickshell: never listed, and every start counted; CRASH=1 crashes, else a clean exit.
    write(bin_dir / "quickshell", """#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$COUNT"
[[ ${CRASH:-0} == 1 ]] && exit 139
exit 0
""", 0o755)
    write(bin_dir / "hyprctl", '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$HYPRCTL_LOG"\nexit 0\n', 0o755)
    # Its first word swayidle, its arguments those it was given - what
    # start-shell.sh checks before it ends one. The sleep goes with it (a lone
    # `sleep` after -c would be exec'ed and take the command line with it).
    write(bin_dir / "swayidle", """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$SWAYIDLE_LOG"
exec -a swayidle bash -c 'sleep 30 & trap "kill $!; exit 0" TERM; wait' "$@"
""", 0o755)
    for name in ("pgrep", "pkill"):
        write(bin_dir / name, "#!/bin/sh\nexit 1\n", 0o755)
    write(bin_dir / "busctl", "#!/bin/sh\nprintf 'NAME PID PROCESS USER CONNECTION UNIT SESSION DESCRIPTION\\n'\n", 0o755)
    write(bin_dir / "systemctl", "#!/bin/sh\nexit 0\n", 0o755)

    count, hyprctl_log, swayidle_log = sb / "count", sb / "hyprctl.log", sb / "swayidle.log"
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("HYPRLAND_", "BUCHHWIN_", "MALLOC_", "QS_", "XDG_"))}
    environment.update(PATH="%s:%s" % (bin_dir, os.environ.get("PATH", "/usr/bin:/bin")),
                       XDG_RUNTIME_DIR=str(run_dir), XDG_CONFIG_HOME=str(config_home), XDG_STATE_HOME=str(state_home),
                       XDG_CACHE_HOME=str(sb / "cache"), WAYLAND_DISPLAY="wayland-giveup",
                       HYPRLAND_INSTANCE_SIGNATURE="sig-test", HOME=str(sb), COUNT=str(count),
                       HYPRCTL_LOG=str(hyprctl_log), SWAYIDLE_LOG=str(swayidle_log),
                       BUCHHWIN_RESTART_PAUSE="0.05", BUCHHWIN_REAP_STEPS="10")
    fallback = run_dir / "buchhwin-shell" / "fallback-idle.sig-test"
    log = state_home / "buchhwin-shell" / "quickshell.log"
    started = []

    def start(**extra):
        count.write_text("0")
        env = dict(environment, **extra)
        done = subprocess.run(["bash", str(SCRIPT), str(cfg)], env=env, stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        return done.returncode

    def read(path):
        try:
            return path.read_text()
        except OSError:
            return ""

    try:
        # ---- five crashes in a minute ---------------------------------------------
        status = start(CRASH="1")
        check(read(count).strip() == "6", "gives up after five restarts (got %s runs)" % read(count).strip())
        check(status == 139, "and ends with the crash's status (got %d)" % status)
        notices = [line for line in read(hyprctl_log).splitlines() if line.startswith("notify ")]
        check(notices == ["notify 0 1800000 0 buchhwin-shell stopped after 5 crashes in a minute - Super+Alt+R starts it again"],
              "the compositor shows the notice, with the key Settings > Shortcuts moved it to (%s)" % notices)
        lock = "'%s/scripts/session-action.sh' lock" % cfg
        check(read(swayidle_log).strip() == "-w before-sleep %s timeout 300 %s" % (lock, lock),
              "the fallback locks before sleep and after the shorter lock timeout (%s)" % read(swayidle_log).strip())
        pid = int(read(fallback).strip() or 0)
        if pid:
            started.append(pid)
        check(pid > 0 and alive(pid), "the fallback is running and written down (pid %s)" % pid)
        check("started a fallback lock" in read(log) and "not restarting it again" in read(log), "and the log says both")

        # ---- the next start takes it back ------------------------------------------
        hyprctl_log.write_text("")
        start()
        check(read(count).strip() == "1", "the next start starts the shell (got %s runs)" % read(count).strip())
        deadline = time.monotonic() + 5
        while pid and alive(pid) and time.monotonic() < deadline:
            time.sleep(0.05)
        check(pid > 0 and not alive(pid), "and ends the fallback")
        check(not fallback.exists(), "and forgets it")
        check("dismissnotify" in read(hyprctl_log).splitlines(), "and takes the notice off the screen (%s)" % read(hyprctl_log))
        check("ended the fallback lock" in read(log), "and the log says so")

        # ---- a pid that is not the fallback is left alone --------------------------
        stranger = subprocess.Popen(["sleep", "30"])
        started.append(stranger.pid)
        write(fallback, "%d\n" % stranger.pid)
        start()
        check(stranger.poll() is None, "a pid that is not this configuration's swayidle is never ended")
        check(not fallback.exists(), "but the stale file goes")

        # ---- nothing to lock, or a nested session: no fallback ----------------------
        swayidle_log.write_text("")
        write(settings, json.dumps({"power": {"lockBeforeSleep": False, "battery": {"lockMinutes": 0},
                                              "ac": {"lockMinutes": 0}}}))
        start(CRASH="1")
        check(read(swayidle_log) == "" and not fallback.exists(), "no lock before sleep and no timeout: no fallback")
        write(settings, json.dumps({"power": {"lockBeforeSleep": True}}))
        start(CRASH="1", BUCHHWIN_NESTED="1")
        check(read(swayidle_log) == "", "a nested session gets no fallback (%s)" % read(swayidle_log))
        notices = [line for line in read(hyprctl_log).splitlines() if line.startswith("notify ")]
        check(len(notices) == 2, "but the notice all the same (%s)" % notices)
        write(settings, json.dumps({"power": {"lockBeforeSleep": True}}))
        swayidle_log.write_text("")
        start(CRASH="1")
        check(read(swayidle_log).strip() == "-w before-sleep %s" % lock, "lock before sleep only (%s)" % read(swayidle_log).strip())
        pid = int(read(fallback).strip() or 0)
        if pid:
            started.append(pid)
        # The default key when none was moved.
        (config_home / "buchhwin-shell" / "shortcut-keys.txt").unlink()
        hyprctl_log.write_text("")
        start()
        start(CRASH="1")
        check("Super+Ctrl+R starts it again" in read(hyprctl_log), "the default key otherwise (%s)" % read(hyprctl_log))
        pid = int(read(fallback).strip() or 0)
        if pid:
            started.append(pid)
    finally:
        for pid in started:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        if "stranger" in globals():
            stranger.wait(timeout=5)
        for holder in sockets:
            holder.close()

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED start_shell_giveup_test")
    sys.exit(1)
print("TESTS PASSED start_shell_giveup_test")
