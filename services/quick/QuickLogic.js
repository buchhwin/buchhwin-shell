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
    { type: "vpn", label: "VPN", icon: "󰖂", w: 1, h: 2 },
    { type: "dnd", label: "Do Not Disturb", icon: "󰂚", w: 1, h: 2 },
    // Offered in the picker, in nobody's layout until added.
    { type: "stayAwake", label: "Stay awake", icon: "󰅶", w: 1, h: 2 },
    { type: "microphone", label: "Microphone", icon: "󰍬", w: 1, h: 2 },
    { type: "fingerprint", label: "Fingerprint", icon: "󰈷", w: 2, h: 2 },
    { type: "brightness", label: "Brightness", icon: "󰃟", w: 1, h: 3, minH: 2 },
    { type: "battery", label: "Battery", icon: "󰁽", w: 1, h: 3 },
    { type: "media", label: "Media", icon: "󰎈", w: 1, h: 5, minH: 2 },
    { type: "audio", label: "Audio", icon: "󰕾", w: 1, h: 5, minH: 2 },
    { type: "drives", label: "Drives", icon: "󰋊", w: 2, h: 2, minW: 2 },
    { type: "phone", label: "Phone", icon: "󰄜", w: 2, h: 2, minW: 2 },
    { type: "shortcuts", label: "Shortcuts", icon: "󰘳", w: 2, h: 2, minW: 2 },
    // The screen zoom and the color filter (ScreenEffectsService): offered
    // in the picker, on no panel until someone adds them.
    { type: "zoom", label: "Zoom", icon: "󰍋", w: 1, h: 2 },
    { type: "colorFilter", label: "Color filter", icon: "󰌁", w: 1, h: 2 }
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

// What the shown overview asks of the services for its tiles: the phone tile
// has KDE Connect polled (a script every 10 s), the fingerprint tile has the
// reader's state read (fprintd-list, which starts the root daemon). Only
// while the overview is shown (`live`) and only for a tile that is on it
// (`types`, LayoutService.quickTypes): both used to run on every open,
// whatever tiles the panel had.
function watches(types, live) {
    const list = types || []
    return {
        phone: live === true && list.indexOf("phone") >= 0,
        fingerprint: live === true && list.indexOf("fingerprint") >= 0
    }
}

// Whether a slider tile - brightness, and the battery beside it with its
// bar - is drawn in its one-line form in a cell `rows` grid steps tall. It is
// a question of rows, not of the cell's shape name: two rows (72 px with the
// gap) hold one line, so the slider comes up beside the glyph and the title
// goes; three (114 px) hold the title line and the slider under it, which a
// one-column cell of three rows used to draw as the one-line form with 80 px
// of empty card around it.
function sliderCompact(rows) {
    return Fit.step(rows, 1) <= 2
}

// What the audio tile draws in a cell of `shape` (FitLogic.fitClass) that is
// `rows` steps tall. The volume row always; the output device above it from
// three rows, where it fits; the System / Apps tabs only in a tall or large
// cell, which has room for what is under them as well.
function audioParts(shape, rows) {
    return { tabs: shape === "tall" || shape === "large", device: Fit.step(rows, 1) >= 3 }
}

// The Settings page that belongs to a control-center page, for the header's
// gear: on the Power page it opens Settings > Power, as the page's own button
// does, rather than whatever Settings showed last. "" for the overview and
// anything unknown, which leaves Settings where it was.
var SETTINGS_PAGES = {
    network: "network", bluetooth: "bluetooth", audio: "audio", power: "power",
    dnd: "notifications", drives: "desktop", tray: "autostart"
}
function settingsPage(page) {
    const key = String(page || "")
    return Object.prototype.hasOwnProperty.call(SETTINGS_PAGES, key) ? SETTINGS_PAGES[key] : ""
}

// Where Escape leaves the control center: a detail page goes back to the
// overview (""), and on the overview it is not the page's to take (null), so
// the panel closes.
function pageAfterEscape(page) {
    return String(page || "").length ? "" : null
}

// The widths of a row of chips sharing `room` px with `gap` between them,
// from what each one needs (its implicit width). As even as their words
// allow: the narrow ones grow towards one common width before any wide one
// grows, and no chip is given less than it needs while the row has room for
// all of them. Shared out by content length, the last chip of the control
// center's four ended up 107 px with its words against the edge beside a
// 163 px one. A row too short for all of them gets the plain needs back, and
// the layout shrinks them as before.
function chipWidths(needs, room, gap) {
    const list = (needs || []).map(value => Math.max(0, Number(value) || 0))
    if (!list.length) return []
    const free = Number(room) - Math.max(0, Number(gap) || 0) * (list.length - 1)
    const total = list.reduce((sum, value) => sum + value, 0)
    if (!(free >= total)) return list
    // The common width `level`: every chip narrower than it is raised to it,
    // and the rest keep what they need. Found from the narrowest up.
    const sorted = list.slice().sort((a, b) => a - b)
    let level = free / list.length
    let kept = 0
    for (let i = sorted.length - 1; i >= 0; --i) {
        const raised = (free - kept) / (i + 1)
        if (sorted[i] <= raised) { level = raised; break }
        kept += sorted[i]
        level = sorted[i]
    }
    return list.map(value => Math.max(value, level))
}
