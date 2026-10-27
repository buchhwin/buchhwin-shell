pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "clipboard/ClipboardLogic.js" as Logic
import "clipboard/PinLogic.js" as Pin

// Clipboard history through cliphist with its own database in the shell's
// cache directory. Text and images are recorded while the setting is on;
// entries marked sensitive by password managers are skipped by cliphist. The
// database and the previews are the user's alone (0600/0700, see
// clipboard/ClipboardLogic.js), previews from before included: the recorders
// take both as they start.
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

    // Preview path once it has been decoded, otherwise "". A pinned picture
    // is its own file, there from the moment it was pinned.
    function thumbnail(entry) {
        if (entry.pinned === true) return entry.image ? "file://" + pinsDir + "/" + Pin.fileName(entry) : ""
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

    // The history only: pinned entries stay (they are kept apart for that).
    function wipe() {
        // A wipe creates the database when there is none yet (a clear before
        // the first copy), and the recorders set its mode only as they start.
        Quickshell.execDetached(Logic.privately(dbPath, ["cliphist", "-db-path", dbPath, "wipe"]))
        Quickshell.execDetached(["rm", "-rf", "--", thumbDir])
        entries = []
        readyThumbs = ({})
        // cliphist starts its ids at 1 again.
        if (ageMarks.length) saveMarks([])
    }

    // ---- pinned entries (Ctrl+P in the panel; PinLogic has how) -------------
    // A copy of each pinned entry's content in the state directory, outside
    // cliphist's rotation, "Clear history" and both ways of forgetting. The
    // index is read the first time the panel opens (a small JSON file) and
    // written by the shell alone, so it is not watched.
    readonly property string pinsDir: Paths.stateDir + "/clipboard-pins"
    property var pins: []              // [{ id, image, format, text }], newest first
    // The pins as the panel lists them: marked, and made once per change of
    // the pins rather than in the panel's filter on every key.
    readonly property var pinRows: pins.map(item => Object.assign({ pinned: true }, item))
    property bool pinsRead: false
    // An index that is there but could not be read is kept as it is, and
    // nothing is pinned over it.
    property bool pinsWritable: true
    readonly property bool pinsFull: Pin.full(pins)
    readonly property int pinLimit: Pin.LIMIT
    // The panel says why a pin did nothing: the list is full.
    signal pinRefused()

    // Turning `preload` on is what reads a FileView that never read (pitfall
    // 34), and from the panel's open it is switched a turn later.
    function loadPins() {
        if (pinsRead || pinsFile.preload) return
        Qt.callLater(() => { pinsFile.preload = true })
    }

    function isPinned(entry) { return entry !== null && entry !== undefined && entry.pinned === true }

    // A history entry into the pins, or a pin out of them.
    function togglePin(entry) {
        if (!entry) return false
        return isPinned(entry) ? unpin(entry) : pin(entry)
    }

    function pin(entry) {
        if (!entry || isPinned(entry) || !pinsRead || !pinsWritable || pinProc.running) return false
        if (pinsFull) { pinRefused(); return false }
        pinProc.entry = { image: entry.image === true, format: entry.image ? entry.format : "", text: entry.text }
        pinProc.command = Pin.pinCommand(pinsDir, dbPath, entry.id, entry.image ? entry.format : "txt")
        pinProc.running = true
        return true
    }

    // `clipboard pin N` over IPC: the history's N-th entry (0 the newest, as
    // the panel lists them), once the pins are read - an IPC call can come
    // before the panel ever opened.
    property var pendingPin: null
    function pinAt(index) {
        const entry = entries[index]
        if (!entry) return false
        if (pinsRead) return pin(entry)
        pendingPin = entry
        loadPins()
        return true
    }
    onPinsReadChanged: if (pinsRead && pendingPin) {
        const entry = pendingPin
        pendingPin = null
        pin(entry)
    }
    function unpinAt(index) {
        return unpin(pins.length > index && index >= 0 ? pinRows[index] : null)
    }

    function unpin(item) {
        if (!isPinned(item) || !pinsWritable) return false
        Quickshell.execDetached(Pin.removeCommand(pinsDir, item))
        savePins(Pin.without(pins, item.id))
        return true
    }

    function copyPin(item) {
        if (isPinned(item)) Quickshell.execDetached(Pin.copyCommand(pinsDir, item))
    }

    function savePins(list) {
        pins = list
        pinsWrite.restart()
    }
    // One write per turn of the event loop (pitfall 3): a pin and an unpin
    // in the same turn are one write of the list as it stands.
    Timer { id: pinsWrite; interval: 0; onTriggered: pinsFile.setText(Pin.serialize(root.pins)) }

    FileView {
        id: pinsFile
        path: Paths.stateDir + "/clipboard-pins.json"
        preload: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const read = Pin.parse(text())
            root.pins = read.pins
            if (!read.ok) {
                root.pinsWritable = false
                console.warn("buchhwin-shell: the clipboard's pinned entries are unreadable, kept as they are:", path)
                root.pinsRead = true
                return
            }
            // Pinning waits for the settle run (pinsRead comes at its end): a
            // pin run beside it would have its temporary file removed as no
            // pin's, or its new pin dropped with the names listed before it.
            pinsSettle.command = Pin.settleCommand(root.pinsDir, read.pins)
            pinsSettle.running = true
        }
        // Not there yet is no pins; anything else is a file that is there
        // and is not written over (pitfall 132).
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                root.pinsWritable = false
                console.warn("buchhwin-shell: the clipboard's pinned entries could not be read:", FileViewError.toString(error))
            }
            root.pinsRead = true
        }
        onSaved: Quickshell.execDetached(["chmod", "600", "--", pinsFile.path])
    }

    // Once, after the index is read: what no pin owns goes, and a pin whose
    // file went is dropped (PinLogic.settleCommand, .present).
    Process {
        id: pinsSettle
        stderr: ErrorLog { label: "ClipboardService.pinsSettle" }
        stdout: StdioCollector {
            onStreamFinished: {
                const kept = Pin.present(root.pins, text.split("\n").filter(line => line.length))
                if (kept.length !== root.pins.length) root.savePins(kept)
            }
        }
        // The listing is in by now (pitfall 131): pins may be taken.
        onExited: root.pinsRead = true
    }

    Process {
        id: pinProc
        property var entry: null
        stderr: ErrorLog { label: "ClipboardService.pinProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                const id = Pin.pinnedId(text)
                if (!id.length || !pinProc.entry) return
                const next = Pin.withPin(root.pins, Object.assign({ id: id }, pinProc.entry))
                if (next) root.savePins(next)
            }
        }
    }

    // ---- forgetting (both off by default; ClipboardLogic has how) ------------
    readonly property bool forgetAtLogout: SettingsService.value("clipboard.forgetAtLogout") === true
    readonly property int maxAgeHours: Logic.maxAgeHours(SettingsService.value("clipboard.maxAgeHours"))
    readonly property bool expiring: enabled && maxAgeHours > 0

    // The session ends from the shell (SessionService: log out, restart, shut
    // down). A session that ends otherwise - a crash, the power - is caught
    // at the next login below.
    function sessionEnding() { if (forgetAtLogout) wipe() }

    // The first start of the shell in a login (LoginMark). Named after the
    // database as well, so a nested session's history is its own.
    property bool loginChecked: false
    function checkLogin() {
        if (loginChecked || !SettingsService.loaded) return
        loginChecked = true
        loginCheck.check()
    }
    LoginMark {
        id: loginCheck
        name: "clipboard-" + Qt.md5(root.dbPath)
        onDecided: first => { if (first && root.forgetAtLogout) root.wipe() }
    }
    Connections {
        target: SettingsService
        function onLoadedChanged() { root.checkLogin() }
    }
    Component.onCompleted: {
        checkLogin()
        if (x11Display.length > 0) Hyprland.refreshToplevels()
    }

    // Entries older than the limit go at each read of the list, which runs
    // every 30 minutes while the limit is set, besides the panel's own reads.
    property var ageMarks: []
    property bool marksRead: false
    onExpiringChanged: if (expiring) refresh()
    Timer { interval: 30 * 60000; repeat: true; running: root.expiring; onTriggered: root.refresh() }

    function forgetOld(list) {
        if (!expiring || !marksRead) return list
        const ids = list.map(entry => entry.id)
        const now = Date.now()
        const maxAge = maxAgeHours * 3600000
        const marks = Logic.withMark(ageMarks, now, ids.reduce((top, id) => Math.max(top, Number(id)), 0), maxAge)
        if (JSON.stringify(marks) !== JSON.stringify(ageMarks)) saveMarks(marks)
        const expired = Logic.expiredIds(ids, marks, now, maxAge)
        if (!expired.length) return list
        Quickshell.execDetached(Logic.deleteCommand(dbPath, expired))
        return list.filter(entry => expired.indexOf(entry.id) < 0)
    }

    function saveMarks(marks) {
        ageMarks = marks
        marksFile.setText(JSON.stringify({ marks: marks }) + "\n")
    }

    // Ids and times only, but when something was copied is the user's too.
    FileView {
        id: marksFile
        path: Paths.cacheDir + "/clipboard-ages.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.ageMarks = Array.isArray(data.marks) ? data.marks : []
            } catch (error) {
                root.ageMarks = []
            }
            root.marksRead = true
        }
        onLoadFailed: root.marksRead = true
        onSaved: Quickshell.execDetached(["chmod", "600", "--", marksFile.path])
    }

    Process {
        id: listProc
        stderr: ErrorLog { label: "ClipboardService.listProc" }
        command: ["cliphist", "-db-path", root.dbPath, "-preview-width", "160", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = root.forgetOld(root.parse(text))
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
        command: Paths.bound(Logic.privately(root.dbPath, ["wl-paste", "--type", "text", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"], root.thumbDir))
    }
    Process {
        stderr: ErrorLog { label: "ClipboardService.process" }
        running: root.enabled && !root.recordersRestarting
        command: Paths.bound(Logic.privately(root.dbPath, ["wl-paste", "--type", "image", "--watch", "cliphist", "-db-path", root.dbPath, "-max-items", String(root.maxItems), "store"], root.thumbDir))
    }

    // Text and pictures an X11 program copies - not what a password manager
    // marks as a secret - handed on to the Wayland clipboard
    // (scripts/x11-clipboard-bridge.py): Hyprland mirrors an X11 clipboard
    // only while an X11 window has the focus, and Citrix's client sets it as
    // its window loses the focus - copied in Citrix, it could not be pasted
    // here (16.10.). Not tied to the history: pasting is the point, not
    // keeping. Started with the session's first X11 window and kept from then
    // on (ClipboardLogic.bridgeWanted has why); restarted after a growing
    // pause if it ever ends, five times in a row at most, like the monitors.
    readonly property string x11Display: Quickshell.env("DISPLAY") || ""
    property bool bridgePaused: false
    property int bridgeFailures: 0
    // An X11 window has been there this session. Hyprland's windows say
    // whether they are X11 ones only in their IPC objects, which a
    // refreshToplevels() fills (one socket request, no process): asked once at
    // the start (a restarted shell may find Citrix running) and after every
    // window that opens, until the first X11 one; from then on nothing here
    // looks at the windows any more.
    property bool sawX11: false
    readonly property bool x11WindowOpen: !sawX11 && x11Display.length > 0
        && Logic.anyX11(Hyprland.toplevels.values.map(toplevel => toplevel.lastIpcObject))
    // Noted a turn later: x11WindowOpen depends on sawX11, and setting it
    // from inside the change of x11WindowOpen is a binding loop that also
    // leaves x11WindowOpen true (probed offscreen).
    function noteX11() { sawX11 = true }
    onX11WindowOpenChanged: if (x11WindowOpen) Qt.callLater(root.noteX11)
    Connections {
        target: root.x11Display.length > 0 ? Hyprland : null
        enabled: !root.sawX11
        function onRawEvent(event) { if (event.name === "openwindow") x11Look.restart() }
    }
    Timer { id: x11Look; interval: 100; onTriggered: Hyprland.refreshToplevels() }

    Process {
        stderr: ErrorLog { label: "ClipboardService.x11Bridge" }
        running: Logic.bridgeWanted(root.x11Display, root.sawX11, root.bridgePaused)
        command: Paths.bound(["python3", "-I", Paths.script("x11-clipboard-bridge.py"), "--display", root.x11Display])
        onRunningChanged: {
            if (running) { bridgeHealthy.restart(); return }
            bridgeHealthy.stop()
            if (!Logic.bridgeWanted(root.x11Display, root.sawX11, root.bridgePaused)) return
            root.bridgeFailures += 1
            const delay = Logic.bridgeRestartDelay(root.bridgeFailures)
            if (delay < 0) return
            root.bridgePaused = true
            bridgeRestart.interval = delay
            bridgeRestart.restart()
        }
    }
    Timer { id: bridgeRestart; onTriggered: root.bridgePaused = false }
    Timer { id: bridgeHealthy; interval: 60000; onTriggered: root.bridgeFailures = 0 }
}
