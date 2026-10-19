.pragma library
.import "LaunchLogic.js" as Launch

// "$ command" in the launcher: Enter runs it, Ctrl+Enter runs it in the
// session's terminal and keeps the window open for its output. Unit tested
// (tests/qml/LauncherSourcesTest.qml).
//
// Through scripts/launch-app.sh like every start from the launcher (a unit
// of its own, the session's environment rather than the shell's - pitfall
// 85), named after the program. A browser of Chromium's family goes through
// its session launcher even here (LaunchLogic.browserLauncher): "$ brave"
// past launch-brave.sh would start it without the wallet's password store,
// and that logs out of everything (pitfall 32).

var PREFIX = "$"

// The command typed after the prefix, or "".
function parse(text) {
    const value = String(text || "")
    return value.charAt(0) === PREFIX ? value.slice(1).trim() : ""
}

// Words a shell would split the same way and leave alone: no quotes, no
// variables, globs, redirections, pipes or "~". Such a command runs as it is
// (one process less); anything else goes to sh -c.
var PLAIN_WORD = /^[A-Za-z0-9_.\/+@%:,=-]+$/

function words(command) {
    return String(command || "").trim().split(/\s+/).filter(word => word.length)
}

function plain(command) {
    const list = words(command)
    return list.length > 0 && list.every(word => PLAIN_WORD.test(word)) && list[0].indexOf("=") < 0
}

// What the unit is called: the program's name, or "sh" for a shell line
// that starts with something else (a variable, a subshell, a quote).
function unitName(command) {
    const first = words(command)[0] || ""
    const name = first.split("/").pop()
    return /^[A-Za-z0-9_.+-]+$/.test(name) && first.indexOf("=") < 0 ? name : "sh"
}

// Whether the program is one that only works in a terminal: the desktop
// entries say so for theirs (Terminal=true: htop, btop, mc …), and Enter on
// "$ htop" would otherwise start it with nowhere to draw.
function needsTerminal(command, apps) {
    const name = unitName(command)
    if (name === "sh") return false
    return (apps || []).some(app => app && app.runInTerminal === true && app.command && app.command.length
                             && String(app.command[0]).split("/").pop() === name)
}

// The title of the terminal window: the command, cut to what a title bar shows.
function title(command) {
    const text = String(command || "").trim()
    return text.length > 60 ? text.slice(0, 59) + "…" : text
}

// → { command } for Quickshell.execDetached, or null for nothing to run.
// `script(name)` is a script's path (Paths.script). In a terminal the window
// stays open once the command has ended, for its output, unless `hold` is
// false: htop started by Enter takes its window with it when it ends, as it
// does when started from its desktop entry.
function context(command, script, inTerminal, hold) {
    const text = String(command || "").trim()
    if (!text.length) return null
    const list = words(text)
    const browser = plain(text) ? Launch.browserLauncher(list[0]) : ""
    if (browser) return { command: [script(browser)].concat(list.slice(1)) }
    if (inTerminal)
        return { command: [script("launch-terminal.sh")].concat(hold === false ? [] : ["--hold"],
                                                                 ["--title", title(text), "--", "sh", "-c", text]) }
    if (plain(text)) return { command: [script("launch-app.sh"), unitName(text)].concat(list) }
    return { command: [script("launch-app.sh"), unitName(text), "sh", "-c", text] }
}
