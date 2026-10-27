import Quickshell
import Quickshell.Io
import QtQuick
import "updates/UpdatesLogic.js" as Logic

// A terminal of a Settings page, run as a user service of its own and
// watched by its unit (UpdatesLogic.UPGRADE_UNIT, the security key's setup):
// no longer a child of the shell, so a reload, a deploy or the shell's own
// update leaves it - and the pacman in it - alone. `busy` from the start until the unit is gone; a
// shell started while one runs (the restart after a deploy) picks it up.
// The unit lasts as long as the window because launch-terminal.sh keeps
// every terminal in its own process (Konsole --nofork, GNOME Terminal
// --wait …) rather than handing the window to one already running.
// A Process's `running` turns true only some time after the start, and a
// command that cannot start only turns it false, without `exited`
// (probed on 0.3.2): own flags say what is going on, and the status of
// the start is -1 until it exits (-2: watched only, not started here).
Scope {
    id: job
    required property string unit
    // The ErrorLog label of the start and the watch.
    property string label: unit
    property bool starting: false
    property bool watching: false
    property int startCode: -2
    readonly property bool busy: starting || watching
    // The unit ran and is gone: the window was closed.
    signal ended()
    signal failed(int code)

    function start(command) {
        if (busy) return
        startCode = -1
        starting = true
        starter.command = command
        starter.running = true
    }
    // What a page says on `failed`.
    function failureText(code) {
        return "The terminal window could not be opened (" + (code < 0 ? "not started" : "exit " + code) + ")"
    }
    function watch() {
        if (watching) return
        watcher.seen = false
        watching = true
        watcher.running = true
    }

    Process {
        id: starter
        stderr: ErrorLog { label: job.label }
        onExited: (code, status) => { job.startCode = code }
        onRunningChanged: {
            if (running || !job.starting) return
            // Watching first, so `busy` does not drop for a moment.
            job.watch()
            job.starting = false
        }
    }
    Process {
        id: watcher
        property bool seen: false
        command: Paths.bound(Logic.unitWatchCommand(job.unit))
        stderr: ErrorLog { label: job.label + ".watch" }
        stdout: SplitParser { onRead: data => { if (data.trim() === "active") watcher.seen = true } }
        onRunningChanged: {
            if (running || !job.watching) return
            job.watching = false
            // Without a user manager launch-app.sh starts the terminal
            // with no unit to watch (status 0): nothing to say then.
            if (watcher.seen) job.ended()
            else if (job.startCode !== 0 && job.startCode !== -2) job.failed(job.startCode)
            job.startCode = -2
        }
    }
}
