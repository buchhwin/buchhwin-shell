import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// A layout.json that is there but cannot be read is not a fresh layout. Here
// it is a directory in the file's place, which root cannot read either (a
// mode-000 file would still be read by a test run as root).
// LayoutService comes up read-only and says why, takes no edit and writes
// nothing over what it could not read; once the file can be read, the watch
// reads it and the layout is the user's to change again.
ShellRoot {
    id: root
    property int tries: 0

    // In place before LayoutService is first touched, so its first read
    // meets the directory.
    Process {
        id: seed
        running: true
        command: ["mkdir", "-p", "--", Paths.configDir + "/layout.json"]
        onExited: unreadable.start()
    }

    Timer {
        id: unreadable
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (!LayoutService.loaded && root.tries < 100) return
            stop()
            T.eq(LayoutService.loaded, true, "the service gives up on the file and runs")
            T.eq(LayoutService.readOnly, true, "read-only, as a file from a newer version is")
            T.ok(LayoutService.readOnlyReason.indexOf("layout.json cannot be read") === 0,
                 "and says why (" + LayoutService.readOnlyReason + ")")
            T.eq(LayoutService.layoutWasEmpty, false, "a file that is there is not a missing one")
            T.eq(LayoutService.setActiveMode("work"), false, "an edit is refused")
            T.eq(LayoutService.pendingText, "", "and nothing is queued for the file")
            untouched.start()
        }
    }

    // Given time for a write that should not come.
    Timer {
        id: untouched
        interval: 300
        onTriggered: stillDirectory.running = true
    }
    Process {
        id: stillDirectory
        command: ["test", "-d", Paths.configDir + "/layout.json"]
        onExited: code => {
            T.eq(code, 0, "what could not be read is still there as it was")
            readable.running = true
        }
    }

    // The user puts it right: a file again, written from outside.
    Process {
        id: readable
        command: ["sh", "-c", "rmdir -- \"$1\" && printf '%s\\n' \"$2\" > \"$1\"", "sh",
                  Paths.configDir + "/layout.json", JSON.stringify(L.sanitize({}))]
        onExited: { root.tries = 0; reread.start() }
    }
    Timer {
        id: reread
        interval: 100
        repeat: true
        onTriggered: {
            root.tries += 1
            if (LayoutService.readOnly && root.tries < 50) return
            stop()
            T.eq([LayoutService.readOnly, LayoutService.readOnlyReason], [false, ""],
                 "the watch reads the file once it can be read, and the layout can be changed again")
            T.eq(LayoutService.setActiveMode("work"), true, "an edit after that is taken")
            T.finish("LayoutUnreadable")
        }
    }
}
