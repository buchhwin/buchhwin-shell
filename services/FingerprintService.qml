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
    // `with-fingerprint`): null while unknown. With the shell's own mode off
    // but this true, the login screen, sudo and polkit still ask for a finger,
    // which is exactly the "the off button does not work" the user reported -
    // the button works, it just governs the lock screen.
    property var systemEnabled: null
    readonly property bool systemOnly: systemEnabled === true && mode === "off"

    Process {
        stderr: ErrorLog { label: "FingerprintService.authselect" }
        running: root.realSession && !root.preview
        command: ["authselect", "current"]
        stdout: StdioCollector {
            onStreamFinished: root.systemEnabled = Logic.systemFingerprint(text, 0)
        }
        onExited: code => { if (code !== 0) root.systemEnabled = null }
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

    function refresh() {
        if (preview) return
        const argv = Logic.listCommand(user)
        if (!argv || listProc.running) return
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
        stdout: SplitParser { onRead: data => root.enrollment = Logic.enrollLine(root.enrollment, data) }
        stderr: SplitParser { onRead: data => root.enrollment = Logic.enrollLine(root.enrollment, data) }
        onExited: code => {
            killTimer.stop()
            root.enrollment = Logic.enrollExited(root.enrollment, code, root.cancelling)
            root.cancelling = false
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
