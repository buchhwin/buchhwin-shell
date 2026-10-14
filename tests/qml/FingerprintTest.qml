import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/fingerprint/FingerprintLogic.js" as F

ShellRoot {
    // Synthetic fprintd output (no real reader or prints).
    FileView { id: enrollSample; path: Qt.resolvedUrl("../fixtures/fingerprint-enroll.txt").toString().replace("file://", ""); blockLoading: true }
    FileView { id: deniedSample; path: Qt.resolvedUrl("../fixtures/fingerprint-enroll-denied.txt").toString().replace("file://", ""); blockLoading: true }
    FileView { id: listSample; path: Qt.resolvedUrl("../fixtures/fingerprint-list.txt").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // Fingers
        T.eq([F.validFinger("right-index-finger"), F.validFinger("nose"), F.validFinger("")], [true, false, false], "finger names")
        T.eq(F.fingerLabel("left-thumb"), "Left thumb", "finger label")
        T.eq(F.defaultFinger([]), "right-index-finger", "right index by default")
        T.eq(F.defaultFinger(["right-index-finger"]), "right-thumb", "first free finger")
        T.eq(F.fingerOptions(["left-thumb"]).find(o => o.value === "left-thumb").label, "Left thumb (enrolled)", "enrolled marker")
        T.eq(F.fingerOptions([]).length, 10, "ten fingers")

        // fprintd-list
        const listed = F.parseList(listSample.text(), 0)
        T.eq([listed.available, listed.device, listed.scanType, listed.fingers], [true, "Sample Fingerprint Reader", "press", ["right-index-finger", "left-thumb"]], "enrolled fingers")
        T.eq(listed.devicePath, "/net/reactivated/Fprint/Device/0", "device path")
        const empty = F.parseList("found 1 devices\nDevice at /net/reactivated/Fprint/Device/0\nUsing device /net/reactivated/Fprint/Device/0\nUser sample has no fingers enrolled for Sample Reader.\n", 0)
        T.eq([empty.available, empty.device, empty.fingers, empty.error], [true, "Sample Reader", [], ""], "no fingers enrolled")
        const none = F.parseList("No devices available\n", 1)
        T.eq([none.known, none.available, none.error], [true, false, ""], "no reader")
        T.eq(F.parseList("", 127).installed, false, "fprintd missing")
        T.eq(F.parseList("Impossible to get devices: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable\n", 1).error,
             "The fingerprint service (fprintd) is not available", "service error")
        T.eq(F.parseList(undefined, 0).known, false, "nothing read yet")
        T.eq(F.parseProperties("i 10\ns \"press\"\ns \"Elan MOC Sensors\"\n"), { stages: 10, scanType: "press" }, "device properties")
        T.eq(F.parseProperties("Failed to get property"), { stages: 0, scanType: "" }, "property error")

        // fprintd-enroll, line by line
        let state = F.enrollStart("right-index-finger", 8, "press")
        T.eq([state.phase, state.stage, state.finished], ["starting", 0, false], "start")
        T.ok(state.message.indexOf("password") >= 0, "start mentions the password dialog")
        state = F.enrollLine(state, "Enrolling right-index-finger finger.")
        T.eq(state.phase, "scanning", "scanning after EnrollStart")
        state = F.enrollLine(state, "Enroll result: enroll-stage-passed")
        state = F.enrollLine(state, "Enroll result: enroll-stage-passed")
        state = F.enrollLine(state, "Enroll result: enroll-stage-passed")
        T.eq([state.stage, state.message], [3, "Lift and place your finger again (3 of 8)"], "stage message")
        T.near(F.progress(state), 3 / 8, "progress")
        state = F.enrollLine(state, "Enroll result: enroll-retry-scan")
        T.eq([state.stage, state.retries, state.error, state.finished], [3, 1, false, false], "retry keeps the stage")
        T.eq(F.enrollLine(state, "Enroll result: enroll-remove-and-retry").message, "Lift your finger, then place it again.", "remove and retry")
        T.eq(F.enrollLine(state, "Enroll result: enroll-too-short").message, "Touch was too short. Try again.", "too short")
        const swipe = F.enrollLine(F.enrollStart("left-thumb", 0, "swipe"), "Enroll result: enroll-stage-passed")
        T.eq(swipe.message, "Swipe your finger again (1)", "swipe without a stage count")

        const done = F.enrollOutput(enrollSample.text(), "right-index-finger", 8, "press")
        T.eq([done.phase, done.success, done.finished, done.stage, done.retries], ["done", true, true, 8, 3], "synthetic enrollment completes")
        T.eq(done.message, "Enrolled. This finger now unlocks the lock screen.", "completed message")
        T.eq(F.progress(done), 1, "full progress")
        T.eq(F.enrollLine(done, "Enroll result: enroll-failed"), done, "finished state is final")

        const duplicate = F.enrollLine(state, "Enroll result: enroll-duplicate")
        T.eq([duplicate.phase, duplicate.error, duplicate.success], ["failed", true, false], "duplicate fails")
        T.eq(F.enrollLine(state, "Enroll result: enroll-failed").message, "Enrollment failed. Try again.", "failed message")

        const denied = F.enrollOutput(deniedSample.text(), "right-index-finger", 8, "press")
        T.eq([denied.phase, denied.error], ["failed", true], "polkit denial fails")
        T.eq(denied.message, "Permission was denied. Confirm the password dialog to change fingerprints.", "polkit denial message")
        T.eq(F.enrollOutput("failed to claim device: GDBus.Error:net.reactivated.Fprint.Error.AlreadyInUse: Device was already claimed", "right-thumb", 8, "press").message,
             "The fingerprint reader is busy. Close other fingerprint apps and try again.", "busy reader")
        T.eq(F.enrollOutput("Impossible to enroll: GDBus.Error:net.reactivated.Fprint.Error.NoSuchDevice: No devices available", "right-thumb", 8, "press").message,
             "No fingerprint reader found", "no reader while enrolling")

        // Process exit
        T.eq(F.enrollExited(state, 0, true).phase, "cancelled", "cancel")
        T.eq(F.enrollExited(state, 1, false).message, "Enrollment stopped (exit code 1)", "unexpected exit")
        T.eq(F.enrollExited(done, 0, true).phase, "done", "exit keeps a result")

        // Unlock mode
        T.eq([F.modeLabel("auto", false), F.modeLabel("auto", true), F.modeLabel("on", true), F.modeLabel("off", false)],
             ["Automatic", "Automatic · lid closed", "On", "Off"], "mode labels")
        T.ok(F.modeState("auto", true).indexOf("lid is closed") >= 0, "automatic with a closed lid")
        T.ok(F.modeState("auto", false).indexOf("On right now") === 0, "automatic with an open lid")
        T.ok(F.modeState("off", true).indexOf("password only") >= 0, "off state")

        // fprintd-delete
        T.eq(F.parseDelete("Using device /net/reactivated/Fprint/Device/0\nFingerprint left-thumb of user sample deleted on Sample Reader\n", 0, "left-thumb"),
             { ok: true, message: "Left thumb deleted" }, "deleted")
        const refused = F.parseDelete("Using device /net/reactivated/Fprint/Device/0\nFailed to delete fingerprints: GDBus.Error:net.reactivated.Fprint.Error.PermissionDenied: Not Authorized: net.reactivated.fprint.device.enroll\n", 1, "left-thumb")
        T.eq(refused.ok, false, "delete refused")
        T.ok(refused.message.indexOf("Permission was denied") >= 0, "delete permission message")

        // Commands
        T.eq(F.enrollCommand("right-thumb"), ["stdbuf", "-oL", "-eL", "fprintd-enroll", "-f", "right-thumb"], "enroll argv")
        T.eq(F.enrollCommand("-f"), null, "invalid finger")
        T.eq(F.deleteCommand("sample", "left-thumb"), ["fprintd-delete", "sample", "-f", "left-thumb"], "delete argv")
        T.eq(F.deleteCommand("a b", "left-thumb"), null, "invalid user")
        T.eq(F.listCommand("sample")[4], "sample", "user is a separate argument")
        // Whether PAM offers the reader to the whole system. "Off" in the
        // shell governs the lock screen; the login screen, sudo and polkit go
        // through system-auth, where authselect puts it - which is why an off
        // button that works still leaves you being asked.
        const withFp = "Profile ID: local\nEnabled features:\n- with-silent-lastlog\n- with-fingerprint\n"
        const withoutFp = "Profile ID: local\nEnabled features:\n- with-silent-lastlog\n"
        T.eq(F.systemFingerprint(withFp, 0), true, "authselect says the reader is on system-wide")
        T.eq(F.systemFingerprint(withoutFp, 0), false, "and says when it is not")
        T.eq(F.systemFingerprint("Profile ID: local\nEnabled features: None\n", 0), false, "no features at all")
        T.eq(F.systemFingerprint(withFp, 1), null, "a failed call is not an answer")
        T.eq(F.systemFingerprint("", 0), null, "and neither is empty output")
        T.eq(F.systemFingerprint("with-fingerprint", 0), null,
             "output that is not authselect's is refused rather than pattern-matched")
        // openSUSE has no authselect; pam-config writes the line into common-auth.
        const suse = "#%PAM-1.0\nauth\trequired\tpam_env.so\nauth\tsufficient\tpam_fprintd.so\nauth\trequired\tpam_unix.so\ttry_first_pass\n"
        const suseOff = "#%PAM-1.0\nauth\trequired\tpam_env.so\n# auth sufficient pam_fprintd.so\nauth\trequired\tpam_unix.so\n"
        T.eq(F.systemFingerprintPam(suse), true, "common-auth with pam_fprintd")
        T.eq(F.systemFingerprintPam(suseOff), false, "a commented line does not count")
        T.eq(F.systemFingerprintPam("auth [success=1 default=ignore] pam_fprintd.so\n"), true, "bracketed control")
        T.eq(F.systemFingerprintPam(""), null, "empty is not an answer")
        T.eq(F.parseSystemFingerprint("opensuse", suse, 0), true, "dispatch: openSUSE reads PAM")
        T.eq(F.parseSystemFingerprint("opensuse", suse, 1), null, "dispatch: a failed read is not an answer")
        T.eq(F.parseSystemFingerprint("fedora", withFp, 0), true, "dispatch: Fedora asks authselect")
        T.eq([F.systemFingerprintCommand("fedora"), F.systemFingerprintCommand("opensuse"), F.systemFingerprintCommand("arch"), F.systemFingerprintCommand("")],
             [["authselect", "current"], ["cat", "/etc/pam.d/common-auth"], ["cat", "/etc/pam.d/system-auth"], []], "the command per family")
        // Arch: system-auth as pambase ships it, and with the reader added by hand.
        const archOff = "#%PAM-1.0\nauth       required                    pam_faillock.so      preauth\nauth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok\n"
        const archOn = "#%PAM-1.0\nauth       sufficient                  pam_fprintd.so\n" + archOff.slice(10)
        T.eq(F.parseSystemFingerprint("arch", archOff, 0), false, "dispatch: Arch reads system-auth, reader off")
        T.eq(F.parseSystemFingerprint("arch", archOn, 0), true, "dispatch: Arch reads system-auth, reader on")
        // Arch's lock includes system-auth only: without the line there the
        // lock cannot offer the reader, and the page must not say it does.
        T.eq([F.pamLineMissing("arch", false), F.pamLineMissing("arch", true), F.pamLineMissing("arch", null),
              F.pamLineMissing("fedora", false), F.pamLineMissing("opensuse", false)],
             [true, false, false, false, false], "only a definite no on Arch is a missing line")
        T.ok(F.modeState("on", false, true).indexOf("not in PAM") >= 0, "on, but the reader is not in PAM")
        T.ok(F.modeState("auto", false, true).indexOf("not in PAM") >= 0, "automatic, the same")
        T.ok(F.modeState("off", false, true).indexOf("password only") >= 0, "off stays off")
        T.ok(F.modeState("on", false, false).indexOf("always offers") >= 0, "in PAM, the text is unchanged")
        // The line the page offers to copy is the one the check reads back.
        T.eq(F.systemFingerprintPam("#%PAM-1.0\n" + F.PAM_FPRINTD_LINE + "\n" + archOff.slice(10)), true,
             "the offered line is one the check recognises")

        T.finish("FingerprintTest")
    }
}
