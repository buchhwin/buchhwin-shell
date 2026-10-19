#!/usr/bin/env python3
"""What scripts/smoke-session.sh walks through exists, and its log filter.

The nested smoke test opens every surface that is built only when it opens -
the settings pages, the control center's pages, the popups, the panels - by
the names written in the script. A name that drifted from the shell (a page
renamed, a popup taken out) would make the session run fail on the test, not
on the shell, and only there; here it fails at once, statically.

The log filter: a nested shell never asks for the notification name, so the
two lines of a shell queueing for it are a defect in a nested run (the test
shell lost BUCHHWIN_NESTED) and are filtered only in the live session's run.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
smoke = (ROOT / "scripts" / "smoke-session.sh").read_text()
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def loop_names(variable):
    match = re.search(r"^\s*for %s in ([\w ]+); do$" % variable, smoke, re.M)
    return match.group(1).split() if match else []


# The settings pages, read from SettingsNavLogic.js with the script's own
# pattern; each has its page file (SettingsPanel loads pages/<Id>Page.qml).
nav = (ROOT / "services" / "settings" / "SettingsNavLogic.js").read_text()
check('{ id: "\\([A-Za-z]*\\)"' in smoke, "the smoke test reads the page ids with the pattern this test checks")
pages = re.findall(r'^\s*\{ id: "([A-Za-z]*)"', nav, re.M)
check(len(pages) >= 10, f"the settings page ids are found in SettingsNavLogic.js ({len(pages)})")
for page in pages:
    file = ROOT / "shell" / "settings" / "pages" / (page[0].upper() + page[1:] + "Page.qml")
    check(file.is_file(), f"settings page {page} has {file.relative_to(ROOT)}")

control_center = (ROOT / "shell" / "controlcenter" / "ControlCenter.qml").read_text()
cc_pages = loop_names("page")
check(cc_pages, "the smoke test walks the control center's pages")
for page in cc_pages:
    check(f'root.page === "{page}"' in control_center, f"the control center has a page {page}")

shell = (ROOT / "shell.qml").read_text()
popup_list = re.search(r"function isPopup\(name: string\): bool \{\s*return \[(.*?)\]", shell, re.S)
known_popups = re.findall(r'"(\w+)"', popup_list.group(1)) if popup_list else []
popups = loop_names("popup")
check(popups, "the smoke test walks the popups")
for popup in popups:
    check(popup in known_popups, f"popup {popup} is one `popup open` knows")

panels = loop_names("panel")
check(panels, "the smoke test walks the panels")
for panel in panels:
    handler = re.search(r'target: "%s"(.*?)\n    \}' % re.escape(panel), shell, re.S)
    check(handler and "function open()" in handler.group(1) and "function close()" in handler.group(1),
          f"IPC target {panel} has open() and close()")


def filtered(line, *args):
    """Whether the smoke test's known_warnings (as set up for ARGS) drop LINE."""
    block = re.search(r"^known_warnings=.*?^fi$", smoke, re.M | re.S)
    if not block:
        return None
    script = block.group(0) + '\nprintf "%s\\n" "$LINE" | grep -qE "$known_warnings"\n'
    result = subprocess.run(["bash", "-c", script, "smoke", *args], env={"LINE": line, "PATH": "/usr/bin:/bin"})
    return result.returncode == 0


register = "WARN: Could not register notification server: name taken, queueing"
again = "WARN: Registration will be attempted again"
check(filtered(register, "--nested") is False, "a nested run reports a shell asking for the notification name")
check(filtered(again, "--nested") is False, "a nested run reports the retry too")
check(filtered(register) is True, "the live session's run still filters another owner of the name")
check(filtered("WARN: QSettings::value: Empty key passed", "--nested") is True,
      "a nested run still filters the environment's own noise")

if failures:
    for failure in failures:
        print(f"FAIL smoke_steps: {failure}")
    print(f"TESTS FAILED smoke_steps ({len(failures)} failed)")
    sys.exit(1)
print(f"TESTS PASSED smoke_steps ({len(pages)} pages, {len(cc_pages)} control center pages, "
      f"{len(popups)} popups, {len(panels)} panels)")
