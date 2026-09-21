.pragma library
.import "bar/BarLogic.js" as BarLogic
.import "quick/QuickLogic.js" as QuickLogic
.import "dashboard/DashboardLogic.js" as DashboardLogic
.import "arrange/FitLogic.js" as Fit
.import "lock/LockCatalogue.js" as LockCatalogue

// Pure layout operations shared by LayoutService and the unit tests.
var ANCHORS = ["left", "center", "right"]
var STYLES = ["minimal", "capsule", "card"]
var SIZES = ["small", "medium", "large"]
// How much larger a tile gets per size step. A bar item and a desktop widget
// use the same ladder, so "large" means the same thing wherever it appears.
var SIZE_SCALE = { small: 1, medium: 1.15, large: 1.3 }

function sizeScale(size) {
    return SIZE_SCALE[size] || 1
}
var SCALE_MIN = 0.7
var SCALE_MAX = 2.0
// Desktop modes, exactly one at a time: floating widgets, the top bar (pill
// or bar style) or a notch at the top centre (time only, a small overview on
// hover).
var MODES = ["widgets", "pills", "notch"]
// Mode names of older layouts. "both" showed widgets and the bar together;
// it becomes the bar and keeps every widget and pill in the profile.
var LEGACY_MODES = { both: "pills" }
var MODE_LABELS = { widgets: "Widgets", pills: "Bar", notch: "Notch" }
var ZONES = ["left", "center", "right"]
// Pill item looks: full, icon (compact) and expanded (only some widgets
// draw more, e.g. media with artist and controls; others treat it as full).
var DISPLAYS = ["full", "icon", "expanded"]
// A grid cell is at most this many columns and rows. The bounds are here and
// not at the surface so a layout file can never ask for a tile taller than the
// screen it is drawn on.
var GRID_MAX_W = 4
var GRID_MAX_H = 6
var FULLSCREEN = ["hide", "show"]

// A stored mode name as one of MODES: legacy names migrate, unknown ones
// become "widgets".
function modeName(mode) {
    const migrated = LEGACY_MODES[mode] || mode
    return MODES.indexOf(migrated) >= 0 ? migrated : "widgets"
}

// Which desktop surface a mode shows; exactly one of the three is true.
function modeShows(mode) {
    const name = modeName(mode)
    return { widgets: name === "widgets", bar: name === "pills", notch: name === "notch" }
}

