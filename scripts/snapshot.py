#!/usr/bin/env python3
"""Copies of the whole setup: a daily snapshot, Restore, Export and Import.

    snapshot.py daily [--stdin]        the day's snapshot, unless one is there or
                                       nothing changed since the newest
    snapshot.py take                   a snapshot now, whatever is there
    snapshot.py list                   the snapshots, newest first
    snapshot.py restore NAME           a snapshot back (a copy of now first)
    snapshot.py inspect FILE           what importing FILE would replace
    snapshot.py import FILE            FILE's setup in place (a copy of now first)
    snapshot.py export FILE            the setup as one file, for a stick or a share

    common: [--config-dir DIR] [--state-dir DIR]

Backups used to exist only before a profile switch (LayoutService.backupToday)
and before a built-in profile was applied (profile-apply.py), and the move to
another machine started from factory settings. A snapshot is everything the
shell keeps of the user's setup:

- every regular file directly in the config directory (settings.json,
  layout.json with every profile, wallpapers.json, shortcut-keys.txt,
  shortcuts.json, monitors.json, fastfetch.jsonc and its logo, the terminal
  files Settings > Terminal writes ...), 4 MiB at most each - backups,
  `.bad` copies, temporary files and links left out;
- the session's default-app lists beside it (buchhwin-shell-mimeapps.list,
  buchhwin-shell-xdg-terminals.list);
- state.json, for the notification rules - Do Not Disturb is left as it is
  now when one comes back.

One tar.gz per snapshot in STATE/snapshots (0700, each file 0600: settings.json
holds where the user lives), with a manifest.json naming every file and a hash
of the whole. `daily` runs on the first write of a day (SnapshotService, from
SettingsService and LayoutService): settings.json and layout.json may come on
stdin as {"settings.json": text, "layout.json": text}, the files as the shell
held them a moment before it rewrote them. Kept: 14 daily ones, 10 others
(taken by hand, or before a restore or an import).

A restore or an import writes each file atomically and leaves every file the
snapshot does not have alone; the shell is restarted afterwards
(SnapshotService) so that every part of it reads them again. Archives are
read member by member against the list above, never unpacked: a file from a
stick names nothing outside these directories.

One JSON line on stdout either way; exit 1 with {"ok": false, "error": ...}.
"""

import argparse
import datetime
import hashlib
import io
import json
import os
import pathlib
import re
import sys
import tarfile
import tempfile

SESSION = "buchhwin-shell"
VERSION = 1
FILE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
# Copies the shell or its helpers keep of a file, never the setup itself.
SKIPPED = re.compile(r"(\.backup|\.bad$|\.tmp$|\.old$|^layout\.v[0-9]+\.backup\.json$|\.lock$|~$)")
XDG_LISTS = (SESSION + "-mimeapps.list", SESSION + "-xdg-terminals.list")
STATE_FILES = ("state.json",)
# What a snapshot of state.json gives back: the notification rules, not a Do
# Not Disturb that was on that day.
STATE_KEEP_CURRENT = {"state.json": ("dnd",)}
MAX_FILE = 4 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
KEEP_DAILY = 14
KEEP_OTHER = 10
SNAPSHOT_NAME = re.compile(r"^(daily|manual|before-restore|before-import)-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]{6})?(-[0-9]+)?\.tar\.gz$")
MEMBER = re.compile(r"^(config|xdg|state)/([A-Za-z0-9][A-Za-z0-9._-]*)$")
PRIVATE_DIR = 0o700
PRIVATE_FILE = 0o600


class Refused(Exception):
    pass


