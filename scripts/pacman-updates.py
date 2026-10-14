#!/usr/bin/env python3
"""Arch's update list in the shape of dnf5's, for scripts/updates-check.sh.

Settings > Updates parses `dnf5 check-upgrade --json` (services/updates/
UpdatesLogic.js). On Arch the same sections are filled from `checkupdates`
(pacman-contrib) and an AUR helper's `-Qua`, both "name old -> new" lines,
converted here, so the parser and the page stay one and the same on every
distribution:

    pacman-updates.py json REPOS CHECKUPDATES [AUR]
        {"upgrades": [{"name", "arch", "evr", "repository"}]}; REPOS is
        `pacman -Sl` against the database checkupdates synced ("repo name
        version [installed]" lines), which names each package's repository;
        packages from AUR are "aur".
    pacman-updates.py installed CHECKUPDATES [AUR]
        "name.arch<TAB>old" lines, the @installed section.

pacman lists no architecture per update, so every entry carries the
machine's (`uname -m`): the key only has to be the same in both sections.
Exits 1 without output when a file cannot be read.
"""

import json
import platform
import re
import sys

# pacman's own rule for package names, so nothing else reaches the page.
NAME = re.compile(r"^[A-Za-z0-9@_+][A-Za-z0-9@._+-]*$")
LINE = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)")


def updates(text):
    """"name old -> new" lines → [(name, old, new)]; anything else is skipped
    (warnings, the helper's chatter). A package held back with IgnorePkg is
    marked "[ignored]" and is not an update anyone is going to install, so it
    is left out too - Citrix pinned to a version that works, for one."""
    result = []
    for line in str(text or "").splitlines():
        match = LINE.match(line.strip())
        if match and NAME.match(match.group(1)) and not line.rstrip().endswith("[ignored]"):
            result.append(match.groups())
    return result


def repositories(text):
    """`pacman -Sl` lines → {name: repository}."""
    result = {}
    for line in str(text or "").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            result.setdefault(parts[1], parts[0])
    return result


def convert(repos_text, pacman_text, aur_text="", arch=None):
    arch = arch or platform.machine() or "x86_64"
    repos = repositories(repos_text)
    upgrades, seen = [], set()
    for source, text in (("", pacman_text), ("aur", aur_text)):
        for name, _old, new in updates(text):
            if name in seen:
                continue
            seen.add(name)
            upgrades.append({"name": name, "arch": arch, "evr": new,
                             "repository": source or repos.get(name, "")})
    return {"upgrades": upgrades}


def installed(pacman_text, aur_text="", arch=None):
    arch = arch or platform.machine() or "x86_64"
    lines, seen = [], set()
    for text in (pacman_text, aur_text):
        for name, old, _new in updates(text):
            if name not in seen:
                seen.add(name)
                lines.append(f"{name}.{arch}\t{old}")
    return lines


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def main(argv):
    try:
        if len(argv) in (4, 5) and argv[1] == "json":
            aur = read(argv[4]) if len(argv) == 5 else ""
            print(json.dumps(convert(read(argv[2]), read(argv[3]), aur)))
            return 0
        if len(argv) in (3, 4) and argv[1] == "installed":
            aur = read(argv[3]) if len(argv) == 4 else ""
            for line in installed(read(argv[2]), aur):
                print(line)
            return 0
    except OSError as error:
        print(error, file=sys.stderr)
        return 1
    print("usage: pacman-updates.py json REPOS CHECKUPDATES [AUR] | installed CHECKUPDATES [AUR]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