function modeLabel(mode) {
    return MODE_LABELS[modeName(mode)]
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

function num(value, fallback) {
    const result = Number(value)
    return isFinite(result) ? result : fallback
}

function oneOf(value, choices, fallback) {
    return choices.indexOf(value) >= 0 ? value : fallback
}

function sanitizeOptions(options) {
    const result = {}
    if (!options || typeof options !== "object") return result
    for (const key of Object.keys(options)) {
        const value = options[key]
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean")
            result[String(key)] = value
    }
    return result
}

function sanitizeWidget(widget) {
    return {
        id: String(widget.id),
        type: String(widget.type),
        screen: String(widget.screen),
        anchorX: oneOf(widget.anchorX, ANCHORS, "right"),
        x: clamp(num(widget.x, 0.5), 0, 1),
        y: clamp(num(widget.y, 0.05), 0, 1),
        scale: clamp(num(widget.scale, 1), SCALE_MIN, SCALE_MAX),
        size: oneOf(widget.size, SIZES, "small"),
        style: oneOf(widget.style, STYLES, "minimal"),
        visible: widget.visible === undefined ? true : Boolean(widget.visible),
        group: typeof widget.group === "string" ? widget.group : "",
        options: sanitizeOptions(widget.options)
    }
}

function sanitizeGroup(group) {
    return {
        id: String(group.id),
        screen: String(group.screen),
        anchorX: oneOf(group.anchorX, ANCHORS, "right"),
        x: clamp(num(group.x, 0.5), 0, 1),
        y: clamp(num(group.y, 0.05), 0, 1),
        scale: clamp(num(group.scale, 1), SCALE_MIN, SCALE_MAX),
        style: oneOf(group.style, STYLES, "minimal"),
        visible: group.visible === undefined ? true : Boolean(group.visible),
        members: Array.isArray(group.members) ? group.members.map(String) : []
    }
}

// Rebuild a v2 layout from whitelisted primitive fields only.
function sanitize(config) {
    // The notch and the lock screen sit outside `profiles` because they are
    // the same on every one.
    // A file without it simply gets the default, the way a profile without a
    // `quick` does, so no version bump and no migration step is needed.
    const result = { configVersion: 2, activeProfile: "minimal", profiles: {}, notch: defaultNotch(),
                     lock: defaultLock(), adopted: [] }
    if (!config || typeof config !== "object") return result
    if (Array.isArray(config.adopted))
        result.adopted = config.adopted.filter(name => typeof name === "string" && name.length).map(String)
    if (config.notch) result.notch = sanitizeNotch(config.notch)
    if (config.lock) result.lock = sanitizeLock(config.lock)
    if (typeof config.activeProfile === "string") result.activeProfile = config.activeProfile
    const profiles = config.profiles && typeof config.profiles === "object" ? config.profiles : {}
    for (const name of Object.keys(profiles)) {
        const profile = profiles[name] || {}
        const widgets = (Array.isArray(profile.widgets) ? profile.widgets : [])
            .filter(widget => widget && widget.id !== undefined && widget.type !== undefined && widget.screen !== undefined)
            .map(sanitizeWidget)
        const ids = widgets.map(widget => widget.id)
        const groups = (Array.isArray(profile.groups) ? profile.groups : [])
            .filter(group => group && group.id !== undefined && group.screen !== undefined)
            .map(sanitizeGroup)
            .map(group => Object.assign(group, { members: group.members.filter(id => ids.indexOf(id) >= 0) }))
            .filter(group => group.members.length > 0)
        const groupIds = groups.map(group => group.id)
        for (const widget of widgets)
            if (widget.group.length && groupIds.indexOf(widget.group) < 0) widget.group = ""
        result.profiles[String(name)] = {
            widgets: widgets,
            groups: groups,
            screens: (Array.isArray(profile.screens) ? profile.screens : []).map(String),
            mode: modeName(profile.mode),
            bar: sanitizeBar(profile.bar),
            quick: sanitizeQuick(profile.quick),
            dashboard: sanitizeDashboard(profile.dashboard)
        }
    }
    return result
}

// One-shot migrations that have already run on this file. The marker belongs
// in the same file as the data it guards: the quick tiles' one lived in
// settings.json while the sizes lived here, so restoring one file without the
// other silently reset every size the user had set by hand.
function hasAdopted(config, name) {
    return !!(config && Array.isArray(config.adopted) && config.adopted.indexOf(name) >= 0)
}

function withAdopted(config, name) {
    const list = config && Array.isArray(config.adopted) ? config.adopted.slice() : []
    if (list.indexOf(name) < 0) list.push(name)
    return list
}

function uniqueId(prefix, taken) {
    if (taken.indexOf(prefix) < 0) return prefix
    let index = 2
    while (taken.indexOf(prefix + "-" + index) >= 0) index += 1
    return prefix + "-" + index
}

// Create screen-specific widgets from a profile template.
function materialize(template, screen, existingIds, isKnownType) {
    const taken = existingIds.slice()
    const widgets = []
    const groups = []
    const idMap = {}
    for (const entry of (template && Array.isArray(template.widgets) ? template.widgets : [])) {
        if (entry.screen !== undefined && entry.screen !== "*" && entry.screen !== screen) continue
        if (isKnownType && !isKnownType(entry.type)) continue
        const id = uniqueId(entry.type + "-" + screen, taken)
        taken.push(id)
        if (entry.key) idMap[entry.key] = id
        widgets.push(sanitizeWidget(Object.assign({}, entry, { id: id, screen: screen, group: "" })))
    }
    for (const entry of (template && Array.isArray(template.groups) ? template.groups : [])) {
        const members = (entry.members || []).map(key => idMap[key]).filter(Boolean)
        if (!members.length) continue
        const id = uniqueId("group-" + screen, taken)
        taken.push(id)
        groups.push(sanitizeGroup(Object.assign({}, entry, { id: id, screen: screen, members: members })))
        for (const widget of widgets)
            if (members.indexOf(widget.id) >= 0) widget.group = id
    }
    return { widgets: widgets, groups: groups }
}

// Top-level placements (ungrouped widgets and groups) for one screen.
function placements(profile, screen, includeHidden) {
    if (!profile) return []
    const result = []
    for (const widget of profile.widgets)
        if (widget.screen === screen && !widget.group.length && (includeHidden || widget.visible))
            result.push(widget.id)
    for (const group of profile.groups)
        if (group.screen === screen && (includeHidden || group.visible))
            result.push(group.id)
    return result
}

// Screen position (top-left, logical pixels) of a placement.
function pixelPosition(item, width, height, screenWidth, screenHeight) {
    const anchorX = item.x * screenWidth
    let left = item.anchorX === "right" ? anchorX - width : item.anchorX === "center" ? anchorX - width / 2 : anchorX
    left = clamp(left, 0, Math.max(0, screenWidth - width))
    const top = clamp(item.y * screenHeight, 0, Math.max(0, screenHeight - height))
    return { x: left, y: top }
}

// Relative position for a top-left pixel position; the anchor follows the
// screen third that contains the item's centre.
function relativePosition(left, top, width, height, screenWidth, screenHeight) {
    const centre = left + width / 2
    const anchorX = centre < screenWidth / 3 ? "left" : centre > screenWidth * 2 / 3 ? "right" : "center"
    const x = anchorX === "left" ? left : anchorX === "right" ? left + width : centre
    return {
        anchorX: anchorX,
        x: clamp(x / Math.max(1, screenWidth), 0, 1),
        y: clamp(top / Math.max(1, screenHeight), 0, 1)
    }
}

// ---- pill bar --------------------------------------------------------------
// bar: { reserve, fullscreen, scale, style, position, left: [pill], center: [pill], right: [pill] }
// style "pills" (capsules) or "bar" (one continuous bar, position "floating"
// or "attached"); a missing style is "pills".
// pill: { id, items: [{ type, display, options }] }

function defaultBar() {
    return {
        reserve: true,
        fullscreen: "hide",
        scale: 1,
        style: "pills",
        position: "floating",
        edge: "top",
        panelSpot: "widget",
        notificationSpot: "widget",
        left: [{ id: "pill-1", items: [{ type: "nowPlaying", display: "icon", options: {} }] }],
        center: [{ id: "pill-2", items: [{ type: "clock", display: "full", options: {} }] }],
        right: [{ id: "pill-3", items: [{ type: "network", display: "icon", options: {} }] }]
    }
}

function sanitizeBarItem(item) {
    return {
        type: String(item.type),
        display: oneOf(item.display, DISPLAYS, "full"),
        // Each item carries its own size, so one tile can be bigger than its
        // neighbours instead of the whole bar having to grow.
        size: oneOf(item.size, SIZES, "small"),
        // How much of a grid it takes, in columns and rows - the notch overview
        // today, the dashboard next. A surface laid out along one line, like
        // the bar, ignores both.
        w: clamp(Math.round(num(item.w, 1)), 1, GRID_MAX_W),
        h: clamp(Math.round(num(item.h, 1)), 1, GRID_MAX_H),
        options: sanitizeOptions(item.options)
    }
}

// The zone -> pill -> item model, for any surface that uses it. The bar is the
// first; the notch, the quick panel and the dashboard are meant to follow, and
// keeping the shape in one function is what makes that possible.
function sanitizeZones(config, zoneNames) {
    const zones = Array.isArray(zoneNames) && zoneNames.length ? zoneNames : ZONES
    const result = {}
    const taken = []
    for (const zone of zones) {
        result[zone] = (Array.isArray(config && config[zone]) ? config[zone] : [])
            .filter(pill => pill && Array.isArray(pill.items))
            .map(pill => {
                const items = pill.items.filter(item => item && typeof item.type === "string" && item.type.length)
                    .map(sanitizeBarItem)
                let id = typeof pill.id === "string" && pill.id.length ? pill.id : "pill"
                if (taken.indexOf(id) >= 0) id = uniqueId("pill", taken)
                taken.push(id)
                return { id: id, items: items }
            })
            .filter(pill => pill.items.length > 0)
    }
    return result
}

// ---- the notch --------------------------------------------------------
// Two zones on the same zone -> pill -> item shape as the bar: the strip that
// is always on screen, and the overview it opens into on hover. They live at
// the top level of the layout file rather than inside a profile, because the
// notch is deliberately the same on every profile.
//
// They cannot live in settings.json, where the rest of the notch's options
// are: SettingsService rebuilds every stored object with Object.keys, which
// turns an array into { "0": ..., "1": ... } on the first write of any
// setting. The two existing list-shaped settings are comma-strings for that
// reason, and a comma-string cannot carry a display or a size.
const NOTCH_ZONES = ["collapsed", "expanded"]
const NOTCH_COLLAPSED_DEFAULT = ["clock"]
const NOTCH_EXPANDED_DEFAULT = ["clock", "weather", "media", "events", "status"]

// The size a type starts at in the overview's four-column grid. It reproduces
// what the notch looked like before it could be sized at all: the media and
// the events beside each other, the status chips across the bottom. Anything
// else - a widget - is a small readout and starts at one cell.
const NOTCH_SIZES = { clock: { w: 2, h: 2 }, weather: { w: 2, h: 2 },
                      media: { w: 2, h: 2, minW: 2, minH: 2 }, events: { w: 2, h: 2, minH: 2 },
                      status: { w: 4, h: 1 } }

// A widget starts two rows tall rather than one. One row is the smallest cell
// the grid has, and a widget that lands on it has room for a glyph and nothing
// else - which is what every widget dropped on the notch used to get, because
// the fallback here was the smallest cell there is.
function notchSize(type) {
    return NOTCH_SIZES[String(type)] || { w: 1, h: 2 }
}

// The smallest cell an item may be pulled to in the overview.
function notchMinSize(type) {
    return Fit.minSize(NOTCH_SIZES[String(type)])
}

// `taken` carries the ids the other zone already used: ids are unique across
// both zones, and the two lists can hold the same type - a clock in the strip
// and the big one in the overview - so numbering each list on its own handed
// out the same id twice and sanitizeZones quietly renamed one of them.
function notchList(types, taken) {
    const used = Array.isArray(taken) ? taken : []
    return types.map((type, index) => {
        const id = uniqueId("notch-" + type + "-" + (index + 1), used)
        used.push(id)
        const size = notchSize(type)
        // The same key order sanitizeBarItem produces, so a default notch and
        // a sanitized one are the same text in the layout file.
        return {
            id: id,
            items: [{ type: type, display: "full", size: "small", w: size.w, h: size.h, options: {} }]
        }
    })
}

function defaultNotch() {
    const taken = []
    return { collapsed: notchList(NOTCH_COLLAPSED_DEFAULT, taken),
             expanded: notchList(NOTCH_EXPANDED_DEFAULT, taken) }
}

function sanitizeNotch(notch) {
    if (!notch || typeof notch !== "object") return defaultNotch()
    const zones = sanitizeZones(notch, NOTCH_ZONES)
    // One item per pill here too: the notch shows a row of things, not a row
    // of groups of things.
    const shape = {}
    for (const zone of NOTCH_ZONES)
        shape[zone] = zones[zone].map(pill => ({ id: pill.id, items: [pill.items[0]] }))
    // An empty overview is a notch that does nothing on hover, which is a
    // choice; an empty strip is a notch that is not there, which is not.
    if (!shape.collapsed.length) shape.collapsed = notchList(NOTCH_COLLAPSED_DEFAULT)
    return shape
}

function notchTypes(notch, zone) {
    return notchItems(notch, zone).map(item => item.type)
}

// The zone as the editor needs it: the stored id beside the type, because the
// notch shows types and the layout file moves ids.
function notchItems(notch, zone) {
    const list = notch && Array.isArray(notch[zone]) ? notch[zone] : []
    return list.map(pill => ({ id: pill.id, type: pill.items[0].type,
                               w: pill.items[0].w, h: pill.items[0].h }))
}

function copyNotch(notch) {
    return sanitizeNotch(JSON.parse(JSON.stringify(notch)))
}

function findNotch(notch, zone, id) {
    return notch[zone].findIndex(pill => pill.id === id)
}

function notchZoneOf(notch, id) {
    for (const zone of NOTCH_ZONES) {
        const index = findNotch(notch, zone, id)
        if (index >= 0) return { zone: zone, index: index }
    }
    return null
}

// Move an item inside its zone or into the other one.
function moveNotchItemTo(notch, id, zone, index) {
    const next = copyNotch(notch)
    if (NOTCH_ZONES.indexOf(zone) < 0) return next
    const place = notchZoneOf(next, id)
    if (!place) return next
    const moved = next[place.zone].splice(place.index, 1)[0]
    next[zone].splice(Math.max(0, Math.min(next[zone].length, index)), 0, moved)
    return sanitizeNotch(next)
}

function removeNotchItem(notch, id) {
    const next = copyNotch(notch)
    const place = notchZoneOf(next, id)
    if (place) next[place.zone].splice(place.index, 1)
    return sanitizeNotch(next)
}

// Added to the overview, which is where there is room for it. A type already
// on the notch is not added twice: two clocks are a mistake, not a layout.
function addNotchItem(notch, type, zone) {
    const next = copyNotch(notch)
    const name = String(type || "")
    if (!name.length) return next
    for (const each of NOTCH_ZONES)
        if (notchTypes(next, each).indexOf(name) >= 0) return next
    const target = NOTCH_ZONES.indexOf(zone) >= 0 ? zone : "expanded"
    const taken = []
    for (const each of NOTCH_ZONES) for (const pill of next[each]) taken.push(pill.id)
    const size = notchSize(name)
    next[target].push({ id: uniqueId("notch", taken),
                        items: [{ type: name, display: "full", size: "small",
                                  w: size.w, h: size.h, options: {} }] })
    return sanitizeNotch(next)
}

// How big an item sits, in grid steps. There is no ladder of three names: a
// corner is dragged and the size is whatever it lands on, bounded by the grid
// itself rather than by a vocabulary.
function setNotchItemSize(notch, id, w, h) {
    const next = copyNotch(notch)
    const place = notchZoneOf(next, id)
    if (!place) return next
    const item = next[place.zone][place.index].items[0]
    const least = notchMinSize(item.type)
    item.w = clamp(Math.round(num(w, item.w)), least.w, GRID_MAX_W)
    item.h = clamp(Math.round(num(h, item.h)), least.h, GRID_MAX_H)
    return sanitizeNotch(next)
}

function resetNotch() {
    return defaultNotch()
}

// The big time and the long date used to be a header the overview always drew,
// above whatever the list said. They are an item now, so a notch stored before
// that gets one - once, at the front, where the header was.
function adoptNotchHeader(notch) {
    const next = copyNotch(notch)
    if (notchTypes(next, "expanded").indexOf("clock") >= 0) return next
    // The strip may already carry a clock of its own; ids are unique across
    // both zones, so the new one is numbered against everything that is there.
    const taken = []
    for (const zone of NOTCH_ZONES) for (const pill of next[zone]) taken.push(pill.id)
    next.expanded = notchList(["clock"], taken).concat(next.expanded)
    return sanitizeNotch(next)
}

// ---- a surface of tiles in one zone ---------------------------------------
// The control center's tiles and the dashboard's cards are the same thing with
// a different catalogue: one zone, one tile per pill, each carrying its own
// grid size, on the same zone -> pill -> item shape as the bar. A flat list
// would have been shorter, but the shape is what lets the surfaces share
// sanitizeZones, their ids and their move/remove/add operations.
//
// Everything below takes a `kind`, which names the zone, the id prefix, what
// the surface starts with and where a type's starting size comes from. Two
// surfaces, one set of operations: the notch and the bar each grew their own
// copy before this existed, and a third would have been the third bug.
// A tile that is not in the list is simply not shown; the picker adds it back.
const QUICK = {
    zone: "quick",
    defaults: ["wifi", "bluetooth", "dnd", "microphone", "fingerprint", "brightness",
               "battery", "media", "audio", "drives", "phone", "shortcuts"],
    sizeOf: QuickLogic.size,
    leastOf: QuickLogic.minSize,
    knows: QuickLogic.isKnown
}
const DASHBOARD = {
    zone: "dashboard",
    defaults: ["clock", "weather", "calendar", "agenda", "events"],
    sizeOf: DashboardLogic.size,
    leastOf: DashboardLogic.minSize,
    knows: DashboardLogic.isKnown
}
// The lock screen's own surface. It sits outside `profiles` for the same
// reason the notch does: there is one lock screen, whatever the desktop
// profile says about monitors. Its login block is not in here - avatar, name
// and password field stay where they are, because the animation that carries
// them to the centre while you type is an anchor margin, and an arranged cell
// is an x and a y. Mixing the two is a whole afternoon.
const LOCK = {
    zone: "lock",
    defaults: ["clock", "date", "media"],
    sizeOf: LockCatalogue.size,
    leastOf: LockCatalogue.minSize,
    knows: LockCatalogue.isKnown
}

function tilePill(kind, type, id) {
    // A type the catalogue knows brings its own start size; anything else is a
    // widget the surface accepts, and the catalogue's fallback is what that
    // surface thinks a one-line readout is worth.
    const size = kind.sizeOf(type)
    return { id: id, items: [{ type: type, display: "full", size: "small",
                               w: size.w, h: size.h, options: {} }] }
}

function defaultTiles(kind) {
    return { [kind.zone]: kind.defaults.map((type, index) => tilePill(kind, type, kind.zone + "-" + (index + 1))) }
}

function sanitizeTiles(kind, surface) {
    if (!surface || typeof surface !== "object") return defaultTiles(kind)
    const zones = sanitizeZones(surface, [kind.zone])
    // One tile per pill: anything the file smuggled in beyond the first is
    // dropped rather than silently shown twice.
    const tiles = zones[kind.zone].map(pill => ({ id: pill.id, items: [pill.items[0]] }))
    return tiles.length ? { [kind.zone]: tiles } : defaultTiles(kind)
}

function tileList(kind, surface) {
    return surface && Array.isArray(surface[kind.zone]) ? surface[kind.zone] : []
}

// The tiles as the surface places them: the stored id, type and grid size.
function tileItems(kind, surface) {
    return tileList(kind, surface).map(pill => ({
        id: pill.id, type: pill.items[0].type, w: pill.items[0].w, h: pill.items[0].h
    }))
}

function tileTypes(kind, surface) {
    return tileList(kind, surface).map(pill => pill.items[0].type)
}

function copyTiles(kind, surface) {
    return sanitizeTiles(kind, JSON.parse(JSON.stringify(surface)))
}

function findTile(kind, surface, id) {
    return surface[kind.zone].findIndex(pill => pill.id === id)
}

// How big one tile sits. Same two axes as a notch item, same bounds - and the
// same floor, which is the catalogue's when it names one. Below its minimum a
// tile is not a smaller version of itself, so the grid refuses rather than
// handing back something that only clips.
function setTileSize(kind, surface, id, w, h) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    if (index < 0) return next
    const item = next[kind.zone][index].items[0]
    const least = tileMinSize(kind, item.type)
    item.w = clamp(Math.round(num(w, item.w)), least.w, GRID_MAX_W)
    item.h = clamp(Math.round(num(h, item.h)), least.h, GRID_MAX_H)
    return sanitizeTiles(kind, next)
}

