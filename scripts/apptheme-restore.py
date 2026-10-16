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
state files without a backup), the palette notification and the three gsettings
keys the shell sets are run, and the GTK files below are written back. Nested
test sessions never run anything.

`--snapshot` prints the colour entries of kdeglobals as JSON (read-only); the
shell stores that output as the backup.

GTK 3 and 4 take their dark variant and the icon theme from
~/.config/gtk-{3.0,4.0}/settings.ini, and the Breeze theme draws with the
colours of the user's gtk.css (`@import 'colors.css';`, written by Plasma's
kded for its own scheme). While "Apps follow theme" is on, the shell changes
those two keys and leaves a colors.css of the other brightness out of gtk.css
(`--gtk DIR JSON`); `--gtk-snapshot` prints what is there now (read-only), and
the restore writes the saved values back. Only files that exist are touched,
through a symbolic link to the file it names, with its permissions kept.
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
GNOME_KEYS = ("color-scheme", "gtk-theme", "icon-theme")
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
# The GTK side (AppThemeLogic.js has the same names and rules).
GTK_DIRS = ("gtk-3.0", "gtk-4.0")
GTK_HELPER = "apptheme-restore.py"
INI_KEYS = {"preferDark": "gtk-application-prefer-dark-theme", "iconTheme": "gtk-icon-theme-name"}
INI_VALUE = re.compile(r"^\S(?:[^\x00-\x1f\x7f]{0,126}\S)?$")
IMPORT_LINE = "@import 'colors.css';"
IMPORT = re.compile(r"""^\s*@import\s+(?:url\(\s*)?['"]colors\.css['"]\s*\)?\s*;\s*$""")
# An import left out is commented, not deleted, so the line comes back as it
# was - and a gtk.css the restore never reached still says why.
LEFT_OUT = re.compile(r"^/\* buchhwin-shell, Apps follow theme: (.*) \*/$")
# The window background of the palette, else the view's.
PALETTE = re.compile(r"@define-color\s+(theme_bg_color_breeze|content_view_bg_breeze)\s+#([0-9a-fA-F]{6})\s*;")


def config_home():
    return pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"))


def nested_environment():
    """The rule of scripts/lib/nested-guard.sh, ported: a nested test session.

    BUCHHWIN_NESTED=1 says so outright, and the session's files in
    BUCHHWIN_NESTED_DIR (default $XDG_RUNTIME_DIR/buchhwin-nested) say so when they name
    this process's WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE. The second
    half matters: the testing recipe exports the nested display and signature
    and says nothing about the flag, and this script writes the host's
    kdeglobals and GNOME settings.
    """
    if os.environ.get("BUCHHWIN_NESTED") == "1":
        return True
    base = pathlib.Path(os.environ.get("BUCHHWIN_NESTED_DIR")
                        or os.path.join(os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR") or "/tmp",
                                        "buchhwin-nested"))
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


# ---- GTK files ----------------------------------------------------------------

def ini_settings(text, keys):
    """{key: value} of [Settings] for `keys`, None for a key it lacks."""
    found = {key: None for key in keys}
    group = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("["):
            group = line[1:-1].strip() if line.endswith("]") else None
            continue
        if group == "Settings" and "=" in line and not line.startswith(("#", ";")):
            key, value = line.split("=", 1)
            if key.strip() in found and found[key.strip()] is None:
                found[key.strip()] = value.strip()
    return found


def edit_ini(text, changes):
    """settings.ini with `changes` ({key: value, or None to remove}) in [Settings].

    Every other line is kept as it is; a key that is missing goes to the end of
    the group.
    """
    out = []
    group = None
    done = set()
    seen = False
    end = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("["):
            if group == "Settings" and end is None:
                end = len(out)
            group = line[1:-1].strip() if line.endswith("]") else None
            seen = seen or group == "Settings"
            out.append(raw)
            continue
        if group == "Settings" and "=" in line and not line.startswith(("#", ";")):
            key = line.split("=", 1)[0].strip()
            if key in changes:
                if key not in done and changes[key] is not None:
                    out.append(f"{key}={changes[key]}")
                done.add(key)
                continue
        out.append(raw)
    if group == "Settings" and end is None:
        end = len(out)
    missing = [f"{key}={value}" for key, value in changes.items() if key not in done and value is not None]
    if missing and not seen:
        out = ["[Settings]"] + missing + ([""] + out if out else [])
    elif missing:
        while end > 0 and not out[end - 1].strip():
            end -= 1
        out[end:end] = missing
    return "\n".join(out) + ("\n" if text.endswith("\n") or not text else "")


