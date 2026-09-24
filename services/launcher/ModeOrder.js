.pragma library

// The order the launcher's modes appear in, and which of them appear at all.
//
// It is a stored **comma-string**, not a list: `SettingsService` rebuilds every
// stored object with `Object.keys`, so an array becomes `{"0": …}` on the first
// write of any setting - the two settings that were list-shaped before this are
// comma-strings for the same reason.
//
// The rules a stored order has to survive, which is why this is a function with
// a test rather than a `split(",")` at the call site:
//
//   * a mode the string does not name still appears, at the end, in the order
//     the shell lists them - otherwise a mode added in a later version is
//     invisible to everyone who ever reordered theirs;
//   * a name the shell does not know is dropped rather than making a hole;
//   * a name twice is one mode;
//   * `apps` is not removable and is always first of the ones that are shown -
//     it is the mode with no prefix, the one the launcher opens in, and a
//     launcher whose first mode needs a prefix opens showing nothing.

var PINNED_FIRST = "apps"

function names(text) {
    return String(text || "").split(",").map(part => part.trim()).filter(part => part.length)
}

// `stored` is the setting, `available` the ids the shell has right now.
function order(stored, available) {
    const have = (available || []).map(String)
    const seen = []
    for (const name of names(stored))
        if (have.indexOf(name) >= 0 && seen.indexOf(name) < 0) seen.push(name)
    // Anything the string does not name keeps the shell's own order, at the end.
    for (const name of have)
        if (seen.indexOf(name) < 0) seen.push(name)
    // The mode with no prefix leads, wherever the string put it.
    const first = seen.indexOf(PINNED_FIRST)
    if (first > 0) {
        seen.splice(first, 1)
        seen.unshift(PINNED_FIRST)
    }
    return seen
}

// The modes themselves, in that order. `modes` is the shell's list of objects
// with an `id`.
function apply(stored, modes) {
    const list = Array.isArray(modes) ? modes : []
    return order(stored, list.map(mode => mode.id))
        .map(id => list.find(mode => mode.id === id))
        .filter(Boolean)
}

// One mode moved by `delta`, as the string to store. `apps` does not move and
// nothing moves above it.
function move(stored, available, name, delta) {
    const list = order(stored, available)
    const from = list.indexOf(String(name))
    const to = from + delta
    const floor = String(name) === PINNED_FIRST ? 0 : 1
    if (from < 0 || to < floor || to >= list.length) return list.join(",")
    if (String(name) === PINNED_FIRST) return list.join(",")
    const moved = list.splice(from, 1)[0]
    list.splice(to, 0, moved)
    return list.join(",")
}

function canMove(stored, available, name, delta) {
    return move(stored, available, name, delta) !== order(stored, available).join(",")
}
