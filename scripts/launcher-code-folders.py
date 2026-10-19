#!/usr/bin/env python3
"""The folders the launcher offers to open in VS Code ("Open in VS Code").

Prints one JSON object and exits:

  {"editors": {"Code": ["/home/u/git/a", ...]}, "projects": ["/home/u/git/b", ...]}

`editors`: for each VS Code build whose user data is there (Code, Code - OSS,
VSCodium, Code - Insiders under ~/.config), the folders and workspace files it
opened last, newest first. They come from its state database
(`history.recentlyOpenedPathsList` in User/globalStorage/state.vscdb) and from
User/globalStorage/storage.json (the window it had open last, the windows it
restores, its backups and profile associations - a build that never shows a
"recent" list still has those). The database is opened read-only and
immutable: the running editor holds it open and writes it, and this must
neither lock it nor change it, not even its journal.

`projects`: the folders under ~/git, by name, and those under ~/src,
~/projects, ~/Projects, ~/code and ~/repos that are Git checkouts.

Local paths that exist only; never a remote folder. The launcher runs this
once per open, when a query first asks for it (services/LauncherService.qml,
services/launcher/CodeFolders.js); nothing of it stays running.
"""

import json
import os
import sqlite3
import sys
from urllib.parse import quote, unquote, urlsplit

EDITORS = ("Code", "Code - OSS", "VSCodium", "Code - Insiders")
# ~/git is the user's own folder of checkouts: every folder in it counts.
# The others are common names that may hold anything, so only checkouts.
PROJECT_ROOTS = (("git", False), ("src", True), ("projects", True), ("Projects", True),
                 ("code", True), ("repos", True))
LIMIT = 100


def local_path(uri):
    """The path of a file:// URI, or None for anything else."""
    if not isinstance(uri, str):
        return None
    parts = urlsplit(uri)
    if parts.scheme != "file" or parts.netloc not in ("", "localhost"):
        return None
    path = unquote(parts.path)
    return path if path.startswith("/") else None


def recent_entries(database):
    """Folder and workspace URIs from the state database, newest first."""
    if not os.path.isfile(database):
        return []
    # The path escaped as a URI's: "Code - OSS" has spaces, and a "?" or "#"
    # in a home folder's name would end the file name.
    try:
        connection = sqlite3.connect("file:" + quote(database) + "?mode=ro&immutable=1", uri=True, timeout=0.5)
    except sqlite3.Error:
        return []
    try:
        row = connection.execute(
            "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'").fetchone()
    except sqlite3.Error:
        return []
    finally:
        connection.close()
    if not row:
        return []
    try:
        value = row[0].decode("utf-8") if isinstance(row[0], bytes) else row[0]
        entries = json.loads(value).get("entries", [])
    except (ValueError, AttributeError, UnicodeDecodeError):
        return []
    found = []
    for entry in entries if isinstance(entries, list) else []:
        if not isinstance(entry, dict):
            continue
        if "folderUri" in entry:
            found.append(entry["folderUri"])
        elif isinstance(entry.get("workspace"), dict):
            found.append(entry["workspace"].get("configPath"))
    return found


def storage_entries(storage):
    """Folder URIs from storage.json: the last window, the restored ones, backups, profiles."""
    try:
        with open(storage, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return []
    if not isinstance(data, dict):
        return []
    found = []
    windows = data.get("windowsState") if isinstance(data.get("windowsState"), dict) else {}
    last = windows.get("lastActiveWindow")
    for window in ([last] if isinstance(last, dict) else []) + [
            item for item in windows.get("openedWindows", []) if isinstance(item, dict)]:
        found.append(window.get("folder"))
        workspace = window.get("workspaceIdentifier")
        if isinstance(workspace, dict):
            found.append(workspace.get("configURIPath"))
    backups = data.get("backupWorkspaces") if isinstance(data.get("backupWorkspaces"), dict) else {}
    for item in backups.get("folders", []) if isinstance(backups.get("folders"), list) else []:
        if isinstance(item, dict):
            found.append(item.get("folderUri"))
    profiles = data.get("profileAssociations") if isinstance(data.get("profileAssociations"), dict) else {}
    workspaces = profiles.get("workspaces")
    if isinstance(workspaces, dict):
        found.extend(workspaces.keys())
    return found


def editor_folders(config_home, name):
    base = os.path.join(config_home, name, "User", "globalStorage")
    if not os.path.isdir(base):
        return None
    seen = set()
    folders = []
    for uri in recent_entries(os.path.join(base, "state.vscdb")) + storage_entries(os.path.join(base, "storage.json")):
        path = local_path(uri)
        if not path:
            continue
        path = path.rstrip("/") or "/"
        if path in seen:
            continue
        seen.add(path)
        if os.path.isdir(path) or (path.endswith(".code-workspace") and os.path.isfile(path)):
            folders.append(path)
        if len(folders) >= LIMIT:
            break
    return folders


def projects(home):
    found = []
    for root, checkouts_only in PROJECT_ROOTS:
        folder = os.path.join(home, root)
        try:
            names = sorted(os.listdir(folder), key=str.lower)
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            if name.startswith(".") or not os.path.isdir(path):
                continue
            if checkouts_only and not os.path.exists(os.path.join(path, ".git")):
                continue
            found.append(path)
            if len(found) >= 2 * LIMIT:
                return found
    return found


def main():
    home = os.environ.get("HOME") or os.path.expanduser("~")
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    editors = {}
    for name in EDITORS:
        folders = editor_folders(config_home, name)
        if folders is not None:
            editors[name] = folders
    json.dump({"editors": editors, "projects": projects(home)}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
