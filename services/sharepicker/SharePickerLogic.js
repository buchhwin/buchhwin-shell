.pragma library

// The shell's half of xdg-desktop-portal-hyprland's custom picker
// (screencopy:custom_picker_binary in ~/.config/hypr/xdph.conf naming
// scripts/share-picker.sh). The portal runs the picker for every request to
// share the screen and waits for it; what the picker prints is the answer,
// read in src/shared/ScreencopyShared.cpp (v1.4.1):
//
//     [SELECTION]<flags>/screen:<output>\n
//     [SELECTION]<flags>/window:<handle>\n
//     [SELECTION]<flags>/region:<output>@<x>,<y>,<w>,<h>\n
//
// The flags are "r" (the app may get a token to share the same thing again
// without asking) or nothing. The portal drops the last character of an
// output's name - the newline the default picker ends with - so the line
// must end in exactly one. A window is named by the low 32 bits of the
// portal's own toplevel handle, from the list it hands the picker in
// XDPH_WINDOW_SHARING_LIST:
//
//     <handle>[HC>]<class>[HT>]<title>[HE>]<address>[HA>]...
//
// where <address> is Hyprland's window address in decimal (0 when the
// portal could not map it; older portals have no [HA>] part at all). A
// region is in the output's own logical pixels. Anything else - no
// [SELECTION] at all - is a cancelled share.
//
// The script hands the list to the shell in a file of a private directory
// (titles are nobody else's business, and a process's arguments are every
// user's), the shell answers with one line on a FIFO there: a SELECTION
// line, "region" (the script runs slurp itself once the panel is gone),
// "cancel" or "fallback" (the picker did not come up). Every error on the
// way - no shell, a refusal, a shell that dies, "fallback" - opens the
// portal's own picker instead (scripts/share-picker.sh).

var CANCEL = "cancel"
var REGION = "region"
var FALLBACK = "fallback"
// The private directory's place under the shell's runtime directory, and
// what a request's own directory is called there (mktemp's XXXXXXXX).
var REQUEST_PARENT = "share-picker"
var REQUEST_NAME = /^req\.[A-Za-z0-9]{6,32}$/
// An output name the portal can take back: Hyprland's connector names
// (eDP-1, DP-10, HDMI-A-1) and the headless and nested ones.
var OUTPUT_NAME = /^[A-Za-z0-9._-]{1,64}$/
var HANDLE = /^\d{1,10}$/

// ---- the portal's window list ------------------------------------------------

// Hyprland's address for a decimal number: lowercase hex without "0x" or
// leading zeros, "" for 0 or anything that is not a number. Done digit by
// digit, because an address is 64 bits and a JS number keeps 53.
function decimalToHex(text) {
    const digits = String(text === undefined || text === null ? "" : text).trim()
    if (!/^\d{1,20}$/.test(digits) || /^0+$/.test(digits)) return ""
    let number = digits.replace(/^0+/, "").split("").map(Number)
    let hex = ""
    while (number.length) {
        let remainder = 0
        const quotient = []
        for (const digit of number) {
            const value = remainder * 10 + digit
            const next = Math.floor(value / 16)
            remainder = value % 16
            if (quotient.length || next) quotient.push(next)
        }
        hex = "0123456789abcdef".charAt(remainder) + hex
        number = quotient
    }
    return hex
}

// An address as one key: lowercase, without "0x" and leading zeros
// (Quickshell's toplevels have none, hyprctl's has "0x").
function addressKey(address) {
    const text = String(address === undefined || address === null ? "" : address).trim().toLowerCase()
    return (text.indexOf("0x") === 0 ? text.slice(2) : text).replace(/^0+/, "")
}

// [{ handle, appClass, title, address }] from XDPH_WINDOW_SHARING_LIST, in its
// order; an entry without a number for a handle is left out, and a broken
// tail ends the list where it breaks, as the default picker reads it.
function parseWindowList(text) {
    const result = []
    let rest = String(text === undefined || text === null ? "" : text)
    while (rest.length) {
        const classAt = rest.indexOf("[HC>]")
        const titleAt = rest.indexOf("[HT>]")
        const endAt = rest.indexOf("[HE>]")
        if (classAt < 0 || titleAt < classAt || endAt < titleAt) break
        const handle = rest.slice(0, classAt).trim()
        const appClass = rest.slice(classAt + 5, titleAt)
        const title = rest.slice(titleAt + 5, endAt)
        let after = rest.slice(endAt + 5)
        // v1.3.4 and later: the window's address up to [HA>], before the
        // next entry's handle.
        let address = ""
        const addressAt = after.indexOf("[HA>]")
        const nextClass = after.indexOf("[HC>]")
        if (addressAt >= 0 && (nextClass < 0 || addressAt < nextClass)) {
            address = decimalToHex(after.slice(0, addressAt))
            after = after.slice(addressAt + 5)
        }
        if (HANDLE.test(handle) && Number(handle) <= 4294967295)
            result.push({ handle: handle, appClass: appClass.trim(), title: title.trim(), address: address })
        rest = after
    }
    return result
}

