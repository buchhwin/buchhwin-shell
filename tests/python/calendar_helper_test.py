#!/usr/bin/env python3
"""scripts/calendar-helper.py answers a bad request with JSON, never a traceback.

The helper is driven the way the shell drives it - one JSON object on stdin,
one on stdout - through `add --dry-run`, which builds the iCalendar and
returns before any Akonadi job is created, so nothing is read or written.

Where the Akonadi bindings are installed (Fedora) the helper runs as the
shell runs it, in a process of its own. Where they are not packaged (Arch,
Leap, the CI container) it said so in its own JSON and this test used to stop
there with exit 0 - a skip nobody saw, and the helper's request checks ran on
no machine at all (round 12, tests-docs#4). There it is now loaded against
stand-ins for PySide6 and the bindings, as calendar_exclude_test.py does, and
its main() is driven in this process: the same requests, the same answers,
nothing that could talk to Akonadi.
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import traceback
import types

ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "calendar-helper.py"

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


class Done:
    """What a run left behind: its exit status and its two streams."""

    def __init__(self, returncode, stdout, stderr):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr


def answer_of(stdout):
    try:
        return json.loads(stdout)
    except ValueError:
        return None


def run_process(command, request):
    done = subprocess.run([sys.executable, str(HELPER), command, "--dry-run"], input=json.dumps(request),
                          capture_output=True, text=True, timeout=60)
    return Done(done.returncode, done.stdout, done.stderr)


# ---- stand-ins, for a machine without the bindings ---------------------------
# Enough of Qt's event loop for drive(): a single shot runs at once, and exec()
# returns, since every job a dry run could start is a stand-in that never
# starts. No Akonadi class is ever reached by a dry run or a refused request.
class Timer:
    def __init__(self):
        self.timeout = types.SimpleNamespace(connect=lambda _slot: None)

    def setSingleShot(self, _on):
        pass

    def start(self, _ms):
        pass

    def stop(self):
        pass

    @staticmethod
    def singleShot(_ms, slot):
        slot()


class Application:
    current = None

    def __init__(self, _argv):
        Application.current = self

    @classmethod
    def instance(cls):
        return cls.current

    def exec(self):
        return 0

    def quit(self):
        pass


class TimeZone:
    @staticmethod
    def systemTimeZoneId():
        return b"UTC"


def load_with_stand_ins():
    qtcore = types.ModuleType("PySide6.QtCore")
    qtcore.QByteArray = bytes
    qtcore.QCoreApplication, qtcore.QTimer, qtcore.QTimeZone = Application, Timer, TimeZone
    pyside = types.ModuleType("PySide6")
    pyside.QtCore = qtcore
    akonadi_core = types.ModuleType("AkonadiCore")
    akonadi_core.Akonadi = types.SimpleNamespace()
    sys.modules.update({"PySide6": pyside, "PySide6.QtCore": qtcore, "AkonadiCore": akonadi_core})
    spec = importlib.util.spec_from_file_location("calendar_helper", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_in_process(helper):
    def run(command, request):
        out, err = io.StringIO(), io.StringIO()
        saved = sys.argv, sys.stdin
        sys.argv, sys.stdin = [str(HELPER), command, "--dry-run"], io.StringIO(json.dumps(request))
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                try:
                    status = helper.main()
                except SystemExit as leaving:
                    status = leaving.code if isinstance(leaving.code, int) else 1
                except Exception:  # noqa: BLE001 - a traceback is what is being looked for
                    traceback.print_exc()
                    status = 1
        finally:
            sys.argv, sys.stdin = saved
        return Done(status, out.getvalue(), err.getvalue())
    return run


def missing_bindings(answer):
    return answer is not None and answer.get("ok") is False and "missing" in str(answer.get("error", ""))


run = run_process
first = run("add", {"allDay": True, "day": "2026-09-20", "title": "x"})
where = "the helper's own process"
if missing_bindings(answer_of(first.stdout)):
    run = run_in_process(load_with_stand_ins())
    where = "stand-ins for the Akonadi bindings, not installed here"
    first = run("add", {"allDay": True, "day": "2026-09-20", "title": "x"})
answer = answer_of(first.stdout)
check(answer is not None and answer.get("ok") is True and answer.get("dryRun") is True,
      f"a well-formed dry run answers ok: {first.stdout!r} {first.stderr!r}")
check("DTSTART;VALUE=DATE:20260920" in str(answer.get("ical", "")) if answer else False, "and builds the day")
check(first.returncode == 0, "and exits 0")

# A day that is not YYYY-MM-DD used to go into DTSTART as it was, or raise
# somewhere inside the date arithmetic with the traceback on stderr and an
# empty stdout the shell could not parse.
for request in ({"allDay": True, "day": "20.09.2026"}, {"allDay": True, "day": "2026-09-20", "endDay": "tomorrow"},
                {"allDay": False, "day": ["2026-09-20"], "start": "09:00"}):
    done = run("add", request)
    answer = answer_of(done.stdout)
    check(answer is not None and answer.get("ok") is False, f"a malformed day is refused with JSON: {request}")
    check(answer is not None and "date" in str(answer.get("error", "")), f"and the error names the format: {request}")
    check("Traceback" not in done.stderr, f"and there is no traceback: {request}")
    check(done.returncode == 1, f"and the exit status is the JSON one: {request}")

# The same for a modify whose changes carry a bad day.
done = run("modify", {"item": 1, "changes": {"day": "next week"}})
answer = answer_of(done.stdout)
check(answer is not None and answer.get("ok") is False and "day" in str(answer.get("error", "")),
      "a bad day inside `changes` is refused before anything is fetched")

# A field of the wrong shape: the count is not a number. That raised
# ValueError inside rule_of and the shell saw no answer at all.
done = run("add", {"allDay": True, "day": "2026-09-20", "repeat": "weekly", "count": "many"})
answer = answer_of(done.stdout)
check(answer is not None and answer.get("ok") is False, "a count that is not a number is refused with JSON")
check("Traceback" not in done.stderr and done.returncode == 1, "without a traceback")

# A request that is not a JSON object at all.
done = run("add", ["not", "an", "object"])
answer = answer_of(done.stdout)
check(answer is not None and answer.get("ok") is False and "could not be read" in str(answer.get("error", "")),
      "a request that is no object is refused with JSON")

if failures:
    for message in failures:
        print("FAIL", message)
    print(f"TESTS FAILED calendar_helper_test (against {where})")
    sys.exit(1)
print(f"TESTS PASSED calendar_helper_test (against {where})")
