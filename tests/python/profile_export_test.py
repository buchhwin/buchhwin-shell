#!/usr/bin/env python3
"""Unit test for scripts/profile-export.py against a temporary HOME.

The export writes into the repository unless it is given --out, so every run
here names a temporary directory, and HOME / XDG_CONFIG_HOME point at fake
files: a weather place with coordinates, a wallpaper under the home directory,
the session's default apps and a fastfetch config with its logo. Coordinates in
these fixtures have at most three decimals, or the suite's private-data check
would trip over this file.
"""

import contextlib
import importlib.util
import io
import json
import os
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("profile_export", ROOT / "scripts" / "profile-export.py")
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
    return status, json.loads(lines[-1]) if lines else {}


def js_list(name):
    """The strings of `var NAME = [...]` in services/profile/ProfileLogic.js."""
    text = (ROOT / "services" / "profile" / "ProfileLogic.js").read_text(encoding="utf-8")
    match = re.search(r"^var " + name + r" = \[(.*?)\]", text, re.S | re.M)
    return re.findall(r'"([^"]+)"', match.group(1)) if match else []


# ---- the export leaves out at least what a profile never keeps -----------------
# ProfileLogic.GLOBAL_SETTINGS is the shell's list of settings that belong to
# the machine or the person; a shipped profile carrying one would set it on
# every machine that activates the profile.
global_settings = js_list("GLOBAL_SETTINGS")
check(len(global_settings) > 5, "ProfileLogic.GLOBAL_SETTINGS is found: %r" % global_settings)
for entry in global_settings:
    check(module.dropped(entry) and module.dropped(entry + ".leaf"),
          "the export drops %s (and what is under it), as ProfileLogic.GLOBAL_SETTINGS does" % entry)
check(not module.dropped("displayX") and not module.dropped("notch.displayOsd"), "a group is matched whole")
check(set(js_list("MODE_SCOPED")) == module.MODE_SCOPED, "the mode-scoped leaves are ProfileLogic.MODE_SCOPED")

