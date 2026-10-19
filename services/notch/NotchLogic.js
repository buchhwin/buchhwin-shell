.pragma library
.import "../appearance/TimeFormat.js" as TimeFormat

// Pure helpers for the notch (desktop mode "notch", shell/notch): texts, the
// catalogue the editor offers, status icons and the outline of the shape.

// The time the way the clock widget writes it: "18:52", or "6:52 PM" when
// the clock is set to twelve hours (SettingsService.twelveHourClock, which
// the caller passes). TimeFormat is the one place a time becomes text; this
// was the copy it had missed, so the strip and the overview said "18:52"
// beside a bar clock that said "6:52 PM".
function timeText(date, twelve) {
    return TimeFormat.time(date, twelve === true, ":")
}

// The event the overview shows: the timed event of today that has not ended
// (the one running or starting first), else the first all-day event, else null.
function nextEvent(events, now) {
    let best = null
    let allDay = null
    for (const event of events || []) {
        if (!event || !(event.start instanceof Date)) continue
        if (event.allDay) {
            if (allDay === null) allDay = event
            continue
        }
        const end = event.end instanceof Date ? event.end : event.start
        if (end.getTime() <= now.getTime() && event.start.getTime() < now.getTime()) continue
        if (best === null || event.start.getTime() < best.start.getTime()) best = event
    }
    return best || allDay
}

// The events the wide overview lists: timed events of today that have not
// ended, earliest first, then all-day events, at most `count`. Unit tested.
function upcomingEvents(events, now, count) {
    const limit = Math.max(1, count || 1)
    const timed = []
    const allDay = []
    for (const event of events || []) {
        if (!event || !(event.start instanceof Date)) continue
        if (event.allDay) { allDay.push(event); continue }
        const end = event.end instanceof Date ? event.end : event.start
        if (end.getTime() <= now.getTime() && event.start.getTime() < now.getTime()) continue
        timed.push(event)
    }
    timed.sort((a, b) => a.start.getTime() - b.start.getTime())
    return timed.concat(allDay).slice(0, limit)
}

// Short time line for the event row. `twelve` as in `timeText`.
function eventWhen(event, now, twelve) {
    if (!event) return ""
    if (event.allDay) return "All day"
    const start = event.start.getTime()
    const end = event.end instanceof Date ? event.end.getTime() : start
    const current = now.getTime()
    if (start <= current && end > current) return "Now · until " + timeText(event.end, twelve)
    const minutes = Math.ceil((start - current) / 60000)
    if (minutes >= 0 && minutes < 60) return minutes <= 1 ? "In 1 min" : "In " + minutes + " min"
    return end > start ? timeText(event.start, twelve) + " – " + timeText(event.end, twelve) : timeText(event.start, twelve)
}

// Status icons of the overview: network, Bluetooth, Do Not Disturb (only
// while on), volume and battery (with percent) - the order of the bars' and
// the taskbar's status, the battery at the outer end where its percent is.
// `dim` marks something off.
// The battery is `charging` or `low` (PowerService.low, the level from
// Settings > Power), never both: a battery on the charger is not in trouble,
// whatever the number says.
function statusItems(state) {
    const items = []
    const s = state || {}
    if (s.network) items.push({ id: "network", icon: s.network.icon, text: "", dim: !s.network.connected })
    if (s.bluetooth && s.bluetooth.available)
        items.push({ id: "bluetooth", icon: s.bluetooth.icon, text: "", dim: !s.bluetooth.connected })
    if (s.dnd) items.push({ id: "dnd", icon: "󰂛", text: "", dim: false })
    // Stay awake while it holds: { on, icon } (IdleService).
    if (s.stayAwake && s.stayAwake.on === true)
        items.push({ id: "stayAwake", icon: String(s.stayAwake.icon || ""), text: "", dim: false })
    if (s.volume) items.push({ id: "volume", icon: s.volume.icon, text: "", dim: s.volume.muted === true })
    if (s.battery && s.battery.present) {
        const charging = s.battery.charging === true
        items.push({ id: "battery", icon: s.battery.icon, text: Math.round(s.battery.percent) + "%", dim: false,
                     charging: charging, low: !charging && s.battery.low === true })
    }
    return items
}

