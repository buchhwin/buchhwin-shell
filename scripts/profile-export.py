#!/usr/bin/env python3
"""Write the running setup out as a built-in profile the repository ships.

    profile-export.py [--name buchhwin] [--out config/builtin-profiles/NAME]
                      [--profile PROFILE] [--dry-run]

Reads ${XDG_CONFIG_HOME:-~/.config}/buchhwin-shell/{settings,layout}.json, the
session's default terminal and file manager (default-apps.py's two lists) and
the fastfetch configuration (~/.config/fastfetch/config.jsonc + its logo), and
writes NAME/profile.json, NAME/fastfetch.jsonc and the logo next to it.

What goes in: the profile's five modes (layouts and the appearance each mode
owns), its notch, the notch presets and its lock screen's layout, and every
setting except what belongs to this machine or this person rather than to the
look (DROP: at least ProfileLogic.GLOBAL_SETTINGS - where the weather is,
hidden calendars, histories, onboarding, the screens, the keyboard layout and
the pointer, power and the fingerprint reader, the clipboard history, what the
login starts, updates, drives and how Alacritty windows start).
The profile in use is exported as it is set now; another one with the state it
keeps in layout.json (LayoutService, `state`), and one that has none yet is
refused rather than exported with the settings of the profile in use. Folder
paths under the home directory are written as "~/...", which SettingsService
expands. A picture chosen by name (the wallpaper, the login screen's) is
written empty: its file name is this machine's - the shipped profiles carried
~/Pictures/Desktop/wallpaper_hyprland.webp, a file no other machine has (nor,
by then, this one) - and an empty one gives way to the folder's first image.
A custom search address is written empty too (it can be an intranet's), and
the accent is written as it is set, never as "taken from the wallpaper": on
another machine that would be the colour of whatever image comes first there.

The result is checked before it is written: a value that looks like a
coordinate, an e-mail address, a path under /home or a Citrix app's id (it
carries the employer's farm and server names) stops the export, so the
repository's private-data rule (testing.md, pitfall 17) holds by construction.
"""
import argparse
import json
import os
import pathlib
import re
import sys

SESSION = "buchhwin-shell"

# Settings that describe this machine or this person, not the look: a setting
# or a whole group. Every entry of ProfileLogic.GLOBAL_SETTINGS is here (a
# profile never keeps those, so a shipped one must not carry them either;
# tests/python/profile_export_test.py holds the two lists together), and this
# may leave out more.
DROP = {
    "configVersion", "notch.headerAdopted", "desktop.quickSizesAdopted",
    "onboarding",
    "colorPicker.history",
    "weather.locationName", "weather.lat", "weather.lon", "weather.autoLocate",
    "wallpaper.recentFolders",
    "calendar.hiddenCalendars", "calendar.newEventCalendar",
    "display", "input.kbLayout", "input.kbVariant",
    "input.sensitivity", "input.accelProfile", "input.mouseNaturalScroll",
    "input.touchpadNaturalScroll", "input.touchpadScrollFactor", "input.tapToClick",
    "input.disableWhileTyping",
    "desktop.settingsMoveX", "desktop.settingsMoveY",
    "power", "lock.fingerprint", "dock.screens", "notch.screens",
    "clipboard", "autostart", "updates", "drives", "terminal.alacrittyDaemon",
    # A shipped profile has the dock off (the default dock and dock.* at
    # their defaults, ProfileLogic.completeLeaves): the dock is switched on
    # by whoever wants it, in the profile they want it in.
    "dock",
}
# Folders that are kept, home-relative.
PATHS = {"wallpaper.folder", "wallpaper.slideshowFolder", "recording.folder"}
# Pictures chosen by name: shipped empty (see above), wherever they are.
FILES = {"wallpaper.path", "login.wallpaper"}
# A search address of the user's own: an intranet's, or one with a token in
# it (IpcLogic.PRIVATE_SETTINGS keeps it to itself too). Shipped empty, and
# the custom engine it belongs to with it: an empty custom one searches
# nothing, so the profile takes the default engine instead.
PERSONAL = {"launcher.searchUrl"}
# A Citrix Workspace app's desktop id names the farm and the server it is
# published from ("Citrix_subscribed_XenApp 7.x.RDS-<name> $S..."), which is
# the employer's, not a look. It can sit among the launcher's pins.
CITRIX = re.compile(r"Citrix_")
# The appearance a mode owns travels with the modes (ProfileLogic.MODE_SCOPED).
MODE_SCOPED = {"blurStrength", "panelOpacity", "animationMode", "animationSpeed", "windowRadius",
               "shellRadius", "borderEnabled", "borderSize", "gapsIn", "gapsOut"}

