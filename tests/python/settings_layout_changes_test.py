#!/usr/bin/env python3
"""Settings pages change the layout only as an undo step that is saved.

LayoutService's item edits (updateItem, removeItem, addWidget, groupItems,
ungroup, moveMember, moveToScreen) change the layout in memory and nothing
else: the caller takes the undo step (beginChange) and writes layout.json
(save), the way the editor's EditLayer.change does. Settings > Widgets called
three of them bare, so Remove, the visibility switch and the style changed the
desktop at once, were gone after the next restart and could not be undone
(ui-b#0). This reads every settings page and fails on a call outside a
`change(() => ...)` wrapper or a beginChange/save pair in the same handler.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PAGES = ROOT / "shell" / "settings" / "pages"
UNSAVED = ("updateItem", "removeItem", "addWidget", "groupItems", "ungroup", "moveMember", "moveToScreen")
CALL = re.compile(r"LayoutService\.(%s)\(" % "|".join(UNSAVED))

failures = []
checked = 0
for path in sorted(PAGES.glob("*.qml")):
    lines = path.read_text(encoding="utf-8").splitlines()
    for number, line in enumerate(lines, 1):
        if line.strip().startswith("//") or not CALL.search(line):
            continue
        checked += 1
        if "change(() =>" in line:
            continue
        # A handler that takes the step and saves around the call itself.
        window = "\n".join(lines[max(0, number - 4):number + 3])
        if "LayoutService.beginChange()" in window and "LayoutService.save()" in window:
            continue
        failures.append("%s:%d: %s" % (path.relative_to(ROOT), number, line.strip()))

if checked == 0:
    failures.append("no layout edits found on the settings pages - did the pattern go stale?")
if failures:
    for failure in failures:
        print("FAIL unsaved layout edit:", failure)
    print("TESTS FAILED settings_layout_changes_test")
    sys.exit(1)
print("TESTS PASSED settings_layout_changes_test (%d calls)" % checked)
