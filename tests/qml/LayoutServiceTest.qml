import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// LayoutService itself, against the runner's sandboxed XDG_CONFIG_HOME: a
// missing layout.json loads as an empty, writable layout; two edits in one
// turn of the event loop are one pending text and one write; and the write
// lands in layout.json with both. The load is asynchronous (the file is
// missing, and `loadFailed` is what loads the empty layout), so it is polled
// for rather than assumed - and so is the write, which is a zero-interval
// Timer and an asynchronous file operation away.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0

    FileView {
        id: written
        path: Paths.configDir + "/layout.json"
        blockLoading: true
        printErrors: false
    }

    function activeBar(document) {
        return document.profiles[LayoutService.activeProfile].modes[LayoutService.activeMode].bar
    }

    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!LayoutService.loaded && root.waits < 100) return
            stop()
            T.ok(LayoutService.loaded, "the layout loads in the sandbox (" + Paths.configDir + ")")
            T.eq(LayoutService.readOnly, false, "a missing file is an empty layout, not a read-only one")
            T.eq(LayoutService.setBarOption("edge", "bottom"), true, "a bar option is taken")
            T.eq(LayoutService.setBarOption("style", "bar"), true, "and a second one in the same turn")
            const pending = root.activeBar(JSON.parse(LayoutService.pendingText))
            T.eq(pending.edge, "bottom", "one pending text holds the first")
            T.eq(pending.style, "bar", "and the second")
            T.eq(LayoutService.bar.edge, "bottom", "the value is live before the write")
            settle.start()
        }
    }

    Timer {
        id: settle
        interval: 100
        repeat: true
        onTriggered: {
            root.tries += 1
            written.reload()
            let parsed = null
            try { parsed = JSON.parse(written.text()) } catch (error) { parsed = null }
            const bar = parsed ? root.activeBar(parsed) : null
            if ((!bar || bar.edge !== "bottom" || bar.style !== "bar") && root.tries < 50) return
            stop()
            T.ok(parsed !== null, "layout.json was written in the sandbox")
            T.ok(bar !== null && bar.edge === "bottom", "the file holds the first option")
            T.ok(bar !== null && bar.style === "bar", "and the second")
            T.finish("LayoutService")
        }
    }
}
