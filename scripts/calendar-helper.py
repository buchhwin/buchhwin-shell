#!/usr/bin/env python3
"""Calendar writes for buchhwin-shell, straight against Akonadi.

konsolekalendar cannot do recurrence at all - its handbook never mentions
RRULE - and it reports success even when a read-only calendar ignored the
change. This helper talks to Akonadi's item API instead, so a plain event, a
series and a single occurrence of one all go the same way, and a failed job is
a failure.

Every command reads one JSON object from stdin and prints exactly one JSON
object on stdout. Event titles, locations and notes never appear in the
arguments and are never logged: they are private data in a public repository.

  calendar-helper.py check                bindings, Akonadi, the system zone
  calendar-helper.py collections          the calendars and who may write
  calendar-helper.py resolve      < json  a shown event -> its stored incidence
  calendar-helper.py add          < json  a new event, with or without a rule
  calendar-helper.py modify       < json  a whole event or a whole series
  calendar-helper.py occurrence   < json  change one occurrence of a series
  calendar-helper.py exclude      < json  drop one occurrence from a series
  calendar-helper.py delete       < json  an event or a whole series

`--dry-run` prints the iCalendar that would be written and touches nothing.

Two things about the bindings, each of which cost a crash before it was
understood:

  * an Akonadi job deletes itself once it emitted result(), and so do the
    collections and items it handed out, so everything is copied into plain
    values inside the slot;
  * QCoreApplication.exec() cannot be entered a second time here - the second
    call segfaults. Every command is therefore a generator that yields one job
    at a time, and drive() runs the whole chain in a single event loop.

The iCalendar itself is built and read in scripts/lib/ical.py, which has no
Akonadi in it and is unit tested on its own (tests/python/ical_test.py).
"""

import argparse
import datetime
import json
import os
import pathlib
import sys
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))
import ical  # noqa: E402

EVENT_MIME = "application/x-vnd.akonadi.calendar.event"
# Akonadi answers in milliseconds; nothing here should ever take this long.
TIMEOUT_MS = 30000


def result(**values):
    print(json.dumps(values, ensure_ascii=False))
    return 0 if values.get("ok") else 1


def read_request():
    try:
        text = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not text.strip():
        return {}
    try:
        value = json.loads(text)
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def real_session():
    """The same rule the shell uses: never touch the host's Akonadi from a test.

    A nested session has its own configuration directory and sets
    BUCHHWIN_NESTED, and either one alone is enough to stay out.
    """
    if os.environ.get("BUCHHWIN_NESTED") == "1":
        return False
    config = os.environ.get("XDG_CONFIG_HOME", "")
    default = str(pathlib.Path.home() / ".config")
    return not config or os.path.realpath(config) == os.path.realpath(default)


try:
    from PySide6.QtCore import QByteArray, QCoreApplication, QTimeZone, QTimer
    from AkonadiCore import Akonadi
except ImportError as error:  # pragma: no cover - environment check
    print(json.dumps({"ok": False,
                      "error": "python3-kf6-kcoreaddons and python3-kf6-kcalendarcore "
                               "are missing", "detail": str(error)}))
    sys.exit(1)


class Failed(Exception):
    """An Akonadi job reported an error; the command stops and says so."""


def drive(steps):
    """Run a generator of Akonadi jobs to its end in one event loop.

    The generator yields (job, collect). `collect` reads what is needed while
    the job is still alive, and its value is sent back into the generator.
    """
    app = QCoreApplication.instance() or QCoreApplication(sys.argv)
    state = {"value": None, "raised": None}
    running = []
    guard = QTimer()
    guard.setSingleShot(True)
    guard.timeout.connect(lambda: give_up(state, app))

    def advance(sent=None, error=None):
        try:
            job, collect = steps.throw(error) if error else steps.send(sent)
        except StopIteration as done:
            state["value"] = done.value
        except Failed as failure:
            state["raised"] = failure
        else:
            def finished(ready):
                problem = Failed(ready.errorString()) if ready.error() else None
                value = None if problem else (collect(ready) if collect else None)
                QTimer.singleShot(0, lambda: advance(value, problem))

            # The list is what keeps the job alive. Nothing else holds a
            # Python reference once this function returns, and a collected
            # wrapper takes the job with it - it then never starts, the event
            # loop finds nothing to do and exec() comes back having done
            # nothing at all. The wrappers are kept to the end on purpose:
            # dropping one while its job is still running is the crash this
            # replaced.
            running.append(job)
            job.result.connect(finished)
            guard.start(TIMEOUT_MS)
            return
        guard.stop()
        app.quit()

    QTimer.singleShot(0, advance)
    app.exec()
    if state["raised"]:
        raise state["raised"]
    return state["value"]


