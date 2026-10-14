#!/usr/bin/env python3
"""scripts/calendar-helper.py exclude: the order of its Akonadi jobs.

Deleting one occurrence of a series writes an EXDATE on the series and removes
the moved copy of that day, if there is one. The series has to be written
first: a write that fails (another client changed it, a revision conflict)
must leave the moved copy where it was, not gone with the day back in its
place. The helper is loaded against stand-ins for PySide6 and the Akonadi
bindings and its command is driven by hand, job by job - nothing here talks to
Akonadi, and it runs where the bindings are not packaged (Leap, Arch).
"""

import argparse
import contextlib
import importlib.util
import io
import pathlib
import sys
import types

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


class Job:
    def __init__(self, item):
        self.item = item
        self.kind = type(self).__name__

    def fetchScope(self):
        return types.SimpleNamespace(fetchFullPayload=lambda _on: None, setAncestorRetrieval=lambda _how: None)


class Item:
    def __init__(self, value=None):
        self.value = value

    def id(self):
        return self.value

    def setRevision(self, _revision):
        pass

    def setMimeType(self, _mime):
        pass

    def setPayloadFromData(self, _data):
        pass


akonadi = types.SimpleNamespace(
    Item=Item,
    ItemFetchJob=type("ItemFetchJob", (Job,), {}),
    ItemModifyJob=type("ItemModifyJob", (Job,), {}),
    ItemDeleteJob=type("ItemDeleteJob", (Job,), {}),
    ItemFetchScope=types.SimpleNamespace(AncestorRetrieval=types.SimpleNamespace(Parent=1)),
)
qtcore = types.ModuleType("PySide6.QtCore")
qtcore.QByteArray = bytes
qtcore.QCoreApplication = qtcore.QTimeZone = qtcore.QTimer = object
pyside = types.ModuleType("PySide6")
pyside.QtCore = qtcore
akonadi_core = types.ModuleType("AkonadiCore")
akonadi_core.Akonadi = akonadi
sys.modules.update({"PySide6": pyside, "PySide6.QtCore": qtcore, "AkonadiCore": akonadi_core})

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("calendar_helper", ROOT / "scripts" / "calendar-helper.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

SERIES = "\r\n".join([
    "BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:series-1", "DTSTAMP:20260901T090000Z",
    "SUMMARY:Invented", "DTSTART:20260907T093000", "DTEND:20260907T094500", "RRULE:FREQ=WEEKLY;BYDAY=MO",
    "END:VEVENT", "END:VCALENDAR", ""])
MOVED = SERIES.replace("RRULE:FREQ=WEEKLY;BYDAY=MO", "RECURRENCE-ID:20260914T093000")
ITEMS = {10: {"id": 10, "revision": 3, "collection": 7, "text": SERIES},
         11: {"id": 11, "revision": 1, "collection": 7, "text": MOVED}}


def exclude(request, fail=None):
    """Drive the command to its end; `fail` is the job kind that reports an error."""
    steps = helper.command_exclude(request, argparse.Namespace(dry_run=False))
    done, sent, error = [], None, None
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        while True:
            try:
                job, _collect = steps.throw(error) if error else steps.send(sent)
            except StopIteration:
                return done, "ok"
            except helper.Failed:
                return done, "failed"
            done.append((job.kind, job.item.id()))
            sent, error = None, None
            if job.kind == fail:
                error = helper.Failed("the item was changed in the meantime")
            elif job.kind == "ItemFetchJob":
                sent = [ITEMS[job.item.id()]] if job.item.id() in ITEMS else []


request = {"item": 10, "recurrenceId": "20260914T093000", "exception": 11}
jobs, outcome = exclude(request)
check(outcome == "ok", "an exclude with a moved copy goes through: %s" % outcome)
check(jobs == [("ItemFetchJob", 10), ("ItemFetchJob", 11), ("ItemModifyJob", 10), ("ItemDeleteJob", 11)],
      "both are read, then the series is written, then the moved copy removed: %s" % jobs)

jobs, outcome = exclude(request, fail="ItemModifyJob")
check(outcome == "failed", "a failed write of the series is a failure: %s" % outcome)
check(("ItemDeleteJob", 11) not in jobs, "and the moved copy is not removed: %s" % jobs)

jobs, outcome = exclude({"item": 10, "recurrenceId": "20260914T093000"})
check(jobs == [("ItemFetchJob", 10), ("ItemModifyJob", 10)], "without a moved copy only the series is written: %s" % jobs)

jobs, outcome = exclude({"item": 10, "recurrenceId": "20260914T093000", "exception": 99})
check(outcome == "ok" and ("ItemDeleteJob", 99) not in jobs, "a moved copy already gone is not removed again: %s" % jobs)

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED calendar_exclude_test")
    sys.exit(1)
print("TESTS PASSED calendar_exclude_test")
