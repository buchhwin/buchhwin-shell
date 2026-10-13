.pragma library

// Pure helpers for the notch (desktop mode "notch", shell/notch): texts, the
// rows of the hover overview, status icons and the outline of the shape.

function pad2(value) {
    return (value < 10 ? "0" : "") + value
}

// 24-hour "HH:MM" like the clock widget.
function timeText(date) {
    return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
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

// Short time line for the event row.
function eventWhen(event, now) {
    if (!event) return ""
    if (event.allDay) return "All day"
    const start = event.start.getTime()
    const end = event.end instanceof Date ? event.end.getTime() : start
    const current = now.getTime()
    if (start <= current && end > current) return "Now · until " + timeText(event.end)
    const minutes = Math.ceil((start - current) / 60000)
    if (minutes >= 0 && minutes < 60) return minutes <= 1 ? "In 1 min" : "In " + minutes + " min"
    return end > start ? timeText(event.start) + " – " + timeText(event.end) : timeText(event.start)
}

// Rows of the expanded notch, top to bottom.
function rows(state) {
    const result = ["header"]
    if (state && state.event) result.push("event")
    if (state && state.media) result.push("media")
    result.push("status")
    return result
}

// Status icons of the overview: battery (with percent), network, Bluetooth,
// Do Not Disturb (only while on) and volume. `dim` marks something off.
function statusItems(state) {
    const items = []
    const s = state || {}
    if (s.battery && s.battery.present)
        items.push({ id: "battery", icon: s.battery.icon, text: Math.round(s.battery.percent) + "%", dim: false,
                     charging: s.battery.charging === true })
    if (s.network) items.push({ id: "network", icon: s.network.icon, text: "", dim: !s.network.connected })
    if (s.bluetooth && s.bluetooth.available)
        items.push({ id: "bluetooth", icon: s.bluetooth.icon, text: "", dim: !s.bluetooth.connected })
    if (s.dnd) items.push({ id: "dnd", icon: "󰂛", text: "", dim: false })
    if (s.volume) items.push({ id: "volume", icon: s.volume.icon, text: "", dim: s.volume.muted === true })
    return items
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
function stripItems(items, recording) {
    const list = Array.isArray(items) ? items.slice() : []
    if (recording && !list.some(item => item && item.type === "recording"))
        return [{ id: "", type: "recording" }].concat(list)
    return list
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

// Interpolated shape between collapsed (0) and expanded (1) sizes.
function mix(from, to, progress) {
    return from + (to - from) * progress
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

function delay(value, range) {
    const number = Number(value)
    if (!isFinite(number)) return range.fallback
    return Math.round(Math.max(range.min, Math.min(range.max, number)))
}

// ---- the collapsed body ------------------------------------------------------
// How tall the collapsed shape is, how round its bottom corners are and how
// much air the strip keeps at both ends (notch.bodyHeight / bodyRadius /
// bodyPadding). The theme's tokens are the defaults; a preset carries all
// three, which is how Classic gets back the 32 / 11 / 16 body the notch had
// before Island without the tokens changing. `BODY_RANGES` names them by their
// setting, for the IPC and the preset files' checks.
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
