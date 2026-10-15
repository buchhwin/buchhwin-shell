import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// SettingsService itself, against the runner's sandboxed XDG_CONFIG_HOME:
// that a change asked for before settings.json has been read lands on top of
// the user's file instead of replacing it with the defaults, what `set`
// refuses, that two sets in one turn of the event loop are one pending text
// and one write, that the write lands in settings.json, and that reading our
// own write back leaves `data` alone while a change from outside still lands.
ShellRoot {
    id: root
    property int tries: 0
    // 1: waiting for the early change in the file, 2: for the later two,
    // 3: for a change written from outside.
    property int phase: 0
    property int dataChanges: 0
    property var dataBefore: null
    property int changesBefore: 0

    // Not before phase 2: touching the singleton earlier would start its
    // read before the user's file is in place.
    Connections {
        target: root.phase >= 2 ? SettingsService : null
        function onDataChanged() { root.dataChanges += 1 }
    }

    FileView {
        id: written
        path: Paths.configDir + "/settings.json"
        blockLoading: true
        printErrors: false
    }

    // The user's own file is in place before SettingsService is first
    // touched, so its read is still out when the early change is asked for.
    Process {
        id: seed
        running: true
        command: ["sh", "-c", "mkdir -p -- \"$1\" && printf '%s\\n' \"$2\" > \"$1/settings.json\"", "sh",
                  Paths.configDir, JSON.stringify({ appearance: { clockFormat: "12" } })]
        onExited: root.early()
    }

    function early() {
        T.eq(SettingsService.loaded, false, "the file is still being read")
        T.eq(SettingsService.set("workspaces.count", 7), true, "a change before the file is read is taken")
        T.eq(SettingsService.value("workspaces.count"), 7, "and live at once")
        T.eq(SettingsService.pendingText, "", "but nothing is written over a file not read yet")
        phase = 1
        settle.start()
    }

    function later() {
        T.eq(SettingsService.value("appearance.clockFormat"), "12", "the user's file was read")
        T.eq(SettingsService.value("workspaces.count"), 7, "with the early change on top")

        T.eq(SettingsService.set("appearance.theme", 5), false, "a value of the wrong type is refused")
        T.eq(SettingsService.value("appearance.theme"), "dark", "and the setting keeps its default")
        T.eq(SettingsService.set("appearance.theme", "purple"), false, "a value outside the allowed list is refused")
        T.eq(SettingsService.value("appearance.theme"), "dark", "and the setting still keeps its default")
        const before = SettingsService.pendingText
        T.eq(SettingsService.set("nothing.here", 1), false, "an unknown key is refused")
        T.eq(SettingsService.pendingText, before, "nothing refused is written")

        T.eq(SettingsService.set("appearance.theme", "light"), true, "an allowed value is taken")
        T.eq(SettingsService.set("workspaces.count", 5), true, "and a second one in the same turn")
        const pending = JSON.parse(SettingsService.pendingText)
        T.eq(pending.appearance.theme, "light", "one pending text holds the first")
        T.eq(pending.workspaces.count, 5, "and the second")
        T.eq(SettingsService.value("workspaces.count"), 5, "the value is live before the write")
        phase = 2
        tries = 0
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
            const count = root.phase === 1 ? 7 : 5
            const done = SettingsService.loaded && parsed !== null && parsed.workspaces
                && parsed.workspaces.count === count
            if (root.phase === 3) {
                if (SettingsService.value("workspaces.count") !== 3 && root.tries < 50) return
                stop()
                root.outsideChange()
                return
            }
            if (!done && root.tries < 50) return
            stop()
            T.ok(parsed !== null, "settings.json was written in the sandbox (" + Paths.configDir + ")")
            if (parsed === null) {
                T.finish("SettingsService")
                return
            }
            if (root.phase === 1) {
                T.eq(parsed.workspaces.count, 7, "the file holds the early change")
                T.eq(parsed.appearance.clockFormat, "12", "and still the user's own setting")
                root.later()
                return
            }
            T.eq(parsed.appearance.theme, "light", "the file holds the first key")
            T.eq(parsed.workspaces.count, 5, "and the second")
            T.eq(parsed.appearance.clockFormat, "12", "and the user's own setting")
            root.dataBefore = SettingsService.data
            root.changesBefore = root.dataChanges
            readBack.start()
        }
    }

    // The watch reads every write of the service's own back. Given time to
    // do so, and once more by hand, that read must not hand out a new `data`:
    // every value() binding in the shell would re-run on it.
    Timer {
        id: readBack
        interval: 600
        onTriggered: {
            T.ok(SettingsService.data === root.dataBefore, "reading our own write back keeps data")
            T.eq(root.dataChanges, root.changesBefore, "and emits no dataChanged")
            SettingsService.load()
            T.ok(SettingsService.data === root.dataBefore, "a load of the same text keeps data")
            T.eq(root.dataChanges, root.changesBefore, "and emits nothing either")
            root.phase = 3
            outside.running = true
        }
    }

    // A hand edit of the file is still read, so the watch was there to read
    // the write above too.
    Process {
        id: outside
        command: ["sh", "-c", "printf '%s\\n' \"$2\" > \"$1/settings.json\"", "sh", Paths.configDir,
                  JSON.stringify({ appearance: { clockFormat: "12", theme: "light" }, workspaces: { count: 3 } })]
        onExited: { root.tries = 0; settle.start() }
    }

    function outsideChange() {
        T.eq(SettingsService.value("workspaces.count"), 3, "a change from outside is read")
        T.ok(root.dataChanges > root.changesBefore, "and hands out a new data")
        T.eq(SettingsService.value("appearance.theme"), "light", "with the rest of the file")
        T.finish("SettingsService")
    }
}
