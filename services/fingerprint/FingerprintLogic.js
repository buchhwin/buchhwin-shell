.pragma library

// Fingerprint reader (fprintd) helpers for services/FingerprintService.qml.
// Parses the output of fprintd-list, fprintd-enroll and fprintd-delete.
// Unit tested in tests/qml/FingerprintTest.qml.

// fprintd finger names in the order a selector shows them.
var FINGERS = [
    { value: "right-index-finger", label: "Right index finger" },
    { value: "right-thumb", label: "Right thumb" },
    { value: "right-middle-finger", label: "Right middle finger" },
    { value: "right-ring-finger", label: "Right ring finger" },
    { value: "right-little-finger", label: "Right little finger" },
    { value: "left-index-finger", label: "Left index finger" },
    { value: "left-thumb", label: "Left thumb" },
    { value: "left-middle-finger", label: "Left middle finger" },
    { value: "left-ring-finger", label: "Left ring finger" },
    { value: "left-little-finger", label: "Left little finger" }
]

var DEFAULT_FINGER = "right-index-finger"

function validFinger(name) {
    return FINGERS.some(function (finger) { return finger.value === name })
}

function fingerLabel(name) {
    var found = FINGERS.find(function (finger) { return finger.value === name })
    return found ? found.label : String(name || "")
}

// Selector options; enrolled fingers are marked.
function fingerOptions(enrolled) {
    var taken = enrolled || []
    return FINGERS.map(function (finger) {
        return { value: finger.value, label: finger.label + (taken.indexOf(finger.value) >= 0 ? " (enrolled)" : "") }
    })
}

// The right index finger unless it is enrolled, then the first free finger.
function defaultFinger(enrolled) {
    var taken = enrolled || []
    if (taken.indexOf(DEFAULT_FINGER) < 0) return DEFAULT_FINGER
    var free = FINGERS.find(function (finger) { return taken.indexOf(finger.value) < 0 })
    return free ? free.value : DEFAULT_FINGER
}

// Short, friendly text for D-Bus errors printed by the fprintd tools.
function errorText(line) {
    var text = String(line || "")
    if (/PermissionDenied|Not Authorized|NotAuthorized|AccessDenied/i.test(text))
        return "Permission was denied. Confirm the password dialog to change fingerprints."
    if (/AlreadyInUse|already claimed/i.test(text))
        return "The fingerprint reader is busy. Close other fingerprint apps and try again."
    if (/NoSuchDevice|No devices available/i.test(text))
        return "No fingerprint reader found"
    if (/NoEnrolledPrints|No fingerprints to delete/i.test(text))
        return "No fingerprints to delete"
    if (/AlreadyEnrolled|already enrolled/i.test(text))
        return "This finger is already enrolled. Delete it first."
    if (/ServiceUnknown|Failed to get Fprintd manager|was not provided by any/i.test(text))
        return "The fingerprint service (fprintd) is not available"
    if (/Invalid finger name/i.test(text))
        return "Unknown finger"
    return ""
}

// fprintd-list USER (stdout and stderr) → reader state.
//   known      – output was parsed (false while nothing ran yet)
//   available  – a reader exists
//   installed  – fprintd-list could be started (exit 127 → false)
function parseList(text, exitCode) {
    var result = { known: text !== undefined && text !== null, installed: exitCode !== 127, available: false,
                   device: "", devicePath: "", scanType: "", fingers: [], error: "" }
    if (!result.installed) { result.error = "Fingerprint support (fprintd) is not installed"; return result }
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        var match
        if ((match = /^Using device (\S+)/.exec(line))) {
            result.devicePath = match[1]
            result.available = true
        } else if ((match = /^Fingerprints for user \S+ on (.+) \((\w+)\):$/.exec(line))) {
            result.device = match[1]
            result.scanType = match[2]
            result.available = true
        } else if ((match = /^User \S+ has no fingers enrolled for (.+)\.$/.exec(line))) {
            result.device = match[1]
            result.available = true
        } else if ((match = /^- #\d+: (\S+)$/.exec(line))) {
            if (validFinger(match[1]) && result.fingers.indexOf(match[1]) < 0) result.fingers.push(match[1])
        } else if (/^No devices available/.test(line)) {
            result.available = false
        } else if (/failed|Impossible|error/i.test(line) && !result.error.length) {
            result.error = errorText(line) || line
        }
    }
    if (!result.available && !result.error.length && result.known && exitCode !== 0 && lines.join("").trim().length === 0)
        result.error = "Could not read the fingerprint reader"
    return result
}

