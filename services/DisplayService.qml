pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "display/DisplayLogic.js" as Logic

// Monitor configuration: edit a draft, apply it as Hyprland monitor rules
// (HyprCompat: keyword or Lua), then keep it within 15 seconds or it reverts
// on its own. Kept settings are stored in ~/.config/buchhwin-shell/monitors.json and applied
// when the shell starts or a monitor is connected. Hyprland's own config files
// are never modified.
Singleton {
    id: root

    property var monitors: []          // live state
    property var draft: []             // edited copy
    property var previous: []          // state before the last apply
    property var saved: null
    property bool savedLoaded: false
    property bool startupApplied: false
    property int countdown: 0
    readonly property int confirmSeconds: 15
    readonly property bool confirming: countdown > 0
    readonly property bool dirty: draft.length > 0 && Logic.changed(monitors, draft)
    readonly property bool valid: Logic.enabledCount(draft) > 0
    readonly property bool overlapping: Logic.overlapping(draft)
    readonly property var transforms: Logic.TRANSFORMS
    readonly property var vrrModes: Logic.VRR

    // Lid "screen off" (Settings > Power): runtime only, never saved.
    property bool lidClosed: false
    property bool lidDpms: false          // internal panel switched off with dpms
    property var lidRestore: null         // internal panel before it was disabled
    readonly property string internalName: {
        const forced = Quickshell.env("BUCHHWIN_NESTED") === "1" ? (Quickshell.env("BUCHHWIN_INTERNAL_OUTPUT") || "") : ""
        if (forced.length) return forced
        const panel = monitors.find(item => Logic.isInternal(item.name))
        return panel ? panel.name : ""
    }

    function setLidClosed(closed) {
        if (closed === lidClosed) return
        lidClosed = closed
        const name = internalName
        if (!name.length) return
        const panel = monitors.find(item => item.name === name)
        if (closed) {
            const plan = Logic.lidPlan(monitors, name)
            if (plan === "disable" && panel) {
                lidRestore = panel
                run([Object.assign({}, panel, { disabled: true })])
            } else if (plan === "dpms") {
                setPanelPower(false)
            }
        } else {
            if (lidRestore) run([Object.assign({}, lidRestore, { disabled: false })])
            else if (panel && panel.disabled) run([Object.assign({}, panel, { disabled: false })])
            if (lidDpms) setPanelPower(true)
            lidRestore = null
            savedDelay.restart()
        }
        refreshSoon.restart()
    }

    function setPanelPower(on) {
        lidDpms = !on
        HyprCompat.dispatch(HyprCompat.commands.dpms(on, internalName))
    }

    // After a global "dpms on" (idle wake) the closed laptop panel stays dark.
    function reassertLid() { if (lidClosed && lidDpms) setPanelPower(false) }

    function refresh() { if (!monitorsProc.running) monitorsProc.running = true }

    function monitor(name) { return draft.find(item => item.name === name) || null }
    function resolutions(name) { const target = monitor(name); return target ? Logic.resolutions(target) : [] }
    function refreshRates(name) { const target = monitor(name); return target ? Logic.refreshRates(target, target.width, target.height) : [] }
    function scaleChoices(name) { const target = monitor(name); return target ? Logic.scaleChoices(target.scale) : Logic.SCALES }
    function logicalSize(target) { return Logic.logicalSize(target) }
    function snap(name, x, y, threshold) { return Logic.snap(draft, name, x, y, threshold) }

    function edit(name, patch) {
        if (confirming) return
        draft = Logic.update(draft, name, patch)
    }
    function setResolution(name, value) {
        const target = monitor(name)
        if (!target) return
        const parts = String(value).split("x").map(Number)
        const modes = target.modes.filter(mode => mode.width === parts[0] && mode.height === parts[1])
        if (!modes.length) return
        const sameRate = modes.find(mode => Math.abs(mode.refresh - target.refresh) < 0.5)
        const mode = sameRate || modes[0]
        edit(name, { width: mode.width, height: mode.height, refresh: mode.refresh })
    }
    function setRefresh(name, value) { edit(name, { refresh: Number(value) }) }
    function setScale(name, value) { edit(name, { scale: Number(value) }) }
    function setTransform(name, value) { edit(name, { transform: Number(value) }) }
    function setVrr(name, value) { edit(name, { vrr: Number(value) }) }
    function setPosition(name, x, y) { edit(name, { x: Math.round(x), y: Math.round(y) }) }

    // One arrow-key step, and a neighbour's edge within a step catches it. The
    // threshold *is* the step: "if an edge is closer than one press, land on
    // it" is the rule that makes the last press before an edge line the two up
    // instead of stopping short.
    //
    // It goes through `edit`, so it is refused while the confirmation
    // countdown is running - the same gate the drag respects.
    function nudge(name, dx, dy, step) {
        if (confirming) return
        const next = Logic.nudge(draft, name, dx, dy, step, step)
        if (next) setPosition(name, next.x, next.y)
    }
    function setEnabled(name, value) {
        const next = Logic.update(draft, name, { disabled: !value })
        if (Logic.enabledCount(next) > 0 && !confirming) draft = next
    }
    function discard() { if (!confirming) draft = monitors.slice() }

    function run(list) {
        HyprCompat.configure(HyprCompat.commands.combine(list.map(entry => HyprCompat.commands.monitor(entry))))
    }

    function apply() {
        if (!dirty || !valid || confirming) return false
        previous = monitors.slice()
        draft = Logic.normalize(draft)
        run(draft)
        countdown = confirmSeconds
        countdownTimer.restart()
        refreshSoon.restart()
        return true
    }

    function keep() {
        if (!confirming) return false
        countdown = 0
        countdownTimer.stop()
        saved = Logic.toSaved(draft)
        savedFile.setText(JSON.stringify(saved, null, 2) + "\n")
        return true
    }

    function revert() {
        if (!confirming) return false
        countdown = 0
        countdownTimer.stop()
        run(previous)
        draft = previous.slice()
        refreshSoon.restart()
        return true
    }

    function applySavedIfNeeded() {
        if (!savedLoaded || !monitors.length || (!saved && !lidClosed)) return
        const base = saved ? Logic.applySaved(monitors, saved) : monitors
        const target = Logic.lidAdjusted(base, internalName, lidClosed)
        if (lidClosed && internalName.length) {
            const panel = target.find(item => item.name === internalName)
            const live = monitors.find(item => item.name === internalName)
            // Docked again: remember the panel before disabling it. Last display
            // gone: the panel comes back but stays dark.
            if (panel && panel.disabled && live && !live.disabled) lidRestore = live
            if (panel && !panel.disabled) Qt.callLater(() => root.setPanelPower(false))
        }
        if (Logic.changed(monitors, target)) {
            run(target)
            refreshSoon.restart()
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown <= 0) {
                root.countdown = 1
                root.revert()
            }
        }
    }

    Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }

    Process {
        id: monitorsProc
        stderr: ErrorLog { label: "DisplayService.monitorsProc" }
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = []
                try { parsed = Logic.parseMonitors(text) } catch (error) { return }
                root.monitors = parsed
                if (!root.confirming) root.draft = parsed.slice()
                if (!root.startupApplied && root.savedLoaded) {
                    root.startupApplied = true
                    root.applySavedIfNeeded()
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A config reload resets monitors to the config rules.
            if (event.name === "configreloaded") {
                root.refresh()
                savedDelay.restart()
            } else if (event.name === "monitoraddedv2" || event.name === "monitorremovedv2") {
                root.refresh()
                if (event.name === "monitoraddedv2" || root.lidClosed) savedDelay.restart()
            }
        }
    }
    Timer { id: savedDelay; interval: 800; onTriggered: root.applySavedIfNeeded() }

    FileView {
        id: savedFile
        path: Paths.configDir + "/monitors.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try { root.saved = JSON.parse(text()) } catch (error) { root.saved = null }
            root.savedLoaded = true
            root.refresh()
        }
        onLoadFailed: {
            root.savedLoaded = true
            root.startupApplied = true
            root.refresh()
        }
    }

    // "Identify": every screen shows its own number for a few seconds, so the
    // numbers on the arrangement canvas can be matched to the monitors on the
    // desk. Drawn by shell/displays/IdentifyOverlay.qml.
    readonly property int identifySeconds: 4
    property bool identifying: false

    function identify() {
        identifying = true
        identifyTimer.restart()
    }

    // The number a monitor carries on this page, by name. The overlay is built
    // from `Quickshell.screens` and the draft is sorted by position, so the two
    // are not in the same order - an overlay numbering by its own index would
    // label the screens differently from the page it belongs to.
    function displayNumber(name) {
        const index = draft.findIndex(item => item.name === name)
        return index < 0 ? 0 : index + 1
    }

    Timer {
        id: identifyTimer
        interval: root.identifySeconds * 1000
        onTriggered: root.identifying = false
    }

    Component.onCompleted: refresh()
}
