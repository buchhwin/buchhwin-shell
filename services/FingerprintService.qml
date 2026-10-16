pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "fingerprint/FingerprintLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// Fingerprint reader for Settings > Lock Screen, through the fprintd tools.
// Reading (fprintd-list, reader properties over busctl) runs while a page
// tracks the service. Enrolling and deleting change the user's biometric data:
// they only run on an explicit click in the real session (fprintd may show a
// polkit password dialog), never in nested sessions or the preview.
// The preview replays tests/fixtures/fingerprint-enroll*.txt for screenshots.
// The unlock mode (lock.fingerprint) is read by the lock screen before every
// PAM conversation; this service sets it and reads the lid state for display.
Singleton {
    id: root

    readonly property bool realSession: Quickshell.env("BUCHHWIN_NESTED") !== "1"
    readonly property string user: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    property int trackers: 0
    property bool loading: false
    property var reader: Logic.parseList(undefined, 0)
    property int stages: 0
    property string scanType: ""
    // Synthetic reader and enrollment output; nothing reaches fprintd.
    property bool preview: false

    // Enrollment state (FingerprintLogic.enrollStart/enrollLine), null when idle.
    property var enrollment: null
    readonly property bool enrolling: enrollment !== null && !enrollment.finished
    property bool cancelling: false
    property string deleting: ""
    property string message: ""
    property bool messageError: false

    readonly property bool known: reader.known
    readonly property bool available: reader.available
    readonly property var fingers: reader.fingers
    readonly property var fingerOptions: Logic.fingerOptions(fingers)
    // A reader with enrolled fingers (control center tile).
    readonly property bool ready: available && fingers.length > 0

    // Unlock mode: auto | on | off (LockLogic.fingerprintEnabled).
    readonly property string mode: SettingsService.value("lock.fingerprint")
    property bool lidClosed: false
    readonly property bool enabledNow: LockLogic.fingerprintEnabled(mode, lidClosed)
    readonly property string modeLabel: Logic.modeLabel(mode, lidClosed)
    readonly property string modeState: Logic.modeState(mode, lidClosed)
    property real refreshedAt: 0

    function setMode(value) {
        if (LockLogic.FINGERPRINT_MODES.indexOf(value) < 0) return false
        return SettingsService.set("lock.fingerprint", value)
    }

    // Whether PAM offers the reader to the *whole system* (authselect's
    // `with-fingerprint` on Fedora, pam-config's pam_fprintd line in
    // common-auth on openSUSE, a hand-made line in system-auth on Arch): null
    // while unknown. With the shell's own mode off but this true, the login
    // screen, sudo and polkit still ask for a finger, which makes the off
    // button look broken - the button works, it just governs the lock
    // screen.
    property var systemEnabled: null
    readonly property bool systemOnly: systemEnabled === true && mode === "off"
    // Whether the PAM stack the lock goes through offers it: the same answer
    // on Fedora and openSUSE, where the lock includes the system stack; on
    // Arch the lock's own /etc/pam.d/buchhwin-lock counts too, which is where
    // the reader belongs there (FingerprintLogic, "Arch").
    property var lockEnabled: null

    // Waits for DistroService: the question is asked differently per
    // distribution, and asking Fedora's tool on openSUSE only fails. Read
    // again with every refresh (the page opening): the line is added or
    // commented out with sudo outside the shell, and an answer kept from the
    // shell's start would go on offering the command just run.
    readonly property var systemCommand: Logic.systemFingerprintCommand(DistroService.family)
    onSystemCommandChanged: readSystemPam()
    Component.onCompleted: readSystemPam()
    function readSystemPam() {
        if (!realSession || preview || systemCommand.length === 0 || systemProc.running) return
        systemProc.command = systemCommand
        systemProc.running = true
    }
    Process {
        id: systemProc
        stderr: ErrorLog { label: "FingerprintService.systemPam" }
        // The output may arrive before or after the exit; parse once both are in.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function finish() {
            if (!outputDone || exitCode < 0) return
            root.systemEnabled = Logic.parseSystemFingerprint(DistroService.family, output, exitCode)
            root.lockEnabled = Logic.parseLockFingerprint(DistroService.family, output, exitCode)
        }
        stdout: StdioCollector { onStreamFinished: { systemProc.output = text; systemProc.outputDone = true; systemProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    // Lid state from UPower (read-only); the preview keeps its synthetic value.
    function readLid() {
        if (preview || lidProc.running) return
        lidProc.running = true
    }

    // Control center: reader state at most every few minutes, lid state now.
    function peek() {
        readLid()
        if (preview) return
        if (!known || Date.now() - refreshedAt > 300000) refresh()
    }

    // IPC `fingerprint previewLid BOOL` (preview only): the closed-lid status.
    function setPreviewLid(closed) {
        if (preview) lidClosed = closed
    }

    readonly property bool actionsAllowed: (realSession || preview) && available && !enrolling && deleting === ""
    readonly property string blockedReason: realSession || preview ? ""
        : "Enrolling and deleting fingerprints only run in the buchhwin-shell session"

    function track() { trackers += 1 }
    function untrack() { trackers = Math.max(0, trackers - 1) }
    onTrackersChanged: if (trackers > 0 && !preview) { refresh(); readLid() }

    function fingerLabel(name) { return Logic.fingerLabel(name) }
    function defaultFinger() { return Logic.defaultFinger(fingers) }
    function progress() { return Logic.progress(enrollment) }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    // A request while fprintd-list runs is kept for one more run after it:
    // the refresh at the end of an enrollment would otherwise be dropped
    // behind a tracker's, and the new finger missing until the next one.
    property bool refreshQueued: false
    function refresh() {
        if (preview) return
        readSystemPam()
        const argv = Logic.listCommand(user)
        if (!argv) return
        if (listProc.running) { refreshQueued = true; return }
        loading = true
        listProc.command = argv
        listProc.running = true
    }

    function enroll(finger) {
        if (!actionsAllowed || !Logic.validFinger(finger)) {
            if (blockedReason.length) say(blockedReason, true)
            return
        }
        say("", false)
        cancelling = false
        enrollment = Logic.enrollStart(finger, stages, scanType)
        if (preview) {
            replay.lines = (replay.source === "denied" ? deniedSample : enrollSample).text().split("\n")
            replay.index = 0
            replay.restart()
            return
        }
        enrollProc.command = Logic.enrollCommand(finger)
        enrollProc.running = true
        stepAside("enroll")
    }

    // ---- the password dialog ----------------------------------------------
    // fprintd asks polkit before every enrollment and deletion - the
    // authorization it keeps belongs to the process that asked, and each run
    // of a tool is a new one - and the agent's dialog is an ordinary window.
    // Settings is a panel above every window and holds the keyboard, so the
    // dialog opened under it, unseen, while the card said "scanning"
    // (testing.md pitfall 6). Settings steps aside when such a run starts and
    // comes back on its page once the question is out of the way: the agent's
    // window came and went, the reader answered or the run ended, or no
    // dialog came at all within a moment of the finger being announced.
    // Never over a panel opened in the meantime.
    property string asideFor: ""
    property bool passwordAsked: false
    // Read only while stepping aside, so nothing follows the focus otherwise.
    readonly property string activeAppId: asideFor.length && HyprlandService.activeToplevel
        ? (HyprlandService.activeToplevel.appId || "") : ""
    onActiveAppIdChanged: {
        if (!asideFor.length) return
        if (Logic.isPasswordAgent(activeAppId)) { passwordAsked = true; asideTimer.stop() }
        else if (passwordAsked) comeBack()
    }
    function stepAside(kind) {
        if (preview || !PanelService.isOpen("settings")) return
        asideFor = kind
        passwordAsked = false
        PanelService.close("settings")
        // A deletion is over in a moment once allowed, so it simply comes
        // back with its answer; an enrollment waits for the finger instead
        // and gets the grace below - a long one while fprintd starts, a short
        // one from the moment the tool announces the finger.
        if (kind === "enroll") { asideTimer.interval = asideTimer.startGrace; asideTimer.restart() }
    }
    function comeBack() {
        if (!asideFor.length) return
        asideFor = ""
        passwordAsked = false
        asideTimer.stop()
        if (!PanelService.active.length) PanelService.open("settings", { page: "lockScreen" })
    }
    // The enrollment as it advances: the announced finger is when polkit may
    // ask, and the reader's first word is past the question.
    function enrollAdvanced() {
        if (asideFor !== "enroll") return
        const phase = Logic.authPhase(enrollment)
        if (phase === "answered") comeBack()
        else if (phase === "asking" && !passwordAsked && !announcedOnce) {
            announcedOnce = true
            asideTimer.interval = asideTimer.askGrace
            asideTimer.restart()
        }
    }
    property bool announcedOnce: false
    onAsideForChanged: if (!asideFor.length) announcedOnce = false
    // Long enough for fprintd to start (it is started on demand) and for
    // polkit to put its dialog up; the timer only brings Settings back when
    // no dialog came.
    Timer {
        id: asideTimer
        readonly property int startGrace: 8000
        readonly property int askGrace: 3000
        interval: startGrace
        onTriggered: if (!root.passwordAsked) root.comeBack()
    }

    // Stops the scan; fprintd releases the reader when the tool exits.
    function cancel() {
        if (!enrolling) return
        cancelling = true
        if (preview) {
            replay.stop()
            enrollment = Logic.enrollExited(enrollment, 0, true)
        } else if (enrollProc.running) {
            enrollProc.signal(2)
            killTimer.restart()
        }
    }

    // Clears a finished enrollment (Done / Close).
    function dismiss() {
        if (!enrolling) enrollment = null
    }

    function remove(finger) {
        if (!actionsAllowed || !Logic.validFinger(finger) || fingers.indexOf(finger) < 0) {
            if (blockedReason.length) say(blockedReason, true)
            return
        }
        if (preview) {
            reader = Object.assign({}, reader, { fingers: fingers.filter(item => item !== finger) })
            say(Logic.fingerLabel(finger) + " deleted (preview)", false)
            return
        }
        const argv = Logic.deleteCommand(user, finger)
        if (!argv) return
        deleting = finger
        say("", false)
        deleteProc.command = argv
        deleteProc.running = true
        stepAside("delete")
    }

    // IPC `fingerprint preview` / `previewDenied`: a synthetic reader with two
    // fingers and an enrollment that replays the fixture.
    function startPreview(kind) {
        if (enrollProc.running) return
        preview = true
        replay.source = kind === "denied" ? "denied" : "enroll"
        reader = Logic.parseList(listSample.text(), 0)
        stages = 8
        scanType = reader.scanType
        say("", false)
        enrollment = null
        enroll(Logic.defaultFinger(fingers))
    }

    function stopPreview() {
        if (!preview) return
        replay.stop()
        preview = false
        enrollment = null
        reader = Logic.parseList(undefined, 0)
        say("", false)
        lidClosed = false
        readLid()
        if (trackers > 0) refresh()
    }

    Process {
        id: lidProc
        stderr: ErrorLog { label: "FingerprintService.lidProc" }
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        command: ["busctl", "--system", "--timeout=1", "get-property", "org.freedesktop.UPower",
                  "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsClosed"]
        function finish() {
            if (!outputDone || exitCode < 0 || root.preview) return
            root.lidClosed = LockLogic.parseLidClosed(output, exitCode)
        }
        stdout: StdioCollector { onStreamFinished: { lidProc.output = text; lidProc.outputDone = true; lidProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    Process {
        id: listProc
        stderr: ErrorLog { label: "FingerprintService.listProc" }
        // The output may arrive before or after the exit; parse once both are in.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function finish() {
            if (!outputDone || exitCode < 0) return
            root.loading = false
            if (root.refreshQueued) {
                root.refreshQueued = false
                Qt.callLater(root.refresh)
            }
            if (root.preview) return
            root.reader = Logic.parseList(output, exitCode)
            root.refreshedAt = Date.now()
            if (root.reader.devicePath.length && !propsProc.running) {
                propsProc.command = ["busctl", "--system", "get-property", "net.reactivated.Fprint", root.reader.devicePath,
                                     "net.reactivated.Fprint.Device", "num-enroll-stages", "scan-type"]
                propsProc.running = true
            }
        }
        stdout: StdioCollector { onStreamFinished: { listProc.output = text; listProc.outputDone = true; listProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    Process {
        id: propsProc
        stderr: ErrorLog { label: "FingerprintService.propsProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.preview) return
                const props = Logic.parseProperties(text)
                root.stages = props.stages
                root.scanType = props.scanType || root.reader.scanType
            }
        }
    }

    Process {
        id: enrollProc
        stdout: SplitParser { onRead: data => { root.enrollment = Logic.enrollLine(root.enrollment, data); root.enrollAdvanced() } }
        stderr: SplitParser { onRead: data => { root.enrollment = Logic.enrollLine(root.enrollment, data); root.enrollAdvanced() } }
        onExited: code => {
            killTimer.stop()
            root.enrollment = Logic.enrollExited(root.enrollment, code, root.cancelling)
            root.cancelling = false
            root.enrollAdvanced()
            root.refresh()
        }
    }

    // fprintd-enroll stops on SIGINT; terminate it if it does not.
    Timer { id: killTimer; interval: 3000; onTriggered: if (enrollProc.running) enrollProc.signal(15) }

    Process {
        id: deleteProc
        property string output: ""
        property int exitCode: 0
        stdout: StdioCollector { onStreamFinished: deleteProc.output += text }
        stderr: StdioCollector { onStreamFinished: deleteProc.output += text }
        onStarted: output = ""
        onExited: code => { exitCode = code; doneTimer.restart() }
    }
    // Collectors finish just after the exit.
    Timer {
        id: doneTimer
        interval: 100
        onTriggered: {
            const result = Logic.parseDelete(deleteProc.output, deleteProc.exitCode, root.deleting)
            root.say(result.message, !result.ok)
            root.deleting = ""
            if (root.asideFor === "delete") root.comeBack()
            root.refresh()
        }
    }

    Timer {
        id: replay
        property string source: "enroll"
        property var lines: []
        property int index: 0
        interval: 900
        repeat: true
        onTriggered: {
            if (!root.enrolling || index >= lines.length) {
                stop()
                if (root.enrolling) root.enrollment = Logic.enrollExited(root.enrollment, 1, false)
                return
            }
            root.enrollment = Logic.enrollLine(root.enrollment, lines[index])
            index += 1
            // The synthetic reader lists the new finger like fprintd-list would.
            if (root.enrollment.success && root.fingers.indexOf(root.enrollment.finger) < 0)
                root.reader = Object.assign({}, root.reader, { fingers: root.fingers.concat([root.enrollment.finger]) })
        }
    }

    FileView { id: enrollSample; path: root.preview ? Paths.shellFile("tests/fixtures/fingerprint-enroll.txt") : ""; blockLoading: true; printErrors: false }
    FileView { id: deniedSample; path: root.preview ? Paths.shellFile("tests/fixtures/fingerprint-enroll-denied.txt") : ""; blockLoading: true; printErrors: false }
    FileView { id: listSample; path: root.preview ? Paths.shellFile("tests/fixtures/fingerprint-list.txt") : ""; blockLoading: true; printErrors: false }
}
