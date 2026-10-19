import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// PanelService's lazy panels and hand-backs (testing.md pitfalls 101, 110):
// a panel built on its first open (`demanded`, the open waiting in
// `pending`), no scrim for a panel that is not there, a dialog's hand-back to
// a panel that went meanwhile, and `onScreen` by name. A stand-in reports in
// the way a ShellPanel does from its LazyLoader in shell.qml; PanelService
// itself has no side effect beyond its properties
// (pitfall 82: no command runs). And shell.qml as it is: every loader on
// `demanded` is a lazy panel, every lazy panel has its loader, and each
// loader builds the panel of that id - one that built another would never
// open (its open waits for an id that never reports in).
ShellRoot {
    id: root
    // The start menu's feature: a dock with a start button that opens it.
    property bool feature: true
    onFeatureChanged: if (!feature) PanelService.release("startMenu")
    property int built: 0
    property int settingsBuilt: 0

    LazyLoader {
        active: root.feature && PanelService.demanded.startMenu === true
        QtObject {
            Component.onCompleted: { root.built += 1; PanelService.reportPresent("startMenu", true) }
            Component.onDestruction: PanelService.reportPresent("startMenu", false)
        }
    }
    // A panel with no feature around it, as Settings is in shell.qml.
    LazyLoader {
        active: PanelService.demanded.settings === true
        QtObject {
            Component.onCompleted: { root.settingsBuilt += 1; PanelService.reportPresent("settings", true) }
            Component.onDestruction: PanelService.reportPresent("settings", false)
        }
    }

    // The runner copies the whole tree beside the test. A FileView of its own
    // per file: one whose path changes can hand back the text it read before
    // (testing.md pitfall 91).
    Component { id: fileReader; FileView { blockLoading: true; printErrors: false } }
    function read(path) {
        const view = fileReader.createObject(root, { path: Quickshell.shellPath(path) })
        const text = view.text()
        view.destroy()
        return text
    }
    // Where each panel shell.qml builds on demand is.
    readonly property var panelFiles: ({
        EmojiPanel: "shell/emoji/EmojiPanel.qml", NotificationCenter: "shell/notifications/NotificationCenter.qml",
        PowerMenu: "shell/powermenu/PowerMenu.qml", ShortcutSheet: "shell/shortcuts/ShortcutSheet.qml",
        EventEditor: "shell/dashboard/EventEditor.qml", WifiDialog: "shell/network/WifiDialog.qml",
        PairingDialog: "shell/bluetooth/PairingDialog.qml", UnlockDialog: "shell/drives/UnlockDialog.qml",
        ClipboardPanel: "shell/clipboard/ClipboardPanel.qml", WallpaperPicker: "shell/wallpaper/WallpaperPicker.qml",
        SettingsPanel: "shell/settings/SettingsPanel.qml", WelcomePanel: "shell/welcome/WelcomePanel.qml",
        DockMenu: "shell/dock/DockMenu.qml", StartMenu: "shell/startmenu/StartMenu.qml"
    })
    function shellLoaders() {
        const text = read("shell.qml")
        const demanded = []
        for (const match of text.match(/PanelService\.demanded\.\w+/g) || []) {
            const id = match.split(".").pop()
            if (demanded.indexOf(id) < 0) demanded.push(id)
        }
        T.eq(demanded.filter(id => PanelService.lazyPanels.indexOf(id) < 0), [],
             "every loader on demanded is a lazy panel (pitfall 110: an open while it is not there)")
        T.eq(PanelService.lazyPanels.filter(id => demanded.indexOf(id) < 0), [], "and every lazy panel has its loader")
        // `LazyLoader { ... demanded.<id> ... <Panel> {} }`, up to the panel.
        const built = {}
        for (const block of text.split("LazyLoader {").slice(1)) {
            const id = (block.match(/PanelService\.demanded\.(\w+)/) || [])[1]
            const panel = (block.match(/\b([A-Z]\w+) \{\s*\}/) || [])[1]
            if (id && panel) built[id] = panel
        }
        T.eq(Object.keys(built).sort(), PanelService.lazyPanels.slice().sort(), "each loader names its panel")
        const wrong = Object.keys(built).filter(id => {
            const file = root.panelFiles[built[id]]
            return !file || read(file).indexOf('panelId: "' + id + '"') < 0
        })
        T.eq(wrong, [], "and builds the panel of that id")
    }

    function state() { return [PanelService.active, PanelService.scrimWanted] }

    // Each step runs a turn after the one before: the open of a panel built
    // on demand waits for the panel (Qt.callLater), as it does in the shell.
    property int step: 0
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                root.shellLoaders()
                T.eq([PanelService.isPresent("startMenu"), root.built], [false, 0], "not built at the start")
                T.ok(!PanelService.canOpen("startMenu") && PanelService.canOpen("launcher"), "a lazy panel cannot open while it is not there")
                T.eq(PanelService.open("startMenu", { startView: "all" }), true, "opening it asks for it")
                T.eq([PanelService.isPresent("startMenu"), root.built], [true, 1], "and it is built at once")
                T.eq(root.state(), ["", false], "but nothing opens, and no scrim, before it has reported in")
                break
            case 1:
                T.eq(root.state(), ["startMenu", true], "it opens a turn later")
                T.eq(PanelService.args.startView, "all", "with its arguments")
                PanelService.close("startMenu")
                T.eq(root.state(), ["", false], "closed")
                T.eq(PanelService.open("startMenu"), true, "a second open")
                T.eq([root.state(), root.built], [["startMenu", true], 1], "opens at once: it is still there")

                // ---- the hand-back to a panel that went ---------------------------------
                // A popup stands in for the dialog: it is built at the
                // start, and the dialogs are not any more.
                PanelService.openOver("networkPopup", {})
                T.eq([PanelService.active, PanelService.args.returnTo.panel], ["networkPopup", "startMenu"], "a dialog over the start menu")
                // The dock switched off meanwhile (the item goes at the end
                // of the turn).
                root.feature = false
                break
            case 2:
                T.eq(PanelService.isPresent("startMenu"), false, "the start menu is unloaded")
                T.eq(PanelService.active, "networkPopup", "the dialog stays")
                PanelService.close("networkPopup")
                T.eq(root.state(), ["", false], "no scrim left over nothing after the dialog")
                T.eq(PanelService.pending, null, "and nothing waiting")

                // A feature that is off builds nothing, and nothing opens later.
                T.eq(PanelService.open("startMenu"), true, "asked for with its feature off")
                T.eq(root.state(), ["", false], "nothing opens")
                break
            case 3:
                T.eq([PanelService.pending, root.built, root.state()], [null, 1, ["", false]], "the open was dropped")
                root.feature = true
                T.eq(root.built, 2, "the demand stood: back on, it is built")
                break
            case 4:
                T.eq(root.state(), ["", false], "but the dropped open does not come back with it")

                // ---- the hand-back to a panel that is there --------------------------------
                PanelService.open("startMenu", { anchorX: 40 })
                PanelService.openOver("networkPopup", {})
                PanelService.close("networkPopup")
                T.eq([root.state(), PanelService.args.anchorX], [["startMenu", true], 40], "a dialog hands back with the arguments")
                PanelService.close("startMenu")

                // ---- another open or a close first -----------------------------------------
                root.feature = false
                root.feature = true
                PanelService.open("startMenu")
                PanelService.open("launcher")
                T.eq([PanelService.pending, PanelService.active], [null, "launcher"], "another panel opened first: the wait is dropped")
                PanelService.close()
                break
            case 5:
                T.eq(root.state(), ["", false], "and the start menu did not open over it")
                T.eq([PanelService.isPresent("startMenu"), PanelService.present.startMenu], [true, 1],
                     "switched off and on in one turn: the new one counts, the old one's goodbye does not take it along")
                root.feature = false
                root.feature = true
                PanelService.open("startMenu")
                PanelService.close("startMenu")
                T.eq(PanelService.pending, null, "closed while it waited")
                break
            case 6:
                T.eq(root.state(), ["", false], "stays closed")

                // ---- onScreen -------------------------------------------------------------
                const screens = Quickshell.screens
                T.ok(screens.length > 0, "an offscreen screen to open on")
                const last = screens[screens.length - 1].name
                PanelService.open("launcher", { onScreen: last })
                T.eq(PanelService.screenName, last, "onScreen by name")
                PanelService.open("launcher", { onScreen: "NO-SUCH-OUTPUT" })
                const focused = PanelService.focusedScreen()
                T.eq(PanelService.screenName, focused ? focused.name : "", "an unknown name: the focused screen")
                T.ok(PanelService.screen !== null, "a screen either way")
                PanelService.close()

                // ---- a lazy panel with no feature: Settings ----------------------------------
                T.eq([PanelService.isPresent("settings"), root.settingsBuilt], [false, 0], "Settings is not built at the start")
                T.eq(PanelService.open("settings", { page: "about" }), true, "opening it asks for it")
                T.eq([root.settingsBuilt, root.state()], [1, ["", false]], "built at once, open a turn later")
                break
            case 7:
                T.eq([root.state(), PanelService.args.page], [["settings", true], "about"], "it opens on its page")
                PanelService.close("settings")
                PanelService.open("settings", { page: "network" })
                T.eq([root.settingsBuilt, root.state(), PanelService.args.page], [1, ["settings", true], "network"],
                     "kept: the next open is at once, with no second build")
                PanelService.close()
                T.finish("PanelServiceTest")
                running = false
                break
            }
        }
    }
}
