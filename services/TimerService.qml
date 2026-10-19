pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "timer/TimerLogic.js" as Logic
import "notifications/NotificationLogic.js" as NotificationLogic
import "lock/LockLogic.js" as LockLogic

// The countdowns: a timer and a Focus session at most, one of each kind
// (TimerLogic's runs). The one to end first is shown in the notch strip's
// timer chip and the bar's timer item while it runs, and its end is
// announced by a notification, seen and heard through Do Not Disturb.
// Started from the launcher ("Timer: 5 minutes", "Focus: 25 minutes") or over
// IPC (`buchhwin timer start 5m`, `buchhwin focus start 25m`). The clock ticks
// once a second, and only while something runs; the runs are kept in
// timer.json, so a shell restart keeps them.
Singleton {
    id: root

    property var runs: []
    readonly property var shown: Logic.shown(runs)
    property real now: Date.now()
    readonly property bool running: shown !== null
    // "timer" or "focus": what the shown countdown is for; "" with none.
    readonly property string kind: shown ? shown.kind : ""
    readonly property real endsAt: shown ? shown.endsAt : 0
    readonly property int total: shown ? shown.total : 0
    readonly property real remaining: running ? Math.max(0, endsAt - now) : 0
    readonly property string remainingText: running ? Logic.remainingText(remaining) : ""
    readonly property real fraction: running ? Logic.fraction(remaining, total) : 0
    readonly property bool realSession: Quickshell.env("BUCHHWIN_NESTED") !== "1"
    // The lock screen's process never keeps, ends or announces a countdown
    // (testing.md pitfall 86): nothing there reaches this service today, and
    // a second writer of timer.json must never come of it.
    readonly property bool sessionSide: !LockLogic.lockProcess(Quickshell.shellId)

    // A run ran out (AdaptiveService ends a Focus session on it), or was
    // stopped by hand - the chip, `timer stop`. `cancel` says nothing: that
    // is the caller ending what it started.
    signal ended(string kind, int seconds)
    signal stopped(string kind)

    function has(kind) { return Logic.find(runs, kind) !== null }
    // Each run's kind and seconds left, for `timer get`.
    function describe() { return Logic.describe(runs, Date.now()) }
    // When the run of `kind` ends (ms since the epoch), 0 when none runs.
    function endOf(kind) {
        const item = Logic.find(runs, kind)
        return item ? item.endsAt : 0
    }

    // A countdown of `seconds`, of `kind` ("timer" when left out); it
    // replaces a running one of the same kind, never the other.
    function start(seconds, kind) {
        const s = Math.round(Number(seconds) || 0)
        if (s <= 0 || s > Logic.MAX_SECONDS) return false
        now = Date.now()
        runs = Logic.withRun(runs, Logic.run(kind, now + s * 1000, s))
        save()
        return true
    }
    // A typed duration ("5m", "1:30", "25"), as the launcher and IPC take it.
    function startText(text, kind) { return start(Logic.parseDuration(text), kind) }
    // Stop the countdown that is shown, or the one of `kind`.
    function stop(kind) {
        const which = kind === undefined || kind === null || kind === "" ? root.kind : Logic.kindOf(kind)
        if (!which.length || !has(which)) return false
        runs = Logic.withoutRun(runs, which)
        save()
        stopped(which)
        return true
    }
    // What "Timer: stop" and `timer stop` mean: the timer, and the Focus
    // session only when no timer runs - not a session that is shown because
    // it ends first. The chip stops what it shows (`stop`).
    function stopTimer() { return stop(has("timer") ? "timer" : "") }
    function cancel(kind) {
        const next = Logic.withoutRun(runs, kind)
        if (next === runs) return
        runs = next
        save()
    }

    function tick() {
        now = Date.now()
        for (const item of Logic.due(runs, now)) finish(item)
    }

    function finish(item) {
        runs = Logic.withoutRun(runs, item.kind)
        save()
        // First what the end does - a Focus session's turns Focus off, and
        // with it the Do Not Disturb it owned - and then the word, into the
        // state that leaves.
        ended(item.kind, item.total)
        announce(item)
    }

    // The ends that wait for NotificationService's state (Logic.announceStep),
    // announced a turn after the read: `stateLoaded` turns true before a Do
    // Not Disturb set during the read is laid over it. NotificationService is
    // asked only while one waits.
    property var pendingEnds: []
    Connections {
        target: root.pendingEnds.length ? NotificationService : null
        function onStateLoadedChanged() { Qt.callLater(root.announcePending) }
    }
    function announcePending() {
        const items = pendingEnds
        pendingEnds = []
        for (const item of items) announce(item)
    }

    function announce(item) {
        const step = Logic.announceStep(sessionSide, sessionSide && NotificationService.stateLoaded)
        if (step === "wait") pendingEnds = pendingEnds.concat([item])
        if (step !== "now") return
        const texts = Logic.endTexts(item.kind, item.total)
        const rule = NotificationLogic.ruleFor(NotificationService.appRules, { appName: Logic.APP_NAME, hints: {} })
        const state = { suppressed: NotificationService.suppressed, dndMode: NotificationService.dndMode,
                        dndBy: NotificationService.dndBy }
        const plan = Logic.endActions({
            real: realSession,
            popsUp: NotificationLogic.shouldPopup(state, true, rule),
            rule: rule,
            sound: SettingsService.value("timer.sound") === true,
            canNotice: typeof NotificationService.postNotice === "function"
        })
        if (plan.send) Quickshell.execDetached(Logic.notifyCommand(texts, plan.sound))
        else console.info("buchhwin-shell: timer: notification (nested, not sent):", texts.body)
        // Urgent, so it stays until it is closed, and forced through every
        // Do Not Disturb: the user started this one.
        if (plan.notice) NotificationService.postNotice({ summary: texts.summary, body: texts.body, icon: "alarm-symbolic",
                                                          appName: Logic.APP_NAME, urgent: true, force: true })
        if (plan.sound) Quickshell.execDetached(Logic.soundCommand(Logic.ALARM_SOUND))
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.loaded && root.runs.length > 0
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    // ---- kept across a restart ---------------------------------------------------
    // Read once at the start (a file of a few bytes, or none) and written
    // when a run starts, stops or ends; nothing watches it, only this process
    // writes it.
    property bool loaded: false
    function restore(text) {
        if (loaded) return
        const boot = bootFile.text().trim()
        let next = Logic.restored(text, boot, Date.now())
        // A run started before the file was read (IPC right at the start)
        // wins over the stored one of its kind.
        for (const item of runs) next = Logic.withRun(next, item)
        const early = runs.length > 0
        runs = next
        loaded = true
        if (early) save()
    }
    // Written a turn later, never from inside the read's own handler, and
    // once for several changes in one turn (testing.md pitfall 3).
    function save() {
        if (sessionSide && loaded) saveTimer.restart()
    }
    Timer {
        id: saveTimer
        interval: 0
        onTriggered: stateFile.setText(Logic.stateText(root.runs, bootFile.text().trim()))
    }

    // The kernel's boot marker (37 bytes, read blocking as NotificationService
    // does): runs of another boot are gone.
    FileView {
        id: bootFile
        path: "/proc/sys/kernel/random/boot_id"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: stateFile
        path: Paths.stateDir + "/timer.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.restore(text())
        onLoadFailed: root.restore("")
    }
}
