.pragma library

// Command widgets (shell/widgets/CommandWidget.qml, services/
// CommandWidgetService.qml): a widget that shows the first line a command of
// the user's prints - a VPN check, a build's state, a counter - and runs
// another command when it is clicked. Pure functions, unit tested in
// CommandWidgetTest.qml.
//
// There are three of them, each a widget type of its own ("Command 1" to
// "Command 3") whose command is set in Settings > Widgets: the layout keeps
// no per-widget options the editor could change, and settings.json cannot
// hold a list, so each one is a group of plain settings
// (commandWidgets.one.command and so on). They are the machine's, like the
// commands in a shell's own rc file: a profile switch leaves them alone and
// `settings get` does not hand them out (a command can hold a token).

var SLOTS = ["one", "two", "three"]
var TYPES = { command1: "one", command2: "two", command3: "three" }

// How often a command runs, in seconds; the setting offers these.
var INTERVALS = [5, 10, 30, 60, 300, 900, 3600]
var DEFAULT_INTERVAL = 60

// Waybar's figure for what a module may show; the widget elides further.
var LINE_MAX = 120

// What a run may print before it is cut off, in bytes. Two lines are all the
// widget shows, and the shell holds the whole output in memory until the run
// ends: a command that prints without end (`yes`, a `journalctl` without -n)
// would grow the shell by what it prints until its timeout. Cut off, it ends
// on the broken pipe, and that counts as failed.
var OUTPUT_MAX = 65536

// The glyph a command widget has until one is chosen: a console.
var DEFAULT_ICON = "\u{f018d}"

function slotOf(type, options) {
    const named = options && typeof options.slot === "string" ? options.slot : ""
    if (SLOTS.indexOf(named) >= 0) return named
    return Object.prototype.hasOwnProperty.call(TYPES, String(type)) ? TYPES[type] : ""
}

function typeOf(slot) {
    return Object.keys(TYPES).find(type => TYPES[type] === slot) || ""
}

// The setting's interval -> one of INTERVALS: the nearest, or the default for
// anything that is no number.
function interval(value) {
    const seconds = Number(value)
    if (!isFinite(seconds) || seconds <= 0) return DEFAULT_INTERVAL
    return INTERVALS.reduce((best, item) => Math.abs(item - seconds) < Math.abs(best - seconds) ? item : best, INTERVALS[0])
}

// A run that takes longer than this is ended: a little under the interval,
// and never more than half a minute - a check that hangs (a host that does
// not answer) must not pile up behind the next one.
function timeoutFor(seconds) {
    return Math.max(2, Math.min(30, interval(seconds) - 1))
}

// "" for a command the widget can run, else why not. One line: it runs as
// one shell line (runCommand), and a script is the place for more.
function commandError(command) {
    const text = String(command === undefined || command === null ? "" : command)
    if (!text.trim().length) return ""
    if (/[\x00-\x08\x0a-\x1f\x7f]/.test(text)) return "Commands must be on one line"
    if (text.length > 1000) return "The command is too long"
    return ""
}

// The glyph to show: the user's, when it is a glyph (a few characters at
// most - a Nerd Font icon is one or two), else the console.
function glyph(icon) {
    const text = String(icon || "").trim()
    return text.length > 0 && text.length <= 4 ? text : DEFAULT_ICON
}

// A slot's settings, read through `get(leaf)` (SettingsService.value of
// commandWidgets.<slot>.<leaf>), as one tidy object.
function definition(get) {
    const read = leaf => {
        const value = get ? get(leaf) : undefined
        return value === undefined || value === null ? "" : value
    }
    const command = String(read("command")).trim()
    const click = String(read("click")).trim()
    return {
        label: String(read("label")).trim(),
        icon: glyph(read("icon")),
        command: commandError(command) ? "" : command,
        click: commandError(click) ? "" : click,
        interval: interval(read("interval"))
    }
}

// The output -> what the widget shows: the first line that is not empty,
// and the next one as its detail line (the large size shows it). Control
// characters - a colour escape - are taken out.
function parseOutput(text) {
    const lines = String(text || "").split("\n")
        .map(line => line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/[\x00-\x1f\x7f]/g, " ").trim())
        .filter(line => line.length)
    const cut = line => line.length > LINE_MAX ? line.slice(0, LINE_MAX - 1) + "…" : line
    return { line: lines.length ? cut(lines[0]) : "", detail: lines.length > 1 ? cut(lines[1]) : "" }
}

// The argv for one run: the session's environment back (the shell runs with
// settings meant for itself alone, scripts/lib/app-env.sh), the command
// under `timeout`, its stderr dropped and its output cut off at OUTPUT_MAX,
// the command's own exit status kept. `timeout` ends the whole run, the
// pipe's reader included, and goes with the shell (Paths.bound). The command
// goes in as an argument, never into the script's text.
function runCommand(command, seconds, appEnvPath) {
    return ["bash", "-c",
        "if [[ -r $1 ]] && source \"$1\" && declare -F app_env_restore >/dev/null; then app_env_restore; fi; "
        + "exec timeout -k 2 \"$2\" bash -c 'c=$1 n=$2; set --; eval \"$c\" 2>/dev/null | head -c \"$n\"; exit \"${PIPESTATUS[0]}\"' "
        + "bash \"$3\" \"$4\"",
        "bash", appEnvPath || "", String(timeoutFor(seconds)), String(command), String(OUTPUT_MAX)]
}

// The argv for a click: an application start like any other, in a scope of
// its own with the session's environment (scripts/launch-app.sh).
function clickCommand(command, launchApp) {
    return [launchApp, "buchhwin-shell-command", "sh", "-c", String(command)]
}

// What a run ended as, for the glyph: a command that failed or timed out
// (exit status not 0) is drawn in the warning ink, which is how a check
// says "down".
function failed(exitCode) {
    return exitCode !== 0
}

// A failed run in words, with its exit status where it is known: "Failed
// (exit 2)". The glyph's warning ink alone said nothing of it. "" for a run
// that did not fail.
function failureText(result) {
    if (!result || result.failed !== true) return ""
    const code = Number(result.exitCode)
    return isFinite(code) && result.exitCode !== undefined && result.exitCode !== null ? "Failed (exit " + code + ")" : "Failed"
}
