.pragma library

// What the profile key does, and what it does to the automatic profile.
//
// The decision, taken with the user: cycling by hand turns the automatic
// switching **off**, because otherwise the choice silently reverts the next
// time a monitor is plugged in - AdaptiveService watches the suggestion and
// the flag, never the active profile, so a profile chosen by hand sticks right
// up until it does not. A delayed surprise is worse than an immediate one.
// Landing back on one of the two profiles the automatic switching itself picks
// turns it on again, so the automatic behaviour is reachable from the key
// rather than only from Settings, and the OSD says so either way.
//
// It is a function with a test rather than three lines at the call site
// because "what does the key do from each of five states, twice round" is
// exactly what a test is for and exactly what a nested session cannot show.

// The two profiles AdaptiveService chooses between on its own.
var AUTOMATIC = ["laptop", "docked"]

function names(list) {
    return (Array.isArray(list) ? list : []).filter(name => typeof name === "string" && name.length)
}

function nextProfile(current, list) {
    const all = names(list)
    if (!all.length) return ""
    // An unknown current profile starts the cycle at the beginning rather than
    // going nowhere: indexOf gives -1, and -1 + 1 is the first.
    return all[(all.indexOf(String(current || "")) + 1) % all.length]
}

// Whether automatic switching should be on once this profile is chosen.
function autoAfter(profile) {
    return AUTOMATIC.indexOf(String(profile || "")) >= 0
}

// Everything the key does, from what it can see. `null` when there is nothing
// to cycle through, so the caller can leave the OSD alone.
function cycle(current, list, wasAuto) {
    const profile = nextProfile(current, list)
    if (!profile.length) return null
    const auto = autoAfter(profile)
    return { profile: profile, auto: auto, autoChanged: auto !== Boolean(wasAuto) }
}

// What the OSD says. The automatic half only when the key changed it: a line
// that says the same thing every time is noise, which is the note the user
// made about the arrange row.
function osdText(label, step) {
    const name = String(label || "")
    if (!step || !step.autoChanged) return name
    return name + " · automatic " + (step.auto ? "on" : "off")
}

// A profile's own name and glyph. Both were written out at each call site; the
// glyphs describe what a profile is for, so they live with the profile rather
// than in Icons, which names actions.
function label(name, templates) {
    const key = String(name || "")
    const template = templates && templates[key] ? templates[key] : null
    return template && template.label ? template.label : key
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
