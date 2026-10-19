import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/clipboard/ClipboardLogic.js" as Logic

// When the X11 clipboard bridge runs: from the session's first X11 window on,
// never before one (it held 12 MB for nothing on days without any), and after
// a crash only five more times in a row, each pause twice the last.
ShellRoot {
    id: root

    // ClipboardService's latch, in the service's shape: the runner hides the
    // X display, so the service itself never sees a window here. Setting the
    // latch from inside the change of the property that reads it was a
    // binding loop (which the runner fails on) and left it reading true.
    QtObject {
        id: latch
        property var windows: []
        property bool sawX11: false
        readonly property bool x11WindowOpen: !sawX11 && Logic.anyX11(windows)
        function noteX11() { sawX11 = true }
        onX11WindowOpenChanged: if (x11WindowOpen) Qt.callLater(latch.noteX11)
    }
    Timer {
        id: afterLatch
        interval: 50
        onTriggered: {
            T.eq([latch.sawX11, latch.x11WindowOpen], [true, false],
                 "the first X11 window is noted once, and the windows are not looked at again")
            latch.windows = []
            T.ok(latch.sawX11, "the bridge stays when the window closes")
            T.finish("ClipboardBridgeTest")
        }
    }

    Component.onCompleted: {
        T.ok(!Logic.bridgeWanted(":1", false, false), "no X11 window yet: no bridge")
        T.ok(Logic.bridgeWanted(":1", true, false), "an X11 window seen: the bridge runs")
        T.ok(!Logic.bridgeWanted(":1", true, true), "paused for a restart: not running")
        T.ok(!Logic.bridgeWanted("", true, false) && !Logic.bridgeWanted(undefined, true, false), "no X display: never")

        // Hyprland's IPC objects, as lastIpcObject holds them; null before a
        // refreshToplevels() filled one.
        T.ok(!Logic.anyX11([]) && !Logic.anyX11(null), "no windows")
        T.ok(!Logic.anyX11([{ class: "Alacritty", xwayland: false }, null, {}]),
             "Wayland windows and unread IPC objects are no X11 window")
        T.ok(Logic.anyX11([{ class: "Alacritty", xwayland: false }, { class: "Wfica", xwayland: true }]),
             "one X11 window among them is enough")
        T.ok(!Logic.anyX11([{ xwayland: "true" }]), "only a real true counts")

        T.eq([1, 2, 3, 4, 5].map(Logic.bridgeRestartDelay), [5000, 10000, 20000, 40000, 80000],
             "restart pauses double from 5 s")
        T.eq(Logic.bridgeRestartDelay(6), -1, "after the fifth end in a row it stays stopped")
        T.eq(Logic.bridgeRestartDelay(0), 0, "no failure, no pause")

        latch.windows = [{ class: "Alacritty", xwayland: false }]
        T.ok(!latch.sawX11, "Wayland windows only: nothing seen")
        latch.windows = [{ class: "Alacritty", xwayland: false }, { class: "Wfica", xwayland: true }]
        afterLatch.start()
    }
}
