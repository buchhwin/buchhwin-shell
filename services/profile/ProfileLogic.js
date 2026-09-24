.pragma library

// Two levels, and the words for them.
//
// A **mode** is what the desktop is set to right now: minimal, work, gaming,
// laptop or docked. A **profile** holds its own five modes. The layout file
// called the five "profiles" until v3 and the user never did - they are modes,
// and this file is where both words are defined.
//
// What the mode key does, and what it does to the automatic mode:
//
// The decision, taken with the user: cycling by hand turns the automatic
// switching **off**, because otherwise the choice silently reverts the next
// time a monitor is plugged in - AdaptiveService watches the suggestion and
// the flag, never the active mode, so a mode chosen by hand sticks right
// up until it does not. A delayed surprise is worse than an immediate one.
// Landing back on one of the two modes the automatic switching itself picks
// turns it on again, so the automatic behaviour is reachable from the key
// rather than only from Settings, and the OSD says so either way.
//
// It is a function with a test rather than three lines at the call site
// because "what does the key do from each of five states, twice round" is
// exactly what a test is for and exactly what a nested session cannot show.

// The two modes AdaptiveService chooses between on its own. They may not be
// renamed or removed anywhere, because this list points at them by name.
var AUTOMATIC = ["laptop", "docked"]

// The five modes every profile has, in the order the key cycles through them.
var MODE_NAMES = ["minimal", "work", "gaming", "laptop", "docked"]

// ---- which settings belong to a mode ---------------------------------------
// The one place that says it. A setting listed here is stored per mode and
// re-applied when the mode is entered; everything else is one choice for the
// whole session.
//
// They are all in the `appearance` group, and that is not a coincidence: what
// differs between a laptop on battery and a docked desktop is how heavy the
// interface is allowed to look, not which theme or which font it uses. So the
// list is leaf names inside that one group, and `modeScopedPath` makes the
// full setting path.
//
// Deliberately **not** here: theme, accent, fonts, cursor and locale. Those
// describe the session, not the mode, and a user who changes the accent in one
// mode means it for all of them.
var MODE_SCOPED_GROUP = "appearance"
var MODE_SCOPED = ["blurStrength", "panelOpacity", "animationMode", "animationSpeed",
                   "windowRadius", "shellRadius", "borderEnabled", "borderSize",
                   "gapsIn", "gapsOut"]

function modeScopedPath(leaf) {
    return MODE_SCOPED_GROUP + "." + String(leaf || "")
}

function modeScopedPaths() {
    return MODE_SCOPED.map(modeScopedPath)
}

// The leaf a full setting path names, or "" when the path is not mode-scoped.
function modeScopedLeaf(path) {
    const text = String(path || "")
    const prefix = MODE_SCOPED_GROUP + "."
    if (text.indexOf(prefix) !== 0) return ""
    const leaf = text.slice(prefix.length)
    return MODE_SCOPED.indexOf(leaf) >= 0 ? leaf : ""
}

function isModeScoped(path) {
    return modeScopedLeaf(path).length > 0
}

// ---- cycling ---------------------------------------------------------------

function names(list) {
    return (Array.isArray(list) ? list : []).filter(name => typeof name === "string" && name.length)
}

function nextIn(current, list) {
    const all = names(list)
    if (!all.length) return ""
    // An unknown current entry starts the cycle at the beginning rather than
    // going nowhere: indexOf gives -1, and -1 + 1 is the first.
    return all[(all.indexOf(String(current || "")) + 1) % all.length]
}

function nextMode(current, list) {
    return nextIn(current, list)
}

// The profile key cycles the level above. It has no automatic half: nothing
// switches a profile on its own, so there is no flag to settle.
function nextProfile(current, list) {
    return nextIn(current, list)
}

// Whether automatic switching should be on once this mode is chosen.
function autoAfter(mode) {
    return AUTOMATIC.indexOf(String(mode || "")) >= 0
}

// Everything the mode key does, from what it can see. `null` when there is
// nothing to cycle through, so the caller can leave the OSD alone.
function cycleMode(current, list, wasAuto) {
    const mode = nextMode(current, list)
    if (!mode.length) return null
    const auto = autoAfter(mode)
    return { mode: mode, auto: auto, autoChanged: auto !== Boolean(wasAuto) }
}

// What the OSD says. The automatic half only when the key changed it: a line
// that says the same thing every time is noise, which is the note the user
// made about the arrange row.
function osdText(label, step) {
    const name = String(label || "")
    if (!step || !step.autoChanged) return name
    return name + " · automatic " + (step.auto ? "on" : "off")
}

// A mode's own name and glyph. Both were written out at each call site; the
// glyphs describe what a mode is for, so they live here rather than in Icons,
// which names actions.
function label(name, templates) {
    const key = String(name || "")
    const template = templates && templates[key] ? templates[key] : null
    return template && template.label ? template.label : key
}

// A profile is a set of modes, not one of them, so it gets a glyph of its own
// rather than borrowing whichever mode happens to be active.
function profileIcon() {
    return "\u{f003b}"
}

function icon(name) {
    switch (String(name || "")) {
    case "gaming": return "󰊴"
    case "laptop": return "󰌢"
    case "docked": return "󰍹"
    case "work": return "󰃖"
    }
    return "󰥔"
}

// ---- naming a profile ------------------------------------------------------
// A profile's id is what the layout file and the IPC use; its label is what the
// user typed. The id is derived from the label so `buchhwin profile set work`
// is guessable, and made unique so two profiles called "Work" can both exist.

function slug(text) {
    const cleaned = String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return cleaned.length ? cleaned : "profile"
}

function uniqueName(text, taken) {
    const list = names(taken)
    const base = slug(text)
    if (list.indexOf(base) < 0) return base
    let index = 2
    while (list.indexOf(base + "-" + index) >= 0) index += 1
    return base + "-" + index
}
