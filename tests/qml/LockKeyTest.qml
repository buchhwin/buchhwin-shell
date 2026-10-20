//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import qs.shell.lock
import "Harness.js" as T
import "../../services/lock/LockLogic.js" as L

// The security key on the lock screen (LockScreen.keyStage), offscreen and on
// the PAM fixtures: test-key stands in for pam_u2f with a key plugged in (a
// PIN, "lock-test-pin", then a touch), test-key-absent for pam_u2f without
// one; test-password is the usual start after it. Each screen plays one way
// through, and none of them ever gives the key a password.
ShellRoot {
    id: root

    component KeyLock: LockScreen {
        nested: true
        dir: ""
        requestedService: "test-password"
        lidHook: "0"
        surfaces: false
        quitOnUnlock: false
        // How often the PIN was asked, and whether the key waited for a touch.
        property int pinPrompts: 0
        property bool touched: false
        property var statuses: []
        // What the screen does when the PIN is asked (a turn later), or null.
        property var pinAnswer: null
        onKeyPinChanged: {
            if (!keyPin) return
            pinPrompts += 1
            if (pinAnswer) Qt.callLater(pinAnswer)
        }
        onKeyTouchChanged: if (keyTouch) touched = true
        onStatusChanged: if (status.length) statuses = statuses.concat([status])
    }

    // No key plugged in: nothing asked, nothing said, and the password works.
    KeyLock { id: absent; requestedKeyService: "test-key-absent" }
    // The key's service failing as a system error, reported twice by PAM:
    // the second report is the key's too, and no shake meets the password.
    KeyLock { id: broken; requestedKeyService: "test-key-error" }
    // The PIN, a touch, unlocked.
    KeyLock {
        id: pin
        requestedKeyService: "test-key"
        pinAnswer: () => { pin.password = "lock-test-pin"; pin.submit() }
    }
    // A password typed before the key asked: the key is left, the PIN never
    // gets it.
    KeyLock {
        id: early
        requestedKeyService: "test-key"
        password: "lock-test-password"
    }
    // A wrong PIN: said in words, the password follows, the PIN is not asked again.
    KeyLock {
        id: wrong
        requestedKeyService: "test-key"
        pinAnswer: () => { if (wrong.pinPrompts === 1) { wrong.password = "wrong-pin"; wrong.submit() } }
    }
    // Escape at the PIN: the password instead, the PIN never sent.
    KeyLock {
        id: escaped
        requestedKeyService: "test-key"
        pinAnswer: () => escaped.pressEscape()
    }
    // The usual start asks for the password: give it, once per screen.
    function answer(screen) {
        if (screen.unlocking || screen.keyStage || screen.busy) return
        screen.password = "lock-test-password"
        screen.submit()
    }
    Timer {
        interval: 200
        repeat: true
        running: root.fixturesInUse
        onTriggered: {
            for (const screen of [absent, broken, early, escaped]) {
                if (!screen.keyStage && screen.keyService.length && !screen.keyTurn) root.answer(screen)
            }
            // The wrong PIN's screen gets the password once the key is done with.
            if (wrong.pinPrompts === 1 && !wrong.keyStage && !wrong.keyTurn && wrong.statuses.length) root.answer(wrong)
        }
    }

    property bool fixturesInUse: false
    Timer {
        interval: 6000
        running: root.fixturesInUse
        onTriggered: root.check()
    }

    function check() {
        T.eq([absent.unlocking, absent.pinPrompts, absent.keyPinsSent, absent.shakes, absent.statuses],
             [true, 0, 0, 0, []], "no key: nothing asked or said, and the password unlocks")
        T.eq([broken.unlocking, broken.pinPrompts, broken.shakes, broken.statuses],
             [true, 0, 0, []], "a key service failing as a system error: no shake, and the password unlocks")
        T.eq([pin.unlocking, pin.pinPrompts, pin.keyPinsSent, pin.touched, pin.passwordOnly],
             [true, 1, 1, true, false], "the PIN, then a touch, unlocks")
        T.eq([early.unlocking, early.pinPrompts, early.keyPinsSent], [true, 0, 0],
             "a password typed before the key asked unlocks, and the key never got it")
        T.eq([wrong.unlocking, wrong.pinPrompts, wrong.keyPinsSent], [true, 1, 1],
             "a wrong PIN once, the PIN not asked again, the password unlocks")
        T.ok(wrong.statuses.some(text => /did not unlock/.test(text)), "the refusal is said: " + JSON.stringify(wrong.statuses))
        T.eq([escaped.unlocking, escaped.pinPrompts, escaped.keyPinsSent], [true, 1, 0], "Escape leaves the PIN for the password")
        T.finish("LockKeyTest")
    }

    Component.onCompleted: {
        // Every screen must be on a fixture before anything is typed.
        const screens = [absent, broken, pin, early, wrong, escaped]
        T.eq(screens.map(screen => [screen.mainService, screen.keyService]),
             [["test-password", "test-key-absent"], ["test-password", "test-key-error"], ["test-password", "test-key"],
              ["test-password", "test-key"], ["test-password", "test-key"], ["test-password", "test-key"]],
             "the screens use the fixtures")
        T.eq(screens.map(screen => L.systemService(screen.keyService) || L.systemService(screen.mainService)),
             [false, false, false, false, false, false], "none of them reaches a system service")
        fixturesInUse = screens.every(screen => !L.systemService(screen.keyService) && !L.systemService(screen.mainService)
                                                && screen.keyService.length > 0)
        if (!fixturesInUse) T.finish("LockKeyTest")
    }
}
