.pragma library

// The notification history kept across a shell restart (Settings >
// Notifications "Keep notifications across restarts", off by default: the
// words of every notification on disk). Quickshell's keepOnReload carries
// the history over a reload, not a restart - and this shell restarts with
// every deploy, with Super+Ctrl+R and after a crash. What is kept is what
// the centre shows, never what could act: app, title, text, when, the
// site's origin; no actions, no pictures. A start shows them under
// "Earlier". Unit tested (NotificationSavedTest).

var VERSION = 1
// The newest this many, the earlier ones among them.
var LIMIT = 50
// A notification's text is capped on its way to the disk: a log pasted into
// a body is not something to keep a copy of.
var SUMMARY_MAX = 300
var BODY_MAX = 2000

function text(value, max) {
    const string = String(value === undefined || value === null ? "" : value)
    return string.length > max ? string.slice(0, max) : string
}

// An app icon worth keeping: a theme name or a local path. Image data the
// sender sent (image://qsimage/...) dies with the shell, and a web url the
// shell never fetches.
function keptIcon(icon) {
    const name = String(icon || "")
    return name.length && !/^(image|https?):/i.test(name) ? name : ""
}

// One notification as the file keeps it. `at` is when it came (ms, 0 when
// not known), `origin` the host its site hint named. Unit tested.
function record(notification, at, origin) {
    const it = notification || {}
    const kept = {
        id: Number(it.id) || 0,
        appName: text(it.appName, 120),
        appIcon: keptIcon(it.appIcon),
        desktopEntry: text(it.desktopEntry, 120),
        summary: text(it.summary, SUMMARY_MAX),
        body: text(it.body, BODY_MAX),
        urgency: Math.max(0, Math.min(2, Math.round(Number(it.urgency) || 0))),
        time: Number(at) > 0 ? Math.round(Number(at)) : 0
    }
    if (origin && String(origin).length) kept.origin = text(origin, 253)
    return kept
}

// What the centre's "Earlier" works with: a kept record as a notification
// looks to NotificationLogic (appKey, group, search) and to a card, with an
// id of its own that no live notification has (a string) and that stays the
// same while others come and go, so the centre's keyed list keeps its cards.
// Unit tested.
function earlierItem(kept, id) {
    const it = kept || {}
    const hints = {}
    if (it.origin) hints["x-kde-origin-name"] = String(it.origin)
    return {
        id: id,
        earlier: true,
        appName: String(it.appName || ""),
        appIcon: String(it.appIcon || ""),
        desktopEntry: String(it.desktopEntry || ""),
        summary: String(it.summary || ""),
        body: String(it.body || ""),
        urgency: Number(it.urgency) || 0,
        time: Number(it.time) || 0,
        image: "",
        actions: [],
        hints: hints,
        source: it
    }
}

// Every record as an item, oldest first, each id once ("earlier-<time>-<id>",
// a count after it for a second one with both the same). Unit tested.
function earlierItems(records) {
    const seen = {}
    return (records || []).map(kept => {
        const base = "earlier-" + (Number(kept.time) || 0) + "-" + (Number(kept.id) || 0)
        const count = seen[base] || 0
        seen[base] = count + 1
        return earlierItem(kept, count ? base + "-" + count : base)
    })
}

function valid(kept) {
    return kept && typeof kept === "object" && typeof kept.summary === "string" && typeof kept.appName === "string"
        && (kept.summary.length > 0 || String(kept.body || "").length > 0)
}

// The records of a file's text, oldest first, at most LIMIT; [] for
// anything unreadable. Unit tested.
function parse(content) {
    try {
        const parsed = JSON.parse(String(content || ""))
        const items = parsed && Array.isArray(parsed.items) ? parsed.items : []
        return items.filter(valid).map(item => record(item, item.time, item.origin)).slice(-LIMIT)
    } catch (error) {
        return []
    }
}

function serialize(records) {
    return JSON.stringify({ version: VERSION, items: (records || []).slice(-LIMIT) }) + "\n"
}

// What the file holds now: the earlier ones still there, then the live
// history (oldest first), the newest LIMIT of all. Unit tested.
function merge(earlier, live) {
    return (earlier || []).concat(live || []).slice(-LIMIT)
}

// What a start makes of the file. A record whose id and title a live
// notification has is that notification, carried over a reload by the
// server: it gets its arrival back (`times`, id -> ms) instead of a second
// card. Every other one is earlier. Unit tested.
function split(saved, live) {
    const current = {}
    for (const notification of live || []) if (notification) current[notification.id] = String(notification.summary || "")
    const earlier = []
    const times = {}
    for (const kept of saved || []) {
        if (current[kept.id] !== undefined && current[kept.id] === kept.summary) {
            if (kept.time > 0) times[kept.id] = kept.time
        } else {
            earlier.push(kept)
        }
    }
    return { earlier: earlier, times: times }
}

// The earlier records without the one a card dismissed (its `source`).
function without(earlier, kept) {
    return (earlier || []).filter(item => item !== kept)
}
