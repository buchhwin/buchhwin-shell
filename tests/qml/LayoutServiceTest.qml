import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// LayoutService itself, against the runner's sandboxed XDG_CONFIG_HOME: a
// missing layout.json loads as an empty, writable layout; two edits in one
// turn of the event loop are one pending text and one write; and the write
// lands in layout.json with both. The load is asynchronous (the file is
// missing, and `loadFailed` is what loads the empty layout), so it is polled
// for rather than assumed - and so is the write, which is a zero-interval
// Timer and an asynchronous file operation away. Then the placement reports:
// a widget window reports its rectangle on every change of its geometry, and
// the same rectangle twice must not announce itself twice. Then the notch
// options: settings, but changed where an undo is within reach (the editor,
// Bar & notch), so `changeNotch` takes an undo step and `undo` brings them
// back. And its own write, read back by the file's watch, is not loaded again.
// Then a mode switch undone, and an automatic one that is no undo step (its
// widgets kept by the undo). Then the dock: a preset undone with its
// options, a change that changes nothing takes no step, and the dock's own
// pieces stay on the dock, once. Last, layout.json is the user's alone (0600).
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property int rectSignals: 0
    property int dockRectSignals: 0

    Connections {
        target: LayoutService
        function onPlacementRectsChanged() { root.rectSignals += 1 }
        function onDockItemRectsChanged() { root.dockRectSignals += 1 }
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
            // Settled too: a first start applies the shipped Default, and
            // its writes would land in the middle of the ones below.
            const there = LayoutService.loaded && LayoutService.stateSettled && !LayoutService.builtinApplying.length
            if (!there && root.waits < 250) return
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
            readBack.start()
        }
    }

    // The watch reads that write back; by now it has. The text is what the
    // service holds already, so it is not parsed again, and no revision
    // re-runs every binding on the layout.
    Timer {
        id: readBack
        interval: 300
        onTriggered: {
            written.reload()
            T.eq(LayoutService.fileText, written.text(), "the service knows the file as it wrote it")
            const revision = LayoutService.revision
            LayoutService.load()
            T.eq(LayoutService.revision, revision, "reading its own write back changes nothing")
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

            // The dock's items report where they are (Pill.reportRects) for
            // the start menu and the panels a key opens out of them.
            root.dockRectSignals = 0
            const start = { x: 0, y: 1040, width: 40, height: 40 }
            LayoutService.reportDockItemRect("screen-a", "start", start)
            T.eq([root.dockRectSignals, LayoutService.dockItemRect("screen-a", "start")], [1, start], "a dock item's place is kept")
            LayoutService.reportDockItemRect("screen-a", "start", { x: 0, y: 1040, width: 40, height: 40 })
            T.eq(root.dockRectSignals, 1, "the same place again announces nothing")
            T.eq(LayoutService.dockItemRect("screen-b", "start"), null, "by screen")
            LayoutService.reportDockItemRect("screen-a", "start", null)
            T.eq([root.dockRectSignals, LayoutService.dockItemRect("screen-a", "start")], [2, null], "null takes it away")
            LayoutService.reportDockItemRect("screen-a", "clock", null)
            T.eq(root.dockRectSignals, 2, "and taking away what is not there announces nothing")
            T.eq(["org.example.App", "Citrix_subscribed_XenApp 7.x.RDS-Sample $S101-255", "@files", "bad/id", "-x", "", "@nothing"]
                     .map(id => LayoutService.dockPinnable(id)),
                 [true, true, true, false, false, false, false], "which ids the dock would take as a pin")
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
            modeUndo.start()
        }
    }

    // A mode switch undone is a switch back, with the mode's own appearance:
    // it used to restore the name only, and the gaps, blur and animations of
    // the mode undone stayed. An automatic switch (a monitor plugged in)
    // takes no step, and undoing the edit before it keeps the mode the
    // machine chose. Not into gaming: its template turns Do Not Disturb on,
    // and the notification server is the session's (pitfall 82).
    Timer {
        id: modeUndo
        interval: 50
        onTriggered: {
            const first = LayoutService.activeMode
            const others = LayoutService.modeNames.filter(name => name !== first && name !== "gaming")
            SettingsService.set("appearance.gapsOut", 7)
            T.eq(L.modeConfig(LayoutService.config, LayoutService.activeProfile, first).appearance.gapsOut, 7,
                 "a mode-scoped setting belongs to the mode in use")
            T.eq(LayoutService.setActiveMode(others[0]), true, "into a second mode")
            T.eq(L.modeConfig(LayoutService.config, LayoutService.activeProfile, others[0]).desktopMode,
                 ({ work: "pills", laptop: "pills", docked: "pills", minimal: "widgets" })[others[0]],
                 "a mode used for the first time takes its surface from its template (round 13)")
            SettingsService.set("appearance.gapsOut", 3)
            const depth = LayoutService.undoStack.length
            LayoutService.undo()
            T.eq(LayoutService.activeMode, first, "undo of the switch switches back")
            T.eq(SettingsService.value("appearance.gapsOut"), 7, "with that mode's own appearance")
            T.eq(LayoutService.undoStack.length, depth - 1, "in one step")

            const edge = L.modeConfig(LayoutService.config, LayoutService.activeProfile, first).bar.edge
            const steps = LayoutService.undoStack.length
            T.eq(LayoutService.setBarOption("edge", edge === "top" ? "bottom" : "top"), true, "an edit")
            T.eq(LayoutService.setActiveMode(others[1], true), true, "then an automatic switch")
            T.eq(LayoutService.undoStack.length, steps + 1, "which takes no step of its own")
            // The machine's mode was first used after the step: its widgets
            // were materialized since, and the step's config has none.
            const machine = L.modeConfig(LayoutService.config, LayoutService.activeProfile, others[1])
            const screensThen = machine.screens.slice()
            const widgetsThen = machine.widgets.length
            LayoutService.undo()
            T.eq(LayoutService.activeMode, others[1], "undo takes the edit back and keeps the mode the machine chose")
            T.eq(L.modeConfig(LayoutService.config, LayoutService.activeProfile, first).bar.edge, edge,
                 "the edit is undone in the mode it was made in")
            const machineAfter = L.modeConfig(LayoutService.config, LayoutService.activeProfile, others[1])
            T.eq(machineAfter.screens, screensThen, "and the machine's mode keeps its screens")
            T.eq(machineAfter.widgets.length, widgetsThen, "and its widgets on them (" + widgetsThen + ")")

            // The user's switch, then the machine's: undoing the user's must
            // not take the machine's mode away again.
            T.eq(LayoutService.setActiveMode(first), true, "a switch of the user's")
            T.eq(LayoutService.setActiveMode(others[2], true), true, "then the machine's")
            LayoutService.undo()
            T.eq(LayoutService.activeMode, others[2], "undoing the user's switch keeps the mode the machine chose since")
            dockSteps.start()
        }
    }

    function dockTypes() {
        const dock = LayoutService.dockLayout
        return ["left", "center", "right"].map(zone => dock[zone].map(pill => pill.items.map(item => item.type).join("+")).join(" "))
    }

    // A dock preset is one step, the layout and the dock.* settings
    // together: undone, the zones came back and the taskbar's options
    // stayed. The step carries them itself, so an unrelated Ctrl+Z leaves
    // what Settings > Dock set alone. The user's own pins stay through a
    // preset. A pin or a move that changes nothing takes no step, and the
    // dock's own pieces stay on the dock, once.
    Timer {
        id: dockSteps
        interval: 50
        onTriggered: {
            T.ok(LayoutService.dockPreset("taskbar") !== null, "the taskbar preset is read")
            const before = { "dock.visibility": "intellihide", "dock.span": "fit", "dock.iconSize": 48, "dock.margin": 8,
                             "dock.enabled": false }
            SettingsService.setAll(before)
            T.eq(LayoutService.dockPin("org.example.Mine"), true, "an app of the user's pinned")
            const pins = LayoutService.dockLayout.pins.slice()
            const zones = dockTypes()
            const depth = LayoutService.undoStack.length
            T.eq(LayoutService.applyDockPreset("taskbar", true), true, "the taskbar applied, the dock switched on with it")
            T.eq([SettingsService.value("dock.span"), SettingsService.value("dock.visibility"), SettingsService.value("dock.enabled")],
                 ["full", "always", true], "with its options")
            T.ok(LayoutService.dockHasStart, "and its start button")
            T.eq(LayoutService.dockLayout.pins, pins, "the user's pins are kept")
            T.eq(LayoutService.undoStack.length, depth + 1, "one step")
            LayoutService.undo()
            for (const key of Object.keys(before))
                T.eq(SettingsService.value(key), before[key], "undo brings " + key + " back")
            T.eq(dockTypes(), zones, "and the zones")
            T.eq(LayoutService.undoStack.length, depth, "the step is gone")

            SettingsService.set("dock.span", "full")
            T.eq(LayoutService.setBarOption("scale", 1.15), true, "an unrelated edit")
            LayoutService.undo()
            T.eq(SettingsService.value("dock.span"), "full", "its undo leaves the dock's options as Settings > Dock set them")

            const steps = LayoutService.undoStack.length
            T.eq(LayoutService.dockPin(LayoutService.dockLayout.pins[0], 0), false, "a pin moved to where it is changes nothing")
            T.eq(LayoutService.dockPin("bad/id"), false, "an id no entry can have is refused")
            T.eq(LayoutService.undoStack.length, steps, "and neither takes a step")
            const citrix = "Citrix_subscribed_XenApp 7.x.RDS-Sample $S101-255"
            T.eq(LayoutService.dockPin(citrix), true, "a Citrix app is pinned")
            T.ok(LayoutService.dockPinned(citrix), "and is on the dock")

            T.eq(LayoutService.pillAdd("bar", "center", "apps", ""), false, "the dock's apps are not put on the bar")
            T.eq(LayoutService.barAddPill("center", "start", ""), false, "nor its start button")
            T.eq(LayoutService.addWidget("", "apps"), "", "nor on the desktop")
            T.eq([LayoutService.quickAdd("start"), LayoutService.dashboardAdd("apps"), LayoutService.notchAdd("apps", "expanded")],
                 [false, false, false], "nor in the control center, the dashboard or the notch")
            T.ok(L.dockHasType(LayoutService.dockLayout, "apps"), "the dock has its apps")
            T.eq(LayoutService.pillAdd("dock", "left", "apps", ""), false, "and gets no second one")
            T.eq(LayoutService.pillAdd("dock", "left", "start", ""), true, "a start button is added")
            T.eq(LayoutService.pillAddItem("dock", LayoutService.dockLayout.left[0].id, "start", ""), false, "once")
            fileMode.running = true
        }
    }

    Process {
        id: fileMode
        command: ["stat", "-c", "%a", "--", Paths.configDir + "/layout.json"]
        stdout: StdioCollector { id: modeText }
        onExited: {
            T.eq(modeText.text.trim(), "600", "layout.json is the user's alone")
            T.finish("LayoutService")
        }
    }
}