function tileMinSize(kind, type) {
    return kind.leastOf ? kind.leastOf(type) : { w: 1, h: 1 }
}

function moveTile(kind, surface, id, delta) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    const target = index + delta
    if (index < 0 || target < 0 || target >= next[kind.zone].length) return next
    const moved = next[kind.zone].splice(index, 1)[0]
    next[kind.zone].splice(target, 0, moved)
    return next
}

function moveTileTo(kind, surface, id, index) {
    const next = copyTiles(kind, surface)
    const from = findTile(kind, next, id)
    if (from < 0) return next
    const moved = next[kind.zone].splice(from, 1)[0]
    next[kind.zone].splice(Math.max(0, Math.min(next[kind.zone].length, index)), 0, moved)
    return next
}

function removeTile(kind, surface, id) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    if (index >= 0) next[kind.zone].splice(index, 1)
    return next
}

// A type neither the catalogue nor the caller knows is refused rather than
// given a cell. The pickers only ever offer known types, so this guards the
// file and the IPC: an unknown type used to take a place on the surface and
// draw nothing, because the switch that turns a type into content has no case
// for it.
//
// `alsoKnown` is how a surface accepts desktop widgets beside its own tiles.
// It is a callback rather than another table because the widget registry is a
// QML singleton and this file is a plain library - the same reason
// `materialize` takes one.
function addTile(kind, surface, type, alsoKnown) {
    const next = copyTiles(kind, surface)
    if (!type || tileTypes(kind, next).indexOf(type) >= 0) return next
    const known = (kind.knows && kind.knows(String(type)))
        || (alsoKnown && alsoKnown(String(type)) === true)
    if (!known) return next
    const taken = next[kind.zone].map(pill => pill.id)
    const id = uniqueId(kind.zone + "-" + (next[kind.zone].length + 1), taken)
    next[kind.zone].push(tilePill(kind, String(type), id))
    return next
}

