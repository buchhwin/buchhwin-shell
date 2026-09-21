pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "kdeconnect/KdeConnectLogic.js" as Logic

// KDE Connect for Settings > Phone and the control center phone row. The
// daemon (kdeconnectd, started through XDG autostart) owns pairing and the
// network; this service reads a snapshot through scripts/kdeconnect-status.sh
// (devices, battery, cellular signal, media player, lock state and the number
// of mirrored notifications) and runs kdeconnect-cli/kdeconnect-sms/busctl
// actions. Notification texts are only read while the list is open, through
// scripts/kdeconnect-notifications.sh; they never reach the log or IPC.
// Nothing runs unless a page or indicator tracks the service; it then
// refreshes every 10 s. Actions and starting the daemon only run in the real
// session: nested sessions share the host's daemon.
Singleton {
    id: root

    readonly property bool realSession: AppearanceService.realSession
    property int trackers: 0
    property var status: Logic.parseStatus("")
    property bool loading: false
    // Synthetic devices from tests/fixtures for screenshots; actions stay off.
    property bool preview: false
    property string message: ""
    property bool messageError: false
    property var pending: []

    readonly property bool known: status.known
    readonly property bool running: status.daemon
    readonly property string summary: Logic.summary(status)
    readonly property var requests: status.devices.filter(item => item.requestedByPeer)
    readonly property var paired: status.devices.filter(item => item.paired && !item.requestedByPeer)
    readonly property var available: status.devices.filter(item => !item.paired && !item.requestedByPeer)
    readonly property var connected: status.devices.filter(item => item.paired && item.reachable)
    // The phone row of the control center: a connected phone, else any other
    // connected device; null hides the row.
    readonly property var phone: connected.find(item => item.type === "phone") || connected[0] || null
    readonly property bool actionsAllowed: realSession && !preview && running
    readonly property string blockedReason: preview ? "Preview data: phone actions are disabled"
        : !realSession ? "Phone actions only run in the buchhwin-shell session" : ""

    // Notification list of one device: only filled while the list is open.
    property string notificationsId: ""
    property var notifications: []
    property bool notificationsLoading: false

    function track() { trackers += 1 }
    function untrack() {
        trackers = Math.max(0, trackers - 1)
        if (trackers === 0) closeNotifications()
    }
    onTrackersChanged: if (trackers > 0) refresh()

    function stateText(item) { return Logic.stateText(item) }
    function batteryText(item) { return Logic.batteryText(item.battery) }
    function detailText(item) { return Logic.detailText(item) }
    function signalText(item) { return Logic.signalText(item.connectivity) }
    function signalIcon(item) { return Logic.signalIcon(item.connectivity) }
    function mediaTitle(item) { return Logic.mediaTitle(item.media) }
    function mediaSubtitle(item) { return Logic.mediaSubtitle(item.media) }
    function notificationCountText(count) { return Logic.notificationCountText(count) }
    function deviceIcon(item) { return Logic.deviceIcon(item.type) }
    function supports(item, plugin) { return Logic.supports(item, plugin) }
    function hasMedia(item) { return item.media !== null && supports(item, "mprisremote") }

    function refresh() {
        preview = false
        loadNotifications()
        if (statusProc.running) { refreshAgain.running = true; return }
        loading = true
        statusProc.running = true
    }

    // Asks the daemon to announce itself and reconnect, then reads again.
    function discover() {
        if (!actionsAllowed) { refresh(); return }
        Quickshell.execDetached(["kdeconnect-cli", "--refresh"])
        say("Searching for phones …", false)
        refreshSoon.restart()
    }

    function startDaemon() {
        if (!realSession || running || !known) return
        Quickshell.execDetached(["kdeconnectd"])
        say("Starting KDE Connect …", false)
        refreshSoon.restart()
    }

    function openApp() {
        Quickshell.execDetached(["kdeconnect-app"])
        PanelService.close()
    }

    function previewDevices() {
        preview = true
        message = ""
        if (sampleFile.loaded) status = Logic.parseStatus(sampleFile.text())
        if (notificationsId.length) loadNotifications()
    }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    // action: pair, unpair, ping, ring, clipboard, lock, unlock, accept,
    // reject, play, next, previous.
    function run(action, item) { runWith(action, item, undefined) }

    function runWith(action, item, extra) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const argv = Logic.command(action, item.id, extra)
        if (argv) enqueue(argv, action, item.name)
        else say("This action is not available for " + item.name, true)
    }

    // Media on the phone (mprisremote plugin).
    function media(item, action) { run(action, item) }
    function setMediaVolume(item, volume) { runWith("volume", item, volume) }
    function setMediaPlayer(item, player) { runWith("player", item, player) }

    // A web address is opened on the phone, anything else arrives as text.
    function sendText(item, text) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const share = Logic.shareAction(text)
        if (!share) { say("Enter a link or some text first", true); return }
        runWith(share.action, item, share.value)
    }

    // kdeconnect-sms is a separate app; it opens the conversation list.
    function openSms(item) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const argv = Logic.command("sms", item.id)
        if (!argv) return
        Quickshell.execDetached(argv)
        say("Opening Messages for " + item.name + " …", false)
    }

    function toggleNotifications(item) {
        if (notificationsId === item.id) { closeNotifications(); return }
        if (!Logic.validId(item.id)) return
        notificationsId = item.id
        notifications = []
        loadNotifications()
    }

    function closeNotifications() {
        notificationsId = ""
        notifications = []
        notificationsLoading = false
    }

    // Reads the open notifications of the tracked device. Read-only, and only
    // while the list is shown; the texts stay inside this process.
    function loadNotifications() {
        if (!notificationsId.length) return
        if (preview) {
            notifications = noteSample.loaded ? Logic.parseNotifications(noteSample.text()) : []
            return
        }
        if (!running || notesProc.running) return
        notificationsLoading = true
        notesProc.deviceId = notificationsId
        notesProc.command = [Paths.script("kdeconnect-notifications.sh"), notificationsId]
        notesProc.running = true
    }

    // Answering a mirrored notification. The phone only accepts one for a
    // notification that says it can be replied to, so the field is offered
    // there and nowhere else.
    function replyToNotification(item, note, text) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return false }
        const trimmed = String(text || "").trim()
        if (!trimmed.length) { say("Write an answer first", true); return false }
        const argv = Logic.command("reply", item.id, { note: note.id, text: trimmed })
        if (!argv) { say("This notification cannot be answered", true); return false }
        enqueue(argv, "reply", item.name)
        return true
    }

    // A command the phone offers (runcommand plugin). The key comes from the
    // phone and is checked like every other id that becomes an argument.
    function runCommand(item, entry) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const argv = Logic.command("runCommand", item.id, entry.key)
        if (argv) enqueue(argv, "runCommand", item.name)
        else say("This command is not available", true)
    }

    // Browsing the phone: the daemon mounts it over SFTP and opens the file
    // manager itself, so the shell never has to know where it landed.
    function browseFiles(item) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const argv = Logic.command("browse", item.id)
        if (argv) enqueue(argv, "browse", item.name)
    }

    function dismissNotification(item, note) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        const argv = Logic.command("dismiss", item.id, note.id)
        if (argv) enqueue(argv, "dismiss", item.name)
    }

    function sendFiles(item) {
        if (!actionsAllowed) { say(blockedReason || "KDE Connect is not running", true); return }
        if (pickProc.running || !Logic.validId(item.id)) return
        pickProc.deviceId = item.id
        pickProc.deviceName = item.name
        pickProc.command = ["kdialog", "--title", "Send files to " + item.name, "--multiple", "--separate-output",
                            "--getopenfilename", Paths.home]
        pickProc.running = true
    }

    function enqueue(argv, action, name) {
        pending = pending.concat([{ argv: argv, action: action, name: name }])
        next()
    }

    function next() {
        if (actionProc.running || !pending.length) return
        actionProc.job = pending[0]
        pending = pending.slice(1)
        actionProc.command = actionProc.job.argv
        actionProc.running = true
    }

    function doneText(job) {
        const name = job.name
        switch (job.action) {
        case "pair": return "Pairing request sent to " + name + ". Accept it on the phone."
        case "unpair": return name + " was unpaired"
        case "ping": return "Ping sent to " + name
        case "ring": return name + " is ringing"
        case "clipboard": return "Clipboard sent to " + name
        case "share": return "Sending to " + name + " …"
        case "url": return "Link opened on " + name
        case "text": return "Text sent to " + name
        case "lock": return name + " was locked"
        case "unlock": return name + " was unlocked"
        case "accept": return name + " is now paired"
        case "reject": return "Pairing with " + name + " rejected"
        case "dismiss": return "Notification dismissed"
        case "reply": return "Answer sent to " + name
        case "runCommand": return "Command started on " + name
        case "browse": return "Opening the files of " + name + " …"
        // Media and player changes show up in the next refresh instead.
        case "play": case "next": case "previous": case "volume": case "player": return ""
        default: return ""
        }
    }

    Process {
        id: statusProc
        stderr: ErrorLog { label: "KdeConnectService.statusProc" }
        command: [Paths.script("kdeconnect-status.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                if (!root.preview) root.status = Logic.parseStatus(text)
            }
        }
    }

    Process {
        id: actionProc
        property var job: null
        property int exitCode: 0
        // The error text may arrive before or after the exit.
        function report() {
            const detail = actionErrors.text.trim().split("\n")[0]
            if (exitCode === 0) root.say(root.doneText(job), false)
            else root.say("Could not reach " + job.name + (detail.length ? ": " + detail : ""), true)
        }
        stderr: StdioCollector {
            id: actionErrors
            onStreamFinished: if (actionProc.exitCode !== 0 && !actionProc.running && actionProc.job) actionProc.report()
        }
        onStarted: exitCode = 0
        onExited: code => {
            exitCode = code
            report()
            if (["pair", "unpair", "accept", "reject"].indexOf(job.action) >= 0) root.refresh()
            // The phone answers media, lock and dismiss requests over the
            // network, so the new state only arrives a moment later.
            else if (["play", "next", "previous", "volume", "player", "lock", "unlock"].indexOf(job.action) >= 0)
                refreshSoon.restart()
            else if (job.action === "dismiss") root.loadNotifications()
            root.next()
        }
    }

    Process {
        id: notesProc
        stderr: ErrorLog { label: "KdeConnectService.notesProc" }
        property string deviceId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.notificationsLoading = false
                if (root.preview) return
                // Another device was selected while the script ran: drop this
                // answer and read that device instead.
                if (root.notificationsId !== notesProc.deviceId) { root.loadNotifications(); return }
                root.notifications = Logic.parseNotifications(text)
            }
        }
    }

    Process {
        id: pickProc
        stderr: ErrorLog { label: "KdeConnectService.pickProc" }
        property string deviceId: ""
        property string deviceName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const files = Logic.parseFiles(text)
                for (const file of files) {
                    const argv = Logic.command("share", pickProc.deviceId, file)
                    if (argv) root.enqueue(argv, "share", pickProc.deviceName)
                }
            }
        }
    }

    FileView {
        id: sampleFile
        path: root.preview ? Paths.shellFile("tests/fixtures/kdeconnect-status.txt") : ""
        printErrors: false
        onLoaded: if (root.preview) root.status = Logic.parseStatus(text())
    }

    // Synthetic notifications so the list can be screenshotted nested.
    FileView {
        id: noteSample
        path: root.preview ? Paths.shellFile("tests/fixtures/kdeconnect-notifications.txt") : ""
        printErrors: false
        onLoaded: if (root.preview && root.notificationsId.length) root.notifications = Logic.parseNotifications(text())
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.trackers > 0 && !root.preview
        onTriggered: root.refresh()
    }
    // Pair requests and the daemon take a moment to show up after an action.
    Timer { id: refreshSoon; interval: 2500; onTriggered: root.refresh() }
    Timer { id: refreshAgain; interval: 300; onTriggered: root.refresh() }
}
