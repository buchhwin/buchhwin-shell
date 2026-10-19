.pragma library
.import "../launcher/LaunchLogic.js" as Launch

// Online meetings in calendar events: the link that joins one, and how it is
// opened. An Outlook invitation carries its Teams link in the event's text
// ("Join the meeting now<https://teams.microsoft.com/l/meetup-join/…>"), a
// Google one its Meet link, Zoom and Webex theirs; the Plasma plugin hands
// the shell the description (CalendarLogic.fromEventData), and a location or
// a title is looked at too where an event has one. The link is never logged:
// it is as private as the event (testing.md pitfall 17).

// The services, in no order of preference: the first link in the text that
// is one of them wins. Hosts and paths are the joining ones only - Outlook's
// text also links "Meeting options" and a help page on teams.microsoft.com,
// which join nothing.
var SERVICES = [
    { id: "teams", label: "Teams", host: /^(teams\.microsoft\.com|teams\.live\.com|teams\.cloud\.microsoft)$/i,
      path: /^\/(l\/meetup-join\/|meet\/)/i },
    { id: "meet", label: "Meet", host: /^meet\.google\.com$/i, path: /^\/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}(\/|$|\?)/i },
    { id: "zoom", label: "Zoom", host: /(^|\.)zoom(gov)?\.(us|com)$/i, path: /^\/(j|my|w|wc\/join)\//i },
    { id: "webex", label: "Webex", host: /(^|\.)webex\.com$/i, path: /^\/(meet\/|join\/|[^/]+\/j\.php|[^/]+\/meet\/|wbxmjs\/joinservice\/)/i }
]

// The minutes before its start from which a meeting offers Join in the
// notch's day page and next to the clock (the lists offer it until it ends).
var LEAD_MINUTES = 5

// Entities a rich-text description writes in its links ("&amp;" between the
// parameters of a Zoom link).
function decoded(text) {
    return String(text || "").replace(/&amp;/g, "&").replace(/&#38;/g, "&")
}

// Every https link in a text, in order, without the punctuation a sentence or
// Outlook's angle brackets put after it.
function links(text) {
    const found = decoded(text).match(/https:\/\/[^\s<>"'()\[\]{}|\\^`]+/gi) || []
    return found.map(url => url.replace(/[.,;:!?*]+$/, ""))
}

// { host, path } of an https link, or null.
function parts(url) {
    const match = /^https:\/\/([^\/?#:@]+)(?::\d+)?(\/[^?#]*)?/i.exec(String(url || ""))
    return match ? { host: match[1].toLowerCase(), path: match[2] || "/" } : null
}

// The service a link joins, or null.
function serviceOf(url) {
    const split = parts(url)
    if (!split) return null
    return SERVICES.find(service => service.host.test(split.host) && service.path.test(split.path)) || null
}

// The meeting an event joins: { url, service, label } ("Join Teams"), or null.
// The description first - that is where an invitation puts it - then the
// location, then the title.
function meeting(event) {
    if (!event) return null
    const text = [event.description, event.location, event.title]
        .filter(part => typeof part === "string" && part.length).join("\n")
    for (const url of links(text)) {
        const service = serviceOf(url)
        if (service) return { url: url, service: service.id, label: "Join " + service.label }
    }
    return null
}

function timeOf(value) {
    return value instanceof Date ? value.getTime() : NaN
}

// Whether an event's Join belongs in a list (the dashboard, the events popup,
// the event's details): it has a link and has not ended.
function listJoin(event, now) {
    if (!meeting(event)) return false
    const end = timeOf(event.end)
    return !(end <= timeOf(now))
}

// Whether it belongs in the notch's day page and next to the clock: a timed
// meeting from `lead` minutes (LEAD_MINUTES when left out) before its start
// until its end.
function soonJoin(event, now, lead) {
    if (!event || event.allDay || !meeting(event)) return false
    const at = timeOf(now)
    const minutes = typeof lead === "number" && lead >= 0 ? lead : LEAD_MINUTES
    const start = timeOf(event.start)
    const end = timeOf(event.end)
    return at >= start - minutes * 60000 && at < Math.max(end, start + 60000)
}

// The first event of a list that offers Join soon, or null.
function nextJoin(events, now, lead) {
    return (events || []).find(event => soonJoin(event, now, lead)) || null
}

// The Teams web app among the desktop entries (DesktopEntries.applications):
// an entry named Teams that runs a browser with an --app-id - the PWA Brave
// or Chrome installed ("Microsoft Teams (PWA)" here). null without one.
function teamsApp(entries) {
    for (const entry of entries || []) {
        if (!entry || !/\bteams\b/i.test(String(entry.name || ""))) continue
        const command = entry.command ? Array.prototype.slice.call(entry.command) : []
        if (!command.length || !Launch.browserLauncher(command[0]).length) continue
        if (command.some(arg => /^--app-id=\S+$/.test(String(arg)))) return entry
    }
    return null
}

// What opens a meeting: a Teams link in the Teams web app, through the
// browser's session launcher (LaunchLogic: the wallet first), with the link
// as the app's start page - the flag Chromium's own desktop actions use for a
// web app's shortcut menu; anything else, or Teams without the web app,
// through the session's xdg-open, which hands a web link to the default
// browser's launcher. `script` is Paths.script. null without a meeting.
function joinCommand(found, app, script) {
    if (!found || !found.url) return null
    if (found.service === "teams" && app) {
        const context = Launch.launchContext(app, {}, script)
        if (context && context.command.length && context.command[0] !== script("launch-app.sh"))
            return context.command.filter(arg => !/^%[fFuU]$/.test(String(arg)))
                .concat(["--app-launch-url-for-shortcuts-menu-item=" + found.url])
    }
    return ["xdg-open", found.url]
}
