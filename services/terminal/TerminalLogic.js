.pragma library

// Settings > Terminal: builds the Starship prompt and Kitty overrides from the
// `terminal.*` settings and turns Starship's ANSI output into rich text for the
// preview. Unit tested in tests/qml/TerminalTest.qml.

var promptColors = ["#4f8ff7", "#6ea8fe", "#2eb8a8", "#62d394", "#e7b43c", "#f28b3c", "#a28bfe", "#d46ad8", "#e6e8ee"]
var errorColors = ["#f07178", "#f28b3c", "#e7b43c", "#a28bfe"]
var mutedColor = "#9ba2ae"
var branchColor = "#a28bfe"

var timeFormats = [
    { value: "%H:%M", label: "21:45" },
    { value: "%I:%M %p", label: "9:45 PM" },
    { value: "%H:%M:%S", label: "21:45:30" },
    { value: "%d.%m %H:%M", label: "07.09 21:45" }
]

// Prompt modules in prompt order: settings key, Starship variable, label.
var modules = [
    { key: "username", variable: "$username", label: "Username" },
    { key: "hostname", variable: "$hostname", label: "Hostname" },
    { key: "directory", variable: "$directory", label: "Directory" },
    { key: "git", variable: "$git_branch", label: "Git branch" },
    { key: "gitStatus", variable: "$git_status", label: "Git status" },
    { key: "python", variable: "$python", label: "Python" },
    { key: "nodejs", variable: "$nodejs", label: "Node.js" },
    { key: "docker", variable: "$docker_context", label: "Docker context" },
    { key: "commandDuration", variable: "$cmd_duration", label: "Command duration" },
    { key: "jobs", variable: "$jobs", label: "Background jobs" },
    { key: "time", variable: "$time", label: "Clock" }
]

var keys = ["fontFamily", "fontSize", "opacity", "padding", "cursorShape", "cursorBlink",
            "cursorBlinkStyle", "cursorTrail",
            "promptColor", "errorColor", "symbol", "errorSymbol", "gitSymbol",
            "username", "hostname", "directory", "git", "gitStatus", "python", "nodejs", "docker",
            "commandDuration", "jobs", "time", "twoLine", "newline",
            "directoryDepth", "durationMin", "timeFormat", "fastfetchOnStart", "imageSize", "previewGit"]

// Reads every terminal setting through `lookup("terminal.<key>")`.
function options(lookup) {
    var result = {}
    for (var i = 0; i < keys.length; ++i) result[keys[i]] = lookup("terminal." + keys[i])
    return result
}

