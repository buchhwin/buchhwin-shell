pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "clipboard/ClipboardLogic.js" as Logic

// Clipboard history through cliphist with its own database in the shell's
// cache directory. Text and images are recorded while the setting is on;
// entries marked sensitive by password managers are skipped by cliphist. The
// database and the previews are the user's alone (0600/0700, see
// clipboard/ClipboardLogic.js).
Singleton {
    id: root

    readonly property bool enabled: SettingsService.value("clipboard.history")
    readonly property int maxItems: Math.max(20, Math.min(1000, SettingsService.value("clipboard.maxItems")))
    readonly property string dbPath: Paths.cacheDir + "/cliphist.db"
    // Next to the database, so nested sessions and wiped histories (cliphist
    // restarts its ids at 1) never show another history's images.
    readonly property string thumbDir: Paths.cacheDir + "/clipboard-previews"
    property var entries: []           // [{ id, text, image, size }]
    property bool loading: false

    function refresh() {
        if (!listProc.running) {
            loading = true
            listProc.running = true
        }
    }

    function parse(text) {
        return text.split("\n").filter(line => line.length).map(line => {
            const tab = line.indexOf("\t")
            const id = line.slice(0, tab)
            const preview = line.slice(tab + 1)
            const image = /^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/.exec(preview)
            const format = image ? (image[2] === "jpg" ? "jpeg" : image[2]) : ""
            return { id: id, text: image ? "Image · " + image[3] + " · " + image[1] : preview, image: image !== null,
                     format: format,
                     // File name includes size and dimensions as a second guard against reused ids.
                     thumb: image ? id + "-" + image[3] + "-" + image[1].replace(/[^0-9A-Za-z]/g, "") + "." + format : "" }
        }).filter(entry => /^\d+$/.test(entry.id))
    }

    // Preview path once it has been decoded, otherwise "".
    function thumbnail(entry) {
        if (!entry.image || !readyThumbs[entry.thumb]) return ""
        return "file://" + thumbDir + "/" + entry.thumb
    }

    function copy(entry) {
        Quickshell.execDetached(["sh", "-c", "cliphist -db-path \"$1\" decode \"$2\" | wl-copy", "sh", dbPath, entry.id])
    }

    function remove(entry) {
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$2\" | cliphist -db-path \"$1\" delete", "sh", dbPath, entry.id])
        entries = entries.filter(item => item.id !== entry.id)
        if (entry.image) Quickshell.execDetached(["rm", "-f", "--", thumbDir + "/" + entry.thumb])
    }

    function wipe() {
        // A wipe creates the database when there is none yet (a clear before
        // the first copy), and the recorders set its mode only as they start.
        Quickshell.execDetached(Logic.privately(dbPath, ["cliphist", "-db-path", dbPath, "wipe"]))
        Quickshell.execDetached(["rm", "-rf", "--", thumbDir])
        entries = []
        readyThumbs = ({})
    }

    Process {
        id: listProc
        stderr: ErrorLog { label: "ClipboardService.listProc" }
        command: ["cliphist", "-db-path", root.dbPath, "-preview-width", "160", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = root.parse(text)
                root.entries = list.slice(0, 200)
                root.pruneThumbnails(list)
                root.loading = false
                // Decode image previews for the first entries.
                root.decodeThumbnails()
            }
        }
        onExited: root.loading = false
    }

    // Entries cliphist drops at `max-items` left their preview file and their
    // mark in `readyThumbs` behind for good: only a remove or a wipe here
    // cleaned up. Each read of the list now keeps what its entries need and
    // lets the rest go - all of the history, not only the 200 shown, so no
    // file of an entry still in it is touched. The marks are the files this
    // session decoded, so their difference with the list names what to
    // delete; files from before it (a restart, a crash) are found by one
    // look into the directory at the first read. Only files directly in the
    // shell's own preview directory are deleted. An empty read prunes
    // nothing: previews are a cache, but a cliphist that failed to open its
    // database is no reason to throw them away.
    property bool thumbsSwept: false
    function pruneThumbnails(list) {
        if (!list.length) return
        const wanted = {}
        for (const entry of list) if (entry.image) wanted[entry.thumb] = true
        const kept = {}
        const gone = []
        for (const name of Object.keys(readyThumbs)) {
            if (wanted[name]) kept[name] = true
            else gone.push(name)
        }
        if (gone.length) readyThumbs = kept
        if (!thumbsSwept) {
            thumbsSwept = true
            Quickshell.execDetached(["sh", "-c",
                "dir=\"$1\"; shift; [ -d \"$dir\" ] || exit 0; for f in \"$dir\"/*; do [ -f \"$f\" ] || continue; name=${f##*/}; for k in \"$@\"; do [ \"$k\" = \"$name\" ] && continue 2; done; rm -f -- \"$f\"; done",
                "sh", thumbDir].concat(Object.keys(wanted)))
        } else if (gone.length) {
            Quickshell.execDetached(["rm", "-f", "--"].concat(gone.map(name => thumbDir + "/" + name)))
        }
    }

    // Decodes previews of the first images; a run in progress finishes first
    // and a new run follows, each with its own list.
    property bool thumbsQueued: false
    function decodeThumbnails() {
        if (thumbProc.running) { thumbsQueued = true; return }
        const images = entries.filter(entry => entry.image && !readyThumbs[entry.thumb]).slice(0, 24)
        if (!images.length) return
        thumbProc.pending = images.map(entry => entry.thumb)
        thumbProc.command = Logic.previewsCommand(thumbDir, dbPath, images.map(entry => [entry.id, entry.thumb]))
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        stderr: ErrorLog { label: "ClipboardService.thumbProc" }
        property var pending: []
        // Only the files that came out non-empty are ready; a failed decode
        // is tried again next time instead of showing a broken image. The
        // list may arrive before or after the exit; it is read once both are
        // in - read at the exit, it could still be empty.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function finish() {
            if (!outputDone || exitCode < 0) return
            const next = Object.assign({}, root.readyThumbs)
            const made = output.split("\n")
            for (const name of pending) if (made.indexOf(name) >= 0) next[name] = true
            root.readyThumbs = next
            if (root.thumbsQueued) {
                root.thumbsQueued = false
                Qt.callLater(root.decodeThumbnails)
            }
        }
        stdout: StdioCollector { onStreamFinished: { thumbProc.output = text; thumbProc.outputDone = true; thumbProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }
    property var readyThumbs: ({})

    // Recorders: one for text, one for images. A running Process keeps the
    // command it was started with, so a new limit has to stop them and start
    // them again - through a flag and a timer, because assigning `running`
    // would take the binding on `enabled` with it, and the old process needs
    // a moment to be gone before the new one may start (the same shape as
    // NightLightService's restart).
    property bool recordersRestarting: false
    onMaxItemsChanged: {
        recordersRestarting = true
        recorderRestart.restart()
    }
    Timer { id: recorderRestart; interval: 300; onTriggered: root.recordersRestarting = false }
    Process {
        stderr: ErrorLog { label: "ClipboardService.process" }
        running: root.enabled && !root.recordersRestarting
        command: Paths.bound(Logic.privately(root.dbPath, ["wl-paste", "--type", "text", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"]))
    }
    Process {
        stderr: ErrorLog { label: "ClipboardService.process" }
        running: root.enabled && !root.recordersRestarting
        command: Paths.bound(Logic.privately(root.dbPath, ["wl-paste", "--type", "image", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"]))
    }

    // Text and pictures an X11 program copies - not what a password manager
    // marks as a secret - handed on to the Wayland clipboard
    // (scripts/x11-clipboard-bridge.py): Hyprland mirrors an X11 clipboard
    // only while an X11 window has the focus, and Citrix's client sets it as
    // its window loses the focus - copied in Citrix, it could not be pasted
    // here (16.10.). Not tied to the history: pasting is the point, not
    // keeping. Restarted after a pause if it ever ends, like the monitors.
    readonly property string x11Display: Quickshell.env("DISPLAY") || ""
    property bool bridgePaused: false
    Process {
        stderr: ErrorLog { label: "ClipboardService.x11Bridge" }
        running: root.x11Display.length > 0 && !root.bridgePaused
        command: Paths.bound(["python3", "-I", Paths.script("x11-clipboard-bridge.py"), "--display", root.x11Display])
        onRunningChanged: {
            if (running || root.x11Display.length === 0 || root.bridgePaused) return
            root.bridgePaused = true
            bridgeRestart.restart()
        }
    }
    Timer { id: bridgeRestart; interval: 5000; onTriggered: root.bridgePaused = false }
}
