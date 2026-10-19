pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "power/KbdBacklightLogic.js" as Logic

// Keyboard backlight, the same shape as BrightnessService: read from sysfs,
// written through brightnessctl. The LED node belongs to root, so brightnessctl
// goes through logind for it, exactly as it does for the screen.
//
// Two things differ, and both are the hardware's doing rather than a choice.
//
// It is a *stepped* light. `max_brightness` is 2 on ThinkPads, so three
// levels; a percentage would read 0/50/100 on a track that looks like a
// hundred. `KbdBacklightLogic` names the step and says how many boxes the OSD
// should draw, out of `maximum` and never out of a three written in the code.
//
// And the LED class sends no udev event for a new level, so there is nothing
// to subscribe to the way the backlight has `udevadm monitor`. The shell's own
// keys (XF86KbdBrightness*) need none: they go through `nudge`, which knows
// the level it set. A change the firmware makes itself - Fn+Space on a
// ThinkPad, which sends no key at all - the LED class marks in
// `brightness_hw_changed`, and the kernel's notify on that file reaches
// inotify: watched (never read; it reads "no data" until the first such
// change), it is the cue to re-read the level, and the OSD shows it like a key
// press would. UPower's KbdBacklight object reports the same as
// BrightnessChangedWithSource on the system bus - a broadcast signal any
// session may match, no eavesdrop needed - but listening there would take a
// process of its own for the whole session.
Singleton {
    id: root
    property string device: ""
    property int maximum: 0
    property int current: 0
    readonly property bool available: device.length > 0 && maximum > 0
    readonly property real value: Logic.fraction(current, maximum)
    // What the OSD writes beside the track: the step's name, not a percentage.
    readonly property string label: Logic.label(current, maximum)
    readonly property int segments: Logic.segments(maximum)

    function refresh() {
        if (!device.length) return
        brightnessFile.reload()
        maxFile.reload()
    }

    // `delta` of 0 means the toggle key: off from anywhere, brightest from off.
    function nudge(delta) {
        if (!available) return
        write(delta === 0 ? Logic.toggle(current, maximum) : Logic.step(current, maximum, delta))
    }

    function write(level) {
        if (!available) return
        const target = Logic.clamp(level, maximum)
        if (target === current) return
        // Shown at once rather than after the re-read: the OSD is the answer
        // to a key press and must not wait for a process to come back.
        current = target
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "leds", "-d", device, "set", String(target)])
        reloadTimer.restart()
    }

    Process {
        stderr: ErrorLog { label: "KbdBacklightService.process" }
        running: true
        command: ["sh", "-c", "ls -1 /sys/class/leds 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.device = Logic.deviceFrom(text) }
    }

    FileView {
        id: maxFile
        path: root.device.length ? "/sys/class/leds/" + root.device + "/max_brightness" : ""
        printErrors: false
        onLoaded: {
            const level = Logic.parseLevel(text())
            if (level !== null) root.maximum = level
        }
    }

    FileView {
        path: root.device.length ? "/sys/class/leds/" + root.device + "/brightness_hw_changed" : ""
        preload: false
        printErrors: false
        watchChanges: true
        onFileChanged: root.refresh()
    }

    FileView {
        id: brightnessFile
        path: root.device.length ? "/sys/class/leds/" + root.device + "/brightness" : ""
        printErrors: false
        onLoaded: {
            const level = Logic.parseLevel(text())
            if (level !== null) root.current = level
        }
    }

    // brightnessctl has to reach logind and the LED has to answer before the
    // file holds the new value; a read that is too early puts the old step
    // back and the OSD flickers between the two.
    Timer { id: reloadTimer; interval: 120; onTriggered: root.refresh() }
}
