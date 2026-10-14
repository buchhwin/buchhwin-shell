#!/usr/bin/env python3
"""Unit test for scripts/pacman-updates.py with invented checkupdates, AUR and
`pacman -Sl` output (Arch)."""

import importlib.util
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "pacman-updates.py"
spec = importlib.util.spec_from_file_location("pacman_updates", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


repos = "core linux 6.17.3.arch1-1 [installed: 6.17.2.arch1-1]\nextra mesa 1:26.2.5-1 [installed: 1:26.2.4-1]\nextra kitty 0.49.3-1\n"
pacman = "linux 6.17.2.arch1-1 -> 6.17.3.arch1-1\nmesa 1:26.2.4-1 -> 1:26.2.5-1\n"
aur = ":: Searching AUR for updates...\nbrave-bin 1:1.97.56-1 -> 1:1.97.60-1\nicaclient 26.04.10.1-1 -> 26.08.0.153-1 [ignored]\n"

result = module.convert(repos, pacman, aur, arch="x86_64")
upgrades = result["upgrades"]
check([item["name"] for item in upgrades] == ["linux", "mesa", "brave-bin"],
      "repository updates first, then the AUR's; chatter and ignored packages skipped")
check(upgrades[0] == {"name": "linux", "arch": "x86_64", "evr": "6.17.3.arch1-1", "repository": "core"},
      "the dnf5 fields, the repository from pacman -Sl")
check(upgrades[1]["evr"] == "1:26.2.5-1", "an epoch is kept")
check([item["repository"] for item in upgrades[2:]] == ["aur"], "AUR packages are marked aur")
check(module.convert("", pacman, "", arch="x86_64")["upgrades"][0]["repository"] == "",
      "an unknown repository is empty, not a failure")
check(module.convert(repos, "", "") == {"upgrades": []}, "nothing to update is an empty list")
check(module.convert(repos, pacman, "linux 1 -> 2\n", arch="x86_64")["upgrades"][0]["repository"] == "core",
      "a name pacman knows is not listed twice")
check(module.convert("", "warning: something\n==> ERROR: Cannot fetch updates\n", "") == {"upgrades": []},
      "error lines are not packages")

lines = module.installed(pacman, aur, arch="x86_64")
check(lines == ["linux.x86_64\t6.17.2.arch1-1", "mesa.x86_64\t1:26.2.4-1",
                "brave-bin.x86_64\t1:1.97.56-1"],
      "the @installed lines carry the old versions under the same key")

# The command line, as scripts/updates-check.sh calls it.
with tempfile.TemporaryDirectory() as tmp:
    paths = {}
    for name, text in (("repos", repos), ("pacman", pacman), ("aur", aur)):
        paths[name] = pathlib.Path(tmp) / name
        paths[name].write_text(text)
    run = subprocess.run([sys.executable, str(SCRIPT), "json", str(paths["repos"]), str(paths["pacman"]), str(paths["aur"])],
                         capture_output=True, text=True, check=False)
    check(run.returncode == 0 and '"brave-bin"' in run.stdout, "json from files")
    run = subprocess.run([sys.executable, str(SCRIPT), "installed", str(paths["pacman"])],
                         capture_output=True, text=True, check=False)
    check(run.returncode == 0 and run.stdout.count("\n") == 2, "installed from files, AUR optional")
    run = subprocess.run([sys.executable, str(SCRIPT), "json", str(pathlib.Path(tmp) / "missing"), str(paths["pacman"])],
                         capture_output=True, text=True, check=False)
    check(run.returncode == 1 and not run.stdout, "a missing file exits 1 without output")
    run = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, check=False)
    check(run.returncode == 2, "no arguments is a usage error")

if failures:
    for failure in failures:
        print("FAIL pacman-updates: " + failure)
    sys.exit(1)
print("TESTS PASSED pacman-updates")