def give_up(state, app):
    state["raised"] = state["raised"] or Failed("Akonadi did not answer.")
    app.quit()


# ---- reading Akonadi -----------------------------------------------------

def copy_item(item):
    """Everything this helper needs from an item, as plain values."""
    return {"id": item.id(), "revision": item.revision(),
            "collection": item.parentCollection().id(),
            "text": bytes(item.payloadData()).decode("utf-8", "replace")}


def fetch_calendars():
    """Every calendar as {id, name, resource, writable}."""
    can_create = int(Akonadi.Collection.CanCreateItem)

    def collect(job):
        return [{"id": collection.id(), "name": collection.name(),
                 "resource": collection.resource(),
                 "writable": bool(int(collection.rights()) & can_create)}
                for collection in job.collections()
                if EVENT_MIME in list(collection.contentMimeTypes())]

    job = Akonadi.CollectionFetchJob(Akonadi.Collection.root(),
                                     Akonadi.CollectionFetchJob.Recursive)
    calendars = yield (job, collect)
    return calendars or []


def fetch_items(collection_id):
    job = Akonadi.ItemFetchJob(Akonadi.Collection(int(collection_id)))
    job.fetchScope().fetchFullPayload(True)
    items = yield (job, lambda ready: [copy_item(item) for item in ready.items()])
    return items or []


def fetch_item(item_id):
    try:
        wanted = Akonadi.Item(int(item_id))
    except (TypeError, ValueError):
        return None
    job = Akonadi.ItemFetchJob(wanted)
    job.fetchScope().fetchFullPayload(True)
    # Fetched by id, an item knows no parent unless it is asked for - and an
    # exception has to be created in the same calendar as its series.
    job.fetchScope().setAncestorRetrieval(Akonadi.ItemFetchScope.AncestorRetrieval.Parent)
    items = yield (job, lambda ready: [copy_item(item) for item in ready.items()])
    return items[0] if items else None


def fetch_stored():
    """Every stored event, with the item and calendar it came from."""
    rows = []
    for calendar in (yield from fetch_calendars()):
        for item in (yield from fetch_items(calendar["id"])):
            for event in ical.events(item["text"]):
                rows.append({"event": event, "item": item, "collection": calendar["id"],
                             "writable": calendar["writable"]})
    return rows


# ---- writing Akonadi -----------------------------------------------------

def payload_item(row, text):
    """An item that writes `text` back over the one `row` was copied from."""
    item = Akonadi.Item(int(row["id"]))
    item.setRevision(int(row["revision"]))
    item.setMimeType(EVENT_MIME)
    item.setPayloadFromData(QByteArray(text.encode("utf-8")))
    return item


def new_item(text):
    item = Akonadi.Item(EVENT_MIME)
    item.setPayloadFromData(QByteArray(text.encode("utf-8")))
    return item


def create(text, collection_id):
    yield (Akonadi.ItemCreateJob(new_item(text), Akonadi.Collection(int(collection_id))), None)


def modify(row, text):
    yield (Akonadi.ItemModifyJob(payload_item(row, text)), None)


def remove(row):
    yield (Akonadi.ItemDeleteJob(Akonadi.Item(int(row["id"]))), None)


# ---- matching a shown event to a stored one ------------------------------

def now_stamp():
    return ical.stamp(datetime.datetime.now(datetime.timezone.utc))


def system_zone():
    return bytes(QTimeZone.systemTimeZoneId()).decode("utf-8", "replace")


def matches(row, request):
    """Does this stored incidence explain the occurrence the shell is showing?"""
    event = row["event"]
    if not ical.same_title(event["summary"], request.get("title", "")):
        return False
    if bool(event["all_day"]) != bool(request.get("allDay")):
        return False
    day = request.get("day", "")
    # Local, not raw: a value stored in UTC names a different day and time than
    # the dashboard is showing, so the raw parts never matched one.
    start_day, start_time = ical.local_parts(event["start"])
    if event["recurrence_id"]:
        return ical.local_parts(event["recurrence_id"])[0] == day or start_day == day
    if not event["rrule"]:
        return start_day == day
    # A series: the dashboard already knows the occurrence falls on that day,
    # so only the time of day and the fact that the series had started need to
    # line up. Expanding the rule would say nothing new.
    if start_day > day:
        return False
    if event["all_day"]:
        return True
    return start_time[:5] == str(request.get("start", ""))[:5]


