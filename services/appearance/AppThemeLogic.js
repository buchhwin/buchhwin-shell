.pragma library

// Apps follow the shell theme and accent (Settings > Appearance, opt-in). KDE/Qt
// apps get the Breeze colour scheme and/or the shell accent through
// plasma-apply-colorscheme, GTK apps and the settings portal the GNOME
// interface keys through gsettings. The values the session found before its
// first change (including a backup of every kdeglobals colour entry, see
// scripts/apptheme-restore.py --snapshot) are saved in apptheme.json and given
// back when the options are turned off (or at logout and, after a crash, at the
// next Plasma login: scripts/apptheme-restore.py).
// Unit tested (tests/qml/AppThemeTest.qml).

var DARK_SCHEME = "BreezeDark"
var LIGHT_SCHEME = "BreezeLight"
// Plasma's default when kdeglobals has no ColorScheme key.
var DEFAULT_SCHEME = "BreezeLight"
var GNOME_SCHEMA = "org.gnome.desktop.interface"
// Themes built into GTK itself; they have no folder in /usr/share/themes.
var BUILTIN_GTK_THEMES = ["Adwaita", "Adwaita-dark", "HighContrast", "HighContrastInverse"]
var STATE_VERSION = 2
// Tells running KDE apps to reload their palette (KGlobalSettings::PaletteChanged).
var NOTIFY_COMMAND = ["dbus-send", "--session", "--type=signal", "/KGlobalSettings",
                      "org.kde.KGlobalSettings.notifyChange", "int32:0", "int32:0"]
// kdeglobals entries of the colour backup; same rules as apptheme-restore.py.
var GENERAL_KEYS = ["ColorScheme", "ColorSchemeHash", "AccentColor", "LastUsedCustomAccentColor",
                    "accentColorFromWallpaper", "TintFactor", "TitlebarIsAccentColored"]
var KDE_KEYS = ["contrast", "frameContrast"]
var AUTOSTART_NAME = "buchhwin-shell-apptheme-restore.desktop"

// "auto" is dark from 19:00 to 07:00 (same rule as theme/Colors.qml).
function effectiveDark(theme, hours) {
    return theme === "dark" || (theme === "auto" && (hours >= 19 || hours < 7))
}

