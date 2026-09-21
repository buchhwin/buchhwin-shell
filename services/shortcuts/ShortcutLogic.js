.pragma library

// Settings > Shortcuts: readable rows from `hyprctl -j binds` and the user's
// own shortcuts in ~/.config/buchhwin-shell/shortcuts.json. Legacy configs
// report the dispatcher and argument, which are turned into titles here; the
// Lua config reports `__lua` with a reference number instead, so
// hypr/hyprland.lua gives every bind a `description` with the same titles.
// Custom shortcuts are bound with the description "Custom: …", which is how
// the shell recognises its own binds. Unit tested (tests/qml/ShortcutTest.qml).

var customPrefix = "Custom: "

var groups = [
    { id: "apps", title: "Apps" },
    { id: "custom", title: "Custom" },
    { id: "panels", title: "Shell panels" },
    { id: "windows", title: "Windows" },
    { id: "workspaces", title: "Workspaces" },
    { id: "screenshots", title: "Screenshots & recording" },
    { id: "system", title: "System & media keys" },
    { id: "other", title: "Other" }
]

// Hyprland modifier bits, in display order.
var modifiers = [
    { name: "SUPER", label: "Super", bit: 64 },
    { name: "CTRL", label: "Ctrl", bit: 4 },
    { name: "ALT", label: "Alt", bit: 8 },
    { name: "SHIFT", label: "Shift", bit: 1 }
]

// Known titles and their groups; hyprland.lua uses the same titles.
var titleGroups = {
    "Terminal": "apps", "Web browser": "apps", "File manager": "apps",
    "Launcher": "panels", "Control center": "panels", "Settings": "panels", "Notification center": "panels",
    "Emoji picker": "panels",
    "Dashboard": "panels", "Session menu": "panels", "Overview": "panels", "Clipboard history": "panels",
    "Layout editor": "panels",
    "Close window": "windows", "Fullscreen": "windows", "Maximize": "windows", "Toggle floating": "windows",
    "Resize window": "windows", "Move window": "windows", "Next window": "windows", "Previous window": "windows",
    "Switch to selected window": "windows",
    "Screenshot of a region": "screenshots", "Screenshot of the screen": "screenshots", "Screenshot of a window": "screenshots",
    "Record a region": "screenshots", "Record the screen": "screenshots",
    "Lock screen": "system", "Restart buchhwin-shell": "system", "Lid closed": "system", "Lid opened": "system",
    "Volume up": "system", "Volume down": "system", "Mute audio": "system", "Mute microphone": "system",
    "Brightness up": "system", "Brightness down": "system", "Play or pause": "system", "Next track": "system",
    "Previous track": "system", "Exit Hyprland": "system"
}

var panelTitles = {
    launcher: "Launcher", controlCenter: "Control center", settings: "Settings", notifications: "Notification center",
    dashboard: "Dashboard", powerMenu: "Session menu", overview: "Overview", clipboard: "Clipboard history",
    editor: "Layout editor", emoji: "Emoji picker"
}

var keyLabels = {
    "return": "Enter", "enter": "Enter", "escape": "Esc", "space": "Space", "tab": "Tab", "backspace": "Backspace",
    "delete": "Delete", "insert": "Insert", "home": "Home", "end": "End", "prior": "Page Up", "next": "Page Down",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down", "print": "Print", "pause": "Pause", "menu": "Menu",
    "comma": ",", "period": ".", "minus": "-", "plus": "+", "slash": "/", "backslash": "\\", "semicolon": ";",
    "apostrophe": "'", "grave": "`", "equal": "=", "less": "<", "greater": ">", "numbersign": "#", "asterisk": "*",
    "bracketleft": "[", "bracketright": "]", "adiaeresis": "Ä", "odiaeresis": "Ö", "udiaeresis": "Ü", "ssharp": "ß",
    "alt_l": "Alt", "alt_r": "Alt (right)", "super_l": "Super", "super_r": "Super (right)",
    "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse:274": "Middle drag",
    "mouse_up": "Scroll up", "mouse_down": "Scroll down", "mouse_left": "Scroll left", "mouse_right": "Scroll right",
    "switch:on:lid switch": "Lid closed", "switch:off:lid switch": "Lid opened",
    "xf86audioraisevolume": "Volume up", "xf86audiolowervolume": "Volume down", "xf86audiomute": "Mute",
    "xf86audiomicmute": "Mic mute", "xf86monbrightnessup": "Brightness up", "xf86monbrightnessdown": "Brightness down",
    "xf86audioplay": "Play", "xf86audiopause": "Pause", "xf86audionext": "Next track", "xf86audioprev": "Previous track",
    "xf86audiostop": "Stop"
}

