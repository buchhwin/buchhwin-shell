.pragma library
.import "../profile/ProfileLogic.js" as Profile

// What shell.qml's IPC `get` handlers hand out. They answer agents, tests and
// CI logs (`buchhwin <target> get`), so they return counts and flags, never a
// name, a title or a place (docs: "get() handlers return counts and flags").
// And, at the end, what a few other handlers take: a rect, a page, settings
// set together. Unit tested (IpcLogicTest).

// ---- settings get PATH -----------------------------------------------------------
// The settings that say where this person is or what they did rather than
// how the desktop looks: everything a profile leaves out as this machine's or
// this person's (ProfileLogic.GLOBAL_SETTINGS: the weather place, the
// calendars, the colours picked, the folders used …), and the paths on disk
// a profile does carry - a file name says something about whose machine it is.
// The login screen's picture is one of those paths, as profile-export.py
// treats it: `settings get login` handed it out whole.
var PRIVATE_SETTINGS = ["wallpaper.path", "wallpaper.lightPath", "wallpaper.darkPath", "wallpaper.folder",
                        "wallpaper.slideshowFolder", "recording.folder", "launcher.searchUrl", "login.wallpaper"]

// Whether `settings get` keeps a path to itself: one of those settings, a
// key inside one, or a group that holds one ("weather" holds the place, ""
// is the whole file).
function privateSetting(path) {
    const text = String(path === undefined || path === null ? "" : path).trim()
    if (!text.length) return true
    const all = Profile.GLOBAL_SETTINGS.concat(PRIVATE_SETTINGS)
    return all.some(entry => text === entry || text.indexOf(entry + ".") === 0 || entry.indexOf(text + ".") === 0)
}

// The answer for such a path: only whether it holds anything other than its
// default, which is what a test can need ("is a place set?").
function withheldAnswer(value, fallback) {
    return { withheld: true, set: JSON.stringify(value) !== JSON.stringify(fallback) }
}

// ---- audio get ---------------------------------------------------------------------
// A sink's node.name carries a Bluetooth device's address
// (bluez_output.XX_XX_XX_XX_XX_XX.1), a stable name for the user's own
// headphones: `audio get` lists the sinks by their PipeWire id, and a stream's
// target the same way ("" for the default output). `audio route` takes either.
function sinkIds(sinks) {
    return Array.prototype.slice.call(sinks || []).filter(sink => sink && sink.id !== undefined).map(sink => sink.id)
}

function sinkIdOf(name, sinks) {
    const text = String(name || "")
    if (!text.length) return ""
    const found = Array.prototype.slice.call(sinks || []).find(sink => sink && sink.name === text)
    return found ? found.id : ""
}

// The sink `audio route STREAM SINK` means: by id or by node.name; null for
// one that is not there. "default" is the caller's own word, not a sink.
function sinkFor(wanted, sinks) {
    const text = String(wanted === undefined || wanted === null ? "" : wanted)
    if (!text.length) return null
    const list = Array.prototype.slice.call(sinks || []).filter(Boolean)
    return list.find(sink => String(sink.id) === text) || list.find(sink => sink.name === text) || null
}

// ---- popup openAt, controlCenter openPage, bar setWorkspaces ---------------------
// The arguments of `popup openAt NAME X Y WIDTH HEIGHT`: the rect a popup grows
// out of, and the place below it, or null for a rect that is none. The client
// hands "nan" and "inf" on as numbers, and `width <= 0` is false for NaN: a
// NaN x kept the card's morph at NaN for the whole open, an invisible panel
// over the scrim.
function originArgs(x, y, width, height) {
    const values = [x, y, width, height]
    if (!values.every(value => typeof value === "number" && isFinite(value)) || width <= 0 || height <= 0) return null
    return { anchorX: x + width / 2, anchorTop: y + height,
             originX: x, originY: y, originWidth: width, originHeight: height }
}

// The control center's detail pages (ControlCenter.qml `detailPage`), and ""
// for its overview. Any other name opened the overview with a Back button and
// no grip, and said nothing.
var CONTROL_CENTER_PAGES = ["network", "bluetooth", "audio", "dnd", "power", "drives", "tray"]
function controlCenterPage(page) {
    const text = String(page === undefined || page === null ? "" : page)
    return text === "" || CONTROL_CENTER_PAGES.indexOf(text) >= 0
}

// Whether every value is one its setting allows (SettingsService.allowed), so
// a call that sets several either sets them all or none: `bar setWorkspaces
// open 99` stored the mode, then refused the count.
function allAllowed(values, allowed) {
    return Object.keys(values || {}).every(path =>
        Array.prototype.indexOf.call((allowed || {})[path] || [], values[path]) >= 0)
}
