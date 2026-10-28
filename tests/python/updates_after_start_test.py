#!/usr/bin/env python3
"""scripts/updates-after-start.py: what the first start after an update says.

The pure parts (versions, the record, the log's problems, the notices) on
their own, then the script as start-shell.sh runs it - in --dry-run, which
prints each decision instead of notifying - against stand-in quickshell and
hyprctl on PATH and a throwaway git checkout. Nothing reaches the session's
notification server, compositor or shell.
"""

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "updates-after-start.py"
spec = importlib.util.spec_from_file_location("after_start", SCRIPT)
after = importlib.util.module_from_spec(spec)
spec.loader.exec_module(after)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


# ---- the pure parts --------------------------------------------------------------
check(after.parse_version("Quickshell 0.3.2 (revision , distributed by Arch Linux)") == "0.3.2", "Quickshell's version")
check(after.parse_version("") == "", "no version")
check(after.hyprland_version('{"version": "0.56.2", "tag": "v0.56.2"}') == "0.56.2", "Hyprland's from hyprctl -j")
check(after.hyprland_version('{"tag": "v0.41.2"}') == "0.41.2", "an older one's tag")
check(after.hyprland_version("", "Hyprland 0.56.2 built from branch v0.56.2 at commit x") == "0.56.2", "or Hyprland --version")
check(after.read_state('{"version": 1, "quickshell": "0.3.2", "hyprland": "0.56.2", "head": "abc1234", "x": 1}')
      == {"quickshell": "0.3.2", "hyprland": "0.56.2", "qt": "", "head": "abc1234"}, "the record")
check(after.read_state('{"version": 1, "qt": "6.12.0"}')["qt"] == "6.12.0", "with the Qt the shell ran on")
# Qt: a minor upgrade keeps Quickshell's version string, so it is a part of its own
maps = "7f00-7f01 r--p 00000000 00:1f 123 /usr/lib/libQt6Core.so.6.12.0\n"
check(after.qt_version(maps) == "6.12.0", "Qt from the running shell's maps")
with tempfile.TemporaryDirectory() as raw:
    link = pathlib.Path(raw) / "libQt6Core.so.6"
    link.symlink_to("libQt6Core.so.6.13.1")
    check(after.qt_version("", [str(link)]) == "6.13.1", "else from where the library's symlink points")
    check(after.qt_version(maps, [str(link)]) == "6.12.0", "the running shell's first")
check(after.qt_version("", []) == "", "unknown without either")
check(after.changes({"quickshell": "0.3.2", "qt": "6.12.0"}, {"quickshell": "0.3.2", "qt": "6.13.0"})
      == ["Qt 6.12.0 → 6.13.0"], "a Qt upgrade under the same Quickshell is a change")
check(after.read_state("{broken") is None and after.read_state('{"version": 2}') is None, "no record")
check(after.settings_of('{"updates": {"coreCheck": "always", "whatsNew": true}}') == ("always", True), "both settings")
check(after.settings_of('{"updates": {"coreCheck": "loud", "whatsNew": "yes"}}') == ("problems", False), "the defaults for anything else")
check(after.settings_of("") == ("problems", False), "and without a file")
check(after.changes({"quickshell": "0.3.2", "hyprland": "0.56.2"}, {"quickshell": "0.3.3", "hyprland": "0.56.2"})
      == ["Quickshell 0.3.2 → 0.3.3"], "what changed")
check(after.changes({"quickshell": "", "hyprland": "0.56.2"}, {"quickshell": "0.3.3", "hyprland": "0.57.0"})
      == ["Hyprland 0.56.2 → 0.57.0"], "an unknown version is no change")
log = "\n".join(["\x1b[31m  WARN: QSettings::value: Empty key passed\x1b[0m", "  INFO: Configuration Loaded",
                 "  WARN qml: @shell/bar/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null",
                 " ERROR: Failed to load configuration", "  WARN: Binding loop detected for property \"width\"",
                 "  WARN: Could not register notification server", "2026-10-19T10:00:00+02:00 start-shell: the shell died on signal 11"])
found = after.problems(log)
check(len(found) == 4 and found[0].startswith("WARN qml: @shell/bar/Bar.qml") and "died on signal" in found[3],
      "the log's problems, the known ones left out (%s)" % found)
check(after.problems("2026-10-28T10:00:00+01:00 start-shell: the shell could not start (status 255) - not restarting it")
      != [], "a shell that could not start is a problem")
check(after.compositor_line("T", "/home/u/.local/state/buchhwin-shell/quickshell.log", "/home/u")
      == "T - see ~/.local/state/buchhwin-shell/quickshell.log", "the compositor's line, the log under ~")
check(after.compositor_line("T", "/srv/quickshell.log", "/home/u") == "T - see /srv/quickshell.log"
      and after.compositor_line("T", "/home/user2/q.log", "/home/u") == "T - see /home/user2/q.log", "elsewhere as it is")