var arrowKeys = ["left", "right", "up", "down"]

function modmask(mods) {
    return modifiers.filter(item => (mods || []).indexOf(item.name) >= 0).reduce((mask, item) => mask | item.bit, 0)
}

function modNames(mask) {
    return modifiers.filter(item => (mask & item.bit) !== 0).map(item => item.name)
}

function keyLabel(key) {
    const text = String(key || "")
    const known = keyLabels[text.toLowerCase()]
    if (known) return known
    if (/^XF86/i.test(text)) return text.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2")
    if (/^switch:(on|off):/i.test(text)) return text.slice(text.indexOf(":", 7) + 1) + (/^switch:on/i.test(text) ? " on" : " off")
    if (text.length === 1 || /^F\d+$/i.test(text)) return text.toUpperCase()
    return text.charAt(0).toUpperCase() + text.slice(1)
}

function modLabels(mask) {
    return modifiers.filter(item => (mask & item.bit) !== 0).map(item => item.label)
}

function keyParts(mask, key) {
    return modLabels(mask).concat([keyLabel(key)])
}

function comboText(mask, key) {
    return keyParts(mask, key).join("+")
}

// Same combination as Hyprland compares it (keys are case-insensitive).
function sameCombo(bind, mask, key) {
    return bind.modmask === mask && String(bind.key).toLowerCase() === String(key).toLowerCase()
}

function parseBinds(text) {
    try {
        const data = JSON.parse(text)
        return Array.isArray(data) ? data.filter(item => item && typeof item === "object" && typeof item.key === "string") : []
    } catch (error) {
        return []
    }
}

function titleOf(title, group, extra) {
    return Object.assign({ title: title, group: group || titleGroups[title] || "other" }, extra || {})
}

function describeExec(arg) {
    const text = String(arg || "")
    let match = text.match(/ipc call (\w+) (\w+)/)
    if (match) {
        if (match[1] === "switcher") return titleOf(match[2] === "next" ? "Next window" : match[2] === "previous" ? "Previous window" : "Switch to selected window")
        if (match[1] === "power") return titleOf(match[2] === "lidClosed" ? "Lid closed" : "Lid opened")
        if (match[1] === "recording") return titleOf(/ toggle screen\b/.test(text) ? "Record the screen" : "Record a region")
        if (match[1] === "kbdBacklight") return titleOf(match[2] === "up" ? "Keyboard light up"
            : match[2] === "down" ? "Keyboard light down" : "Keyboard light on or off")
        if (panelTitles[match[1]]) return titleOf(panelTitles[match[1]])
    }
    match = text.match(/launch-default\.sh (terminal|browser|files)\b/)
    if (match) return titleOf(match[1] === "terminal" ? "Terminal" : match[1] === "browser" ? "Web browser" : "File manager")
    match = text.match(/screenshot\.sh (region|screen|window)\b/)
    if (match) return titleOf(match[1] === "region" ? "Screenshot of a region" : match[1] === "screen" ? "Screenshot of the screen" : "Screenshot of a window")
    if (/reload-shell\.sh\b/.test(text)) return titleOf("Restart buchhwin-shell")
    if (/session-action\.sh lock\b/.test(text)) return titleOf("Lock screen")
    if (/launch-kitty\.sh\b/.test(text)) return titleOf("Kitty", "apps")
    if (/launch-brave\.sh\b/.test(text)) return titleOf("Brave", "apps")
    match = text.match(/^gtk-launch ([A-Za-z0-9._-]+)$/)
    if (match) return titleOf("Open " + match[1], "apps")
    if (/^wpctl set-volume\b.*\+$/.test(text)) return titleOf("Volume up")
    if (/^wpctl set-volume\b.*-$/.test(text)) return titleOf("Volume down")
    if (/^wpctl set-mute @DEFAULT_AUDIO_SINK@/.test(text)) return titleOf("Mute audio")
    if (/^wpctl set-mute @DEFAULT_AUDIO_SOURCE@/.test(text)) return titleOf("Mute microphone")
    if (/^brightnessctl\b.*\+$/.test(text)) return titleOf("Brightness up")
    if (/^brightnessctl\b.*-$/.test(text)) return titleOf("Brightness down")
    match = text.match(/^playerctl (play-pause|next|previous)$/)
    if (match) return titleOf(match[1] === "play-pause" ? "Play or pause" : match[1] === "next" ? "Next track" : "Previous track")
    return titleOf(text, "other", { raw: true })
}

