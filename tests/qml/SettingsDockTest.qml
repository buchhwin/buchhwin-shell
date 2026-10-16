import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/settings/DockPageLogic.js" as D
import "../../services/LayoutLogic.js" as L

// Settings > Dock's logic (services/settings/DockPageLogic.js): the preset in
// use, read against the two shipped presets as LayoutService reads them, and
// the pin list's rows.
ShellRoot {
    FileView { id: taskbarFile; path: Qt.resolvedUrl("../../config/dock-presets/taskbar.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: dockFile; path: Qt.resolvedUrl("../../config/dock-presets/dock.json").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        const taskbar = L.sanitizeDockPreset(JSON.parse(taskbarFile.text()))
        const dock = L.sanitizeDockPreset(JSON.parse(dockFile.text()))
        taskbar.id = "taskbar"
        dock.id = "dock"
        const presets = [taskbar, dock]
        const settingsOf = options => key => options[key]

        // ---- the preset in use ---------------------------------------------
        T.eq(D.presetInUse(presets, L.copyDock(dock.layout), settingsOf(dock.options)), "dock",
             "the dock preset as applied is the one in use")
        T.eq(D.presetInUse(presets, L.copyDock(taskbar.layout), settingsOf(taskbar.options)), "taskbar",
             "and the taskbar as applied")
        const ownPins = L.copyDock(taskbar.layout)
        ownPins.pins = ["org.kde.dolphin", "firefox"]
        T.eq(D.presetInUse(presets, ownPins, settingsOf(taskbar.options)), "taskbar", "pins of the user's own do not count")
        // The live layout of 16.10.: what layout.json keeps after sanitizing
        // (displays, sizes, options filled in).
        const stored = { pins: ["@files"], left: [], right: [],
                         center: [{ id: "dock-apps", items: [{ type: "apps", display: "full", size: "small", w: 1, h: 1, options: {} }] }] }
        T.eq(D.presetInUse(presets, stored, settingsOf(dock.options)), "dock", "a stored layout with the editor's fields")
        // The user's own dock of 16.10.: the Dock preset with a margin of 4.
        T.eq(D.presetInUse(presets, stored, settingsOf(Object.assign({}, dock.options, { margin: 4 }))), "dock",
             "an option tuned since: still the preset the dock is built from")
        T.eq(D.presetInUse(presets, L.copyDock(taskbar.layout), settingsOf(dock.options)), "taskbar",
             "the taskbar's widgets with the dock's options: the taskbar")
        const twin = Object.assign({}, dock, { id: "twin", options: Object.assign({}, dock.options, { iconSize: 64 }) })
        T.eq([D.presetInUse([dock, twin], L.copyDock(dock.layout), settingsOf(twin.options)),
              D.presetInUse([dock, twin], L.copyDock(dock.layout), settingsOf(Object.assign({}, dock.options, { margin: 4 })))],
             ["twin", "dock"], "two presets with the same widgets: the one whose options match, else the first")
        const own = L.copyDock(dock.layout)
        own.right = [{ id: "dock-clock", items: [{ type: "clock" }] }]
        T.eq(D.presetInUse(presets, own, settingsOf(dock.options)), "", "a widget added in the editor: a dock of its own")
        const moved = L.copyDock(taskbar.layout)
        moved.right = moved.right.slice().reverse()
        T.eq(D.presetInUse(presets, moved, settingsOf(taskbar.options)), "", "the taskbar's widgets in another order: neither")
        T.eq([D.presetInUse([], stored, settingsOf({})), D.presetInUse(null, stored, settingsOf({}))], ["", ""], "no presets read yet")
        T.eq([D.holds(taskbar.layout, "start"), D.holds(dock.layout, "start"), D.holds(null, "start")], [true, false, false],
             "the taskbar has the start button (its card wears the Saturn), the dock does not")

        // ---- the pin list ------------------------------------------------------
        T.eq(D.pinRow("org.kde.dolphin", { name: "Dolphin", icon: "system-file-manager" }, true),
             { pin: "org.kde.dolphin", name: "Dolphin", subtitle: "", icon: "system-file-manager", settings: false, missing: false },
             "an installed app by its name and icon")
        const gone = D.pinRow("brave-abc-Default", null, true)
        T.eq([gone.name, gone.subtitle, gone.missing], ["brave-abc-Default", "Not installed", true],
             "an app that is gone: by its id, and said so - the dock draws nothing for it")
        T.eq(D.pinRow("@terminal", { name: "Alacritty", icon: "Alacritty" }, true).subtitle, "Default terminal", "a default by the app it is now")
        const unread = D.pinRow("@browser", null, false)
        T.eq([unread.name, unread.subtitle, unread.missing], ["Browser", "Default browser", false],
             "a default not looked up yet is not missing")
        const unset = D.pinRow("@files", null, true)
        T.eq([unset.subtitle, unset.missing], ["Default file manager - none found", true], "a default with no app")
        T.eq([D.pinRow("@settings", null, false).name, D.pinRow("@settings", null, false).settings], ["Settings", true],
             "the shell's Settings")
        T.eq([D.stepTarget(0, -1, 4), D.stepTarget(0, 1, 4), D.stepTarget(3, 1, 4), D.stepTarget(2, -1, 4), D.stepTarget(5, 1, 4)],
             [-1, 1, -1, 1, -1], "earlier and later stop at the ends")
        // dockPinAt takes the pin out and puts it back at the index, so the
        // step target is where it ends up.
        const pinned = { left: [], center: [], right: [], pins: ["a", "b", "c", "d"] }
        T.eq(L.dockPinAt(pinned, "c", D.stepTarget(2, -1, 4)).pins, ["a", "c", "b", "d"], "earlier swaps with the one before")
        T.eq(L.dockPinAt(pinned, "b", D.stepTarget(1, 1, 4)).pins, ["a", "c", "b", "d"], "later with the one after")

        T.finish("SettingsDockTest")
    }
}
