#!/usr/bin/env python3
"""The file work of activating a built-in profile (LayoutService.applyBuiltin).

    profile-apply.py --from DIR --config-dir DIR [--backup-dir DIR] [--dry-run]
    profile-apply.py --backup-stdin --backup-dir DIR

--from is config/builtin-profiles/<id> (profile.json, fastfetch.jsonc, the
logo), --config-dir the shell's ${XDG_CONFIG_HOME}/buchhwin-shell, --backup-dir
its state directory (~/.local/state/buchhwin-shell).

In this order, and nothing after a step that failed:

1. A copy of what is about to be overwritten: settings.json, layout.json and
   the session's default-app lists (buchhwin-shell-mimeapps.list and
   buchhwin-shell-xdg-terminals.list beside the config directory) go into
   BACKUP/backup-<YYYY-MM-DD>, or backup-<YYYY-MM-DD>-<HHMMSS> when that is
   taken. An existing backup is never written into.
2. fastfetch.jsonc and its logo into the config directory. A different file
   already there is kept as <name>.backup-<YYYY-MM-DD> (with the time when that
   name holds something else again); the same file is left alone.
3. Which of the profile's default apps are installed here, by default-apps.py's
   own lookup, and whether its cursor theme is (a `cursors` folder in one of
   the icon directories Xcursor searches) - the shell sets only those, so a
   missing one is skipped rather than reported as an error.

The settings, the layout and the default apps themselves are the shell's to
write (SettingsService, LayoutService, DefaultAppsService); this only moves
files. One JSON line on stdout either way.

--backup-stdin is the backup before the first profile switch of a day
(LayoutService.backupToday): a JSON object on stdin, {"settings.json": text,
"layout.json": text}, the files as the shell held them a moment before it
rewrote them, goes into BACKUP/backup-<YYYY-MM-DD>. When that directory is
there already (an earlier switch, or a built-in profile applied today), the
day's state is kept and nothing is written. The texts come from the shell
rather than from disk because the shell writes the new files before a copy
started from here could read the old ones.

Backups are the user's alone: settings.json holds where the user lives (the
weather's place), so a backup directory is made 0700 and every copy in it
0600, and the backup directories of earlier runs (0755, their copies 0644)
are closed the same way as they are met.
"""
import argparse
import datetime
import filecmp
import importlib.util
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile

SESSION = "buchhwin-shell"
# The files a built-in profile overwrites, relative to the config directory.
BACKED_UP = ["settings.json", "layout.json",
             "../" + SESSION + "-mimeapps.list", "../" + SESSION + "-xdg-terminals.list"]
# A shipped file name, never a path: the profile directory is the repository's,
# but a name with a slash in it would still be a way out of the config directory.
FILE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
# How often a backup name that another run took first is chosen again.
BACKUP_ATTEMPTS = 5
# A backup directory and the copies in it: the user's alone.
PRIVATE_DIR = 0o700
PRIVATE_FILE = 0o600
# The names this script gives its backup directories (see free_name).
BACKUP_DIR_NAME = re.compile(r"^backup-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]{6}(-[0-9]+)?)?$")


