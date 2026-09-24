#!/usr/bin/env python3
"""Give Plasma its colours back when buchhwin-shell logs out.

Settings > Appearance "Apps follow theme" and "Use the shell accent in apps"
(services/AppThemeService.qml) save the Plasma and GNOME interface values they
found before their first change in $XDG_STATE_HOME/buchhwin-shell/apptheme.json:
the colour scheme, the GNOME keys and a backup of every colour entry of
kdeglobals (the [Colors:*], [ColorEffects:*] and [WM] groups plus the colour
keys of [General] and [KDE]) that plasma-apply-colorscheme rewrites.

scripts/session-action.sh logout runs this helper before the compositor exits,
and a Plasma autostart entry (OnlyShowIn=KDE) runs it again as a safety net
after a crash. When the shell changed the values and "Restore Plasma colors at
logout" is on, kdeglobals gets exactly the backed-up entries back through
kwriteconfig6 (entries added since are deleted), apps are told the palette
changed, the GNOME keys are set again and, when all of that succeeded, the
state file forgets the saved values (the next login saves them again). Only
kwriteconfig6 on kdeglobals colour entries, plasma-apply-colorscheme (older
state files without a backup), the palette notification and the two gsettings
keys the shell sets are run. Nested test sessions never run anything.

`--snapshot` prints the colour entries of kdeglobals as JSON (read-only); the
shell stores that output as the backup.
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

GNOME_SCHEMA = "org.gnome.desktop.interface"
GNOME_KEYS = ("color-scheme", "gtk-theme")
NOTIFY_COMMAND = ["dbus-send", "--session", "--type=signal", "/KGlobalSettings",
                  "org.kde.KGlobalSettings.notifyChange", "int32:0", "int32:0"]
# Keys outside the colour groups that plasma-apply-colorscheme writes.
GENERAL_KEYS = ("ColorScheme", "ColorSchemeHash", "AccentColor", "LastUsedCustomAccentColor",
                "accentColorFromWallpaper", "TintFactor", "TitlebarIsAccentColored")
KDE_KEYS = ("contrast", "frameContrast")
COLOR_GROUP = re.compile(r"^(Colors|ColorEffects):[A-Za-z]+$")
SUBGROUP = re.compile(r"^[A-Za-z]+$")
KEY = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
VALUE = re.compile(r"^[^\\\x00-\x1f\x7f]{0,200}$")


def config_home():
    return pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"))


def nested_environment():
    """The rule of scripts/lib/nested-guard.sh, ported: a nested test session.

    BUCHHWIN_NESTED=1 says so outright, and the session's files in
    BUCHHWIN_NESTED_DIR (default $TMPDIR/buchhwin-nested) say so when they name
    this process's WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE. The second
    half matters: the testing recipe exports the nested display and signature
    and says nothing about the flag, and this script writes the host's
    kdeglobals and GNOME settings.
    """
    if os.environ.get("BUCHHWIN_NESTED") == "1":
        return True
    base = pathlib.Path(os.environ.get("BUCHHWIN_NESTED_DIR")
                        or os.path.join(os.environ.get("TMPDIR") or "/tmp", "buchhwin-nested"))
    for name, variable in (("wayland-display", "WAYLAND_DISPLAY"), ("instance", "HYPRLAND_INSTANCE_SIGNATURE")):
        value = os.environ.get(variable)
        if not value:
            continue
        try:
            stored = (base / name).read_text()
        except OSError:
            continue
        # bash's $(<file) drops trailing newlines; the same comparison here.
        if stored.rstrip("\n") == value:
            return True
    return False


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return pathlib.Path(base) / "buchhwin-shell" / "apptheme.json"


def managed(group, key):
    """Whether a kdeglobals entry belongs to the colour backup."""
    if not isinstance(group, list) or not group or not all(isinstance(part, str) for part in group):
        return False
    if not isinstance(key, str) or not KEY.match(key):
        return False
    top = group[0]
    if len(group) == 1:
        if COLOR_GROUP.match(top) or top == "WM":
            return True
        return (top == "General" and key in GENERAL_KEYS) or (top == "KDE" and key in KDE_KEYS)
    return len(group) == 2 and top.startswith("Colors:") and COLOR_GROUP.match(top) is not None and SUBGROUP.match(group[1]) is not None


def valid_entry(entry):
    return (isinstance(entry, list) and len(entry) == 3 and managed(entry[0], entry[1])
            and isinstance(entry[2], str) and VALUE.match(entry[2]) is not None)


def parse_kdeglobals(text):
    """Colour entries of a KConfig file as [[group, ...], key, value] in file order.

    Escaped values, localized or immutable keys and groups are left out: the
    colour groups written by Plasma never contain them.
    """
    entries = []
    group = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            parts = re.findall(r"\[([^\]]*)\]", line)
            group = parts if "".join(f"[{part}]" for part in parts) == line and parts else None
            if group and any(part.startswith("$") for part in group):
                group = None
            continue
        if group is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        entry = [group, key.strip(), value.strip()]
        if valid_entry(entry):
            entries.append(entry)
    return entries


def snapshot(path=None):
    """Backup of the colour entries; a missing kdeglobals is an empty backup."""
    path = path or config_home() / "kdeglobals"
    try:
        text = path.read_text()
    except FileNotFoundError:
        text = ""
    return {"entries": parse_kdeglobals(text)}


def backup_entries(saved):
    """Validated backup entries from a state file, or None without a backup."""
    if not isinstance(saved, dict):
        return None
    backup = saved.get("kdeColors")
    if not isinstance(backup, dict) or not isinstance(backup.get("entries"), list):
        return None
    return [entry for entry in backup["entries"] if valid_entry(entry)]


def kwrite_command(group, key, value=None):
    command = ["kwriteconfig6", "--file", "kdeglobals"]
    for part in group:
        command += ["--group", part]
    command += ["--key", key]
    # "--" keeps values such as "-0.1" from being read as options.
    return command + (["--delete", "--", ""] if value is None else ["--", value])


def kde_restore_commands(backup, current):
    """kwriteconfig6 calls that turn the current colour entries into the backup."""
    wanted = {(tuple(group), key): value for group, key, value in backup}
    now = {(tuple(group), key): value for group, key, value in current}
    commands = [kwrite_command(list(group), key) for (group, key) in now if (group, key) not in wanted]
    commands += [kwrite_command(list(group), key, value) for (group, key), value in wanted.items() if now.get((group, key)) != value]
    return commands


def valid_command(command):
    """The only commands a state file may ask for."""
    if not isinstance(command, list) or not all(isinstance(part, str) and part for part in command):
        return False
    if len(command) == 2 and command[0] == "plasma-apply-colorscheme":
        return not command[1].startswith("-")
    return (len(command) == 5 and command[:3] == ["gsettings", "set", GNOME_SCHEMA]
            and command[3] in GNOME_KEYS and not command[4].startswith("-"))


def should_restore(state):
    return isinstance(state, dict) and state.get("applied") is True and state.get("restoreOnLogout") is not False


def restore_commands(state, current=None):
    """Commands to run for a parsed state file; empty when there is nothing to do.

    With a colour backup, kdeglobals is restored from it (plus the palette
    notification) instead of re-applying the saved scheme.
    """
    if not should_restore(state):
        return []
    commands = state.get("restore")
    commands = [command for command in commands if valid_command(command)] if isinstance(commands, list) else []
    backup = backup_entries(state.get("saved"))
    if backup is None:
        return commands
    kde = kde_restore_commands(backup, current if current is not None else snapshot()["entries"])
    if kde:
        kde.append(list(NOTIFY_COMMAND))
    return kde + [command for command in commands if command[0] != "plasma-apply-colorscheme"]


def forgotten(state):
    """State after a restore: nothing applied, the logout preference kept."""
    return {"version": 2, "applied": False, "restoreOnLogout": state.get("restoreOnLogout") is not False,
            "saved": None, "restore": []}


def write_atomic(path, text):
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=".apptheme.")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def command_environment():
    """Plasma's view of kdeglobals: its look-and-feel defaults come first."""
    env = dict(os.environ)
    defaults = str(config_home() / "kdedefaults")
    dirs = [part for part in (env.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if part]
    env["XDG_CONFIG_DIRS"] = ":".join([defaults] + [part for part in dirs if part != defaults])
    return env


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--state", type=pathlib.Path, default=None, help="state file (default: XDG state dir)")
    parser.add_argument("--dry-run", action="store_true", help="print the commands, change nothing")
    parser.add_argument("--snapshot", action="store_true", help="print the kdeglobals colour entries as JSON")
    args = parser.parse_args(argv)

    if args.snapshot:
        print(json.dumps(snapshot(), separators=(",", ":")))
        return 0

    if not args.dry_run and nested_environment():
        print("apptheme-restore: skipped in a nested test session", file=sys.stderr)
        return 0

    path = args.state or state_path()
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        return 0
    commands = restore_commands(state)
    if not commands:
        if should_restore(state) and not args.dry_run:
            # Nothing differs any more: forget the saved values all the same.
            write_atomic(path, json.dumps(forgotten(state), indent=2) + "\n")
        return 0

    status = 0
    env = command_environment()
    for command in commands:
        if args.dry_run:
            print(json.dumps(command))
            continue
        try:
            result = subprocess.run(command, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                    text=True, env=env)
            failed = result.returncode != 0
            detail = result.stderr.strip()
        except (OSError, subprocess.TimeoutExpired) as error:
            failed, detail = True, str(error)
        if failed:
            print(f"apptheme-restore: {command[0]} failed: {detail}", file=sys.stderr)
            # Without a session bus the palette notification cannot be sent;
            # the colours are back all the same.
            if command != NOTIFY_COMMAND:
                status = 1
    # A failed restore keeps the saved values for the next attempt (turning the
    # option off in the next session, the next logout or the Plasma autostart).
    if not args.dry_run and status == 0:
        write_atomic(path, json.dumps(forgotten(state), indent=2) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