def edit_import(text, wanted):
    """gtk.css with the colors.css import, or with it commented out."""
    lines = text.split("\n")
    if not wanted:
        return "\n".join(f"/* buchhwin-shell, Apps follow theme: {line} */" if IMPORT.match(line) else line for line in lines)
    if any(IMPORT.match(line) for line in lines):
        return text
    if any(LEFT_OUT.match(line) and IMPORT.match(LEFT_OUT.match(line).group(1)) for line in lines):
        return "\n".join(LEFT_OUT.match(line).group(1) if LEFT_OUT.match(line) and IMPORT.match(LEFT_OUT.match(line).group(1))
                         else line for line in lines)
    return IMPORT_LINE + ("\n" + text if text else "\n")


def palette_dark(text):
    """Whether a colors.css is a dark palette; None when it does not say."""
    colours = dict(PALETTE.findall(text))
    value = colours.get("theme_bg_color_breeze") or colours.get("content_view_bg_breeze")
    if not value:
        return None
    red, green, blue = (int(value[index:index + 2], 16) for index in (0, 2, 4))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 128


def read_text(path):
    try:
        return path.read_text() if path.is_file() else None
    except OSError:
        return None


def gtk_snapshot(home=None):
    """What --gtk-snapshot prints: per GTK folder the keys of the files it has."""
    base = home or config_home()
    result = {}
    for directory in GTK_DIRS:
        entry = {}
        settings = read_text(base / directory / "settings.ini")
        if settings is not None:
            values = ini_settings(settings, INI_KEYS.values())
            for name, key in INI_KEYS.items():
                # A value the helper could not write back is not reported, so
                # it is never changed.
                if values[key] is None or INI_VALUE.match(values[key]):
                    entry[name] = values[key]
        css = read_text(base / directory / "gtk.css")
        if css is not None:
            entry["colorsImport"] = any(IMPORT.match(line) for line in css.splitlines())
        colors = read_text(base / directory / "colors.css")
        dark = palette_dark(colors) if colors is not None else None
        if dark is not None:
            entry["colorsDark"] = dark
        if entry:
            result[directory] = entry
    return result


def valid_gtk_values(values):
    """The changes `--gtk` may make: the two keys (a value or None) and the import."""
    if not isinstance(values, dict) or not values:
        return False
    for name, value in values.items():
        if name in INI_KEYS:
            if value is not None and not (isinstance(value, str) and INI_VALUE.match(value)):
                return False
        elif name == "colorsImport":
            if not isinstance(value, bool):
                return False
        else:
            return False
    return True


def write_kept(path, text):
    """Write a file that exists: through a symbolic link, permissions kept."""
    real = path.resolve()
    mode = os.stat(real).st_mode & 0o7777
    write_atomic(real, text, mode)


def apply_gtk(directory, values, home=None):
    """Change one GTK folder's files as `values` says; only files that exist."""
    if directory not in GTK_DIRS or not valid_gtk_values(values):
        raise ValueError(f"refused: {directory} {values!r}")
    base = (home or config_home()) / directory
    changes = {INI_KEYS[name]: value for name, value in values.items() if name in INI_KEYS}
    settings = base / "settings.ini"
    text = read_text(settings)
    if changes and text is not None:
        edited = edit_ini(text, changes)
        if edited != text:
            write_kept(settings, edited)
    css = base / "gtk.css"
    text = read_text(css)
    if "colorsImport" in values and text is not None:
        edited = edit_import(text, values["colorsImport"])
        if edited != text:
            write_kept(css, edited)