function isHex(value) { return /^#[0-9a-fA-F]{6}$/.test(String(value)) }
function hex(value, fallback) { return isHex(value) ? String(value).toLowerCase() : fallback }

function clamp(value, min, max, fallback) {
    var number = Number(value)
    return isFinite(number) ? Math.max(min, Math.min(max, number)) : fallback
}

// One line, at most `max` characters (code points, so Nerd Font glyphs stay whole).
function singleLine(text, max) {
    return Array.from(String(text === undefined || text === null ? "" : text).replace(/[\r\n\t\x00-\x1f]+/g, " ")).slice(0, max).join("")
}

function symbol(text, fallback) {
    var value = singleLine(text, 32)
    return value.trim().length ? value : fallback
}

function tomlString(text) {
    return "\"" + String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
}

function timeFormat(text) {
    var value = singleLine(text, 32).trim()
    return value.length ? value : "%H:%M"
}

function promptColor(o, accent) {
    return o.promptColor === "shell" ? hex(accent, "#4f8ff7") : hex(o.promptColor, "#4f8ff7")
}

// Fastfetch labels use the prompt colour: the fastfetch-color file, passed as
// --color-keys by zsh/.zshrc (the user@host title keeps its own colour).
function fastfetchColorText(o, accent) {
    return promptColor(o, accent) + "\n"
}

// cmatrix's -C only knows eight colour names, and they are ncurses palette
// slots: the terminal decides what "cyan" actually looks like. So the nearest
// name is only half the answer - the zsh wrapper also repaints that slot with
// the exact accent (OSC 4) and restores it afterwards (OSC 104), which is why
// the index travels with the name.
var CMATRIX_COLORS = [
    { name: "black", index: 0, rgb: [0, 0, 0] }, { name: "red", index: 1, rgb: [255, 0, 0] },
    { name: "green", index: 2, rgb: [0, 255, 0] }, { name: "yellow", index: 3, rgb: [255, 255, 0] },
    { name: "blue", index: 4, rgb: [0, 0, 255] }, { name: "magenta", index: 5, rgb: [255, 0, 255] },
    { name: "cyan", index: 6, rgb: [0, 255, 255] }, { name: "white", index: 7, rgb: [255, 255, 255] }
]

function rgbOf(color) {
    const value = hex(color, "#4f8ff7")
    return [parseInt(value.substr(1, 2), 16), parseInt(value.substr(3, 2), 16), parseInt(value.substr(5, 2), 16)]
}

function cmatrixName(o, accent) {
    const target = rgbOf(promptColor(o, accent))
    let best = CMATRIX_COLORS[0]
    let bestDistance = Infinity
    for (const option of CMATRIX_COLORS) {
        const distance = option.rgb.reduce((sum, part, index) => sum + Math.pow(part - target[index], 2), 0)
        if (distance < bestDistance) { bestDistance = distance; best = option }
    }
    return best
}

// Kept for callers that only want the name.
function cmatrixColor(o, accent) {
    return cmatrixName(o, accent).name
}

// The line the shell writes to `cmatrix-color`: the nearest colour name, its
// ncurses palette slot and the exact colour the wrapper paints into that slot.
// Unit tested.
function cmatrixColorLine(o, accent) {
    const best = cmatrixName(o, accent)
    return best.name + " " + best.index + " " + hex(promptColor(o, accent), "#4f8ff7")
}

// cava configuration with a gradient from the accent: dark at the bottom,
// the accent in the middle, a bright tint at the top.
function cavaConfig(o, accent) {
    const base = rgbOf(promptColor(o, accent))
    const mix = (from, to, amount) => from.map((part, index) =>
        Math.max(0, Math.min(255, Math.round(part + (to[index] - part) * amount))))
    const toHex = rgb => "#" + rgb.map(part => ("0" + part.toString(16)).slice(-2)).join("")
    const stops = [0.6, 0.35, 0.15, 0, 0.15, 0.3, 0.45, 0.6].map((amount, index) =>
        toHex(mix(base, index < 3 ? [0, 0, 0] : [255, 255, 255], amount)))
    return "# Written by buchhwin-shell (Settings > Terminal); edits are overwritten.\n"
        + "[color]\ngradient = 1\n"
        + stops.map((color, index) => "gradient_color_" + (index + 1) + " = '" + color + "'").join("\n")
        + "\n"
}

function starshipToml(o, accent) {
    var color = promptColor(o, accent)
    var error = hex(o.errorColor, "#f07178")
    var format = modules.filter(function (m) { return o[m.key] }).map(function (m) { return m.variable }).join("")
    if (o.twoLine) format += "$line_break"
    format += "$character"
    // Username and hostname are joined as user@host; the last one adds the space.
    var userFormat = "[$user]($style)" + (o.hostname ? "" : " ")
    var hostFormat = "[" + (o.username ? "@" : "") + "$hostname]($style) "
    var lines = [
        "# Generated by buchhwin-shell (Settings > Terminal); edits are overwritten.",
        "add_newline = " + (o.newline ? "true" : "false"),
        "format = " + tomlString(format),
        "",
        "[username]",
        "show_always = true",
        "style_user = " + tomlString("bold " + color),
        "style_root = " + tomlString("bold " + error),
        "format = " + tomlString(userFormat),
        "",
        "[hostname]",
        "ssh_only = false",
        "style = " + tomlString("bold " + color),
        "format = " + tomlString(hostFormat),
        "",
        "[directory]",
        "style = " + tomlString(mutedColor),
        "truncation_length = " + Math.round(clamp(o.directoryDepth, 1, 10, 3)),
        "truncate_to_repo = false",
        "home_symbol = \"~\"",
        "",
        "[git_branch]",
        "symbol = " + tomlString(symbol(o.gitSymbol, "󰊢") + " "),
        "style = " + tomlString(branchColor),
        "",
        "[git_status]",
        "style = " + tomlString(error),
        "",
        "[cmd_duration]",
        "min_time = " + Math.round(clamp(o.durationMin, 100, 10000, 1500)),
        "style = " + tomlString(mutedColor),
        "",
        "[time]",
        "disabled = " + (o.time ? "false" : "true"),
        "time_format = " + tomlString(timeFormat(o.timeFormat)),
        "style = " + tomlString(mutedColor),
        "format = \"[$time]($style) \"",
        "",
        "[character]",
        "success_symbol = " + tomlString("[" + symbol(o.symbol, "❯") + "](bold " + color + ")"),
        "error_symbol = " + tomlString("[" + symbol(o.errorSymbol, "❯") + "](bold " + error + ")"),
        ""
    ]
    return lines.join("\n")
}

// Kitty 0.36 and newer take an easing function after the blink interval, so a
// cursor can breathe instead of switching hard on and off. The trail (0.38 and
// newer) is the smear the cursor leaves when it jumps; its colour follows the
// shell accent so it belongs to the rest of the session.
function kittyConf(o, accent) {
    var family = singleLine(o.fontFamily, 80).trim() || "JetBrains Mono"
    var shape = ["beam", "block", "underline"].indexOf(o.cursorShape) >= 0 ? o.cursorShape : "beam"
    var blinkStyle = o.cursorBlinkStyle === "hard" ? "hard" : "soft"
    var blink = !o.cursorBlink ? "0" : blinkStyle === "soft" ? "0.6 ease-in-out" : "0.6"
    var trail = ["off", "short", "long"].indexOf(o.cursorTrail) >= 0 ? o.cursorTrail : "short"
    var lines = [
        "# Generated by buchhwin-shell (Settings > Terminal); edits are overwritten.",
        "font_family " + family,
        "font_size " + clamp(o.fontSize, 8, 20, 11).toFixed(1),
        "background_opacity " + clamp(o.opacity, 0.5, 1, 0.86).toFixed(2),
        "window_padding_width " + Math.round(clamp(o.padding, 0, 24, 12)),
        "cursor_shape " + shape,
        "cursor_blink_interval " + blink,
        "cursor_trail " + (trail === "off" ? "0" : trail === "long" ? "10" : "3"),
        "cursor_trail_color " + promptColor(o, accent)
    ]
    if (trail !== "off") lines.push("cursor_trail_decay " + (trail === "long" ? "0.2 0.8" : "0.1 0.4"))
    lines.push("")
    return lines.join("\n")
}

var basicColors = ["#1b1e26", "#f07178", "#62d394", "#e7b43c", "#6ea8fe", "#a28bfe", "#2eb8a8", "#e6e8ee"]

function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Starship ANSI output → rich text with colours and bold, spaces preserved.
function ansiToRich(text) {
    var clean = String(text).replace(/%\{|%\}/g, "").replace(/\r/g, "")
    var pattern = /\x1b\[([0-9;]*)m/g
    var state = { color: "", bold: false }
    var parts = []
    var last = 0
    var match
    function emit(chunk) {
        if (!chunk.length) return
        var html = escapeHtml(chunk).replace(/ /g, "&nbsp;").replace(/\n/g, "<br>")
        if (state.bold) html = "<b>" + html + "</b>"
        if (state.color) html = "<font color=\"" + state.color + "\">" + html + "</font>"
        parts.push(html)
    }
    while ((match = pattern.exec(clean)) !== null) {
        emit(clean.slice(last, match.index))
        last = pattern.lastIndex
        var codes = match[1].length ? match[1].split(";").map(Number) : [0]
        for (var i = 0; i < codes.length; ++i) {
            var code = codes[i]
            if (code === 0) { state.color = ""; state.bold = false }
            else if (code === 1) state.bold = true
            else if (code === 22) state.bold = false
            else if (code === 39) state.color = ""
            else if (code >= 30 && code <= 37) state.color = basicColors[code - 30]
            else if (code >= 90 && code <= 97) state.color = basicColors[code - 90]
            else if (code === 38 && codes[i + 1] === 2 && i + 4 < codes.length) {
                state.color = "#" + codes.slice(i + 2, i + 5).map(function (n) { return ("0" + Math.max(0, Math.min(255, n)).toString(16)).slice(-2) }).join("")
                i += 4
            } else if (code === 38 && codes[i + 1] === 5) i += 2
            // A background (48) is not painted, but its arguments have to be
            // consumed the same way: left in the list, `48;2;30;30;30` read
            // as three foreground codes and painted the text.
            else if (code === 48 && codes[i + 1] === 2) i += 4
            else if (code === 48 && codes[i + 1] === 5) i += 2
        }
    }
    emit(clean.slice(last))
    return parts.join("")
}
