#!/usr/bin/env python3
"""Unit test for scripts/apptheme-restore.py with synthetic state files (stub tools only)."""

import importlib.util
import inspect
import io
import json
import os
import pathlib
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("apptheme_restore", ROOT / "scripts" / "apptheme-restore.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


SCHEME = ["plasma-apply-colorscheme", "BreezeLight"]
COLOR = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"]
THEME = ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "adw-gtk3-dark"]
SAVED = {"colorScheme": "BreezeLight", "gtkColorScheme": "prefer-dark", "gtkTheme": "adw-gtk3-dark"}

# Allowed commands only.
for command in (SCHEME, COLOR, THEME):
    check(module.valid_command(command), f"allowed: {command}")
for command in (["rm", "-rf", "/"], ["plasma-apply-colorscheme", "--help"], ["plasma-apply-colorscheme"],
                ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", "x"],
                ["gsettings", "reset", "org.gnome.desktop.interface", "gtk-theme", "x"],
                ["gsettings", "set", "org.gnome.desktop.wm.preferences", "theme", "x"],
                ["plasma-apply-colorscheme", ""], "plasma-apply-colorscheme BreezeLight", [SCHEME]):
    check(not module.valid_command(command), f"refused: {command}")

# What to restore.
state = {"version": 1, "applied": True, "restoreOnLogout": True, "saved": SAVED, "restore": [SCHEME, ["sh", "-c", "x"], THEME]}
check(module.restore_commands(state) == [SCHEME, THEME], "invalid commands dropped")
check(module.restore_commands({**state, "restoreOnLogout": False}) == [], "restore at logout turned off")
check(module.restore_commands({**state, "applied": False}) == [], "nothing applied")
check(module.restore_commands({**state, "applied": "true"}) == [], "applied must be a boolean")
check(module.restore_commands({**state, "restore": "plasma-apply-colorscheme"}) == [], "restore must be a list")
check(module.restore_commands([]) == [] and module.restore_commands(None) == [], "not an object")
check(module.forgotten(state) == {"version": 2, "applied": False, "restoreOnLogout": True, "saved": None, "restore": []},
      "forgotten state")
check(module.forgotten({"restoreOnLogout": False})["restoreOnLogout"] is False, "logout preference kept")

with tempfile.TemporaryDirectory() as scratch:
    path = pathlib.Path(scratch) / "apptheme.json"
    path.write_text(json.dumps(state))
    # Dry run prints the commands and keeps the file.
    output = io.StringIO()
    with redirect_stdout(output):
        status = module.main(["--state", str(path), "--dry-run"])
    check(status == 0, "dry run status")
    check([json.loads(line) for line in output.getvalue().splitlines()] == [SCHEME, THEME], "dry run output")
    check(json.loads(path.read_text()) == state, "dry run keeps the state file")

    # A nested session never runs anything, even with a real state file.
    previous = os.environ.get("BUCHHWIN_NESTED")
    os.environ["BUCHHWIN_NESTED"] = "1"
    try:
        with redirect_stderr(io.StringIO()):
            check(module.main(["--state", str(path)]) == 0, "nested status")
        check(json.loads(path.read_text()) == state, "nested keeps the state file")
    finally:
        if previous is None:
            os.environ.pop("BUCHHWIN_NESTED")
        else:
            os.environ["BUCHHWIN_NESTED"] = previous

    # Missing or broken files are fine.
    check(module.main(["--state", str(pathlib.Path(scratch) / "missing.json"), "--dry-run"]) == 0, "missing file")
    broken = pathlib.Path(scratch) / "broken.json"
    broken.write_text("{")
    check(module.main(["--state", str(broken), "--dry-run"]) == 0, "broken file")

    # A real run with stub tools: PATH holds only the stub folder, so the host's
    # plasma-apply-colorscheme and gsettings can never be reached.
    stubs = pathlib.Path(scratch) / "stubs"
    stubs.mkdir()
    log = pathlib.Path(scratch) / "calls.log"

    def run_with_stubs(gsettings_code):
        for name, code in (("plasma-apply-colorscheme", 0), ("gsettings", gsettings_code)):
            stub = stubs / name
            stub.write_text(f'#!/bin/sh\necho "{name} $*" >> "{log}"\nexit {code}\n')
            stub.chmod(0o755)
        previous_path = os.environ.get("PATH", "")
        previous_nested = os.environ.pop("BUCHHWIN_NESTED", None)
        os.environ["PATH"] = str(stubs)
        try:
            with redirect_stderr(io.StringIO()) as errors:
                status = module.main(["--state", str(path)])
        finally:
            os.environ["PATH"] = previous_path
            if previous_nested is not None:
                os.environ["BUCHHWIN_NESTED"] = previous_nested
        calls = log.read_text().splitlines() if log.exists() else []
        log.unlink(missing_ok=True)
        return status, errors.getvalue(), calls

    expected_calls = ["plasma-apply-colorscheme BreezeLight", "gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark"]
    status, errors, calls = run_with_stubs(3)
    check(calls == expected_calls, "stub commands ran in order")
    check(status == 1 and "gsettings failed" in errors, "failing command reported")
    check(json.loads(path.read_text()) == state, "failed restore keeps the saved values")
    status, errors, calls = run_with_stubs(0)
    check(calls == expected_calls and status == 0, "restore succeeded")
    check(json.loads(path.read_text()) == module.forgotten(state), "state forgotten after the restore")
    check(sorted(p.name for p in pathlib.Path(scratch).iterdir()) == ["apptheme.json", "broken.json", "stubs"],
          "no temporary files")
    status, errors, calls = run_with_stubs(0)
    check(status == 0 and calls == [], "second logout: nothing to restore")