def gtk_saved(saved):
    """The validated GTK values of a state file's saved block, or {}."""
    gtk = saved.get("gtk") if isinstance(saved, dict) else None
    if not isinstance(gtk, dict):
        return {}
    result = {}
    for directory in GTK_DIRS:
        entry = gtk.get(directory)
        if not isinstance(entry, dict):
            continue
        clean = {name: value for name, value in entry.items()
                 if (name in INI_KEYS and (value is None or (isinstance(value, str) and INI_VALUE.match(value))))
                 or (name == "colorsImport" and isinstance(value, bool))}
        if clean:
            result[directory] = clean
    return result


def gtk_restore_commands(saved, current):
    """[GTK_HELPER, "--gtk", DIR, JSON] for the saved values that differ now."""
    commands = []
    for directory, before in gtk_saved(saved).items():
        now = current.get(directory)
        if not isinstance(now, dict):
            continue
        changes = {name: value for name, value in before.items() if name in now and now[name] != value}
        if changes:
            commands.append([GTK_HELPER, "--gtk", directory, json.dumps(changes, separators=(",", ":"))])
    return commands


def should_restore(state):
    return isinstance(state, dict) and state.get("applied") is True and state.get("restoreOnLogout") is not False


def restore_commands(state, current=None, gtk_current=None):
    """Commands to run for a parsed state file; empty when there is nothing to do.

    With a colour backup, kdeglobals is restored from it (plus the palette
    notification) instead of re-applying the saved scheme. The GTK files come
    last, from the saved values (this helper writes them itself).
    """
    if not should_restore(state):
        return []
    commands = state.get("restore")
    commands = [command for command in commands if valid_command(command)] if isinstance(commands, list) else []
    saved = state.get("saved")
    gtk = []
    if gtk_saved(saved):
        gtk = gtk_restore_commands(saved, gtk_current if gtk_current is not None else gtk_snapshot())
    backup = backup_entries(saved)
    if backup is None:
        return commands + gtk
    kde = kde_restore_commands(backup, current if current is not None else snapshot()["entries"])
    if kde:
        kde.append(list(NOTIFY_COMMAND))
    return kde + [command for command in commands if command[0] != "plasma-apply-colorscheme"] + gtk


def forgotten(state):
    """State after a restore: nothing applied, the logout preference kept."""
    return {"version": 2, "applied": False, "restoreOnLogout": state.get("restoreOnLogout") is not False,
            "saved": None, "restore": []}


def write_atomic(path, text, mode=None):
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=".apptheme.")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
        if mode is not None:
            os.chmod(temporary, mode)
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
    parser.add_argument("--gtk-snapshot", action="store_true", help="print the GTK settings.ini keys and colors.css import as JSON")
    parser.add_argument("--gtk", nargs=2, metavar=("DIR", "JSON"), help="change gtk-3.0 or gtk-4.0 as JSON says")
    args = parser.parse_args(argv)

    if args.snapshot:
        print(json.dumps(snapshot(), separators=(",", ":")))
        return 0
    if args.gtk_snapshot:
        print(json.dumps(gtk_snapshot(), separators=(",", ":")))
        return 0

    if not args.dry_run and nested_environment():
        print("apptheme-restore: skipped in a nested test session", file=sys.stderr)
        return 0

    if args.gtk:
        try:
            values = json.loads(args.gtk[1])
            if args.dry_run:
                print(json.dumps([GTK_HELPER, "--gtk", args.gtk[0], json.dumps(values, separators=(",", ":"))]))
            else:
                apply_gtk(args.gtk[0], values)
        except (OSError, ValueError) as error:
            print(f"apptheme-restore: GTK files: {error}", file=sys.stderr)
            return 1
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
            if command[0] == GTK_HELPER:
                apply_gtk(command[2], json.loads(command[3]))
                failed, detail = False, ""
            else:
                result = subprocess.run(command, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                        text=True, env=env)
                failed = result.returncode != 0
                detail = result.stderr.strip()
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
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
