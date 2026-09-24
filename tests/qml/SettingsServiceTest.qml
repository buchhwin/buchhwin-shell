import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// SettingsService itself, against the runner's sandboxed XDG_CONFIG_HOME:
// what `set` refuses, that two sets in one turn of the event loop are one
// pending text and one write, and that the write lands in settings.json.
ShellRoot {
    id: root
    property int tries: 0

    FileView {
        id: written
        path: Paths.configDir + "/settings.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        T.eq(SettingsService.set("appearance.theme", 5), false, "a value of the wrong type is refused")
        T.eq(SettingsService.value("appearance.theme"), "dark", "and the setting keeps its default")
        T.eq(SettingsService.set("appearance.theme", "purple"), false, "a value outside the allowed list is refused")
        T.eq(SettingsService.value("appearance.theme"), "dark", "and the setting still keeps its default")
        T.eq(SettingsService.set("nothing.here", 1), false, "an unknown key is refused")
        T.eq(SettingsService.pendingText, "", "nothing refused is written")

        T.eq(SettingsService.set("appearance.theme", "light"), true, "an allowed value is taken")
        T.eq(SettingsService.set("workspaces.count", 7), true, "and a second one in the same turn")
        const pending = JSON.parse(SettingsService.pendingText)
        T.eq(pending.appearance.theme, "light", "one pending text holds the first")
        T.eq(pending.workspaces.count, 7, "and the second")
        T.eq(SettingsService.value("workspaces.count"), 7, "the value is live before the write")
        settle.start()
    }

    // The write is a zero-interval Timer and an asynchronous file operation
    // away; the file is polled rather than waited for by a fixed delay.
    Timer {
        id: settle
        interval: 100
        repeat: true
        onTriggered: {
            root.tries += 1
            written.reload()
            let parsed = null
            try { parsed = JSON.parse(written.text()) } catch (error) { parsed = null }
            if (parsed === null && root.tries < 50) return
            stop()
            T.ok(parsed !== null, "settings.json was written in the sandbox (" + Paths.configDir + ")")
            if (parsed !== null) {
                T.eq(parsed.appearance.theme, "light", "the file holds the first key")
                T.eq(parsed.workspaces.count, 7, "and the second")
            }
            T.finish("SettingsService")
        }
    }
}