// What an overview cell with nothing to show says: what is missing, rather
// than the bare name of the block ("Weather", "Events", "Active window"),
// which read like a label someone forgot to fill in. Still one muted line
// beside the block's glyph, so it is no louder than the name was; hiding the
// cell instead would leave a hole in a grid the user arranged, and an empty
// field that reads as broken - unless the item asks for exactly that
// (`hidesEmpty`). `facts`: `weather` (WeatherService.status) and
// `workspaceEmpty` (no window on the focused workspace). Anything else keeps
// `fallback`, its name.
function emptyText(type, facts, fallback) {
    const f = facts || {}
    if (type === "weather") {
        return f.weather === "disabled" ? "Weather off"
            : f.weather === "noLocation" ? "No location"
            : f.weather === "error" ? "No forecast"
            : "Loading …"
    }
    if (type === "events" || type === "calendarSummary") return "No events"
    if (type === "media" || type === "nowPlaying") return "Nothing playing"
    if (type === "activeWindow") return f.workspaceEmpty === true ? "Empty workspace" : "No window"
    return String(fallback || type || "")
}

// Whether an overview cell is left out of the grid for now. Only an item
// that says so (`options.hideEmpty`, which the built-in presets give their
// music block - "Nothing playing" was the biggest thing on Island most of the
// time - and Classic its weather as well) and only while its block has
// nothing to draw (no song, no forecast): the grid then closes up, and the
// cell comes back with the song. Never while the notch is arranged, where
// every item has to be there to be taken hold of. The notch's own blocks
// only: a widget's emptiness is known once it is loaded, in the very cell
// this would take away.
var HIDE_EMPTY_TYPES = ["weather", "media", "events"]

function hidesEmpty(item, hasContent, arranging) {
    if (arranging === true || hasContent === true || !item || !item.options) return false
    return item.options.hideEmpty === true && HIDE_EMPTY_TYPES.indexOf(item.type) >= 0
}

// ---- what the editor offers -------------------------------------------------
// The notch's own blocks: what it draws better than a widget can - the
// weather beside the time, the music with its controls, the day's events and
// the status row. The weather is a widget too (WidgetRegistry), and that is
// what the strip loads for it; the other three exist only as blocks.
var BLOCKS = [
    { type: "weather", label: "Weather", icon: "\u{f0590}" },
    { type: "media", label: "Media", icon: "\u{f075a}" },
    { type: "events", label: "Events", icon: "\u{f00ed}" },
    { type: "status", label: "Status", icon: "\u{f05a9}" }
]

// The blocks the strip cannot draw. It draws the time, the recording and the
// timer itself and loads a widget file for everything else, and these have
// none: put there, one was an empty spot that could not go back into the
// overview either, because a type sits in one list only.
var STRIP_REFUSES = ["media", "events", "status"]

function stripTakes(type) {
    return STRIP_REFUSES.indexOf(String(type)) < 0
}

// What a widget is called on the notch, where a block may already carry its
// name: the calendar widget is "Events" everywhere else, and beside the
// events block that was two buttons saying the same thing.
var WIDGET_LABELS = { calendarSummary: "Calendar" }

function widgetLabel(type, label) {
    return Object.prototype.hasOwnProperty.call(WIDGET_LABELS, type) ? WIDGET_LABELS[type] : String(label || type || "")
}

