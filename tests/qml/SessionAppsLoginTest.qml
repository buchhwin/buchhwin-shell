//@ pragma Env BUCHHWIN_SHELL_PATH=/nonexistent/buchhwin-shell
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// The login step of services/SessionAppsService.qml in a process that takes
// itself for the session's shell (the pragma; the runner strips the real
// BUCHHWIN_SHELL_PATH): once the settings and apps.json are read, the
// service asks once whether this is the login's first start and leaves a
// marker in the runtime directory (the runner's own, emptied with it).
//
// loginReady used to read the flag its own handler sets, so the handler's
// write re-ran the binding inside its own change: "Binding loop detected for
// property loginReady" at every start of the real session, which the runner
// fails on. Nothing else runs here: the work apps and the offer are off in a
// fresh sandbox, and without a compositor's signature hyprctl reaches none.
ShellRoot {
    id: root

    property int ticks: 0
    property bool checkedSeen: false

    FileView {
        id: marker
        printErrors: false
        blockLoading: true
    }

    function finish() {
        T.ok(SessionAppsService.realSession, "a process with the session's shell path is the real session")
        T.ok(SessionAppsService.loginChecked, "the login is asked about once the settings and apps.json are read")
        T.ok(SessionAppsService.loginReady, "and stays ready: the flag guards the handler, not the binding")
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || ""
        T.ok(runtime.length > 0 && SessionAppsService.loginMarker.indexOf(runtime + "/") === 0,
             "the marker lives in the runtime directory")
        marker.path = SessionAppsService.loginMarker
        marker.reload()
        T.ok(/^\d{4}-\d\d-\d\dT/.test(marker.text()), "the first start of a login leaves its marker")
        T.finish("SessionAppsLoginTest")
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            root.ticks += 1
            if (SessionAppsService.loginChecked && !root.checkedSeen) root.checkedSeen = true
            // The marker is written a turn after the read that found none.
            if (root.checkedSeen && root.ticks >= 8 || root.ticks > 60) {
                running = false
                root.finish()
            }
        }
    }
}
