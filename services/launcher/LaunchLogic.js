.pragma library

// How the launcher starts an entry (services/LauncherService.qml): what
// Quickshell.execDetached gets, or null when the entry has nothing to run.
//
// Everything goes through scripts/launch-app.sh: a unit of its own, named
// after the entry (the portals know the application by that name), and the
// session's environment rather than the shell's own settings
// (scripts/lib/app-env.sh). DesktopEntry.execute() is a plain execDetached
// of the command, so terminal entries and the like inherited the shell's two
// malloc arenas, Mesa without its threads and no Plasma look (16.10.). The
// entry's working directory (Path=) goes along, as execute() passed it. An
// override is a session launcher (launch-brave.sh, launch-kitty.sh …), which
// ends in launch-app.sh itself.
//
// A Terminal=true entry (htop, btop …) runs in the session's terminal
// through scripts/launch-terminal.sh, which ends in launch-app.sh too: the
// terminal is the application there, and its unit is named after the
// terminal. execute() ignores Terminal= and ran such a command with no
// terminal at all, so nothing showed.
//
// A browser of Chromium's family is known by the program an entry runs, not
// only by its id: a web app's entry (brave-<app>-Default, chrome-<app>-
// Default - Outlook and Teams here) runs /opt/brave-bin/brave --app-id=…,
// and its actions run the browser too. Started past the browser's session
// launcher, a browser that was not running yet came up without
// --password-store=kwallet6 and without waiting for the wallet - under this
// desktop name Chromium then picks libsecret, a different key, and every
// login is gone (testing.md pitfall 32). The launcher takes the entry's
// arguments after the program; it finds the browser's executable itself.
// Exact names only: a beta or nightly build is another browser with its own
// profile, which the stable launcher would not start.
const BROWSER_PROGRAMS = {
    "brave": "launch-brave.sh",
    "brave-browser": "launch-brave.sh",
    "brave-browser-stable": "launch-brave.sh",
    "google-chrome": "launch-chrome.sh",
    "google-chrome-stable": "launch-chrome.sh",
    "chromium": "launch-chromium-browser.sh",
    "chromium-browser": "launch-chromium-browser.sh"
}

function browserLauncher(program) {
    const name = String(program || "").split("/").pop()
    return Object.prototype.hasOwnProperty.call(BROWSER_PROGRAMS, name) ? BROWSER_PROGRAMS[name] : ""
}

function copied(list) {
    return list && list.length ? Array.prototype.slice.call(list) : []
}

// What runs a command line of an entry: its own or one of its actions'.
function commandContext(app, argv, script) {
    const id = app.id || ""
    // launch-app.sh names the unit after the id and refuses to run without one.
    if (!argv.length || !id.length) return null
    const browser = browserLauncher(argv[0])
    const context = { command: browser ? [script(browser)].concat(argv.slice(1))
                                       : app.runInTerminal ? [script("launch-terminal.sh"), "--"].concat(argv)
                                       : [script("launch-app.sh"), id].concat(argv) }
    if (app.workingDirectory) context.workingDirectory = app.workingDirectory
    return context
}

// script: name -> path of a script in scripts/ (Paths.script).
function launchContext(app, overrides, script) {
    if (!app) return null
    const id = app.id || ""
    if (id.length && Object.prototype.hasOwnProperty.call(overrides, id))
        return { command: [script(overrides[id])] }
    return commandContext(app, copied(app.command), script)
}

// A desktop action (DesktopEntry.actions: "New Window", "New Incognito
// Window", a web app's "New message" …): its own command line, started the
// way its entry is. An entry with a session launcher (Alacritty, kitty)
// keeps it when the action runs the entry's own program, with the action's
// arguments after it; anything else the action runs goes the usual way.
function actionContext(app, action, overrides, script) {
    if (!app || !action) return null
    const argv = copied(action.command)
    if (!argv.length) return null
    const id = app.id || ""
    const own = copied(app.command)
    if (id.length && Object.prototype.hasOwnProperty.call(overrides, id) && own.length
            && String(own[0]).split("/").pop() === String(argv[0]).split("/").pop())
        return { command: [script(overrides[id])].concat(argv.slice(1)) }
    return commandContext(app, argv, script)
}