// The whole catalogue: the blocks first, then every widget that is not one of
// them already (the weather was offered twice). `widgets` is
// WidgetRegistry.availableTypes(): `{ name, label, icon, category }`.
function catalogue(blocks, widgets) {
    const own = (Array.isArray(blocks) ? blocks : []).map(block =>
        ({ type: block.type, label: block.label, icon: block.icon, category: "blocks" }))
    const taken = own.map(block => block.type)
    const rest = (Array.isArray(widgets) ? widgets : [])
        .filter(widget => widget && taken.indexOf(widget.name) < 0)
        .map(widget => ({ type: widget.name, label: widgetLabel(widget.name, widget.label),
                          icon: widget.icon, category: widget.category }))
    return own.concat(rest)
}

// What the editor's list offers for a zone: the catalogue less what is on the
// notch already (a type sits in one list or the other), and for the strip
// less what it cannot draw. `onNotch`: every type in either list.
function offered(entries, onNotch, zone) {
    const placed = Array.isArray(onNotch) ? onNotch : []
    return (Array.isArray(entries) ? entries : []).filter(entry =>
        placed.indexOf(entry.type) < 0 && (zone !== "collapsed" || stripTakes(entry.type)))
}

// The list in groups, in the order of `categories` ({ id, label }), the
// blocks first under their own heading; anything in no known group comes
// last rather than not at all. Groups left with nothing go.
function catalogueGroups(entries, categories) {
    const groups = [{ id: "blocks", label: "Blocks" }].concat(Array.isArray(categories) ? categories : [])
    const ids = groups.map(group => group.id)
    const list = Array.isArray(entries) ? entries : []
    return groups.map(group => ({ id: group.id, label: group.label,
                                  entries: list.filter(entry => entry.category === group.id) }))
        .concat([{ id: "other", label: "Other", entries: list.filter(entry => ids.indexOf(entry.category) < 0) }])
        .filter(group => group.entries.length > 0)
}

// Width of the collapsed notch: room for the strip the user arranged plus
// padding on both sides, never below the minimum and never wider than the
// expanded shape - a strip that outgrew the surface would be cut off by it.
// The strip is measured rather than computed, because what it carries is a
// list now and not a clock plus an optional recording chip.
function collapsedWidth(contentWidth, wanted, minWidth, maxWidth, padding) {
    const room = Math.max(minWidth, maxWidth)
    const content = Math.ceil(contentWidth + padding * 2)
    // The width the user dragged is a floor, not a cage: a strip whose items
    // no longer fit would cut them off, and there is no scrollbar on a notch.
    const floor = Math.max(minWidth, Math.round(Number(wanted) || 0))
    return Math.min(room, Math.max(floor, content))
}

// The overview's size. Both are dragged, both are bounded by the surface, and
// the height is a floor too: what the grid needs always wins.
function expandedSize(wantedWidth, wantedHeight, contentHeight, defaults) {
    const d = defaults || {}
    const minWidth = Math.max(1, Number(d.minWidth) || 1)
    const maxWidth = Math.max(minWidth, Number(d.maxWidth) || minWidth)
    const maxHeight = Math.max(1, Number(d.maxHeight) || 1)
    const fallback = Math.max(minWidth, Math.min(maxWidth, Number(d.width) || minWidth))
    const width = Number(wantedWidth) > 0
        ? Math.max(minWidth, Math.min(maxWidth, Math.round(Number(wantedWidth))))
        : fallback
    const floor = Number(wantedHeight) > 0 ? Math.round(Number(wantedHeight)) : 0
    const height = Math.min(maxHeight, Math.max(floor, Math.round(Number(contentHeight) || 0)))
    return { width: width, height: height }
}

// How many grid columns a width of that many pixels is worth. Wider notches
// get more columns rather than wider cells, so a cell stays the size of the
// things it holds. This is what replaced "wide" and "stacked".
function gridColumns(width, cell, maxColumns) {
    const step = Math.max(1, Number(cell) || 1)
    const most = Math.max(1, Math.round(Number(maxColumns) || 1))
    return Math.max(1, Math.min(most, Math.round(Number(width) / step)))
}