check(after.count_targets("target bar\n  function x\ntarget notch\n") == 2, "IPC targets")
changed = ["Quickshell 0.3.2 → 0.3.3"]
check(after.core_notice(changed, [], 40, "problems") is None, "clean and 'problems': nothing to say")
clean = after.core_notice(changed, [], 40, "always")
check(clean == ("Quickshell 0.3.2 → 0.3.3: the shell started cleanly",
                "No errors in its log during the first minute, and it answers on 40 IPC targets.", False), "clean and 'always' (%s,)" % (clean,))
bad = after.core_notice(changed, ["TypeError: x", "ERROR: y", "a" * 200, "fourth"], 0, "problems")
check(bad[0] == "Quickshell 0.3.2 → 0.3.3: the shell found 5 problems" and bad[2] is True, "problems, IPC silence counted (%s)" % (bad,))
check(bad[1].count("\n") == 3 and "a" * 117 + "…" in bad[1], "three lines shown, cut to length")
check(after.core_notice(changed, ["x"], 4, "off") is None and after.core_notice([], ["x"], 4, "always") is None, "off, or nothing changed")
notice = after.whats_new_notice(["One", "Two"], 2)
check(notice == ("buchhwin-shell updated: 2 changes", "· One\n· Two"), "what is new (%s,)" % (notice,))
many = after.whats_new_notice(["S%d" % n for n in range(10)], 14)
check(many[0] == "buchhwin-shell updated: 14 changes" and many[1].endswith("… and 4 more in Settings > About"), "ten shown of more")
check(after.whats_new_notice([], 0) is None, "nothing without a subject")

