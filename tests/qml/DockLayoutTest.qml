import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/dock/DockLogic.js" as D

// The dock's layout in layout.json (LayoutLogic: zones of pills like the
// bar's, the dock's own pins, kept in a profile's state), the bar's
// operations on it, its two shipped presets, and where its zones go along it.
ShellRoot {
    FileView { id: taskbarFile; path: Qt.resolvedUrl("../../config/dock-presets/taskbar.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: dockFile; path: Qt.resolvedUrl("../../config/dock-presets/dock.json").toString().replace("file://", ""); blockLoading: true }

    function types(zone) { return zone.map(pill => pill.items.map(item => item.type).join("+")) }

    Component.onCompleted: {
        // ---- the default and sanitizing -----------------------------------------
        const fresh = L.defaultDock()
        T.eq(types(fresh.center), ["apps"], "the default dock is its apps, in the middle")
        T.eq(fresh.pins, ["@files", "@terminal", "@settings", "@browser"], "pinned: files, terminal, Settings, browser")
        T.eq(L.sanitizeDock(null), fresh, "nothing stored: the default")
        T.eq(L.sanitize({}).dock, fresh, "a layout file without a dock gets the default")
        const odd = L.sanitizeDock({ left: [{ id: "pill-1", items: [{ type: "clock" }] }, { id: "pill-1", items: [{ type: "date" }] }],
                                    center: [{ items: [] }], pins: ["org.kde.dolphin.desktop", "@terminal", "@nope", "a b", "@terminal"] })
        T.eq(odd.left.map(pill => pill.id), ["dock-pill-1", "dock-pill"], "pill ids start with dock-, and stay unique")
        T.eq(odd.center, [], "an empty pill is no pill")
        T.eq(odd.pins, ["org.kde.dolphin", "@terminal"], "pins: ids without .desktop, known defaults, once each")
        T.eq(L.sanitizeDock({ left: [] }).pins, fresh.pins, "no pins stored: the default ones")
        T.eq(L.sanitizeDock({ left: [], pins: [] }).pins, [], "but an empty list stays empty")
        const many = L.sanitizeDock({ pins: Array.from({ length: 20 }, (_, i) => "app" + i) })
        T.eq(many.pins.length, L.DOCK_PIN_LIMIT, "at most the limit")

        // ---- the bar's operations on the dock ---------------------------------------
        let dock = L.dockZoneOp(fresh, L.addPill, ["right", "clock", "full"])
        T.eq(types(dock.right), ["clock"], "a widget added to a zone")
        T.ok(dock.right[0].id.indexOf("dock-") === 0, "with a dock- id (" + dock.right[0].id + ")")
        T.eq(dock.pins, fresh.pins, "the pins kept")
        dock = L.dockZoneOp(dock, L.addItem, [dock.right[0].id, "date", "full"])
        T.eq(types(dock.right), ["clock+date"], "an item added to a pill")
        dock = L.dockZoneOp(dock, L.movePillTo, [dock.right[0].id, "left", 0])
        T.eq([types(dock.left), dock.right.length], [["clock+date"], 0], "a pill moved to another zone")
        dock = L.dockZoneOp(dock, L.removePill, [dock.left[0].id])
        T.eq(dock.left, [], "and removed")
        T.eq(L.findPill(dock, "dock-apps"), { zone: "center", index: 0 }, "the bar's lookup finds a dock pill")

        // ---- pins -------------------------------------------------------------------
        dock = L.dockPinAt(fresh, "org.kde.kate")
        T.eq(dock.pins[dock.pins.length - 1], "org.kde.kate", "pinned at the end")
        dock = L.dockPinAt(dock, "org.kde.kate", 0)
        T.eq(dock.pins[0], "org.kde.kate", "moved to the front, not doubled")
        T.eq(dock.pins.length, 5, "five pins")
        dock = L.dockUnpin(dock, "org.kde.kate.desktop")
        T.eq(dock.pins, fresh.pins, "unpinned by id, .desktop or not")
        T.ok(L.dockPinned(fresh, "@terminal") && !L.dockPinned(fresh, "x"), "dockPinned")
        const full = L.sanitizeDock({ pins: Array.from({ length: L.DOCK_PIN_LIMIT }, (_, i) => "app" + i) })
        T.eq(L.dockPinAt(full, "more").pins, full.pins, "nothing new past the limit")
        T.eq(L.dockPinAt(full, "app5", 0).pins[0], "app5", "but a pinned one still moves")

        // ---- a profile keeps its dock ----------------------------------------------------
        const state = L.sanitizeProfileState({ settings: {}, dock: { center: [{ id: "dock-apps", items: [{ type: "apps" }] }], pins: ["x"] } })
        T.eq(state.dock.pins, ["x"], "a profile's state keeps its dock")
        T.eq(L.sanitizeProfileState({ settings: {} }).dock, null, "a state without one leaves the dock as it is")
        const restored = L.restoreStateLayout(L.sanitize({}), state)
        T.eq(restored.dock.pins, ["x"], "entering the profile puts it back")

        // ---- the shipped presets -----------------------------------------------------------
        const taskbar = L.sanitizeDockPreset(JSON.parse(taskbarFile.text()))
        const dockPreset = L.sanitizeDockPreset(JSON.parse(dockFile.text()))
        T.eq([taskbar.id, taskbar.label, dockPreset.id, dockPreset.label], ["taskbar", "Taskbar", "dock", "Dock"], "both presets read")
        T.eq(types(taskbar.layout.left), ["start", "apps"], "taskbar: the start button, then the apps")
        T.eq(types(taskbar.layout.right), ["network+volume+battery", "notificationIndicator", "clock+date"],
             "taskbar: status, notifications and the clock on the right")
        T.eq(taskbar.layout.pins, ["@files", "@terminal", "@settings", "@browser"], "taskbar: files, terminal, Settings, browser")
        T.eq([taskbar.options.span, taskbar.options.visibility, taskbar.options.margin], ["full", "always", 0], "taskbar: the whole edge, always there")
        T.eq([dockPreset.options.span, dockPreset.options.visibility], ["fit", "intellihide"], "dock: fit, hiding for windows")
        T.eq(types(dockPreset.layout.center), ["apps"], "dock: the apps in the middle")
        for (const preset of [taskbar, dockPreset])
            for (const key of Object.keys(preset.options))
                T.ok(D.optionValue(key, String(preset.options[key])) !== null, preset.id + ": " + key + " is a value the dock takes")
        T.eq(L.sanitizeDockPreset({ options: {} }), null, "a preset without a label is none")

        // ---- zones along the dock ------------------------------------------------------------
        T.eq(D.zonesLength([100, 0, 50], 12), 162, "the zones' length: what they hold and one gap between them")
        T.eq(D.zonesLength([0, 0, 0], 12), 0, "nothing")
        T.eq(D.zoneStarts([100, 0, 50], false, 200, 6, 12), [6, 118, 118], "fit: one after the other, an empty one takes no room")
        T.eq(D.zoneStarts([100, 40, 50], true, 1000, 6, 12), [6, 480, 944], "full: start, centred, end")
        T.eq(D.zoneStarts([600, 40, 50], true, 1000, 6, 12)[1], 618, "the centre never under the start zone")
        T.eq(D.zoneStarts([10, 300, 650], true, 1000, 6, 12)[1], 32, "nor under the end zone, as far as it can")

        // ---- defaults and starting ---------------------------------------------------------------
        const categories = [{ id: "terminal", current: "Alacritty.desktop" }, { id: "browser", current: "brave-browser.desktop" }]
        T.eq([D.pinCategory("@terminal"), D.pinCategory("@files"), D.pinCategory("@settings"), D.pinCategory("kitty")],
             ["terminal", "files", "", ""], "the defaults' categories")
        T.eq(D.defaultFor("@terminal", categories), "Alacritty", "the default terminal now")
        T.eq(D.defaultFor("@browser", categories), "brave-browser", "the default browser")
        T.eq(D.defaultFor("@files", categories), "", "not read yet: nothing")
        T.eq(D.defaultFor("kitty", categories), "", "an id is not a default")
        T.ok(D.launchSettled(2, 1, 0, 100, 10000), "a window more than before: started")
        T.ok(!D.launchSettled(1, 1, 0, 100, 10000), "not yet")
        T.ok(D.launchSettled(1, 1, 0, 10000, 10000), "given up after the limit")
        T.eq(D.dropPlan({ pin: "@terminal", entryId: "Alacritty", pinned: true }, 0, ["@files", "@terminal"], 12),
             { action: "move", id: "@terminal", index: 0 }, "a default is moved by its token")
        T.eq(D.dropPlan({ pin: "@settings", entryId: "shell-settings", pinned: true, special: "settings" }, 1, ["@settings", "x"], 12),
             { action: "move", id: "@settings", index: 1 }, "Settings too")

        T.finish("DockLayoutTest")
    }
}
