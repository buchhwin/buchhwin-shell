#!/usr/bin/env python3
"""The device and stream lists keep their rows: no Repeater over a bare list.

AudioService's lists (sinks, sources, the playback and capture streams) are
filters over PipeWire's nodes and BluetoothService's (connected, paired,
nearby) filters over BlueZ's devices: a new array whenever anything comes or
goes. A Repeater over such an array builds every row again on each change -
a slider drag ended under the hand, an armed Remove fell back to its first
click, the keyboard focus went - and one over sections written as a list of
new objects builds the sections again too, scrolled back to the top. The
rows go through a ScriptModel (the nodes and devices keep their identity) and
sections are named by plain strings; tests/qml/BluetoothListTest.qml shows
the difference in a window. This keeps the files from going back.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
AREAS = ["shell/controlcenter", "shell/popups", "shell/settings/pages"]
LISTS = re.compile(r"\b(AudioService|BluetoothService)\.\w+")


def repeater_models(text):
    """(line, model expression) for every Repeater, the expression joined
    over the lines an array literal spans."""
    lines = text.splitlines()
    found = []
    for index, line in enumerate(lines):
        if not re.search(r"\bRepeater\s*\{", line.split("//")[0]):
            continue
        for at in range(index + 1, min(index + 12, len(lines))):
            code = lines[at].split("//")[0].strip()
            if not code:
                continue
            if not code.startswith("model:"):
                continue
            expression = code[len("model:"):].strip()
            depth = expression.count("[") - expression.count("]")
            end = at
            while depth > 0 and end + 1 < len(lines):
                end += 1
                more = lines[end].split("//")[0].strip()
                expression += " " + more
                depth += more.count("[") - more.count("]")
            found.append((at + 1, expression))
            break
    return found


def problems(text):
    """(line, reason) for each Repeater that rebuilds on a service's change."""
    result = []
    for line, expression in repeater_models(text):
        if expression.startswith("ScriptModel"):
            continue
        if expression.startswith("[") and LISTS.search(expression):
            result.append((line, "sections built as new objects from a service's lists"))
        elif LISTS.search(expression):
            result.append((line, "a Repeater over a bare service list"))
    return result


failures = []

# The scanner itself, on what it has to tell apart.
sample = '''Item {
    Repeater {
        model: AudioService.sinks
    }
    Repeater {
        // kept
        model: ScriptModel { values: AudioService.playbackStreams }
    }
    Repeater {
        model: [
            { label: "Nearby", list: BluetoothService.nearby }
        ]
    }
    Repeater {
        model: ["connected", "nearby"]
    }
    Repeater {
        model: TrayService.items
    }
    Repeater {
        model: ["shell"].concat(TerminalService.promptColors)
    }
}
'''
expected = [(3, "a Repeater over a bare service list"),
            (10, "sections built as new objects from a service's lists")]
if problems(sample) != expected:
    failures.append(f"scanner: expected {expected}, got {problems(sample)}")

checked = 0
for area in AREAS:
    for path in sorted((ROOT / area).rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        checked += len(repeater_models(text))
        for line, reason in problems(text):
            failures.append(f"{path.relative_to(ROOT)}:{line}: {reason}")

if checked == 0:
    failures.append("no Repeater found: the scanner or the paths are wrong")

if failures:
    for failure in failures:
        print("FAIL kept_rows: " + failure)
    sys.exit(1)
print(f"TESTS PASSED kept_rows ({checked} Repeaters)")
