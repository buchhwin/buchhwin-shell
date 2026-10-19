pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "sharepicker/SharePickerLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// The shell's share picker (shell/sharepicker/SharePickerPanel.qml) for
// xdg-desktop-portal-hyprland, through scripts/share-picker.sh: the portal
// runs the script for each request to share the screen, the script hands
// the request over IPC (`sharePicker request DIR ALLOW`) and waits on a
// FIFO in DIR for the one line this writes back - a choice, "region",
// "cancel" or "fallback" (SharePickerLogic.js has the contract).
//
// Nothing here runs until a request comes: no process, no timer, no
// surface; the two timers below run only while a request is open. The
// panel is built on its first open (PanelService.lazyPanels) and shows live
// previews only while it is open.
Singleton {
    id: root

    // Settings > Desktop extras > Screen sharing. Off, every request is
    // refused and the script opens the portal's own picker.
    readonly property bool enabled: SettingsService.value("sharePicker.enabled") !== false
    // The lock process never shows a picker (testing.md pitfall 86).
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)
    // How long a request waits for a choice before it is answered "cancel":
    // the script's own limit (120 s) and a little more, so the script, which
    // also closes the picker at its limit, is normally the one that ends it.
    // Only for a script that went without a word.
    readonly property int waitLimit: 130000

    // The request the picker is open for - { dir, allowToken, windows } - or
    // null.
    property var pending: null
    // Open without a request (Settings' "Preview", IPC `open`): the picker as
    // it would look now, and a choice only closes it.
    property bool preview: false
    property var previewWindows: []
    readonly property var windows: pending ? pending.windows : preview ? previewWindows : []
    readonly property bool allowTokenDefault: pending ? pending.allowToken === true : false
    // slurp draws the region; without it the picker offers none (asked once,
    // at the first request).
    property bool regionAvailable: true
    property bool regionChecked: false

    // `sharePicker request`: "opened" once the picker shows, else why not -
    // the script then opens the portal's own picker.
    function take(dir, allowToken) {
        if (lockProcess) return "refused"
        if (!enabled) return "disabled"
        if (!Logic.requestDirOk(dir, Paths.runtimeDir)) return "refused"
        listFile.path = dir + "/windows"
        const text = listFile.text()
        // The portal handles one request at a time, so one still waiting is
        // a script that is gone: its answer is a cancel.
        if (pending && pending.dir !== dir) answer("cancel")
        if (!regionChecked) {
            regionChecked = true
            slurpCheck.running = true
        }
        preview = false
        pending = { dir: dir, allowToken: allowToken === true, windows: Logic.parseWindowList(text) }
        limit.restart()
        if (!PanelService.open("sharePicker")) {
            pending = null
            limit.stop()
            return "unbuilt"
        }
        shownCheck.restart()
        return "opened"
    }
    // The picker is built on its first open, and PanelService opens it once
    // it has reported in. Not on screen two seconds later: something kept it
    // from being built or shown, and the portal's own picker is better than a
    // share that waits for a picker nobody sees.
    Timer {
        id: shownCheck
        interval: 2000
        onTriggered: {
            if (!root.pending || PanelService.isOpen("sharePicker")) return
            root.answer(Logic.FALLBACK)
        }
    }

    // The picker's choice: a stop of SharePickerLogic.stops.
    function choose(stop, allowToken) {
        if (preview) {
            preview = false
            PanelService.close("sharePicker")
            return true
        }
        if (!pending) return false
        const line = Logic.answerFor(stop, allowToken === true)
        if (!line.length) return false
        answer(line)
        PanelService.close("sharePicker")
        return true
    }

    // `sharePicker cancel DIR` (the script at its limit), or the picker
    // closed some other way: the share is cancelled.
    function cancel(dir) {
        if (!pending || (dir !== undefined && dir !== "" && dir !== pending.dir)) return false
        answer("cancel")
        PanelService.close("sharePicker")
        return true
    }
    // The panel stopped being the open one - Escape, a click beside it,
    // another panel: whatever was not chosen is cancelled.
    function closed() {
        preview = false
        if (pending) answer("cancel")
    }

    function openPreview() {
        if (pending) return false
        Hyprland.refreshToplevels()
        previewWindows = Hyprland.toplevels.values.map((toplevel, index) => ({
            handle: String(index + 1),
            appClass: toplevel.lastIpcObject && toplevel.lastIpcObject["class"] ? String(toplevel.lastIpcObject["class"]) : "",
            title: String(toplevel.title || ""),
            address: Logic.addressKey(toplevel.address)
        }))
        preview = true
        if (!regionChecked) {
            regionChecked = true
            slurpCheck.running = true
        }
        // Over the panel that asked for it - Settings' button -, so closing
        // it goes back there; with nothing open (IPC) a plain open.
        PanelService.openOver("sharePicker", {}, {})
        return true
    }

    // Counts and flags only, never a title (IPC `sharePicker get`).
    function describe() {
        return JSON.stringify({ enabled: enabled, pending: pending !== null, preview: preview,
                                open: PanelService.isOpen("sharePicker"), windows: windows.length,
                                screens: Quickshell.screens.length, region: regionAvailable })
    }

    // One line into the request's FIFO, then the request is over. The
    // script holds the FIFO open, so the write does not wait; a script that
    // is gone took its directory along and the write fails at once, and a
    // FIFO nobody reads any more (a script killed outright) is given up on
    // after five seconds.
    function answer(line) {
        if (!pending) return
        const path = pending.dir + "/answer"
        pending = null
        limit.stop()
        shownCheck.stop()
        queue = queue.concat([{ line: line, path: path }])
        if (!writer.running) writeNext()
    }
    property var queue: []
    function writeNext() {
        if (!queue.length) return
        const next = queue[0]
        queue = queue.slice(1)
        writer.command = ["timeout", "5", "sh", "-c", "{ printf '%s\\n' \"$1\" > \"$2\"; } 2>/dev/null", "sh", next.line, next.path]
        writer.running = true
    }
    Process {
        id: writer
        onExited: Qt.callLater(root.writeNext)
    }

    Timer {
        id: limit
        interval: root.waitLimit
        onTriggered: root.cancel()
    }

    // The window list, read once per request from the script's private file.
    // A FileView whose path is set at that moment, so the read is the file's
    // own (testing.md pitfall 91).
    FileView {
        id: listFile
        blockLoading: true
        printErrors: false
    }

    Process {
        id: slurpCheck
        command: ["sh", "-c", "command -v slurp"]
        onExited: code => { root.regionAvailable = code === 0 }
    }
}