COORDINATE = re.compile(r"[-+]?\d{1,3}\.\d{3,}\s*[,;]\s*[-+]?\d{1,3}\.\d{3,}")
# The shape the shell and Open-Meteo store a place in - a number under a "lat"
# or "lon" key - which the pair above never saw; scripts/lib/checks.py looks
# for the same.
COORDINATE_KEY = re.compile(r"\b(?:lat|lon|lng|latitude|longitude)\b[\"']?\s*[:=]\s*[\"']?[-+]?\d{1,3}\.\d{3,}",
                            re.IGNORECASE)
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def config_home():
    return pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")


def flatten(tree, prefix=""):
    out = {}
    for key, value in tree.items():
        path = prefix + key
        if isinstance(value, dict):
            out.update(flatten(value, path + "."))
        else:
            out[path] = value
    return out


def unflatten(flat):
    tree = {}
    for path, value in flat.items():
        node = tree
        parts = path.split(".")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return tree


def contract_home(value, home):
    text = str(value or "")
    if text == home:
        return "~"
    return "~" + text[len(home):] if home and text.startswith(home + "/") else text


def dropped(path):
    return any(path == entry or path.startswith(entry + ".") for entry in DROP)


def settings_of(raw, home):
    flat = flatten(raw)
    kept = {}
    for path, value in flat.items():
        if dropped(path):
            continue
        group, _, leaf = path.partition(".")
        if group == "appearance" and leaf in MODE_SCOPED:
            continue
        if path == "launcher.searchEngine" and value == "custom":
            continue
        if path in FILES or path in PERSONAL:
            value = ""
        elif path in PATHS:
            value = contract_home(value, home)
        elif path == "appearance.accentFromWallpaper":
            # The accent set now is the one the wallpaper gave; it travels as
            # it is (appearance.accent), and the wallpaper it came from stays.
            value = False
        kept[path] = value
    return unflatten(kept)


def default_apps(config):
    apps = {}
    terminals = config / (SESSION + "-xdg-terminals.list")
    if terminals.is_file():
        first = next((line.strip() for line in terminals.read_text(encoding="utf-8").splitlines()
                      if line.strip() and not line.startswith("#")), "")
        if first:
            apps["terminal"] = first
    mimes = config / (SESSION + "-mimeapps.list")
    if mimes.is_file():
        for line in mimes.read_text(encoding="utf-8").splitlines():
            if line.startswith("inode/directory="):
                value = line.split("=", 1)[1].split(";")[0].strip()
                if value:
                    apps["files"] = value
    return apps


def fastfetch_files(config):
    """(config text with the logo pointed at the shell's copy, logo name, logo text) or None."""
    source = config / "fastfetch" / "config.jsonc"
    if not source.is_file():
        return None
    text = source.read_text(encoding="utf-8")
    match = re.search(r'"source"\s*:\s*"([^"]+)"', text)
    logo_name, logo_text = "", ""
    if match:
        logo_path = pathlib.Path(os.path.expanduser(match.group(1)))
        if logo_path.is_file():
            logo_name = logo_path.name
            logo_text = logo_path.read_text(encoding="utf-8")
            # Applied, the logo sits beside the shell's fastfetch.jsonc.
            text = text.replace(match.group(1), "~/.config/buchhwin-shell/" + logo_name)
    return text, logo_name, logo_text


