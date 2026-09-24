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
//
// And the shell itself, through scripts/shell-update.sh: the checkout the
// session runs from against the git remote it follows. A clone from GitHub
// follows origin/main and is fast-forwarded from here, on request or by the
// automatic check when `updates.shellAuto` says so; the development machine's
// stable worktree follows nothing and the page says so. The look at start and
// in nested sessions is offline - local git only.
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
    property bool shellExpanded: false

    // ---- the shell itself --------------------------------------------------------
    property var shell: Logic.emptyShell()
    readonly property bool shellChecking: shellProc.running
    readonly property bool shellUpdating: shellUpdateProc.running
    readonly property bool shellAuto: SettingsService.value("updates.shellAuto") === true
    readonly property string shellSummary: Logic.shellSummary(shell)
    readonly property string shellSubtitle: Logic.shellSubtitle(shell)
    readonly property bool shellUpdatable: Logic.shellUpdatable(shell)

    // offline: local git only, no fetch - what the start and a nested session
    // may do. automatic: the timer's check, which may install (shellAuto).
    function checkShell(offline, automatic) {
        if (shellProc.running || preview) return
        shellProc.automatic = !!automatic
        shellProc.command = Logic.shellCheckCommand(Paths.script("shell-update.sh"), offline || !realSession)
        shellProc.running = true
    }

    function finishShell(text) {
        shell = Logic.parseShellReport(text)
        saveState(Object.assign({}, state, { shell: shell }))
        if (shellProc.automatic && shellAuto && realSession && shellUpdatable) updateShell()
    }

    function updateShell() {
        if (!actionsAllowed) {
            say(preview ? "Preview data: updates are disabled" : "Updating only runs in the buchhwin-shell session", true)
            return
        }
        if (shellUpdateProc.running || !shellUpdatable) return
        shellUpdateProc.command = Logic.shellUpdateCommand(Paths.script("shell-update.sh"))
        shellUpdateProc.running = true
        say("Updating the shell - it restarts in a moment …", false)
    }

    Process {
        id: shellProc
        property bool automatic: false
        stderr: ErrorLog { label: "UpdatesService.shellProc" }
        stdout: StdioCollector { onStreamFinished: root.finishShell(text) }
    }
    // Only the hand-over to systemd can fail here; the update itself reports
    // through a notification once the shell is back.
    Process {
        id: shellUpdateProc
        stderr: ErrorLog { label: "UpdatesService.shellUpdateProc" }
        onExited: (code, status) => { if (code !== 0) root.say("The shell update could not be started (exit " + code + ")", true) }
    }

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
        checkShell(false, automatic)
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
            if (root.state.shell) root.shell = root.state.shell
            root.stateLoaded = true
            // What the last check said may be a shell restart old - the one an
            // update ends in. Local git answers in a moment and without the
            // network, so the page opens on the truth.
            root.checkShell(true, false)
        }
        onLoadFailed: { root.stateLoaded = true; root.checkShell(true, false) }
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
