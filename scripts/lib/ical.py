"""iCalendar reading and writing for scripts/calendar-helper.py.

Pure text work, no Akonadi and no KDE bindings, so it is unit tested without a
session (tests/python/ical_test.py). KCalendarCore's Python bindings cannot do
this job: Calendar/MemoryCalendar are bound without addEvent(), events() or
event(), so there is no way to put an incidence into a calendar and serialise
it. Editing the text directly is also the safer half of the trade: every
property the shell does not know about - ORGANIZER, ATTENDEE, SEQUENCE, X-*,
the VALARM block, the VTIMEZONE definitions - survives an edit untouched.

One Akonadi item holds one VCALENDAR with its VTIMEZONEs and exactly one
VEVENT. A recurring event is one item for the series; an occurrence that was
changed is a second item with the same UID and a RECURRENCE-ID.
"""

import datetime
import re

# RFC 5545: a line longer than 75 octets continues on the next line, which
# starts with one space or tab.
FOLD_LIMIT = 75

# Properties the shell owns. Everything else in a VEVENT is copied unchanged.
OWNED = (
    "DTSTART", "DTEND", "DURATION", "SUMMARY", "DESCRIPTION", "LOCATION",
    "RRULE", "EXDATE", "RECURRENCE-ID", "LAST-MODIFIED", "DTSTAMP", "SEQUENCE",
)

