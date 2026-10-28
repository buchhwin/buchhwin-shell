import Quickshell
import Quickshell.Io
import QtQuick
import qs.theme
import qs.shell.lock
import "Harness.js" as T
import "../../services/lock/LockLogic.js" as L

ShellRoot {
    id: root
    // The lock process's entry point, for the shell id it names itself by.
    // The runner copies the whole tree beside the test, lock.qml included.
    FileView { id: lockEntry; path: Quickshell.shellPath("lock.qml"); blockLoading: true }

    // Two screens' password fields over one shared state, wired the way
    // LockFace wires them: one buffer, and `showsInput` from LockLogic with
    // the screen the faces report. The connector names are generic ones.
    QtObject {
        id: shared
        property string password: ""
        property bool busy: false
        property int shakes: 0
        property string inputScreen: ""
        property bool keyPin: false
        property bool keyTouch: false
        function noteInput(screenName, gained) { inputScreen = L.inputScreenAfter(inputScreen, screenName, gained) }
        function submit() {}
    }
    Item {
        width: 800
        height: 200
        PasswordField { id: fieldA; lockState: shared; showsInput: L.showsInput("DP-1", shared.inputScreen) }
        PasswordField { id: fieldB; y: 100; lockState: shared; showsInput: L.showsInput("HDMI-A-1", shared.inputScreen) }
    }

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
    function shown(field, words) {
        const label = find(field, item => item.role !== undefined && item.text === words)
        return label !== null && label.visible
    }
    function dots(field) {
        const label = find(field, item => item.role !== undefined && /^•/.test(item.text))
        return label !== null && label.visible ? label.text : ""
    }
    // The pill carries the shake's Translate; the arrow is the MouseArea's button.
    function offset(field) { return find(field, item => item.transform !== undefined && item.transform.length > 0).transform[0].x }
    function arrow(field) { return find(field, item => item.containsMouse !== undefined).parent }

    // The shake and the arrow animate, so they are read over a few frames.
    property int phase: 0
    property int ticks: 0
    property real swingA: 0
    property real swingB: 0
    Timer {
        id: frames
        interval: 10
        repeat: true
        onTriggered: root.frame()
    }
    function frame() {
        ticks += 1
        swingA = Math.max(swingA, Math.abs(offset(fieldA)))
        swingB = Math.max(swingB, Math.abs(offset(fieldB)))
        if (phase === 0) {
            // Read while the shake is under way (it lasts ~0.4 s), not after.
            if (swingA === 0 && ticks < 50) return
            // A wrong password typed on DP-1 shakes there and nowhere else.
            T.ok(swingA > 0, "the field with the keyboard shakes (max offset " + swingA + ")")
            T.eq(swingB, 0, "the other screen's field stands still")
            // The keyboard leaves mid-shake: the field it left stops at rest.
            shared.noteInput("HDMI-A-1", true)
            T.eq(offset(fieldA), 0, "the field the keyboard left is back at rest at once")
            swingA = 0
            swingB = 0
            ticks = 0
            phase = 1
            return
        }
        if (ticks < 25) return
        frames.stop()
        T.eq([swingA, swingB], [0, 0], "neither field moves after the keyboard moved")
        T.ok(arrow(fieldB).visible && arrow(fieldB).opacity > 0, "the arrow comes up where the keyboard went")
        T.ok(!arrow(fieldA).visible, "and leaves the screen it left")
        T.finish("LockTest")
    }

    Component.onCompleted: {
        // The lock process keeps the session's services inert. It is told
        // apart by the shell id lock.qml declares, so the two must agree.
        T.eq([L.lockProcess("buchhwin-shell-lock"), L.lockProcess(""), L.lockProcess(undefined), L.lockProcess("buchhwin-shell")],
             [true, false, false, false], "only the lock's shell id is the lock process")
        // Quickshell 0.2.1 (Fedora) has no `shellId`: there the id is the
        // last part of the shell's cache directory. An id Quickshell does
        // name wins, an empty one too.
        T.eq([L.shellIdOf({ shellId: "buchhwin-shell-lock", cacheDir: "/home/u/.cache/quickshell/by-shell/abc123" }),
              L.shellIdOf({ cacheDir: "/home/u/.cache/quickshell/by-shell/buchhwin-shell-lock" }),
              L.shellIdOf({ cacheDir: "/home/u/.cache/quickshell/by-shell/buchhwin-shell-lock/" }),
              L.shellIdOf({ cacheDir: "/home/u/.cache/elsewhere" }), L.shellIdOf({}), L.shellIdOf("buchhwin-shell")],
             ["buchhwin-shell-lock", "buchhwin-shell-lock", "buchhwin-shell-lock", "", "", "buchhwin-shell"],
             "the shell id from Quickshell, or from its cache directory where Quickshell has none")
        T.eq([L.lockProcess({ cacheDir: "/home/u/.cache/quickshell/by-shell/buchhwin-shell-lock" }),
              L.lockProcess({ shellId: "", cacheDir: "/home/u/.cache/quickshell/by-shell/buchhwin-shell-lock" }),
              L.lockProcess({ cacheDir: "/home/u/.cache/quickshell/by-shell/abc123" }), L.lockProcess(Quickshell)],
             [true, false, false, false], "the lock process on either version; this test is not it")
        T.ok(lockEntry.text().split("\n").indexOf("//@ pragma ShellId " + L.LOCK_SHELL_ID) >= 0,
             "lock.qml declares the shell id LockLogic knows")

        // An invented account, never a real one.
        T.eq(L.displayName("sample:x:1000:1000:Sample User,,,:/home/sample:/bin/bash", "sample"), "Sample User", "GECOS full name")
        T.eq(L.displayName("sample:x:1000:1000::/home/sample:/bin/bash", "sample"), "sample", "login without GECOS")
        T.eq(L.displayName("", "sample"), "sample", "missing passwd line")
        T.eq([L.initial("sample"), L.initial(""), L.initial("Ärger")], ["S", "?", "Ä"], "initials")

        const results = { Success: 0, Failed: 1, Error: 2, MaxTries: 3 }
        T.eq(L.afterPam(0, results).action, "unlock", "success unlocks")
        T.eq(L.afterPam(1, results).action, "retry", "wrong password retries")
        T.eq(L.afterPam(3, results).action, "message", "too many tries shows a message")
        T.eq(L.afterPam(2, results).action, "retry", "a PAM error retries like a wrong password")
        T.eq([L.afterPam(1, results).text, L.afterPam(2, results).text], ["", ""],
             "a rejected password says nothing in words")
        T.eq(L.afterPam(1, results, "The account is locked due to 3 failed logins.").action, "message",
             "a faillock lockout keeps its message")
        T.eq(L.lockoutNotice(["The account is locked due to 3 failed logins.", "(9 minutes left to unlock)"]),
             "The account is locked due to 3 failed logins. (9 minutes left to unlock)", "both faillock lines")
        T.eq([L.lockoutNotice(["Place your finger on the reader"]), L.lockoutNotice([]), L.lockoutNotice(undefined)],
             ["", "", ""], "other messages are not a lockout")
        T.eq(L.afterPam(1, results, "").action, "retry", "no notice: a plain retry")
        T.eq(L.afterPam(0, results).shake, false, "a successful unlock does not shake")
        T.eq([L.afterPam(1, results).shake, L.afterPam(2, results).shake, L.afterPam(3, results).shake],
             [true, true, true], "every rejected attempt shakes: wrong password, PAM error and too many tries")

        const devices = { keyboards: [{ name: "a", main: false, capsLock: false, active_keymap: "English (US)" },
                                      { name: "b", main: true, capsLock: true, active_keymap: "German" }] }
        T.eq(L.keyboardState(devices), { capsLock: true, layout: "DE" }, "caps lock and main keymap")
        T.eq(L.keyboardState(JSON.stringify({ keyboards: [{ capsLock: false, active_keymap: "English (US)" }] })), { capsLock: false, layout: "US" }, "JSON text")
        T.eq(L.keyboardState("not json"), { capsLock: false, layout: "" }, "broken output")
        T.eq([L.shortLayout("de"), L.shortLayout("French (Swiss)")], ["DE", "FR"], "short layouts")

        T.eq(L.pamService(false, "test-permit"), "buchhwin-lock", "real session always uses buchhwin-lock")
        T.eq(L.pamService(true, "test-deny"), "test-deny", "nested test service")
        T.eq(L.pamService(true, "login"), "buchhwin-lock", "only the test services are accepted")
        T.eq(L.pamService(true, "test-fingerprint"), "test-fingerprint", "nested fingerprint fixture")
        T.eq(L.pamService(false, "test-fingerprint"), "buchhwin-lock", "fingerprint fixture only nested")
        T.eq([L.pamService(true, "test-password"), L.pamService(true, "test-fingerprint-late")],
             ["test-password", "test-fingerprint-late"], "the password-checking fixtures are test services too")
        T.eq(L.pamService("yes", "test-permit"), "buchhwin-lock", "only a real true opens the test services")

        // The test hooks need the nested lock directory as well as the flag:
        // session-action.sh names the real session's `…/lock`, and a flag
        // that leaked into it must not reach a fixture.
        T.eq([L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock-nested"),
              L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock-nested/")],
             [true, true], "a nested session's lock directory allows the hooks")
        T.eq(L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock"), false,
             "the real session's lock directory refuses them, flag or not")
        T.eq(L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock-nestedx"), false, "only that exact name")
        T.eq([L.testHooksAllowed(true, ""), L.testHooksAllowed(true, undefined)], [false, false],
             "nor a lock without a directory: started by hand after the real one was ended, test-permit took any input")
        T.eq([L.testHooksAllowed(false, ""), L.testHooksAllowed(false, "/run/user/1000/buchhwin-shell/lock-nested"),
              L.testHooksAllowed("1", "")], [false, false, false], "never without the nested flag")
        T.eq(L.pamService(L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock"), "test-permit"), "buchhwin-lock",
             "a leaked test-permit in the real session's lock is the real service")
        T.eq(L.lidOverride(L.testHooksAllowed(true, "/run/user/1000/buchhwin-shell/lock"), "1"), null,
             "and so is a leaked lid override")

        // Password-only conversation while the fingerprint reader blocks the prompt
        T.eq(L.passwordService("buchhwin-lock", true), "buchhwin-lock-password", "installed password-only service")
        T.eq(L.passwordService("buchhwin-lock", false), "buchhwin-lock", "falls back without the PAM file")
        T.eq(L.passwordService("test-fingerprint", false), "test-permit", "fixture pair")
        T.eq(L.passwordService("test-fingerprint-late", false), "test-password", "the late reader pairs with the password check")
        T.eq(L.passwordService("test-deny", true), "test-deny", "test services stay")

        // A password submitted before the reader spoke goes the password-only
        // way once the reader announces itself, instead of waiting it out.
        T.eq(L.passwordInstead(true, true, "buchhwin-lock", "buchhwin-lock-password"), true,
             "the reader spoke after an early submit: switch")
        T.eq([L.passwordInstead(false, true, "buchhwin-lock", "buchhwin-lock-password"),
              L.passwordInstead(true, false, "buchhwin-lock", "buchhwin-lock-password")], [false, false],
             "not before the reader speaks, and not without a pending password")
        T.eq(L.passwordInstead(true, true, "buchhwin-lock", "buchhwin-lock"), false,
             "without a password-only service the password waits for the prompt, as before")
        T.eq(L.passwordInstead(true, true, "test-fingerprint-late", "test-password"), true, "the fixture pair switches too")

        // Which fastfetch logos are worth asking fastfetch-image.py about.
        T.eq([L.logoMayBePicture({ type: "file", source: "~/.config/buchhwin-shell/saturn.txt" }),
              L.logoMayBePicture({ type: "data", source: "$1 o" }),
              L.logoMayBePicture({ type: "builtin", source: "arch" }),
              L.logoMayBePicture({ type: "small", source: "arch" })], [false, false, false, false],
             "text and named logos are no picture")
        T.eq([L.logoMayBePicture({}), L.logoMayBePicture({ source: "" }), L.logoMayBePicture(null),
              L.logoMayBePicture("logo")], [false, false, false, false], "no logo, no source: no picture")
        T.eq([L.logoMayBePicture({ type: "kitty-direct", source: "~/Pictures/me.png" }),
              L.logoMayBePicture({ type: "Sixel", source: "/tmp/x" })], [true, true], "an image type is asked about")
        T.eq([L.logoMayBePicture({ source: "~/Pictures/me.png" }), L.logoMayBePicture({ type: "auto", source: "~/pic" }),
              L.logoMayBePicture({ type: "something-new", source: "~/pic" })], [true, true, true],
             "with no type, or one not known here, the helper decides by the file")
        T.eq([L.logoMayBePicture({ source: "~/.config/buchhwin-shell/saturn.txt" }),
              L.logoMayBePicture({ type: "auto", source: "/x/LOGO.TXT" })], [false, false], "a .txt file is text")
        T.eq([L.systemService("buchhwin-lock"), L.systemService("buchhwin-lock-password"), L.systemService("test-permit")], [true, true, false], "PAM directories")
        T.eq([L.systemService("buchhwin-lock-key"), L.systemService("test-key")], [true, false], "the key's service and its fixture")

        // Security key: its own service, asked first and once per lock
        T.eq([L.keyService(false, "", true, "auto"), L.keyService(false, "", false, "auto"), L.keyService(false, "", true, "off")],
             ["buchhwin-lock-key", "", ""], "the key's service once set up, unless turned off")
        T.eq(L.keyService(false, "test-key", true, "auto"), "buchhwin-lock-key", "a fixture is asked for only with the test hooks")
        T.eq([L.keyService(true, "test-key", false, "auto"), L.keyService(true, "", true, "auto"), L.keyService(true, "test-permit", true, "auto"),
              L.keyService(true, "test-key", false, "off")], ["test-key", "", "", ""], "a test lock takes a key fixture or none")
        T.eq(L.keyService(false, "", true, "bogus"), "buchhwin-lock-key", "an unknown mode behaves like automatic")
        const plenty = { state: "ok", retries: 8 }
        T.eq([L.startsWithKey("buchhwin-lock-key", true, false, plenty, 0), L.startsWithKey("buchhwin-lock-key", false, false, plenty, 0),
              L.startsWithKey("", true, false, plenty, 0), L.startsWithKey("buchhwin-lock-key", true, true, plenty, 0)], [true, false, false, false],
             "the key goes first on its turn, never with a password already sent")
        T.eq([L.startsWithKey("buchhwin-lock-key", true, false, null, 0),
              L.startsWithKey("buchhwin-lock-key", true, false, { state: "few", retries: 3 }, 0),
              L.startsWithKey("buchhwin-lock-key", true, false, { state: "unknown", retries: -1 }, 0),
              L.startsWithKey("buchhwin-lock-key", true, false, { state: "none", retries: -1 }, 0),
              L.startsWithKey("buchhwin-lock-key", true, false, plenty, 2)], [false, false, false, false, false],
             "the key is not asked first before its tries are read, with 3 or fewer, unread, unplugged, or after two wrong PINs")
        // The key's PIN tries (security-key.py pins), asked without the PIN.
        const pins = list => JSON.stringify({ ok: true, fido2Token: true, pins: list })
        T.eq(L.keyTries(pins([{ set: true, retries: 8 }])), { state: "ok", retries: 8 }, "plenty of tries")
        T.eq([L.keyTries(pins([{ set: true, retries: 4 }])).state, L.keyTries(pins([{ set: true, retries: 3 }])).state,
              L.keyTries(pins([{ set: true, retries: 0 }])).state], ["ok", "few", "few"], "more than 3 tries, or few")
        T.eq(L.keyTries(pins([{ set: true, retries: 8 }, { set: true, retries: 2 }])), { state: "few", retries: 2 },
             "two keys: the one with fewer tries counts")
        T.eq(L.keyTries(pins([])), { state: "none", retries: -1 }, "no key plugged in")
        T.eq(L.keyTries(pins([{ set: false, retries: null }])), { state: "ok", retries: -1 }, "a key without a PIN loses no tries")
        T.eq([L.keyTries(pins([{ set: true, retries: null }])).state, L.keyTries(pins([{ set: null, retries: null }])).state,
              L.keyTries(JSON.stringify({ ok: true, fido2Token: false, pins: [] })).state, L.keyTries("").state,
              L.keyTries("not json").state, L.keyTries(pins([null])).state],
             ["unknown", "unknown", "unknown", "unknown", "unknown", "unknown"],
             "tries that could not be read are unknown, never plenty")
        T.eq(L.keyTries("a warning\n" + pins([{ set: true, retries: 6 }])).retries, 6, "the last line is the answer")
        T.eq([L.keyTriesAfterWrong({ state: "ok", retries: 5 }), L.keyTriesAfterWrong({ state: "ok", retries: 4 }),
              L.keyTriesAfterWrong({ state: "ok", retries: -1 }), L.keyTriesAfterWrong(null)],
             [{ state: "ok", retries: 4 }, { state: "few", retries: 3 }, { state: "ok", retries: -1 }, null],
             "a wrong PIN costs one try")
        T.eq([L.keyPause(plenty, 0), L.keyPause(plenty, 1), L.keyPause(plenty, 2), L.keyPause(null, 0),
              L.keyPause({ state: "few", retries: 3 }, 0), L.keyPause({ state: "unknown", retries: -1 }, 0),
              L.keyPause({ state: "none", retries: -1 }, 0), L.keyPause({ state: "few", retries: 3 }, 2)],
             ["", "", "wrong", "reading", "few", "unknown", "", "wrong"], "why the key is not asked")
        T.eq([L.keyPauseText("", 8), L.keyPauseText("reading", -1)], ["", ""], "nothing said while the key may be asked")
        T.ok(/2 wrong PINs.*password/.test(L.keyPauseText("wrong", 6)), "two wrong PINs said: " + L.keyPauseText("wrong", 6))
        T.eq([L.keyPauseText("few", 3).indexOf("only 3 PIN tries"), L.keyPauseText("few", 1).indexOf("only 1 PIN try ")].map(at => at > 0),
             [true, true], "few tries said with their number: " + L.keyPauseText("few", 1))
        T.ok(/could not be read.*password/.test(L.keyPauseText("unknown", -1)), "unread tries said")
        T.eq([L.keyEvent("Please enter the PIN: ", true), L.keyEvent("Password: ", true), L.keyEvent("Please touch the FIDO authenticator.", false),
              L.keyEvent("something else", false), L.keyEvent("", false)], ["pin", "pin", "touch", "", ""], "the key's prompt and cue")
        T.eq([L.afterKey(true, true, false).action, L.afterKey(false, true, false).action, L.afterKey(false, false, false).action],
             ["unlock", "refused", "next"], "what the key's end leads to")
        T.eq([L.afterKey(false, false, false).text, L.afterKey(false, false, true).text], ["", "No security key found"],
             "no key is said in words only when it was asked for")
        T.ok(L.afterKey(false, true, true).text.indexOf("password") >= 0, "a refusal points to the password")

        // Fingerprint mode and lid
        T.eq([L.fingerprintEnabled("auto", false), L.fingerprintEnabled("auto", true)], [true, false], "automatic follows the lid")
        T.eq([L.fingerprintEnabled("on", true), L.fingerprintEnabled("off", false)], [true, false], "on and off ignore the lid")
        T.eq(L.fingerprintEnabled("bogus", true), false, "unknown mode behaves like automatic")
        T.eq([L.parseLidClosed("b true\n", 0), L.parseLidClosed("b false\n", 0)], [true, false], "UPower lid state")
        T.eq([L.parseLidClosed("", 1), L.parseLidClosed("b true", 1), L.parseLidClosed("Connection timed out", 0)], [false, false, false], "errors count as open")
        T.eq([L.lidOverride(true, "1"), L.lidOverride(true, "0"), L.lidOverride(true, ""), L.lidOverride(false, "1")], [true, false, null, null], "nested lid hook")
        T.eq(L.startPasswordOnly(false, "buchhwin-lock", "buchhwin-lock-password"), true, "disabled starts password-only")
        T.eq(L.startPasswordOnly(false, "buchhwin-lock", "buchhwin-lock"), false, "missing password-only service keeps the main one")
        T.eq(L.startPasswordOnly(true, "test-fingerprint", "test-permit"), false, "enabled keeps the reader")
        T.eq(L.startPasswordOnly(false, "test-fingerprint", "test-permit"), true, "fixture pair when disabled")

        // pam_fprintd messages
        T.eq(L.fingerprintEvent("Place your finger on the fingerprint reader", false, false, false), "prompt", "prompt")
        T.eq(L.fingerprintEvent("Place your right index finger on Elan MOC Sensors", false, false, false), "prompt", "prompt with finger and device")
        T.eq(L.fingerprintEvent("Swipe your finger across the fingerprint reader", false, false, false), "prompt", "swipe prompt")
        T.eq(L.fingerprintEvent("Place your finger on the reader again", false, false, true), "retry", "retry")
        T.eq(L.fingerprintEvent("Remove your finger, and try touching the sensor again", false, false, true), "retry", "remove and retry")
        T.eq(L.fingerprintEvent("Swipe was too short, try again", false, false, true), "retry", "too short")
        T.eq(L.fingerprintEvent("Failed to match fingerprint", true, false, true), "mismatch", "mismatch")
        T.eq(L.fingerprintEvent("Verification timed out", true, false, true), "ended", "timeout")
        T.eq(L.fingerprintEvent("An unknown error occurred", true, false, true), "ended", "reader error in the stage")
        T.eq(L.fingerprintEvent("An unknown error occurred", true, false, false), "", "other errors outside the stage")
        T.eq(L.fingerprintEvent("Password: ", false, true, true), "", "password prompt is not a fingerprint message")
        T.eq(L.fingerprintEvent("You have new mail", false, false, false), "", "unrelated info")
        T.eq(L.fingerprintText("prompt", "Place your finger on the fingerprint reader"), "Place your finger on the fingerprint reader", "prompt text")
        T.eq(L.fingerprintText("ended", "Verification timed out"), "Fingerprint timed out. Enter your password.", "timeout text")
        T.ok(L.fingerprintText("mismatch", "Failed to match fingerprint").indexOf("not recognized") >= 0, "mismatch text")

        // Which screen draws the typed password: the one with the keyboard.
        T.eq(L.inputScreenAfter("", "DP-1", true), "DP-1", "a surface gaining the keyboard takes the input")
        T.eq(L.inputScreenAfter("DP-1", "HDMI-A-1", true), "HDMI-A-1", "the keyboard moving to another monitor moves it")
        T.eq(L.inputScreenAfter("DP-1", "DP-1", false), "DP-1", "losing the keyboard moves nothing")
        T.eq(L.inputScreenAfter("DP-1", "HDMI-A-1", false), "DP-1", "another surface losing it moves nothing")
        T.eq(L.inputScreenAfter("DP-1", "", true), "DP-1", "a surface without a screen name moves nothing")
        T.eq(L.inputScreenAfter(undefined, undefined, true), "", "nothing reported yet")
        // Both orders a compositor may report a move in end on the new screen.
        T.eq(L.inputScreenAfter(L.inputScreenAfter("DP-1", "DP-1", false), "HDMI-A-1", true), "HDMI-A-1", "leave, then enter")
        T.eq(L.inputScreenAfter(L.inputScreenAfter("DP-1", "HDMI-A-1", true), "DP-1", false), "HDMI-A-1", "enter, then leave")
        T.eq([L.showsInput("DP-1", "DP-1"), L.showsInput("HDMI-A-1", "DP-1")], [true, false], "only the input screen draws the password")
        T.eq([L.showsInput("DP-1", ""), L.showsInput("HDMI-A-1", undefined)], [true, true], "before any report every screen draws, as before")
        T.eq(L.showsInput("eDP-1", "eDP-1"), true, "a single monitor draws it")

        // The fields: nothing reported yet, nothing typed - both empty.
        T.eq([shown(fieldA, "Enter password"), shown(fieldB, "Enter password")], [true, true], "both fields empty at the start")
        // The keyboard on DP-1 (the face's report), then three keys.
        shared.noteInput("DP-1", true)
        shared.noteInput("HDMI-A-1", false)
        shared.password = "abc"
        T.eq([fieldA.length, fieldB.length], [3, 0], "one buffer, drawn on one screen")
        T.eq([dots(fieldA), dots(fieldB)], ["•••", ""], "dots only where the keys go")
        T.eq([shown(fieldA, "Enter password"), shown(fieldB, "Enter password")], [false, true], "the other screen keeps the placeholder")
        shared.busy = true
        T.eq([dots(fieldA), shown(fieldB, "Checking …")], ["•••", true], "while PAM works the other screen says so, still without dots")
        shared.busy = false
        // The pointer takes the keyboard to HDMI-A-1: the dots follow.
        shared.noteInput("DP-1", false)
        shared.noteInput("HDMI-A-1", true)
        T.eq([dots(fieldA), dots(fieldB)], ["", "•••"], "the dots follow the keyboard to the other monitor")
        // A key from a surface that never reported the keyboard counts too.
        shared.noteInput("DP-1", true)
        T.eq([dots(fieldA), dots(fieldB)], ["•••", ""], "a key moves the dots to where it arrived")

        T.ok(Animations.motionEnabled, "the sandbox animates (the shake needs it)")
        shared.shakes += 1
        frames.start()
    }
}