// Every tile back to the size its type starts at. The control center's tiles
// were laid out by their content until it became a grid, and a file written in
// between carries the smallest cell there is for each of them - which is not
// what anybody chose, it is what a missing field defaults to. Run once,
// guarded by a marker in this same file.
function adoptTileSizes(kind, surface) {
    const next = copyTiles(kind, surface)
    for (const pill of next[kind.zone]) {
        const size = kind.sizeOf(pill.items[0].type)
        pill.items[0].w = size.w
        pill.items[0].h = size.h
    }
    return sanitizeTiles(kind, next)
}

// ---- the two surfaces, by name --------------------------------------------
// Thin wrappers so a call site reads as what it is working on rather than as
// a descriptor plus a generic verb.

function defaultQuick() { return defaultTiles(QUICK) }
function sanitizeQuick(quick) { return sanitizeTiles(QUICK, quick) }
function quickItems(quick) { return tileItems(QUICK, quick) }
function quickTypes(quick) { return tileTypes(QUICK, quick) }
function setQuickTileSize(quick, id, w, h) { return setTileSize(QUICK, quick, id, w, h) }
function moveQuickTile(quick, id, delta) { return moveTile(QUICK, quick, id, delta) }
function moveQuickTileTo(quick, id, index) { return moveTileTo(QUICK, quick, id, index) }
function removeQuickTile(quick, id) { return removeTile(QUICK, quick, id) }
function addQuickTile(quick, type, alsoKnown) { return addTile(QUICK, quick, type, alsoKnown) }
function adoptQuickSizes(quick) { return adoptTileSizes(QUICK, quick) }
function quickMinSize(type) { return tileMinSize(QUICK, type) }

