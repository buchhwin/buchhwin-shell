import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import qs.theme
import qs.services
import "../../services/lock/LockLogic.js" as Logic
import "../../services/LayoutLogic.js" as LayoutLogic

// Session lock, run as its own process (lock.qml, started by
// scripts/session-action.sh in a systemd unit): ext-session-lock through
// WlSessionLock with one surface per screen, one PAM conversation shared by
// all screens. If this process dies the compositor keeps the session locked
// and the unit restarts it (misc:allow_session_lock_restore).
Scope {
    id: root

    readonly property bool nested: Quickshell.env("BUCHHWIN_NESTED") === "1"
    // Nested test sessions can render the face in normal windows (screenshots).
    readonly property bool preview: nested && Quickshell.env("BUCHHWIN_LOCK_PREVIEW") === "1"
    readonly property string dir: Quickshell.env("BUCHHWIN_LOCK_DIR") || ""
    readonly property string user: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    readonly property bool showAvatar: SettingsService.value("lock.showAvatar")
    readonly property bool showMedia: SettingsService.value("lock.showMedia")
    readonly property bool showStatus: SettingsService.value("lock.showStatus")
    readonly property bool showPowerButtons: SettingsService.value("lock.showPowerButtons")

    // The arrangement above the login block, read straight from the layout
    // file. **Read, never written.** LayoutService is the shell's, and loading
    // it here would bring its migration, its `ensureScreens` and its one-shot
    // adoptions into a second process that can run at the same time as the
    // first - two writers on one file, for a surface that only ever displays.
    // A FileView and the pure sanitizer are the whole of what is needed.
    property var lockItems: LayoutLogic.lockItems(LayoutLogic.defaultLock())
    FileView {
        path: Paths.configDir + "/layout.json"
        watchChanges: true
        printErrors: false
        // `reload()` is FileView's own; a function of that name here would
        // shadow it, and the handler would read the text it already had.
        onFileChanged: reload()
        onLoaded: root.readLayout(text())
    }
    function readLayout(text) {
        if (!text || !text.trim().length) return
        try {
            const config = LayoutLogic.sanitize(JSON.parse(text))
            lockItems = LayoutLogic.lockItems(config.lock)
        } catch (error) {
            console.warn("buchhwin-shell: lock layout unreadable:", error)
        }
    }

    property string displayName: user
    readonly property string initial: Logic.initial(displayName)
    property string avatar: ""
    property string password: ""
    property bool busy: false
    property bool submitPending: false
    property string status: ""
    property bool statusIsError: false
    property int shakes: 0
    property bool capsLock: false
    property string layout: ""
    property bool unlocking: false
    // Typing moves the login block to the centre; it returns after a while
    // without input while the field is empty.
    property bool engaged: false
    // 0 → 1 while the lock screen appears, back to 0 when unlocking.
    property real fade: 0

    // Fingerprint (pam_fprintd in system-auth): the reader blocks the password
    // prompt until it matches or times out. `fingerprint` is the last event
    // (LockLogic.fingerprintEvent), `fingerprintStage` is true while the reader
    // waits. Submitting meanwhile aborts and checks the password alone.
    property string fingerprint: ""
    property bool fingerprintStage: false
    property int fingerprintMisses: 0
    property bool passwordOnly: false
    property bool passwordServiceInstalled: false
    readonly property string mainService: Logic.pamService(nested, Quickshell.env("BUCHHWIN_LOCK_PAM_SERVICE") || "")
    readonly property string passwordService: Logic.passwordService(mainService, passwordServiceInstalled)
    // The /etc/pam.d/buchhwin-lock-password check has finished (test services need none).
    property bool passwordServiceChecked: mainService !== "buchhwin-lock"

    // Fingerprint mode (lock.fingerprint): read before every conversation that
    // may use the reader. "auto" asks UPower whether the lid is closed (docked,
    // the sensor is out of reach); then the conversation is password-only.
    readonly property string fingerprintMode: SettingsService.value("lock.fingerprint")
    readonly property var lidOverride: Logic.lidOverride(nested, Quickshell.env("BUCHHWIN_LOCK_LID_CLOSED") || "")
    property bool lidClosed: false
    property bool lidChecked: false
    // The last start decision; false hides the fingerprint retry.
    property bool fingerprintAllowed: true
    // A start waits for the settings, the PAM file check and the lid state.
    property bool startQueued: false

    Behavior on fade {
        NumberAnimation {
            duration: root.unlocking ? Animations.lockExit : Animations.lockEnter
            easing.type: root.unlocking ? Easing.InCubic : Easing.OutCubic
        }
    }
    Component.onCompleted: fade = 1

    function engage() {
        engaged = true
        idleTimer.restart()
    }

    function type(text) {
        if (busy || unlocking) return
        engage()
        password += text
        if (!statusIsError && !fingerprintStage) {
            status = ""
            if (fingerprint === "ended") fingerprint = ""
        }
    }
    function erase(word) {
        if (busy || unlocking) return
        engage()
        password = word ? "" : Array.from(password).slice(0, -1).join("")
    }
    function clear() { if (!busy) password = "" }

    function submit() {
        if (busy || unlocking || !password.length) return
        if (pam.active && pam.responseRequired) {
            clearStatus()
            busy = true
            pam.respond(password)
        } else if (pam.active && fingerprintStage && passwordService !== mainService) {
            // The reader still blocks the prompt: leave it, check the password alone.
            pam.abort()
            clearStatus()
            submitPending = true
            busy = true
            startPam(true)
        } else {
            if (!fingerprintStage) clearStatus()
            // The conversation is not waiting for a password yet; answer when it asks.
            submitPending = true
            busy = true
            if (!pam.active) startPam()
        }
    }

    function clearStatus() {
        statusIsError = false
        status = ""
        fingerprint = ""
    }

    // passwordOnly: the service without pam_fprintd. Every other start (after
    // a failure) offers the fingerprint again when the mode allows it.
    function startPam(passwordOnly) {
        if (pam.active || unlocking) return
        if (passwordOnly === true) {
            beginPam(true)
            return
        }
        if (startQueued) return
        startQueued = true
        lidChecked = false
        startWatchdog.restart()
        if (fingerprintMode !== "auto") {
            lidChecked = true
        } else if (lidOverride !== null) {
            lidClosed = lidOverride
            lidChecked = true
        } else if (!lidProc.running) {
            lidProc.running = true
        }
        tryStart(false)
    }

    // force: the watchdog gives up waiting (lid unknown counts as open).
    function tryStart(force) {
        if (!startQueued) return
        const ready = SettingsService.loaded && passwordServiceChecked && lidChecked
        if (!ready && !force) return
        if (!lidChecked) lidClosed = false
        startQueued = false
        startWatchdog.stop()
        if (pam.active || unlocking) return
        fingerprintAllowed = Logic.fingerprintEnabled(fingerprintMode, lidClosed)
        beginPam(Logic.startPasswordOnly(fingerprintAllowed, mainService, passwordService))
    }

    function beginPam(passwordOnly) {
        if (pam.active || unlocking) return
        root.passwordOnly = passwordOnly === true
        fingerprintStage = false
        if (!pam.start()) {
            busy = false
            submitPending = false
            statusIsError = true
            status = "Authentication is not available"
            restartTimer.restart()
        }
    }

    // Clicking the fingerprint after a timeout starts the reader again.
    function retryFingerprint() {
        if (busy || unlocking || fingerprintStage || passwordOnly) return
        if (pam.active) pam.abort()
        clearStatus()
        startPam(false)
    }

    function keyActivity() { if (!keyboardProc.running) keyboardProc.running = true }

    function power(action) {
        if (["suspend", "reboot", "poweroff"].indexOf(action) >= 0)
            Quickshell.execDetached([Paths.script("session-action.sh"), action])
    }

    function unlock() {
        if (unlocking) return
        unlocking = true
        password = ""
        fade = 0
        unlockTimer.restart()
    }

    function finish() {
        if (dir.length) Quickshell.execDetached(["sh", "-c", "rm -f -- \"$1\"/*.png \"$1\"/locked", "sh", dir])
        if (!preview) lock.locked = false
        quitTimer.restart()
    }

    PamContext {
        id: pam
        config: root.passwordOnly ? root.passwordService : root.mainService
        configDirectory: Logic.systemService(config) ? "/etc/pam.d" : Quickshell.shellPath("tests/fixtures/pam")
        user: root.user

        onPamMessage: {
            const event = Logic.fingerprintEvent(message, messageIsError, responseRequired, root.fingerprintStage)
            if (responseRequired) {
                // The reader gave up (or was not used): the password is asked now.
                root.fingerprintStage = false
                if (root.submitPending) {
                    root.submitPending = false
                    respond(root.password)
                }
            } else if (event.length && !root.passwordOnly) {
                root.fingerprintStage = event !== "ended"
                root.fingerprint = event
                if (event === "mismatch") root.fingerprintMisses += 1
                root.status = Logic.fingerprintText(event, message)
                root.statusIsError = event === "mismatch"
            } else if (message.length) {
                root.status = message
                root.statusIsError = messageIsError
            }
        }
        onCompleted: result => {
            root.busy = false
            root.submitPending = false
            root.fingerprintStage = false
            root.fingerprint = ""
            const next = Logic.afterPam(result, { Success: PamResult.Success, Failed: PamResult.Failed, Error: PamResult.Error, MaxTries: PamResult.MaxTries })
            if (next.shake) root.shakes += 1
            if (next.action === "unlock") {
                root.unlock()
            } else if (next.action === "retry") {
                root.password = ""
                root.status = ""
                restartTimer.restart()
            } else {
                root.password = ""
                root.statusIsError = true
                root.status = next.text
                restartTimer.restart()
            }
        }
        onError: error => {
            root.busy = false
            root.submitPending = false
            root.fingerprintStage = false
            root.fingerprint = ""
            // No words for a rejected attempt: the shake is the answer.
            root.password = ""
            root.status = ""
            root.statusIsError = false
            root.shakes += 1
            restartTimer.restart()
        }
    }

    Timer { id: restartTimer; interval: 1000; onTriggered: root.startPam() }
    // busctl has its own 1 s timeout; never wait longer than this for a start.
    Timer { id: startWatchdog; interval: 1500; onTriggered: root.tryStart(true) }
    Connections {
        target: SettingsService
        function onLoadedChanged() { root.tryStart(false) }
    }
    Timer {
        id: idleTimer
        interval: 12000
        onTriggered: {
            if (root.password.length || root.busy) restart()
            else root.engaged = false
        }
    }
    Timer { id: unlockTimer; interval: Animations.lockExit + 40; onTriggered: root.finish() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    WlSessionLock {
        id: lock
        locked: !root.preview
        onSecureChanged: if (secure) marker.setText("1\n")

        WlSessionLockSurface {
            id: surface
            color: Colors.lockBase
            LockFace {
                anchors.fill: parent
                lockState: root
                screenName: surface.screen ? surface.screen.name : ""
            }
        }
    }

    Variants {
        model: root.preview ? Quickshell.screens : []
        PanelWindow {
            id: previewWindow
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Colors.lockBase
            WlrLayershell.namespace: "buchhwin-lock-preview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            LockFace {
                anchors.fill: parent
                lockState: root
                screenName: previewWindow.modelData.name
            }
        }
    }

    FileView {
        id: marker
        path: root.dir.length ? root.dir + "/locked" : ""
        printErrors: false
    }

    // Preview windows are "locked" as soon as they exist.
    Timer { running: root.preview; interval: 200; onTriggered: marker.setText("1\n") }

    Process {
        running: root.user.length > 0
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector { onStreamFinished: root.displayName = Logic.displayName(text, root.user) }
    }

    Process {
        running: root.showAvatar
        command: ["python3", Paths.script("fastfetch-image.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.avatar = JSON.parse(text).source || "" } catch (error) { root.avatar = "" }
            }
        }
    }

    Process {
        id: keyboardProc
        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = Logic.keyboardState(text)
                root.capsLock = state.capsLock
                root.layout = state.layout
            }
        }
    }

    // The password-only PAM service is optional (install/system-install.sh).
    Process {
        running: root.mainService === "buchhwin-lock"
        command: ["test", "-r", "/etc/pam.d/buchhwin-lock-password"]
        onExited: code => {
            root.passwordServiceInstalled = code === 0
            root.passwordServiceChecked = true
            root.tryStart(false)
        }
    }

    // Lid state from UPower (read-only), before each start in "auto" mode.
    Process {
        id: lidProc
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        command: ["busctl", "--system", "--timeout=1", "get-property", "org.freedesktop.UPower",
                  "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsClosed"]
        function finish() {
            if (!outputDone || exitCode < 0) return
            root.lidClosed = Logic.parseLidClosed(output, exitCode)
            root.lidChecked = true
            root.tryStart(false)
        }
        stdout: StdioCollector { onStreamFinished: { lidProc.output = text; lidProc.outputDone = true; lidProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    // Start the conversation right away so the first Enter is answered.
    Timer { running: true; interval: 50; onTriggered: root.startPam() }
}
