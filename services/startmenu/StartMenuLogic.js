.pragma library
.import "../dock/DockLogic.js" as Dock
.import "../system/UserDirsLogic.js" as UserDirs

// The start menu (shell/startmenu/StartMenu.qml), opened by the dock's start
// button: the fastfetch Saturn over it, a search, the pinned apps, the ones
// used most, every app from A to Z, the places and the way out of the
// session. Everything here is arithmetic on plain values, so the tests can
// ask it everything the panel decides. Unit tested (StartMenuTest).

// ---- the ASCII logo ----------------------------------------------------------
// A fastfetch logo file: `$1` … `$9` switch the colour (fastfetch's
// `logo.color` keys), `$$` is a dollar sign, and every line starts in the
// first colour again, as fastfetch draws it. The runs of characters that are
// not spaces, each at its column - drawn one by one, so no space has to be
// laid out and every run stays at its column whatever the font does between
// them (the README banner is made the same way). `columns` is where the last
// run ends.
//
// The logo may be the user's own (textLogo below), so it is kept to
// LOGO_LIMIT - a long file would be thousands of Texts, built with every
// open - and terminal colour codes (a raw logo's) are dropped: its two
// colours are the planet's and the ring's. Not text at all (an image named
// by its path): no logo.
var LOGO_LIMIT = { rows: 30, columns: 80 }
// The room the header has for it: the shipped Saturn's 55 x 15 cells. A
// larger logo is drawn smaller to fit (SaturnAscii), a smaller one as it is.
var LOGO_BOX = { rows: 15, columns: 55 }

function looksLikeText(text) {
    const value = String(text || "")
    if (value.indexOf("\u0000") >= 0) return false
    const controls = value.replace(/[\n\r\t\u001b]/g, "").replace(/[^\u0001-\u001f\u007f]/g, "").length
    return controls * 20 <= value.length
}

