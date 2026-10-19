pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "widgets/CommandLogic.js" as Logic

// The command widgets' runs (CommandLogic has what they are). A command runs
// only while a widget of its slot is placed and shown - the bar, the notch,
// the desktop, an open dashboard - however many of them there are: one run
// per interval for all of them, the first at once. Nothing runs, and no timer
// ticks, while no widget asks.
Singleton {
    id: root
    // { slot: how many widgets show it }.
    property var trackers: ({})
    // { slot: { line, detail, failed, exitCode } }: the last run's answer.
    property var results: ({})

    function track(slot) {
        if (Logic.SLOTS.indexOf(slot) < 0) return
        const next = Object.assign({}, trackers)
        next[slot] = (next[slot] || 0) + 1
        trackers = next
    }
    function untrack(slot) {
        if (!(trackers[slot] > 0)) return
        const next = Object.assign({}, trackers)
        next[slot] -= 1
        trackers = next
    }

    function definition(slot) {
        return Logic.definition(leaf => SettingsService.value("commandWidgets." + slot + "." + leaf))
    }
    function runnerOf(slot) {
        return slot === "one" ? one : slot === "two" ? two : slot === "three" ? three : null
    }

    // Run now, whoever is watching: Settings' "Run now", and a click on a
    // widget without a click command of its own.
    function runNow(slot) {
        const runner = runnerOf(slot)
        if (runner) runner.run()
    }

    // A widget's click: its click command, and a run a moment later, so the
    // widget shows what the click changed (a VPN switched on). Without a
    // click command, a click asks again at once; without a command at all,
    // the widget leads to the place it is set up.
    function click(slot) {
        const runner = runnerOf(slot)
        if (!runner) return
        if (!runner.command.length) {
            PanelService.open("settings", { page: "widgets" })
        } else if (runner.click.length) {
            Quickshell.execDetached(Logic.clickCommand(runner.click, Paths.script("launch-app.sh")))
            runner.soon()
        } else {
            runner.run()
        }
    }

    // For `widgets commands` over IPC: per slot whether a command is set, how
    // many widgets show it and how its last run went - never the command or
    // what it printed (a command can hold a token, its answer is the user's).
    function status() {
        return Logic.SLOTS.map(slot => {
            const result = results[slot] || null
            return { slot: slot, set: definition(slot).command.length > 0, tracked: trackers[slot] || 0,
                     running: runnerOf(slot).running, ran: result !== null,
                     failed: result !== null && result.failed, hasLine: result !== null && result.line.length > 0 }
        })
    }

    component Runner: Scope {
        id: runner
        required property string slot
        readonly property bool wanted: (root.trackers[slot] || 0) > 0
        // Strings and a number, not the whole definition: a binding to an
        // object would change on every write of settings.json, and each change
        // would be a run.
        readonly property string command: root.definition(slot).command
        readonly property string click: root.definition(slot).click
        readonly property int seconds: root.definition(slot).interval
        readonly property bool running: proc.running

        function run() {
            if (!command.length || proc.running) return
            proc.command = Paths.bound(Logic.runCommand(command, seconds, Paths.script("lib/app-env.sh")))
            proc.running = true
        }
        function soon() { soonTimer.restart() }

        onCommandChanged: {
            const next = Object.assign({}, root.results)
            delete next[slot]
            root.results = next
            if (wanted) Qt.callLater(runner.run)
        }

        Process {
            id: proc
            property string output: ""
            stdout: StdioCollector { onStreamFinished: proc.output = text }
            onStarted: output = ""
            // The whole output is in by now (pitfall 131).
            onExited: code => {
                const next = Object.assign({}, root.results)
                next[runner.slot] = Object.assign(Logic.parseOutput(proc.output), { failed: Logic.failed(code), exitCode: code })
                root.results = next
            }
        }
        Timer {
            interval: runner.seconds * 1000
            repeat: true
            triggeredOnStart: true
            running: runner.wanted && runner.command.length > 0
            onTriggered: runner.run()
        }
        Timer { id: soonTimer; interval: 1500; onTriggered: runner.run() }
    }

    Runner { id: one; slot: "one" }
    Runner { id: two; slot: "two" }
    Runner { id: three; slot: "three" }
}