function defaultDashboard() { return defaultTiles(DASHBOARD) }
function sanitizeDashboard(dashboard) { return sanitizeTiles(DASHBOARD, dashboard) }
function dashboardItems(dashboard) { return tileItems(DASHBOARD, dashboard) }
function dashboardTypes(dashboard) { return tileTypes(DASHBOARD, dashboard) }
function setDashboardCardSize(dashboard, id, w, h) { return setTileSize(DASHBOARD, dashboard, id, w, h) }
function moveDashboardCardTo(dashboard, id, index) { return moveTileTo(DASHBOARD, dashboard, id, index) }
function removeDashboardCard(dashboard, id) { return removeTile(DASHBOARD, dashboard, id) }
function addDashboardCard(dashboard, type, alsoKnown) { return addTile(DASHBOARD, dashboard, type, alsoKnown) }
function dashboardMinSize(type) { return tileMinSize(DASHBOARD, type) }

function defaultLock() { return defaultTiles(LOCK) }
function sanitizeLock(lock) { return sanitizeTiles(LOCK, lock) }
function lockItems(lock) { return tileItems(LOCK, lock) }
function lockTypes(lock) { return tileTypes(LOCK, lock) }
function setLockItemSize(lock, id, w, h) { return setTileSize(LOCK, lock, id, w, h) }
function moveLockItemTo(lock, id, index) { return moveTileTo(LOCK, lock, id, index) }
function removeLockItem(lock, id) { return removeTile(LOCK, lock, id) }
function addLockItem(lock, type) { return addTile(LOCK, lock, type) }
function lockMinSize(type) { return tileMinSize(LOCK, type) }