// The strip as it is drawn: the arranged list, led by the recording chip
// while a recording runs and the list does not carry one itself. The pill bar
// follows the same rule for its own recording pill. The automatic chip has no
// id because it is not in the list, which is also what makes it undraggable.
function stripItems(items, recording, timer) {
    let list = Array.isArray(items) ? items.slice() : []
    // A running countdown leads the strip too, after a recording.
    if (timer && !list.some(item => item && item.type === "timer"))
        list = [{ id: "", type: "timer" }].concat(list)
    if (recording && !list.some(item => item && item.type === "recording"))
        return [{ id: "", type: "recording" }].concat(list)
    return list
}

// Whether a part of the strip is drawn. A widget with nothing to say
// (`hasData` false: a privacy item while nothing listens, a player that is
// not there) is left out, as the pill bar and the overview leave it out; a
// placed recording or timer item only while one runs - before, the strip
// showed "Microphone active" all day and a lone red dot. While the notch is
// arranged every part is there, so it can be taken hold of and the drop
// indices count the whole list.
function stripShows(type, hasData, recording, timer, arranging) {
    if (arranging === true) return true
    if (type === "recording") return recording === true
    if (type === "timer") return timer === true
    return hasData !== false
}

// ---- beside a taskbar ----------------------------------------------------------
// notch.dockDuplicates: "keep" (the default) or "hide". A dock along a whole
// edge and always there - the Taskbar preset - with the status glyphs or the
// clock on it shows them a second time on the screen the strip is on (Island's
// strip: the time, Wi-Fi and the battery). With "hide" the strip on such a
// screen leaves out the readouts the dock holds too; a dock that hides, fits
// its apps, is off or is on another screen leaves the strip as it is, and so
// does the layout editor, which arranges every item there is.
var DOCK_DUPLICATES = ["keep", "hide"]
// What counts as a readout the two would show twice. The workspaces, the
// recording and anything else stay on the strip.
var DOCK_READOUTS = ["clock", "date", "network", "bluetooth", "volume", "battery", "notificationIndicator"]

function dockDuplicates(value) {
    return DOCK_DUPLICATES.indexOf(value) >= 0 ? value : "keep"
}

// The types the strip on `screenName` leaves out. `dock`: { enabled, span,
// visibility, screens: [names it is on] }; `held`: the types its layout
// holds. [] unless the setting is "hide" and the dock is a full, always
// shown one on that screen.
function dockDuplicateTypes(setting, dock, held, screenName, arranging) {
    if (dockDuplicates(setting) !== "hide" || arranging === true || !dock || dock.enabled !== true) return []
    if (dock.span !== "full" || dock.visibility !== "always") return []
    if (!screenName || !Array.isArray(dock.screens) || dock.screens.indexOf(screenName) < 0) return []
    return (Array.isArray(held) ? held : []).filter(type => DOCK_READOUTS.indexOf(type) >= 0)
}

// The strip's items without those types; the very list when nothing goes.
function withoutTypes(items, types) {
    const list = Array.isArray(items) ? items : []
    if (!Array.isArray(types) || !types.length) return list
    return list.filter(item => !(item && types.indexOf(item.type) >= 0))
}

// The strip around its clock. The notch's shape is centred on the screen, so
// the clock sits in the middle of the screen only if the strip is as wide on
// its lighter side as on its heavier one: five workspace dots on the left and
// two glyphs on the right would otherwise push the time to the right. The
// strip is therefore clock + 2 x the wider side, and the lighter side is
// padded to the heavier one's width (`leftPad`, `rightPad`; one of them is 0).
//
// The padding is split in two, half at the outer edge and half between the
// group and the clock, so the lighter group stands in the middle of its half
// rather than pressed against the clock with all the air outside it (two
// glyphs right of the time, and the room to the right of them, was the
// complaint). `offset` is the row's shift inside the strip, the outer half of
// the left pad; the strip puts the inner halves beside the clock. Without a
// clock the row stands as measured.
function stripSymmetry(rowWidth, clockX, clockWidth) {
    const row = Math.max(0, Number(rowWidth) || 0)
    if (!(clockWidth > 0) || !(clockX >= 0) || clockX + clockWidth > row + 0.5)
        return { width: row, offset: 0, leftPad: 0, rightPad: 0 }
    const left = clockX
    const right = Math.max(0, row - clockX - clockWidth)
    const side = Math.max(left, right)
    const leftPad = side - left
    const rightPad = side - right
    return { width: 2 * side + clockWidth, offset: leftPad / 2, leftPad: leftPad, rightPad: rightPad }
}