# ---- the script, dry, on stand-ins ---------------------------------------------------
with tempfile.TemporaryDirectory(prefix="buchhwin-afterstart.") as raw:
    base = pathlib.Path(raw)
    bin_dir, state, config, shell = base / "bin", base / "state", base / "config", base / "shell"
    for directory in (bin_dir, state, config, shell):
        directory.mkdir()
    (bin_dir / "quickshell").write_text("""#!/bin/sh
case "$1" in
  --version) printf 'Quickshell %s (revision , distributed by a test)\\n' "$QS_VERSION" ;;
  ipc) [ "$TARGETS" = 0 ] || printf 'target bar\\ntarget notch\\n' ;;
esac
""")
    (bin_dir / "hyprctl").write_text('#!/bin/sh\n[ "$1" = version ] && printf \'{"version": "%s"}\\n\' "$HYPR_VERSION"\n'
                                     '[ "$1" = notify ] && printf \'%s\\n\' "$*" >> "$SENT"\nexit 0\n')
    # Outside --dry-run: no notification server (the shell is down), and
    # notify-send only writes down that it was asked.
    (bin_dir / "busctl").write_text("#!/bin/sh\necho 'b false'\n")
    (bin_dir / "notify-send").write_text('#!/bin/sh\nprintf \'notify-send %s\\n\' "$*" >> "$SENT"\n')
    for name in ("quickshell", "hyprctl", "busctl", "notify-send"):
        (bin_dir / name).chmod(0o755)
    sent = base / "sent.log"
    git = ["git", "-C", str(shell), "-c", "user.name=Test", "-c", "user.email=test@example.invalid"]
    subprocess.run(["git", "init", "-q", str(shell)], check=True)

    def commit(subject):
        (shell / "file.txt").write_text(subject)
        subprocess.run(git + ["add", "file.txt"], check=True)
        subprocess.run(git + ["commit", "-q", "-m", subject], check=True)

    commit("The first change")
    log_file = base / "quickshell.log"
    log_file.write_text("  INFO: Configuration Loaded\n")
    settings = config / "settings.json"

    def run(qs="0.3.2", hypr="0.56.2", targets="2", pid=None, dry=True, signature=None):
        env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ.get("PATH", "")), QS_VERSION=qs, HYPR_VERSION=hypr,
                   TARGETS=targets, SENT=str(sent), HOME=str(base))
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        if signature:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = signature
        args = [sys.executable, str(SCRIPT), "--shell-dir", str(shell), "--log", str(log_file), "--state-dir", str(state),
                "--config-dir", str(config), "--settle", "0", "--server-wait", "0"] + (["--dry-run"] if dry else [])
        if pid is not None:
            args += ["--pid", str(pid)]
        done = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
        lines = [json.loads(line) for line in done.stdout.splitlines() if line.startswith("{")]
        return done.returncode, lines

    def record():
        return json.loads((state / "versions.json").read_text())

    code, said = run()
    check(code == 0 and [item["kind"] for item in said] == ["recorded"], "the first run only records (%s)" % said)
    head = record()["head"]
    # Qt is this machine's (no shell process to read here): only its key is known
    qt = record().get("qt")
    check(record() == {"version": 1, "quickshell": "0.3.2", "hyprland": "0.56.2", "qt": qt, "head": head}
          and len(head) == 7 and isinstance(qt, str), "the record")
    check([item["kind"] for item in run()[1]] == ["unchanged"], "the same versions: nothing")

    # A core update, a clean minute: quiet by default, recorded.
    said = run(qs="0.3.3")[1]
    check([item["kind"] for item in said] == ["clean"] and record()["quickshell"] == "0.3.3", "clean after a core update (%s)" % said)
    # 'always' says so.
    settings.write_text(json.dumps({"updates": {"coreCheck": "always"}}))
    said = run(hypr="0.57.0", qs="0.3.3")[1]
    check(said and said[-1]["kind"] == "core" and said[-1]["title"] == "Hyprland 0.56.2 → 0.57.0: the shell started cleanly",
          "always: the clean start is told (%s)" % said)
    # Problems in the log, and a shell that does not answer.
    settings.write_text(json.dumps({"updates": {"coreCheck": "problems"}}))
    log_file.write_text("  WARN qml: TypeError: Cannot read property 'x' of null\n")
    said = run(qs="0.3.4", hypr="0.57.0", targets="0")[1]
    check(said and said[-1]["kind"] == "core" and said[-1]["problems"] == 1 and said[-1]["targets"] == 0
          and said[-1]["title"] == "Quickshell 0.3.3 → 0.3.4: the shell found 2 problems", "problems are told (%s)" % said)
    # Stopped within the minute (not a crash): the next start checks again.
    log_file.write_text("  INFO: Configuration Loaded\n")
    gone = subprocess.Popen(["true"])
    gone.wait()
    said = run(qs="0.3.5", hypr="0.57.0", pid=gone.pid)[1]
    check([item["kind"] for item in said] == ["stopped"] and record()["quickshell"] == "0.3.4", "a stopped shell leaves the check to the next start (%s)" % said)
    log_file.write_text("start-shell: the shell died on signal 11, restarting (1 of 5)\n")
    said = run(qs="0.3.5", hypr="0.57.0", pid=gone.pid)[1]
    check(said and said[-1]["kind"] == "core" and record()["quickshell"] == "0.3.5", "but a crash is a problem (%s)" % said)
    # A shell that could not start (the configuration did not load, and
    # start-shell.sh said so) is no stop either: told, and taken as seen.
    log_file.write_text("  ERROR: Failed to load configuration\n"
                        "2026-10-28T10:00:00+01:00 start-shell: the shell could not start (status 255) - not restarting it\n")
    said = run(qs="0.3.5", hypr="0.57.1", pid=gone.pid)[1]
    check(said and said[-1]["kind"] == "core" and said[-1]["problems"] == 2 and record()["hyprland"] == "0.57.1",
          "a failed start is told, not taken for a stop (%s)" % said)
    # Without the shell there is no notification server: the compositor shows it.
    said = run(qs="0.3.5", hypr="0.57.2", pid=gone.pid, dry=False, signature="sig-test")[1]
    line = "Hyprland 0.57.1 → 0.57.2: the shell found 2 problems - see ~/quickshell.log"
    check(sent.read_text().splitlines() == ["notify 0 600000 0 " + line] and said and said[-1] == {"kind": "compositor", "text": line},
          "no server: the problems go to the compositor, once (%s, %s)" % (sent.read_text(), said))
    sent.write_text("")
    said = run(qs="0.3.5", hypr="0.57.3", pid=gone.pid, dry=False)[1]
    check(sent.read_text() == "" and not any(item["kind"] == "compositor" for item in said),
          "and nothing without a compositor (%s, %s)" % (sent.read_text(), said))
    # Off: recorded, nothing said.
    settings.write_text(json.dumps({"updates": {"coreCheck": "off"}}))
    said = run(qs="0.3.6", hypr="0.57.0")[1]
    check([item["kind"] for item in said] == ["checkOff"] and record()["quickshell"] == "0.3.6", "off (%s)" % said)

    # The checkout moved: told only with whatsNew on.
    commit("Do Not Disturb ends with the mode")
    commit("Workspaces that stay until closed")
    said = run(qs="0.3.6", hypr="0.57.0")[1]
    check([item["kind"] for item in said] == ["unchanged"] and record()["head"] != head, "off by default, the head recorded (%s)" % said)
    commit("A third change")
    settings.write_text(json.dumps({"updates": {"whatsNew": True}}))
    said = run(qs="0.3.6", hypr="0.57.0")[1]
    check(said and said[0]["kind"] == "whatsNew" and said[0]["title"] == "buchhwin-shell updated: 1 change"
          and said[0]["body"] == "· A third change", "what is new since the last start (%s)" % said)
    # A head the checkout does not have (history rewritten): nothing to list.
    data = record()
    data["head"] = "0000000"
    (state / "versions.json").write_text(json.dumps(data))
    said = run(qs="0.3.6", hypr="0.57.0")[1]
    check([item["kind"] for item in said] == ["unchanged"], "an unknown head lists nothing (%s)" % said)

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED updates_after_start_test")
    sys.exit(1)
print("TESTS PASSED updates_after_start_test")
