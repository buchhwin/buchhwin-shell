#!/usr/bin/env python3
"""zypper's update list in the shape of dnf5's, for scripts/updates-check.sh.

Settings > Updates parses `dnf5 check-upgrade --json` (services/updates/
UpdatesLogic.js). On openSUSE the same section is filled from
`zypper --xmlout list-updates`, converted here, so the parser and the page stay
one and the same on both distributions:

    zypper --non-interactive --xmlout list-updates | zypper-updates.py

prints {"upgrades": [{"name", "arch", "evr", "repository"}]} and exits 0, or
exits 1 without output when the input is not zypper's XML. Only package
updates are listed; patches and their security rating are not mapped to
packages, so on openSUSE the page shows no security count.
"""

import json
import sys
import xml.etree.ElementTree as ElementTree


def convert(text):
    """XML text → the dnf5 dict, or None for input that is not the update list."""
    try:
        root = ElementTree.fromstring(text)
    except ElementTree.ParseError:
        return None
    update_list = root.find(".//update-status/update-list")
    if update_list is None:
        return None
    upgrades = []
    for update in update_list.findall("update"):
        if update.get("kind", "package") != "package":
            continue
        name, arch, edition = update.get("name"), update.get("arch"), update.get("edition")
        if not name or not arch or not edition:
            continue
        source = update.find("source")
        repository = source.get("alias", "") if source is not None else ""
        upgrades.append({"name": name, "arch": arch, "evr": edition, "repository": repository})
    return {"upgrades": upgrades}


def main():
    result = convert(sys.stdin.read())
    if result is None:
        return 1
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
