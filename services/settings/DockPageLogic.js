.pragma library

// Settings > Dock (shell/settings/pages/DockPage.qml): which preset is the
// one in use, and the dock's pins as the rows of its list.

var ZONES = ["left", "center", "right"]

// What a dock holds, zone by zone and pill by pill, as widget types: what a
// preset decides, without the ids, displays and sizes the editor tunes.
function zoneTypes(dock) {
    const result = {}
    for (const zone of ZONES) {
        const pills = dock && Array.isArray(dock[zone]) ? dock[zone] : []
        result[zone] = pills.map(pill => (pill && Array.isArray(pill.items) ? pill.items : [])
            .map(item => item && item.type ? String(item.type) : ""))
    }
    return result
}

// Whether any pill of the dock holds a widget of this type.
function holds(dock, type) {
    const zones = zoneTypes(dock)
    return ZONES.some(zone => zones[zone].some(types => types.indexOf(type) >= 0))
}

function sameTypes(first, second) {
    return JSON.stringify(zoneTypes(first)) === JSON.stringify(zoneTypes(second))
}

// The id of the preset the dock is built from: the same widgets in the same
// zones. The pins do not count - they are the user's once pinned and
// unpinned, and a preset may leave them as they are - and neither do the
// options tuned since (Behavior and Look on the same page): the live dock of
// 16.10. was the Dock preset with a margin of 4 instead of 8, and a mark that
// went out with the first tuned option said "neither" about it. Where two
// presets hold the same widgets, the one whose options all match. "" when
// the dock has been made into something of its own. `valueOf(key)` reads a
// dock option ("iconSize" for dock.iconSize).
function presetInUse(presets, dock, valueOf) {
    const built = Array.prototype.slice.call(presets || []).filter(preset => preset && sameTypes(preset.layout, dock))
    const exact = built.find(preset => {
        const options = preset.options || {}
        return Object.keys(options).every(key => valueOf(key) === options[key])
    })
    const found = exact || built[0]
    return found ? String(found.id || "") : ""
}

// The defaults a pin can stand for (Settings > Default apps), and what a row
// says about one.
var DEFAULTS = {
    "@files": { name: "Files", role: "Default file manager" },
    "@terminal": { name: "Terminal", role: "Default terminal" },
    "@browser": { name: "Browser", role: "Default browser" }
}

// One row of the pin list. `entry` is the desktop entry the pin resolves to
// now ({ name, icon }, null when there is none: an app uninstalled, a
// default not set). Such a pin still holds one of the dock's places and
// draws nothing on the dock, so the row says so, and the row is where it can
// be taken off. `defaultsKnown`: Settings > Default apps' list has been read
// (until then a default is not missing, only not looked up yet).
function pinRow(pin, entry, defaultsKnown) {
    const id = String(pin || "")
    if (id === "@settings")
        return { pin: id, name: "Settings", subtitle: "This shell's settings", icon: "", settings: true, missing: false }
    const fallback = DEFAULTS[id]
    if (fallback) {
        const missing = !entry && defaultsKnown === true
        return { pin: id, name: entry && entry.name ? entry.name : fallback.name,
                 subtitle: missing ? fallback.role + " - none found" : fallback.role,
                 icon: entry && entry.icon ? entry.icon : "", settings: false, missing: missing }
    }
    if (!entry) return { pin: id, name: id, subtitle: "Not installed", icon: "", settings: false, missing: true }
    return { pin: id, name: entry.name || id, subtitle: "", icon: entry.icon || "", settings: false, missing: false }
}

// Where the pin at `index` goes one step earlier (-1) or later (+1); -1
// when it is at that end already.
function stepTarget(index, delta, count) {
    const next = index + (delta < 0 ? -1 : 1)
    return index < 0 || index >= count || next < 0 || next >= count ? -1 : next
}
