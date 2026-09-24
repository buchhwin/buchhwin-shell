.pragma library

// The apps kept in front of the launcher's search field.
//
// **Why this one and nothing else.** A search surface is at heart one thing,
// its result list, and a fixed tile above it competes with that list for the
// room and for the attention. The exception is the thing you want to see
// *before* you type, which is exactly what a pinned app is - it answers the
// query "I have not typed anything yet". That was the objection on the record
// against filling the launcher with modules, and it is the reason this is the
// module that got built.
//
// Stored as a comma-string of desktop entry ids: `SettingsService` rebuilds
// every stored object with `Object.keys`, so an array becomes `{"0": …}` on the
// first write of any setting.

// More than this and the row is a second app grid rather than a shortcut, and
// it starts eating the height the results need.
var LIMIT = 10

function ids(text) {
    const seen = []
    for (const part of String(text || "").split(",")) {
        const id = part.trim()
        if (id.length && seen.indexOf(id) < 0) seen.push(id)
    }
    return seen.slice(0, LIMIT)
}

function has(text, id) {
    return ids(text).indexOf(String(id || "")) >= 0
}

// Pin or unpin, as the string to store. A new one goes to the end, where it
// does not move the ones already there out from under the pointer. At the
// limit, pinning one more is refused rather than quietly dropping the oldest:
// a list that forgets what you put on it is worse than one that says no.
function toggle(text, id) {
    const name = String(id || "")
    if (!name.length) return ids(text).join(",")
    const list = ids(text)
    const index = list.indexOf(name)
    if (index >= 0) list.splice(index, 1)
    else if (list.length < LIMIT) list.push(name)
    return list.join(",")
}

function full(text) {
    return ids(text).length >= LIMIT
}

// The apps themselves, in the pinned order. An id whose app is not installed
// right now is skipped **for drawing only** - it stays in the string, because
// an app that is missing today may be back tomorrow and a list that forgets
// during an upgrade is its own kind of bug.
function apps(text, entries) {
    // **Not `Array.isArray`.** What Quickshell hands out for
    // `DesktopEntries.applications.values` walks and filters like an array and
    // is not one, so the guard threw the whole list away and the pinned row
    // drew nothing while the ids sat in the settings file. Anything with a
    // length is copied into a real array and used as one.
    const list = []
    if (entries && typeof entries.length === "number")
        for (let index = 0; index < entries.length; ++index) list.push(entries[index])
    return ids(text)
        .map(id => list.find(app => app && app.id === id))
        .filter(app => app && !app.noDisplay)
}

function move(text, id, delta) {
    const list = ids(text)
    const from = list.indexOf(String(id || ""))
    const to = from + delta
    if (from < 0 || to < 0 || to >= list.length) return list.join(",")
    const moved = list.splice(from, 1)[0]
    list.splice(to, 0, moved)
    return list.join(",")
}
