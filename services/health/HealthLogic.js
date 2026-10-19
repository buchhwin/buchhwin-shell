.pragma library

// Settings > About's Health: what scripts/session-check.sh --json and
// scripts/doctor.sh --json found, and what the shell itself knows to be left
// to do (a reader with no finger, a VPN without its tile, a default app
// missing), as one list of things to look at - each with a command to copy
// for the steps that need sudo, or a button for the ones that are the
// user's own. Pure; unit tested in tests/qml/HealthTest.qml.

var LEVELS = ["error", "warn", "note"]
var LEVEL_RANK = { "error": 0, "warn": 1, "note": 2 }
// What a button does, and what it says. The page maps each to a call.
var ACTIONS = {
    "restartShell": "Restart shell",
    "enrollFinger": "Enroll finger",
    "vpnTile": "Add tile",
    "defaultApps": "Default apps",
    "lockScreen": "Lock screen"
}
// How long a run counts as fresh when the page opens again.
var FRESH_MS = 60000
var CORE_APPS = ["browser", "terminal", "files"]

function clean(text, limit) {
    const value = typeof text === "string" ? text.trim() : ""
    return value.length > limit ? value.slice(0, limit - 1) + "…" : value
}

// One finding, checked: a level the page knows, text, at most one command
// line (no newline: it is copied as one line) and an action it has a button
// for. The text starts with a capital, as a sentence on the page: the
// scripts' messages often start with a tool's name in lower case.
function item(level, text, command, action, section, id) {
    const raw = clean(text, 400)
    const shown = raw.length ? raw[0].toUpperCase() + raw.slice(1) : raw
    if (!shown.length || LEVELS.indexOf(level) < 0) return null
    const line = clean(command, 600)
    return {
        id: clean(id, 80) || shown,
        level: level,
        text: shown,
        section: clean(section, 80),
        command: line.indexOf("\n") < 0 ? line : "",
        action: ACTIONS[action] ? action : ""
    }
}

// JSON lines → { items, result } for one script. session-check's levels are
// ok, warn and error; doctor's missing and note. An ok is counted, not
// listed; a line that does not parse is skipped.
function parseLines(text, source) {
    const items = []
    const ids = {}
    let ok = 0
    let result = null
    for (const raw of String(text || "").split("\n")) {
        const line = raw.trim()
        if (!line.length || line[0] !== "{") continue
        let data = null
        try { data = JSON.parse(line) } catch (error) { continue }
        if (!data || typeof data !== "object") continue
        if (data.kind === "result") { result = data; continue }
        if (data.level === "ok") { ok += 1; continue }
        const level = data.level === "missing" ? "warn" : data.level
        const found = item(level, data.text, data.command, data.action, data.section || (source === "doctor" ? "Packages" : ""),
                           source + ":" + (data.id || data.text))
        if (!found) continue
        // The page keys its rows by id, and one check can speak once per
        // thing it found (doctor's note for each icon folder): a second one
        // gets its place in the list on top.
        if (ids[found.id]) found.id += "#" + items.length
        ids[found.id] = true
        items.push(found)
    }
    return { items: items, ok: ok, result: result }
}

// What the shell knows: state = { reader: { available, fingers, pamMissing,
// onCommand }, vpn: { count, tile }, apps: DefaultAppsService.categories }.
function shellItems(state) {
    const items = []
    const reader = state && state.reader
    if (reader && reader.available && reader.fingers === 0)
        items.push(item("note", "A fingerprint reader without a finger: enroll one to unlock the lock screen with it", "", "enrollFinger", "Fingerprint", "shell:finger"))
    if (reader && reader.available && reader.fingers > 0 && reader.pamMissing)
        items.push(item("warn", "A finger is enrolled, but the reader is not in the lock screen's PAM file yet, so the lock asks for the password only",
                        reader.onCommand, "lockScreen", "Fingerprint", "shell:pam"))
    const vpn = state && state.vpn
    if (vpn && vpn.count > 0 && !vpn.tile)
        items.push(item("note", (vpn.count === 1 ? "A VPN connection" : vpn.count + " VPN connections")
                        + " but no VPN tile in the control center", "", "vpnTile", "Control center", "shell:vpn"))
    for (const category of (state && state.apps) || []) {
        if (!category || CORE_APPS.indexOf(category.id) < 0) continue
        if (typeof category.current === "string" && category.current.length && category.currentName) continue
        items.push(item("warn", "No default " + String(category.label || category.id).toLowerCase()
                        + " - the keys that open one do nothing", "", "defaultApps", "Default apps", "shell:app:" + category.id))
    }
    return items.filter(found => found !== null)
}

// Every source's items as one list, the most urgent first, each text once.
function merge(lists) {
    const seen = {}
    const merged = []
    for (const list of lists || []) {
        for (const found of list || []) {
            if (!found || seen[found.text]) continue
            seen[found.text] = true
            merged.push(found)
        }
    }
    return merged.map((found, index) => ({ found: found, index: index }))
        .sort((a, b) => (LEVEL_RANK[a.found.level] - LEVEL_RANK[b.found.level]) || a.index - b.index)
        .map(entry => entry.found)
}

function actionLabel(action) {
    return ACTIONS[action] || ""
}

// The line above the list.
function summary(items, ran, running) {
    if (running && !ran) return "Checking the session …"
    if (!ran) return "Not checked yet"
    const count = (items || []).length
    if (!count) return "Everything is set up"
    return count === 1 ? "1 thing to look at" : count + " things to look at"
}

function levelLabel(level) {
    return level === "error" ? "Error" : level === "warn" ? "Warning" : "Note"
}

function due(lastRun, now) {
    return !lastRun || now - lastRun >= FRESH_MS
}
