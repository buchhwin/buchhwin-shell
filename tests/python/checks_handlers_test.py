#!/usr/bin/env python3
"""Unit tests for the handler and IpcHandler checks in scripts/lib/checks.py."""

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

COMPAT = """
Singleton {
    readonly property var commands: ({
        options: Commands.options, workspace: Commands.workspace, // a comment: Commands.notHere
        moveWorkspaceToMonitor: Commands.moveWorkspaceToMonitor
    })
}
"""
COMMANDS = """
function options(map) { return {} }
function workspace(id) { return {} }
function moveWorkspaceToMonitor(id, name) { return {} }
"""
USES = {
    "services/A.qml": "Item {\n  function f() { HyprCompat.dispatch(HyprCompat.commands.workspace(1)) }\n}\n",
    "services/B.qml": "Item {\n  // HyprCompat.commands.inComment(1)\n  function g() { HyprCompat.dispatch(HyprCompat.commands.moveWorkspaceToMonitor(3, \"DP-8\")) }\n  function h() { HyprCompat.dispatch(HyprCompat.commands.missing(3)) }\n}\n",
}
problems = checks.compat_problems(COMPAT, COMMANDS, USES)
check(len(problems) == 1, f"one problem for the one use outside the table (got {problems})")
check(problems and problems[0][0] == "services/B.qml" and problems[0][1] == 4 and "missing" in problems[0][2],
      f"the missing command is named with its file and line (got {problems})")
problems = checks.compat_problems(COMPAT.replace("Commands.workspace", "Commands.gone"), COMMANDS, {})
check(len(problems) == 1 and "Commands.gone" in problems[0][2], f"a table entry with no function is reported (got {problems})")
check(checks.compat_problems(COMPAT, COMMANDS, {}) == [], "a consistent table has no problems")
check(checks.compat_problems("Singleton {}", COMMANDS, {})[0][2].startswith("no `property var commands"), "a missing table is reported")

found = checks.injected_parameter_uses(SOURCE)
check((4, "onPressed", "mouse") in found, "block handler using mouse is reported")
check((5, "onReleased", "mouse") in found, "expression handler using mouse is reported")
check((11, "Keys.onPressed", "event") in found, "attached Keys handler using event is reported")
check(len(found) == 3, f"declared parameters, drag, strings, comments, locals and members are ignored: {found}")

source_with_id = "Item {\n    MouseArea { id: mouse }\n    onWidthChanged: mouse.enabled = true\n}\n"
check(checks.injected_parameter_uses(source_with_id) == [], "ids named like a parameter are ignored")

check(checks.check_handlers() == 0, "repository has no injected handler parameters")

# A property inside an IpcHandler is exported and a var cannot cross IPC;
# a function, a property outside the handler, one in a child object, and
# anything in a comment or a string are not the same thing.
IPC_SOURCE = '''
Item {
    // IpcHandler { target: "comment" }
    property var outside: []
    IpcHandler {
        target: "one" // a "quoted" word, and property var inComment: 1
        property var list: []
        readonly property string name: "property var inString: 2"
        function get(): string { return "{" }
        Timer { property int inner: 0 }
    }
    IpcHandler { target: "two"; function go(): void {} }
    IpcHandler {
        target: "three"
        Item { target: "nested" }
    }
}
'''
ipc_found = checks.ipc_properties(IPC_SOURCE)
check((7, "one", "list") in ipc_found, "a var property inside an IpcHandler is reported")
check((8, "one", "name") in ipc_found, "a readonly property inside an IpcHandler is reported too")
check(len(ipc_found) == 2, f"functions, children, siblings, comments and strings are not: {ipc_found}")
check(checks.ipc_targets(IPC_SOURCE) == ["one", "two", "three"],
      f"the targets are read in order, from the handler's own line only: {checks.ipc_targets(IPC_SOURCE)}")
blank = checks.blank_code(IPC_SOURCE)
check(len(blank) == len(IPC_SOURCE) and blank.count("\n") == IPC_SOURCE.count("\n"),
      "blank_code keeps every offset and line")
check("comment" not in blank and "inString" not in blank, "and blanks comments and strings")

check(checks.check_ipc() == 0, "shell.qml declares no property inside an IpcHandler")

if failures:
    for failure in failures:
        print(f"FAIL checks_handlers: {failure}")
    print(f"TESTS FAILED checks_handlers ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_handlers")
