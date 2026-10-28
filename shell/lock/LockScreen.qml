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
// WlSessionLock with one surface per screen, one PAM conversation and one
// password shared by all screens; only the screen whose surface has the
// keyboard draws what is typed (`inputScreen`). If this process dies the
// compositor keeps the session locked and the unit restarts it
// (misc:allow_session_lock_restore).
Scope {
    id: root

    // What the environment asks for. Properties rather than constants, so
    // that tests/qml/LockScreenTest.qml can drive this screen with the PAM
    // fixtures offscreen; lock.qml sets none of them.
    property bool nested: Quickshell.env("BUCHHWIN_NESTED") === "1"
    property string dir: Quickshell.env("BUCHHWIN_LOCK_DIR") || ""
    property string requestedService: Quickshell.env("BUCHHWIN_LOCK_PAM_SERVICE") || ""
    property string requestedKeyService: Quickshell.env("BUCHHWIN_LOCK_KEY_SERVICE") || ""
    property string lidHook: Quickshell.env("BUCHHWIN_LOCK_LID_CLOSED") || ""
    property bool previewWanted: Quickshell.env("BUCHHWIN_LOCK_PREVIEW") === "1"
    // false: no session lock, for the test - a test locks nothing.
    property bool surfaces: true
    // false: the process goes on after an unlock, for a test that unlocks
    // several screens in turn (LockKeyTest).
    property bool quitOnUnlock: true
    // The fixtures, the lid override and the preview need a nested session
    // the lock directory confirms (LockLogic.testHooksAllowed).
    readonly property bool testHooks: Logic.testHooksAllowed(nested, dir)
    // Nested test sessions can render the face in normal windows (screenshots).
    readonly property bool preview: testHooks && previewWanted
    readonly property string user: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    readonly property bool showAvatar: SettingsService.value("lock.showAvatar")
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
            // Only the lock section, which sits at the top level of the file:
            // sanitizing all of it - every profile, mode and stored state -
            // to take that one part cost a few milliseconds per read, for the
            // same items (both give the default to a file without one).
            const parsed = JSON.parse(text)
            const items = LayoutLogic.lockItems(LayoutLogic.sanitizeLock(parsed && typeof parsed === "object" ? parsed.lock : null))
            // The shell writes the file while the screen is locked (a mode
            // switch on docking), mostly without touching this section, and
            // a new array rebuilt every block on every screen, the rolling
            // clock included: a Repeater over a plain array starts over on
            // each assignment (testing.md pitfall 75).
            if (JSON.stringify(items) === JSON.stringify(lockItems)) return
            lockItems = items
        } catch (error) {
            console.warn("buchhwin-shell: lock layout unreadable:", error)
        }
    }

    property string displayName: user
    readonly property string initial: Logic.initial(displayName)
    property string avatar: ""
    property string password: ""
    // The screen that draws the password (LockLogic.showsInput): the last one
    // whose surface gained the keyboard or received a key, reported by each
    // LockFace. "" until the first report.
    property string inputScreen: ""
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

    // Fingerprint (pam_fprintd in the lock's PAM stack: system-auth on Fedora,
    // /etc/pam.d/buchhwin-lock itself on Arch): the reader blocks the password
    // prompt until it matches or times out. `fingerprint` is the last event
    // (LockLogic.fingerprintEvent), `fingerprintStage` is true while the reader
    // waits. Submitting meanwhile aborts and checks the password alone.
    property string fingerprint: ""
    property bool fingerprintStage: false
    // What PAM said during the current attempt, for Logic.lockoutNotice.
    property var pamMessages: []
    property int fingerprintMisses: 0
    property bool passwordOnly: false
    property bool passwordServiceInstalled: false
    readonly property string mainService: Logic.pamService(testHooks, requestedService)
    readonly property string passwordService: Logic.passwordService(mainService, passwordServiceInstalled)
    // The /etc/pam.d/buchhwin-lock-password check has finished (test services need none).
    property bool passwordServiceChecked: mainService !== "buchhwin-lock"

    // Fingerprint mode (lock.fingerprint): read before every conversation that
    // may use the reader. "auto" asks UPower whether the lid is closed (docked,
    // the sensor is out of reach); then the conversation is password-only.
    readonly property string fingerprintMode: SettingsService.value("lock.fingerprint")
    readonly property var lidOverride: Logic.lidOverride(testHooks, lidHook)
    property bool lidClosed: false
    property bool lidChecked: false
    // The last start decision; false hides the fingerprint retry.
    property bool fingerprintAllowed: true

    // Security key (pam_u2f in /etc/pam.d/buchhwin-lock-key, set up by
    // scripts/security-key.py; lock.securityKey): asked first, in a
    // conversation of its own, once per lock - at the first start, and again
    // only on a click (useKey). A key that is not plugged in ends it at once
    // and without a word; every end that does not unlock goes on with the
    // usual start, so the fingerprint (as lock.fingerprint and the lid say)
    // and the password are untouched by it. `keyStage` while it runs,
    // `keyPin` while it waits for the PIN, `keyTouch` while the key waits for
    // a finger on it. What was typed before the PIN prompt is a password and
    // never goes to the key: each wrong PIN counts against the key's own
    // tries, and the key's FIDO part locks when they run out. For the same
    // reason the key is asked only while it has tries to spare, and not after
    // two wrong PINs in this lock (`keyTries`, `keyWrong`, LockLogic.keyPause).
    readonly property string keyMode: SettingsService.value("lock.securityKey")
    property bool keyServiceInstalled: false
    // The /etc/pam.d/buchhwin-lock-key check has finished (test services need none).
    property bool keyServiceChecked: mainService !== "buchhwin-lock"
    readonly property string keyService: Logic.keyService(testHooks, requestedKeyService, keyServiceInstalled, keyMode)
    property bool keyTurn: true
    property bool keyStage: false
    property bool keyPin: false
    property bool keyTouch: false
    property bool keyAsked: false
    property bool keyManual: false
    // From the key's end until the next conversation begins: PamContext can
    // report a system error as well as the result, and the second of them
    // belongs to the key's conversation, not to the one that follows.
    property bool keyClosing: false
    // PINs this lock gave the key (the test holds the "never a password" rule to it).
    property int keyPinsSent: 0
    // The plugged key's PIN tries (LockLogic.keyTries), read without the PIN
    // before the key's first turn and again on each "Use security key"; null
    // until read. A test lock reads `keyPinsHook`, never a key.
    property string keyPinsHook: Logic.KEY_TEST_PINS
    property var keyTries: null
    // PINs of this lock that did not unlock; the PIN of the running
    // conversation was sent; "Use security key" waits for the tries.
    property int keyWrong: 0
    property bool keyPinGiven: false
    property bool keyWanted: false
    readonly property string keyPause: keyService.length > 0 ? Logic.keyPause(keyTries, keyWrong) : ""
    // Said where the "Use security key" link was.
    readonly property string keyNotice: keyStage ? "" : Logic.keyPauseText(keyPause, keyTries ? keyTries.retries : -1)
    readonly property bool keyOffered: keyService.length > 0 && keyPause === "" && !keyStage && !unlocking && SettingsService.loaded
    onKeyServiceChanged: readKeyTries()
    // A start waits for the settings, the PAM file check and the lid state.
    property bool startQueued: false

    Behavior on fade {
        NumberAnimation {
            duration: root.unlocking ? Animations.lockExit : Animations.lockEnter
            easing.type: root.unlocking ? Easing.InCubic : Easing.OutCubic
        }
    }
    Component.onCompleted: {
        fade = 1
        readKeyTries()
    }

    function engage() {
        engaged = true
        idleTimer.restart()
    }

    // A face reports its surface gaining (or losing) the keyboard, and every
    // key it is given.
    function noteInput(screenName, gained) {
        inputScreen = Logic.inputScreenAfter(inputScreen, screenName, gained)
    }

    function type(text) {
        if (busy || unlocking) return
        engage()
        password += text
        if (!statusIsError && !fingerprintStage && !keyStage) {
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
    // Escape: leaves the key's conversation for the password, else clears.
    function pressEscape() {
        if (keyStage && !unlocking) leaveKey()
        else clear()
    }

    function submit() {
        if (busy || unlocking || !password.length) return
        if (pam.active && keyStage && !pam.responseRequired) {
            // Sent before the key asked for its PIN: a password, never the PIN.
            submitPending = true
            busy = true
            leaveKey()
        } else if (pam.active && pam.responseRequired) {
            clearStatus()
            busy = true
            if (keyStage) {
                // The PIN leaves the buffer at once: the field waits for the
                // touch, and nothing typed later is added to a PIN.
                const pin = password
                password = ""
                keyPin = false
                keyPinsSent += 1
                keyPinGiven = true
                pam.respond(pin)
                return
            }
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
        const ready = SettingsService.loaded && passwordServiceChecked && keyServiceChecked && lidChecked
                      && (!keyService.length || keyTries !== null)
        if (!ready && !force) return
        if (!lidChecked) lidClosed = false
        startQueued = false
        startWatchdog.stop()
        if (pam.active || unlocking) return
        if (Logic.startsWithKey(keyService, keyTurn, submitPending, keyTries, keyWrong)) {
            beginKey(false)
            return
        }
        fingerprintAllowed = Logic.fingerprintEnabled(fingerprintMode, lidClosed)
        beginPam(Logic.startPasswordOnly(fingerprintAllowed, mainService, passwordService))
    }

    // The key's conversation (see keyService). `manual`: asked for by a click.
    function beginKey(manual) {
        if (pam.active || unlocking) return
        root.passwordOnly = false
        fingerprintStage = false
        fingerprint = ""
        keyTurn = false
        keyPinGiven = false
        keyManual = manual === true
        keyClosing = false
        keyAsked = false
        keyPin = false
        keyTouch = false
        keyStage = true
        pamMessages = []
        if (!pam.start()) {
            keyStage = false
            startPam()
        }
    }
    // The key is left for the password: Escape, a click on "Use password",
    // or a password typed before the PIN prompt. Synchronous like
    // passwordNow; a password already sent goes the password-only way.
    function leaveKey() {
        if (!keyStage || unlocking) return
        if (pam.active) pam.abort()
        // A PIN sent and then left may have been a wrong one.
        if (keyPinGiven) keyMissed()
        // A PIN half typed is no password.
        if (keyPin) password = ""
        keyStage = false
        keyPin = false
        keyTouch = false
        busy = submitPending
        clearStatus()
        startPam(submitPending)
    }
    // "Use security key": the key once more, whatever runs now - once its
    // tries were read again, so that a key plugged in meanwhile is asked and
    // one with few tries left is not.
    function useKey() {
        if (!keyOffered || busy || keyWanted) return
        keyWanted = true
        readKeyTries()
    }
    function readKeyTries() {
        if (!keyService.length || keyTriesProc.running) return
        keyTriesProc.running = true
    }
    function keyTriesRead(text) {
        keyTries = Logic.keyTries(text)
        if (!keyWanted) {
            tryStart(false)
            return
        }
        keyWanted = false
        // Few tries left, or a password sent meanwhile: the password goes on.
        if (!keyOffered || busy) return
        if (pam.active) pam.abort()
        clearStatus()
        password = ""
        submitPending = false
        beginKey(true)
    }
    // A PIN that did not unlock: one try fewer on the key, one more of this lock's.
    function keyMissed() {
        keyPinGiven = false
        keyWrong += 1
        keyTries = Logic.keyTriesAfterWrong(keyTries)
    }
    function keyDone(success) {
        if (!keyStage) return
        if (!success && keyPinGiven) keyMissed()
        const next = Logic.afterKey(success, keyAsked, keyManual)
        keyStage = false
        keyPin = false
        keyTouch = false
        keyClosing = true
        busy = false
        if (next.action === "unlock") {
            unlock()
            return
        }
        status = next.text
        statusIsError = next.action === "refused"
        // A refusal stays readable for a moment before the reader speaks;
        // otherwise the usual start follows a turn later, outside
        // PamContext's own signal.
        if (next.action === "refused") restartTimer.restart()
        else Qt.callLater(() => root.startPam(root.submitPending))
    }

    function beginPam(passwordOnly) {
        if (pam.active || unlocking) return
        root.passwordOnly = passwordOnly === true
        keyStage = false
        keyClosing = false
        fingerprintStage = false
        pamMessages = []
        if (!pam.start()) {
            busy = false
            submitPending = false
            statusIsError = true
            status = "Authentication is not available"
            restartTimer.restart()
        }
    }

    // The reader announced itself after the password was submitted (see
    // LockLogic.passwordInstead): leave it and check the password alone, as
    // submit() does during the reader's wait. Called a turn after the message,
    // outside PamContext's own signal; abort() is synchronous and emits
    // neither completed nor error.
    function passwordNow() {
        if (!pam.active || !fingerprintStage || !submitPending || unlocking) return
        pam.abort()
        clearStatus()
        startPam(true)
    }

    // Clicking the fingerprint after a timeout starts the reader again.
    function retryFingerprint() {
        if (busy || unlocking || fingerprintStage || passwordOnly) return
        if (pam.active) pam.abort()
        clearStatus()
        startPam(false)
    }

    // Caps Lock and the layout after a key: asked at once, then at most every
    // 300 ms while keys keep coming, and once more after the last of them.
    // Every key started its own `hyprctl -j devices` before (~10 ms each).
    // Which key it was is not looked at: a layout switch is whatever xkb
    // option the user chose.
    property bool keysUnchecked: false
    function keyActivity() {
        if (keyboardPause.running || keyboardProc.running) {
            keysUnchecked = true
            keyboardPause.start()
            return
        }
        keysUnchecked = false
        keyboardProc.running = true
        keyboardPause.start()
    }
    Timer { id: keyboardPause; interval: 300; onTriggered: if (root.keysUnchecked) root.keyActivity() }

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
        if (quitOnUnlock) quitTimer.restart()
    }

    PamContext {
        id: pam
        config: root.keyStage ? root.keyService : root.passwordOnly ? root.passwordService : root.mainService
        configDirectory: Logic.systemService(config) ? "/etc/pam.d" : Quickshell.shellPath("tests/fixtures/pam")
        user: root.user

        onPamMessage: {
            if (root.keyStage) {
                const keyEvent = Logic.keyEvent(message, responseRequired)
                if (keyEvent === "pin") {
                    // Typed for the password before the key spoke: not its PIN.
                    if (root.password.length || root.submitPending) {
                        Qt.callLater(root.leaveKey)
                        return
                    }
                    root.keyAsked = true
                    root.keyPin = true
                    root.status = "Then touch the key"
                    root.statusIsError = false
                } else if (keyEvent === "touch") {
                    root.keyPin = false
                    root.keyTouch = true
                    root.status = ""
                    root.statusIsError = false
                }
                return
            }
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
                if (Logic.passwordInstead(root.fingerprintStage, root.submitPending, root.mainService, root.passwordService))
                    Qt.callLater(root.passwordNow)
            } else if (message.length) {
                root.status = message
                root.statusIsError = messageIsError
                root.pamMessages = root.pamMessages.concat([message])
            }
        }
        onCompleted: result => {
            if (root.keyStage || root.keyClosing) {
                root.keyDone(result === PamResult.Success)
                return
            }
            root.busy = false
            root.submitPending = false
            root.fingerprintStage = false
            root.fingerprint = ""
            const next = Logic.afterPam(result, { Success: PamResult.Success, Failed: PamResult.Failed, Error: PamResult.Error, MaxTries: PamResult.MaxTries },
                                        Logic.lockoutNotice(root.pamMessages))
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
            if (root.keyStage || root.keyClosing) {
                root.keyDone(false)
                return
            }
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
        locked: root.surfaces && !root.preview
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

    // The preview's windows (LockPreviewWindows.qml) are lock.qml's to make:
    // a file that names PanelWindow does not load offscreen at all.

    FileView {
        id: marker
        path: root.dir.length ? root.dir + "/locked" : ""
        printErrors: false
    }

    // Preview windows are "locked" as soon as they exist.
    Timer { running: root.preview && root.dir.length > 0; interval: 200; onTriggered: marker.setText("1\n") }

    Process {
        running: root.user.length > 0
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector { onStreamFinished: root.displayName = Logic.displayName(text, root.user) }
    }

    // The helper is asked only for a logo that can be a picture
    // (LockLogic.logoMayBePicture). The file as fastfetch-image.py writes it
    // is plain JSON; one with comments in it cannot be read here and is
    // asked about as before.
    property bool logoMayBePicture: false
    FileView {
        path: Paths.configDir + "/fastfetch.jsonc"
        printErrors: false
        onLoaded: {
            let logo = null
            try {
                const config = JSON.parse(text())
                logo = config && typeof config === "object" ? config.logo : null
            } catch (error) {
                root.logoMayBePicture = true
                return
            }
            root.logoMayBePicture = Logic.logoMayBePicture(logo)
        }
    }

    Process {
        running: root.showAvatar && root.logoMayBePicture
        command: ["python3", Paths.script("fastfetch-image.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Only a picture: a text logo (the buchhwin profile's
                // saturn.txt) is fastfetch's too, and as an image it only
                // failed to decode before the initial took its place.
                try {
                    const logo = JSON.parse(text)
                    root.avatar = logo.kind === "image" ? logo.source || "" : ""
                } catch (error) { root.avatar = "" }
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

    // The security key's PAM service exists only once it was set up.
    Process {
        running: root.mainService === "buchhwin-lock"
        command: ["test", "-r", "/etc/pam.d/buchhwin-lock-key"]
        onExited: code => {
            root.keyServiceInstalled = code === 0
            root.keyServiceChecked = true
            root.tryStart(false)
        }
    }

    // The key's PIN tries (readKeyTries), asked without its PIN, so the read
    // costs no try; a test lock prints its hook instead and asks no key.
    Process {
        id: keyTriesProc
        command: root.testHooks ? ["printf", "%s\n", root.keyPinsHook] : [Paths.script("security-key.py"), "pins"]
        stdout: StdioCollector { onStreamFinished: root.keyTriesRead(text) }
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
