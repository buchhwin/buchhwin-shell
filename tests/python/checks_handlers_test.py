#!/usr/bin/env python3
"""Unit test for the injected signal handler parameter check in scripts/lib/checks.py."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


SOURCE = '''
MouseArea {
    id: area
    onPressed: { root.x = mouse.x }
    onReleased: root.y = mouse.y
    onClicked: mouse => root.pick(mouse.button)
    onWheel: function(wheel) { root.scroll(wheel.angleDelta.y) }
    onDoubleClicked: (event) => root.open(event)
    onPositionChanged: { if (drag.active) root.move() }
    onCanceled: root.note("mouse left") // mouse in a comment
    Keys.onPressed: { if (event.key === Qt.Key_Escape) root.close() }
    onEntered: { const event = root.last; root.show(event) }
    onExited: root.hide(area.mouse)
}
'''

found = checks.injected_parameter_uses(SOURCE)
check((4, "onPressed", "mouse") in found, "block handler using mouse is reported")
check((5, "onReleased", "mouse") in found, "expression handler using mouse is reported")
check((11, "Keys.onPressed", "event") in found, "attached Keys handler using event is reported")
check(len(found) == 3, f"declared parameters, drag, strings, comments, locals and members are ignored: {found}")

source_with_id = "Item {\n    MouseArea { id: mouse }\n    onWidthChanged: mouse.enabled = true\n}\n"
check(checks.injected_parameter_uses(source_with_id) == [], "ids named like a parameter are ignored")

check(checks.check_handlers() == 0, "repository has no injected handler parameters")

if failures:
    for failure in failures:
        print(f"FAIL checks_handlers: {failure}")
    print(f"TESTS FAILED checks_handlers ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_handlers")