def default_apps_module():
    path = pathlib.Path(__file__).resolve().parent / "default-apps.py"
    spec = importlib.util.spec_from_file_location("default_apps", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def free_name(base, stamp_day, stamp_time):
    """BASE-day, or BASE-day-time (then -2, -3 ...) when that is taken."""
    candidate = base.with_name(base.name + "-" + stamp_day)
    if not candidate.exists():
        return candidate
    candidate = base.with_name(base.name + "-" + stamp_day + "-" + stamp_time)
    index = 2
    while candidate.exists():
        candidate = base.with_name(base.name + "-" + stamp_day + "-" + stamp_time + "-" + str(index))
        index += 1
    return candidate


def close_old_backups(backup_dir):
    """Take the group's and the others' bits off the backup directories of earlier runs.

    Only directories with the names this script gives (never a link, never
    anything else in the state directory), and only their own mode: what is
    inside a 0700 directory is out of anyone else's reach, whatever its mode.
    A directory that cannot be changed is left; it is no reason to stop.
    """
    try:
        entries = list(os.scandir(backup_dir))
    except OSError:
        return
    for entry in entries:
        try:
            if not BACKUP_DIR_NAME.match(entry.name) or not entry.is_dir(follow_symlinks=False):
                continue
            mode = entry.stat(follow_symlinks=False).st_mode & 0o777
            if mode & 0o077:
                os.chmod(entry.path, mode & PRIVATE_DIR)
        except OSError:
            continue


def private_copy(source, target):
    """shutil.copy2, then the copy made the user's alone (copy2 takes the source's mode along)."""
    shutil.copy2(source, target)
    os.chmod(target, PRIVATE_FILE)


def backup(config_dir, backup_dir, now):
    """(backup directory or None, names copied). Nothing to copy creates nothing."""
    # Normalised, not resolved: a settings.json that is a link (a dotfiles
    # repository) is copied by its own name, with the content it points to.
    sources = [pathlib.Path(os.path.normpath(config_dir / relative)) for relative in BACKED_UP]
    present = [path for path in sources if path.is_file()]
    if not present:
        return None, []
    # Choosing a free name and making it are two steps, and another run can
    # take the name in between (the day's backup before a switch, a second
    # apply): a name taken a moment ago means asking for the next free one.
    for attempt in range(BACKUP_ATTEMPTS):
        target = free_name(backup_dir / "backup", now.strftime("%Y-%m-%d"), now.strftime("%H%M%S"))
        try:
            target.mkdir(mode=PRIVATE_DIR, parents=True)
            break
        except FileExistsError:
            if attempt == BACKUP_ATTEMPTS - 1:
                raise
    close_old_backups(backup_dir)
    for path in present:
        private_copy(path, target / path.name)
    return target, [path.name for path in present]


# The files a profile switch rewrites, and the only names --backup-stdin
# writes: the names come from the shell, but a name is still a path.
DAILY = ("settings.json", "layout.json")


def daily_backup(texts, backup_dir, now):
    """(backup directory or None, names written, whether the day's backup was there already)."""
    present = {name: texts[name] for name in DAILY
               if isinstance(texts.get(name), str) and texts[name].strip()}
    target = backup_dir / ("backup-" + now.strftime("%Y-%m-%d"))
    close_old_backups(backup_dir)
    if target.exists():
        return None, [], True
    if not present:
        return None, [], False
    try:
        target.mkdir(mode=PRIVATE_DIR, parents=True)
    except FileExistsError:
        # Made a moment ago by another run (profile-apply for a built-in
        # profile entered by the same switch): that one is the day's.
        return None, [], True
    # write_atomic's mkstemp makes each file 0600 already.
    for name, text in present.items():
        write_atomic(target / name, text)
    return target, sorted(present), False


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + "-")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


def install(text, target, now):
    """Write TEXT to TARGET; a different file there is kept first. Returns (written, backup or None)."""
    kept = None
    if target.is_file():
        if target.read_text(encoding="utf-8", errors="replace") == text:
            return False, None
        base = target.with_name(target.name + ".backup")
        day = base.with_name(base.name + "-" + now.strftime("%Y-%m-%d"))
        # The same old file kept once already today is not kept twice.
        if day.is_file() and filecmp.cmp(day, target, shallow=False):
            kept = day
        else:
            kept = free_name(base, now.strftime("%Y-%m-%d"), now.strftime("%H%M%S"))
            shutil.copy2(target, kept)
    write_atomic(target, text)
    return True, kept


def contract_home(path):
    home = str(pathlib.Path.home())
    text = str(path)
    return "~" + text[len(home):] if home and text.startswith(home + "/") else text


def install_fastfetch(profile, source_dir, config_dir, now):
    """{"written": [...], "backups": [...]} for the profile's fastfetch files."""
    spec = profile.get("fastfetch")
    result = {"written": [], "backups": []}
    if not isinstance(spec, dict):
        return result
    config_name = spec.get("config") or ""
    logo_name = spec.get("logo") or ""
    for name in (config_name, logo_name):
        if name and not FILE_NAME.match(name):
            raise ValueError("not a file name in the profile: %r" % name)
    if not config_name:
        return result
    text = (source_dir / config_name).read_text(encoding="utf-8")
    if logo_name:
        # The export points the logo at ~/.config/buchhwin-shell/<logo>; a
        # config directory somewhere else (XDG_CONFIG_HOME, a sandbox) gets
        # its own path, or fastfetch would look for a logo that is not there.
        shipped = "~/.config/" + SESSION + "/" + logo_name
        text = text.replace(shipped, contract_home(config_dir / logo_name))
        logo = (source_dir / logo_name).read_text(encoding="utf-8")
        written, kept = install(logo, config_dir / logo_name, now)
        if written:
            result["written"].append(logo_name)
        if kept:
            result["backups"].append(kept.name)
    written, kept = install(text, config_dir / "fastfetch.jsonc", now)
    if written:
        result["written"].append("fastfetch.jsonc")
    if kept:
        result["backups"].append(kept.name)
    return result