// Corner sizes that fit a body of width x height: the ears at most half the
// height, the bottom radius at most half the width and the height left below
// the ears.
function fitCorners(width, height, ear, radius) {
    const e = Math.max(0, Math.min(ear, height / 2))
    const r = Math.max(0, Math.min(radius, width / 2, height - e))
    return { ear: e, radius: r }
}

// Outline of the notch: a body `width` x `height` hanging from the top edge,
// centred at `centre`, with concave "ears" where it meets the top edge and
// rounded bottom corners (like a MacBook notch). The path elements of
// shell/notch/Notch.qml bind to these values; the springs move every frame,
// so no SVG string is built and re-parsed for each one.
function geometry(centre, width, height, ear, radius) {
    const w = Math.max(0, width)
    const h = Math.max(0, height)
    const corners = fitCorners(w, h, ear, radius)
    return {
        ear: corners.ear,
        radius: corners.radius,
        left: centre - w / 2,
        right: centre + w / 2,
        bottom: h
    }
}

// A pill is a notch that let go of the top edge: the same thing, the same
// items, the same sizes, drawn detached and rounded all the way round. How far
// down it sits, and how round it is at that size.
function pillTop(shape, margin) {
    return shape === "pill" ? Math.max(0, Math.round(Number(margin) || 0)) : 0
}

// How much room the shape asks the windows to leave.
//
// Both shapes want the same `margin` between themselves and the window below.
// The compositor already puts `windowGap` between a window and whatever is
// reserved, so each reserves what it actually covers plus one margin, less
// that gap, and lets the window's own gap do the rest of the work.
//
// A notch used to reserve its bare height, so the compositor's whole gap of 12
// showed under it while the pill - which subtracted the gap - left 6. The user
// reported that twice. Reserving less than the shape covers is right, not a
// bug: the compositor adds the gap back, and it is the sum that the window
// actually starts at.
function reserveHeight(shape, height, margin, windowGap) {
    const h = Math.max(0, Math.round(Number(height) || 0))
    const m = Math.max(0, Math.round(Number(margin) || 0))
    const gap = Math.max(0, Math.round(Number(windowGap) || 0))
    return Math.max(0, pillTop(shape, m) + h + m - gap)
}

function pillRadius(height, collapsedRadius, expandedRadius, expanded) {
    const h = Math.max(0, Number(height) || 0)
    const wanted = expanded ? expandedRadius : Math.max(collapsedRadius, h / 2)
    return Math.max(0, Math.min(wanted, h / 2))
}

// ---- how the notch opens -----------------------------------------------------
// hover: resting the pointer on it opens the overview, a click opens the
//        dashboard (or the overview, with clickAction "expand")
// click: only a click opens the overview
// off:   the overview never opens; a click opens the dashboard
var HOVER_MODES = ["hover", "click", "off"]
var CLICK_ACTIONS = ["dashboard", "expand"]
var OPEN_DELAY = { min: 0, max: 1000, fallback: 150 }
var CLOSE_DELAY = { min: 0, max: 2000, fallback: 400 }

function hoverMode(value) {
    return HOVER_MODES.indexOf(value) >= 0 ? value : "hover"
}

function hoverOpens(mode) {
    return hoverMode(mode) === "hover"
}

