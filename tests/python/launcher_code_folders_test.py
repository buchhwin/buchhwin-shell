#!/usr/bin/env python3
"""scripts/launcher-code-folders.py on an invented home: VS Code's recent
folders from its state database and storage.json, newest first and each
once, only local ones that exist; the project folders under ~/git (all) and
~/src (checkouts only); and the database left exactly as it was - read
immutable, so a running editor holding a lock on it changes nothing."""

import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "launcher-code-folders.py"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL launcher_code_folders:", message)


def run(home, config=None):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home)}
    if config:
        env["XDG_CONFIG_HOME"] = str(config)
    result = subprocess.run([sys.executable, "-I", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=30)
    check(result.returncode == 0, "exit status %d (%s)" % (result.returncode, result.stderr.strip()))
    return json.loads(result.stdout)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory(prefix="buchhwin-codefolders.") as scratch:
    home = Path(scratch) / "home"
    for folder in ("work/site", "work/api", "git/shell", "git/dots", "git/.hidden", "src/tool/.git", "src/notes",
                   "projects/old"):
        (home / folder).mkdir(parents=True)
    (home / "git" / "README.txt").write_text("not a folder\n")
    (home / "work" / "all.code-workspace").write_text("{}\n")
    storage_dir = home / ".config" / "Code" / "User" / "globalStorage"
    storage_dir.mkdir(parents=True)
    database = storage_dir / "state.vscdb"
    connection = sqlite3.connect(database)
    connection.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
    recent = {"entries": [
        {"folderUri": "file://%s/work/site" % home},
        {"fileUri": "file://%s/work/site/index.html" % home},
        {"workspace": {"id": "1", "configPath": "file://%s/work/all.code-workspace" % home}},
        {"folderUri": "vscode-remote://ssh-remote%%2Bhost/srv/app"},
        {"folderUri": "file://%s/gone" % home},
        {"folderUri": "file://%s/git/shell/" % home},
        {"folderUri": "file://%s/work/with%%20space" % home},
        "not an entry",
    ]}
    connection.execute("INSERT INTO ItemTable VALUES (?, ?)", ("history.recentlyOpenedPathsList", json.dumps(recent)))
    connection.execute("INSERT INTO ItemTable VALUES (?, ?)", ("other.key", "x"))
    connection.commit()
    connection.close()
    (home / "work" / "with space").mkdir()
    (storage_dir / "storage.json").write_text(json.dumps({
        "windowsState": {"lastActiveWindow": {"folder": "file://%s/work/api" % home},
                         "openedWindows": [{"folder": "file://%s/work/site" % home}]},
        "backupWorkspaces": {"folders": [{"folderUri": "file://%s/git/dots" % home}]},
        "profileAssociations": {"workspaces": {"file://%s/projects/old" % home: "__default__profile__"}},
    }))
    before = digest(database)
    files_before = sorted(path.name for path in storage_dir.iterdir())

    # The running editor holds the database: an exclusive lock from another
    # connection, as VS Code's writer would.
    holder = sqlite3.connect(database, isolation_level=None)
    holder.execute("BEGIN EXCLUSIVE")
    try:
        data = run(home)
    finally:
        holder.execute("ROLLBACK")
        holder.close()

    code = data["editors"].get("Code")
    check(code == [str(home / "work/site"), str(home / "work/all.code-workspace"), str(home / "git/shell"),
                   str(home / "work/with space"), str(home / "work/api"), str(home / "git/dots"),
                   str(home / "projects/old")],
          "the recent list first, then storage.json, each once, local and there: %r" % (code,))
    check(set(data["editors"]) == {"Code"}, "only the builds whose user data is there: %r" % (sorted(data["editors"]),))
    check(data["projects"] == [str(home / "git/dots"), str(home / "git/shell"), str(home / "src/tool")],
          "every folder under ~/git, checkouts only under ~/src, nothing hidden: %r" % (data["projects"],))
    check(digest(database) == before, "the state database is not changed")
    check(sorted(path.name for path in storage_dir.iterdir()) == files_before,
          "and no journal or lock file is left beside it: %r" % (sorted(path.name for path in storage_dir.iterdir()),))

    # A database without the key, a broken storage.json, another build.
    connection = sqlite3.connect(database)
    connection.execute("DELETE FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'")
    connection.commit()
    connection.close()
    (storage_dir / "storage.json").write_text("{ broken")
    codium = home / ".config" / "VSCodium" / "User" / "globalStorage"
    codium.mkdir(parents=True)
    (codium / "state.vscdb").write_text("not a database")
    data = run(home)
    check(data["editors"] == {"Code": [], "VSCodium": []}, "nothing to read is an empty list, not an error: %r" % (data["editors"],))

    # XDG_CONFIG_HOME is where the builds' user data is looked for.
    elsewhere = Path(scratch) / "config"
    elsewhere.mkdir()
    data = run(home, elsewhere)
    check(data["editors"] == {}, "another config folder, no editor there: %r" % (data["editors"],))

    # A database path that is no plain URI: the build's name has spaces, and
    # a "#" in a folder's name would end the file name in one unescaped.
    odd = Path(scratch) / "config #2"
    oss = odd / "Code - OSS" / "User" / "globalStorage"
    oss.mkdir(parents=True)
    connection = sqlite3.connect(oss / "state.vscdb")
    connection.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
    connection.execute("INSERT INTO ItemTable VALUES (?, ?)", ("history.recentlyOpenedPathsList",
                       json.dumps({"entries": [{"folderUri": "file://%s/git/dots" % home}]})))
    connection.commit()
    connection.close()
    data = run(home, odd)
    check(data["editors"] == {"Code - OSS": [str(home / "git/dots")]},
          "read under a folder with spaces and a \"#\": %r" % (data["editors"],))

    # No home folders at all.
    empty = Path(scratch) / "empty"
    empty.mkdir()
    data = run(empty)
    check(data == {"editors": {}, "projects": []}, "an empty home: %r" % (data,))

if failures:
    print("TESTS FAILED launcher_code_folders_test (%d)" % len(failures))
    sys.exit(1)
print("TESTS PASSED launcher_code_folders_test")
