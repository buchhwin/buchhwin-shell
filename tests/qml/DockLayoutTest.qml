import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.theme
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/dock/DockLogic.js" as D
import "../../services/appearance/ContrastLogic.js" as C

// The dock's layout in layout.json (LayoutLogic: zones of pills like the
// bar's, the dock's own pins, kept in a profile's state), the bar's
// operations on it, its two shipped presets, and where its zones go along it.
// And the registry's word on the dock's own pieces (WidgetRegistry, which
// runs nothing), and the editor's frames on it (Colors, in the test's
// settings sandbox).
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
        T.eq(odd.pins, ["org.kde.dolphin", "@terminal", "a b"], "pins: ids without .desktop, known defaults, once each")
        // Citrix's subscribed apps are desktop ids with spaces and '$'
        // (StartupWMClass=RDS-…): "Pin to dock" did nothing for them.
        const citrix = "Citrix_subscribed_XenApp 7.x.RDS-Sample $S101-255"
        T.eq(L.sanitizeDockPins([citrix + ".desktop"]), [citrix], "an id with spaces and '$' is a pin")
        T.eq(L.dockPinAt(fresh, citrix).pins.slice(-1), [citrix], "and can be pinned")
        T.eq(L.dockUnpin(L.dockPinAt(fresh, citrix), citrix).pins, fresh.pins, "and unpinned")
        T.eq(L.sanitizeDockPins(["", "  ", "a\nb", "tab\there", "x/y", "-rf", "@nope", "../up", "a".repeat(300)]), [],
             "but nothing, a control character, a slash, a leading dash, an unknown @ name or a run-on is none")
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

        // A new pill in an earlier zone must not take an untouched pill's
        // id: addPill names it in the bar's way ("pill-3"), and in zone
        // order the left one used to win "dock-pill-3" - the date pill on
        // the right was renamed, and the editor selected it instead.
        const ids = d => L.barPillIds(d)
        let named = L.dockZoneOp(fresh, L.addPill, ["right", "clock", "full"])
        named = L.dockZoneOp(named, L.addPill, ["right", "date", "full"])
        const datePill = named.right[1].id
        named = L.dockZoneOp(named, L.removePill, [named.right[0].id])
        const beforeAdd = ids(named)
        named = L.dockZoneOp(named, L.addPill, ["left", "volume", "icon"])
        T.eq(named.right.map(pill => [pill.id, pill.items[0].type]), [[datePill, "date"]], "an untouched pill keeps its id (" + datePill + ")")
        const created = ids(named).filter(id => beforeAdd.indexOf(id) < 0)
        T.eq(created.length, 1, "one id is new")
        T.eq(L.findPill(named, created[0]), { zone: "left", index: 0 }, "and it is the new pill's")
        T.eq(new Set(ids(named)).size, ids(named).length, "every id once")
        // The same for a split: the pill split off is the only one renamed
        // (two pills, so splitItem names the new one "pill-3").
        let split = L.sanitizeDock({ left: [{ id: "dock-a", items: [{ type: "clock" }, { type: "date" }] }],
                                     right: [{ id: "dock-pill-3", items: [{ type: "volume" }] }] })
        const splitBefore = ids(split)
        split = L.dockZoneOp(split, L.splitItem, ["dock-a", 1])
        T.eq(split.right.map(pill => pill.id), ["dock-pill-3"], "a split renames no other pill")
        T.eq(split.left.map(pill => pill.items[0].type), ["clock", "date"], "and makes two")
        T.eq(ids(split).filter(id => splitBefore.indexOf(id) < 0).length, 1, "with one new id")

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

        // ---- a preset and the user's pins ------------------------------------------------
        const presetLayout = L.sanitizeDock({ center: [{ id: "dock-apps", items: [{ type: "apps" }] }], pins: ["@files", "@browser"] })
        const mine = L.dockPinAt(fresh, "org.kde.kate")
        T.eq(L.dockFromPreset(mine, presetLayout).pins, mine.pins, "a preset keeps the apps the user pinned")
        T.eq(L.dockFromPreset(mine, presetLayout).center, presetLayout.center, "and brings its zones")
        T.eq(L.dockFromPreset(fresh, presetLayout).pins, ["@files", "@browser"], "onto the default pins it brings its own")
        T.eq(L.dockFromPreset(L.sanitizeDock({ pins: [] }), presetLayout).pins, ["@files", "@browser"], "and onto none")
        T.eq(L.dockFromPreset(undefined, presetLayout).pins, ["@files", "@browser"], "no dock yet: the preset's")
        const reordered = L.dockPinAt(fresh, "@browser", 0)
        T.eq(L.dockFromPreset(reordered, presetLayout).pins, reordered.pins, "the defaults in an order of the user's are theirs too")

        // ---- the registry: the dock's own pieces ------------------------------------------
        const offered = WidgetRegistry.availableTypes().map(entry => entry.name)
        T.ok(offered.indexOf("apps") < 0 && offered.indexOf("start") < 0,
             "the pickers elsewhere (widgets, bar, control center, dashboard, notch) are not offered the dock's pieces")
        T.ok(offered.indexOf("clock") >= 0, "but every other widget")
        const all = WidgetRegistry.availableTypes(true).map(entry => entry.name)
        T.ok(all.indexOf("apps") >= 0 && all.indexOf("start") >= 0, "a caller that asks gets them")
        T.ok(WidgetRegistry.isDockOnly("apps") && WidgetRegistry.isDockOnly("start") && !WidgetRegistry.isDockOnly("clock"), "dockOnly")
        T.ok(WidgetRegistry.isOnce("apps") && WidgetRegistry.isOnce("start") && !WidgetRegistry.isOnce("clock"), "once on the dock")
        T.ok(!WidgetRegistry.pillSized("apps") && WidgetRegistry.pillSized("start") && WidgetRegistry.pillSized("workspace"),
             "the apps size themselves, every other item takes the editor's item size")

        // ---- the editor's frames ------------------------------------------------------------
        // The only sign on the flat taskbar of what can be dragged: a mark
        // at 3:1 on the panel under the editor's scrim, in both themes (the
        // divider line it was came to 1.1-1.2:1).
        const hex = color => typeof color === "string" ? color : String(Qt.rgba(color.r, color.g, color.b, 1))
        for (const theme of ["dark", "light"]) {
            SettingsService.set("appearance.theme", theme)
            const under = Colors.flat(Colors.scrim, Colors.panelBase)
            T.ok(C.contrast(hex(Colors.editorFrame), hex(under)) >= 3,
                 theme + ": a frame is a mark on the dimmed panel (" + C.contrast(hex(Colors.editorFrame), hex(under)).toFixed(2) + ")")
            T.ok(C.contrast(hex(Colors.flat(Colors.border, under)), hex(under)) < 3, theme + ": which the divider line was not")
        }
        SettingsService.set("appearance.theme", "dark")

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
        T.ok(L.dockHasType(taskbar.layout, "start"), "the taskbar has a start button")
        T.ok(!L.dockHasType(L.defaultDock(), "start") && L.dockHasType(L.defaultDock(), "apps"), "the default dock has the apps only")
        T.ok(!L.dockHasType(null, "start") && !L.dockHasType({ left: "junk", center: [null, { items: 3 }] }, "start"), "junk has none")
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
