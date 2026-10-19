#!/usr/bin/env python3
"""Every shell test in tests/ is one scripts/test.sh runs.

The QML and Python tests are globbed and cannot be forgotten; the shell tests
are run by name, in sections, so a new tests/foo-test.sh that nobody added to
the list was only ever parsed (`bash -n`), never run - in the suite or in CI.
tests/run-qml-test.sh is the QML runner, not a test of its own.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
suite = (ROOT / "scripts" / "test.sh").read_text()
run = set(re.findall(r'^\s*"\$project_dir/tests/([\w.-]+-test\.sh)"', suite, re.M))
tests = sorted(path.name for path in (ROOT / "tests").glob("*-test.sh") if path.name != "run-qml-test.sh")

failures = []
if len(tests) < 10:
    failures.append(f"the shell tests in tests/ are found ({len(tests)})")
missing = [name for name in tests if name not in run]
if missing:
    failures.append(f"scripts/test.sh never runs {', '.join(missing)}: add each to its section")
gone = sorted(name for name in run if not (ROOT / "tests" / name).is_file())
if gone:
    failures.append(f"scripts/test.sh runs tests that do not exist: {', '.join(gone)}")

if failures:
    for failure in failures:
        print(f"FAIL shell_tests_listed: {failure}")
    print(f"TESTS FAILED shell_tests_listed ({len(failures)} failed)")
    sys.exit(1)
print(f"TESTS PASSED shell_tests_listed ({len(tests)} shell tests)")
