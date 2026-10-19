.pragma library
.import "../appearance/TimeFormat.js" as TimeFormat

// The key a per-app rule is stored under, and the one `group` uses. Unit tested.
function appKey(notification) {
    const name = String((notification && notification.appName) || "").trim()
    return name.length ? name.toLowerCase() : "__system"
}

// An app icon as Qt can load it. The specification lets a sender name it as
// a file:// URI or as a theme icon, and senders pass absolute paths too:
// Quickshell's `iconPath` (the caller's lookup) answers nothing for a URI,
// so a file:// icon showed the bell on the card and no icon at all over its
// group, where only the absolute path had been handled. A URI is taken as it
// came, a path becomes one, and anything else is a name for the theme -
// except an http(s) url, which the shell never fetches (pitfall 28). The
// card, the notch and the centre's group headers all come through here.
// Unit tested.
function iconSource(icon, iconPath) {
    const name = String(icon || "")
    if (!name.length || /^https?:\/\//i.test(name)) return ""
    if (/^file:\/\//i.test(name)) return name
    // Encoded, as WallpaperLogic.folderUrl does: a "#" or "?" in a path
    // would end the file name in a url.
    if (name.charAt(0) === "/") return "file://" + name.split("/").map(encodeURIComponent).join("/")
    return String(iconPath(name) || "")
}

// The picture a notification shows: its own image, else its app icon. An
// image given as an http(s) url is skipped for the icon: Qt's HTTP/2 client
// is where the shell's crashes and the "HEADERS on invalid stream" noise
// came from (pitfall 28), and a notification has no business making the
// shell fetch from the network. Unit tested.
function picture(notification, iconPath) {
    const it = notification || {}
    const image = String(it.image || "")
    if (image && !/^https?:\/\//i.test(image)) return image
    return iconSource(it.appIcon, iconPath)
}

// What the notch shows for its popup: the same picture the card uses, by the
// same route - the image the notification brought, else its app icon
// (resolved by `iconPath`, which is Quickshell's lookup), else a bell, or the
// card's warning sign for a critical one. Takes the notification itself, so
// the caller reads its fields at one moment rather than through a binding
// that may not have caught up. `critical` comes from the caller, which knows
// the urgency enum; the notch draws such a one in the warning ink. Unit
// tested.
function notchContent(notification, iconPath, critical) {
    const it = notification || {}
    const shown = picture(it, iconPath)
    const urgent = critical === true
    return {
        kind: "notification",
        icon: shown ? "" : urgent ? "\u{f0026}" : "󰂚", // Icons.warning
        iconSource: shown,
        title: it.summary || it.appName || "Notification",
        subtitle: it.body || "",
        critical: urgent
    }
}

// The popup the notch shows: the newest, which `withPopup` puts last. It read
// the first entry - the oldest - so a second notification waited behind the
// first and had what was left of its own time once that one had gone, and
// behind a critical one (no timer) every later one ran out unseen. Unit
// tested.
function notchPick(popups) {
    const list = popups || []
    return list.length ? list[list.length - 1] : null
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

// The rule the bell over an app's group goes to on a click: Normal and Muted,
// back and forth. It went on from Muted to "Always urgent", so un-muting an
// app made it break through Do Not Disturb, and a third click was needed to
// get back to normal. An always-urgent app goes back to normal; "Always
// urgent" itself is chosen in Settings > Notifications. Unit tested.
function nextAppRule(rule) {
    return rule === "default" || rule === undefined || rule === null || rule === "" ? "mute" : "default"
}

// Every app Settings > Notifications lists for its rule: the ones with a rule
// stored - also when nothing of theirs is in the history, where the centre's
// bell was the only way to see or undo it - and the ones in the history.
// Sorted by name; `name` is the app's own spelling when the history has it,
// else the key with a capital. Unit tested.
function ruleRows(rules, history) {
    const stored = rules || {}
    const names = {}
    for (const notification of history || []) {
        if (!notification) continue
        const key = appKey(notification)
        if (names[key] === undefined) {
            const name = String(notification.appName || "").trim()
            names[key] = name.length ? name : "System"
        }
    }
    for (const key in stored) {
        if (names[key] !== undefined || (stored[key] !== "mute" && stored[key] !== "critical")) continue
        names[key] = key === "__system" ? "System" : key.charAt(0).toUpperCase() + key.slice(1)
    }
    return Object.keys(names)
        .map(key => ({ key: key, name: names[key],
                       rule: stored[key] === "mute" || stored[key] === "critical" ? stored[key] : "default" }))
        .sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1
                        : a.key < b.key ? -1 : a.key > b.key ? 1 : 0)
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

// The groups by key, for a list keyed by the keys themselves: the centre's
// list hands its Repeater the key strings, which a ScriptModel compares by
// value and so keeps every group that is still there (pitfall 76), and each
// group looks its entry up here. On the groups themselves - new objects on
// every change - every group and card was built again for each notification
// that came or went; Clear all of a hundred blocked for over three seconds.
// Unit tested.
function groupIndex(groups) {
    const index = {}
    for (const entry of groups || []) if (entry && entry.key !== undefined) index[entry.key] = entry
    return index
}

// Notifications shown for a group: all when expanded, otherwise the newest
// two (a group of three shows all three instead of "1 more").
function visibleItems(groupEntry, expanded) {
    const items = (groupEntry && groupEntry.items) || []
    return expanded || items.length <= 3 ? items : items.slice(0, 2)
}

// Whether a notification becomes a popup. `state` carries the suppression
// flags and whose Do Not Disturb it is (`dndBy`); `critical` marks an urgent
// notification. Critical notifications still pop up while Do Not Disturb
// runs on a timer, or while it is on because something turned it on for
// itself (it has an owner: a mode) - gaming's own silenced "Battery very
// low" and "Timer done", which the user never asked for. Only the user's own
// manual one silences everything. Unit tested.
function shouldPopup(state, critical, rule) {
    // A per-app rule decides before anything else: "mute" never pops up, and
    // "critical" makes the app's notifications as urgent as the sender can.
    if (rule === "mute") return false
    const urgent = !!critical || rule === "critical"
    if (!state) return true
    if (!state.suppressed) return true
    return urgent && (state.dndMode !== "manual" || !!state.dndBy)
}

// The popup queue after a new notification arrived: newest last, at most
// `maxPopups` entries. Unit tested.
function withPopup(popups, notification, maxPopups) {
    const next = (popups || []).concat([notification])
    const limit = Math.max(1, maxPopups || 1)
    return next.slice(Math.max(0, next.length - limit))
}

// The queue after a sender replaced a notification in place (replaces_id;
// Quickshell updates the object it has and announces nothing new): one still
// on screen stays where it is - its card shows the new words by itself - and
// one whose popup has gone comes back as the newest when `show` says it may
// pop up at all. The same queue when nothing changes, so it is not assigned
// again. Unit tested.
function requeue(popups, notification, show, maxPopups) {
    const list = popups || []
    if (!notification || list.indexOf(notification) >= 0 || !show) return list
    return withPopup(list, notification, maxPopups)
}

// Whether a notification holds its picture itself: image data the sender
// sent along, which Quickshell keeps for as long as the notification is
// tracked and serves as image://qsimage/... An image path or an app icon is
// a file somewhere else and costs nothing while no card shows it. Unit tested.
function carriesPixels(notification) {
    return /^image:\/\/qsimage\//.test(String((notification && notification.image) || ""))
}

// The notifications to let go once the history holds more than `limit`: the
// ones older than the newest `limit`, but never one in `keep` (the popups on
// screen). A popup that is still up keeps its place and the history stays
// that much over until a later arrival finds it gone; nothing of the newest
// `limit` is taken in its stead. `history` is in arrival order, as the server
// keeps it.
//
// `imageLimit`, when given, is a second cap for the ones that carry their
// pixels (`carriesPixels`): the cap by count let a hundred of them stay,
// and a hundred 256 px pictures held 27 MB that the heap kept after they
// had gone. Beyond the newest `imageLimit` of them the older ones go too,
// popups again excepted. Unit tested.
function overflow(history, limit, keep, imageLimit) {
    const list = history || []
    const kept = keep || []
    const over = Math.max(0, list.length - Math.max(0, limit))
    const pictures = imageLimit === undefined || imageLimit === null ? -1 : Math.max(0, imageLimit)
    let seen = 0
    const heavy = []
    if (pictures >= 0) {
        for (let index = list.length - 1; index >= 0; --index) {
            if (!carriesPixels(list[index])) continue
            seen += 1
            if (seen > pictures) heavy.push(list[index])
        }
    }
    if (over <= 0 && !heavy.length) return []
    return list.filter((notification, index) => (index < over || heavy.indexOf(notification) >= 0)
                                                && kept.indexOf(notification) < 0)
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

// How many notifications are unread: the ones still in the history that
// `unseen` (id -> true) names. Counted from the history rather than per
// arrival, so one closed by its ×, by its action or by its sender leaves the
// count with it - the bell said 1 over an empty history until the centre was
// opened. Unit tested.
function unreadCount(history, unseen) {
    const marks = unseen || {}
    let count = 0
    for (const notification of history || [])
        if (notification && marks[notification.id] === true) count += 1
    return count
}

// `table` (id -> anything) cut down to the notifications still in the
// history, so a table kept per notification does not grow with every one the
// session ever saw. The same table when nothing goes. Unit tested.
function forHistory(table, history) {
    const source = table || {}
    const next = {}
    let dropped = false
    const live = {}
    for (const notification of history || []) if (notification) live[notification.id] = true
    for (const key in source) {
        if (live[key] === true) next[key] = source[key]
        else dropped = true
    }
    return dropped ? next : source
}

// When a notification came, as a card in the centre says it: "now", "5 min",
// the time today ("14:05" or "2:05 PM"), "Yesterday", else "3 days". `at` and
// `now` are ms since the epoch; nothing for an unknown `at` (one carried
// over a shell restart, which keeps the notification but not when it came).
// Unit tested.
function ageLabel(at, now, twelve) {
    const then = Number(at)
    const current = Number(now)
    if (!(then > 0) || !(current > 0)) return ""
    const minutes = Math.floor(Math.max(0, current - then) / 60000)
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + " min"
    const arrived = new Date(then)
    const today = new Date(current)
    const days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
                             - new Date(arrived.getFullYear(), arrived.getMonth(), arrived.getDate()).getTime()) / 86400000)
    if (days <= 0) return TimeFormat.time(arrived, twelve === true, ":")
    if (days === 1) return "Yesterday"
    return days + " days"
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

// Where "until tomorrow morning" ends, set at `now`: the next time the clock
// reads `hour` o'clock - this morning while it is still before that hour,
// else tomorrow's. It always took the day after, so set at 00:30 it ran to
// the morning after next: 29.5 hours of Do Not Disturb for a night. `hour`
// is the setting (6 when it is missing). Unit tested.
function tomorrowEnd(now, hour) {
    const current = new Date(Number(now))
    const wanted = Number(hour)
    const at = Number.isFinite(wanted) ? Math.max(0, Math.min(23, Math.floor(wanted))) : 6
    const today = new Date(current.getFullYear(), current.getMonth(), current.getDate(), at, 0, 0)
    if (today.getTime() > current.getTime()) return today.getTime()
    return new Date(current.getFullYear(), current.getMonth(), current.getDate() + 1, at, 0, 0).getTime()
}

// What Do Not Disturb says it does, for the tiles, the bell and Settings:
// "Off", "Until you leave Gaming", "Until turned off", or "Until 06:00" with
// " (tomorrow)" when "until tomorrow" ends on another day than `now`'s. The
// time as the clock shows it (`twelve`, TimeFormat). Unit tested.
function dndLabel(mode, until, by, now, twelve) {
    if (!dndActive(mode, until, now)) return "Off"
    if (mode === "manual") return dndOwner(mode, by).length ? "Until you leave " + dndOwnerTitle(by) : "Until turned off"
    const end = new Date(Number(until))
    const current = new Date(Number(now))
    const later = end.getFullYear() !== current.getFullYear() || end.getMonth() !== current.getMonth()
        || end.getDate() !== current.getDate()
    return "Until " + TimeFormat.time(end, twelve === true, ":") + (mode === "tomorrow" && later ? " (tomorrow)" : "")
}

// Do Not Disturb as read back from state.json, written in boot `storedBoot`
// and read in `bootId`. A reboot ends a manual one - "until turned off" is a
// promise about this session - and a timed one keeps its clock time. `ended`
// names the mode whose manual Do Not Disturb the reboot ended ("" for none,
// and for the user's own): while that mode is still the one in use, it is
// the mode's again (`NotificationService.resumeModeDnd`). Gaming came back
// from a reboot without it, and notifications popped up in gaming until the
// mode was left and entered again. Unit tested.
function dndAtBoot(mode, by, storedBoot, bootId) {
    const known = ["off", "1h", "tomorrow", "manual"].indexOf(mode) >= 0 ? mode : "off"
    const owner = dndOwner(known, by)
    if (known === "manual" && String(storedBoot || "") !== String(bootId || ""))
        return { mode: "off", by: "", ended: owner }
    return { mode: known, by: owner, ended: "" }
}
