#!/usr/bin/env python3
"""Every raw `Text` on the surfaces that show other people's strings is plain.

Qt's default text format is AutoText: a string that looks like markup is
rendered as rich text, and an `<img src=...>` in it is fetched. A web page's
title (the active window widget), an MPRIS title or artist (the notch, the
Playback widget, the bar), an SSID, a device name or an invitation's event
title then made the shell request whatever address the string named
(the review of 2026-10-16). `ShellText` is plain already; this checks the
`Text {` elements and `component X: Text` definitions written by hand in the
notch, the bar, the widgets, the overview, the switcher, the notifications and
the OSD. A glyph element is checked too: it costs nothing and keeps the rule
one rule. `checks.py plaintext` holds the rest of shell/ to it.
"""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
AREAS = ["shell/notch", "shell/bar", "shell/widgets", "shell/overview", "shell/switcher",
         "shell/notifications", "shell/osd", "shell/dock"]
FILES = ["shell.qml", "shell/popups/MediaPopup.qml", "shell/components/MediaCard.qml",
         "shell/components/NotchHoverRows.qml", "shell/components/ScrimLayer.qml"]

# The scanner lives with the static checks (`checks.py plaintext`, which runs
# it over all of shell/); this test keeps it honest and the areas above plain.
spec = importlib.util.spec_from_file_location("checks", ROOT / "scripts" / "lib" / "checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
raw_texts = checks.raw_texts


failures = []

# The scanner itself, on what it has to tell apart.
sample = '''Item {
    Text {
        text: "a"
        textFormat: Text.PlainText
    }
    component Label: Text {
        Rectangle { textFormat: 1 }
        text: "b"
    }
    ShellText { text: "c" }
    // Text { in a comment }
    property string s: "Text {"
}
'''
expected = [(2, True), (6, False)]
if raw_texts(sample) != expected:
    failures.append(f"scanner: expected {expected}, got {raw_texts(sample)}")

paths = []
for area in AREAS:
    paths.extend(sorted((ROOT / area).rglob("*.qml")))
paths.extend(ROOT / name for name in FILES)

checked = 0
for path in paths:
    if not path.exists():
        continue
    for line, has_format in raw_texts(path.read_text(encoding="utf-8")):
        checked += 1
        if not has_format:
            failures.append(f"{path.relative_to(ROOT)}:{line}: a raw Text without textFormat")

if checked == 0:
    failures.append("no Text elements found: the scanner or the paths are wrong")

if failures:
    for failure in failures:
        print("FAIL plain_text: " + failure)
    sys.exit(1)
print(f"TESTS PASSED plain_text ({checked} Text elements)")
