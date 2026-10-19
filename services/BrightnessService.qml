pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "brightness/DdcLogic.js" as Ddc
import "display/DisplayLogic.js" as Display
import "lock/LockLogic.js" as LockLogic

// Backlight brightness: read from sysfs, written through brightnessctl with a
// short debounce. Hardware key changes arrive as udev events.
//
// And the external monitors' brightness over DDC/CI (ddcutil, DdcLogic): one
// level per monitor that answers, asked once per hotplug and only once
// something wants it - Settings > Displays opened, or a brightness key
// pressed while an external screen has the focus. Nothing runs before, and
// nothing at all without an external monitor.
Singleton {
    id: root
    property string device: ""
    property int maximum: 0
    property int current: 0
    property real pending: -1
    // Changes made by the shell itself (dim before screen off) skip the OSD.
    property real quietUntil: 0
    readonly property bool available: device.length > 0 && maximum > 0
    readonly property real value: available ? current / maximum : 0
    // A nested session's shell sees the host's backlight and never writes
    // it: `brightness preview` (shell.qml) shows the OSD there instead.
    readonly property bool writable: Quickshell.env("BUCHHWIN_NESTED") !== "1"

    function refresh() {
        if (!device.length) return
        brightnessFile.reload()
        maxFile.reload()
    }

    function set(ratio) {
        if (!available || !writable) return
        pending = Math.max(0.01, Math.min(1, ratio))
        current = Math.round(pending * maximum)
        debounce.restart()
    }

    // Exact raw value, written at once (the idle dim stage restores the
    // previous brightness unchanged). `quiet` hides the OSD.
    function setRaw(raw, quiet) {
        if (!available || !writable) return
        const target = Math.max(1, Math.min(maximum, Math.round(raw)))
        if (quiet) quietUntil = Date.now() + 1500
        debounce.stop()
        pending = -1
        current = target
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", String(target)])
    }

    // The brightness keys (`brightness up|down`, a global shortcut from
    // hypr/hyprland.lua): the brightnessctl call the bind used to run itself,
    // then the re-read its `ipc call brightness refresh` tail asked for (the
    // udev monitor below sees the change too - amdgpu does send a change
    // uevent for every write, checked 15.10. - but only after its debounce,
    // and it is what keeps a change made outside the shell in view, so it
    // stays even where the keys re-read). A held key repeats about 25 times a
    // second, and every repeat started sh, brightnessctl and the Quickshell
    // IPC client; now it is brightnessctl alone. Presses that come while one
    // runs are added up and sent as one step when it is done (two presses up
    // are `set 10%+`, up and down cancel), so none is lost and the direction
    // is theirs.
    //
    // With an external screen focused the keys act on that screen (DDC, see
    // below) when it answers; the laptop panel, a screen that does not
    // answer and the setting off keep the backlight, as before.
    property int queuedSteps: 0
    function step(direction) {
        const steps = direction > 0 ? 1 : -1
        const target = ddcKeyTarget()
        if (target === "wait") { waitForDetection(steps); return }
        if (target.length) { stepDdc(target, steps); return }
        backlightSteps(steps)
    }
    function backlightSteps(steps) {
        if (!writable || steps === 0) return
        queuedSteps += steps
        if (!stepProc.running) sendSteps()
    }
    function sendSteps() {
        if (queuedSteps === 0) return
        const steps = queuedSteps
        queuedSteps = 0
        stepProc.command = ["brightnessctl", "-q", "-e4", "-n2", "set", Math.abs(steps) * 5 + "%" + (steps > 0 ? "+" : "-")]
        stepProc.running = true
    }
    Process {
        id: stepProc
        stderr: ErrorLog { label: "BrightnessService.stepProc" }
        onExited: {
            root.refresh()
            root.sendSteps()
        }
    }

    Process {
        stderr: ErrorLog { label: "BrightnessService.process" }
        running: true
        command: ["sh", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.device = text.trim() }
    }

    FileView {
        id: maxFile
        path: root.device.length ? "/sys/class/backlight/" + root.device + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.maximum = parseInt(text()) || 0
    }

    FileView {
        id: brightnessFile
        path: root.device.length ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        printErrors: false
        onLoaded: if (root.pending < 0) root.current = parseInt(text()) || 0
    }

    Timer {
        id: debounce
        interval: 60
        onTriggered: {
            if (root.pending < 0) return
            Quickshell.execDetached(["brightnessctl", "-q", "-d", root.device, "set", Math.round(root.pending * 100) + "%"])
            root.pending = -1
        }
    }

    // Restarted after a pause if it ever exits, like NetworkService's
    // monitor: without it the slider and the OSD stop following the keys.
    property bool monitorPaused: false
    Process {
        stderr: ErrorLog { label: "BrightnessService.process" }
        running: root.device.length > 0 && !root.monitorPaused
        command: Paths.bound(["udevadm", "monitor", "--udev", "--subsystem-match=backlight"])
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("backlight") >= 0) reloadTimer.restart() }
        }
        onRunningChanged: {
            if (running || root.device.length === 0 || root.monitorPaused) return
            root.monitorPaused = true
            monitorRestart.restart()
        }
    }
    Timer { id: monitorRestart; interval: 5000; onTriggered: root.monitorPaused = false }

    Timer { id: reloadTimer; interval: 50; onTriggered: root.refresh() }

    // ---- What the OSD shows -------------------------------------------------
    // The level the brightness keys changed last: the backlight's, or an
    // external screen's (`osdName`). A backlight change takes it back.
    property string osdName: ""
    readonly property real osdLevel: {
        const display = osdName.length ? ddcDisplay(osdName) : null
        return display ? Ddc.toRatio(display.value, display.max) : value
    }
    // A key changed an external screen's brightness: the OSD shows `osdLevel`.
    signal ddcStepped()
    onValueChanged: osdName = ""

    // ---- External monitors over DDC/CI --------------------------------------
    //
    // ddcutil, with the seat's access to the display buses that its udev rule
    // gives (no i2c group needed). Never in the lock's process, and in a
    // nested session only with a stand-in named in BUCHHWIN_DDCUTIL: a nested
    // shell sees the host's monitors and must not change them.
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)
    readonly property string ddcProgram: lockProcess ? "" : writable ? "ddcutil" : (Quickshell.env("BUCHHWIN_DDCUTIL") || "")
    // Settings > Displays > "Brightness of external displays".
    readonly property bool ddcEnabled: ddcProgram.length > 0 && SettingsService.value("display.ddc") !== false
    // Something has asked for the levels this session (a page, a key, IPC):
    // from then on a hotplug detects again. Until then nothing runs.
    property bool ddcWanted: false
    // idle (nothing asked or nothing connected), detecting, ready, missing
    // (no ddcutil).
    property string ddcState: "idle"
    // [{ name, description, bus, value, max, pending, read, failed, keySteps }]
    // for the monitors that answered, replaced as a whole on every change.
    property var ddcDisplays: []
    // The external monitors `ddcDisplays` were detected for (DdcLogic.externalKey).
    property string ddcKey: ""
    readonly property string externalKey: ddcEnabled ? Ddc.externalKey(DisplayService.monitors, DisplayService.internalName) : ""
    readonly property bool ddcCurrent: ddcState === "ready" && ddcKey.length > 0 && ddcKey === externalKey
    // The last level of each monitor that answered, by description: one
    // plugged in again has its slider at once, before its read.
    property var ddcCache: ({})

    onExternalKeyChanged: {
        if (!externalKey.length) { ddcForget(); return }
        // Monitors arrive one by one while a dock settles: one detection
        // after they have, not one per monitor.
        if (ddcWanted) hotplugWait.restart()
    }
    onDdcEnabledChanged: if (!ddcEnabled) ddcForget()
    Timer { id: hotplugWait; interval: 2000; onTriggered: root.ddcDetect() }

    // Asked for by whatever shows the levels (Settings > Displays) or needs
    // them (a key): detects when the monitors have not been yet.
    function ddcDemand() {
        if (!ddcEnabled) return
        ddcWanted = true
        // Without ddcutil the next hotplug asks again, not every open of the
        // page.
        if (ddcState === "missing") return
        if (externalKey.length && !ddcCurrent && ddcState !== "detecting" && !hotplugWait.running) ddcDetect()
    }
    function ddcDetect() {
        if (!ddcEnabled || !externalKey.length) return
        ddcWanted = true
        detectWanted = true
        ddcState = "detecting"
        ddcPump()
    }
    function ddcForget() {
        hotplugWait.stop()
        detectWanted = false
        ddcDisplays = []
        ddcKey = ""
        ddcState = "idle"
        osdName = ""
        releaseWaitingSteps(false)
    }

    function ddcDisplay(name) {
        return ddcCurrent ? (ddcDisplays.find(item => item.name === name && !item.failed) || null) : null
    }
    // For `brightness get`: each monitor that answered, by connector name,
    // with its level in percent (null until read).
    function ddcSummary() {
        return ddcCurrent ? ddcDisplays.filter(item => !item.failed)
            .map(item => ({ name: item.name, level: item.max > 0 ? Math.round(Ddc.toRatio(item.value, item.max) * 100) : null })) : []
    }
    // A monitor's level as 0-1, for a slider; 0 for one without.
    function ddcLevel(name) {
        const display = ddcDisplay(name)
        return display ? Ddc.toRatio(display.value, display.max) : 0
    }
    // What Settings > Displays says for a monitor: "ready" (a slider),
    // "checking", "none" (it did not answer), "missing" (no ddcutil), "off",
    // or "" for the laptop panel and a monitor that is off.
    function ddcStatus(name) {
        const live = DisplayService.monitors.find(item => item.name === name) || null
        if (!live || live.disabled || Display.isPanel(name, DisplayService.internalName) || Display.isInternal(name)) return ""
        if (!ddcEnabled) return "off"
        if (ddcState === "missing") return "missing"
        const display = ddcDisplay(name)
        if (display) return display.max > 0 ? "ready" : "checking"
        return ddcState === "detecting" || hotplugWait.running || !ddcCurrent ? "checking" : "none"
    }

    function patchDisplay(name, patch) {
        ddcDisplays = ddcDisplays.map(item => item.name === name ? Object.assign({}, item, patch) : item)
    }

    // A slider (0-1). The newest value wins: a drag is many of these and
    // only where it is when ddcutil is free again is written.
    function setDdc(name, ratio) {
        const display = ddcDisplay(name)
        if (!display || !(display.max > 0) || !isFinite(ratio)) return false
        const target = Ddc.fromRatio(ratio, display.max)
        patchDisplay(name, { value: target, pending: target })
        ddcPump()
        return true
    }
    // `steps` key presses on a monitor (negative is down). Before its level
    // is known they wait for the read.
    function stepDdc(name, steps) {
        const display = ddcDisplay(name)
        if (!display) { backlightSteps(steps); return }
        if (!(display.max > 0)) { patchDisplay(name, { keySteps: (display.keySteps || 0) + steps }); return }
        const from = display.pending >= 0 ? display.pending : display.value
        const target = Ddc.stepped(from, display.max, steps)
        patchDisplay(name, { value: target, pending: target })
        osdName = name
        ddcStepped()
        ddcPump()
    }

    // Where a brightness key goes: "" for the backlight, a monitor's name,
    // or "wait" while the focused external screen has not been asked yet.
    function ddcKeyTarget() {
        if (!ddcEnabled) return ""
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        if (!name.length || Display.isPanel(name, DisplayService.internalName) || Display.isInternal(name)) return ""
        const live = DisplayService.monitors.find(item => item.name === name)
        if (!live || live.disabled) return ""
        if (ddcState === "missing") return ""
        if (ddcCurrent) return ddcDisplay(name) ? name : ""
        return "wait"
    }
    // The first key on an external screen asks the monitors; the presses
    // wait for the answer (a few seconds at most) and then go to that screen
    // or, where it did not answer, to the backlight as before.
    property string waitingName: ""
    property int waitingSteps: 0
    function waitForDetection(steps) {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        if (name !== waitingName) { releaseWaitingSteps(false); waitingName = name }
        waitingSteps += steps
        if (!keyWait.running) keyWait.restart()
        ddcDemand()
    }
    function releaseWaitingSteps(toDisplay) {
        keyWait.stop()
        const name = waitingName, steps = waitingSteps
        waitingName = ""
        waitingSteps = 0
        if (!steps) return
        if (toDisplay && ddcDisplay(name)) stepDdc(name, steps)
        else backlightSteps(steps)
    }
    // A dock that hangs DDC must not hold the keys for the whole of
    // ddcutil's timeout: after this the waiting presses go to the backlight.
    Timer { id: keyWait; interval: 4000; onTriggered: root.releaseWaitingSteps(false) }

    // One ddcutil at a time (DdcLogic.nextJob).
    property bool detectWanted: false
    property string detectKey: ""
    property var ddcJob: null
    function ddcPump() {
        if (ddcProc.running || !ddcEnabled || !ddcProgram.length) return
        const next = Ddc.nextJob(detectWanted, ddcCurrent || detectWanted ? ddcDisplays : [])
        if (!next) return
        ddcJob = next
        if (next.kind === "detect") {
            detectWanted = false
            detectKey = externalKey
            ddcProc.command = Ddc.detectCommand(ddcProgram)
        } else if (next.kind === "write") {
            patchDisplay(next.name, { pending: -1 })
            ddcProc.command = Ddc.writeCommand(ddcProgram, next.bus, next.value)
        } else {
            ddcProc.command = Ddc.readCommand(ddcProgram, next.bus)
        }
        ddcProc.running = true
    }
    function ddcFinished(code) {
        const done = ddcJob
        ddcJob = null
        if (!done || !ddcEnabled) return
        if (done.kind === "detect") {
            // `timeout` exits 127 for a program that is not there.
            if (code === 127 || code === 126) {
                ddcState = "missing"
                ddcDisplays = []
                releaseWaitingSteps(false)
                return
            }
            const found = code === 0 ? Ddc.match(Ddc.parseDetect(ddcOut.text), DisplayService.monitors, DisplayService.internalName) : []
            if (code !== 0) console.warn("buchhwin-shell: BrightnessService: ddcutil detect ended with", code)
            ddcDisplays = found.map(item => {
                const known = ddcCache[item.description] || null
                return Object.assign({}, item, { value: known ? known.value : 0, max: known ? known.max : 0,
                                                 pending: -1, read: false, failed: false, keySteps: 0 })
            })
            ddcKey = detectKey
            ddcState = "ready"
            // The monitors changed while it ran: once more for the new set.
            if (detectKey !== externalKey && externalKey.length) { detectWanted = true; ddcState = "detecting" }
            else releaseWaitingSteps(true)
        } else if (done.kind === "read") {
            const level = code === 0 ? Ddc.parseVcp(ddcOut.text) : null
            const display = ddcDisplays.find(item => item.name === done.name) || null
            if (level && display) {
                // A write asked for meanwhile wins over what was read.
                const value = display.pending >= 0 ? display.pending : level.value
                patchDisplay(done.name, { value: value, max: level.max, read: true })
                remember(display.description, value, level.max)
                if (display.keySteps) { patchDisplay(done.name, { keySteps: 0 }); stepDdc(done.name, display.keySteps) }
            } else if (display) {
                giveUp(display, "read", code)
            }
        } else if (done.kind === "write") {
            const display = ddcDisplays.find(item => item.name === done.name) || null
            if (code !== 0 && display) giveUp(display, "write", code)
            else if (display) remember(display.description, done.value, display.max)
        }
        Qt.callLater(root.ddcPump)
    }
    // A monitor that stopped answering (or timed out) has no slider until the
    // next hotplug, and says so once in the log - the bus number only.
    function giveUp(display, kind, code) {
        patchDisplay(display.name, { failed: true, pending: -1 })
        if (osdName === display.name) osdName = ""
        console.warn("buchhwin-shell: BrightnessService: DDC " + kind + " on bus " + display.bus + " ended with " + code
                     + "; that display has no brightness control until it is plugged in again")
    }
    function remember(description, value, max) {
        if (!String(description || "").length || !(max > 0)) return
        const next = Object.assign({}, ddcCache)
        next[description] = { value: value, max: max }
        ddcCache = next
    }
    Process {
        id: ddcProc
        stdout: StdioCollector { id: ddcOut }
        // Collected, not logged line by line: ddcutil's own messages name the
        // monitor's model, and the outcome is logged once by giveUp.
        stderr: StdioCollector {}
        // Quickshell ends the collectors before `exited` (testing.md pitfall
        // 131), so the whole answer is there.
        onExited: code => root.ddcFinished(code)
    }
}
