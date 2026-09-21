pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history through cliphist with its own database in the shell's
// cache directory. Text and images are recorded while the setting is on;
// entries marked sensitive by password managers are skipped by cliphist.
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
        Quickshell.execDetached(["cliphist", "-db-path", dbPath, "wipe"])
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
                root.entries = root.parse(text).slice(0, 200)
                root.loading = false
                // Decode image previews for the first entries.
                root.decodeThumbnails()
            }
        }
        onExited: root.loading = false
    }

    // Decodes previews of the first images; a run in progress finishes first
    // and a new run follows, each with its own list.
    property bool thumbsQueued: false
    function decodeThumbnails() {
        if (thumbProc.running) { thumbsQueued = true; return }
        const images = entries.filter(entry => entry.image && !readyThumbs[entry.thumb]).slice(0, 24)
        if (!images.length) return
        thumbProc.pending = images.map(entry => entry.thumb)
        thumbProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && dir=\"$1\" && db=\"$2\" && shift 2 && while [ $# -gt 1 ]; do [ -s \"$dir/$2\" ] || cliphist -db-path \"$db\" decode \"$1\" > \"$dir/$2\"; shift 2; done",
            "sh", thumbDir, dbPath].concat(images.reduce((list, entry) => list.concat([entry.id, entry.thumb]), []))
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        stderr: ErrorLog { label: "ClipboardService.thumbProc" }
        property var pending: []
        onExited: {
            const next = Object.assign({}, root.readyThumbs)
            for (const name of pending) next[name] = true
            root.readyThumbs = next
            if (root.thumbsQueued) {
                root.thumbsQueued = false
                Qt.callLater(root.decodeThumbnails)
            }
        }
    }
    property var readyThumbs: ({})

    // Recorders: one for text, one for images.
    Process {
        stderr: ErrorLog { label: "ClipboardService.process" }
        running: root.enabled
        command: ["wl-paste", "--type", "text", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"]
    }
    Process {
        stderr: ErrorLog { label: "ClipboardService.process" }
        running: root.enabled
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"]
    }
}
