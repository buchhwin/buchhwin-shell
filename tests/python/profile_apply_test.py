#!/usr/bin/env python3
"""Unit test for scripts/profile-apply.py with temporary directories only.

Never the real ~/.config: HOME, the XDG directories, the config, state and
profile directories are all below one temporary directory.
"""

import contextlib
import datetime
import importlib.util
import io
import json
import os
import pathlib
import stat
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("profile_apply", ROOT / "scripts" / "profile-apply.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def mode(path):
    return stat.S_IMODE(os.lstat(path).st_mode)


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        status = module.main(list(argv))
    lines = out.getvalue().strip().splitlines()
    check(len(lines) == 1, "one JSON line out, got %d" % len(lines))
    return status, json.loads(lines[-1]) if lines else {}


with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    home, data, system = base / "home", base / "data", base / "system"
    os.environ.update({"HOME": str(home), "XDG_CONFIG_HOME": str(base / "xdg-config"),
                       "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(system)})
    config = base / "config" / "buchhwin-shell"
    state = base / "state" / "buchhwin-shell"
    source = base / "profile"
    config.mkdir(parents=True)
    source.mkdir()
    (config / "settings.json").write_text('{"appearance": {"accent": "#123456"}}\n', encoding="utf-8")
    (config / "layout.json").write_text('{"configVersion": 3}\n', encoding="utf-8")
    (config.parent / "buchhwin-shell-xdg-terminals.list").write_text("kitty.desktop\n", encoding="utf-8")
    shipped = '{\n  "logo": { "type": "file", "source": "~/.config/buchhwin-shell/saturn.txt" }\n}\n'
    (source / "fastfetch.jsonc").write_text(shipped, encoding="utf-8")
    (source / "saturn.txt").write_text("  ( o )\n", encoding="utf-8")
    profile = {"configVersion": 1, "id": "test", "modes": {},
               "defaultApps": {"terminal": "Alacritty.desktop", "files": "org.kde.dolphin.desktop"},
               "fastfetch": {"config": "fastfetch.jsonc", "logo": "saturn.txt"}}
    (source / "profile.json").write_text(json.dumps(profile), encoding="utf-8")
    apps = system / "applications"
    apps.mkdir(parents=True)
    (apps / "Alacritty.desktop").write_text("[Desktop Entry]\nType=Application\nName=Alacritty\n"
                                            "Categories=System;TerminalEmulator;\n", encoding="utf-8")

    # ---- the backup's name -------------------------------------------------------
    # What earlier runs left: a backup directory 0755 with a 0644 copy in it,
    # beside other things in the state directory that are not backups.
    old = state / "backup-2026-10-14"
    old.mkdir(parents=True)
    (old / "settings.json").write_text("{}\n", encoding="utf-8")
    os.chmod(old, 0o755)
    os.chmod(old / "settings.json", 0o644)
    other = state / "round12"
    other.mkdir()
    os.chmod(other, 0o755)
    elsewhere = base / "elsewhere"
    elsewhere.mkdir()
    os.chmod(elsewhere, 0o755)
    (state / "backup-2026-10-13").symlink_to(elsewhere)
    # The live settings.json was 0644, whatever umask this test runs under.
    os.chmod(config / "settings.json", 0o644)
    morning = datetime.datetime(2026, 10, 15, 9, 30, 5)
    first, copied = module.backup(config, state, morning)
    check(first == state / "backup-2026-10-15", "the first backup of a day is named after the day: %s" % first)
    check(sorted(copied) == ["buchhwin-shell-xdg-terminals.list", "layout.json", "settings.json"],
          "settings, layout and the session's default-app list are copied: %r" % copied)
    check((first / "settings.json").read_text(encoding="utf-8") == '{"appearance": {"accent": "#123456"}}\n',
          "with their content")
    # settings.json holds the weather's place.
    check(mode(config / "settings.json") == 0o644, "the original keeps its own mode")
    check(mode(first) == 0o700, "a backup directory is the user's alone: %o" % mode(first))
    check(all(mode(first / name) == 0o600 for name in copied),
          "and so is every copy in it: %r" % {name: oct(mode(first / name)) for name in copied})
    check(mode(old) == 0o700, "an earlier run's backup directory is closed: %o" % mode(old))
    check(mode(other) == 0o755 and mode(elsewhere) == 0o755,
          "nothing else in the state directory is touched, and a link named like a backup is not followed")
    second, _ = module.backup(config, state, morning)
    check(second == state / "backup-2026-10-15-093005", "a second one that day gets the time: %s" % second)
    third, _ = module.backup(config, state, morning)
    check(third == state / "backup-2026-10-15-093005-2", "and a third in the same second a counter: %s" % third)
    check((first / "settings.json").is_file(), "an existing backup is never written into")
    empty = base / "empty"
    empty.mkdir()
    check(module.backup(empty, base / "nostate", morning) == (None, []) and not (base / "nostate").exists(),
          "nothing to back up creates nothing")

    # Another run takes the name between choosing it and making it: the
    # day's backup before a switch, started by the same switch.
    raced = base / "raced"
    choose = module.free_name
    taken = []

    def racing(name_base, day, time):
        candidate = choose(name_base, day, time)
        if not taken:
            candidate.mkdir(parents=True)
            taken.append(candidate)
        return candidate

    module.free_name = racing
    try:
        target, copied = module.backup(config, raced, morning)
    except OSError as error:
        target, copied = None, []
        check(False, "a name taken in between is not a failed backup: %s" % error)
    finally:
        module.free_name = choose
    check(target == raced / "backup-2026-10-15-093005" and len(copied) == 3,
          "a name taken in between: the next free one is used: %s" % target)
    check(taken == [raced / "backup-2026-10-15"] and not any(taken[0].iterdir()),
          "and the one the other run made is not written into")

    # ---- the cursor theme: set only when it is installed here --------------------
    themed = dict(profile, settings={"appearance": {"cursorTheme": "Example-Cursors", "accent": "#123456"}})
    check(module.cursor_theme(themed) == {"theme": "Example-Cursors", "installed": False},
          "a cursor theme that is nowhere is not installed")
    for where in (data / "icons", home / ".icons", system / "icons"):
        (where / "Example-Cursors" / "cursors").mkdir(parents=True)
        check(module.cursor_theme(themed) == {"theme": "Example-Cursors", "installed": True},
              "one under %s is" % where.relative_to(base))
        (where / "Example-Cursors" / "cursors").rmdir()
    (data / "icons" / "Example-Cursors" / "index.theme").write_text("[Icon Theme]\n", encoding="utf-8")
    check(module.cursor_theme(themed)["installed"] is False, "an icon theme without cursors is not a cursor theme")
    check(module.cursor_theme(dict(profile, settings={"appearance": {"cursorTheme": "../icons"}}))["installed"] is False,
          "a path is not a theme name")
    check(module.cursor_theme(profile) == {} and module.cursor_theme(dict(profile, settings={"appearance": {}})) == {},
          "a profile that names no cursor theme says nothing about one")

    # ---- fastfetch: a different file is kept, the same one left alone -------------
    target_config = base / "ff" / "buchhwin-shell"
    target_config.mkdir(parents=True)
    (target_config / "fastfetch.jsonc").write_text('{ "mine": true }\n', encoding="utf-8")
    result = module.install_fastfetch(profile, source, target_config, morning)
    check(sorted(result["written"]) == ["fastfetch.jsonc", "saturn.txt"], "both files written: %r" % result)
    check(result["backups"] == ["fastfetch.jsonc.backup-2026-10-15"], "the user's own config kept: %r" % result)
    check((target_config / "fastfetch.jsonc.backup-2026-10-15").read_text(encoding="utf-8") == '{ "mine": true }\n',
          "with what it said")
    installed = (target_config / "fastfetch.jsonc").read_text(encoding="utf-8")
    check('"source": "%s"' % (target_config / "saturn.txt") in installed,
          "a config directory outside ~/.config gets its own logo path: %r" % installed)
    check((target_config / "saturn.txt").read_text(encoding="utf-8") == "  ( o )\n", "the logo beside it")
    again = module.install_fastfetch(profile, source, target_config, morning)
    check(again == {"written": [], "backups": []}, "the same files again: nothing written, nothing kept: %r" % again)
    (target_config / "fastfetch.jsonc").write_text('{ "mine": true }\n', encoding="utf-8")
    once_more = module.install_fastfetch(profile, source, target_config, morning)
    check(once_more["backups"] == ["fastfetch.jsonc.backup-2026-10-15"], "the same old file is kept once a day, not twice")
    (target_config / "fastfetch.jsonc").write_text('{ "mine": 2 }\n', encoding="utf-8")
    later = module.install_fastfetch(profile, source, target_config, morning)
    check(later["backups"] == ["fastfetch.jsonc.backup-2026-10-15-093005"], "a different one that day gets the time: %r" % later)
    check((target_config / "fastfetch.jsonc.backup-2026-10-15").read_text(encoding="utf-8") == '{ "mine": true }\n',
          "without touching the first")
    under_home = home / ".config" / "buchhwin-shell"
    module.install_fastfetch(profile, source, under_home, morning)
    check('"source": "~/.config/buchhwin-shell/saturn.txt"' in (under_home / "fastfetch.jsonc").read_text(encoding="utf-8"),
          "under the home directory the shipped path stays as it is")
    try:
        module.install_fastfetch(dict(profile, fastfetch={"config": "../escape.jsonc"}), source, target_config, morning)
        check(False, "a path instead of a file name is refused")
    except ValueError:
        pass

    # ---- the whole run -----------------------------------------------------------
    status, answer = run("--from", str(source), "--config-dir", str(config), "--backup-dir", str(state))
    check(status == 0 and answer.get("ok") is True, "a run goes through: %r" % answer)
    check(answer.get("backup", "").startswith(str(state / "backup-")), "and says where the backup is")
    check(answer.get("apps") == {"terminal": "Alacritty.desktop"}, "only the installed default app is handed on: %r" % answer)
    check(answer.get("missing") == ["org.kde.dolphin.desktop"], "the missing one is named, not an error")
    check(answer.get("cursor") == {}, "a profile without a cursor theme answers with none: %r" % answer.get("cursor"))
    check((config / "fastfetch.jsonc").is_file() and (config / "saturn.txt").is_file(), "fastfetch's files are in place")
    check(not (base / "xdg-config").exists(), "nothing outside the directories it was given")

    status, answer = run("--from", str(source), "--config-dir", str(config))
    check(status == 1 and "backup" in answer.get("error", ""), "without a backup directory nothing is overwritten")

    broken = base / "broken"
    broken.mkdir()
    (broken / "profile.json").write_text(json.dumps(dict(profile, fastfetch={"config": "../x"})), encoding="utf-8")
    before = sorted(path.name for path in state.iterdir())
    status, answer = run("--from", str(broken), "--config-dir", str(config), "--backup-dir", str(state))
    check(status == 1 and answer.get("ok") is False, "a bad profile is an error")
    check(len(sorted(path.name for path in state.iterdir())) == len(before) + 1, "after the backup, which stays")

    status, answer = run("--from", str(base / "nowhere"), "--config-dir", str(config), "--backup-dir", str(state))
    check(status == 1 and "cannot read" in answer.get("error", ""), "a missing profile is an error before anything")

    # ---- the backup before the first profile switch of a day (--backup-stdin) -----
    daily = base / "daily-state"
    texts = {"settings.json": '{"appearance": {"accent": "#abcdef"}}\n', "layout.json": '{"configVersion": 3}\n',
             "../escape.json": "x", "fastfetch.jsonc": "x"}
    target, written, kept = module.daily_backup(texts, daily, morning)
    check(target == daily / "backup-2026-10-15" and written == ["layout.json", "settings.json"] and not kept,
          "the day's backup holds the two files: %r %r" % (target, written))
    check((target / "settings.json").read_text(encoding="utf-8") == texts["settings.json"], "as they were handed over")
    check(mode(target) == 0o700 and all(mode(target / name) == 0o600 for name in written),
          "the day's backup is the user's alone too")
    check(sorted(path.name for path in target.iterdir()) == ["layout.json", "settings.json"],
          "and nothing else: a name that is not one of the two is not a file to write")
    again, written, kept = module.daily_backup({"settings.json": "{}\n"}, daily, morning)
    check(again is None and written == [] and kept, "a second switch that day writes nothing")
    check((target / "settings.json").read_text(encoding="utf-8") == texts["settings.json"], "and the day's backup stays")
    nothing = module.daily_backup({"settings.json": "  ", "layout.json": 3}, base / "daily-none", morning)
    check(nothing == (None, [], False) and not (base / "daily-none").exists(), "empty texts create nothing")

    def run_stdin(text, *argv):
        out = io.StringIO()
        previous = sys.stdin
        sys.stdin = io.StringIO(text)
        try:
            with contextlib.redirect_stdout(out):
                status = module.main(list(argv))
        finally:
            sys.stdin = previous
        lines = out.getvalue().strip().splitlines()
        check(len(lines) == 1, "one JSON line out, got %d" % len(lines))
        return status, json.loads(lines[-1]) if lines else {}

    status, answer = run_stdin(json.dumps({"layout.json": "{}\n"}), "--backup-stdin", "--backup-dir", str(base / "daily-run"))
    check(status == 0 and answer.get("ok") is True and answer.get("backedUp") == ["layout.json"],
          "--backup-stdin backs up what it is given: %r" % answer)
    check(answer.get("backup", "").startswith(str(base / "daily-run" / "backup-")), "and says where")
    status, answer = run_stdin(json.dumps({"layout.json": "{}\n"}), "--backup-stdin", "--backup-dir", str(base / "daily-run"))
    check(status == 0 and answer.get("alreadyToday") is True and answer.get("backup") == "",
          "the same day again: kept as it is: %r" % answer)
    status, answer = run_stdin("not json", "--backup-stdin", "--backup-dir", str(base / "daily-bad"))
    check(status == 1 and answer.get("ok") is False and not (base / "daily-bad").exists(), "unreadable input is an error")
    status, answer = run_stdin("{}", "--backup-stdin")
    check(status == 1 and "backup directory" in answer.get("error", ""), "and so is no backup directory")
    status, answer = run("--config-dir", str(config))
    check(status == 1 and "--from" in answer.get("error", ""), "without --backup-stdin, --from is needed")

    # The shipped profile itself, as a dry run: it only says what is installed.
    status, answer = run("--from", str(ROOT / "config" / "builtin-profiles" / "buchhwin"),
                         "--config-dir", str(base / "untouched"), "--dry-run")
    check(status == 0 and answer.get("apps") == {"terminal": "Alacritty.desktop"}, "the shipped profile reads: %r" % answer)
    check(answer.get("cursor") == {"theme": "macOS", "installed": False},
          "and says its cursor theme is not installed in the sandbox: %r" % answer.get("cursor"))
    check(not (base / "untouched").exists(), "and a dry run writes nothing")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED profile_apply_test")
    sys.exit(1)
print("TESTS PASSED profile_apply_test")
