pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "accounts/AccountsLogic.js" as Logic

// Accounts for Settings > Accounts. KDE PIM (Akonadi) owns the accounts and
// their credentials; the shell has no OAuth and stores no tokens. A read-only
// snapshot comes from scripts/accounts-status.sh (busctl on the AgentManager,
// never starting Akonadi); Sync now, Settings … and Remove call the same
// interface. Nothing runs unless the page tracks the service; it then refreshes
// every 10 s. Actions only run in the real session, nested sessions and the
// preview show the command instead. Account names stay in the UI: they are
// never logged and never leave through IPC.
Singleton {
    id: root

    readonly property bool realSession: AppearanceService.realSession
    property int trackers: 0
    property bool loading: false
    property bool refreshQueued: false

    property var liveStatus: Logic.parseStatus("")
    // Synthetic accounts from tests/fixtures for screenshots; actions stay off.
    property var previewStatus: Logic.parseStatus("")
    property bool preview: false
    readonly property var status: preview ? previewStatus : liveStatus

    property string message: ""
    property bool messageError: false
    property string previewCommand: ""
    property string busyId: ""
    property string confirmRemoveId: ""
    // Instance id → epoch ms of a synchronization this session saw.
    property var lastSync: ({})
    property var previewSync: ({})
    property double now: Date.now()

    readonly property bool known: status.known
    readonly property bool serverRunning: status.server
    readonly property var accounts: status.accounts
    readonly property var groups: Logic.groups(status.accounts)
    readonly property string summary: Logic.summary(status)
    readonly property var addOptions: Logic.addOptions(status.tools)
    readonly property int syncingCount: Logic.syncing(status.accounts)
    readonly property int brokenCount: status.accounts.filter(item => item.status === Logic.STATUS_BROKEN).length
    readonly property int offlineCount: status.accounts.filter(item => !item.online).length

    readonly property bool actionsAllowed: realSession && !preview && status.server
    readonly property string blockedReason: preview ? "Preview data: account actions are disabled"
        : !realSession ? "Account actions only run in the buchhwin-shell session"
        : !status.server ? "KDE PIM (Akonadi) is not running" : ""

    function track() { trackers += 1 }
    function untrack() {
        trackers = Math.max(0, trackers - 1)
        if (trackers === 0) confirmRemoveId = ""
    }
    onTrackersChanged: if (trackers > 0) refresh()

    function icon(item) { return Logic.icon(item) }
    function statusText(item) { return Logic.statusText(item) }
    function statusTone(item) { return Logic.statusTone(item) }
    function syncTime(id) {
        const map = preview ? previewSync : lastSync
        return map[id] || 0
    }
    function subtitle(item) { return Logic.subtitle(item, syncTime(item.id), now) }
    function find(id) { return accounts.find(item => item.id === id) || null }
    function isBusy(item) { return !!item && busyId === item.id }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    // ---- snapshot -------------------------------------------------------------
    function refresh() {
        preview = false
        now = Date.now()
        if (statusProc.running) { refreshQueued = true; return }
        loading = true
        statusProc.running = true
    }

    // A resource that stopped running has just finished a synchronization.
    function applyStatus(next) {
        const stamps = Object.assign({}, lastSync)
        let changed = false
        for (const item of next.accounts) {
            const before = liveStatus.accounts.find(entry => entry.id === item.id)
            if (before && before.status === Logic.STATUS_RUNNING && item.status !== Logic.STATUS_RUNNING) {
                stamps[item.id] = Date.now()
                changed = true
            }
        }
        if (changed) lastSync = stamps
        liveStatus = next
        if (confirmRemoveId.length && !next.accounts.some(item => item.id === confirmRemoveId)) confirmRemoveId = ""
    }

    Process {
        id: statusProc
        stderr: ErrorLog { label: "AccountsService.statusProc" }
        command: [Paths.script("accounts-status.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                root.now = Date.now()
                root.applyStatus(Logic.parseStatus(text))
                if (root.refreshQueued) {
                    root.refreshQueued = false
                    Qt.callLater(root.refresh)
                }
            }
        }
    }

    Timer {
        id: poll
        interval: 10000
        repeat: true
        running: root.trackers > 0 && !root.preview
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoon
        interval: 1500
        onTriggered: root.refresh()
    }

    // ---- actions --------------------------------------------------------------
    // action: sync, configure, remove.
    function run(action, item) {
        const id = item ? item.id : ""
        const argv = Logic.command(action, id)
        if (!argv) return
        if (!actionsAllowed) {
            previewCommand = Logic.commandText(argv)
            say((realSession ? "Preview: this command would run." : "Test session: this command would run.")
                + " Nothing was changed.", false)
            return
        }
        if (actionProc.running) { say("Another account action is still running", true); return }
        previewCommand = ""
        busyId = id
        actionProc.action = action
        actionProc.accountId = id
        actionProc.command = Logic.wrap(argv)
        actionProc.running = true
        say(action === "sync" ? "Synchronizing …" : action === "configure" ? "Opening the settings dialog …" : "Removing …", false)
    }

    function sync(item) {
        confirmRemoveId = ""
        run("sync", item)
    }

    function configure(item) {
        confirmRemoveId = ""
        run("configure", item)
    }

    // Removing an account deletes its local copy, so the second click confirms.
    function remove(item) {
        if (!item) return
        if (confirmRemoveId !== item.id) {
            confirmRemoveId = item.id
            say("Click Remove again to take this account out of KDE PIM", false)
            return
        }
        confirmRemoveId = ""
        run("remove", item)
    }

    function cancelRemove() {
        confirmRemoveId = ""
        message = ""
    }

    function finish(text) {
        const action = actionProc.action
        const id = actionProc.accountId
        actionProc.action = ""
        actionProc.accountId = ""
        busyId = ""
        const result = Logic.parseResult(text)
        if (result.code !== 0) {
            // The output can quote the account name and is never logged.
            say(Logic.errorText(action, result.output), true)
            return
        }
        if (action === "sync") {
            const stamps = Object.assign({}, lastSync)
            stamps[id] = Date.now()
            lastSync = stamps
        }
        say(Logic.successText(action), false)
        refreshSoon.restart()
    }

    // A helper that died before it printed anything left the row spinning and
    // the action marked as running for good: `finish` is driven by stdout and
    // nothing else cleared it. Deferred, because the stream may close after the
    // exit - if `finish` already ran there is nothing left to say.
    function actionDied() {
        if (!actionProc.action.length) return
        const action = actionProc.action
        actionProc.action = ""
        actionProc.accountId = ""
        busyId = ""
        say(Logic.errorText(action, ""), true)
    }

    Process {
        id: actionProc
        stderr: ErrorLog { label: "AccountsService.actionProc" }
        property string action: ""
        property string accountId: ""
        stdout: StdioCollector { onStreamFinished: root.finish(text) }
        onExited: code => { if (code !== 0) Qt.callLater(root.actionDied) }
    }

    // ---- adding ---------------------------------------------------------------
    // KDE's wizards own the provider list, the browser login and the tokens.
    function addAccount(option) {
        const argv = Logic.addCommand(option ? option.tool : "")
        if (!argv) return
        confirmRemoveId = ""
        if (!realSession || preview) {
            previewCommand = Logic.commandText(argv)
            say((realSession ? "Preview: this wizard would open." : "Test session: this wizard would open.")
                + " Nothing was changed.", false)
            return
        }
        previewCommand = ""
        Quickshell.execDetached(argv)
        say("The KDE wizard is opening. This list refreshes on its own.", false)
        refreshSoon.restart()
    }

    // ---- preview --------------------------------------------------------------
    function showPreview() {
        message = ""
        previewCommand = ""
        confirmRemoveId = ""
        now = Date.now()
        if (sampleFile.loaded) applySample(sampleFile.text())
        preview = true
    }

    function stopPreview() {
        if (!preview) return
        preview = false
        message = ""
        previewCommand = ""
        confirmRemoveId = ""
        refresh()
    }

    function applySample(text) {
        previewStatus = Logic.parseStatus(text)
        const stamps = {}
        // One synthetic account carries a "last sync" so screenshots show it.
        for (const item of previewStatus.accounts)
            if (item.status === Logic.STATUS_IDLE && item.online) { stamps[item.id] = Date.now() - 23 * 60 * 1000; break }
        previewSync = stamps
    }

    FileView {
        id: sampleFile
        path: Paths.shellFile("tests/fixtures/accounts-status.txt")
        printErrors: false
        onLoaded: if (root.preview) root.applySample(text())
    }
}