def describe(row, request, rows):
    """The answer for one matched incidence.

    A changed occurrence is its own incidence, so the answer names both: the
    exception to edit and the series it belongs to, because "all events in the
    series" has to reach the series even when an exception was clicked.
    """
    event = row["event"]
    master = next((other["item"]["id"] for other in rows
                   if other["event"]["uid"] == event["uid"]
                   and other["collection"] == row["collection"]
                   and not other["event"]["recurrence_id"]), 0)
    rule = ical.read_rrule(event["rrule"])
    is_occurrence = bool(event["rrule"]) and not event["recurrence_id"]
    recurrence_id = event["recurrence_id"]
    if is_occurrence:
        # An occurrence's own start is its RECURRENCE-ID, and the shell is
        # showing exactly that day at exactly the series' time of day.
        recurrence_id = (ical.day_value(request.get("day", "")) if event["all_day"]
                         else ical.local_date_time(request.get("day", ""),
                                                   ical.local_parts(event["start"])[1][:5]))
    return {
        "ok": True,
        "uid": event["uid"],
        "item": row["item"]["id"],
        "masterItem": master or (0 if event["recurrence_id"] else row["item"]["id"]),
        "exceptionItem": row["item"]["id"] if event["recurrence_id"] else 0,
        "collection": row["collection"],
        "writable": row["writable"],
        "allDay": event["all_day"],
        "location": event["location"],
        "description": event["description"],
        "recurs": bool(event["rrule"]),
        "isOccurrence": is_occurrence,
        "isException": bool(event["recurrence_id"]),
        "recurrenceId": recurrence_id,
        "rrule": event["rrule"],
        "repeat": rule["repeat"],
        "weekday": rule["weekday"],
        "count": rule["count"],
        "until": rule["until"],
        "ruleKnown": rule["known"],
    }


# ---- the draft the editor sends ------------------------------------------

def shift_day(value, days):
    """"20260920" one day on."""
    moment = datetime.datetime.strptime(value, "%Y%m%d") + datetime.timedelta(days=days)
    return moment.strftime("%Y%m%d")


def until_value(day, all_day):
    """The editor's last day as an UNTIL value: a date, or the end of it in UTC."""
    if not day:
        return ""
    value = ical.day_value(day)
    return value if all_day else value + "T235959Z"


def rule_of(request, all_day):
    """The rule from the editor's fields, or the raw one if it sent one.

    The grammar lives in scripts/lib/ical.py alone: the editor sends what it
    shows - repeat, weekday, how it ends - and never a rule string of its own.
    """
    if "rrule" in request:
        return str(request.get("rrule") or "")
    return ical.build_rrule(str(request.get("repeat") or ""),
                            str(request.get("weekday") or ""),
                            int(request.get("count") or 0),
                            until_value(str(request.get("until") or ""), all_day))


def draft_fields(request, uid=""):
    """The editor's draft as the fields scripts/lib/ical.py writes."""
    all_day = bool(request.get("allDay"))
    if all_day:
        start = ical.day_value(request.get("day", ""))
        # DTEND of an all-day event is exclusive; the editor's "until" is the
        # last day the event covers.
        end = shift_day(ical.day_value(request.get("endDay") or request.get("day", "")), 1)
        zone = ""
    else:
        start = ical.local_date_time(request.get("day", ""), request.get("start", ""))
        end_day = request.get("endDay") or request.get("day", "")
        end = ical.local_date_time(end_day, request.get("end", ""))
        zone = request.get("zone") or system_zone()
    return {
        "uid": uid or ("buchhwin-" + uuid.uuid4().hex),
        "summary": request.get("title", ""),
        "description": request.get("notes", ""),
        "location": request.get("location", ""),
        "rrule": rule_of(request, all_day),
        "start": start, "end": end, "all_day": all_day, "tzid": zone,
    }


def change_fields(request):
    """Only the fields the editor actually changed reach the payload."""
    changes = {}
    given = request.get("changes") or {}
    for sent, field in (("title", "summary"), ("notes", "description"),
                        ("location", "location")):
        if sent in given:
            changes[field] = given[sent]
    if {"repeat", "rrule", "weekday", "count", "until"} & set(given):
        changes["rrule"] = rule_of(given, bool(given.get("allDay", request.get("allDay"))))
    if {"day", "start", "end", "allDay", "endDay"} & set(given):
        times = draft_fields({
            "allDay": given.get("allDay", request.get("allDay")),
            "day": given.get("day", request.get("day")),
            "endDay": given.get("endDay", request.get("endDay")),
            "start": given.get("start", request.get("start")),
            "end": given.get("end", request.get("end")),
            "zone": given.get("zone", request.get("zone")),
        })
        changes.update(start=times["start"], end=times["end"],
                       all_day=times["all_day"], tzid=times["tzid"])
    return changes


