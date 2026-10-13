import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// LayoutService itself, against the runner's sandboxed XDG_CONFIG_HOME: a
// missing layout.json loads as an empty, writable layout; two edits in one
// turn of the event loop are one pending text and one write; and the write
// lands in layout.json with both. The load is asynchronous (the file is
// missing, and `loadFailed` is what loads the empty layout), so it is polled
// for rather than assumed - and so is the write, which is a zero-interval
// Timer and an asynchronous file operation away. Then the placement reports:
// a widget window reports its rectangle on every change of its geometry, and
// the same rectangle twice must not announce itself twice. Last, the notch
// options: settings, but changed where an undo is within reach (the editor,
// Bar & Notch), so `changeNotch` takes an undo step and `undo` brings them
// back.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property int rectSignals: 0

    Connections {
        target: LayoutService
        function onPlacementRectsChanged() { root.rectSignals += 1 }
    }

    FileView {
        id: written
        path: Paths.configDir + "/layout.json"
        blockLoading: true
        printErrors: false
    }

    function activeBar(document) {
        return document.profiles[LayoutService.activeProfile].modes[LayoutService.activeMode].bar
    }

    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!LayoutService.loaded && root.waits < 100) return
            stop()
            T.ok(LayoutService.loaded, "the layout loads in the sandbox (" + Paths.configDir + ")")
            T.eq(LayoutService.readOnly, false, "a missing file is an empty layout, not a read-only one")
            T.eq(LayoutService.setBarOption("edge", "bottom"), true, "a bar option is taken")
            T.eq(LayoutService.setBarOption("style", "bar"), true, "and a second one in the same turn")
            const pending = root.activeBar(JSON.parse(LayoutService.pendingText))
            T.eq(pending.edge, "bottom", "one pending text holds the first")
            T.eq(pending.style, "bar", "and the second")
            T.eq(LayoutService.bar.edge, "bottom", "the value is live before the write")
            settle.start()
        }
    }

    Timer {
        id: settle
        interval: 100
        repeat: true
        onTriggered: {
            root.tries += 1
            written.reload()
            let parsed = null
            try { parsed = JSON.parse(written.text()) } catch (error) { parsed = null }
            const bar = parsed ? root.activeBar(parsed) : null
            if ((!bar || bar.edge !== "bottom" || bar.style !== "bar") && root.tries < 50) return
            stop()
            T.ok(parsed !== null, "layout.json was written in the sandbox")
            T.ok(bar !== null && bar.edge === "bottom", "the file holds the first option")
            T.ok(bar !== null && bar.style === "bar", "and the second")
            placementReports.start()
        }
    }

    // Its own turn, after the write above has landed, like the phase below.
    Timer {
        id: placementReports
        interval: 50
        onTriggered: {
            const rect = { x: 10, y: 20, width: 300, height: 40 }
            root.rectSignals = 0
            LayoutService.reportRect("screen-a", "widget-1", rect)
            T.eq(root.rectSignals, 1, "a placement report announces itself")
            T.eq(LayoutService.placementRects["screen-a/widget-1"].width, 300, "and is kept")
            LayoutService.reportRect("screen-a", "widget-1", { x: 10, y: 20, width: 300, height: 40 })
            T.eq(root.rectSignals, 1, "the same rectangle again does not announce itself a second time")
            LayoutService.reportRect("screen-a", "widget-1", { x: 10, y: 20, width: 300, height: 48 })
            T.eq(root.rectSignals, 2, "a rectangle with one side changed does")
            LayoutService.reportRect("screen-b", "widget-1", { x: 10, y: 20, width: 300, height: 48 })
            T.eq(root.rectSignals, 3, "and so does the same rectangle on another screen")
            notchOptions.start()
        }
    }

    // Its own turn of the event loop, after the layout write above has landed:
    // one FileView write per turn (docs/testing.md, Pitfalls).
    Timer {
        id: notchOptions
        interval: 50
        onTriggered: {
            const cases = [
                ["notch.reserve", !SettingsService.value("notch.reserve")],
                ["notch.eventCount", SettingsService.value("notch.eventCount") === 3 ? 2 : 3],
                ["notch.bodyHeight", SettingsService.value("notch.bodyHeight") === 32 ? 40 : 32],
                ["notch.fullscreen", SettingsService.value("notch.fullscreen") === "show" ? "hide" : "show"]
            ]
            for (let i = 0; i < cases.length; i++) {
                const key = cases[i][0]
                const next = cases[i][1]
                const before = SettingsService.value(key)
                const depth = LayoutService.undoStack.length
                T.eq(LayoutService.changeNotch(key, next), true, key + " is a notch option")
                T.eq(SettingsService.value(key), next, key + " is set")
                T.eq(LayoutService.undoStack.length, depth + 1, key + " took one undo step")
                LayoutService.undo()
                T.eq(SettingsService.value(key), before, key + " comes back with undo")
                T.eq(LayoutService.undoStack.length, depth, key + " and the step is gone")
            }
            T.eq(LayoutService.changeNotch("notch.displayOsd", false), false,
                 "a notch setting that is not a layout option is refused")
            T.finish("LayoutService")
        }
    }
}