function sanitizeBar(bar) {
    if (!bar || typeof bar !== "object") return defaultBar()
    const result = {
        reserve: bar.reserve === undefined ? true : Boolean(bar.reserve),
        fullscreen: oneOf(bar.fullscreen, FULLSCREEN, "hide"),
        scale: clamp(num(bar.scale, 1), SCALE_MIN, 1.5),
        style: BarLogic.style(bar.style),
        position: BarLogic.position(bar.position),
        // Sanitizing is total, so a file written before there was an edge
        // simply gets "top" when it is read. No version bump, no migration.
        edge: BarLogic.edge(bar.edge),
        // Where a panel and where a notification open along the bar. Both
        // default to "widget", which is the behaviour every bar had before
        // there was a choice, so a file written without them reads as one that
        // asked for what it already had.
        panelSpot: BarLogic.spot(bar.panelSpot),
        notificationSpot: BarLogic.spot(bar.notificationSpot)
    }
    const zones = sanitizeZones(bar, ZONES)
    for (const zone of ZONES) result[zone] = zones[zone]
    return result
}

function barPillIds(bar) {
    return ZONES.reduce((ids, zone) => ids.concat(bar[zone].map(pill => pill.id)), [])
}

// { zone, index } of a pill, or null.
function findPill(bar, pillId) {
    for (const zone of ZONES) {
        const index = bar[zone].findIndex(pill => pill.id === pillId)
        if (index >= 0) return { zone: zone, index: index }
    }
    return null
}

