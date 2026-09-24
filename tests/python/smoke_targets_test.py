#!/usr/bin/env python3
"""The smoke test's expected IPC targets are the ones shell.qml declares.

scripts/smoke-session.sh asks `quickshell ipc show` for every target in its
`expected_targets` list. A handler added to shell.qml and not to that list
was never checked (seventeen of them, when this was written), and a target
taken out of shell.qml failed only the session run. Both directions are held
here, statically, so the difference is found by scripts/test.sh.
"""

import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


targets = checks.ipc_targets((ROOT / "shell.qml").read_text())
smoke = (ROOT / "scripts" / "smoke-session.sh").read_text()
match = re.search(r"^expected_targets=\((.*?)\)$", smoke, re.M)
expected = match.group(1).split() if match else []

check(len(targets) >= 20, f"shell.qml's IpcHandlers were read ({len(targets)} found)")
check(match is not None, "scripts/smoke-session.sh has an expected_targets list")
check(len(set(targets)) == len(targets), f"no target is declared twice in shell.qml: {targets}")
missing = [target for target in targets if target not in expected]
check(not missing, f"shell.qml targets the smoke test never checks: {missing}")
extra = [target for target in expected if target not in targets]
check(not extra, f"expected_targets names targets shell.qml does not declare: {extra}")

if failures:
    for failure in failures:
        print(f"FAIL smoke_targets: {failure}")
    print(f"TESTS FAILED smoke_targets ({len(failures)} failed)")
    sys.exit(1)
print(f"TESTS PASSED smoke_targets ({len(targets)} targets)")
