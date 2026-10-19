#!/usr/bin/env python3
"""`checks.py style --strict` counts what it is there to count.

The suite runs it as a gate, and a pattern or an allow-list entry that
matches too much would make it print 0 for any tree. So it runs here against
a tree built in a temporary directory, one line per pattern, beside the
values and exceptions it has to leave alone.
"""
import io
import shutil
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "lib"))
import checks  # noqa: E402

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def counted(line, name="shell/Page.qml"):
    """How many of LINE's lines the strict check counts, in a file NAME."""
    (root / "shell").mkdir(exist_ok=True)
    (root / "services").mkdir(exist_ok=True)
    for old in list((root / "shell").rglob("*")) + list((root / "services").rglob("*")):
        if old.is_file():
            old.unlink()
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(line + "\n")
    out = io.StringIO()
    with redirect_stdout(out):
        total = checks.check_style(True)
    return total


root = Path(tempfile.mkdtemp(prefix="buchhwin-style."))
saved_root, saved_roots = checks.ROOT, checks.STYLE_ROOTS
try:
    checks.ROOT = root
    checks.STYLE_ROOTS = ["shell", "services"]
    for line in ('color: "#ff0000"', "color: Qt.rgba(0, 0, 0, 0.5)", 'color: "white"',
                 'font.family: "Inter"', "duration: 200", "radius: 8", "font.pixelSize: 12",
                 "spacing: 6", "anchors.margins: 4", "Layout.leftMargin: 10", "border.width: 2",
                 "shadowBlur: 1", "font.letterSpacing: 1", "width: Metrics.iconXl * 1.5", "labelWidth: 120"):
        check(counted(line) == 1, f"`{line}` is counted")
    for line in ("radius: 0", "spacing: 0", 'color: "transparent"', "anchors.margins: 0",
                 "radius: Metrics.radius", "// radius: 8 in a comment",
                 "radius: 8 // style: the shape's own corner"):
        check(counted(line) == 0, f"`{line}` is not counted")
    # The allowed value is taken out, not the line around it.
    for line in ("radius: 8; x: 0", "font.pixelSize: 12; opacity: 0.5",
                 'Rectangle { width: 0; color: "#ff0000" }', 'color: "transparent"; border.width: 2'):
        check(counted(line) == 1, f"`{line}` is counted beside the allowed value")
    check(counted("radius: 8", "services/Logic.js") == 1, "a .js file is read too")
    check(counted("radius: 8", "shell/x.txt") == 0, "and nothing else")
    # theme/ owns the values: it is not one of the roots.
    (root / "theme").mkdir(exist_ok=True)
    (root / "theme" / "Metrics.qml").write_text("readonly property int radius: 8\n")
    check(counted("radius: Metrics.radius") == 0, "theme/ is not read")
finally:
    checks.ROOT, checks.STYLE_ROOTS = saved_root, saved_roots
    shutil.rmtree(root)

if failures:
    for failure in failures:
        print("FAIL checks_style: " + failure)
    print(f"TESTS FAILED checks_style ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_style")