# ---- kdeglobals colour backup ------------------------------------------------
PLASMA_KDEGLOBALS = """[ColorEffects:Disabled]
ChangeSelectionColor=
Color=56,56,56
ContrastAmount=-0.65

[Colors:Button]
DecorationFocus=61,174,233
ForegroundNormal=252,252,252

[Colors:Header][Inactive]
BackgroundNormal=32,35,38

[Colors:View][$i]
BackgroundNormal=1,2,3

[General]
BrowserApplication=brave-browser.desktop
ColorSchemeHash=0efb452114ece4d3338057cb89f434aff85d80d0
Name[de]=Breeze
TerminalApplication=kitty

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
frameContrast=0.2

[KFileDialog Settings]
Sort by=Name

[WM]
activeBackground=39,44,49
activeFont=Noto Sans\\,10
"""
BACKUP = [
    [["ColorEffects:Disabled"], "ChangeSelectionColor", ""],
    [["ColorEffects:Disabled"], "Color", "56,56,56"],
    [["ColorEffects:Disabled"], "ContrastAmount", "-0.65"],
    [["Colors:Button"], "DecorationFocus", "61,174,233"],
    [["Colors:Button"], "ForegroundNormal", "252,252,252"],
    [["Colors:Header", "Inactive"], "BackgroundNormal", "32,35,38"],
    [["General"], "ColorSchemeHash", "0efb452114ece4d3338057cb89f434aff85d80d0"],
    [["KDE"], "frameContrast", "0.2"],
    [["WM"], "activeBackground", "39,44,49"],
]
check(module.parse_kdeglobals(PLASMA_KDEGLOBALS) == BACKUP,
      "colour entries only: no immutable groups, localized keys, escaped values or other settings")
check(module.parse_kdeglobals("") == [] and module.parse_kdeglobals("key=value\n[General\nColorScheme=x") == [], "empty or broken files")
for entry in BACKUP:
    check(module.valid_entry(entry), f"valid entry {entry}")
for entry in ([["General"], "BrowserApplication", "x"], [["WM"], "x", "a\nb"], [["Colors:View", "A", "B"], "k", "v"],
              [["WM", "Inactive"], "k", "v"], [["Colors:View"], "k[de]", "v"], [["Colors:View"], "k", 3], "junk"):
    check(not module.valid_entry(entry), f"invalid entry {entry}")


def kwrite(group, key, value=None):
    command = ["kwriteconfig6", "--file", "kdeglobals"]
    for part in group:
        command += ["--group", part]
    return command + ["--key", key] + (["--delete", "--", ""] if value is None else ["--", value])


