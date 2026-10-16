pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "display/DisplayLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

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
    // No apply while anything overlaps: Hyprland keeps explicit positions as
    // given and only warns, with input landing on the wrong screen. The
    // page's moves never produce an overlap (Logic.placeApart), so this only
    // catches a layout edited by hand.
    readonly property bool valid: Logic.enabledCount(draft) > 0 && !Logic.overlapping(draft)
    readonly property bool overlapping: Logic.overlapping(draft)
    readonly property var transforms: Logic.TRANSFORMS
    readonly property var vrrModes: Logic.VRR

    // The lock screen's process (lock.qml) can create this service too - its
    // calendar reaches AppearanceService, whose X11 scale reads `monitors` -
    // and there it only reads. The saved layout and the lid are the shell's:
    // a copy in the lock is never told the lid is shut, so applying the file
    // from there would switch the laptop panel back on behind the shell's
    // back (16.10. review, with the lock's own IdleService).
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)

    // Lid "screen off" (Settings > Power): runtime only, never saved - a
    // Keep with the lid shut saves the panel as it is without the lid
    // (Logic.kept), and a saved "off" for it counts only when it was kept
    // with the lid open (Logic.withEntry).
    property bool lidClosed: false
    property bool lidDpms: false          // internal panel switched off with dpms
    property var lidRestore: null         // internal panel before it was disabled
    readonly property string internalName: {
        const forced = Quickshell.env("BUCHHWIN_NESTED") === "1" ? (Quickshell.env("BUCHHWIN_INTERNAL_OUTPUT") || "") : ""
        if (forced.length) return forced
        const panel = monitors.find(item => Logic.isInternal(item.name))
        return panel ? panel.name : ""
    }

    // Whether the lid is known: IdleService's check at start has answered (or
    // failed), a lid switch has been seen, or 3 s have passed (busctl gives
    // up after 2). Until then a startup apply leaves a panel that is off now
    // off (Logic.lidPending), and `lidHeld` says one was held back.
    property bool lidKnown: false
    property bool lidHeld: false
    function lidChecked() {
        if (lockProcess || lidKnown) return
        lidKnown = true
        lidWait.stop()
        if (lidHeld) {
            lidHeld = false
            applySavedIfNeeded()
        }
    }
    Timer { id: lidWait; interval: 3000; running: !root.lockProcess; onTriggered: root.lidChecked() }

    function setLidClosed(closed) {
        if (lockProcess) return
        // A lid event is an answer too. A panel held back while the lid was
        // believed open gets the saved layout again; for a shut lid the
        // plan below decides.
        const held = lidHeld
        lidKnown = true
        lidHeld = false
        lidWait.stop()
        if (closed === lidClosed) {
            if (held) savedDelay.restart()
            return
        }
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

    // Only setLidClosed and reassertLid lead here, and neither does anything
    // in the lock process; the guard keeps it that way for a new caller.
    function setPanelPower(on) {
        if (lockProcess) return
        lidDpms = !on
        HyprCompat.dispatch(HyprCompat.commands.dpms(on, internalName))
    }

    // After a global "dpms on" (idle wake) the closed laptop panel stays dark.
    function reassertLid() { if (lidClosed && lidDpms) setPanelPower(false) }

    // A request while hyprctl is running is kept for one more run after it:
    // docking adds two monitors, and the second refresh, dropped, left the
    // snapshot (and applySavedIfNeeded) without the second screen.
    property bool refreshQueued: false
    function refresh() {
        if (monitorsProc.running) { refreshQueued = true; return }
        monitorsProc.running = true
    }

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
    // An edit that changes a monitor's size (mode, scale, rotation) or brings
    // one back: its neighbours are pushed clear afterwards (Logic.spread), so
    // a bigger screen never ends up under the next one.
    function resize(name, patch) {
        if (confirming) return
        draft = Logic.spread(Logic.update(draft, name, patch))
    }
    function setResolution(name, value) {
        const target = monitor(name)
        if (!target) return
        const parts = String(value).split("x").map(Number)
        const modes = target.modes.filter(mode => mode.width === parts[0] && mode.height === parts[1])
        if (!modes.length) return
        const sameRate = modes.find(mode => Math.abs(mode.refresh - target.refresh) < 0.5)
        const mode = sameRate || modes[0]
        resize(name, { width: mode.width, height: mode.height, refresh: mode.refresh })
    }
    function setRefresh(name, value) { edit(name, { refresh: Number(value) }) }
    function setScale(name, value) { resize(name, { scale: Number(value) }) }
    function setTransform(name, value) { resize(name, { transform: Number(value) }) }
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
        // A monitor coming back keeps its old place, which may be under a
        // neighbour that moved in the meantime.
        if (Logic.enabledCount(next) > 0 && !confirming) draft = value ? Logic.spread(next) : next
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

    // Merged into the file, so the screens of a desk that is not connected
    // now keep their entries; see Logic.kept for the lid. A repair still
    // waiting was made from the file before this one and would write it
    // back over the Keep.
    function keep() {
        if (!confirming) return false
        countdown = 0
        countdownTimer.stop()
        repaired = null
        repairWrite.stop()
        saved = Logic.kept(saved, draft, internalName, lidClosed, lidRestore)
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
        if (lockProcess || !savedLoaded) return
        const plan = Logic.savedTarget(monitors, saved, internalName, lidClosed, lidKnown)
        if (!plan) return
        const base = plan.base
        const target = plan.target
        if (plan.held) lidHeld = true
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
        // A file whose positions had to be spread apart is rewritten with the
        // corrected ones, once, so the next login does not start by
        // correcting it again. From the lid-free layout (the lid's disabling
        // is runtime only), and from a timer rather than from here, which may
        // be running inside the file's own `loaded` handler: one FileView
        // write per turn, or the read is dropped.
        if (saved && !confirming) {
            const corrected = Logic.repairSaved(saved, base, internalName)
            if (corrected) { repaired = corrected; repairWrite.restart() }
        }
    }
    property var repaired: null
    Timer {
        id: repairWrite
        interval: 1500
        onTriggered: {
            if (root.repaired && !root.confirming) {
                root.saved = root.repaired
                savedFile.setText(JSON.stringify(root.saved, null, 2) + "\n")
            }
            root.repaired = null
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
        onExited: {
            if (!root.refreshQueued) return
            root.refreshQueued = false
            Qt.callLater(root.refresh)
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
        // No file is a file read: the startup apply still runs on the first
        // monitors, because a lid shut at login needs it even without one
        // (Logic.savedTarget). It was marked done here, and when the lid's
        // answer came before the first monitors - it usually does - the
        // panel stayed on behind the shut lid with a workspace on it.
        onLoadFailed: {
            root.savedLoaded = true
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