var focusDirections = { l: "left", r: "right", u: "up", d: "down" }

// { title, group, raw } for one bind of `hyprctl -j binds`.
function describe(bind) {
    const arg = String(bind.arg || "")
    if (bind.has_description && bind.description) {
        const text = String(bind.description)
        if (text.indexOf(customPrefix) === 0) return titleOf(text.slice(customPrefix.length), "custom")
        const workspace = /^(Go to|Move window to) workspace \d+$/.test(text)
        return titleOf(text, workspace ? "workspaces" : /^Move focus /.test(text) ? "windows" : undefined)
    }
    switch (bind.dispatcher) {
    case "exec": return describeExec(arg)
    case "killactive": return titleOf("Close window")
    case "fullscreen": return titleOf(arg === "1" ? "Maximize" : "Fullscreen")
    case "togglefloating": return titleOf("Toggle floating")
    case "resizeactive": return titleOf("Resize window")
    case "movefocus": return titleOf("Move focus " + (focusDirections[arg] || arg), "windows")
    case "workspace": return titleOf("Go to workspace " + arg, "workspaces")
    case "movetoworkspace": return titleOf("Move window to workspace " + arg + " and follow", "workspaces")
    case "movetoworkspacesilent": return titleOf("Move window to workspace " + arg, "workspaces")
    case "exit": return titleOf("Exit Hyprland")
    case "mouse": return titleOf(arg === "movewindow" ? "Move window" : arg === "resizewindow" ? "Resize window" : arg, "windows")
    case "__lua": return titleOf("Lua action", "other", { raw: true })
    default: return titleOf((bind.dispatcher + " " + arg).trim(), "other", { raw: true })
    }
}

// Rows for the overview; custom shortcuts from the store take their titles
// from `labelFor(entry)` (app name or command).
function rows(binds, custom, labelFor) {
    return (binds || []).filter(bind => !bind.submap).map(bind => {
        const mask = Number(bind.modmask) || 0
        const entry = (custom || []).find(item => sameCombo(bind, modmask(item.mods), item.key))
        const info = entry ? titleOf(labelFor ? labelFor(entry) : entryLabel(entry), "custom") : describe(bind)
        // Alt_L with the Alt modifier (the switcher's release bind) reads "Release Alt".
        let keys = keyParts(mask, bind.key)
        if (keys.length > 1 && keys.indexOf(keys[keys.length - 1]) < keys.length - 1) keys = keys.slice(0, -1)
        if (bind.release) keys = keys.slice(0, -1).concat(["Release " + keys[keys.length - 1]])
        return {
            modmask: mask, key: bind.key, keys: keys, combo: keys.join("+"),
            title: info.title, group: info.group, raw: info.raw === true,
            command: bind.dispatcher === "exec" ? String(bind.arg || "") : entry ? commandFor(entry, {}) : ""
        }
    })
}

// Several binds of one family (workspaces 1–9, arrow keys) become one row.
function family(row) {
    const key = String(row.key).toLowerCase()
    let match = row.title.match(/^(Go to workspace|Move window to workspace) (\d+)$/)
    if (match && /^\d$/.test(key)) return { id: match[1], title: match[1], kind: "digits" }
    match = row.title.match(/^(Move focus) (left|right|up|down)$/)
    if (match && arrowKeys.indexOf(key) >= 0) return { id: match[1], title: match[1], kind: "arrows" }
    if (row.title === "Resize window" && arrowKeys.indexOf(key) >= 0) return { id: row.title, title: row.title, kind: "arrows" }
    return null
}