# ---- commands ------------------------------------------------------------

def command_check(_request, _args):
    calendars = yield from fetch_calendars()
    return result(ok=True, calendars=len(calendars), zone=system_zone())


def command_collections(_request, _args):
    calendars = yield from fetch_calendars()
    return result(ok=True, calendars=calendars)


def command_resolve(request, _args):
    stored = yield from fetch_stored()
    rows = [row for row in stored if matches(row, request)]
    if not rows:
        return result(ok=False, reason="notFound")
    # An occurrence that was changed once is stored next to its series and
    # explains the shown day better than the series does.
    exceptions = [row for row in rows if row["event"]["recurrence_id"]]
    if exceptions:
        rows = exceptions
    if len({(row["event"]["uid"], row["collection"]) for row in rows}) > 1:
        return result(ok=False, reason="ambiguous")
    return result(**describe(rows[0], request, stored))


def command_add(request, args):
    collection_id = request.get("collection")
    fields = draft_fields(request)
    text = ical.build(fields, now_stamp())
    if args.dry_run:
        return result(ok=True, dryRun=True, ical=text, uid=fields["uid"])
    calendars = {calendar["id"]: calendar for calendar in (yield from fetch_calendars())}
    if collection_id not in calendars:
        return result(ok=False, error="That calendar is not there any more.")
    if not calendars[collection_id]["writable"]:
        return result(ok=False, error="This calendar cannot be written to.")
    yield from create(text, collection_id)
    return result(ok=True, uid=fields["uid"])


def command_modify(request, args):
    item = yield from fetch_item(request.get("item"))
    if item is None:
        return result(ok=False, error="The event is not there any more.")
    text = ical.patch(item["text"], change_fields(request), now_stamp())
    if args.dry_run:
        return result(ok=True, dryRun=True, ical=text)
    yield from modify(item, text)
    return result(ok=True)


def command_occurrence(request, args):
    """Change one occurrence: a second incidence with the same UID."""
    master = yield from fetch_item(request.get("item"))
    if master is None:
        return result(ok=False, error="The series is not there any more.")
    recurrence_id = request.get("recurrenceId", "")
    if not recurrence_id:
        return result(ok=False, error="This occurrence cannot be identified.")
    text = ical.occurrence(master["text"], recurrence_id, change_fields(request), now_stamp())
    if not text:
        return result(ok=False, error="This series could not be read.")
    if args.dry_run:
        return result(ok=True, dryRun=True, ical=text)
    yield from create(text, master["collection"])
    return result(ok=True)


def command_exclude(request, args):
    """Delete one occurrence: an EXDATE on the series.

    An occurrence that had been moved is its own incidence, so it is removed as
    well - excluding the day alone would leave the moved copy behind.
    """
    master = yield from fetch_item(request.get("item"))
    if master is None:
        return result(ok=False, error="The series is not there any more.")
    recurrence_id = request.get("recurrenceId", "")
    if not recurrence_id:
        return result(ok=False, error="This occurrence cannot be identified.")
    text = ical.add_exdate(master["text"], recurrence_id, now_stamp())
    if args.dry_run:
        return result(ok=True, dryRun=True, ical=text)
    exception = request.get("exception") or 0
    if exception:
        stale = yield from fetch_item(exception)
        if stale is not None:
            yield from remove(stale)
    yield from modify(master, text)
    return result(ok=True)


def command_delete(request, args):
    item = yield from fetch_item(request.get("item"))
    if item is None:
        return result(ok=False, error="The event is not there any more.")
    if args.dry_run:
        return result(ok=True, dryRun=True)
    yield from remove(item)
    return result(ok=True)


COMMANDS = {
    "check": (command_check, False),
    "collections": (command_collections, False),
    "resolve": (command_resolve, False),
    "add": (command_add, True),
    "modify": (command_modify, True),
    "occurrence": (command_occurrence, True),
    "exclude": (command_exclude, True),
    "delete": (command_delete, True),
}


def main():
    parser = argparse.ArgumentParser(description="Calendar writes through Akonadi.")
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("--dry-run", action="store_true",
                        help="print the iCalendar instead of writing it")
    args = parser.parse_args()
    handler, writes = COMMANDS[args.command]
    if writes and not args.dry_run and not real_session():
        return result(ok=False, error="Calendar writes only run in the real session.")
    request = read_request()
    if request is None:
        return result(ok=False, error="The request could not be read.")
    try:
        return drive(handler(request, args))
    except Failed as failure:
        return result(ok=False, error=str(failure))


if __name__ == "__main__":
    sys.exit(main())
