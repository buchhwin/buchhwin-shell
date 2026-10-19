#!/usr/bin/env python3
"""A QML file that declares a Qt type imports the module that has it.

shell.qml imports Quickshell and the shell's own modules, and none of them
hands on Qt's types: a `Connections` added there without `import QtQml` was
"Connections is not a type" at load, and the whole shell did not start. The
offscreen tests never load shell.qml, and qmllint does not fail on it, so only
a nested start would have shown it. This fails on a .qml file that declares an
object of a QtQml or QtQuick type without importing QtQml or QtQuick (either
brings QtQml's types).
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
# The types such a file is most likely to reach for: QtQml's own, and the
# QtQuick items every other file draws with.
QT_TYPES = ("Connections", "Timer", "QtObject", "Binding", "Instantiator", "Component",
            "Item", "Rectangle", "Text", "MouseArea", "Loader", "Repeater")
DECLARES = re.compile(r"^\s*(%s)\s*\{" % "|".join(QT_TYPES), re.M)
IMPORTS = re.compile(r"^\s*import\s+(QtQml|QtQuick)\b", re.M)


def files():
    yield from sorted(ROOT.glob("*.qml"))
    for folder in ("services", "shell", "theme", "tests/qml"):
        yield from sorted((ROOT / folder).rglob("*.qml"))


def main():
    failures = []
    checked = 0
    for path in files():
        text = path.read_text(encoding="utf-8")
        checked += 1
        found = DECLARES.search(text)
        if found and not IMPORTS.search(text):
            line = text.count("\n", 0, found.start(1)) + 1
            failures.append("%s:%d: `%s` without `import QtQml` or `import QtQuick` - it does not load"
                            % (path.relative_to(ROOT), line, found.group(1)))
    if checked < 100:
        failures.append("only %d QML files found - did the folders move?" % checked)
    for failure in failures:
        print("FAIL", failure)
    if failures:
        print("TESTS FAILED qml_imports_test")
        return 1
    print("TESTS PASSED qml_imports_test (%d files)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