function copyBar(bar) {
    return sanitizeBar(JSON.parse(JSON.stringify(bar)))
}

// All operations return a new, sanitized bar and never mutate the input.
function addPill(bar, zone, type, display) {
    const next = copyBar(bar)
    if (ZONES.indexOf(zone) < 0 || !type) return next
    const id = uniqueId("pill-" + (barPillIds(next).length + 1), barPillIds(next))
    next[zone].push({ id: id, items: [{ type: String(type), display: oneOf(display, DISPLAYS, "full"), options: {} }] })
    return sanitizeBar(next)
}

function addItem(bar, pillId, type, display) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !type) return next
    next[place.zone][place.index].items.push({ type: String(type), display: oneOf(display, DISPLAYS, "full"), options: {} })
    return sanitizeBar(next)
}

function removeItem(bar, pillId, itemIndex) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    next[place.zone][place.index].items.splice(itemIndex, 1)
    return sanitizeBar(next)
}

function moveItem(bar, pillId, itemIndex, delta) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    const items = next[place.zone][place.index].items
    const target = itemIndex + delta
    if (itemIndex < 0 || itemIndex >= items.length || target < 0 || target >= items.length) return next
    const moved = items.splice(itemIndex, 1)[0]
    items.splice(target, 0, moved)
    return next
}

