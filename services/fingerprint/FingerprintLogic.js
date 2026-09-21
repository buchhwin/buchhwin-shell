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
        next.message = "Enrollment cancelled"
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
function modeState(mode, lidClosed) {
    if (mode === "off") return "The lock screen asks for your password only."
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
