.pragma library

// Calendars from a link (Settings > Calendar "Add calendar from a link"): a
// published calendar - Outlook's "Publish a calendar" ICS link, a Google
// calendar's secret address, any .ics on the web - read through an Akonadi
// iCal resource on that URL, read-only and fetched again every 15 minutes
// (scripts/calendar-link.py, which talks to Akonadi over D-Bus). The shell
// then shows its events like any other KDE calendar.
//
// A published link is readable by anyone who has it, so it is treated like a
// password: it goes to the helper on stdin, never as an argument, never into
// the log, the IPC or the settings, and once added the shell only ever shows
// its host. Akonadi keeps it in the resource's own configuration
// (~/.config/akonadi_ical_resource_N_rc), which is where KDE keeps every
// calendar's address.

var REFRESH_MINUTES = 15
var MAX_LENGTH = 4096

// The link as the helper takes it: { ok, url, error }. webcal:// and
// webcals:// are https:// (Outlook and Google offer both, and KDE's file
// layer speaks only the second); plain http:// is refused - anyone on the
// way could read, or change, the calendar.
function normalize(text) {
    const value = String(text === undefined || text === null ? "" : text).trim()
    if (!value.length) return { ok: false, url: "", error: "Paste the calendar's link first." }
    if (value.length > MAX_LENGTH) return { ok: false, url: "", error: "That link is too long to be a calendar's." }
    if (/\s/.test(value)) return { ok: false, url: "", error: "A link has no spaces in it." }
    let url = value
    if (/^webcals?:\/\//i.test(url)) url = url.replace(/^webcals?:\/\//i, "https://")
    if (/^http:\/\//i.test(url))
        return { ok: false, url: "", error: "Only https links are taken: a plain http calendar can be read on the way." }
    if (!/^https:\/\//i.test(url)) return { ok: false, url: "", error: "A calendar link starts with https:// or webcal://." }
    const host = hostOf(url)
    if (!host.length) return { ok: false, url: "", error: "That link names no server." }
    // A user name or password in the link would be kept as written.
    if (/^https:\/\/[^\/?#]*@/i.test(url)) return { ok: false, url: "", error: "Leave the user name and password out of the link." }
    return { ok: true, url: "https://" + url.slice("https://".length), error: "" }
}

// The server of an https link, lower case; "" for anything else.
function hostOf(url) {
    const match = /^https:\/\/(?:[^\/?#@]*@)?([^\/?#:]+)/i.exec(String(url || ""))
    return match ? match[1].toLowerCase() : ""
}

// A name for the calendar when the user gave none: what the link is from.
function defaultName(url) {
    const host = hostOf(url)
    if (/(^|\.)(outlook\.office365\.com|outlook\.office\.com|outlook\.live\.com)$/.test(host)) return "Outlook"
    if (/(^|\.)calendar\.google\.com$/.test(host)) return "Google"
    if (/(^|\.)icloud\.com$/.test(host)) return "iCloud"
    return host.length ? host : "Calendar"
}

// The name as the helper takes it: one line, at most 80 characters, or the
// default for the link.
function nameFor(given, url) {
    const text = String(given === undefined || given === null ? "" : given).replace(/[\x00-\x1f\x7f]+/g, " ").trim()
    return text.length ? text.slice(0, 80) : defaultName(url)
}

// What goes to `calendar-link.py add` on stdin; null when the link is not
// one (`normalize` says why).
function addRequest(text, name) {
    const link = normalize(text)
    if (!link.ok) return null
    return JSON.stringify({ url: link.url, name: nameFor(name, link.url), refreshMinutes: REFRESH_MINUTES })
}

// Akonadi's instance ids for this resource type: the only ids the shell ever
// hands back to the helper.
function validId(id) {
    return typeof id === "string" && /^akonadi_ical_resource_\d+$/.test(id)
}

// Akonadi's agent status numbers (AgentManager.agentInstanceStatus).
var STATUS = { 0: "idle", 1: "running", 2: "broken", 3: "notConfigured" }

function statusText(row) {
    if (!row.online) return "Offline"
    if (row.status === "running") return "Updating …"
    if (row.status === "broken") return row.message.length ? row.message : "Could not be read"
    if (row.status === "notConfigured") return "Not set up"
    return "Read-only · updated every " + REFRESH_MINUTES + " minutes"
}

// One row of `calendar-link.py list`, with nothing but what the page shows.
function cleanRow(row) {
    if (!row || typeof row !== "object" || !validId(row.id)) return null
    const status = typeof row.status === "number" && Object.prototype.hasOwnProperty.call(STATUS, row.status)
        ? STATUS[row.status] : "idle"
    const clean = {
        id: row.id,
        name: typeof row.name === "string" && row.name.trim().length ? row.name.trim() : "Calendar",
        host: typeof row.host === "string" ? row.host : "",
        status: status,
        online: row.online !== false,
        message: typeof row.message === "string" ? row.message.trim() : ""
    }
    clean.subtitle = (clean.host.length ? clean.host + " · " : "") + statusText(clean)
    return clean
}

// The helper's answer: { ok, reason, message, calendars, id }. `reason` is
// the helper's word for a refusal (notRunning, missingDbus, …); `message`
// what the page says.
function parseAnswer(code, text) {
    let data = null
    try { data = JSON.parse(String(text || "").trim()) } catch (error) { data = null }
    if (!data || typeof data !== "object") {
        return { ok: false, reason: "noAnswer", message: code === 127 ? "python3 is missing." : "The calendar helper gave no answer.",
                 calendars: [], id: "" }
    }
    const rows = Array.isArray(data.calendars) ? data.calendars.map(cleanRow).filter(row => row !== null) : []
    const ok = data.ok === true && code === 0
    const reason = typeof data.reason === "string" ? data.reason : ""
    return {
        ok: ok,
        reason: reason,
        message: ok ? "" : typeof data.error === "string" && data.error.length ? data.error : reasonText(reason),
        calendars: rows,
        id: validId(data.id) ? data.id : ""
    }
}

function reasonText(reason) {
    switch (reason) {
    case "notRunning": return "KDE PIM (Akonadi) is not running. Open the dashboard or Merkuro once, then try again."
    case "missingDbus": return "The D-Bus module for Python is missing (python-dbus)."
    case "notLink": return "That calendar is not one from a link."
    case "sandbox": return "Only in the buchhwin-shell session."
    case "timeout": return "Akonadi did not answer in time."
    }
    return "That did not work."
}
