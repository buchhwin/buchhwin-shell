import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/quick/QuickLogic.js" as Quick

// Escape in the control center: on a detail page it goes back to the
// overview and the panel stays, after the page's own steps (the background
// apps page's open menu); on the overview it closes the panel. The
// page's handler used to be `onEscapePressed`, which ShellPanel runs before
// its close and never instead of it, so the panel went with the page it had
// just cleared. ShellPanel needs a PanelWindow backend, which offscreen has
// not: its Escape sequence (escapeKey, requestClose) is a stand-in here with
// a copy of ControlCenter's handler, against the real PanelService (no side
// effect beyond its properties, pitfall 82), and the panel's file is read
// for the handler itself.
ShellRoot {
    id: root

    // The panel's own file, since the panel cannot be built here: it has to
    // take Escape through `escapeHandler` with the steps below, not through
    // `onEscapePressed`.
    FileView {
        id: panelFile
        path: Quickshell.shellPath("shell/controlcenter/ControlCenter.qml")
        blockLoading: true
    }

    // A page with a step of its own, as TrayPage has: an app's menu, with
    // one submenu open in it.
    QtObject {
        id: trayPage
        property bool menuOpen: true
        property var stack: ["submenu"]
        function stepBack() {
            if (!menuOpen) return false
            if (stack.length) stack = stack.slice(0, -1)
            else menuOpen = false
            return true
        }
    }

    QtObject {
        id: panel
        property string panelId: "controlCenter"
        property string page: ""
        property var shownPage: null
        property int beforeClose: 0
        // ControlCenter.escapeHandler, with `shownPage` for its detail Loader.
        property var escapeHandler: () => {
            const shownPage = panel.shownPage
            if (shownPage && typeof shownPage.stepBack === "function" && shownPage.stepBack() === true) return true
            const next = Quick.pageAfterEscape(panel.page)
            if (next === null) return false
            panel.page = next
            return true
        }
        signal escapePressed()
        onEscapePressed: beforeClose += 1
        function requestClose() { PanelService.close(panelId) }
        // ShellPanel.escapeKey without its arrange-drag branch: the handler
        // first, and only when it did not take the key the close.
        function escapeKey() {
            if (typeof escapeHandler === "function" && escapeHandler() === true) return
            escapePressed()
            requestClose()
        }
    }

    property int step: 0
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                T.eq(PanelService.open("controlCenter", { page: "network" }), true, "the control center opens")
                panel.page = PanelService.args.page
                T.eq([PanelService.active, panel.page], ["controlCenter", "network"], "on its network page")
                panel.escapeKey()
                T.eq([PanelService.active, panel.page], ["controlCenter", ""], "Escape goes back to the overview and keeps the panel")
                T.eq(panel.beforeClose, 0, "nothing on the way to a close ran")
                break
            case 1:
                T.eq(PanelService.active, "controlCenter", "still open a turn later")
                panel.escapeKey()
                T.eq(PanelService.active, "", "Escape on the overview closes it")
                T.eq(panel.beforeClose, 1, "through the close")
                break
            case 2:
                PanelService.open("controlCenter", { page: "tray" })
                panel.page = PanelService.args.page
                panel.shownPage = trayPage
                panel.escapeKey()
                T.eq([PanelService.active, panel.page, trayPage.stack.length, trayPage.menuOpen],
                     ["controlCenter", "tray", 0, true], "Escape in an app's submenu goes back to its menu")
                panel.escapeKey()
                T.eq([PanelService.active, panel.page, trayPage.menuOpen], ["controlCenter", "tray", false],
                     "then out of the menu, on the page")
                panel.escapeKey()
                T.eq([PanelService.active, panel.page], ["controlCenter", ""], "then back to the overview")
                panel.shownPage = null
                panel.escapeKey()
                T.eq(PanelService.active, "", "and closed")

                const source = panelFile.text()
                T.ok(/^\s*escapeHandler\s*:/m.test(source), "ControlCenter.qml takes Escape through escapeHandler")
                T.ok(!/^\s*onEscapePressed\s*:/m.test(source), "and not through onEscapePressed")
                T.ok(source.indexOf("stepBack()") >= 0 && source.indexOf("Quick.pageAfterEscape(root.page)") >= 0,
                     "with the page's own steps first, then the way back to the overview")
                stop()
                T.finish("ControlCenterEscapeTest")
                break
            }
        }
    }
}
