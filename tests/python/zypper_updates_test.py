#!/usr/bin/env python3
"""Unit test for scripts/zypper-updates.py with a recorded zypper XML list."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("zypper_updates", ROOT / "scripts" / "zypper-updates.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


sample = (ROOT / "tests" / "fixtures" / "zypper-list-updates.xml").read_text()
result = module.convert(sample)
check(result is not None, "the recorded list converts")
upgrades = (result or {}).get("upgrades", [])
check([item["name"] for item in upgrades] == ["kitty", "python313-Pillow"], "packages in order, the broken one skipped")
check(upgrades and upgrades[0] == {"name": "kitty", "arch": "x86_64", "evr": "0.42.1-160000.2.1",
                                   "repository": "openSUSE:repo-oss"}, "the dnf5 fields")

empty = module.convert("<stream><update-status version='0.6'><update-list></update-list></update-status></stream>")
check(empty == {"upgrades": []}, "no updates is an empty list, not a failure")
check(module.convert("") is None, "empty input is not an answer")
check(module.convert("<stream><message>Root privileges are required</message></stream>") is None,
      "XML without the update list is not an answer")
patch = module.convert("<stream><update-status><update-list><update kind='patch' name='p' edition='1' arch='noarch'/>"
                       "</update-list></update-status></stream>")
check(patch == {"upgrades": []}, "patches are not packages")

if failures:
    for failure in failures:
        print("FAIL zypper-updates: " + failure)
    sys.exit(1)
print("TESTS PASSED zypper-updates")
