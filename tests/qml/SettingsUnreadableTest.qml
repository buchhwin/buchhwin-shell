import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// A settings.json that is there but cannot be read is not a first start. Here
// it is a directory in the file's place, which root cannot read either (a
// mode-000 file would still be read by a test run as root). The
// service runs on the defaults, keeps a change live, writes nothing over what
// it could not read and says why; once the file can be read, the watch reads
// it and the service writes again.
ShellRoot {
    id: root
    property int tries: 0

    // In place before SettingsService is first touched, so its first read
    // meets the directory.
    Process {
        id: seed
        running: true
        command: ["mkdir", "-p", "--", Paths.configDir + "/settings.json"]
        onExited: unreadable.start()
    }

    Timer {
        id: unreadable
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (!SettingsService.loaded && root.tries < 100) return
            stop()
            T.eq(SettingsService.loaded, true, "the service gives up on the file and runs")
            T.eq(SettingsService.readOnly, true, "but not as on a first start: it writes nothing")
            T.ok(SettingsService.readOnlyReason.length > 0, "and says why (" + SettingsService.readOnlyReason + ")")
            T.eq(SettingsService.value("appearance.theme"), "dark", "on the defaults")
            T.eq(SettingsService.set("appearance.theme", "light"), true, "a change is taken")
            T.eq(SettingsService.value("appearance.theme"), "light", "and is live")
            T.eq(SettingsService.pendingText, "", "but nothing is queued for the file")
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
        command: ["test", "-d", Paths.configDir + "/settings.json"]
        onExited: code => {
            T.eq(code, 0, "what could not be read is still there as it was")
            readable.running = true
        }
    }

    // The user puts it right: a file again, written from outside.
    Process {
        id: readable
        command: ["sh", "-c", "rmdir -- \"$1\" && printf '%s\\n' \"$2\" > \"$1\"", "sh",
                  Paths.configDir + "/settings.json", JSON.stringify({ workspaces: { count: 3 } })]
        onExited: { root.tries = 0; reread.start() }
    }
    Timer {
        id: reread
        interval: 100
        repeat: true
        onTriggered: {
            root.tries += 1
            if (SettingsService.value("workspaces.count") !== 3 && root.tries < 50) return
            stop()
            T.eq(SettingsService.value("workspaces.count"), 3, "the watch reads the file once it can be read")
            T.eq(SettingsService.readOnly, false, "and the service writes again")
            T.eq(SettingsService.set("workspaces.count", 4), true, "a change after that")
            T.ok(SettingsService.pendingText.indexOf("\"count\": 4") >= 0, "is queued for the file")
            T.finish("SettingsUnreadable")
        }
    }
}
