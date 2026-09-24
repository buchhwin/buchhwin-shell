#!/usr/bin/env python3
"""scripts/calendar-helper.py answers a bad request with JSON, never a traceback.

The helper is driven the way the shell drives it - one JSON object on stdin,
one on stdout - through `add --dry-run`, which builds the iCalendar and
returns before any Akonadi job is created, so nothing is read or written. On
a machine without the Akonadi bindings the helper says so in its own JSON and
the checks here are skipped.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "calendar-helper.py"

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def run(command, request):
    done = subprocess.run([sys.executable, str(HELPER), command, "--dry-run"], input=json.dumps(request),
                          capture_output=True, text=True, timeout=60)
    try:
        answer = json.loads(done.stdout)
    except ValueError:
        answer = None
    return done, answer


done, answer = run("add", {"allDay": True, "day": "2026-09-20", "title": "x"})
if answer is not None and answer.get("ok") is False and "missing" in str(answer.get("error", "")):
    print("SKIPPED calendar_helper_test (no Akonadi bindings)")
    sys.exit(0)
check(answer is not None and answer.get("ok") is True and answer.get("dryRun") is True, "a well-formed dry run answers ok")
check("DTSTART;VALUE=DATE:20260920" in str(answer.get("ical", "")) if answer else False, "and builds the day")

# A day that is not YYYY-MM-DD used to go into DTSTART as it was, or raise
# somewhere inside the date arithmetic with the traceback on stderr and an
# empty stdout the shell could not parse.
for request in ({"allDay": True, "day": "20.09.2026"}, {"allDay": True, "day": "2026-09-20", "endDay": "tomorrow"},
                {"allDay": False, "day": ["2026-09-20"], "start": "09:00"}):
    done, answer = run("add", request)
    check(answer is not None and answer.get("ok") is False, f"a malformed day is refused with JSON: {request}")
    check(answer is not None and "date" in str(answer.get("error", "")), f"and the error names the format: {request}")
    check("Traceback" not in done.stderr, f"and there is no traceback: {request}")
    check(done.returncode == 1, f"and the exit status is the JSON one: {request}")

# The same for a modify whose changes carry a bad day.
done, answer = run("modify", {"item": 1, "changes": {"day": "next week"}})
check(answer is not None and answer.get("ok") is False and "day" in str(answer.get("error", "")),
      "a bad day inside `changes` is refused before anything is fetched")

# A field of the wrong shape: the count is not a number. That raised
# ValueError inside rule_of and the shell saw no answer at all.
done, answer = run("add", {"allDay": True, "day": "2026-09-20", "repeat": "weekly", "count": "many"})
check(answer is not None and answer.get("ok") is False, "a count that is not a number is refused with JSON")
check("Traceback" not in done.stderr and done.returncode == 1, "without a traceback")

if failures:
    for message in failures:
        print("FAIL", message)
    print("TESTS FAILED calendar_helper_test")
    sys.exit(1)
print("TESTS PASSED calendar_helper_test")