# The shipped profiles themselves: edited by hand as well as written by the
# export, and a global setting in one is set on every machine that uses it.
for shipped in sorted((ROOT / "config" / "builtin-profiles").glob("*/profile.json")):
    carried = [path for path in module.flatten(json.loads(shipped.read_text(encoding="utf-8")).get("settings") or {})
               if module.dropped(path)]
    check(carried == [], "%s carries no global setting: %r" % (shipped.parent.name, carried))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    home = base / "home"
    config = home / ".config"
    shell = config / "buchhwin-shell"
    os.environ.update({"HOME": str(home), "XDG_CONFIG_HOME": str(config)})

    settings = {
        "configVersion": 1,
        "appearance": {"accent": "#50e2cb", "blurStrength": 0.9, "gapsIn": 3, "theme": "dark"},
        "weather": {"enabled": True, "locationName": "Exampletown", "lat": 12.34, "lon": 56.78, "unit": "celsius"},
        "wallpaper": {"path": str(home / "Pictures" / "w.webp"), "folder": "", "recentFolders": str(home / "Pictures")},
        "onboarding": {"completed": True},
        "colorPicker": {"history": "#112233,#445566"},
        "recording": {"folder": "~/Videos/Recordings"},
        "input": {"kbLayout": "de", "repeatRate": 30},
        "display": {"x11Scale": 1.5},
        "notch": {"headerAdopted": True, "bodyHeight": 32},
        "power": {"lowBatteryLevel": 20, "ac": {"lidAction": "nothing"}},
        "lock": {"fingerprint": "on", "showAvatar": True},
    }
    layout = {
        "configVersion": 3, "activeProfile": "default", "activeMode": "work",
        "profiles": {"default": {"label": "Default", "modes": {
            "work": {"widgets": [], "groups": [], "screens": ["DP-1"], "desktopMode": "notch",
                     "appearance": {"blurStrength": 0.9, "gapsIn": 3}}}}},
        "notch": {"collapsed": [], "expanded": []}, "notchPresets": [], "lock": {"lock": []},
    }
    write_json(shell / "settings.json", settings)
    write_json(shell / "layout.json", layout)
    (config / "buchhwin-shell-xdg-terminals.list").write_text("# chosen in Settings\nAlacritty.desktop\n", encoding="utf-8")
    (config / "buchhwin-shell-mimeapps.list").write_text(
        "[Default Applications]\ninode/directory=org.kde.dolphin.desktop;\n", encoding="utf-8")
    (config / "fastfetch").mkdir(parents=True)
    (config / "fastfetch" / "saturn.txt").write_text("  ( o )\n", encoding="utf-8")
    (config / "fastfetch" / "config.jsonc").write_text(
        '{\n  // the planet\n  "logo": { "type": "file", "source": "~/.config/fastfetch/saturn.txt" },\n'
        '  "modules": ["os"]\n}\n', encoding="utf-8")

    # ---- a clean export --------------------------------------------------------
    out = base / "out"
    status, answer = run("--name", "test", "--out", str(out))
    check(status == 0 and answer.get("ok") is True, "a clean setup exports: %r" % answer)
    profile = json.loads((out / "profile.json").read_text(encoding="utf-8"))
    check(profile["id"] == "test" and profile["configVersion"] == 1, "under the name asked for, with a configVersion")
    weather = profile["settings"]["weather"]
    check("lat" not in weather and "lon" not in weather and "locationName" not in weather,
          "the place and its coordinates are dropped")
    check(weather.get("unit") == "celsius", "the rest of the weather group stays")
    check(profile["settings"]["wallpaper"]["path"] == "~/Pictures/w.webp", "a path under the home directory is contracted to ~")
    check("recentFolders" not in profile["settings"]["wallpaper"], "recent folders are this machine's")
    check("onboarding" not in profile["settings"] and "colorPicker" not in profile["settings"],
          "onboarding and the colour history are dropped")
    check("configVersion" not in profile["settings"], "settings.json's own version is not a setting")
    check("blurStrength" not in profile["settings"]["appearance"] and "gapsIn" not in profile["settings"]["appearance"],
          "the mode-scoped appearance travels with the modes, not with the settings")
    check(profile["settings"]["appearance"]["accent"] == "#50e2cb", "the accent is a setting")
    check(profile["settings"]["input"] == {"repeatRate": 30}, "the keyboard layout is this machine's, the repeat rate is not")
    check("display" not in profile["settings"], "the screens are this machine's")
    check(profile["settings"]["notch"] == {"bodyHeight": 32}, "a one-shot marker is this machine's files'")
    check("power" not in profile["settings"], "power - the lid, sleep, the battery - is this machine's")
    check(profile["settings"]["lock"] == {"showAvatar": True}, "and so is the fingerprint reader, the rest of the lock screen is not")
    check("autoLocate" not in weather, "asking where this machine is goes with the place")
    check(profile["label"] == "Default", "the label is the profile's own")
    check(profile["modes"]["work"]["appearance"] == {"blurStrength": 0.9, "gapsIn": 3}, "the modes keep their appearance")
    check(profile["defaultApps"] == {"terminal": "Alacritty.desktop", "files": "org.kde.dolphin.desktop"},
          "the session's terminal and file manager")
    check(profile.get("fastfetch") == {"config": "fastfetch.jsonc", "logo": "saturn.txt"}, "fastfetch named")
    fastfetch = (out / "fastfetch.jsonc").read_text(encoding="utf-8")
    check('"source": "~/.config/buchhwin-shell/saturn.txt"' in fastfetch, "the logo points at the shell's copy")
    check("// the planet" in fastfetch, "comments in the fastfetch config survive")
    check((out / "saturn.txt").read_text(encoding="utf-8") == "  ( o )\n", "the logo is written beside it")
    check(str(home) not in (out / "profile.json").read_text(encoding="utf-8"), "the home directory appears nowhere")

    # ---- --dry-run writes nothing ----------------------------------------------
    dry = base / "dry"
    status, answer = run("--out", str(dry), "--dry-run")
    check(status == 0 and answer.get("dryRun") is True and not dry.exists(), "a dry run writes nothing")

    # ---- an unexpected private value stops the export --------------------------
    def refused(field, value, label):
        changed = json.loads(json.dumps(settings))
        group, leaf = field.split(".")
        changed.setdefault(group, {})[leaf] = value
        write_json(shell / "settings.json", changed)
        target = base / ("refused-" + label)
        status, answer = run("--out", str(target))
        check(status == 1 and answer.get("ok") is False, label + ": the export refuses")
        check(not target.exists(), label + ": and writes nothing")
        return answer.get("error", "")

    error = refused("launcher.searchUrl", "https://search.invalid/?q=%s&from=someone@example.org", "email")
    check("e-mail" in error, "an e-mail address in a field is named: %r" % error)
    error = refused("autostart.apps", "/home/someone/bin/tool.desktop", "home")
    check("/home/<user>" in error, "another user's /home path in a field is named: %r" % error)
    error = refused("terminal.symbol", "12.345, 67.890", "coordinate")
    check("coordinate" in error, "a coordinate pair in a field is named: %r" % error)
    error = refused("autostart.apps", str(home / "bin" / "x.desktop"), "own-home")
    check(str(home) in error or "/home" in error or "path under" in error,
          "a path under the home directory outside the known path fields is named: %r" % error)

    # ---- a profile that is not in use: its own state -----------------------------
    stored = {"settings": {"appearance": {"accent": "#0a0b0c", "panelColor": "#202020"},
                           "wallpaper": {"path": str(home / "Pictures" / "other.webp")}},
              "notch": {"collapsed": [{"id": "n1", "items": [{"type": "clock"}]}], "expanded": []},
              "lock": {"lock": [{"id": "l1", "items": [{"type": "clock"}]}]}}
    two = dict(layout, profiles=dict(layout["profiles"], studio={"label": "Studio", "modes": {}, "state": stored},
                                     bare={"label": "Bare", "modes": {}}))
    write_json(shell / "layout.json", two)
    write_json(shell / "settings.json", settings)
    status, answer = run("--name", "studio", "--profile", "studio", "--out", str(base / "studio"))
    check(status == 0 and answer.get("ok") is True, "a profile not in use exports: %r" % answer)
    exported = json.loads((base / "studio" / "profile.json").read_text(encoding="utf-8"))
    check(exported["settings"]["appearance"] == {"accent": "#0a0b0c", "panelColor": "#202020"},
          "with the settings it keeps, not the ones in use")
    check(exported["settings"]["wallpaper"]["path"] == "~/Pictures/other.webp", "home paths contracted there too")
    check(exported["notch"] == stored["notch"] and exported["lock"] == stored["lock"], "its notch and lock screen")
    check(exported["label"] == "Studio", "under its label")
    status, answer = run("--profile", "bare", "--out", str(base / "bare"))
    check(status == 1 and "no state" in answer.get("error", "") and not (base / "bare").exists(),
          "one that keeps no state yet is refused rather than given the settings in use: %r" % answer)

    # ---- nothing to export -----------------------------------------------------
    write_json(shell / "layout.json", dict(layout, activeProfile="gone", profiles={}))
    write_json(shell / "settings.json", settings)
    status, answer = run("--out", str(base / "none"))
    check(status == 1 and "no profile" in answer.get("error", ""), "a layout without the profile is an error, not an empty export")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED profile_export_test")
    sys.exit(1)
print("TESTS PASSED profile_export_test")
