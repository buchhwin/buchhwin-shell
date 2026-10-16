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
// script: name -> path of a script in scripts/ (Paths.script).
function launchContext(app, overrides, script) {
    if (!app) return null
    const id = app.id || ""
    if (id.length && Object.prototype.hasOwnProperty.call(overrides, id))
        return { command: [script(overrides[id])] }
    const argv = app.command && app.command.length ? Array.prototype.slice.call(app.command) : []
    // launch-app.sh names the unit after the id and refuses to run without one.
    if (!argv.length || !id.length) return null
    const context = { command: app.runInTerminal ? [script("launch-terminal.sh"), "--"].concat(argv)
                                                 : [script("launch-app.sh"), id].concat(argv) }
    if (app.workingDirectory) context.workingDirectory = app.workingDirectory
    return context
}
