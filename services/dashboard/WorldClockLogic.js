.pragma library

// The dashboard's world clock card (shell/dashboard/WorldClockCard.qml): a few
// places and their time beside the local one, with how far ahead or behind
// they are. Pure functions, unit tested in DashboardExtrasTest.qml.
//
// QML's JavaScript knows one time zone, the machine's own: no Intl, and a
// Date's getHours() is always local. So the card asks `date` once for each
// place's offset from UTC (TZ set to the zone's file) and works the times out
// from there; the offsets are asked again as the dashboard opens and every
// quarter of an hour while it is open, so a change to or from summer time
// shows within fifteen minutes. Places are IANA zone names ("Europe/London"),
// kept in settings.json as one comma-string (desktop.worldClocks), because
// the settings file cannot hold a list (SettingsService.sanitizedNode).

// Two or three places is what the card is for; four still fit a cell.
var LIMIT = 4

// The system's zone files. TZDIR is what glibc reads instead, when set.
var ZONE_DIR = "/usr/share/zoneinfo"

// A zone name as the tz database writes them: one to three parts of letters,
// digits, "_", "+" and "-", the first starting with a letter. Nothing that
// could climb out of the zone directory ("..", a leading "/"), so a name read
// back from the settings is safe to put on a path.
function validZone(zone) {
    return typeof zone === "string" && /^[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+){0,2}$/.test(zone)
}

// The setting's comma-string -> the places, each once, at most LIMIT.
function parseZones(setting) {
    const zones = []
    for (const part of String(setting || "").split(",")) {
        const zone = part.trim()
        if (validZone(zone) && zones.indexOf(zone) < 0 && zones.length < LIMIT) zones.push(zone)
    }
    return zones
}

function storeZones(zones) {
    return parseZones((zones || []).join(",")).join(",")
}

// The places after adding `zone` at the end; null when it is no zone, is
// there already or the card is full.
function withZone(zones, zone) {
    const list = parseZones((zones || []).join(","))
    if (!validZone(zone) || list.indexOf(zone) >= 0 || list.length >= LIMIT) return null
    return list.concat([zone])
}

function withoutZone(zones, zone) {
    return (zones || []).filter(item => item !== zone)
}

// "America/Argentina/Buenos_Aires" -> "Buenos Aires": the last part is the
// place a zone is named after.
function cityOf(zone) {
    const parts = String(zone || "").split("/")
    return parts[parts.length - 1].replace(/_/g, " ")
}

// `date +%z` -> minutes east of UTC: "+0530" is 330, "-0300" is -180; NaN for
// anything else.
function parseOffset(text) {
    const match = /^([+-])(\d{2})(\d{2})$/.exec(String(text || "").trim())
    if (!match) return NaN
    const minutes = Number(match[2]) * 60 + Number(match[3])
    return match[1] === "-" ? -minutes : minutes
}

// Asks for every place's offset in one run: "zone<TAB>+hhmm" per line, and
// "zone<TAB>?" for a name that has no zone file here (a zone the database
// dropped since it was chosen). The names go in as arguments, never into the
// script's text.
function offsetsCommand(zones, zoneDir) {
    return ["sh", "-c",
        "dir=$1; shift; for z do if [ -f \"$dir/$z\" ]; then printf '%s\\t%s\\n' \"$z\" \"$(TZ=\":$dir/$z\" date +%z)\"; "
        + "else printf '%s\\t?\\n' \"$z\"; fi; done",
        "sh", zoneDir || ZONE_DIR].concat((zones || []).filter(validZone))
}

// The run's output -> { zone: minutes }, an unknown zone as null.
function parseOffsets(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        const tab = line.indexOf("\t")
        if (tab < 0) continue
        const zone = line.slice(0, tab)
        if (!validZone(zone)) continue
        const minutes = parseOffset(line.slice(tab + 1))
        result[zone] = isNaN(minutes) ? null : minutes
    }
    return result
}

