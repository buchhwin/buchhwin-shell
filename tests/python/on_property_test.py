#!/usr/bin/env python3
"""A property named onX never beside a property or signal named x.

QML takes the declaration `readonly property bool onBattery: ...` for a
handler as soon as the same object also has a property or a signal called
`battery`: the binding never runs, and the property keeps its type's default
whatever its expression says (probed offscreen on Qt 6.12, both with a
property and with a signal). PowerService.onBattery is such a property: with a
`battery` beside it the shell keeps the charger's settings on battery and
warns of no low battery, without a word in the log. This fails on a QML file
that declares both names.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROPERTY = re.compile(r"^\s*(?:(?:readonly|required|default)\s+)*property\s+[\w<>.]+\s+(\w+)", re.M)
SIGNAL = re.compile(r"^\s*signal\s+(\w+)", re.M)


def files():
    yield from sorted(ROOT.glob("*.qml"))
    for folder in ("services", "shell", "theme"):
        yield from sorted((ROOT / folder).rglob("*.qml"))


def main():
    failures = []
    checked = 0
    for path in files():
        text = path.read_text(encoding="utf-8")
        names = set(PROPERTY.findall(text)) | set(SIGNAL.findall(text))
        for name in sorted(names):
            match = re.fullmatch(r"on([A-Z]\w*)", name)
            if not match:
                continue
            checked += 1
            base = match.group(1)[0].lower() + match.group(1)[1:]
            if base in names:
                failures.append("%s: `%s` beside `%s` - QML reads it as a handler and its binding never runs"
                                % (path.relative_to(ROOT), name, base))
    if checked < 5:
        failures.append("only %d onX properties found - did the pattern go stale?" % checked)
    for failure in failures:
        print("FAIL", failure)
    if failures:
        print("TESTS FAILED on_property_test")
        return 1
    print("TESTS PASSED on_property_test (%d onX properties)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
