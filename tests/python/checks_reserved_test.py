#!/usr/bin/env python3
"""Unit test for `checks.py reserved`: names Qt 6.9 refuses in QML files."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

failures = []


def expect(source, found, message):
    actual = checks.reserved_names(source)
    if actual != found:
        failures.append(f"{message}: expected {found}, got {actual}")


# What failed to parse on Leap 16, each found once while running the shell there.
expect("const short = 1\n", [(1, "short")], "a const")
expect("readonly property bool short: true\n", [(1, "short")], "a property")
expect("const f = (long) => long\n", [(1, "long")], "an arrow parameter")
expect("function g(a, char) { return char }\n", [(1, "char")], "a function parameter")
expect("for (const byte of xs) {}\n", [(1, "byte")], "a loop variable")
expect("Item { id: final }\n", [(1, "final")], "an id")
expect("x\nconst long = 2\n", [(2, "long")], "the line number")

# What is fine on both.
expect("text: clockBody.short ? a : b\n", [], "a member access")
expect("function f(day: string, index: int): bool {}\n", [], "a type annotation")
expect("signal chosen(int index)\n", [], "a signal parameter type")
expect("property int short_value: 1\n", [], "a longer name")
expect("// const long = 1\n", [], "a comment")
expect('text: "const long = 1"\n', [], "a string")

if failures:
    for failure in failures:
        print("FAIL checks_reserved: " + failure)
    sys.exit(1)
print("TESTS PASSED checks_reserved")