function setItemDisplay(bar, pillId, itemIndex, display) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !next[place.zone][place.index].items[itemIndex]) return next
    next[place.zone][place.index].items[itemIndex].display = oneOf(display, DISPLAYS, "full")
    return next
}

function setItemSize(bar, pillId, itemIndex, size) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !next[place.zone][place.index].items[itemIndex]) return next
    next[place.zone][place.index].items[itemIndex].size = oneOf(size, SIZES, "small")
    return next
}

// Move a pill within its zone (delta) and across zone borders: moving past
// the end of a zone places it at the start of the next zone and vice versa.
function movePill(bar, pillId, delta) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !delta) return next
    const list = next[place.zone]
    const target = place.index + delta
    if (target >= 0 && target < list.length) {
        const moved = list.splice(place.index, 1)[0]
        list.splice(target, 0, moved)
        return next
    }
    const zoneIndex = ZONES.indexOf(place.zone) + (delta > 0 ? 1 : -1)
    if (zoneIndex < 0 || zoneIndex >= ZONES.length) return next
    const moved = list.splice(place.index, 1)[0]
    if (delta > 0) next[ZONES[zoneIndex]].unshift(moved)
    else next[ZONES[zoneIndex]].push(moved)
    return next
}

// Move a pill to an exact place (editor drag and drop): `index` counts the
// target zone without the pill itself and is clamped to its ends.
function movePillTo(bar, pillId, zone, index) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || ZONES.indexOf(zone) < 0) return next
    const moved = next[place.zone].splice(place.index, 1)[0]
    const list = next[zone]
    list.splice(clamp(Math.round(num(index, list.length)), 0, list.length), 0, moved)
    return next
}

// Split one item out into its own pill right after the original pill.
function splitItem(bar, pillId, itemIndex) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    const pill = next[place.zone][place.index]
    if (pill.items.length < 2 || !pill.items[itemIndex]) return next
    const item = pill.items.splice(itemIndex, 1)[0]
    const id = uniqueId("pill-" + (barPillIds(next).length + 1), barPillIds(next))
    next[place.zone].splice(place.index + 1, 0, { id: id, items: [item] })
    return next
}

// Merge a pill into the following pill of the same zone.
function mergeWithNext(bar, pillId) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || place.index + 1 >= next[place.zone].length) return next
    const list = next[place.zone]
    list[place.index].items = list[place.index].items.concat(list[place.index + 1].items)
    list.splice(place.index + 1, 1)
    return next
}

function removePill(bar, pillId) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (place) next[place.zone].splice(place.index, 1)
    return next
}
