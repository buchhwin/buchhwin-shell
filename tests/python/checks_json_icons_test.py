#!/usr/bin/env python3
"""`checks.py json` parses the fixtures, and `checks.py icons` reads whole lines.

Both run against a repository built in a temporary directory, because the
things they must catch - a broken fixture, a glyph beside a `: 0` - are not
in the real one.
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


def run(function):
    out = io.StringIO()
    with redirect_stdout(out):
        result = function()
    return result, out.getvalue()


root = Path(tempfile.mkdtemp(prefix="buchhwin-checks."))
try:
    (root / "config").mkdir()
    (root / "config" / "a.json").write_text('{"configVersion": 1}')
    fixtures = root / "tests" / "fixtures"
    fixtures.mkdir(parents=True)
    (fixtures / "layout-broken.json").write_text("{ this is not json")
    (fixtures / "sample.json").write_text('{"ok": true}')
    (root / "theme").mkdir()
    (root / "theme" / "Icons.qml").write_text('Singleton {\n    readonly property string close: "X"\n}\n')
    (root / "shell").mkdir()
    (root / "services").mkdir()
    checks.ROOT = root

    result, output = run(checks.check_json)
    check(result == 0, f"a fixture broken on purpose is not a failure: {output}")
    (fixtures / "sample.json").write_text("{ broken by accident")
    result, output = run(checks.check_json)
    check(result == 1 and "sample.json" in output, f"any other fixture that does not parse is: {output}")

    page = root / "shell" / "Page.qml"
    page.write_text('Text { text: "X" }\n')
    result, output = run(checks.check_icons)
    check(result == 1, f"a glyph the theme names is reported: {output}")
    page.write_text('Text { x: 0; text: "X" }\n')
    result, output = run(checks.check_icons)
    check(result == 1, f"and still is beside an allowed `: 0`: {output}")
    page.write_text('Text { x: 0; text: Icons.close }\n')
    result, output = run(checks.check_icons)
    check(result == 0, f"the name is what the check wants: {output}")
    page.write_text('Text { text: "X" } // style: the one place the glyph is drawn raw\n')
    result, output = run(checks.check_icons)
    check(result == 1, "a style exception does not excuse a glyph")
    page.unlink()

    # The top-level shells are read, and an escape is the glyph it stands for
    # - in a file and in Icons.qml itself.
    (root / "theme" / "Icons.qml").write_text(
        'Singleton {\n    readonly property string close: "X"\n    readonly property string dock: "\\u{f1888}"\n}\n')
    (root / "shell.qml").write_text('Item { property string a: "X" }\n')
    result, output = run(checks.check_icons)
    check(result == 1 and "shell.qml:1" in output, f"shell.qml is read: {output}")
    (root / "shell.qml").write_text('Item { property string a: Icons.close }\n')
    (root / "lock.qml").write_text("Item { property string a: '\U000f1888' }\n")
    result, output = run(checks.check_icons)
    check(result == 1 and "lock.qml:1 uses the glyph of Icons.dock" in output,
          f"lock.qml is read, in single quotes, against an escaped name: {output}")
    (root / "lock.qml").write_text('Item { property string a: "\\u{f1888}" }\n')
    result, output = run(checks.check_icons)
    check(result == 1 and "lock.qml:1" in output, f"an escape is the glyph it stands for: {output}")
    (root / "lock.qml").unlink()

    # A .js file cannot reach Icons: it names the glyph in a comment, and the
    # comment has to be the glyph's own name.
    logic = root / "services" / "NavLogic.js"
    logic.write_text('const PAGES = [{ id: "a", icon: "X" }]\n')
    result, output = run(checks.check_icons)
    check(result == 1 and "NavLogic.js:1" in output and "// Icons.close" in output, f"a .js glyph is reported: {output}")
    logic.write_text('const PAGES = [{ id: "a", icon: "X" }] // Icons.close\n')
    result, output = run(checks.check_icons)
    check(result == 0, f"and passes once named: {output}")
    logic.write_text('const PAGES = [{ id: "a", icon: "X" }] // Icons.dock\n')
    result, output = run(checks.check_icons)
    check(result == 1, f"another glyph's name does not excuse it: {output}")
    logic.write_text('function icon() { return "\\u{f1888}" } // Icons.dock\n')
    result, output = run(checks.check_icons)
    check(result == 0, f"an escaped glyph named in the comment passes: {output}")
    logic.write_text('function icon() { return "\\udb86\\udc88" }\n')
    result, output = run(checks.check_icons)
    check(result == 1 and "Icons.dock" in output, f"so does a surrogate pair of escapes, as the glyph it is: {output}")
finally:
    shutil.rmtree(root)

# An icon-only button needs a tip: it is the button's only name.
check(checks.unnamed_buttons('ShellButton { icon: Icons.close; onClicked: x() }\n') == [1], "a bare glyph button is unnamed")
check(checks.unnamed_buttons('Item {\n    ShellButton {\n        icon: Icons.close\n        toolTip: "Close"\n    }\n}\n') == [], "a tip names it")
check(checks.unnamed_buttons('ShellButton { icon: Icons.add; text: "Add" }\n') == [], "words name it")
check(checks.unnamed_buttons('ShellButton { icon: Icons.add; Rectangle { toolTip: "no" } }\n') == [1], "a tip on a child does not count")

if failures:
    for failure in failures:
        print("FAIL checks_json_icons: " + failure)
    print(f"TESTS FAILED checks_json_icons ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_json_icons")