// What a click on the *collapsed* notch does: "expand", "dashboard" or "".
function clickResult(mode, action) {
    const which = hoverMode(mode)
    if (which === "click") return "expand"
    if (which === "off") return "dashboard"
    return CLICK_ACTIONS.indexOf(action) >= 0 ? action : "dashboard"
}

// What the middle and the right button do on the collapsed notch; the left
// one is `clickResult` and stays exactly what it was. "none" by default: a
// click that does something new is a change nobody asked the notch for.
var BUTTON_ACTIONS = ["none", "dashboard", "controlCenter", "notifications", "launcher",
                      "clipboard", "mediaPopup", "playPause", "overview"]

function buttonAction(value) {
    return BUTTON_ACTIONS.indexOf(value) >= 0 ? value : "none"
}

// ---- swiping the collapsed notch --------------------------------------------
// A scroll or a two-finger swipe over the collapsed notch moves between its
// pages: the date on the left (-1), the strip (0), what is playing on the
// right (+1). Tide-island's numbers for a touchpad: a page is crossed past
// 56 % of the way, the gesture settles 150 ms after the last event, the
// larger axis wins and 240 px (times 0.8) is one page. A mouse wheel has no
// pixels, and Tide's quarter of its angle made a page seven notches; here a
// notch is 0.35 of a page, so two of them turn it.
//
// A page is not where the notch lives: `returnMs` after the pointer has left
// it, the notch goes back to the strip, as an island does. A short touchpad
// swipe on the way past the top edge turns a page, and it used to stay there
// until scrolled back - the time and the workspaces gone, the calendar kept
// awake for the date page.
var SWIPE = { threshold: 0.56, idleMs: 150, pagePixels: 240, notchPage: 0.35, returnMs: 8000 }

// One wheel event as a step along the pages: positive is to the right (and
// down, for a plain mouse wheel, which only has the one axis).
function swipeStep(pixelX, pixelY, angleX, angleY) {
    const px = Number(pixelX) || 0, py = Number(pixelY) || 0
    if (px || py) return (Math.abs(px) >= Math.abs(py) ? -px : -py) * 0.8 / SWIPE.pagePixels
    const ax = Number(angleX) || 0, ay = Number(angleY) || 0
    return (Math.abs(ax) >= Math.abs(ay) ? -ax : -ay) / 120 * SWIPE.notchPage
}

// Where a swipe lands: the next page past the threshold, if there is one,
// else back where it started.
function swipeSettle(page, position, pages) {
    const list = Array.isArray(pages) ? pages : [0]
    const target = position >= SWIPE.threshold ? page + 1 : position <= -SWIPE.threshold ? page - 1 : page
    return list.indexOf(target) >= 0 ? target : page
}

function delay(value, range) {
    const number = Number(value)
    if (!isFinite(number)) return range.fallback
    return Math.round(Math.max(range.min, Math.min(range.max, number)))
}

// The ranges a number the IPC sets is checked against, by its key: the same
// ones the notch clamps to when it reads them. One rule for all five - the
// open delay used to be accepted up to 2000 ms and stored, while the notch
// clamped it to 1000 and `notch get` said 1000, so a preset saved afterwards
// carried a number the notch never used.
function optionRange(key) {
    if (key === "openDelay") return OPEN_DELAY
    if (key === "closeDelay") return CLOSE_DELAY
    return Object.prototype.hasOwnProperty.call(BODY_RANGES, key) ? BODY_RANGES[key] : null
}

// The whole number to store for `key`, or null when the key takes no number
// or the value is not one inside its range: refused, not clamped.
function optionNumber(key, value) {
    const range = optionRange(key)
    if (range === null) return null
    const text = String(value === undefined || value === null ? "" : value).trim()
    const number = Number(text)
    if (!text.length || !isFinite(number) || number < range.min || number > range.max) return null
    return Math.round(number)
}

