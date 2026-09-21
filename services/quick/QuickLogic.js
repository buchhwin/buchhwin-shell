.pragma library
.import "../arrange/FitLogic.js" as Fit

// The tiles the control center can show, for the picker and for the labels in
// its edit mode. The tiles themselves live in
// shell/controlcenter/pages/OverviewPage.qml; this is only what they are
// called, what they look like in a list, and how wide they sit.
//
// A tile that has nothing to show hides itself (no reader, no phone, no
// removable drive). That is not the same as being removed here, which is the
// user saying they never want to see it.

var catalogue = [
    { type: "wifi", label: "Wi-Fi", icon: "󰤨", w: 1, h: 2 },
    { type: "bluetooth", label: "Bluetooth", icon: "󰂯", w: 1, h: 2 },
    { type: "dnd", label: "Do Not Disturb", icon: "󰂚", w: 1, h: 2 },
    { type: "microphone", label: "Microphone", icon: "󰍬", w: 1, h: 2 },
    { type: "fingerprint", label: "Fingerprint", icon: "󰈷", w: 2, h: 2 },
    { type: "brightness", label: "Brightness", icon: "󰃟", w: 1, h: 3, minH: 2 },
    { type: "battery", label: "Battery", icon: "󰁽", w: 1, h: 3 },
    { type: "media", label: "Media", icon: "󰎈", w: 1, h: 5, minH: 2 },
    { type: "audio", label: "Audio", icon: "󰕾", w: 1, h: 5, minH: 2 },
    { type: "drives", label: "Drives", icon: "󰋊", w: 2, h: 2, minW: 2 },
    { type: "phone", label: "Phone", icon: "󰄜", w: 2, h: 2, minW: 2 },
    { type: "shortcuts", label: "Shortcuts", icon: "󰘳", w: 2, h: 2, minW: 2 }
]

function entry(type) {
    return catalogue.find(tile => tile.type === String(type || "")) || null
}

function label(type) {
    const found = entry(type)
    return found ? found.label : String(type || "")
}

function icon(type) {
    const found = entry(type)
    return found ? found.icon : ""
}

// How big a tile starts: `w` columns wide and `h` rows tall in the panel's
// grid. Both are the user's from then on - a corner is dragged - so this is
// only where a tile begins, and it begins where it used to sit.
function size(type) {
    const found = entry(type)
    // Anything not in the table is a desktop widget the panel accepts: one
    // column, two of its 30 px rows, which is a glyph and a line of text.
    return found ? { w: found.w, h: found.h } : { w: 1, h: 2 }
}

// The smallest cell this tile may be pulled to. Most tiles have none and go
// down to a single step; a slider, a player and a list do not - below their
// minimum they are not a smaller version of themselves, they are nothing.
function minSize(type) {
    return Fit.minSize(entry(type))
}

function isKnown(type) {
    return entry(type) !== null
}

// What the picker offers: everything that is not on the panel already.
function missing(types) {
    const shown = types || []
    return catalogue.filter(tile => shown.indexOf(tile.type) < 0)
}
