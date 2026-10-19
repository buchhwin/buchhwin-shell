.pragma library

// Unread counts on the dock's icons (`dock.badges`) and an app's volume under
// the wheel (`dock.wheelVolume`), both off until Settings > Dock turns them
// on. Plain objects in, plain answers out (DockWindowsTest).
//
// Chromium has the Badging API on Linux but shows nothing for it, so a web
// app's own count - Teams writes "(3) Chat | Microsoft Teams" - is only in its
// window's title. Apps that say nothing there have their unread
// notifications: the ones in the shell's history that came while the
// notification centre was closed (NotificationService.unseen).

// Counts above this show as "99+".
var MAX_SHOWN = 99
// One notch of the wheel over an icon: what a volume key does (5 %).
var VOLUME_STEP = 0.05

function lower(text) { return String(text || "").toLowerCase() }
function lastSegment(id) {
    const parts = String(id || "").split(".")
    return parts[parts.length - 1]
}

// ---- the count in a title ---------------------------------------------------------
// A web app installed from Chromium or Brave: crx_<id> under X11,
// <browser>-<id>-<profile> under Wayland, the id 32 letters a to p. Only these
// are read: a document called "(1) notes.txt" in an editor is no unread count,
// and a browser's window is titled after whatever tab is in front.
function isWebApp(cls) {
    const text = lower(cls)
    return /^crx_[a-p]{32}$/.test(text) || /^[a-z]+-[a-p]{32}-.+$/.test(text)
}

// The count a title starts with - "(3) Chat", "(12+) Inbox" -, 0 for none.
function titleBadge(title) {
    const match = /^\s*\((\d{1,4})\+?\)(\s|$)/.exec(String(title || ""))
    return match ? Number(match[1]) : 0
}

// ---- unread notifications ----------------------------------------------------------
// { key: count } of the unread ones, by the desktop entry the sender named
// (without ".desktop") and by its app name, both lowered: a notification
// counts once under each. `history`: [{ id, desktopEntry, appName }];
// `unseen`: { id: true }.
function unseenByApp(history, unseen) {
    const marks = unseen || {}
    const counts = {}
    for (const notification of Array.prototype.slice.call(history || [])) {
        if (!notification || marks[notification.id] !== true) continue
        const keys = [lower(notification.desktopEntry).replace(/\.desktop$/, ""), lower(notification.appName)]
            .filter((key, index, list) => key.length > 0 && list.indexOf(key) === index)
        for (const key of keys) counts[key] = (counts[key] || 0) + 1
    }
    return counts
}

// The names an app on the dock goes by: its entry's id (and the last part of
// a reverse-DNS one), its name - a web app's without " (PWA)" -, and its
// windows' classes. Lowered, each once.
function appKeys(item) {
    const it = item || {}
    const keys = []
    const add = key => {
        const text = lower(key).trim()
        if (text.length && keys.indexOf(text) < 0) keys.push(text)
    }
    add(it.entryId)
    add(String(it.entryId || "").replace(/\.desktop$/i, ""))
    add(lastSegment(it.entryId))
    add(it.name)
    add(String(it.name || "").replace(/\s*\(pwa\)\s*$/i, ""))
    for (const window of Array.prototype.slice.call(it.windows || [])) {
        if (!window) continue
        add(window.appClass)
        add(lastSegment(window.appClass))
    }
    return keys
}

// An app's unread notifications: the largest count among its names - a
// notification is counted under its entry and its app name, and an app that
// answers to both must not count it twice.
function notificationBadge(item, counts) {
    const table = counts || {}
    let best = 0
    for (const key of appKeys(item)) best = Math.max(best, Number(table[key]) || 0)
    return best
}

// The badge on an app: what its windows' titles say (the largest, for an app
// with several windows that say the same), else its unread notifications.
function itemBadge(item, counts) {
    const windows = Array.prototype.slice.call((item && item.windows) || [])
    const titled = windows.reduce((most, window) => Math.max(most, Number(window && window.badge) || 0), 0)
    return titled > 0 ? titled : notificationBadge(item, counts)
}

function badgeText(count) {
    const n = Math.max(0, Math.round(Number(count) || 0))
    return n <= 0 ? "" : n > MAX_SHOWN ? MAX_SHOWN + "+" : String(n)
}

// ---- volume under the wheel -----------------------------------------------------------
// A playback stream's names, lowered: what PipeWire knows of the app that
// plays it (`application.name`, `application.process.binary`,
// `application.icon-name`) and the node's own name and description, which
// are there before the node is bound. `stream`: { appName, binary, icon,
// name, description }.
function streamKeys(stream) {
    const s = stream || {}
    const keys = []
    for (const value of [s.appName, s.binary, s.icon, s.name, s.description]) {
        const text = lower(value).trim()
        if (text.length && keys.indexOf(text) < 0) keys.push(text)
    }
    return keys
}

// Whether a stream is an app's: one of its names is one of the stream's.
// `program`: the program the app's entry runs (brave, spotify) - a web app's
// sound comes from its browser, which cannot tell one web app's from
// another's, so the wheel over Teams turns Brave's streams.
function streamMatches(item, program, stream) {
    const own = appKeys(item)
    const binary = lower(program).trim()
    if (binary.length && own.indexOf(binary) < 0) own.push(binary)
    const theirs = streamKeys(stream)
    return theirs.some(key => own.indexOf(key) >= 0)
}

// What the icon says while the wheel turns: the level of the first stream,
// as a whole percentage - or, for none (DockService.stepVolume's -1), that
// nothing of it plays.
function volumeNotice(level) {
    const value = level === null || level === undefined || level === "" ? NaN : Number(level)
    return isFinite(value) && value >= 0 ? "Volume " + Math.round(Math.min(1, value) * 100) + "%" : "Nothing playing"
}