// `busctl get-property … num-enroll-stages scan-type` → { stages, scanType }.
function parseProperties(text) {
    var result = { stages: 0, scanType: "" }
    String(text || "").split("\n").forEach(function (line) {
        var number = /^i\s+(-?\d+)/.exec(line.trim())
        var word = /^s\s+"([^"]*)"/.exec(line.trim())
        if (number) result.stages = Math.max(0, parseInt(number[1], 10))
        else if (word && !result.scanType.length) result.scanType = word[1]
    })
    return result
}

// Enrollment results from `fprintd-enroll` ("Enroll result: NAME").
//   kind: progress (a stage passed), retry (scan again), done, failed
var RESULTS = {
    "enroll-stage-passed": { kind: "progress" },
    "enroll-completed": { kind: "done", text: "Fingerprint enrolled" },
    "enroll-retry-scan": { kind: "retry", text: "That didn't work. Place your finger again." },
    "enroll-swipe-too-short": { kind: "retry", text: "Swipe was too short. Try again." },
    "enroll-too-short": { kind: "retry", text: "Touch was too short. Try again." },
    "enroll-finger-not-centered": { kind: "retry", text: "Center your finger on the reader and try again." },
    "enroll-remove-and-retry": { kind: "retry", text: "Lift your finger, then place it again." },
    "enroll-duplicate": { kind: "failed", text: "This fingerprint is already enrolled." },
    "enroll-failed": { kind: "failed", text: "Enrollment failed. Try again." },
    "enroll-data-full": { kind: "failed", text: "The reader's storage is full. Delete a fingerprint first." },
    "enroll-disconnected": { kind: "failed", text: "The fingerprint reader was disconnected." },
    "enroll-unknown-error": { kind: "failed", text: "The reader reported an error. Try again." }
}

function placeText(scanType) {
    return scanType === "swipe" ? "Swipe your finger across the reader" : "Place your finger on the reader"
}

function stageText(scanType, stage, stages) {
    var count = stages > 0 ? " (" + Math.min(stage, stages) + " of " + stages + ")" : " (" + stage + ")"
    return (scanType === "swipe" ? "Swipe your finger again" : "Lift and place your finger again") + count
}

// A fresh enrollment state.
function enrollStart(finger, stages, scanType) {
    return { finger: finger, stages: stages > 0 ? stages : 0, scanType: scanType || "press", phase: "starting",
             stage: 0, retries: 0, message: "Confirm with your password if asked, then " + placeText(scanType).toLowerCase(),
             error: false, finished: false, success: false }
}

function copy(state) {
    var next = {}
    for (var key in state) next[key] = state[key]
    return next
}

// Folds one output line of fprintd-enroll into the state.
function enrollLine(state, line) {
    var text = String(line || "").trim()
    if (!text.length || state.finished) return state
    var next = copy(state)
    var match = /^Enroll result: (\S+)/.exec(text)
    if (match) {
        var info = RESULTS[match[1]]
        if (!info) return next
        if (info.kind === "progress") {
            next.phase = "scanning"
            next.stage = state.stage + 1
            next.error = false
            next.message = stageText(state.scanType, next.stage, state.stages)
        } else if (info.kind === "retry") {
            next.phase = "scanning"
            next.retries = state.retries + 1
            next.error = false
            next.message = info.text
        } else if (info.kind === "done") {
            next.phase = "done"
            next.stage = Math.max(state.stage, state.stages)
            next.finished = true
            next.success = true
            next.error = false
            next.message = "Enrolled. This finger now unlocks the lock screen."
        } else {
            next.phase = "failed"
            next.finished = true
            next.error = true
            next.message = info.text
        }
        return next
    }
    // Printed before EnrollStart, which may still wait for the polkit dialog:
    // the starting hint stays until the first result.
    if (/^Enrolling \S+ finger\.?$/.test(text)) {
        next.phase = "scanning"
        return next
    }
    if (/failed|Impossible|Invalid finger|couldn't|error/i.test(text)) {
        next.phase = "failed"
        next.finished = true
        next.error = true
        next.message = errorText(text) || "Enrollment failed: " + text
    }
    return next
}