DATE = re.compile(r"^(\d{4})(\d{2})(\d{2})$")
DATETIME = re.compile(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$")


def unfold(text):
    """Split into logical lines, joining RFC 5545 continuations."""
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return [line for line in lines if line]


def fold(line):
    """Break one logical line at 75 octets, continuing with a space."""
    data = line.encode("utf-8")
    if len(data) <= FOLD_LIMIT:
        return line
    parts = []
    while data:
        cut = min(FOLD_LIMIT if not parts else FOLD_LIMIT - 1, len(data))
        # Never cut inside a UTF-8 sequence: a continuation byte is 10xxxxxx.
        while cut > 1 and cut < len(data) and (data[cut] & 0xC0) == 0x80:
            cut -= 1
        chunk, data = data[:cut], data[cut:]
        parts.append(chunk.decode("utf-8"))
    return parts[0] + "".join("\n " + part for part in parts[1:])


def split_property(line):
    """'DTSTART;TZID=Europe/Berlin:20260920T093000' -> name, params, value."""
    head, _, value = partition_unquoted(line, ":")
    name, _, param_text = partition_unquoted(head, ";")
    params = {}
    while param_text:
        piece, _, param_text = partition_unquoted(param_text, ";")
        key, _, val = piece.partition("=")
        if key:
            params[key.strip().upper()] = val.strip().strip('"')
    return name.strip().upper(), params, value


def partition_unquoted(text, sep):
    """partition(), but a separator inside double quotes does not count."""
    quoted = False
    for index, char in enumerate(text):
        if char == '"':
            quoted = not quoted
        elif char == sep and not quoted:
            return text[:index], sep, text[index + 1:]
    return text, "", ""


def components(text):
    """Every component as (name, [lines]), nested ones included, in order."""
    found = []
    stack = []
    for line in unfold(text):
        name, _, value = split_property(line)
        if name == "BEGIN":
            stack.append((value.strip().upper(), []))
            continue
        if name == "END":
            if not stack:
                continue
            done = stack.pop()
            found.append(done)
            continue
        if stack:
            stack[-1][1].append(line)
    return found


def events(text):
    """The VEVENT components of a payload, parsed. Ignores VTIMEZONE rules."""
    return [fields(lines) for name, lines in components(text) if name == "VEVENT"]


def fields(lines):
    """The properties the shell cares about, from one VEVENT's lines."""
    event = {
        "uid": "", "summary": "", "description": "", "location": "",
        "rrule": "", "recurrence_id": "", "exdates": [],
        "start": "", "end": "", "all_day": False, "tzid": "",
    }
    for line in lines:
        name, params, value = split_property(line)
        if name == "UID":
            event["uid"] = unescape(value)
        elif name == "SUMMARY":
            event["summary"] = unescape(value)
        elif name == "DESCRIPTION":
            event["description"] = unescape(value)
        elif name == "LOCATION":
            event["location"] = unescape(value)
        elif name == "RRULE":
            event["rrule"] = value.strip()
        elif name == "RECURRENCE-ID":
            event["recurrence_id"] = value.strip()
        elif name == "EXDATE":
            event["exdates"].extend(part for part in value.split(",") if part)
        elif name == "DTSTART":
            event["start"] = value.strip()
            event["all_day"] = params.get("VALUE", "") == "DATE" or bool(DATE.match(value.strip()))
            event["tzid"] = params.get("TZID", "")
        elif name == "DTEND":
            event["end"] = value.strip()
    return event


def escape(value):
    """RFC 5545 text escaping. Order matters: backslash first."""
    return (str(value).replace("\\", "\\\\").replace(";", "\\;")
            .replace(",", "\\,").replace("\n", "\\n"))


def unescape(value):
    out = []
    index = 0
    while index < len(value):
        char = value[index]
        if char == "\\" and index + 1 < len(value):
            nxt = value[index + 1]
            out.append("\n" if nxt in ("n", "N") else nxt)
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def stamp(moment):
    """A datetime as a UTC DTSTAMP value."""
    return moment.strftime("%Y%m%dT%H%M%SZ")


def local_date_time(day, time_of_day):
    """'2026-09-20' + '09:30' -> '20260920T093000'."""
    return day.replace("-", "") + "T" + time_of_day.replace(":", "") + "00"


def day_value(day):
    """'2026-09-20' -> '20260920'."""
    return day.replace("-", "")


def parse_value(value):
    """An iCalendar date or date-time -> (date, time, utc) as plain strings."""
    value = value.strip()
    match = DATETIME.match(value)
    if match:
        year, month, day, hour, minute, second, zulu = match.groups()
        return f"{year}-{month}-{day}", f"{hour}:{minute}:{second}", zulu == "Z"
    match = DATE.match(value)
    if match:
        year, month, day = match.groups()
        return f"{year}-{month}-{day}", "", False
    return "", "", False


def local_parts(value):
    """An iCalendar value as the *local* day and time the shell would show.

    A value stored in UTC - which is how Google stores most of what it syncs -
    names a different day and time than the one on screen, so comparing the raw
    parts against what the shell sends never matched and a Google event could
    not be resolved at all. A floating or zoned value is already local as far
    as this comparison is concerned and is handed back unchanged.
    """
    day, time_of_day, utc = parse_value(value)
    if not utc or not time_of_day:
        return day, time_of_day
    moment = datetime.datetime.strptime(day + " " + time_of_day, "%Y-%m-%d %H:%M:%S")
    # astimezone() with no argument converts to the system's local zone, which
    # is the zone the dashboard is drawing in.
    local = moment.replace(tzinfo=datetime.timezone.utc).astimezone()
    return local.strftime("%Y-%m-%d"), local.strftime("%H:%M:%S")


def normalized_title(text):
    """A title as the shell sends it: whitespace collapsed and trimmed.

    The dashboard trims what it shows, so a stored SUMMARY with a newline or a
    run of spaces in it never equalled the title that came back from it.
    Collapsing both sides is a superset of trimming both and matches strictly
    more of what is really stored.
    """
    return " ".join(str(text or "").split())


def same_title(stored, wanted):
    """The dashboard shows "(No title)" for an event that has none."""
    want = normalized_title(wanted)
    if want in ("", "(No title)"):
        return normalized_title(stored) == ""
    return normalized_title(stored) == want


def property_line(name, params, value):
    parts = [name]
    for key, val in params.items():
        parts.append(f";{key}={val}")
    return "".join(parts) + ":" + value


def build(fields_in, stamp_value, product_id="-//buchhwin-shell//EN"):
    """A whole VCALENDAR for a new event."""
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:{product_id}", "BEGIN:VEVENT"]
    lines.extend(event_lines(fields_in, stamp_value))
    lines.extend(["END:VEVENT", "END:VCALENDAR"])
    return "\r\n".join(fold(line) for line in lines) + "\r\n"


def event_lines(fields_in, stamp_value):
    """The VEVENT body for a new event, in a stable order."""
    lines = [f"UID:{fields_in['uid']}", f"DTSTAMP:{stamp_value}", f"CREATED:{stamp_value}",
             f"LAST-MODIFIED:{stamp_value}"]
    lines.extend(time_lines(fields_in))
    lines.append("SUMMARY:" + escape(fields_in.get("summary", "")))
    if fields_in.get("description"):
        lines.append("DESCRIPTION:" + escape(fields_in["description"]))
    if fields_in.get("location"):
        lines.append("LOCATION:" + escape(fields_in["location"]))
    if fields_in.get("rrule"):
        lines.append("RRULE:" + fields_in["rrule"])
    if fields_in.get("recurrence_id"):
        lines.append(recurrence_line(fields_in))
    for value in fields_in.get("exdates", []):
        lines.append(exdate_line(value, fields_in))
    lines.append("TRANSP:OPAQUE")
    return lines


def time_lines(fields_in):
    """DTSTART/DTEND, all-day as VALUE=DATE, timed with the event's zone."""
    if fields_in.get("all_day"):
        return [f"DTSTART;VALUE=DATE:{fields_in['start']}", f"DTEND;VALUE=DATE:{fields_in['end']}"]
    tzid = fields_in.get("tzid", "")
    params = {"TZID": tzid} if tzid else {}
    return [property_line("DTSTART", params, fields_in["start"]),
            property_line("DTEND", params, fields_in["end"])]


def recurrence_line(fields_in):
    value = fields_in["recurrence_id"]
    if fields_in.get("all_day"):
        return f"RECURRENCE-ID;VALUE=DATE:{value}"
    tzid = fields_in.get("recurrence_tzid", fields_in.get("tzid", ""))
    return property_line("RECURRENCE-ID", {"TZID": tzid} if tzid else {}, value)


def exdate_line(value, fields_in):
    if fields_in.get("all_day"):
        return f"EXDATE;VALUE=DATE:{value}"
    tzid = fields_in.get("tzid", "")
    return property_line("EXDATE", {"TZID": tzid} if tzid else {}, value)


def patch(text, changes, stamp_value):
    """Replace the shell's properties inside the payload's VEVENT.

    `changes` maps a field name to its new value; a field that is absent is
    left alone, a field set to None is removed. Everything outside the VEVENT
    and every property the shell does not own survives byte for byte.
    """
    lines = unfold(text)
    start, end = vevent_range(lines)
    if start < 0:
        return text
    current = fields(lines[start:end])
    merged = dict(current)
    for key, value in changes.items():
        merged[key] = value
    kept = [line for line in lines[start:end] if keeps(line, changes)]
    kept = [line for line in kept if split_property(line)[0] != "LAST-MODIFIED"]
    kept.append(f"LAST-MODIFIED:{stamp_value}")
    kept.extend(rewritten(merged, changes))
    out = lines[:start] + kept + lines[end:]
    return "\r\n".join(fold(line) for line in out) + "\r\n"


def keeps(line, changes):
    """True while a property is not one the caller is rewriting."""
    name = split_property(line)[0]
    if name in ("DTSTART", "DTEND") and ("start" in changes or "end" in changes
                                         or "all_day" in changes or "tzid" in changes):
        return False
    return name not in rewritten_names(changes)


def rewritten_names(changes):
    names = set()
    for key in changes:
        if key == "summary":
            names.add("SUMMARY")
        elif key == "description":
            names.add("DESCRIPTION")
        elif key == "location":
            names.add("LOCATION")
        elif key == "rrule":
            names.add("RRULE")
        elif key == "exdates":
            names.add("EXDATE")
        elif key == "recurrence_id":
            names.add("RECURRENCE-ID")
    return names


# A changed field with an empty value means "remove this property": that is how
# the editor clears a location or drops a recurrence.
TEXT_FIELDS = (("summary", "SUMMARY"), ("description", "DESCRIPTION"), ("location", "LOCATION"))


def rewritten(merged, changes):
    """The replacement lines for exactly the properties the caller changed."""
    lines = []
    if "start" in changes or "end" in changes or "all_day" in changes or "tzid" in changes:
        lines.extend(time_lines(merged))
    for key, name in TEXT_FIELDS:
        if key in changes and merged.get(key):
            lines.append(name + ":" + escape(merged[key]))
    if "rrule" in changes and merged.get("rrule"):
        lines.append("RRULE:" + merged["rrule"])
    if "recurrence_id" in changes and merged.get("recurrence_id"):
        lines.append(recurrence_line(merged))
    if "exdates" in changes:
        for value in merged.get("exdates") or []:
            lines.append(exdate_line(value, merged))
    return lines


def vevent_range(lines):
    """The half-open range of the VEVENT body inside a payload's lines."""
    start = -1
    for index, line in enumerate(lines):
        name, _, value = split_property(line)
        if name == "BEGIN" and value.strip().upper() == "VEVENT":
            start = index + 1
        elif name == "END" and value.strip().upper() == "VEVENT" and start >= 0:
            return start, index
    return -1, -1


def add_exdate(text, value, stamp_value):
    """Exclude one occurrence from a series."""
    current = events(text)
    exdates = list(current[0]["exdates"]) if current else []
    if value not in exdates:
        exdates.append(value)
    return patch(text, {"exdates": exdates}, stamp_value)


def occurrence(master_text, recurrence_id, changes, stamp_value):
    """A new payload for one changed occurrence of a series.

    The exception is a separate incidence: same UID, its own RECURRENCE-ID, and
    no RRULE of its own. It is built from the master so that everything the
    series carries - attendees, alarms, categories - comes along.
    """
    lines = unfold(master_text)
    start, end = vevent_range(lines)
    if start < 0:
        return ""
    body = [line for line in lines[start:end]
            if split_property(line)[0] not in ("RRULE", "EXDATE", "RDATE", "RECURRENCE-ID")]
    merged = dict(fields(lines[start:end]))
    merged["recurrence_id"] = recurrence_id
    merged["rrule"] = ""
    for key, value in changes.items():
        merged[key] = value
    body = [line for line in body if keeps(line, changes)]
    body = [line for line in body if split_property(line)[0] not in ("LAST-MODIFIED", "SEQUENCE")]
    body.append(f"LAST-MODIFIED:{stamp_value}")
    body.append("SEQUENCE:0")
    body.extend(rewritten(merged, changes))
    body.append(recurrence_line(merged))
    out = lines[:start] + body + lines[end:]
    return "\r\n".join(fold(line) for line in out) + "\r\n"


# ---- recurrence rules ----------------------------------------------------
# The shell offers the handful of rules its editor can also show again. A rule
# it did not write is never rewritten: the editor says what it is and leaves
# it alone.

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
FREQUENCIES = {"daily": "DAILY", "weekly": "WEEKLY", "monthly": "MONTHLY", "yearly": "YEARLY"}


def build_rrule(repeat, weekday="", count=0, until=""):
    """'weekly' + MO -> 'FREQ=WEEKLY;BYDAY=MO'. '' for no recurrence."""
    if repeat in ("", "never"):
        return ""
    if repeat == "weekdays":
        parts = ["FREQ=WEEKLY", "BYDAY=MO,TU,WE,TH,FR"]
    elif repeat in FREQUENCIES:
        parts = ["FREQ=" + FREQUENCIES[repeat]]
        if repeat == "weekly" and weekday in WEEKDAYS:
            parts.append("BYDAY=" + weekday)
    else:
        return ""
    if count > 0:
        parts.append("COUNT=%d" % count)
    elif until:
        parts.append("UNTIL=" + until)
    return ";".join(parts)


def rule_parts(rrule):
    parts = {}
    for piece in (rrule or "").split(";"):
        key, _, value = piece.partition("=")
        if key:
            parts[key.strip().upper()] = value.strip()
    return parts


def read_rrule(rrule):
    """A rule back into the editor's fields, or repeat='' when it is not ours."""
    parts = rule_parts(rrule)
    if not parts:
        return {"repeat": "", "weekday": "", "count": 0, "until": "", "known": True}
    freq = parts.get("FREQ", "")
    days = [day for day in parts.get("BYDAY", "").split(",") if day]
    known = (parts.get("INTERVAL", "1") == "1" and "BYMONTHDAY" not in parts
             and "BYMONTH" not in parts and "BYSETPOS" not in parts
             and all(day in WEEKDAYS for day in days))
    repeat = ""
    weekday = ""
    if freq == "WEEKLY" and sorted(days) == sorted(["MO", "TU", "WE", "TH", "FR"]):
        repeat = "weekdays"
    elif freq == "WEEKLY":
        repeat = "weekly"
        weekday = days[0] if len(days) == 1 else ""
        known = known and len(days) <= 1
    else:
        for name, value in FREQUENCIES.items():
            if value == freq:
                repeat = name
        known = known and not days
    if not repeat:
        known = False
    return {"repeat": repeat, "weekday": weekday,
            "count": int(parts["COUNT"]) if parts.get("COUNT", "").isdigit() else 0,
            "until": parts.get("UNTIL", ""), "known": known}
