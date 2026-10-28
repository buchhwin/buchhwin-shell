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
// through, and none of them ever gives the key a password. The key's PIN
// tries come from each screen's keyPinsHook (8 unless it says otherwise),
// never from a key.
ShellRoot {
    id: root

    component KeyLock: LockScreen {
        nested: true
        dir: Quickshell.env("XDG_RUNTIME_DIR") + "/buchhwin-shell/lock-nested"
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
        // Clicks on "Use security key" the test made.
        property int clicks: 0
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
    // Few tries left on the key: it is never asked, a click on "Use security
    // key" does nothing, the lock says why, and the password works.
    KeyLock { id: few; requestedKeyService: "test-key"; keyPinsHook: root.pins(3) }
    // The tries could not be read (no fido2-token): the same.
    KeyLock { id: unread; requestedKeyService: "test-key"; keyPinsHook: JSON.stringify({ ok: true, fido2Token: false, pins: [] }) }
    // Two wrong PINs, the second after "Use security key": the key is not
    // asked again in this lock, whatever is clicked.
    KeyLock {
        id: twice
        requestedKeyService: "test-key"
        pinAnswer: () => { twice.password = "wrong-pin"; twice.submit() }
    }
    // 4 tries and one wrong PIN: 3 left, so the key is not asked again.
    KeyLock {
        id: four
        requestedKeyService: "test-key"
        keyPinsHook: root.pins(4)
        pinAnswer: () => { four.password = "wrong-pin"; four.submit() }
    }
    // "Use security key" reads the tries again: 3 by now (another sign-in
    // used some), so the key is not asked.
    KeyLock {
        id: reread
        requestedKeyService: "test-key"
        pinAnswer: () => { reread.keyPinsHook = root.pins(3); reread.pressEscape() }
    }
    function pins(retries) { return JSON.stringify({ ok: true, fido2Token: true, pins: [{ set: true, retries: retries }] }) }
    // The face of the few-tries screen: the notice where the link was.
    LockFace { id: fewFace; width: 1920; height: 1200; lockState: few; screenName: "" }
    property bool fewNoticeShown: false
    property bool fewLinkShown: true
    function find(item, test) {
        if (!item) return null
        if (test(item)) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) {
            const found = find(kids[i], test)
            if (found) return found
        }
        return null
    }
    function shown(face, words) {
        const label = find(face, item => item.role !== undefined && item.text === words)
        return label !== null && label.visible
    }
    // A click on "Use security key", as the face makes it.
    function click(screen) {
        screen.clicks += 1
        screen.useKey()
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
            for (const screen of [few, unread]) {
                if (screen.keyTries === null || screen.keyStage || screen.busy || screen.unlocking) continue
                if (screen === few && !few.clicks) {
                    root.fewNoticeShown = root.shown(fewFace, few.keyNotice)
                    root.fewLinkShown = root.shown(fewFace, "Use security key")
                }
                if (!screen.clicks) root.click(screen)
                else root.answer(screen)
            }
            // The first wrong PIN said, then the key once more by a click; after
            // the second, a click that asks nothing, then the password.
            if (twice.keyWrong === 1 && twice.clicks === 0 && !twice.keyStage && twice.statuses.length) root.click(twice)
            if (twice.keyWrong === 2 && !twice.keyStage) {
                if (twice.clicks === 1) root.click(twice)
                else root.answer(twice)
            }
            if (four.keyWrong === 1 && !four.keyStage) {
                if (!four.clicks) root.click(four)
                else root.answer(four)
            }
            if (reread.pinPrompts === 1 && !reread.keyStage) {
                if (!reread.clicks) root.click(reread)
                else if (!reread.keyWanted && reread.keyPause === "few") root.answer(reread)
            }
        }
    }

    property bool fixturesInUse: false
    Timer {
        interval: 9000
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
        T.eq([few.unlocking, few.clicks, few.pinPrompts, few.keyPinsSent, few.keyPause], [true, 1, 0, 0, "few"],
             "3 tries left: the key is not asked, not even on a click, and the password unlocks")
        T.ok(/only 3 PIN tries/.test(few.keyNotice), "the lock says why: " + few.keyNotice)
        T.eq([root.fewNoticeShown, root.fewLinkShown], [true, false], "the face shows the words in place of the link")
        T.eq([unread.unlocking, unread.clicks, unread.pinPrompts, unread.keyPause], [true, 1, 0, "unknown"],
             "tries that could not be read: the key is not asked, the password unlocks")
        T.eq([twice.unlocking, twice.clicks, twice.pinPrompts, twice.keyPinsSent, twice.keyWrong, twice.keyPause], [true, 2, 2, 2, 2, "wrong"],
             "two wrong PINs, then a click asks the key nothing, and the password unlocks")
        T.ok(/2 wrong PINs/.test(twice.keyNotice), "the lock says why: " + twice.keyNotice)
        T.eq([four.unlocking, four.clicks, four.pinPrompts, four.keyPinsSent, four.keyTries, four.keyPause],
             [true, 1, 1, 1, { state: "few", retries: 3 }, "few"], "4 tries and one wrong PIN: 3 left, the key is not asked again")
        T.eq([reread.unlocking, reread.clicks, reread.pinPrompts, reread.keyPinsSent, reread.keyWrong, reread.keyPause],
             [true, 1, 1, 0, 0, "few"], "a click reads the tries again, and 3 left keeps the key from being asked")
        T.finish("LockKeyTest")
    }

    Component.onCompleted: {
        // Every screen must be on a fixture before anything is typed.
        const screens = [absent, broken, pin, early, wrong, escaped, few, unread, twice, four, reread]
        T.eq(screens.map(screen => [screen.mainService, screen.keyService]),
             [["test-password", "test-key-absent"], ["test-password", "test-key-error"]]
             .concat(screens.slice(2).map(screen => ["test-password", "test-key"])),
             "the screens use the fixtures")
        T.eq(screens.map(screen => L.systemService(screen.keyService) || L.systemService(screen.mainService)),
             screens.map(screen => false), "none of them reaches a system service")
        T.eq(screens.map(screen => screen.testHooks), screens.map(screen => true), "and all of them read the tries from their hook")
        fixturesInUse = screens.every(screen => !L.systemService(screen.keyService) && !L.systemService(screen.mainService)
                                                && screen.keyService.length > 0)
        if (!fixturesInUse) T.finish("LockKeyTest")
    }
}