// Folds a whole output (several lines) into a fresh state.
function enrollOutput(text, finger, stages, scanType) {
    var state = enrollStart(finger, stages, scanType)
    String(text || "").split("\n").forEach(function (line) { state = enrollLine(state, line) })
    return state
}

// The process ended: keep a result, otherwise explain the exit.
function enrollExited(state, exitCode, cancelled) {
    if (state.finished) return state
    var next = copy(state)
    next.finished = true
    if (cancelled) {
        next.phase = "cancelled"
        next.error = false
        next.message = "Enrollment canceled"
    } else {
        next.phase = "failed"
        next.error = true
        next.message = exitCode === 127 ? "Fingerprint support (fprintd) is not installed"
            : "Enrollment stopped" + (exitCode ? " (exit code " + exitCode + ")" : "")
    }
    return next
}

// 0…1 for progress bars.
function progress(state) {
    if (!state) return 0
    if (state.success) return 1
    return state.stages > 0 ? Math.min(1, state.stage / state.stages) : 0
}

// fprintd-delete USER -f FINGER (stdout and stderr) → { ok, message }.
function parseDelete(text, exitCode, finger) {
    var output = String(text || "")
    var label = fingerLabel(finger)
    if (/deleted on/.test(output) && exitCode === 0) return { ok: true, message: label + " deleted" }
    var line = output.split("\n").map(function (l) { return l.trim() })
        .filter(function (l) { return /failed|Impossible|No fingerprints|error/i.test(l) })[0] || ""
    if (exitCode === 127) return { ok: false, message: "Fingerprint support (fprintd) is not installed" }
    return { ok: false, message: "Could not delete " + label.toLowerCase() + (line.length ? ": " + (errorText(line) || line) : "") }
}

// Unlock mode (lock.fingerprint, see LockLogic.fingerprintEnabled) as a short
// status for the control center tile.
function modeLabel(mode, lidClosed) {
    if (mode === "on") return "On"
    if (mode === "off") return "Off"
    return lidClosed === true ? "Automatic · lid closed" : "Automatic"
}

// What the lock screen does right now, for Settings > Lock Screen.
// `pamMissing` (pamLineMissing below): the reader is in no PAM stack the lock
// goes through, so no mode can offer it - saying "always offers the
// fingerprint first" there was the page contradicting the lock.
function modeState(mode, lidClosed, pamMissing) {
    if (mode === "off") return "The lock screen asks for your password only."
    if (pamMissing === true) return "The reader is not in PAM yet, so the lock screen asks for your password only."
    if (mode === "on") return "The lock screen always offers the fingerprint first."
    return lidClosed === true ? "Off right now because the lid is closed."
        : "On right now because the lid is open."
}

// argv for the fprintd tools; null for invalid input.
function enrollCommand(finger) {
    return validFinger(finger) ? ["stdbuf", "-oL", "-eL", "fprintd-enroll", "-f", finger] : null
}

function deleteCommand(user, finger) {
    return validFinger(finger) && /^[A-Za-z0-9._-]+$/.test(String(user || "")) ? ["fprintd-delete", user, "-f", finger] : null
}

function listCommand(user) {
    return /^[A-Za-z0-9._-]+$/.test(String(user || "")) ? ["sh", "-c", "exec fprintd-list \"$1\" 2>&1", "sh", user] : null
}

// Whether the reader is wired into PAM for the *whole system*, from
// `authselect current`.
//
// This is the difference between two things a user cannot tell apart from the
// outside. `lock.fingerprint` is the shell's own setting and governs the lock
// screen only: with it off, lock.qml authenticates through
// `buchhwin-lock-password`, which includes Fedora's `password-auth` and has no
// pam_fprintd in it. But `authselect` puts `pam_fprintd` into `system-auth`
// when the `with-fingerprint` feature is on, and the login screen, sudo and
// every polkit dialog go through *that* - so they keep asking for a finger
// however the shell is set.
//
// Turning it off everywhere is one host command and needs the user's word, so
// the page states the situation instead of acting on it.
function systemFingerprint(output, exitCode) {
    if (Number(exitCode) !== 0) return null
    const text = String(output || "")
    if (!/Profile ID:/.test(text)) return null
    return /^\s*-\s*with-fingerprint\s*$/m.test(text)
}