def emit(**values):
    sys.stdout.write(json.dumps(values, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def now():
    return datetime.datetime.now()


# ---- what a snapshot holds -----------------------------------------------------

def collect(config_dir, state_dir, overrides=None):
    """{member path: bytes} of the setup as it is now; overrides replace the
    text of config files by name (the shell's own copies, --stdin)."""
    files = {}
    total = 0
    config_dir = pathlib.Path(config_dir)
    if config_dir.is_dir():
        for path in sorted(config_dir.iterdir()):
            name = path.name
            if not FILE_NAME.match(name) or SKIPPED.search(name) or path.is_symlink() or not path.is_file():
                continue
            try:
                if path.stat().st_size > MAX_FILE:
                    continue
                files["config/" + name] = path.read_bytes()
            except OSError:
                continue
    for name, text in (overrides or {}).items():
        if name in ("settings.json", "layout.json") and isinstance(text, str) and text.strip():
            files["config/" + name] = text.encode("utf-8")
    for name in XDG_LISTS:
        path = config_dir.parent / name
        if path.is_file() and not path.is_symlink():
            try:
                if path.stat().st_size <= MAX_FILE:
                    files["xdg/" + name] = path.read_bytes()
            except OSError:
                pass
    for name in STATE_FILES:
        path = pathlib.Path(state_dir) / name
        if path.is_file() and not path.is_symlink():
            try:
                if path.stat().st_size <= MAX_FILE:
                    files["state/" + name] = path.read_bytes()
            except OSError:
                pass
    for data in files.values():
        total += len(data)
    if total > MAX_TOTAL:
        raise Refused("the setup is larger than %d MiB" % (MAX_TOTAL // (1024 * 1024)))
    return files


def digest(files):
    hasher = hashlib.sha256()
    for path in sorted(files):
        hasher.update(path.encode("utf-8") + b"\0" + hashlib.sha256(files[path]).digest())
    return hasher.hexdigest()


def manifest(files, kind, created):
    return {"version": VERSION, "kind": kind, "created": created.isoformat(timespec="seconds"),
            "hash": digest(files),
            "files": [{"path": path, "size": len(files[path])} for path in sorted(files)]}


def archive_bytes(files, kind, created):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        entries = dict(files)
        entries["manifest.json"] = json.dumps(manifest(files, kind, created), indent=2).encode("utf-8")
        for path in sorted(entries):
            info = tarfile.TarInfo(path)
            info.size = len(entries[path])
            info.mode = PRIVATE_FILE
            info.mtime = int(created.timestamp())
            tar.addfile(info, io.BytesIO(entries[path]))
    return buffer.getvalue()


def read_archive(path):
    """(manifest, {member: bytes}) of an archive, only the members a snapshot
    can hold; Refused for anything that is not one."""
    files = {}
    meta = None
    total = 0
    try:
        with tarfile.open(str(path), mode="r:gz") as tar:
            for info in tar:
                if not info.isreg():
                    continue
                if info.name == "manifest.json":
                    if info.size > MAX_FILE:
                        raise Refused("its manifest is too large")
                    try:
                        meta = json.loads(tar.extractfile(info).read().decode("utf-8"))
                    except (ValueError, UnicodeDecodeError):
                        raise Refused("its manifest is unreadable")
                    continue
                if not MEMBER.match(info.name) or SKIPPED.search(info.name.split("/", 1)[1]):
                    continue
                if info.name.startswith("xdg/") and info.name[4:] not in XDG_LISTS:
                    continue
                if info.name.startswith("state/") and info.name[6:] not in STATE_FILES:
                    continue
                if info.size > MAX_FILE:
                    continue
                total += info.size
                if total > MAX_TOTAL:
                    raise Refused("it is larger than %d MiB" % (MAX_TOTAL // (1024 * 1024)))
                files[info.name] = tar.extractfile(info).read()
    except (OSError, tarfile.TarError, EOFError) as error:
        raise Refused("it is not a buchhwin-shell setup (%s)" % error.__class__.__name__)
    if not isinstance(meta, dict) or meta.get("version") != VERSION or not files:
        raise Refused("it is not a buchhwin-shell setup")
    return meta, files


# ---- the snapshot directory ------------------------------------------------------

def snapshot_dir(state_dir):
    directory = pathlib.Path(state_dir) / "snapshots"
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, PRIVATE_DIR)
    return directory


def write_private(path, data):
    """Atomically, the user's alone - where the filesystem has modes at all
    (an export to a FAT stick has none, and chmod fails there)."""
    path = pathlib.Path(path)
    handle, temporary = tempfile.mkstemp(dir=str(path.parent), prefix="." + path.name + ".")
    try:
        with os.fdopen(handle, "wb") as out:
            out.write(data)
        try:
            os.chmod(temporary, PRIVATE_FILE)
        except OSError:
            pass
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def free_name(directory, kind, created, with_time):
    stamp = created.strftime("%Y-%m-%d") + (created.strftime("-%H%M%S") if with_time else "")
    name = "%s-%s.tar.gz" % (kind, stamp)
    number = 1
    while (directory / name).exists():
        number += 1
        name = "%s-%s-%d.tar.gz" % (kind, stamp, number)
    return name


def entries(directory):
    """[{name, kind, created, files, size, hash}] newest first."""
    found = []
    for path in directory.iterdir():
        if not SNAPSHOT_NAME.match(path.name) or not path.is_file():
            continue
        try:
            meta, files = read_archive(path)
        except Refused:
            continue
        found.append({"name": path.name, "kind": path.name.split("-20", 1)[0],
                      "created": str(meta.get("created", "")), "files": len(files),
                      "size": path.stat().st_size, "hash": str(meta.get("hash", ""))})
    found.sort(key=lambda item: (item["created"], item["name"]), reverse=True)
    return found


def prune(directory):
    listed = entries(directory)
    daily = [item for item in listed if item["kind"] == "daily"]
    other = [item for item in listed if item["kind"] != "daily"]
    for item in daily[KEEP_DAILY:] + other[KEEP_OTHER:]:
        try:
            (directory / item["name"]).unlink()
        except OSError:
            pass


def take(config_dir, state_dir, kind, overrides=None, unless_same=False, created=None):
    """A new snapshot of kind; None when unless_same and the newest holds
    the same setup."""
    created = created or now()
    files = collect(config_dir, state_dir, overrides)
    if not files:
        return None
    directory = snapshot_dir(state_dir)
    if unless_same:
        listed = entries(directory)
        if listed and listed[0]["hash"] == digest(files):
            return None
    name = free_name(directory, kind, created, kind != "daily")
    write_private(directory / name, archive_bytes(files, kind, created))
    prune(directory)
    return name


# ---- putting a setup back ------------------------------------------------------------

def target_of(member, config_dir, state_dir):
    area, name = member.split("/", 1)
    if area == "config":
        return pathlib.Path(config_dir) / name
    if area == "xdg":
        return pathlib.Path(config_dir).parent / name
    return pathlib.Path(state_dir) / name


def merged(member, data, target):
    """state.json keeps what STATE_KEEP_CURRENT names from the file there now."""
    keep = STATE_KEEP_CURRENT.get(member.split("/", 1)[1]) if member.startswith("state/") else None
    if not keep:
        return data
    try:
        incoming = json.loads(data.decode("utf-8"))
        current = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}
    except (ValueError, UnicodeDecodeError, OSError):
        return data
    if not isinstance(incoming, dict) or not isinstance(current, dict):
        return data
    for key in keep:
        if key in current:
            incoming[key] = current[key]
        else:
            incoming.pop(key, None)
    return (json.dumps(incoming, indent=2) + "\n").encode("utf-8")


def compare(files, config_dir, state_dir):
    """[{path, size, state: new | same | differs}] against the files there now."""
    listed = []
    for member in sorted(files):
        target = target_of(member, config_dir, state_dir)
        try:
            state = "same" if target.read_bytes() == files[member] else "differs"
        except FileNotFoundError:
            state = "new"
        except OSError:
            state = "differs"
        listed.append({"path": member, "size": len(files[member]), "state": state})
    return listed


def put_back(files, config_dir, state_dir):
    written = []
    pathlib.Path(config_dir).mkdir(parents=True, exist_ok=True)
    for member in sorted(files):
        target = target_of(member, config_dir, state_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        data = merged(member, files[member], target)
        try:
            if target.read_bytes() == data:
                continue
        except OSError:
            pass
        write_private(target, data)
        written.append(member)
    return written


# ---- commands ------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("command", choices=["daily", "take", "list", "restore", "inspect", "import", "export"])
    parser.add_argument("target", nargs="?", default="")
    parser.add_argument("--stdin", action="store_true")
    parser.add_argument("--config-dir", default=os.path.join(os.environ.get("XDG_CONFIG_HOME") or
                                                             os.path.expanduser("~/.config"), SESSION))
    parser.add_argument("--state-dir", default=os.path.join(os.environ.get("XDG_STATE_HOME") or
                                                            os.path.expanduser("~/.local/state"), SESSION))
    args = parser.parse_args(argv)
    try:
        if args.command == "daily":
            overrides = {}
            if args.stdin:
                try:
                    overrides = json.loads(sys.stdin.read() or "{}")
                except ValueError:
                    overrides = {}
                if not isinstance(overrides, dict):
                    overrides = {}
            directory = snapshot_dir(args.state_dir)
            today = "daily-" + now().strftime("%Y-%m-%d")
            if any(path.name.startswith(today) for path in directory.iterdir()):
                emit(ok=True, skipped="today")
                return 0
            name = take(args.config_dir, args.state_dir, "daily", overrides, unless_same=True)
            emit(ok=True, name=name, skipped="" if name else "unchanged")
            return 0
        if args.command == "take":
            name = take(args.config_dir, args.state_dir, "manual")
            if not name:
                raise Refused("there is no setup to keep yet")
            emit(ok=True, name=name)
            return 0
        if args.command == "list":
            listed = entries(snapshot_dir(args.state_dir))
            emit(ok=True, snapshots=[{key: item[key] for key in ("name", "kind", "created", "files", "size")} for item in listed])
            return 0
        if args.command == "export":
            if not args.target:
                raise Refused("no file to export to")
            files = collect(args.config_dir, args.state_dir)
            if not files:
                raise Refused("there is no setup to export yet")
            destination = pathlib.Path(args.target).expanduser()
            if destination.is_dir():
                raise Refused("that is a folder")
            write_private(destination, archive_bytes(files, "export", now()))
            emit(ok=True, path=str(destination), files=len(files))
            return 0
        if args.command == "inspect":
            meta, files = read_archive(pathlib.Path(args.target).expanduser())
            emit(ok=True, created=str(meta.get("created", "")), files=compare(files, args.config_dir, args.state_dir))
            return 0
        if args.command in ("restore", "import"):
            if args.command == "restore":
                if not SNAPSHOT_NAME.match(args.target):
                    raise Refused("no such snapshot")
                source = snapshot_dir(args.state_dir) / args.target
                if not source.is_file():
                    raise Refused("no such snapshot")
            else:
                source = pathlib.Path(args.target).expanduser()
            meta, files = read_archive(source)
            # A copy of now first, whatever it holds: the way back from here.
            kind = "before-" + args.command
            backup = take(args.config_dir, args.state_dir, kind)
            written = put_back(files, args.config_dir, args.state_dir)
            emit(ok=True, backup=backup or "", written=written, created=str(meta.get("created", "")))
            return 0
    except Refused as refusal:
        emit(ok=False, error=str(refusal))
        return 1
    except OSError as error:
        emit(ok=False, error=error.strerror or str(error))
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
