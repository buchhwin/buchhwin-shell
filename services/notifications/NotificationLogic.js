.pragma library

// The key a per-app rule is stored under, and the one `group` uses. Unit tested.
function appKey(notification) {
    const name = String((notification && notification.appName) || "").trim()
    return name.length ? name.toLowerCase() : "__system"
}

// What the notch shows for the newest popup: the same picture the card uses,
// by the same route - the image the notification brought, else its app icon
// (resolved by `iconPath`, which is Quickshell's lookup), else a bell. Takes
// the notification itself, so the caller reads its fields at one moment
// rather than through a binding that may not have caught up. Unit tested.
// The picture a notification shows: its own image, else its app icon. An
// image given as an http(s) url is skipped for the icon: Qt's HTTP/2 client
// is where the shell's crashes and the "HEADERS on invalid stream" noise
// came from (pitfall 28), and a notification has no business making the
// shell fetch from the network. Unit tested.
function picture(notification, iconPath) {
    const it = notification || {}
    const image = String(it.image || "")
    if (image && !/^https?:\/\//i.test(image)) return image
    return it.appIcon ? String(iconPath(it.appIcon) || "") : ""
}

function notchContent(notification, iconPath) {
    const it = notification || {}
    const shown = picture(it, iconPath)
    return {
        kind: "notification",
        icon: shown ? "" : "󰂚",
        iconSource: shown,
        title: it.summary || it.appName || "Notification",
        subtitle: it.body || ""
    }
}

// Whether a notification matches a query: app name, summary or body. Unit
// tested.
function matches(notification, query) {
    const text = String(query || "").trim().toLowerCase()
    if (!text) return true
    const haystack = [(notification && notification.appName) || "",
                      (notification && notification.summary) || "",
                      (notification && notification.body) || ""].join(" ").toLowerCase()
    return haystack.indexOf(text) >= 0
}

// The history filtered by a query, in arrival order. Unit tested.
function search(history, query) {
    return (history || []).filter(notification => matches(notification, query))
}

// The rule for one app: "default", "mute" (never pops up, still lands in the
// history) or "critical" (always pops up, even while Do Not Disturb runs).
// Unit tested.
function ruleFor(rules, notification) {
    const rule = (rules || {})[appKey(notification)]
    return rule === "mute" || rule === "critical" ? rule : "default"
}

// Groups notifications by app for the notification center. Input is the
// history in arrival order; groups come newest first, each with its
// notifications newest first. Unit tested.
function group(history) {
    const groups = []
    const byKey = {}
    const list = (history || []).slice().reverse()
    for (const notification of list) {
        if (!notification) continue
        const name = String(notification.appName || "").trim()
        const key = appKey(notification)
        if (!byKey[key]) {
            byKey[key] = { key: key, name: name.length ? name : "System", icon: String(notification.appIcon || ""), items: [] }
            groups.push(byKey[key])
        }
        byKey[key].items.push(notification)
        if (!byKey[key].icon.length && notification.appIcon) byKey[key].icon = String(notification.appIcon)
    }
    return groups
}

// Notifications shown for a group: all when expanded, otherwise the newest
// two (a group of three shows all three instead of "1 more").
function visibleItems(groupEntry, expanded) {
    const items = groupEntry.items
    return expanded || items.length <= 3 ? items : items.slice(0, 2)
}

// Whether a notification becomes a popup. `state` carries the suppression
// flags; `critical` marks an urgent notification. Critical notifications still
// pop up while Do Not Disturb runs on a timer, but manual DND silences
// everything. Unit tested.
function shouldPopup(state, critical, rule) {
    // A per-app rule decides before anything else: "mute" never pops up, and
    // "critical" makes the app's notifications as urgent as the sender can.
    if (rule === "mute") return false
    const urgent = !!critical || rule === "critical"
    if (!state) return true
    if (!state.suppressed) return true
    return urgent && state.dndMode !== "manual"
}

// The popup queue after a new notification arrived: newest last, at most
// `maxPopups` entries. Unit tested.
function withPopup(popups, notification, maxPopups) {
    const next = (popups || []).concat([notification])
    const limit = Math.max(1, maxPopups || 1)
    return next.slice(Math.max(0, next.length - limit))
}

// The notifications to let go once the history holds more than `limit`: the
// ones older than the newest `limit`, but never one in `keep` (the popups on
// screen). A popup that is still up keeps its place and the history stays
// that much over until a later arrival finds it gone; nothing of the newest
// `limit` is taken in its stead. `history` is in arrival order, as the server
// keeps it. Unit tested.
function overflow(history, limit, keep) {
    const list = history || []
    const over = list.length - Math.max(0, limit)
    if (over <= 0) return []
    const kept = keep || []
    return list.slice(0, over).filter(notification => kept.indexOf(notification) < 0)
}

// Popups that are still in the server's list. Dismissed notifications leave
// the history and must leave the queue with it. Unit tested.
function livePopups(popups, live) {
    const values = live || []
    return (popups || []).filter(item => values.indexOf(item) >= 0)
}

// Whether two queues hold the same notifications in the same order. By
// identity, which is how `livePopups` and `hidePopup` find a notification too:
// the server hands out one object per notification and keeps it for its whole
// life. A queue that has not changed is not assigned again, so nothing that
// hangs off it has to be worked out again. Unit tested.
function sameSequence(a, b) {
    const left = a || []
    const right = b || []
    if (left.length !== right.length) return false
    for (let index = 0; index < left.length; ++index)
        if (left[index] !== right[index]) return false
    return true
}

// Do Not Disturb at `now` (ms since the epoch): "manual" until it is switched
// off, "1h" and "tomorrow" until `until`. Unit tested.
var TIMED_DND = ["1h", "tomorrow"]

function dndActive(mode, until, now) {
    if (mode === "manual") return true
    return TIMED_DND.indexOf(mode) >= 0 && Number(until) > Number(now)
}

// The mode to keep at `now`: a timed one that has run out is "off". The
// service asks at its expiry *and* once a minute while a timed mode is on,
// because the expiry is a Qt timer on the monotonic clock, which stands still
// in suspend: "until 07:00" slept through from 23:00 to 07:30 fired at about
// 15:30, and the indicator, the tile and the clock showed Do Not Disturb all
// morning. Unit tested.
function dndAfter(mode, until, now) {
    return TIMED_DND.indexOf(mode) >= 0 && !dndActive(mode, until, now) ? "off" : mode
}

// Whose Do Not Disturb `mode` is, from what a mode switch (or state.json)
// says: a mode's plain name while it is on, else "" - the user's. Unit tested.
function dndOwner(mode, by) {
    return mode !== "off" && typeof by === "string" && /^[a-z]{1,32}$/.test(by) ? by : ""
}

// "gaming" -> "Gaming", the templates' own labels.
function dndOwnerTitle(by) {
    const name = String(by || "")
    return name.length ? name.charAt(0).toUpperCase() + name.slice(1) : ""
}