function isHex(value) { return /^#[0-9a-fA-F]{6}$/.test(String(value)) }

// kdeglobals stores colours as "R,G,B" (optionally ",A"); "" when unset or invalid.
function colorToHex(value) {
    const text = String(value === undefined || value === null ? "" : value).trim()
    if (isHex(text)) return text.toLowerCase()
    const match = /^(\d{1,3}),(\d{1,3}),(\d{1,3})(,\d{1,3})?$/.exec(text)
    if (!match) return ""
    const parts = match.slice(1, 4).map(Number)
    if (parts.some(part => part > 255)) return ""
    return "#" + parts.map(part => ("0" + part.toString(16)).slice(-2)).join("")
}

function hexToRgb(hex) {
    const value = colorToHex(hex)
    if (!value.length) return ""
    return [1, 3, 5].map(index => parseInt(value.slice(index, index + 2), 16)).join(",")
}

// gsettings prints strings quoted: 'prefer-dark'.
function unquote(value) {
    const text = String(value === undefined || value === null ? "" : value).trim()
    const match = /^'(.*)'$/.exec(text) || /^"(.*)"$/.exec(text)
    return match ? match[1] : text
}

// `plasma-apply-colorscheme --list-schemes`: " * Name" lines, the active one
// ends with "(current color scheme)".
function parseSchemes(text) {
    const result = { schemes: [], current: "" }
    for (const line of String(text || "").split("\n")) {
        const match = /^\s*\*\s+(\S.*?)\s*$/.exec(line)
        if (!match) continue
        let name = match[1]
        const marked = /\s*\(current colou?r scheme\)$/i.exec(name)
        if (marked) {
            name = name.slice(0, marked.index)
            result.current = name
        }
        if (name.length && result.schemes.indexOf(name) < 0) result.schemes.push(name)
    }
    return result
}

// `gsettings range`: "enum" followed by quoted values.
function parseRange(text) {
    return String(text || "").split("\n").map(unquote).filter(line => line.length && line !== "enum")
}

// A kdeglobals entry that belongs to the colour backup.
function managedEntry(group, key) {
    if (!Array.isArray(group) || !group.length || !group.every(part => typeof part === "string")) return false
    if (typeof key !== "string" || !/^[A-Za-z][A-Za-z0-9_]*$/.test(key)) return false
    const colorGroup = /^(Colors|ColorEffects):[A-Za-z]+$/
    if (group.length === 1) {
        if (colorGroup.test(group[0]) || group[0] === "WM") return true
        return (group[0] === "General" && GENERAL_KEYS.indexOf(key) >= 0) || (group[0] === "KDE" && KDE_KEYS.indexOf(key) >= 0)
    }
    return group.length === 2 && /^Colors:[A-Za-z]+$/.test(group[0]) && /^[A-Za-z]+$/.test(group[1])
}

function validEntry(entry) {
    return Array.isArray(entry) && entry.length === 3 && managedEntry(entry[0], entry[1])
        && typeof entry[2] === "string" && /^[^\\\x00-\x1f\x7f]{0,200}$/.test(entry[2])
}

// Colour backup ({ entries: [[group, key, value], ...] }); null when invalid.
function validBackup(backup) {
    if (!backup || typeof backup !== "object" || !Array.isArray(backup.entries)) return null
    return { entries: backup.entries.filter(validEntry).map(entry => [entry[0].slice(), entry[1], entry[2]]) }
}

function parseSnapshot(text) {
    try { return validBackup(JSON.parse(String(text || "").trim())) } catch (error) { return null }
}

// Output of the service's read-only query script: "[section]" headers
// followed by that command's output.
function parseQuery(text) {
    const sections = {}
    let current = ""
    for (const line of String(text || "").split("\n")) {
        const header = /^\[(\w+)\]$/.exec(line.trim())
        if (header) {
            current = header[1]
            sections[current] = sections[current] || []
        } else if (current.length) {
            sections[current].push(line)
        }
    }
    const joined = name => (sections[name] || []).join("\n")
    const lines = name => (sections[name] || []).map(line => line.trim()).filter(line => line.length)
    const listed = parseSchemes(joined("schemes"))
    const tools = lines("tools").map(path => path.split("/").pop())
    const seen = {}
    // ".../themes/<name>/gtk-3.0/gtk.css": key-binding themes have no gtk.css.
    const themes = lines("themes")
        .map(path => /([^/]+)\/gtk-3\.0(\/gtk\.css)?\/?$/.exec(path))
        .filter(match => match && !seen[match[1]] && (seen[match[1]] = true))
        .map(match => match[1])
    return {
        plasma: tools.indexOf("plasma-apply-colorscheme") >= 0,
        gsettings: tools.indexOf("gsettings") >= 0,
        colorScheme: lines("colorScheme")[0] || listed.current || DEFAULT_SCHEME,
        accentColor: colorToHex(lines("accentColor")[0] || ""),
        kdeColors: parseSnapshot(joined("kdeColors")),
        schemes: listed.schemes,
        gtkColorScheme: unquote(lines("gtkColorScheme")[0] || ""),
        colorSchemeRange: parseRange(joined("colorSchemeRange")),
        gtkTheme: unquote(lines("gtkTheme")[0] || ""),
        themes: themes
    }
}

function isDarkThemeName(name) {
    return /[-_ ]dark$/i.test(String(name || ""))
}

// The KDE colour scheme for the theme; "" when that scheme is not installed.
function colorSchemeTarget(dark, schemes) {
    const name = dark ? DARK_SCHEME : LIGHT_SCHEME
    return (schemes || []).indexOf(name) >= 0 ? name : ""
}

// GNOME color-scheme key; older schemas have no prefer-light.
function gtkColorSchemeTarget(dark, range) {
    if (dark) return "prefer-dark"
    const values = range || []
    return !values.length || values.indexOf("prefer-light") >= 0 ? "prefer-light" : "default"
}

// A theme that already matches keeps its name (even an uninstalled one the
// user chose), then the other variant of the same theme, then Breeze. ""
// leaves the key alone.
function gtkThemeTarget(current, dark, installed) {
    const available = (installed || []).concat(BUILTIN_GTK_THEMES)
    const name = String(current || "")
    if (name.length && isDarkThemeName(name) === dark) return name
    if (name.length) {
        const candidates = dark ? [name + "-dark", name + "-Dark", name + "_dark"] : [name.replace(/[-_ ]dark$/i, "")]
        for (const candidate of candidates) if (available.indexOf(candidate) >= 0) return candidate
    }
    const fallback = dark ? "Breeze-Dark" : "Breeze"
    return (installed || []).indexOf(fallback) >= 0 ? fallback : ""
}

function colorSchemeCommand(name) { return ["plasma-apply-colorscheme", name] }
function gsettingsCommand(key, value) { return ["gsettings", "set", GNOME_SCHEMA, key, value] }

// Values to set for the theme, from a parsed query.
function targets(dark, query) {
    const q = query || {}
    return {
        colorScheme: q.plasma ? colorSchemeTarget(dark, q.schemes) : "",
        gtkColorScheme: q.gsettings ? gtkColorSchemeTarget(dark, q.colorSchemeRange) : "",
        gtkTheme: q.gsettings ? gtkThemeTarget(q.gtkTheme, dark, q.themes) : ""
    }
}

function differs(values, current, key) {
    return !!values && typeof values[key] === "string" && values[key].length > 0 && values[key] !== (current || {})[key]
}

function gnomeCommands(values, current) {
    const commands = []
    if (differs(values, current, "gtkColorScheme")) commands.push(gsettingsCommand("color-scheme", values.gtkColorScheme))
    if (differs(values, current, "gtkTheme")) commands.push(gsettingsCommand("gtk-theme", values.gtkTheme))
    return commands
}

// Commands that change what differs; empty targets are skipped. `current`
// may be null (then every non-empty value is set, as at logout).
function commandsFor(values, current) {
    const commands = differs(values, current, "colorScheme") ? [colorSchemeCommand(values.colorScheme)] : []
    return commands.concat(gnomeCommands(values, current))
}

function kwriteCommand(group, key, value) {
    let command = ["kwriteconfig6", "--file", "kdeglobals"]
    for (const part of group) command = command.concat(["--group", part])
    command = command.concat(["--key", key])
    // "--" keeps values such as "-0.1" from being read as options.
    return command.concat(value === undefined ? ["--delete", "--", ""] : ["--", value])
}

// kwriteconfig6 calls that turn the current colour entries back into the
// backup (entries added since are deleted), then the palette notification.
function kdeRestoreCommands(backup, current) {
    const wanted = validBackup(backup)
    if (!wanted) return []
    const now = validBackup(current) || { entries: [] }
    const id = entry => JSON.stringify([entry[0], entry[1]])
    const wantedValues = {}
    const nowValues = {}
    for (const entry of wanted.entries) wantedValues[id(entry)] = entry[2]
    for (const entry of now.entries) nowValues[id(entry)] = entry[2]
    const commands = []
    for (const entry of now.entries)
        if (!(id(entry) in wantedValues)) commands.push(kwriteCommand(entry[0], entry[1]))
    for (const entry of wanted.entries)
        if (nowValues[id(entry)] !== entry[2]) commands.push(kwriteCommand(entry[0], entry[1], entry[2]))
    if (commands.length) commands.push(NOTIFY_COMMAND.slice())
    return commands
}

// Two commands are the same call (used to avoid a second notify signal).
function sameCommand(a, b) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length
        && a.every((part, index) => part === b[index])
}

