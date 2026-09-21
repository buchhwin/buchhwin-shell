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

    Process {
        stderr: ErrorLog { label: "BrightnessService.process" }
        running: root.device.length > 0
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("backlight") >= 0) reloadTimer.restart() }
        }
    }

    Timer { id: reloadTimer; interval: 50; onTriggered: root.refresh() }
}
