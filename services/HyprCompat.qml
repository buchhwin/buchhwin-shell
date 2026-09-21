pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "hypr/HyprCommands.js" as Commands

// Runs Hyprland actions in the syntax of the active configuration: legacy
// `dispatch`/`keyword` for hyprland.conf, Lua `dispatch`/`eval` for
// hyprland.lua (Hyprland 0.57+). The dialect is detected at startup with
// `hyprctl eval`, which only the Lua config manager accepts; commands issued
// before that are queued.
//
// **A failed probe is not an answer.** This used to decide from one attempt
// and take anything that was not "ok" as "legacy" - including the compositor
// not being reachable yet, which at ~300 ms into a session is a real
// possibility. Guessing wrong is silent and total: every `keyword` sent to a
// Lua Hyprland is rejected, so the animation mode, the speed, blur, rounding,
// gaps and the cursor never reach the compositor again for the whole session,
// and nothing says so. That is the shape of a "it worked yesterday" bug.
//
// So the probe asks whether Hyprland is reachable at all first, and only a
// reachable compositor gets to settle the question. An unreachable one is
// tried again.
Singleton {
    id: root

    property bool detected: false
    property bool lua: false
    property var queue: []
    // For session-check.sh: which dialect the shell settled on, or that it
    // never managed to ask.
    readonly property string dialect: !detected ? "unknown" : lua ? "lua" : "legacy"
    property int probes: 0
    // Enough to cover a compositor that is slow to come up, and few enough
    // that a genuinely absent Hyprland stops asking. The shell has no work
    // for the compositor before this is over anyway - it is all queued.
    readonly property int maxProbes: 10

    readonly property var commands: ({
        options: Commands.options, monitor: Commands.monitor, env: Commands.env, combine: Commands.combine,
        workspace: Commands.workspace, focusWindow: Commands.focusWindow, moveWindowSilent: Commands.moveWindowSilent,
        moveActiveSilent: Commands.moveActiveSilent, workspaceRule: Commands.workspaceRule,
        closeWindow: Commands.closeWindow, dpms: Commands.dpms, exit: Commands.exit,
        bindExec: Commands.bindExec, unbind: Commands.unbind, gestures: Commands.gestures
    })

    function run(kind, command) {
        if (!detected) {
            queue = queue.concat([{ kind: kind, command: command }])
            return
        }
        if (kind === "dispatch") Quickshell.execDetached(["hyprctl", "dispatch", lua ? command.lua : command.legacy])
        else if (lua) Quickshell.execDetached(["hyprctl", "eval", command.lua])
        else {
            // Empty values go after the batch as real empty arguments.
            const empty = (command.legacyEmpty || []).map(key => "hyprctl keyword " + key + " ''").join(" && ")
            const script = (command.legacy.length ? "hyprctl --batch \"$1\" >/dev/null" : "true") + (empty.length ? " && " + empty : "")
            Quickshell.execDetached(["sh", "-c", script, "sh", command.legacy])
        }
    }

    // A dispatcher from `commands` (workspace, focusWindow, …).
    function dispatch(command) { run("dispatch", command) }
    // Configuration changes (options, monitor, env or a combination).
    function configure(command) { run("config", command) }
    function setOptions(map) { configure(Commands.options(map)) }

    function settle(answer) {
        if (root.detected) return
        // "unreachable" is the probe saying it could not ask, which is a
        // different thing from Hyprland saying no.
        if (answer === "unreachable") {
            if (root.probes < root.maxProbes) { retry.restart(); return }
            console.warn("HyprCompat: Hyprland never answered after " + root.probes
                         + " probes; falling back to the legacy dialect")
        }
        root.lua = answer === "ok"
        root.detected = true
        const pending = root.queue
        root.queue = []
        for (const item of pending) root.run(item.kind, item.command)
    }

    Timer {
        id: retry
        interval: 200
        onTriggered: probe.running = true
    }

    Process {
        id: probe
        stderr: ErrorLog { label: "HyprCompat.process" }
        running: true
        // Three answers, not two: "unreachable" when hyprctl cannot reach the
        // compositor at all, "ok" from a Lua config manager, and anything else
        // from a legacy one (which rejects `eval`). Without the first, a
        // compositor that is merely not ready reads as a legacy one.
        command: ["sh", "-c",
                  "hyprctl version >/dev/null 2>&1 || { echo unreachable; exit 0; }; hyprctl eval 'return 1' 2>/dev/null"]
        onRunningChanged: if (running) root.probes += 1
        stdout: StdioCollector {
            onStreamFinished: root.settle(text.trim())
        }
    }
}
