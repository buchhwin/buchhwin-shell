#!/usr/bin/env python3
"""Unit test for scripts/lib/ical.py: parsing, patching and recurrence rules.

Pure text, no Akonadi. The payloads below have the shape a real one has: a
VCALENDAR with its VTIMEZONE and exactly one VEVENT, and the VTIMEZONE carries
its own RRULE - which the parser must not mistake for the event's.
"""

import importlib.util
import os
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ical", ROOT / "scripts" / "lib" / "ical.py")
ical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ical)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


STAMP = "20260918T090000Z"

SERIES = "\r\n".join([
    "BEGIN:VCALENDAR",
    "PRODID:-//K Desktop Environment//NONSGML libkcal 4.3//EN",
    "VERSION:2.0",
    "BEGIN:VTIMEZONE",
    "TZID:Europe/Berlin",
    "BEGIN:DAYLIGHT",
    "TZOFFSETFROM:+0100",
    "TZOFFSETTO:+0200",
    "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3",
    "DTSTART:19810329T020000",
    "TZNAME:CEST",
    "END:DAYLIGHT",
    "END:VTIMEZONE",
    "BEGIN:VEVENT",
    "DTSTAMP:20260901T090000Z",
    "CREATED:20260901T090000Z",
    "UID:series-1234",
    "LAST-MODIFIED:20260901T090000Z",
    "SUMMARY:Team standup",
    "LOCATION:Room 2\\, upstairs",
    "DTSTART;TZID=Europe/Berlin:20260907T093000",
    "DTEND;TZID=Europe/Berlin:20260907T094500",
    "RRULE:FREQ=WEEKLY;BYDAY=MO",
    "ORGANIZER;CN=Someone:mailto:someone@example.org",
    "ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@example.org",
    "X-KDE-SOMETHING:keep me",
    "BEGIN:VALARM",
    "ACTION:DISPLAY",
    "TRIGGER:-PT15M",
    "END:VALARM",
    "TRANSP:OPAQUE",
    "END:VEVENT",
    "END:VCALENDAR",
]) + "\r\n"

ALL_DAY = "\r\n".join([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "UID:allday-1",
    "SUMMARY:Holiday",
    "DTSTART;VALUE=DATE:20260920",
    "DTEND;VALUE=DATE:20260922",
    "END:VEVENT",
    "END:VCALENDAR",
]) + "\r\n"

# ---- parsing -------------------------------------------------------------

found = ical.events(SERIES)
check(len(found) == 1, "one VEVENT, not the VTIMEZONE blocks: %d" % len(found))
event = found[0]
check(event["uid"] == "series-1234", "uid: %r" % event["uid"])
check(event["summary"] == "Team standup", "summary: %r" % event["summary"])
check(event["location"] == "Room 2, upstairs", "escaped comma read back: %r" % event["location"])
check(event["rrule"] == "FREQ=WEEKLY;BYDAY=MO",
      "the event's rule, not the time zone's: %r" % event["rrule"])
check(event["tzid"] == "Europe/Berlin", "tzid: %r" % event["tzid"])
check(event["start"] == "20260907T093000", "start: %r" % event["start"])
check(not event["all_day"], "a timed event is not all day")

day = ical.events(ALL_DAY)[0]
check(day["all_day"], "VALUE=DATE is all day")
check(day["start"] == "20260920", "all-day start: %r" % day["start"])

check(ical.parse_value("20260920T093000") == ("2026-09-20", "09:30:00", False), "parse date-time")
check(ical.parse_value("20260920T073000Z") == ("2026-09-20", "07:30:00", True), "parse UTC")
check(ical.parse_value("20260920") == ("2026-09-20", "", False), "parse date")

# Folding and unfolding survive a long value with multi-byte characters.
long_line = "DESCRIPTION:" + "Grüße " * 20
check(ical.unfold(ical.fold(long_line)) == [long_line], "fold/unfold round trip")
check(all(len(part.encode()) <= 76 for part in ical.fold(long_line).split("\n")),
      "no folded part is longer than the limit")

# ---- patching ------------------------------------------------------------

moved = ical.patch(SERIES, {"summary": "Standup", "start": "20260907T100000",
                            "end": "20260907T101500"}, STAMP)
after = ical.events(moved)[0]
check(after["summary"] == "Standup", "patched summary: %r" % after["summary"])
check(after["start"] == "20260907T100000", "patched start: %r" % after["start"])
check(after["tzid"] == "Europe/Berlin", "the zone survives a time change")
check(after["rrule"] == "FREQ=WEEKLY;BYDAY=MO", "an untouched rule stays")
check("ORGANIZER;CN=Someone:mailto:someone@example.org" in moved, "ORGANIZER survives")
check("ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@example.org" in moved, "ATTENDEE survives")
check("X-KDE-SOMETHING:keep me" in moved, "an unknown X- property survives")
check("BEGIN:VALARM" in moved and "TRIGGER:-PT15M" in moved, "the alarm survives")
check("BEGIN:VTIMEZONE" in moved and "TZNAME:CEST" in moved, "the time zone block survives")
check(moved.count("SUMMARY:") == 1, "the old summary is gone, not doubled")
check(moved.count("DTSTART") == 2, "one DTSTART in the event, one in the time zone")
check("LAST-MODIFIED:" + STAMP in moved, "LAST-MODIFIED is refreshed")
check(moved.count("LAST-MODIFIED:") == 1, "LAST-MODIFIED is not doubled")