// KDE colours towards `desired` ({ colorScheme, accentColor }): the scheme
// with the accent when the scheme changes, only the accent when it alone
// differs. Removing an accent Plasma did not have restores the backup first.
function kdeCommands(desired, current, saved) {
    const now = current || {}
    const scheme = String(desired.colorScheme || "")
    const accent = colorToHex(desired.accentColor)
    const commands = []
    let schemeNow = now.colorScheme
    let accentNow = colorToHex(now.accentColor)
    if (!accent.length && accentNow.length && saved && validBackup(saved.kdeColors)) {
        const restore = kdeRestoreCommands(saved.kdeColors, now.kdeColors)
        for (const command of restore) commands.push(command)
        schemeNow = saved.colorScheme
        accentNow = colorToHex(saved.accentColor)
    }
    // An unknown or unchanged scheme must not swallow the accent: without a
    // scheme to switch to, the accent alone is applied.
    if (scheme.length && scheme !== schemeNow)
        commands.push(accent.length ? ["plasma-apply-colorscheme", "--accent-color", accent, scheme] : colorSchemeCommand(scheme))
    else if (accent.length && accent !== accentNow)
        commands.push(["plasma-apply-colorscheme", "--accent-color", accent])
    return commands
}

// The query as it would read after the commands ran. Test sessions never run
// them, so their next plan starts from these simulated values.
function afterCommands(query, commands, saved) {
    const result = Object.assign({}, query || {})
    const setColors = () => {
        const entries = ((validBackup(result.kdeColors) || { entries: [] }).entries)
            .filter(entry => !(entry[0].length === 1 && entry[0][0] === "General" && (entry[1] === "ColorScheme" || entry[1] === "AccentColor")))
        entries.push([["General"], "ColorScheme", result.colorScheme])
        if (result.accentColor) entries.push([["General"], "AccentColor", hexToRgb(result.accentColor)])
        result.kdeColors = { entries: entries }
    }
    for (const command of commands || []) {
        if (command[0] === "plasma-apply-colorscheme") {
            const args = command.slice(1)
            const flag = args.indexOf("--accent-color")
            if (flag >= 0) result.accentColor = colorToHex(args.splice(flag, 2)[1])
            if (args.length) result.colorScheme = args[0]
            setColors()
        } else if (command[0] === "kwriteconfig6" && saved) {
            result.colorScheme = saved.colorScheme
            result.accentColor = colorToHex(saved.accentColor)
            result.kdeColors = validBackup(saved.kdeColors)
        } else if (command[3] === "color-scheme") {
            result.gtkColorScheme = command[4]
        } else if (command[3] === "gtk-theme") {
            result.gtkTheme = command[4]
        }
    }
    return result
}