def private_findings(text, home):
    found = []
    if COORDINATE.search(text):
        found.append("a coordinate pair")
    if COORDINATE_KEY.search(text):
        found.append("a coordinate")
    if EMAIL.search(text):
        found.append("an e-mail address")
    if home and home in text:
        found.append("a path under " + home)
    if re.search(r"/home/[A-Za-z0-9_.-]+", text):
        found.append("a /home/<user> path")
    if CITRIX.search(text):
        found.append("a Citrix app id")
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--name", default="buchhwin")
    parser.add_argument("--out", default="")
    parser.add_argument("--profile", default="", help="the layout profile to export (default: the active one)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    home = str(pathlib.Path.home())
    config = config_home()
    shell_config = config / SESSION
    try:
        settings = json.loads((shell_config / "settings.json").read_text(encoding="utf-8"))
        layout = json.loads((shell_config / "layout.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": "cannot read the configuration: %s" % error}))
        return 1
    active = layout.get("activeProfile") or "default"
    name = args.profile or active
    source = (layout.get("profiles") or {}).get(name)
    if not isinstance(source, dict) or not isinstance(source.get("modes"), dict):
        print(json.dumps({"ok": False, "error": "no profile %r in layout.json" % name}))
        return 1
    # The settings, notch and lock screen in use belong to the active profile;
    # any other keeps its own in its state.
    notch, lock = layout.get("notch") or {}, layout.get("lock") or {}
    if name != active:
        state = source.get("state")
        if not isinstance(state, dict) or not isinstance(state.get("settings"), dict):
            print(json.dumps({"ok": False, "error": "profile %r keeps no state yet: switch to it once, "
                                                    "or export it while it is in use" % name}))
            return 1
        settings = state["settings"]
        notch = state.get("notch") or notch
        lock = state.get("lock") or lock
    label = source.get("label") if isinstance(source.get("label"), str) and source.get("label").strip() else args.name

    profile = {
        "configVersion": 1,
        "id": args.name,
        "label": label,
        "modes": source["modes"],
        "notch": notch,
        "notchPresets": layout.get("notchPresets") or [],
        "lock": lock,
        "settings": settings_of(settings, home),
        "defaultApps": default_apps(config),
    }
    fastfetch = fastfetch_files(config)
    if fastfetch:
        profile["fastfetch"] = {"config": "fastfetch.jsonc", "logo": fastfetch[1]}

    text = json.dumps(profile, indent=2, ensure_ascii=False) + "\n"
    findings = private_findings(text, home) + (private_findings(fastfetch[0], home) if fastfetch else [])
    if findings:
        print(json.dumps({"ok": False, "error": "refusing to write private data: " + ", ".join(sorted(set(findings)))}))
        return 1

    out = pathlib.Path(args.out) if args.out else pathlib.Path(__file__).resolve().parent.parent / "config" / "builtin-profiles" / args.name
    written = [str(out / "profile.json")]
    if not args.dry_run:
        out.mkdir(parents=True, exist_ok=True)
        (out / "profile.json").write_text(text, encoding="utf-8")
        if fastfetch:
            (out / "fastfetch.jsonc").write_text(fastfetch[0], encoding="utf-8")
            written.append(str(out / "fastfetch.jsonc"))
            if fastfetch[1]:
                (out / fastfetch[1]).write_text(fastfetch[2], encoding="utf-8")
                written.append(str(out / fastfetch[1]))
    print(json.dumps({"ok": True, "profile": name, "written": written, "dryRun": args.dry_run,
                      "settings": len(flatten(profile["settings"])), "defaultApps": profile["defaultApps"]}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
