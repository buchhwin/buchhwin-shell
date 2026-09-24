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
function notchContent(notification, iconPath) {
    const it = notification || {}
    const picture = it.image || (it.appIcon ? String(iconPath(it.appIcon) || "") : "")
    return {
        kind: "notification",
        icon: picture ? "" : "󰂚",
        iconSource: picture,
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

// Popups that are still in the server's list. Dismissed notifications leave
// the history and must leave the queue with it. Unit tested.
function livePopups(popups, live) {
    const values = live || []
    return (popups || []).filter(item => values.indexOf(item) >= 0)
}