// ---- what the picker answers ---------------------------------------------------

// The line the script hands to the portal for a choice, without its newline:
// "" for a choice it cannot take (an output name or a handle that is not
// one). A region is answered "region" and the script asks slurp for it.
function answerFor(stop, allowToken) {
    if (!stop || typeof stop !== "object") return ""
    const flags = allowToken === true ? "r" : ""
    if (stop.kind === "screen" && OUTPUT_NAME.test(String(stop.name || "")))
        return "[SELECTION]" + flags + "/screen:" + stop.name
    if (stop.kind === "window" && HANDLE.test(String(stop.handle || "")))
        return "[SELECTION]" + flags + "/window:" + stop.handle
    if (stop.kind === "region") return REGION + (flags.length ? " " + flags : "")
    return ""
}

// Whether a line is one the portal reads as a choice - the script checks the
// same with its own expression before it prints anything.
function validSelection(line) {
    return /^\[SELECTION\]r?\/(?:screen:[A-Za-z0-9._-]{1,64}|window:\d{1,10}|region:[A-Za-z0-9._-]{1,64}@-?\d{1,6},-?\d{1,6},\d{1,6},\d{1,6})$/
        .test(String(line === undefined || line === null ? "" : line))
}

// A request's directory is only ever the script's own, under the shell's
// runtime directory: the shell writes its answer into it, and an IPC caller
// must not be able to point that write anywhere else.
function requestDirOk(dir, runtimeDir) {
    const base = String(runtimeDir === undefined || runtimeDir === null ? "" : runtimeDir)
    const path = String(dir === undefined || dir === null ? "" : dir)
    if (base.charAt(0) !== "/" || base.indexOf("/..") >= 0 || base.indexOf("/./") >= 0) return false
    const prefix = base.replace(/\/+$/, "") + "/" + REQUEST_PARENT + "/"
    if (path.indexOf(prefix) !== 0) return false
    return REQUEST_NAME.test(path.slice(prefix.length))
}

// ---- what the picker shows, and the keys -----------------------------------------

// The windows, those on a workspace that is shown first, then by workspace,
// then as the portal listed them; windows Hyprland does not know (no address
// mapped) last. `info` is { address key: { workspace, shown } }.
function orderWindows(windows, info) {
    const known = info || {}
    const rank = entry => {
        const item = known[addressKey(entry.address)]
        if (!item) return [3, 0]
        const workspace = Number(item.workspace)
        if (item.shown === true) return [0, isFinite(workspace) ? workspace : 0]
        return [isFinite(workspace) && workspace > 0 ? 1 : 2, isFinite(workspace) ? Math.abs(workspace) : 0]
    }
    return (windows || []).map((entry, index) => ({ entry: entry, index: index, rank: rank(entry) }))
        .sort((a, b) => a.rank[0] - b.rank[0] || a.rank[1] - b.rank[1] || a.index - b.index)
        .map(item => item.entry)
}

// Every choice in the order the keys walk them: the screens, the windows,
// the region. [{ key, kind, section, name | handle | entry }]
function stops(screens, windows, regionShown) {
    const result = []
    for (const screen of screens || [])
        if (screen && OUTPUT_NAME.test(String(screen.name || "")))
            result.push({ key: "screen:" + screen.name, kind: "screen", section: "screens", name: screen.name })
    for (const entry of windows || [])
        if (entry && HANDLE.test(String(entry.handle || "")))
            result.push({ key: "window:" + entry.handle, kind: "window", section: "windows", handle: entry.handle, entry: entry })
    if (regionShown !== false) result.push({ key: "region", kind: "region", section: "region" })
    return result
}

function indexOfKey(list, key) {
    return (list || []).findIndex(stop => stop.key === key)
}

// Where the selection starts: the screen the picker opened on, which is the
// one the user is looking at; the first choice otherwise.
function openingIndex(list, screenName) {
    const at = indexOfKey(list, "screen:" + String(screenName || ""))
    return at >= 0 ? at : 0
}

