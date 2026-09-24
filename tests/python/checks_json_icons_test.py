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
finally:
    shutil.rmtree(root)

if failures:
    for failure in failures:
        print("FAIL checks_json_icons: " + failure)
    print(f"TESTS FAILED checks_json_icons ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_json_icons")