// ---- status glyphs in the accent ---------------------------------------------
// notch.accentGlyphs: the neutral status glyphs (network, Bluetooth, battery,
// volume, the bell) in the accent instead of the notch's white - nowhere, only
// in the hover overview, or on the collapsed strip as well. Only the neutral
// ink: a glyph that shows a state (charging, low, unread, a warning) keeps its
// own colour wherever this says, because that colour is the message.
var ACCENT_GLYPHS = ["off", "overview", "all"]

function accentGlyphs(value) {
    return ACCENT_GLYPHS.indexOf(value) >= 0 ? value : "off"
}

// Whether the glyphs in `where` ("overview" or "strip") take the accent.
function glyphsInAccent(setting, where) {
    const value = accentGlyphs(setting)
    if (where === "overview") return value === "overview" || value === "all"
    if (where === "strip") return value === "all"
    return false
}

// ---- the collapsed body ------------------------------------------------------
// How tall the collapsed shape is, how round its bottom corners are and how
// much air the strip keeps at both ends (notch.bodyHeight / bodyRadius /
// bodyPadding). The theme's tokens are the defaults (Island's 34 / 14 / 22); a
// preset carries all three, which is how Classic gets back the 32 / 11 / 16
// body the notch had before Island without the tokens changing. The height
// is also a slider (NotchHoverRows). `BODY_RANGES` names them by their
// setting, for the IPC, the slider and the preset files' checks.
var BODY_HEIGHT = { min: 24, max: 64 }
var BODY_RADIUS = { min: 0, max: 32 }
var BODY_PADDING = { min: 0, max: 48 }
var BODY_RANGES = { bodyHeight: BODY_HEIGHT, bodyRadius: BODY_RADIUS, bodyPadding: BODY_PADDING }

// Like `delay`, but the fallback is the caller's: the theme's token, which
// this file cannot see, so a value that is not a number leaves the body as
// the theme draws it.
function bodySize(value, range, fallback) {
    const number = Number(value)
    if (!isFinite(number)) return fallback
    return Math.round(Math.max(range.min, Math.min(range.max, number)))
}

// The radius the collapsed body is drawn with: the setting (already under the
// shell corner scale), never more than half the body's height. The height is
// a slider now and the radius a separate number, so a low body with large
// corners is a pair anyone can set; past half the height the bottom corners
// would run up into the ears. Clamped rather than scaled with the height: the
// corners stay the number chosen while the height moves, and only a body too
// low for them rounds off at its ends, as a pill's do. The stored radius is
// untouched, so a preset saved afterwards keeps it.
function collapsedRadius(radius, height) {
    const r = Math.max(0, Number(radius) || 0)
    const h = Math.max(0, Number(height) || 0)
    return Math.min(r, h / 2)
}

// What a release of a body slider stores for `key`: whole pixels inside the
// key's range, or null when that is the number stored already - a click on
// the knob that moved nothing is no change, and takes no undo step.
function bodyChange(key, value, stored) {
    const range = Object.prototype.hasOwnProperty.call(BODY_RANGES, key) ? BODY_RANGES[key] : null
    // Number(null) and Number("") are 0, which would clamp to the minimum.
    const size = v => v === null || v === undefined || v === "" ? null : bodySize(v, range, null)
    const number = range === null ? null : size(value)
    return number === null || number === size(stored) ? null : number
}

// settings.json from before hoverMode: expandOnHover false meant "a click
// opens it". The old key is dropped either way; SettingsService would drop it
// as unknown anyway, and this keeps what it meant.
function migrate(document) {
    if (!document || typeof document !== "object") return document
    const notch = document.notch
    if (!notch || typeof notch !== "object" || notch.expandOnHover === undefined) return document
    const next = {}
    for (const key of Object.keys(notch))
        if (key !== "expandOnHover") next[key] = notch[key]
    if (next.hoverMode === undefined) next.hoverMode = notch.expandOnHover === false ? "click" : "hover"
    const result = Object.assign({}, document)
    result.notch = next
    return result
}
