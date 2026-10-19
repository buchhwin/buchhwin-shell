#!/usr/bin/env python3
"""scripts/snapshot.py in a sandbox: what a snapshot holds, the daily one,
Restore, Export, Inspect and Import, the copies it keeps, and archives it
refuses. Invented settings only; nothing of this machine's setup is read."""

import datetime
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "snapshot.py"
spec = importlib.util.spec_from_file_location("snapshot", SCRIPT)
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def cli(base, *args, stdin=""):
    done = subprocess.run([sys.executable, str(SCRIPT)] + list(args)
                          + ["--config-dir", str(base / "config" / "buchhwin-shell"), "--state-dir", str(base / "state")],
                          input=stdin, capture_output=True, text=True, timeout=60)
    try:
        answer = json.loads(done.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        answer = {"raw": done.stdout + done.stderr}
    return done.returncode, answer


def setup(base):
    config = base / "config" / "buchhwin-shell"
    config.mkdir(parents=True)
    (base / "state").mkdir()
    (config / "settings.json").write_text('{"appearance": {"theme": "dark"}}\n')
    (config / "layout.json").write_text('{"configVersion": 3}\n')
    (config / "wallpapers.json").write_text('{"favourites": []}\n')
    (config / "shortcut-keys.txt").write_text("SUPER + B = SUPER + W\n")
    (config / "fastfetch.jsonc").write_text("{}\n")
    # What a snapshot leaves out: backups, a broken copy, a migration's copy,
    # a temporary file, a link and anything too big.
    (config / "fastfetch.jsonc.backup-2026-10-15").write_text("old\n")
    (config / "settings.json.bad").write_text("{broken\n")
    (config / "layout.v1.backup.json").write_text("{}\n")
    (config / ".settings.json.Ab12Cd").write_text("{}\n")
    (config / "shell.zsh").symlink_to(base / "elsewhere.zsh")
    (config / "huge.json").write_bytes(b"x" * (snapshot.MAX_FILE + 1))
    (base / "config" / "buchhwin-shell-mimeapps.list").write_text("[Default Applications]\n")
    (base / "state" / "state.json").write_text(json.dumps({"dnd": {"mode": "off", "until": 0}, "appRules": {"Teams": "muted"}}))
    return config


with tempfile.TemporaryDirectory(prefix="buchhwin-snapshot.") as raw:
    base = pathlib.Path(raw)
    config = setup(base)
    state = base / "state"

    # ---- what it holds ------------------------------------------------------------
    files = snapshot.collect(config, state)
    check(sorted(files) == ["config/fastfetch.jsonc", "config/layout.json", "config/settings.json",
                            "config/shortcut-keys.txt", "config/wallpapers.json",
                            "state/state.json", "xdg/buchhwin-shell-mimeapps.list"],
          "the setup, without backups, temporary files, links or a file too large (%s)" % sorted(files))
    over = snapshot.collect(config, state, {"settings.json": '{"from": "the shell"}', "kitty.conf": "no"})
    check(over["config/settings.json"] == b'{"from": "the shell"}' and "config/kitty.conf" not in over,
          "the shell's own copies replace settings.json and layout.json only")
    check(snapshot.digest(files) == snapshot.digest(dict(files)) and snapshot.digest(files) != snapshot.digest(over),
          "the hash follows the content")

    # ---- the daily snapshot ---------------------------------------------------------
    code, answer = cli(base, "daily", "--stdin", stdin=json.dumps({"settings.json": '{"held": "before the write"}\n'}))
    today = "daily-" + datetime.date.today().isoformat() + ".tar.gz"
    check(code == 0 and answer.get("name") == today, "the day's snapshot (%s)" % answer)
    directory = state / "snapshots"
    check(directory.is_dir() and (directory.stat().st_mode & 0o777) == 0o700, "in a folder of the user's alone")
    check(((directory / today).stat().st_mode & 0o777) == 0o600, "and the file too")
    meta, held = snapshot.read_archive(directory / today)
    check(held.get("config/settings.json") == b'{"held": "before the write"}\n', "settings.json as the shell held it")
    check(held.get("config/layout.json") == b'{"configVersion": 3}\n', "layout.json from disk without a copy on stdin")
    check(meta["kind"] == "daily" and len(meta["files"]) == 7, "with its manifest (%s)" % meta.get("files"))
    code, answer = cli(base, "daily")
    check(code == 0 and answer.get("skipped") == "today", "once a day (%s)" % answer)

    # ---- by hand, and unchanged ------------------------------------------------------
    code, answer = cli(base, "take")
    check(code == 0 and answer.get("name", "").startswith("manual-"), "a snapshot by hand (%s)" % answer)
    newest = snapshot.entries(directory)[0]
    check(newest["kind"] == "manual", "the newest first (%s)" % newest)
    check(snapshot.take(config, state, "daily", unless_same=True) is None, "a daily one with nothing changed is skipped")

    # ---- restore ---------------------------------------------------------------------
    (config / "settings.json").write_text('{"appearance": {"theme": "light"}}\n')
    (state / "state.json").write_text(json.dumps({"dnd": {"mode": "manual", "until": 0}, "appRules": {}}))
    code, answer = cli(base, "restore", today)
    check(code == 0 and "config/settings.json" in answer.get("written", []), "restore writes what differs (%s)" % answer)
    check((config / "settings.json").read_text() == '{"held": "before the write"}\n', "and settings.json is back")
    restored_state = json.loads((state / "state.json").read_text())
    check(restored_state["appRules"] == {"Teams": "muted"} and restored_state["dnd"]["mode"] == "manual",
          "the notification rules come back, Do Not Disturb stays as it is now (%s)" % restored_state)
    check(answer.get("backup", "").startswith("before-restore-"), "a copy of now first (%s)" % answer.get("backup"))
    before = snapshot.read_archive(directory / answer["backup"])[1]
    check(before["config/settings.json"] == b'{"appearance": {"theme": "light"}}\n', "which holds the setup before the restore")
    check(cli(base, "restore", "../../etc/passwd")[0] == 1, "a name that is no snapshot is refused")
    check(cli(base, "restore", "daily-1999-01-01.tar.gz")[1].get("error") == "no such snapshot", "and one that is not there")
    (config / "extra.json").write_text("{}\n")
    cli(base, "restore", today)
    check((config / "extra.json").exists(), "a file the snapshot does not have is left alone")

    # ---- export, inspect, import --------------------------------------------------------
    stick = base / "stick"
    stick.mkdir()
    code, answer = cli(base, "export", str(stick / "setup.tar.gz"))
    check(code == 0 and (stick / "setup.tar.gz").is_file(), "export writes one file (%s)" % answer)
    (config / "wallpapers.json").write_text('{"favourites": ["a.png"]}\n')
    (config / "shortcut-keys.txt").unlink()
    code, answer = cli(base, "inspect", str(stick / "setup.tar.gz"))
    states = {item["path"]: item["state"] for item in answer.get("files", [])}
    check(states.get("config/wallpapers.json") == "differs" and states.get("config/shortcut-keys.txt") == "new"
          and states.get("config/layout.json") == "same", "inspect says what importing replaces (%s)" % states)
    check((config / "wallpapers.json").read_text().find("a.png") > 0, "and changes nothing")
    code, answer = cli(base, "import", str(stick / "setup.tar.gz"))
    check(code == 0 and sorted(answer.get("written", [])) == ["config/shortcut-keys.txt", "config/wallpapers.json"],
          "import writes what differs (%s)" % answer)
    check(answer.get("backup", "").startswith("before-import-"), "after a copy of now")
    check((config / "shortcut-keys.txt").read_text() == "SUPER + B = SUPER + W\n", "and the setup is back")

    # ---- archives it refuses -------------------------------------------------------------
    def hostile(path, members, with_manifest=True):
        with tarfile.open(str(path), "w:gz") as tar:
            items = dict(members)
            if with_manifest:
                items["manifest.json"] = json.dumps({"version": 1}).encode()
            for name, data in items.items():
                info = tarfile.TarInfo(name)
                if data is None:
                    info.type = tarfile.SYMTYPE
                    info.linkname = "/etc/passwd"
                    tar.addfile(info)
                    continue
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))

    hostile(base / "evil.tar.gz", {"../escape.json": b"x", "/abs.json": b"x", "config/../up.json": b"x",
                                   "config/link.json": None, "xdg/other.list": b"x", "state/launcher.json": b"x",
                                   "config/settings.json": b'{"ok": true}\n'})
    meta, taken = snapshot.read_archive(base / "evil.tar.gz")
    check(sorted(taken) == ["config/settings.json"], "only the members a snapshot can hold are read (%s)" % sorted(taken))
    hostile(base / "bare.tar.gz", {"config/settings.json": b"{}"}, with_manifest=False)
    code, answer = cli(base, "import", str(base / "bare.tar.gz"))
    check(code == 1 and "not a buchhwin-shell setup" in answer.get("error", ""), "an archive without a manifest is refused (%s)" % answer)
    (base / "plain.txt").write_text("hello")
    check(cli(base, "inspect", str(base / "plain.txt"))[0] == 1, "and a file that is no archive")
    check(not (base / "escape.json").exists() and not pathlib.Path("/abs.json").exists(), "nothing was written outside")

    # ---- what is kept ------------------------------------------------------------------------
    for day in range(20):
        (config / "settings.json").write_text('{"day": %d}\n' % day)
        snapshot.take(config, state, "daily", created=datetime.datetime(2026, 1, 1) + datetime.timedelta(days=day))
    kinds = [item["kind"] for item in snapshot.entries(directory)]
    check(kinds.count("daily") == snapshot.KEEP_DAILY, "fourteen daily snapshots are kept (%d)" % kinds.count("daily"))
    for number in range(12):
        snapshot.take(config, state, "manual", created=datetime.datetime(2026, 2, 1, 12, 0, number))
    kinds = [item["kind"] for item in snapshot.entries(directory)]
    check(len(kinds) - kinds.count("daily") == snapshot.KEEP_OTHER, "and ten others (%s)" % kinds)
    code, answer = cli(base, "list")
    check(code == 0 and len(answer.get("snapshots", [])) == snapshot.KEEP_DAILY + snapshot.KEEP_OTHER
          and all(set(item) == {"name", "kind", "created", "files", "size"} for item in answer["snapshots"]),
          "list names them, newest first")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED snapshot_test")
    sys.exit(1)
print("TESTS PASSED snapshot_test")
