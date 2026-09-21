import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/lock/LockLogic.js" as L

ShellRoot {
    Component.onCompleted: {
        T.eq(L.displayName("jan:x:1000:1000:Jan Buchwinkler,,,:/home/jan:/bin/bash", "jan"), "Jan Buchwinkler", "GECOS full name")
        T.eq(L.displayName("jan:x:1000:1000::/home/jan:/bin/bash", "jan"), "jan", "login without GECOS")
        T.eq(L.displayName("", "jan"), "jan", "missing passwd line")
        T.eq([L.initial("jan"), L.initial(""), L.initial("Ärger")], ["J", "?", "Ä"], "initials")

        const results = { Success: 0, Failed: 1, Error: 2, MaxTries: 3 }
        T.eq(L.afterPam(0, results).action, "unlock", "success unlocks")
        T.eq(L.afterPam(1, results).action, "retry", "wrong password retries")
        T.eq(L.afterPam(3, results).action, "message", "too many tries shows a message")
        T.eq(L.afterPam(2, results).action, "retry", "a PAM error retries like a wrong password")
        T.eq([L.afterPam(1, results).text, L.afterPam(2, results).text], ["", ""],
             "a rejected password says nothing in words")
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

        // Password-only conversation while the fingerprint reader blocks the prompt
        T.eq(L.passwordService("buchhwin-lock", true), "buchhwin-lock-password", "installed password-only service")
        T.eq(L.passwordService("buchhwin-lock", false), "buchhwin-lock", "falls back without the PAM file")
        T.eq(L.passwordService("test-fingerprint", false), "test-permit", "fixture pair")
        T.eq(L.passwordService("test-deny", true), "test-deny", "test services stay")
        T.eq([L.systemService("buchhwin-lock"), L.systemService("buchhwin-lock-password"), L.systemService("test-permit")], [true, true, false], "PAM directories")

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
        T.finish("LockTest")
    }
}