# Same case as tests/qml/AppThemeTest.qml: the JS plan and this helper agree.
js_backup = [[["Colors:Button"], "DecorationFocus", "61,174,233"], [["Colors:Header", "Inactive"], "BackgroundNormal", "32,35,38"],
             [["ColorEffects:Disabled"], "Enable", ""], [["General"], "ColorSchemeHash", "0efb"], [["WM"], "activeBackground", "39,44,49"]]
js_changed = [[["Colors:Button"], "DecorationFocus", "231,180,60"], [["General"], "AccentColor", "231,180,60"],
              [["Colors:Header", "Inactive"], "BackgroundNormal", "32,35,38"], [["WM"], "activeBackground", "-0.5"]]
check(module.kde_restore_commands(js_backup, js_changed) == [
    kwrite(["General"], "AccentColor"), kwrite(["Colors:Button"], "DecorationFocus", "61,174,233"),
    kwrite(["ColorEffects:Disabled"], "Enable", ""), kwrite(["General"], "ColorSchemeHash", "0efb"),
    kwrite(["WM"], "activeBackground", "39,44,49")], "restore commands match the JS plan")
check(module.kde_restore_commands(BACKUP, BACKUP) == [], "nothing changed")

# The accent run of plasma-apply-colorscheme as seen in kdeglobals.
ACCENTED = PLASMA_KDEGLOBALS.replace("DecorationFocus=61,174,233", "DecorationFocus=231,180,60").replace(
    "[General]\n", "[General]\nAccentColor=231,180,60\nColorScheme=BreezeDark\n").replace(
    "[WM]\n", "[WM]\nactiveBlend=231,180,60\n")
backup_state = {"version": 2, "applied": True, "restoreOnLogout": True,
                "saved": {"colorScheme": "BreezeDark", "accentColor": "", "kdeColors": {"entries": BACKUP + ["junk"]},
                          "gtkColorScheme": "prefer-dark", "gtkTheme": "Breeze-Dark"},
                "restore": [SCHEME, THEME]}
expected_kde = [kwrite(["General"], "AccentColor"), kwrite(["General"], "ColorScheme"), kwrite(["WM"], "activeBlend"),
                kwrite(["Colors:Button"], "DecorationFocus", "61,174,233")]
check(module.restore_commands(backup_state, module.parse_kdeglobals(ACCENTED)) == expected_kde + [module.NOTIFY_COMMAND, THEME],
      "backup restore: kdeglobals entries, notification, GNOME keys, no scheme re-apply")
check(module.restore_commands(backup_state, BACKUP) == [THEME], "backup already in place: only the GNOME keys")
check(module.restore_commands({**backup_state, "restoreOnLogout": False}, module.parse_kdeglobals(ACCENTED)) == [], "backup: restore off")


def apply_kwrite(path, argv):
    """Minimal kwriteconfig6 for tests: edits an INI file like KConfig (sorted keys)."""
    groups, key, delete, value, index = [], None, False, None, 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--file":
            index += 1
        elif arg == "--group":
            index += 1
            groups.append(argv[index])
        elif arg == "--key":
            index += 1
            key = argv[index]
        elif arg == "--delete":
            delete = True
        elif arg == "--":
            value = argv[index + 1]
            break
        index += 1
    data, order, current = {}, [], None
    for line in path.read_text().splitlines():
        if line.startswith("["):
            current = line
            data.setdefault(current, {})
            order.append(current)
        elif "=" in line and current:
            name, text = line.split("=", 1)
            data[current][name] = text
    header = "".join(f"[{part}]" for part in groups)
    if header not in data:
        data[header] = {}
        order.append(header)
    if delete:
        data[header].pop(key, None)
    else:
        data[header][key] = value
    blocks = [header_name + "\n" + "".join(f"{k}={v}\n" for k, v in sorted(data[header_name].items()))
              for header_name in sorted(set(order)) if data[header_name]]
    path.write_text("\n".join(blocks))