// The same question on openSUSE, which has no authselect: pam-config writes
// pam_fprintd straight into /etc/pam.d/common-auth, so an active `auth` line
// naming it is the answer. Comments do not count. Arch has neither tool; its
// PAM files are read the same way (below).
function systemFingerprintPam(text) {
    if (typeof text !== "string" || !/^\s*auth\s/m.test(text)) return null
    return /^\s*auth\s[^#\n]*\bpam_fprintd\.so\b/m.test(text)
}

// Arch: the reader belongs to the lock's own PAM file, not to system-auth.
// /etc/pam.d/sddm (through system-login), sudo and polkit all include
// system-auth there, so pam_fprintd in it makes the login screen and sudo wait
// for a finger first - and a finger login at SDDM gives pam_kwallet5 and
// pam_gnome_keyring no password, the wallets stay shut and Brave refuses.
// Above the `include system-auth` of /etc/pam.d/buchhwin-lock only the lock
// offers it, and buchhwin-lock-password (mode off, lid closed) stays
// password-only. A line in system-auth still counts: someone may have put it
// there by hand. Both files are read in one call; `grep -H` prefixes every
// line with its file, which keeps the two answers apart. The command that
// adds the line is DistroLogic.fingerprintOnCommand.
var ARCH_LOCK_PAM = "/etc/pam.d/buchhwin-lock"
var ARCH_SYSTEM_PAM = "/etc/pam.d/system-auth"

// grep's exit status for that read: 0 a line was found, 1 none (both files
// empty), 2 a file could not be read - on Arch before install/system-install.sh
// that is the lock's own file, and system-auth was read all the same. Each
// file is judged from its own lines, so 2 is half an answer, not none.
// Anything else (127: no grep) is no read at all.
function pamRead(exitCode) {
    const code = Number(exitCode)
    return code === 0 || code === 1 || code === 2
}

// `grep -H "" FILE…` split back into one text per file.
function pamFiles(output) {
    const files = {}
    String(output || "").split("\n").forEach(function (line) {
        const at = line.indexOf(":")
        if (at <= 0) return
        const path = line.slice(0, at)
        files[path] = (files[path] || "") + line.slice(at + 1) + "\n"
    })
    return files
}

// Until the line is in one of the two files the reader is offered nowhere on
// Arch, the lock screen included, whatever its mode says, and the page shows
// the command that adds it. `lockEnabled` is parseLockFingerprint's answer;
// only a definite "no" counts (null is "not known yet"). Fedora and openSUSE
// turn the reader on with their own tools and keep their texts.
function pamLineMissing(family, lockEnabled) {
    return family === "arch" && lockEnabled === false
}

// The read-only command that answers both questions below, per distribution
// family.
function systemFingerprintCommand(family) {
    if (family === "fedora") return ["authselect", "current"]
    if (family === "opensuse") return ["cat", "/etc/pam.d/common-auth"]
    if (family === "arch") return ["grep", "-H", "", ARCH_LOCK_PAM, ARCH_SYSTEM_PAM]
    return []
}

// Whether the reader is on for the whole system - the login screen, sudo,
// polkit: authselect's feature, common-auth, Arch's system-auth.
function parseSystemFingerprint(family, output, exitCode) {
    if (family === "arch") return pamRead(exitCode) ? systemFingerprintPam(pamFiles(output)[ARCH_SYSTEM_PAM]) : null
    if (family === "opensuse") return Number(exitCode) === 0 ? systemFingerprintPam(String(output || "")) : null
    return systemFingerprint(output, exitCode)
}

// Whether the PAM stack the lock goes through offers it. Fedora's and
// openSUSE's lock includes the system stack, so the answer is the same; on
// Arch the lock's own file counts too, and a definite no needs both files.
// Without the lock's file (grep's 2 and none of its lines) PAM runs the lock
// through /etc/pam.d/other, which is pam_deny on Arch and includes nothing -
// not system-auth either, so no line anywhere gives the lock a reader. Only
// when neither file was read is there nothing to say.
function parseLockFingerprint(family, output, exitCode) {
    if (family !== "arch") return parseSystemFingerprint(family, output, exitCode)
    if (!pamRead(exitCode)) return null
    const files = pamFiles(output)
    if (Number(exitCode) === 2 && files[ARCH_LOCK_PAM] === undefined)
        return files[ARCH_SYSTEM_PAM] === undefined ? null : false
    const lock = systemFingerprintPam(files[ARCH_LOCK_PAM])
    const system = systemFingerprintPam(files[ARCH_SYSTEM_PAM])
    if (lock === true || system === true) return true
    return lock === false && system === false ? false : null
}
