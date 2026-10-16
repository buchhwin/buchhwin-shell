import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// PanelService's lazy panels and hand-backs (testing.md pitfalls 101, 110):
// a panel built on its first open (`demanded`, the open waiting in
// `pending`), no scrim for a panel that is not there, a dialog's hand-back to
// a panel that went meanwhile (tests-docs#3), and `onScreen` by name. A
// stand-in reports in the way a ShellPanel does from its LazyLoader in
// shell.qml; PanelService itself has no side effect beyond its properties
// (pitfall 82: no command runs).
ShellRoot {
    id: root
    // The start menu's feature: a dock with a start button that opens it.
    property bool feature: true
    onFeatureChanged: if (!feature) PanelService.release("startMenu")
    property int built: 0

    LazyLoader {
        active: root.feature && PanelService.demanded.startMenu === true
        QtObject {
            Component.onCompleted: { root.built += 1; PanelService.reportPresent("startMenu", true) }
            Component.onDestruction: PanelService.reportPresent("startMenu", false)
        }
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

                // ---- tests-docs#3: the hand-back to a panel that went --------------------
                PanelService.openOver("pairing", {})
                T.eq([PanelService.active, PanelService.args.returnTo.panel], ["pairing", "startMenu"], "a dialog over the start menu")
                // The dock switched off meanwhile (the item goes at the end
                // of the turn).
                root.feature = false
                break
            case 2:
                T.eq(PanelService.isPresent("startMenu"), false, "the start menu is unloaded")
                T.eq(PanelService.active, "pairing", "the dialog stays")
                PanelService.close("pairing")
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
                PanelService.openOver("pairing", {})
                PanelService.close("pairing")
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
                T.finish("PanelServiceTest")
                running = false
                break
            }
        }
    }
}