with tempfile.TemporaryDirectory() as scratch:
    scratch = pathlib.Path(scratch)
    config = scratch / "config"
    config.mkdir()
    (config / "kdeglobals").write_text(ACCENTED)
    previous_config = os.environ.get("XDG_CONFIG_HOME")
    previous_dirs = os.environ.get("XDG_CONFIG_DIRS")
    os.environ["XDG_CONFIG_HOME"] = str(config)
    os.environ.pop("XDG_CONFIG_DIRS", None)
    try:
        # --snapshot prints the backup of the current file (read-only).
        output = io.StringIO()
        with redirect_stdout(output):
            check(module.main(["--snapshot"]) == 0, "snapshot status")
        check(json.loads(output.getvalue()) == {"entries": module.parse_kdeglobals(ACCENTED)}, "snapshot output")
        check((config / "kdeglobals").read_text() == ACCENTED, "snapshot keeps kdeglobals")
        check(module.snapshot(config / "missing") == {"entries": []}, "missing kdeglobals: empty backup")
        env = module.command_environment()
        check(env["XDG_CONFIG_DIRS"] == f"{config}/kdedefaults:/etc/xdg", "commands see Plasma's kdedefaults")

        # Real run with stubs: kwriteconfig6 edits the sandbox file, the palette
        # notification fails (no bus) without failing the restore.
        stubs = scratch / "stubs"
        stubs.mkdir()
        log = scratch / "calls.log"
        stub_kwrite = scratch / "kwrite.py"
        stub_kwrite.write_text("import os, pathlib, sys\n\n" + inspect.getsource(apply_kwrite)
                               + "\napply_kwrite(pathlib.Path(os.environ['XDG_CONFIG_HOME']) / 'kdeglobals', sys.argv[1:])\n")
        for name, body in (("kwriteconfig6", f'echo "kwriteconfig6 $XDG_CONFIG_DIRS $*" >> "{log}"\nexec {sys.executable} "{stub_kwrite}" "$@"\n'),
                           ("dbus-send", f'echo "dbus-send $*" >> "{log}"\nexit 1\n'),
                           ("gsettings", f'echo "gsettings $*" >> "{log}"\nexit 0\n'),
                           ("plasma-apply-colorscheme", f'echo "plasma-apply-colorscheme $*" >> "{log}"\nexit 0\n')):
            stub = stubs / name
            stub.write_text(f"#!/bin/sh\n{body}")
            stub.chmod(0o755)
        state_file = scratch / "apptheme.json"
        state_file.write_text(json.dumps(backup_state))
        previous_path = os.environ.get("PATH", "")
        previous_nested = os.environ.pop("BUCHHWIN_NESTED", None)
        os.environ["PATH"] = str(stubs)
        try:
            with redirect_stderr(io.StringIO()) as errors:
                status = module.main(["--state", str(state_file)])
        finally:
            os.environ["PATH"] = previous_path
            if previous_nested is not None:
                os.environ["BUCHHWIN_NESTED"] = previous_nested
        calls = log.read_text().splitlines()
        check(status == 0, f"backup restore succeeded: {errors.getvalue()}")
        check("dbus-send failed" in errors.getvalue(), "missing bus reported")
        check(len([call for call in calls if call.startswith("kwriteconfig6")]) == 4, "four kdeglobals entries restored")
        check(all(f"{config}/kdedefaults:" in call for call in calls if call.startswith("kwriteconfig6")),
              "kwriteconfig6 runs with Plasma's config dirs")
        check(not any(call.startswith("plasma-apply-colorscheme") for call in calls), "no scheme re-apply with a backup")
        check(calls[-1] == "gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark", "GNOME key after the colours")
        check(module.parse_kdeglobals((config / "kdeglobals").read_text()) == BACKUP, "kdeglobals colours equal the backup again")
        restored = (config / "kdeglobals").read_text()
        check("BrowserApplication=brave-browser.desktop" in restored and "Sort by=Name" in restored, "other settings untouched")
        check(json.loads(state_file.read_text()) == module.forgotten(backup_state), "backup state forgotten")
    finally:
        for name, value in (("XDG_CONFIG_HOME", previous_config), ("XDG_CONFIG_DIRS", previous_dirs)):
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED apptheme_restore_test")
    sys.exit(1)
print("TESTS PASSED apptheme_restore_test")
