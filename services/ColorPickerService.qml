pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "color/ColorLogic.js" as Logic

// Picking a colour off the screen (Super+Shift+C).
//
// The screen is frozen once, into `$XDG_RUNTIME_DIR`, and the overlay shows
// those frames: a live screen and a sampled capture drift apart the moment
// anything under the pointer animates, and then the swatch lies about what
// was picked. `scripts/color-picker.py` holds the frames open and answers a
// coordinate with a hex colour, one process rather than one per sample.
//
// The history is a comma-string in settings.json, because SettingsService
// cannot store a list at all - `sanitizedNode` rebuilds every object with
// `Object.keys` and turns an array into {"0": ...} on the next write of any
// setting. The same reason `autostart.apps` is one.
Singleton {
    id: root

    readonly property string captureDir: Paths.runtimeDir + "/color-picker"
    property bool active: false
    property bool ready: false
    // [{ name, x, y, width, height, file }] - the frozen frames, in global
    // compositor coordinates.
    property var frames: []
    // The colour under the pointer right now, and the point it was read at.
    property string hovered: ""
    property real pointerX: 0
    property real pointerY: 0

    readonly property var history: Logic.parseHistory(SettingsService.value("colorPicker.history"))

    function open() {
        if (active) return
        hovered = ""
        frames = []
        ready = false
        active = true
        helper.running = true
    }

    function close() {
        active = false
        ready = false
        frames = []
        hovered = ""
        helper.running = false
    }

    // Where the pointer is, in global compositor coordinates. The helper is
    // asked for that point and answers on its own line.
    function sample(x, y) {
        pointerX = x
        pointerY = y
        if (!ready || !helper.running) return
        helper.write(Math.round(x) + " " + Math.round(y) + "\n")
    }

    // Take the colour under the pointer: to the clipboard, to the front of the
    // history, and the overlay closes.
    function pick() {
        const colour = hovered
        if (!colour.length) return
        Quickshell.execDetached(["wl-copy", "--", colour])
        SettingsService.set("colorPicker.history", Logic.addToHistory(history, colour))
        close()
    }

    function clearHistory() { SettingsService.set("colorPicker.history", "") }
    function copy(colour) {
        if (Logic.isColour(colour)) Quickshell.execDetached(["wl-copy", "--", colour])
    }

    Process {
        id: helper
        command: [Paths.script("color-picker.py"), "capture", root.captureDir]
        stderr: ErrorLog { label: "ColorPickerService.helper" }
        stdout: SplitParser {
            onRead: data => {
                const line = String(data)
                if (!root.ready) {
                    // The first line is the frames it froze.
                    try { root.frames = JSON.parse(line) } catch (error) {
                        console.warn("buchhwin-shell: colour picker sent no frames:", error)
                        root.close()
                        return
                    }
                    root.ready = root.frames.length > 0
                    if (!root.ready) root.close()
                    else root.sample(root.pointerX, root.pointerY)
                    return
                }
                root.hovered = Logic.isColour(line.trim()) ? line.trim() : ""
            }
        }
        // The helper dying is the overlay's cue to go: it has nothing left to
        // sample, and a picker that answers nothing is worse than none.
        onRunningChanged: if (!running && root.active) root.close()
    }
}
