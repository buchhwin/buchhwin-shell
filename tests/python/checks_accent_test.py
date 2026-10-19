#!/usr/bin/env python3
"""Unit test for the raw-accent rule of `checks.py style`: a fill that marks a
state or carries a label takes Colors.accentFill, not the raw accent."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

if not hasattr(checks, "raw_accent_lines"):
    print("skipped: checks.py has no raw_accent_lines (the raw-accent rule of `style`)")
    sys.exit(77)

failures = []


def expect(relative, source, found, message):
    actual = checks.raw_accent_lines(relative, source)
    if actual != found:
        failures.append(f"{message}: expected {found}, got {actual}")


# What the rule is for: on a light panel the raw teal was 1.3:1, the switch
# beside it 3.9:1.
expect("shell/components/PanelHeader.qml", "color: root.iconActive ? Colors.accent : Colors.surface2\n", [1],
       "a header tile in the raw accent")
expect("shell/x/Y.qml", "a: 1\ncolor: down ? Colors.accentPressed : Colors.accent\n", [2], "the line number")
expect("shell/x/Y.qml", "color: Colors.accent\n", [1], "the token at the end of the line")

# What it leaves alone.
expect("shell/x/Y.qml", "color: root.iconActive ? Colors.accentFill : Colors.surface2\n", [], "the fill")
expect("shell/x/Y.qml", "color: Colors.accentFillHover\ncolor: Colors.accentLine\ncolor: Colors.accentForeground\n", [],
       "the accent's other tokens")
expect("shell/x/Y.qml", "// the raw Colors.accent was 1.3:1\n", [], "a comment")
expect("shell/x/Y.qml", "color: Colors.accent // style: the avatar's disc is the accent itself\n", [],
       "a line that says why")
expect("shell/editor/EditLayer.qml", "color: Colors.accent\n", [], "the layout editor's chrome")
expect("shell/lock/LockFace.qml", "color: Colors.accent\n", [], "the lock screen, dark in both themes")
expect("shell/notch/NotchStrip.qml", "strokeColor: Colors.accent\n", [], "the notch, black in both themes")
expect("services/CalendarService.qml", "return Logic.eventColor(event, Colors.accent, mode)\n", [],
       "a service handing the accent on as data")

# And the tree holds to it.
for path in sorted((ROOT / "shell").rglob("*.qml")):
    relative = path.relative_to(ROOT).as_posix()
    for number in checks.raw_accent_lines(relative, path.read_text()):
        failures.append(f"{relative}:{number}: the raw accent where a fill wants Colors.accentFill")

for failure in failures:
    print("FAIL", failure)
if failures:
    sys.exit(1)
print("checks_accent_test: ok")
