pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "updates/UpdatesLogic.js" as Logic

// Available updates for Settings > Updates: system packages (dnf5, read-only
// as the user) and Flatpaks (system and user installations) through
// scripts/updates-check.sh. Installing needs the administrator password, so
// the shell only checks and hands off to Discover; Flatpaks of the user
// installation can be updated in a Kitty window on request. The automatic
// check (every `updates.checkHours`) and its notification only run in the real
// session; nested sessions check on "Check now" from the dnf cache and never
// notify. Last check times, the notified set and the last result are kept in
// $XDG_STATE_HOME/buchhwin-shell/updates.json.
Singleton {
    id: root

    readonly property bool realSession: AppearanceService.realSession
    readonly property int checkHours: Logic.validHours(SettingsService.value("updates.checkHours"))
    readonly property bool notifyEnabled: SettingsService.value("updates.notify")

    property var state: Logic.parseState("")
    property bool stateLoaded: false
    property var result: Logic.emptyResult()
    property bool checking: false
    // Synthetic updates from tests/fixtures for screenshots; actions stay off.
    property bool preview: false
    property real previewTime: 0
    property string message: ""
    property bool messageError: false
    property real now: Date.now()

    readonly property var packages: result.packages
    readonly property var flatpaks: result.flatpaks
    readonly property int securityCount: Logic.securityCount(result)
    readonly property int userFlatpakCount: Logic.userFlatpaks(result).length
    readonly property int total: Logic.total(result)
    readonly property string summary: checking && !result.packagesKnown && !result.flatpaksKnown ? "Checking for updates …" : Logic.summary(result)
    readonly property real lastCheck: preview ? previewTime : state.lastCheck
    readonly property string checkedText: Logic.checkedText(lastCheck, now)
    readonly property bool flatpakUpdating: flatpakProc.running
    readonly property bool actionsAllowed: realSession && !preview
    readonly property string flatpakInstallations: Logic.installationsText(result)
    // Expanded lists on the page (kept here so IPC can open them for screenshots).
    property bool packagesExpanded: false
    property bool flatpaksExpanded: false

    function packageSubtitle(item) { return Logic.packageSubtitle(item) }
    function flatpakSubtitle(item) { return Logic.flatpakSubtitle(item) }
    function severityLabel(item) { return Logic.severityLabel(item.severity) }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    // automatic: from the timer (notifies about new updates).
    function check(automatic) {
        if (checkProc.running) return
        if (preview) stopPreview()
        const started = Date.now()
        const cacheOnly = !realSession
        const refresh = !cacheOnly && Logic.refreshDue(started, state, checkHours)
        checkProc.automatic = !!automatic
        checkProc.refresh = refresh
        checkProc.started = started
        checkProc.command = Logic.checkCommand(Paths.script("updates-check.sh"), refresh, cacheOnly)
        checking = true
        if (!automatic) say(cacheOnly ? "Checking with cached package data (test session) …" : "Checking for updates …", false)
        checkProc.running = true
    }

    function finish(text) {
        checking = false
        now = Date.now()
        const next = Logic.parseReport(text)
        const errors = [next.packageError, next.flatpakError].filter((item, index, list) => item.length && list.indexOf(item) === index)
        const nextState = Object.assign({}, state, { lastAttempt: checkProc.started })
        if (next.checked) nextState.lastCheck = checkProc.started
        if (checkProc.refresh && next.packagesKnown && !next.packagesCached) nextState.lastRefresh = checkProc.started
        // Keep the last known list when a source failed without a cache.
        if (!next.packagesKnown && result.packagesKnown) next.packages = result.packages
        if (!next.flatpaksKnown && result.flatpaksKnown) next.flatpaks = result.flatpaks
        next.packagesKnown = next.packagesKnown || result.packagesKnown
        next.flatpaksKnown = next.flatpaksKnown || result.flatpaksKnown
        result = next
        nextState.result = next

        if (errors.length) say(errors.join(" · ") + (next.packagesCached || next.flatpaksCached ? " · showing cached data" : ""), true)
        else say("", false)

        if (realSession && next.checked) {
            const keys = Logic.itemKeys(next)
            if (checkProc.automatic && notifyEnabled && Logic.newKeys(keys, state.notified).length) notify(next)
            // A set seen on the page counts as notified too.
            nextState.notified = keys
        }
        saveState(nextState)
    }

    function saveState(nextState) {
        state = nextState
        stateFile.setText(Logic.serializeState(nextState))
    }

    // ---- actions --------------------------------------------------------------
    function openDiscover() {
        Quickshell.execDetached(Logic.discoverCommand())
        PanelService.close("settings")
    }

    function updateFlatpaks() {
        if (!actionsAllowed) {
            say(preview ? "Preview data: updates are disabled" : "Updating only runs in the buchhwin-shell session", true)
            return
        }
        if (flatpakProc.running) return
        flatpakProc.command = Logic.flatpakUpdateCommand(Paths.script("launch-kitty.sh"))
        flatpakProc.running = true
        say("Updating Flatpaks in a terminal window …", false)
    }

    // Check again once the terminal window is closed.
    Process {
        id: flatpakProc
        stderr: ErrorLog { label: "UpdatesService.flatpakProc" }
        onRunningChanged: if (!running) root.check(false)
    }

    // ---- notifications (notify-send to the shell's own server) ----------------
    function notify(next) {
        if (notifier.running) {
            dismissNotifications()
            notifier.running = false
        }
        notifier.command = ["notify-send", "--app-name=Updates", "--icon=system-software-update",
                            "--action=open=Open", "--", Logic.notifyTitle(next), Logic.notifyBody(next)]
        notifier.running = true
    }

    function dismissNotifications() {
        const list = NotificationService.history
        for (let j = list.length - 1; j >= 0; --j) {
            const item = list[j]
            if (item && item.appName === "Updates") item.dismiss()
        }
    }

    Process {
        id: notifier
        stderr: ErrorLog { label: "UpdatesService.notifier" }
        // notify-send prints the chosen action and exits when the notice closes.
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "open") PanelService.open("settings", { page: "updates" })
        }
    }

    // ---- preview ----------------------------------------------------------------
    function showPreview() {
        if (checkProc.running) return
        previewTime = Date.now() - 12 * 60000
        now = Date.now()
        preview = true
        message = ""
        if (sampleFile.loaded) result = Logic.parseReport(sampleFile.text())
    }

    function stopPreview() {
        preview = false
        message = ""
        result = state.result || Logic.emptyResult()
    }

    FileView {
        id: sampleFile
        path: Paths.shellFile("tests/fixtures/updates-report.txt")
        printErrors: false
        onLoaded: if (root.preview) root.result = Logic.parseReport(text())
    }

    // ---- check process and schedule ----------------------------------------------
    Process {
        id: checkProc
        stderr: ErrorLog { label: "UpdatesService.checkProc" }
        property bool automatic: false
        property bool refresh: false
        property real started: 0
        stdout: StdioCollector { onStreamFinished: root.finish(text) }
    }

    FileView {
        id: stateFile
        path: Paths.stateDir + "/updates.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.state = Logic.parseState(text())
            if (!root.preview && !root.checking && root.state.result) root.result = root.state.result
            root.stateLoaded = true
        }
        onLoadFailed: root.stateLoaded = true
    }

    function tick() {
        now = Date.now()
        if (realSession && stateLoaded && !checkProc.running && Logic.checkDue(now, state, checkHours)) check(true)
    }

    // First look a few minutes after login, then every 10 minutes (cheap: only
    // compares timestamps until the interval has passed).
    Timer {
        id: startDelay
        interval: 180000
        running: root.realSession && root.checkHours > 0
        onTriggered: root.tick()
    }
    Timer {
        interval: 600000
        repeat: true
        running: root.realSession && root.checkHours > 0 && !startDelay.running
        onTriggered: root.tick()
    }
    // Keeps "5 minutes ago" current, but only while something shows it
    // (Settings > Updates); it was the one timer that always ran.
    property int trackers: 0
    function track() { trackers += 1 }
    function untrack() { trackers = Math.max(0, trackers - 1) }
    Timer {
        interval: 60000
        repeat: true
        running: root.trackers > 0
        onTriggered: root.now = Date.now()
    }
}