function condense(list) {
    const result = []
    const merged = {}
    for (const row of list) {
        const info = family(row)
        if (!info) { result.push(row); continue }
        const id = info.id + "|" + row.modmask + "|" + row.group
        if (!merged[id]) {
            merged[id] = { info: info, members: [] }
            result.push(merged[id])
        }
        merged[id].members.push(row)
    }
    return result.reduce((out, item) => {
        if (!item.members) return out.concat([item])
        if (item.members.length < 2) return out.concat(item.members)
        const first = item.members[0]
        let keyText = "Arrows"
        let title = item.info.title
        if (item.info.kind === "digits") {
            const digits = item.members.map(row => Number(row.key)).sort((a, b) => a - b)
            keyText = digits[0] + "–" + digits[digits.length - 1]
            title += " " + keyText
        }
        return out.concat([Object.assign({}, first, {
            keys: modLabels(first.modmask).concat([keyText]),
            combo: modLabels(first.modmask).concat([keyText]).join("+"),
            title: title, command: ""
        })])
    }, [])
}

// [{ id, title, rows }] in group order, filtered by the search text.
function grouped(list, query) {
    const q = String(query || "").trim().toLowerCase()
    const condensed = condense(list)
    return groups.map(group => ({
        id: group.id, title: group.title,
        rows: condensed.filter(row => row.group === group.id
            && (!q.length || (row.title + " " + row.combo + " " + row.command + " " + group.title).toLowerCase().indexOf(q) >= 0))
    })).filter(group => group.rows.length > 0)
}

// Custom shortcuts ------------------------------------------------------------

function validKey(key) {
    return /^[A-Za-z0-9_]+$/.test(String(key || ""))
}

// Keys that make sense without a modifier (anything else would stop typing).
function standaloneKey(key) {
    return /^(F([1-9]|1\d|2[0-4])|XF86\w+|Print|Pause|Menu|Insert|Scroll_Lock)$/i.test(String(key))
}

function comboError(mods, key) {
    if (!validKey(key)) return "Press a key combination"
    if (!(mods || []).length && !standaloneKey(key)) return "Add Super, Ctrl or Alt to this key"
    if ((mods || []).length === 1 && mods[0] === "SHIFT" && !standaloneKey(key)) return "Add Super, Ctrl or Alt to this key"
    return ""
}

function commandError(command) {
    const text = String(command || "").trim()
    if (!text.length) return "Enter a command"
    if (/[\x00-\x1f]/.test(text)) return "Commands must be on one line"
    if (text.indexOf(";") >= 0) return "Use && instead of ; or put the commands in a script"
    if (text.length > 400) return "The command is too long"
    return ""
}

function validAppId(id) {
    return /^[A-Za-z0-9._-]+$/.test(String(id || ""))
}

function normalizeEntry(item) {
    if (!item || typeof item !== "object" || !Array.isArray(item.mods)) return null
    const mods = modifiers.map(mod => mod.name).filter(name => item.mods.map(mod => String(mod).toUpperCase()).indexOf(name) >= 0)
    if (item.mods.length !== mods.length || comboError(mods, item.key)) return null
    const key = String(item.key)
    if (typeof item.app === "string" && validAppId(item.app)) return { mods: mods, key: key, app: item.app }
    if (typeof item.command === "string" && !commandError(item.command)) return { mods: mods, key: key, command: item.command.trim() }
    return null
}

function parseStore(text) {
    let data = null
    try { data = JSON.parse(text) } catch (error) { return [] }
    const list = data && Array.isArray(data.custom) ? data.custom : []
    const result = []
    for (const item of list) {
        const entry = normalizeEntry(item)
        if (entry && !result.some(other => sameCombo({ modmask: modmask(other.mods), key: other.key }, modmask(entry.mods), entry.key)))
            result.push(entry)
    }
    return result
}

function serializeStore(list) {
    return JSON.stringify({ configVersion: 1, custom: list }, null, 2) + "\n"
}

function entryLabel(entry) {
    return entry.app ? entry.app : entry.command
}

function comboOf(entry) {
    return comboText(modmask(entry.mods), entry.key)
}