function asciiRuns(text) {
    const raw = String(text || "")
    if (!looksLikeText(raw)) return { rows: 0, columns: 0, runs: [] }
    const lines = raw.replace(/\r/g, "").replace(/\u001b\[[0-9;?]*[A-Za-z]/g, "").split("\n").slice(0, LOGO_LIMIT.rows)
    while (lines.length && !lines[lines.length - 1].replace(/\$[1-9]/g, "").trim().length) lines.pop()
    const runs = []
    let columns = 0
    for (let row = 0; row < lines.length; ++row) {
        const line = lines[row]
        let tone = 1
        let column = 0
        let run = null
        for (let index = 0; index < line.length; ++index) {
            let character = line.charAt(index)
            if (character === "$" && index + 1 < line.length) {
                const next = line.charAt(index + 1)
                if (next >= "1" && next <= "9") {
                    tone = Number(next)
                    run = null
                    ++index
                    continue
                }
                if (next === "$") ++index
            }
            if (column >= LOGO_LIMIT.columns) break
            if (character === " " || character === "\t") {
                run = null
            } else if (run && run.tone === tone) {
                run.text += character
            } else {
                run = { row: row, col: column, text: character, tone: tone }
                runs.push(run)
            }
            ++column
            if (run) columns = Math.max(columns, column)
        }
    }
    return { rows: lines.length, columns: columns, runs: runs }
}

// ---- which logo ----------------------------------------------------------------
// The menu follows the user's fastfetch: the text logo its configuration
// (the shell's fastfetch.jsonc, Settings > Terminal) draws, else the user's
// own copy of the Saturn in the config directory, else the one the shell
// ships. fastfetch's logo types as scripts/fastfetch-image.py reads them:
// "file"/"file-raw" name a text file, "data"/"data-raw" are the text itself,
// the image types and the named logos ("builtin", "small", "none") are no
// text logo; with no type ("auto") a path that is not an image's is one.
var TEXT_LOGO_TYPES = ["file", "file-raw"]
var DATA_LOGO_TYPES = ["data", "data-raw"]
var IMAGE_SUFFIXES = [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"]

// JSONC as fastfetch writes it: // and /* */ comments and trailing commas,
// outside strings (fastfetch-image.py's strip_jsonc, the same walk).
function stripJsonc(text) {
    const source = String(text || "")
    let out = ""
    let comma = false
    let index = 0
    while (index < source.length) {
        const character = source.charAt(index)
        if (character === '"') {
            let end = index + 1
            while (end < source.length && source.charAt(end) !== '"') end += source.charAt(end) === "\\" ? 2 : 1
            if (comma) { out += ","; comma = false }
            out += source.slice(index, end + 1)
            index = end + 1
            continue
        }
        if (source.startsWith("//", index)) {
            const end = source.indexOf("\n", index)
            index = end < 0 ? source.length : end
            continue
        }
        if (source.startsWith("/*", index)) {
            const end = source.indexOf("*/", index + 2)
            index = end < 0 ? source.length : end + 2
            continue
        }
        if (character === ",") {
            if (comma) out += ","
            comma = true
        } else if (/\s/.test(character)) {
            out += character
        } else {
            // A comma right before a closing bracket was a trailing one.
            if (comma && character !== "}" && character !== "]") out += ","
            comma = false
            out += character
        }
        ++index
    }
    return comma ? out + "," : out
}

function expandHome(path, home) {
    const text = String(path || "")
    if (text === "~") return String(home || "")
    return text.indexOf("~/") === 0 ? String(home || "") + text.slice(1) : text
}

// The text logo a fastfetch configuration draws: { path } for a file,
// { text } for one written into it, {} for none (or no configuration).
function textLogo(configText, home) {
    let config = null
    try { config = JSON.parse(stripJsonc(configText)) } catch (error) { return {} }
    const logo = config && typeof config === "object" ? config.logo : null
    if (!logo || typeof logo !== "object" || typeof logo.source !== "string" || !logo.source.length) return {}
    const kind = typeof logo.type === "string" && logo.type.length ? logo.type.toLowerCase() : "auto"
    if (DATA_LOGO_TYPES.indexOf(kind) >= 0) return { text: logo.source }
    const path = expandHome(logo.source, home)
    if (TEXT_LOGO_TYPES.indexOf(kind) >= 0) return { path: path }
    if (kind !== "auto") return {}
    const lower = path.toLowerCase()
    if (IMAGE_SUFFIXES.some(suffix => lower.endsWith(suffix)) || path.indexOf("/") < 0) return {}
    return { path: path }
}

// The files to try, in order, each once: the configuration's, the user's
// Saturn, the shipped one.
function logoPaths(logo, userCopy, shipped) {
    const result = []
    for (const path of [logo && logo.path, userCopy, shipped])
        if (typeof path === "string" && path.length && result.indexOf(path) < 0) result.push(path)
    return result
}

// ---- the Saturn on the start button ----------------------------------------
// Traced from the same logo (config/builtin-profiles/buchhwin/saturn.txt):
// the planet in columns 12-37 and rows 1-12, the ring from its tip at the
// lower left (column 0.5, row 13.6) to the upper right (54.5, 1.3), crossing
// the planet's lower half in front of it. In a box 177 wide and 100 high - the
// logo's own proportions, with the ring opened a little so that its two sides
// stay apart at the size of a dock icon - the planet's radius is 40, the
// ring's half axes 94 and 18, its line 8.8 thick and tilted 27 degrees up to
// the right. `overlap` is how far, in degrees, the ring's front half reaches
// over the back half at each tip, so the two meet without a seam.
var SATURN = { width: 177, height: 100, planet: 40, ringA: 94, ringB: 18, stroke: 8.8, tilt: -27, overlap: 6 }

function saturnGeometry(width, height) {
    const w = Math.max(0, Number(width) || 0)
    const h = Math.max(0, Number(height) || 0)
    const scale = Math.min(w / SATURN.width, h / SATURN.height)
    return {
        cx: w / 2, cy: h / 2,
        planet: SATURN.planet * scale,
        ringA: SATURN.ringA * scale, ringB: SATURN.ringB * scale,
        stroke: SATURN.stroke * scale,
        tilt: SATURN.tilt, overlap: SATURN.overlap
    }
}

// The width the Saturn needs for a height, in its own proportions.
function saturnWidth(height) {
    return Math.round(Math.max(0, Number(height) || 0) * SATURN.width / SATURN.height)
}

// ---- every app, A to Z --------------------------------------------------------
// The letter an app is filed under: its name's first letter without accents
// (Ärger under A, émail under E), "#" for a digit or a sign, a letter of
// another alphabet as itself.
function letterOf(name) {
    const plain = String(name || "").normalize("NFD").replace(/[̀-ͯ]/g, "").trim()
    if (!plain.length) return "#"
    const first = plain.charAt(0).toUpperCase()
    if (/[A-Z]/.test(first)) return first
    // Without a case it is a digit or a sign.
    return first.toLowerCase() === first ? "#" : first
}

function nameOf(entry) {
    return String(entry && (entry.name || entry.id) || "")
}

// The list "All apps" shows: a header for each letter, then its apps by name.
// `#` first, then A-Z, then other letters. The rows are keyed by strings
// ("h:A", "a:<id>"), so a list rebuilt from a new scan keeps its delegates
// (ScriptModel, testing.md pitfall 76); `appIndex` counts the apps alone, for
// the keys.
function alphabet(entries) {
    const list = Array.prototype.slice.call(entries || []).filter(entry => entry && entry.id)
        .map(entry => ({ entry: entry, letter: letterOf(nameOf(entry)), name: nameOf(entry) }))
    function rank(letter) { return letter === "#" ? 0 : /^[A-Z]$/.test(letter) ? 1 : 2 }
    list.sort((a, b) => rank(a.letter) - rank(b.letter) || a.letter.localeCompare(b.letter)
        || a.name.localeCompare(b.name) || (a.entry.id < b.entry.id ? -1 : a.entry.id > b.entry.id ? 1 : 0))
    const rows = []
    const ids = []
    const letters = []
    const seen = {}
    for (const item of list) {
        if (seen[item.entry.id]) continue
        seen[item.entry.id] = true
        if (letters[letters.length - 1] !== item.letter) {
            letters.push(item.letter)
            rows.push({ key: "h:" + item.letter, kind: "header", letter: item.letter })
        }
        rows.push({ key: "a:" + item.entry.id, kind: "app", id: item.entry.id, letter: item.letter, appIndex: ids.length })
        ids.push(item.entry.id)
    }
    return { rows: rows, ids: ids, letters: letters }
}

// ---- the keys ---------------------------------------------------------------
// The keyboard stays in the search field the whole time (typing searches at
// once, as in the launcher); the arrows move a selection over the menu's
// zones instead - the pinned grid, the frequent apps, the places, the footer,
// or the one list of all apps or results. `zones` are the ones with
// something in them, in order: [{ id, count, columns }]. `state` is
// { zone, index }, zone "" being the field. Keys: up, down, left, right, tab,
// backtab, home, end, pageUp, pageDown.
function move(state, key, zones, page) {
    const list = Array.prototype.slice.call(zones || []).filter(zone => zone && zone.count > 0)
    const field = { zone: "", index: 0 }
    if (!list.length) return field
    const at = state && state.zone ? list.findIndex(zone => zone.id === state.zone) : -1
    if (!state || !state.zone || at < 0) {
        if (key === "down" || key === "tab") return { zone: list[0].id, index: 0 }
        if (key === "backtab") return { zone: list[list.length - 1].id, index: 0 }
        return field
    }
    const zone = list[at]
    const columns = Math.max(1, zone.columns || 1)
    const index = Math.max(0, Math.min(zone.count - 1, Number(state.index) || 0))
    const column = index % columns
    const rows = Math.ceil(zone.count / columns)
    const row = Math.floor(index / columns)
    const step = Math.max(1, Number(page) || 8)
    function into(other, wanted, fromBelow) {
        const cols = Math.max(1, other.columns || 1)
        const lastRow = Math.floor((other.count - 1) / cols)
        const target = (fromBelow ? lastRow * cols : 0) + Math.min(wanted, cols - 1)
        return { zone: other.id, index: Math.min(other.count - 1, target) }
    }
    switch (key) {
    case "right": return { zone: zone.id, index: column < columns - 1 && index + 1 < zone.count ? index + 1 : index }
    case "left": return { zone: zone.id, index: column > 0 ? index - 1 : index }
    case "down":
        if (index + columns < zone.count) return { zone: zone.id, index: index + columns }
        if (row < rows - 1) return { zone: zone.id, index: zone.count - 1 }
        return at + 1 < list.length ? into(list[at + 1], column, false) : { zone: zone.id, index: index }
    case "up":
        if (index - columns >= 0) return { zone: zone.id, index: index - columns }
        return at > 0 ? into(list[at - 1], column, true) : field
    case "tab": return at + 1 < list.length ? { zone: list[at + 1].id, index: 0 } : field
    case "backtab": return at > 0 ? { zone: list[at - 1].id, index: 0 } : field
    case "home": return { zone: zone.id, index: 0 }
    case "end": return { zone: zone.id, index: zone.count - 1 }
    case "pageDown": return { zone: zone.id, index: Math.min(zone.count - 1, index + step * columns) }
    case "pageUp": return { zone: zone.id, index: Math.max(0, index - step * columns) }
    }
    return { zone: zone.id, index: index }
}

// Escape, one step at a time: the app's or the power menu, then the query,
// then All apps, then the menu closes. The field itself clears what was
// typed since it took the focus; a query it already held then (a focus that
// went and came back) it passes on, and this step clears it.
function escapeStep(menuOpen, query, view) {
    if (menuOpen) return "menu"
    if (String(query || "").length) return "query"
    if (view === "all") return "view"
    return "close"
}

// ---- frequent -----------------------------------------------------------------
// The apps used most (ids ranked by Usage.top) that are still installed, meant
// to be shown and not pinned already.
function frequent(rankedIds, entries, pinnedIds, limit) {
    const byId = {}
    for (const entry of Array.prototype.slice.call(entries || []))
        if (entry && entry.id && !entry.noDisplay) byId[entry.id] = entry
    const pinned = Array.prototype.slice.call(pinnedIds || [])
    const result = []
    const most = limit === undefined ? Infinity : Math.max(0, Number(limit) || 0)
    for (const id of Array.prototype.slice.call(rankedIds || [])) {
        if (result.length >= most) break
        if (byId[id] && pinned.indexOf(id) < 0 && result.indexOf(byId[id]) < 0) result.push(byId[id])
    }
    return result
}

// ---- suggested ------------------------------------------------------------------
// With nothing pinned the menu suggests what the dock pins by default: the
// session's file manager, terminal and browser (Settings > Default apps,
// default-apps.py's categories: [{ id: "terminal", current: "Alacritty.desktop" } …])
// and the shell's own Settings. Each app once, only what is installed and
// shown; a right click pins it. `lookup(id)` is DesktopEntries.byId.
var SUGGESTED = ["files", "terminal", "browser"]

function suggested(categories, lookup) {
    const list = Array.prototype.slice.call(categories || [])
    const result = []
    for (const category of SUGGESTED) {
        const found = list.find(item => item && item.id === category)
        const id = found && found.current ? String(found.current).replace(/\.desktop$/, "") : ""
        const entry = id.length && typeof lookup === "function" ? lookup(id) : null
        if (entry && entry.id && !entry.noDisplay && !result.some(item => item.entry && item.entry.id === entry.id))
            result.push({ kind: "app", entry: entry })
    }
    result.push({ kind: "settings" })
    return result
}

// ---- places -------------------------------------------------------------------
// Home and the user's own folders (user-dirs.dirs), each opened in the file
// manager. A folder the file does not name, or turns off with a bare $HOME, is
// left out; without the file there is Home alone.
var PLACES = [
    { id: "home", key: "", label: "Home", glyph: "\u{f02dc}" },
    { id: "documents", key: "DOCUMENTS", label: "Documents", glyph: "\u{f0219}" },
    { id: "downloads", key: "DOWNLOAD", label: "Downloads", glyph: "\u{f01da}" },
    { id: "pictures", key: "PICTURES", label: "Pictures", glyph: "\u{f02e9}" },
    { id: "music", key: "MUSIC", label: "Music", glyph: "\u{f075a}" },
    { id: "videos", key: "VIDEOS", label: "Videos", glyph: "\u{f0567}" }
]

function places(userDirsText, home) {
    const base = String(home || "")
    const result = []
    for (const place of PLACES) {
        const path = place.key.length ? UserDirs.userDir(userDirsText, place.key, base) : base
        if (!path.length || (place.key.length && path === base)) continue
        result.push({ id: place.id, label: place.label, glyph: place.glyph, path: path })
    }
    return result
}

// ---- the header's second line ----------------------------------------------------
// /proc/uptime → whole seconds, -1 when it is not a number.
function uptimeSeconds(procText) {
    const first = String(procText || "").trim().split(/\s+/)[0]
    const seconds = Number(first)
    return first.length && isFinite(seconds) && seconds >= 0 ? Math.floor(seconds) : -1
}

// "14 min", "2 h 14 min", "3 d 2 h": the two largest units that are there,
// the way fastfetch's uptime reads at a glance.
function uptimeText(seconds) {
    const total = Number(seconds)
    if (!isFinite(total) || total < 0) return ""
    const days = Math.floor(total / 86400)
    const hours = Math.floor(total % 86400 / 3600)
    const minutes = Math.floor(total % 3600 / 60)
    if (days > 0) return days + " d" + (hours > 0 ? " " + hours + " h" : "")
    if (hours > 0) return hours + " h" + (minutes > 0 ? " " + minutes + " min" : "")
    return minutes + " min"
}

// The header's rows beside the logo, fastfetch's way: a key and its value,
// hung from a tree line. Rows whose value is not known are left out.
function infoRows(prettyName, kernel, seconds) {
    const rows = [{ key: "os", value: String(prettyName || "").trim() },
                  { key: "kernel", value: String(kernel || "").trim() },
                  { key: "uptime", value: uptimeText(seconds) }].filter(row => row.value.length)
    return rows.map((row, index) => Object.assign(row, {
        branch: rows.length === 1 ? "──" : index === 0 ? "╭─" : index === rows.length - 1 ? "╰─" : "├─"
    }))
}

// ---- menus ----------------------------------------------------------------------
// An app's menu (right click, the menu key): open it, its own actions (a
// browser's private window, a web app's "New message"), pin it to the start
// menu or take it off, move a pinned one along, and pin it to the dock while
// there is one. A pin that cannot be made (the list is full) stays, turned
// off, so its hint can say why. `ctx`: { source ("pinned" | "frequent" | "all" | "results"),
// pinned, pinnedFull, pinIndex, pinCount, dockEnabled, inDock, dockFull,
// actions }.
function appMenuRows(ctx) {
    const c = ctx || {}
    const rows = [{ kind: "open" }]
    const actions = c.actions && typeof c.actions.length === "number" ? Array.prototype.slice.call(c.actions) : []
    for (const action of actions)
        if (action && action.id) rows.push({ kind: "action", id: String(action.id), name: String(action.name || action.id) })
    rows.push(c.pinned ? { kind: "unpinStart" } : { kind: "pinStart", enabled: !c.pinnedFull })
    // Only the moves there is room for: the first tile has no left.
    if (c.source === "pinned" && c.pinned) {
        const index = Number(c.pinIndex) || 0
        if (index > 0) rows.push({ kind: "moveLeft" })
        if (index < (Number(c.pinCount) || 0) - 1) rows.push({ kind: "moveRight" })
    }
    if (c.dockEnabled) rows.push(c.inDock ? { kind: "unpinDock" } : { kind: "pinDock", enabled: !c.dockFull })
    return rows
}

// The power button's menu. Lock has a button of its own beside it; sleep runs
// at once, the other three ask first (the power menu's confirmation).
function powerRows() {
    return [
        { kind: "suspend", confirm: false },
        { kind: "logout", confirm: true },
        { kind: "reboot", confirm: true },
        { kind: "poweroff", confirm: true }
    ]
}

// Whether an app is on the dock, and by which pin: its own id, or one of the
// default-app tokens (@files, @terminal, @browser) that stands for it now
// (Settings > Default apps). Taking it off the dock takes that pin away.
function dockState(pins, id, categories) {
    const name = String(id || "").replace(/\.desktop$/, "")
    const list = Array.prototype.slice.call(pins || [])
    if (!name.length) return { pinned: false, pin: "" }
    if (list.indexOf(name) >= 0) return { pinned: true, pin: name }
    for (const pin of list)
        if (Dock.pinCategory(pin).length && Dock.defaultFor(pin, categories) === name) return { pinned: true, pin: pin }
    return { pinned: false, pin: name }
}
