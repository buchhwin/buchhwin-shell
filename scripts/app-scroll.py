#!/usr/bin/env python3
"""Scroll sensitivity for apps that scroll with their own factor.

The compositor's touchpad scroll factor (Settings > Input) reaches every app,
but some apps multiply it again: VS Code scrolls far more per step than Qt
apps. This helper adjusts the app's own setting instead, keeping everything
else in the file untouched.

    scripts/app-scroll.py status [--factor F]     what is set now (JSON)
    scripts/app-scroll.py apply --factor F        write the matching values
    scripts/app-scroll.py reset                   remove the keys again

`--factor` is the shell's touchpad scroll factor (0.2-2, 1 = unchanged); the
app value is its inverse, so a faster compositor factor does not add up. Every
write keeps a `<file>.buchhwin-backup` copy of the first version it changed.
Only VS Code (`~/.config/Code/User/settings.json`, JSON with comments) is
handled: Chromium and Brave have no scroll sensitivity setting.
"""
import argparse
import json
import os
import re
import sys

KEYS = ("editor.mouseWheelScrollSensitivity", "workbench.list.mouseWheelScrollSensitivity")
MIN_FACTOR, MAX_FACTOR = 0.2, 2.0


def code_settings_path():
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(config, "Code", "User", "settings.json")


def app_value(factor):
    """App sensitivity for a compositor factor: the inverse, clamped and rounded."""
    factor = max(MIN_FACTOR, min(MAX_FACTOR, float(factor)))
    return round(1.0 / factor, 2)


def strip_comments(text):
    """JSON with // and /* */ comments and trailing commas (VS Code writes those)."""
    out, i, in_string, escape = [], 0, False, False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            i += 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(char)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def read_settings(path):
    if not os.path.exists(path):
        return None, "missing"
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        data = json.loads(strip_comments(text) or "{}")
        if not isinstance(data, dict):
            return None, "unreadable"
        return data, ""
    except (OSError, ValueError):
        return None, "unreadable"


def write_settings(path, data):
    """Write the whole file as plain JSON; comments cannot be kept."""
    backup = path + ".buchhwin-backup"
    if not os.path.exists(backup) and os.path.exists(path):
        with open(path, encoding="utf-8") as source, open(backup, "w", encoding="utf-8") as target:
            target.write(source.read())
    temporary = path + ".buchhwin-new"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=4, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary, path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "apply", "reset"))
    parser.add_argument("--factor", type=float, default=1.0)
    parser.add_argument("--path", default=None, help="settings.json to use (tests)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    path = args.path or code_settings_path()
    data, problem = read_settings(path)
    wanted = app_value(args.factor)
    current = None if data is None else data.get(KEYS[0])
    report = {"app": "vscode", "path": path, "problem": problem, "current": current,
              "wanted": None if args.action == "reset" else wanted}

    if args.action == "status" or args.dry_run or data is None:
        report["changed"] = False
        if data is None:
            report["problem"] = problem or "missing"
        print(json.dumps(report))
        return 0 if args.action == "status" or args.dry_run else 1

    if args.action == "apply":
        changed = any(data.get(key) != wanted for key in KEYS)
        for key in KEYS:
            data[key] = wanted
    else:
        changed = any(key in data for key in KEYS)
        for key in KEYS:
            data.pop(key, None)
    if changed:
        write_settings(path, data)
    report["changed"] = changed
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