// Values worth restoring; a tool that is missing has nothing to restore.
function snapshot(query) {
    const q = query || {}
    return {
        colorScheme: q.plasma ? String(q.colorScheme || "") : "",
        accentColor: q.plasma ? colorToHex(q.accentColor) : "",
        kdeColors: q.plasma ? validBackup(q.kdeColors) : null,
        gtkColorScheme: q.gsettings ? String(q.gtkColorScheme || "") : "",
        gtkTheme: q.gsettings ? String(q.gtkTheme || "") : ""
    }
}

function emptyState() {
    return { version: STATE_VERSION, applied: false, restoreOnLogout: true, saved: null, restore: [] }
}

function validSaved(saved) {
    if (!saved || typeof saved !== "object") return null
    const text = key => typeof saved[key] === "string" ? saved[key] : ""
    // Same key order as snapshot().
    const result = { colorScheme: text("colorScheme"), accentColor: colorToHex(saved.accentColor),
                     kdeColors: validBackup(saved.kdeColors), gtkColorScheme: text("gtkColorScheme"), gtkTheme: text("gtkTheme") }
    return result.colorScheme.length || result.gtkColorScheme.length || result.gtkTheme.length ? result : null
}

// Commands apptheme-restore.py may take from the state file; with a colour
// backup it restores kdeglobals from the backup instead of the saved scheme.
function restoreList(saved) {
    if (!saved) return []
    return saved.kdeColors ? gnomeCommands(saved, null) : commandsFor(saved, null)
}

// apptheme.json; unreadable files count as "nothing applied".
function parseState(text) {
    const state = emptyState()
    let data = null
    try { data = JSON.parse(String(text || "")) } catch (error) { return state }
    if (!data || typeof data !== "object") return state
    state.saved = validSaved(data.saved)
    state.applied = data.applied === true && state.saved !== null
    state.restoreOnLogout = data.restoreOnLogout !== false
    state.restore = state.applied ? restoreList(state.saved) : []
    return state
}