def icon_dirs():
    """Where a cursor theme can be installed, in the order Xcursor looks."""
    home = pathlib.Path.home()
    data_home = pathlib.Path(os.environ.get("XDG_DATA_HOME") or home / ".local" / "share")
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [data_home / "icons", home / ".icons"] + [pathlib.Path(entry) / "icons"
                                                      for entry in data_dirs.split(":") if entry]


def cursor_theme(profile):
    """{"theme": name, "installed": bool} for the profile's cursor theme, {} when it names none.

    The shell sets the theme only when it is installed here: a name nothing
    answers to leaves Hyprland and every toolkit to a fallback of their own,
    which is a different cursor in each, rather than the one in use now.
    """
    settings = profile.get("settings")
    appearance = settings.get("appearance") if isinstance(settings, dict) else None
    name = appearance.get("cursorTheme") if isinstance(appearance, dict) else None
    if not isinstance(name, str) or not name:
        return {}
    # A theme's name, never a path.
    if "/" in name or name in (".", ".."):
        return {"theme": name, "installed": False}
    return {"theme": name, "installed": any((directory / name / "cursors").is_dir() for directory in icon_dirs())}


def installed_apps(profile):
    apps = profile.get("defaultApps")
    if not isinstance(apps, dict):
        return {}, []
    lookup = default_apps_module().InstalledApps()
    found, missing = {}, []
    for category in ("terminal", "files"):
        desktop_id = apps.get(category)
        if not isinstance(desktop_id, str) or not desktop_id:
            continue
        if desktop_id in lookup:
            found[category] = desktop_id
        else:
            missing.append(desktop_id)
    return found, missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--from", dest="source", default="")
    parser.add_argument("--config-dir", default="")
    parser.add_argument("--backup-dir", default="")
    parser.add_argument("--dry-run", action="store_true", help="only say which default apps are installed")
    parser.add_argument("--backup-stdin", action="store_true",
                        help="only keep the files on stdin as the day's backup")
    args = parser.parse_args(argv)
    now = datetime.datetime.now()

    if args.backup_stdin:
        if not args.backup_dir:
            print(json.dumps({"ok": False, "error": "no backup directory"}))
            return 1
        try:
            texts = json.loads(sys.stdin.read() or "{}")
            if not isinstance(texts, dict):
                raise ValueError("not an object")
        except ValueError as error:
            print(json.dumps({"ok": False, "error": "cannot read the files to back up: %s" % error}))
            return 1
        try:
            target, written, kept = daily_backup(texts, pathlib.Path(args.backup_dir), now)
        except OSError as error:
            print(json.dumps({"ok": False, "error": "backup failed: %s" % error}))
            return 1
        print(json.dumps({"ok": True, "backup": str(target) if target else "", "backedUp": written,
                          "alreadyToday": kept}))
        return 0
    if not args.source or not args.config_dir:
        print(json.dumps({"ok": False, "error": "--from and --config-dir are needed"}))
        return 1

    source_dir = pathlib.Path(args.source)
    config_dir = pathlib.Path(args.config_dir)
    try:
        profile = json.loads((source_dir / "profile.json").read_text(encoding="utf-8"))
        if not isinstance(profile, dict):
            raise ValueError("profile.json is not an object")
    except (OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": "cannot read the profile: %s" % error}))
        return 1
    apps, missing = installed_apps(profile)
    cursor = cursor_theme(profile)
    if args.dry_run:
        print(json.dumps({"ok": True, "dryRun": True, "apps": apps, "missing": missing, "cursor": cursor}))
        return 0
    if not args.backup_dir:
        print(json.dumps({"ok": False, "error": "no backup directory: nothing is overwritten without one"}))
        return 1
    try:
        target, copied = backup(config_dir, pathlib.Path(args.backup_dir), now)
    except OSError as error:
        print(json.dumps({"ok": False, "error": "backup failed, nothing changed: %s" % error}))
        return 1
    try:
        fastfetch = install_fastfetch(profile, source_dir, config_dir, now)
    except (OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": "fastfetch not installed: %s" % error,
                          "backup": str(target) if target else ""}))
        return 1
    print(json.dumps({"ok": True, "backup": str(target) if target else "", "backedUp": copied,
                      "fastfetch": fastfetch, "apps": apps, "missing": missing, "cursor": cursor}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