// Apps start through gtk-launch unless the launcher has a session script
// (Kitty, Brave); `overrides` maps desktop ids to script paths.
function commandFor(entry, overrides) {
    if (!entry.app) return entry.command
    const script = (overrides || {})[entry.app]
    if (!script) return "gtk-launch " + entry.app
    return /^[A-Za-z0-9_\/.+-]+$/.test(script) ? script : "'" + script.replace(/'/g, "'\\''") + "'"
}

// Bind description; the prefix marks the shell's own binds. Hyprlang
// separators and variables are replaced so the legacy form stays intact.
function descriptionFor(entry) {
    const text = entryLabel(entry).replace(/[,;#$\x00-\x1f]/g, " ").replace(/\s+/g, " ").trim()
    return customPrefix + (text.length > 60 ? text.slice(0, 59) + "…" : text)
}

// Title of the bind already using this combination, or "".
function conflictFor(binds, mods, key) {
    const mask = modmask(mods)
    const bind = (binds || []).find(item => !item.submap && sameCombo(item, mask, key))
    return bind ? describe(bind).title : ""
}

function ownBind(bind) {
    return bind.has_description === true && String(bind.description || "").indexOf(customPrefix) === 0
}

// What to change so Hyprland matches the store: remove stale own binds (never
// a combination that another bind also uses), add missing ones, and report
// entries whose combination is taken by a bind from the config.
function syncPlan(binds, custom) {
    const active = (binds || []).filter(bind => !bind.submap)
    const wanted = (custom || []).map(entry => ({ entry: entry, mask: modmask(entry.mods), description: descriptionFor(entry) }))
    const unbind = []
    const bind = []
    const conflicts = []
    for (const current of active.filter(ownBind)) {
        const keep = wanted.some(item => sameCombo(current, item.mask, item.entry.key) && item.description === current.description)
        const foreign = active.some(other => !ownBind(other) && sameCombo(other, current.modmask, current.key))
        if (!keep && !foreign && !unbind.some(item => sameCombo({ modmask: modmask(item.mods), key: item.key }, current.modmask, current.key)))
            unbind.push({ mods: modNames(current.modmask), key: current.key })
    }
    for (const item of wanted) {
        const same = active.filter(current => sameCombo(current, item.mask, item.entry.key))
        if (same.some(current => !ownBind(current))) conflicts.push(comboOf(item.entry))
        else if (!same.some(current => current.description === item.description)) bind.push(item.entry)
    }
    return { unbind: unbind, bind: bind, conflicts: conflicts }
}

// Default key combinations --------------------------------------------------

// What each built-in shortcut sits on *by default*, read out of
// `hypr/hyprland.lua`.
//
// It has to be read rather than asked for. With a Lua configuration every bind
// is a closure, so `hyprctl -j binds` answers `dispatcher: "__lua"` and an
// internal index: the *name* of a shortcut is readable from outside, the
// *action* is not, and neither is the combination it started on once it has
// been moved. The configuration is therefore the only place that knows, and
// the string has to match it exactly - which is why this reads the file rather
// than rebuilding the combination from a modmask and hoping the spelling and
// the order of the modifiers agree.
//
// Descriptions are deliberately **not** the key: four bindings are called
// "Resize window".
// One spelling to compare two combinations by. The configuration writes
// "SUPER + D" and "Print"; `hyprctl -j binds` answers a modmask and "D" or
// "PRINT". Neither the case nor the order of the modifiers can be relied on,
// so both sides are reduced to sorted modifiers plus an upper-case key.
// Measured against the real configuration: all 56 built-in bindings match this
// way, and none of them matched by order or by description.
var MOD_NAMES = ["SUPER", "SHIFT", "CTRL", "ALT"]

function canonicalCombo(text) {
    const parts = String(text || "").split("+").map(part => part.trim().toUpperCase()).filter(part => part.length)
    const mods = parts.filter(part => MOD_NAMES.indexOf(part) >= 0).sort()
    const keys = parts.filter(part => MOD_NAMES.indexOf(part) < 0)
    return mods.concat(keys).join("+")
}

// The same, from what the compositor reports.
function canonicalBind(modmask, key) {
    const mask = Number(modmask) || 0
    const mods = []
    if (mask & 64) mods.push("SUPER")
    if (mask & 1) mods.push("SHIFT")
    if (mask & 4) mods.push("CTRL")
    if (mask & 8) mods.push("ALT")
    return mods.sort().concat([String(key || "").toUpperCase()]).join("+")
}

function parseDefaults(text) {
    const result = []
    const pattern = /hl\.bind\(keyFor\("([^"]+)"\)[\s\S]*?description\s*=\s*"([^"]*)"/g
    let match
    while ((match = pattern.exec(String(text || ""))) !== null) {
        const combo = match[1].trim()
        if (!combo.length || result.some(item => item.combo === combo)) continue
        // `combo` verbatim, because hyprland.lua looks the override up by the
        // exact string it wrote; `canon` for comparing against a live bind.
        result.push({ combo: combo, canon: canonicalCombo(combo), description: match[2] })
    }
    return result
}

// `default = replacement` per line, the format hyprland.lua parses by hand.
// Comments and blank lines are ignored on both sides, so a file a person has
// edited survives a round trip through the shell.
function parseKeyOverrides(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        if (/^\s*#/.test(line)) continue
        const match = line.match(/^\s*([^=]+?)\s*=\s*(.+?)\s*$/)
        if (!match) continue
        const from = match[1].trim(), to = match[2].trim()
        if (from.length && to.length) result[from] = to
    }
    return result
}

function serializeKeyOverrides(map) {
    const lines = ["# buchhwin-shell: where a shortcut sits, written by Settings > Shortcuts.",
                   "# One `default = replacement` per line. What a shortcut does stays in",
                   "# hypr/hyprland.lua; this file only moves it."]
    for (const from of Object.keys(map || {}).sort()) {
        const to = String(map[from] || "").trim()
        if (to.length && to !== from) lines.push(from + " = " + to)
    }
    return lines.join("\n") + "\n"
}

// Key capture ----------------------------------------------------------------

// Qt key codes (Qt::Key) → keysym names Hyprland understands.
var qtNames = {
    0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "BackSpace", 0x01000004: "Return", 0x01000005: "Return",
    0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print", 0x01000010: "Home",
    0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
    0x01000016: "Prior", 0x01000017: "Next", 0x01000055: "Menu", 0x20: "space",
    0x2c: "comma", 0x2d: "minus", 0x2e: "period", 0x2f: "slash", 0x3b: "semicolon", 0x3c: "less", 0x3d: "equal",
    0x3e: "greater", 0x5b: "bracketleft", 0x5c: "backslash", 0x5d: "bracketright", 0x27: "apostrophe",
    0x60: "grave", 0x23: "numbersign", 0x2b: "plus", 0x2a: "asterisk",
    0xc4: "adiaeresis", 0xd6: "odiaeresis", 0xdc: "udiaeresis", 0xdf: "ssharp",
    0x01000070: "XF86AudioLowerVolume", 0x01000071: "XF86AudioMute", 0x01000072: "XF86AudioRaiseVolume",
    0x01000080: "XF86AudioPlay", 0x01000081: "XF86AudioStop", 0x01000082: "XF86AudioPrev", 0x01000083: "XF86AudioNext",
    0x01000085: "XF86AudioPause", 0x01000086: "XF86AudioPlay", 0x010000b2: "XF86MonBrightnessUp",
    0x010000b3: "XF86MonBrightnessDown"
}
// Shift, Control, Meta, Alt, CapsLock, NumLock, ScrollLock, Super, Hyper, AltGr.
var qtModifierKeys = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025, 0x01000026,
                      0x01000053, 0x01000054, 0x01000056, 0x01000057, 0x01001103]

// { cancel } for Escape, { waiting } while only modifiers are held,
// { mods, key } for a combination, { unsupported } otherwise. Shifted
// number-row symbols fall back to the digit through the xkb keycode.
function captureKey(qtKey, qtModifiers, nativeScanCode) {
    const mods = []
    if (qtModifiers & 0x10000000) mods.push("SUPER")
    if (qtModifiers & 0x04000000) mods.push("CTRL")
    if (qtModifiers & 0x08000000) mods.push("ALT")
    if (qtModifiers & 0x02000000) mods.push("SHIFT")
    if (qtKey === 0x01000000 && !mods.length) return { cancel: true }
    if (qtModifierKeys.indexOf(qtKey) >= 0) return { waiting: true, mods: mods }
    let key = ""
    if ((qtKey >= 0x41 && qtKey <= 0x5a) || (qtKey >= 0x30 && qtKey <= 0x39)) key = String.fromCharCode(qtKey)
    else if (qtKey >= 0x01000030 && qtKey <= 0x01000047) key = "F" + (qtKey - 0x01000030 + 1)
    else if (nativeScanCode >= 10 && nativeScanCode <= 19 && mods.indexOf("SHIFT") >= 0) key = String((nativeScanCode - 9) % 10)
    else key = qtNames[qtKey] || ""
    return key.length ? { mods: mods, key: key } : { unsupported: true, mods: mods }
}
