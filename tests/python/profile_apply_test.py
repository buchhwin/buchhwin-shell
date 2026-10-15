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
    morning = datetime.datetime(2026, 10, 15, 9, 30, 5)
    first, copied = module.backup(config, state, morning)
    check(first == state / "backup-2026-10-15", "the first backup of a day is named after the day: %s" % first)
    check(sorted(copied) == ["buchhwin-shell-xdg-terminals.list", "layout.json", "settings.json"],
          "settings, layout and the session's default-app list are copied: %r" % copied)
    check((first / "settings.json").read_text(encoding="utf-8") == '{"appearance": {"accent": "#123456"}}\n',
          "with their content")
    second, _ = module.backup(config, state, morning)
    check(second == state / "backup-2026-10-15-093005", "a second one that day gets the time: %s" % second)
    third, _ = module.backup(config, state, morning)
    check(third == state / "backup-2026-10-15-093005-2", "and a third in the same second a counter: %s" % third)
    check((first / "settings.json").is_file(), "an existing backup is never written into")
    empty = base / "empty"
    empty.mkdir()
    check(module.backup(empty, base / "nostate", morning) == (None, []) and not (base / "nostate").exists(),
          "nothing to back up creates nothing")

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

    # The shipped profile itself, as a dry run: it only says what is installed.
    status, answer = run("--from", str(ROOT / "config" / "builtin-profiles" / "buchhwin"),
                         "--config-dir", str(base / "untouched"), "--dry-run")
    check(status == 0 and answer.get("apps") == {"terminal": "Alacritty.desktop"}, "the shipped profile reads: %r" % answer)
    check(not (base / "untouched").exists(), "and a dry run writes nothing")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED profile_apply_test")
    sys.exit(1)
print("TESTS PASSED profile_apply_test")