function stateText(state) {
    const s = state || emptyState()
    return JSON.stringify({ version: STATE_VERSION, applied: s.applied === true, restoreOnLogout: s.restoreOnLogout !== false,
                            saved: s.saved || null, restore: s.restore || [] }, null, 2) + "\n"
}

function forgottenState(restoreOnLogout) {
    return { version: STATE_VERSION, applied: false, restoreOnLogout: restoreOnLogout !== false, saved: null, restore: [] }
}

// What to do now. `options`: followTheme, accentEnabled, accent (shell accent),
// dark, restoreOnLogout. Enabled: save the current values once (unless an
// earlier run already changed them), then set the wanted values; what an
// option that is off no longer sets goes back to the saved value. Disabled
// after a change: give the saved values back. Returns the commands, the state
// to keep, whether it must be written before ("apply") or after ("restore")
// the commands run, and an error when the accent cannot be applied safely.
function plan(options, query, state) {
    const o = options || {}
    const previous = state || emptyState()
    const keepOnLogout = o.restoreOnLogout !== false
    const follow = o.followTheme === true
    const accentOn = o.accentEnabled === true && isHex(o.accent)
    const q = query || {}
    if (follow || accentOn) {
        const saved = previous.applied && previous.saved ? previous.saved : snapshot(q)
        const hasSaved = validSaved(saved) !== null
        let error = ""
        let commands = follow ? gnomeCommands(targets(o.dark, q), q)
            : previous.applied && previous.saved ? gnomeCommands(saved, q) : []
        if (q.plasma) {
            // Without a backup Plasma's colours could not be given back exactly.
            const canAccent = accentOn && !!saved.kdeColors
            if (accentOn && !canAccent) error = "Plasma colors could not be backed up; the accent is not applied."
            const desired = {
                colorScheme: follow ? colorSchemeTarget(o.dark, q.schemes) : saved.colorScheme,
                accentColor: canAccent ? o.accent : saved.accentColor
            }
            commands = kdeCommands(desired, q, previous.applied ? saved : null).concat(commands)
        } else if (accentOn) {
            error = "plasma-apply-colorscheme is missing, so KDE apps keep their accent."
        }
        // Running KDE apps only re-read the palette after this signal.
        if (commands.length && !sameCommand(commands[commands.length - 1], NOTIFY_COMMAND))
            commands.push(NOTIFY_COMMAND.slice())
        return {
            action: "apply",
            commands: commands,
            error: error,
            state: { version: STATE_VERSION, applied: hasSaved, restoreOnLogout: keepOnLogout, saved: hasSaved ? saved : null,
                     restore: hasSaved ? restoreList(saved) : [] }
        }
    }
    if (previous.applied && previous.saved) {
        const saved = previous.saved
        const commands = saved.kdeColors && q.plasma
            ? kdeRestoreCommands(saved.kdeColors, q.kdeColors).concat(gnomeCommands(saved, q))
            : commandsFor(saved, q)
        return { action: "restore", commands: commands, error: "", state: forgottenState(keepOnLogout) }
    }
    return { action: "none", commands: [], error: "", state: forgottenState(keepOnLogout) }
}

// Desktop Exec quoting: the path in double quotes with ", `, $ and \ escaped.
function execQuote(text) {
    return "\"" + String(text).replace(/[\\"`$]/g, "\\$&") + "\""
}

// Plasma autostart safety net: gives Plasma its colours back at its next
// login when this session could not (crash, power loss). A no-op when
// nothing is applied; other desktops skip it.
function autostartEntry(scriptPath) {
    return [
        "[Desktop Entry]",
        "Type=Application",
        "Name=buchhwin-shell color restore",
        "Comment=Gives Plasma its colors back if a buchhwin-shell session ended without restoring them",
        "Exec=python3 " + execQuote(scriptPath),
        "OnlyShowIn=KDE;",
        "NoDisplay=true",
        "X-KDE-autostart-phase=0",
        ""
    ].join("\n")
}