// The wall clock at a place `offset` minutes east of UTC, and how many days
// that is from the local date (-1, 0 or 1). `localOffset` is the machine's
// own offset in the same unit (-Date.getTimezoneOffset()). `date` reads that
// time the way TimeFormat reads a Date (getHours, getMinutes): a real Date
// made from those fields would be a local one, and on the night the clocks
// here go forward an hour that does not exist here - 02:30 in London while
// Berlin skips from 02:00 to 03:00 - came out an hour off.
function wallClock(nowMs, offset, localOffset) {
    const there = new Date(nowMs + offset * 60000)
    const here = new Date(nowMs + localOffset * 60000)
    const thereDay = Date.UTC(there.getUTCFullYear(), there.getUTCMonth(), there.getUTCDate())
    const hereDay = Date.UTC(here.getUTCFullYear(), here.getUTCMonth(), here.getUTCDate())
    const hours = there.getUTCHours()
    const minutes = there.getUTCMinutes()
    return {
        date: { getHours: () => hours, getMinutes: () => minutes },
        dayShift: Math.round((thereDay - hereDay) / 86400000)
    }
}

// How far a place is from here: "+5:30 h", "−6 h", "Same time". The minus is
// the typographic one, as the media popup's remaining time has it.
function difference(offset, localOffset) {
    const delta = offset - localOffset
    if (!isFinite(delta)) return ""
    if (delta === 0) return "Same time"
    const sign = delta > 0 ? "+" : "−"
    const hours = Math.floor(Math.abs(delta) / 60)
    const minutes = Math.abs(delta) % 60
    return sign + hours + (minutes ? ":" + String(minutes).padStart(2, "0") : "") + " h"
}

function dayNote(dayShift) {
    return dayShift > 0 ? "Tomorrow" : dayShift < 0 ? "Yesterday" : ""
}

// Whether the offsets are due again: on the quarter hours, which is when
// summer time starts or ends anywhere (Chatham's at a quarter to).
function offsetsDue(date) {
    return date instanceof Date && date.getMinutes() % 15 === 0
}

// ---- choosing a place ------------------------------------------------------
// The tz database's own list of places (zone.tab: country code, coordinates,
// zone, comment per line) and its country names (iso3166.tab: code, name),
// read while the card is being edited and searched by city, country, zone or
// comment.

function parseZoneTab(text) {
    const zones = []
    for (const line of String(text || "").split("\n")) {
        if (!line.length || line[0] === "#") continue
        const fields = line.split("\t")
        if (fields.length < 3 || !validZone(fields[2])) continue
        zones.push({ zone: fields[2], country: fields[0].split(",")[0], comment: fields[3] || "" })
    }
    return zones
}

function parseCountries(text) {
    const names = {}
    for (const line of String(text || "").split("\n")) {
        if (!line.length || line[0] === "#") continue
        const fields = line.split("\t")
        if (fields.length >= 2 && /^[A-Z]{2}$/.test(fields[0])) names[fields[0]] = fields[1].trim()
    }
    return names
}

// The places that match `query`, best first: a city that starts with it,
// then one that holds it, then a match on the country, the zone or the
// comment. The ones on the card already are left out. UTC is always a
// place. { zone, label, detail } each.
function search(table, countries, query, taken, limit) {
    const text = String(query || "").trim().toLowerCase()
    if (!text.length) return []
    const have = taken || []
    const names = countries || {}
    const rows = (table || []).concat([{ zone: "UTC", country: "", comment: "Coordinated Universal Time" }])
    const scored = []
    for (const row of rows) {
        if (have.indexOf(row.zone) >= 0) continue
        const city = cityOf(row.zone).toLowerCase()
        const country = String(names[row.country] || "").toLowerCase()
        const rank = city.indexOf(text) === 0 ? 0 : city.indexOf(text) > 0 ? 1
            : country.indexOf(text) === 0 ? 2
            : (country + " " + row.zone.toLowerCase() + " " + row.comment.toLowerCase()).indexOf(text) >= 0 ? 3 : -1
        if (rank < 0) continue
        scored.push({ rank: rank, row: row, city: cityOf(row.zone) })
    }
    scored.sort((a, b) => a.rank - b.rank || a.city.localeCompare(b.city))
    return scored.slice(0, Math.max(0, limit || 6)).map(item => ({
        zone: item.row.zone,
        label: item.city,
        detail: [names[item.row.country] || "", item.row.comment].filter(part => part.length).join(" · ")
    }))
}
