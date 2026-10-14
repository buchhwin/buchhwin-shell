pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Backlight brightness: read from sysfs, written through brightnessctl with a
// short debounce. Hardware key changes arrive as udev events.
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

    function refresh() {
        if (!device.length) return
        brightnessFile.reload()
        maxFile.reload()
    }

    function set(ratio) {
        if (!available) return
        pending = Math.max(0.01, Math.min(1, ratio))
        current = Math.round(pending * maximum)
        debounce.restart()
    }

    // Exact raw value, written at once (the idle dim stage restores the
    // previous brightness unchanged). `quiet` hides the OSD.
    function setRaw(raw, quiet) {
        if (!available) return
        const target = Math.max(1, Math.min(maximum, Math.round(raw)))
        if (quiet) quietUntil = Date.now() + 1500
        debounce.stop()
        pending = -1
        current = target
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", String(target)])
    }

    // The brightness keys (`brightness up|down`, a global shortcut from
    // hypr/hyprland.lua): the brightnessctl call the bind used to run itself,
    // then the re-read its `ipc call brightness refresh` tail asked for -
    // amdgpu sends no udev event for it. A held key repeats about 25 times a
    // second, and every repeat started sh, brightnessctl and the Quickshell
    // IPC client; now it is brightnessctl alone. Presses that come while one
    // runs are added up and sent as one step when it is done (two presses up
    // are `set 10%+`, up and down cancel), so none is lost and the direction
    // is theirs.
    property int queuedSteps: 0
    function step(direction) {
        queuedSteps += direction > 0 ? 1 : -1
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
}