// The selection after an arrow key: Left and Right walk the whole list,
// Up and Down a section's rows (`columns` per section), and from a section's
// first or last row to the nearest place of the section before or after.
function move(list, index, direction, columns) {
    const all = list || []
    if (!all.length) return -1
    const at = Math.max(0, Math.min(all.length - 1, Math.round(Number(index)) || 0))
    if (direction === "left") return Math.max(0, at - 1)
    if (direction === "right") return Math.min(all.length - 1, at + 1)
    if (direction !== "up" && direction !== "down") return at
    const sections = []
    for (let i = 0; i < all.length; i += 1) {
        const last = sections[sections.length - 1]
        if (last && last.name === all[i].section) last.count += 1
        else sections.push({ name: all[i].section, start: i, count: 1 })
    }
    const perRow = name => Math.max(1, Math.round(Number(columns && columns[name])) || 1)
    const current = sections.findIndex(section => at >= section.start && at < section.start + section.count)
    const section = sections[current]
    const width = perRow(section.name)
    const offset = at - section.start
    const row = Math.floor(offset / width)
    const column = offset % width
    const rows = Math.ceil(section.count / width)
    if (direction === "down" && row + 1 < rows)
        return section.start + Math.min(section.count - 1, (row + 1) * width + column)
    if (direction === "up" && row > 0) return section.start + (row - 1) * width + column
    const target = sections[current + (direction === "down" ? 1 : -1)]
    if (!target) return at
    const targetWidth = perRow(target.name)
    const targetRow = direction === "down" ? 0 : Math.ceil(target.count / targetWidth) - 1
    return target.start + Math.min(target.count - 1, targetRow * targetWidth + Math.min(column, targetWidth - 1))
}

// A thumbnail's size: `width` x `height` fitted into the box, the box
// itself for a size nobody knows.
function fitInside(width, height, boxWidth, boxHeight) {
    const w = Number(width)
    const h = Number(height)
    const bw = Math.max(0, Number(boxWidth) || 0)
    const bh = Math.max(0, Number(boxHeight) || 0)
    if (!(w > 0 && h > 0) || !(bw > 0 && bh > 0)) return { width: bw, height: bh }
    const scale = Math.min(bw / w, bh / h)
    return { width: Math.round(w * scale), height: Math.round(h * scale) }
}

// "Built-in display · 1920 × 1200", the size in logical pixels.
// `monitor` (optional) is DisplayService's entry for it, `internal` whether
// it is the laptop's own panel: the screen is then called what Settings >
// Displays calls it - "Built-in display", or its make and model - rather
// than by its connector (eDP-1, DP-8), which says nothing to anyone.
function screenLabel(screen, monitor, internal) {
    if (!screen) return ""
    const known = monitor ? [monitor.make, monitor.model].filter(value => value && String(value).length).join(" ") : ""
    const name = internal === true ? "Built-in display" : known.length ? known : String(screen.name || "")
    const width = Math.round(Number(screen.width))
    const height = Math.round(Number(screen.height))
    return width > 0 && height > 0 ? name + " · " + width + " × " + height : name
}

// A window's line: its title, else its class, else "Window".
function windowLabel(entry) {
    if (!entry) return "Window"
    if (String(entry.title || "").length) return entry.title
    if (String(entry.appClass || "").length) return entry.appClass
    return "Window"
}

// ---- the portal's configuration (Settings) ----------------------------------------

// The picker the portal's configuration names: the value of
// `custom_picker_binary` in a `screencopy { }` block or as
// `screencopy:custom_picker_binary`, "" when it names none (the portal's own
// picker then). Hyprlang comments start with "#".
function configuredPicker(text) {
    let depth = 0
    let inScreencopy = false
    let found = ""
    for (const raw of String(text === undefined || text === null ? "" : text).split("\n")) {
        const line = raw.replace(/#.*$/, "").trim()
        if (!line.length) continue
        const open = /^([A-Za-z_][\w-]*)\s*\{$/.exec(line)
        if (open) {
            depth += 1
            if (depth === 1) inScreencopy = open[1] === "screencopy"
            continue
        }
        if (line === "}") {
            depth = Math.max(0, depth - 1)
            if (depth === 0) inScreencopy = false
            continue
        }
        const pair = /^([\w:-]+)\s*=\s*(.*)$/.exec(line)
        if (!pair) continue
        if ((inScreencopy && depth === 1 && pair[1] === "custom_picker_binary")
            || (depth === 0 && pair[1] === "screencopy:custom_picker_binary"))
            found = pair[2].trim()
    }
    return found
}

// Whether that picker is the shell's: any tree's scripts/share-picker.sh.
function isShellPicker(value) {
    return /(?:^|\/)scripts\/share-picker\.sh$/.test(String(value || "").trim())
}

// The lines that make the portal use the shell's picker.
function configSnippet(scriptPath) {
    return "screencopy {\n    custom_picker_binary = " + String(scriptPath || "") + "\n}\n"
}