cleared = ical.patch(SERIES, {"location": ""}, STAMP)
check("LOCATION" not in cleared, "an emptied field removes its property")

unrolled = ical.patch(SERIES, {"rrule": ""}, STAMP)
check("RRULE:FREQ=WEEKLY" not in unrolled, "the event's rule can be dropped")
check("RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3" in unrolled,
      "dropping the event's rule leaves the time zone's alone")

# ---- one occurrence ------------------------------------------------------

excluded = ical.add_exdate(SERIES, "20260914T093000", STAMP)
check("EXDATE;TZID=Europe/Berlin:20260914T093000" in excluded, "EXDATE written with the zone")
check(ical.events(excluded)[0]["exdates"] == ["20260914T093000"], "EXDATE read back")
twice = ical.add_exdate(excluded, "20260914T093000", STAMP)
check(twice.count("EXDATE") == 1, "the same occurrence is not excluded twice")

exception = ical.occurrence(SERIES, "20260914T093000",
                            {"start": "20260914T110000", "end": "20260914T111500"}, STAMP)
one = ical.events(exception)[0]
check(one["uid"] == "series-1234", "an exception keeps the series UID")
check(one["recurrence_id"] == "20260914T093000", "recurrence id: %r" % one["recurrence_id"])
check(one["start"] == "20260914T110000", "the moved occurrence has the new time")
check(not one["rrule"], "an exception carries no rule of its own")
check(exception.count("RECURRENCE-ID") == 1, "exactly one RECURRENCE-ID")
check("BEGIN:VALARM" in exception, "the exception inherits the alarm")
check("ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@example.org" in exception,
      "the exception inherits the attendees")

# ---- recurrence rules ----------------------------------------------------

check(ical.build_rrule("") == "", "no recurrence is no rule")
check(ical.build_rrule("daily") == "FREQ=DAILY", "daily")
check(ical.build_rrule("weekly", "MO") == "FREQ=WEEKLY;BYDAY=MO", "weekly on a day")
check(ical.build_rrule("weekdays") == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "weekdays")
check(ical.build_rrule("monthly", count=5) == "FREQ=MONTHLY;COUNT=5", "monthly, five times")
check(ical.build_rrule("yearly", until="20301231T000000Z") == "FREQ=YEARLY;UNTIL=20301231T000000Z",
      "yearly until a date")
check(ical.build_rrule("weekly", "MO", count=3, until="20301231T000000Z")
      == "FREQ=WEEKLY;BYDAY=MO;COUNT=3", "a count wins over an end date")

back = ical.read_rrule("FREQ=WEEKLY;BYDAY=MO")
check(back["repeat"] == "weekly" and back["weekday"] == "MO" and back["known"], "read weekly: %r" % back)
check(ical.read_rrule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")["repeat"] == "weekdays", "read weekdays")
check(ical.read_rrule("FREQ=DAILY;COUNT=4")["count"] == 4, "read a count")
check(not ical.read_rrule("FREQ=MONTHLY;BYSETPOS=-1;BYDAY=FR")["known"],
      "a rule the editor cannot show again is reported as unknown")
check(not ical.read_rrule("FREQ=DAILY;INTERVAL=3")["known"], "an interval is not ours")
check(ical.read_rrule("")["repeat"] == "" and ical.read_rrule("")["known"], "no rule is known")

for name in ("daily", "weekly", "monthly", "yearly", "weekdays"):
    rule = ical.build_rrule(name, "MO")
    check(ical.read_rrule(rule)["repeat"] == name, "round trip %s: %r" % (name, rule))

# ---- matching a shown occurrence to a stored one -------------------------
# The two the shell's own Google events used to fall through.

# A UTC value names a different day and time than the dashboard is showing.
os.environ["TZ"] = "Europe/Berlin"
time.tzset()
check(ical.local_parts("20260920T073000Z") == ("2026-09-20", "09:30:00"),
      "a summer UTC value is read in the local zone: %r" % (ical.local_parts("20260920T073000Z"),))
check(ical.local_parts("20261220T230000Z") == ("2026-12-21", "00:00:00"),
      "and one that crosses midnight moves the day too: %r" % (ical.local_parts("20261220T230000Z"),))
check(ical.local_parts("20260920T093000") == ("2026-09-20", "09:30:00"),
      "a floating value is already local")
check(ical.local_parts("20260920") == ("2026-09-20", ""), "and an all-day value has no time at all")
check(ical.local_parts("") == ("", ""), "nonsense is nothing")

# The dashboard trims what it shows, so a stored SUMMARY with whitespace in it
# never equalled the title that came back from it.
check(ical.normalized_title("  Team\n meeting  ") == "Team meeting", "titles collapse their whitespace")
check(ical.normalized_title(None) == "", "and nothing is nothing")
check(ical.same_title("  Team  meeting ", "Team meeting"), "a padded stored title still matches")
check(ical.same_title("Team meeting", "  Team meeting  "), "and a padded wanted one does too")
check(ical.same_title("", "(No title)"), "an untitled event matches the placeholder")
check(ical.same_title("   ", "(No title)"), "even one whose title is only spaces")
check(ical.same_title("", ""), "and an empty request")
check(not ical.same_title("Team meeting", "(No title)"), "but a titled event is not untitled")
check(not ical.same_title("Team meeting", "Other meeting"), "and two titles are two titles")

if failures:
    for message in failures:
        print("FAIL " + message)
    print("TESTS FAILED ical_test (%d failed)" % len(failures))
    sys.exit(1)
print("TESTS PASSED ical_test")
