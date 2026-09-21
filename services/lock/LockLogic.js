.pragma library

// Lock screen helpers (shell/lock/). Unit tested in tests/qml/LockTest.qml.

// Full name from a passwd line (GECOS field before the first comma), else the login.
function displayName(passwdLine, login) {
    var fields = String(passwdLine || "").trim().split(":")
    var gecos = fields.length > 4 ? fields[4].split(",")[0].trim() : ""
    return gecos.length ? gecos : String(login || "")
}

function initial(name) {
    var first = Array.from(String(name || "").trim())[0]
    return first ? first.toUpperCase() : "?"
}

// What to do when a PAM conversation ends. PamResult values are passed in so
// the logic stays independent of the QML enum.
//   unlock  – authenticated
//   retry   – rejected: clear and start a new conversation
//   message – show `text`, restart after a pause
// A rejected password says so by shaking, never in words: "Authentication
// failed" under the field told the user nothing they did not just see. Only a
// lockout keeps a message, because the shake cannot explain a wait.
function afterPam(result, results) {
    if (result === results.Success) return { action: "unlock", text: "", shake: false }
    if (result === results.MaxTries) return { action: "message", text: "Too many attempts. Try again in a moment.", shake: true }
    return { action: "retry", text: "", shake: true }
}

// Caps Lock and the active keyboard layout from `hyprctl -j devices`.
function keyboardState(json) {
    var data
    try { data = typeof json === "string" ? JSON.parse(json) : json } catch (error) { return { capsLock: false, layout: "" } }
    var keyboards = data && Array.isArray(data.keyboards) ? data.keyboards : []
    var main = keyboards.find(function (k) { return k.main }) || keyboards[0] || null
    return {
        capsLock: keyboards.some(function (k) { return k.capsLock === true }),
        layout: main ? shortLayout(main.active_keymap || main.layout || "") : ""
    }
}

// "German" → "DE", "English (US)" → "US", "de" → "DE".
function shortLayout(keymap) {
    var text = String(keymap || "").trim()
    var paren = /\(([A-Za-z]{2,3})\)/.exec(text)
    if (paren) return paren[1].toUpperCase()
    var known = { german: "DE", english: "EN", french: "FR", spanish: "ES", italian: "IT", dutch: "NL", polish: "PL", swiss: "CH", austrian: "AT" }
    var first = text.split(/[\s(,]/)[0].toLowerCase()
    if (known[first]) return known[first]
    return text.length <= 3 ? text.toUpperCase() : text.slice(0, 2).toUpperCase()
}

// Only nested test sessions may use the test PAM services (tests/fixtures/pam).
var TEST_SERVICES = ["test-permit", "test-deny", "test-fingerprint"]

function pamService(nested, requested) {
    if (nested && TEST_SERVICES.indexOf(requested) >= 0) return requested
    return "buchhwin-lock"
}

// Service for a password-only conversation, without pam_fprintd. It is used
// when the password is submitted while the fingerprint reader still blocks the
// prompt. `installed`: /etc/pam.d/buchhwin-lock-password exists; without it
// the main service is kept (the password is checked after the reader gives up).
// The nested fixture test-fingerprint pairs with test-permit.
function passwordService(service, installed) {
    if (service === "buchhwin-lock") return installed ? "buchhwin-lock-password" : "buchhwin-lock"
    if (service === "test-fingerprint") return "test-permit"
    return service
}

// Fingerprint unlock mode (setting lock.fingerprint): "auto" offers the reader
// only while the lid is open (closed on a dock, the sensor is out of reach),
// "on" always, "off" never. Unknown modes count as "auto".
var FINGERPRINT_MODES = ["auto", "on", "off"]

function fingerprintEnabled(mode, lidClosed) {
    if (mode === "off") return false
    if (mode === "on") return true
    return lidClosed !== true
}

// `busctl get-property org.freedesktop.UPower … LidIsClosed` prints "b true" or
// "b false". Errors, timeouts and missing UPower count as an open lid.
function parseLidClosed(output, exitCode) {
    return exitCode === 0 && /^b\s+true$/.test(String(output || "").trim())
}

// Nested test hook BUCHHWIN_LOCK_LID_CLOSED=1|0: true/false, otherwise null
// (read UPower). Ignored outside nested sessions.
function lidOverride(nested, value) {
    if (!nested) return null
    if (value === "1") return true
    if (value === "0") return false
    return null
}

// Whether the next conversation starts on the password-only service: when the
// fingerprint is disabled and that service differs from the main one (without
// /etc/pam.d/buchhwin-lock-password the main service stays).
function startPasswordOnly(fingerprintOn, service, passwordOnlyService) {
    return !fingerprintOn && passwordOnlyService !== service
}

// System services live in /etc/pam.d, test services in tests/fixtures/pam.
function systemService(service) {
    return service === "buchhwin-lock" || service === "buchhwin-lock-password"
}

// Classifies a PAM message from pam_fprintd (sent without a response).
//   prompt   – "Place your finger on …", "Swipe your finger across …"
//   retry    – bad scan, "… try again"
//   mismatch – "Failed to match fingerprint" (the reader keeps trying)
//   ended    – timeout or reader error; the password prompt follows
//   ""       – not a fingerprint message
// `inStage`: a fingerprint message came before (generic errors then count).
function fingerprintEvent(message, isError, responseRequired, inStage) {
    if (responseRequired) return ""
    var text = String(message || "").trim()
    if (!text.length) return ""
    if (/failed to match fingerprint/i.test(text)) return "mismatch"
    if (/verification timed out/i.test(text)) return "ended"
    if (/fprintd|finger verification/i.test(text)) return "ended"
    if (/\bagain\b|too (short|fast)|not centered/i.test(text) && /finger|swipe|scan|reader|sensor/i.test(text)) return "retry"
    if (/^(place|swipe|touch|put) your .*(finger|thumb)/i.test(text)) return "prompt"
    if (inStage && isError) return "ended"
    return ""
}

// Status line for a fingerprint event.
function fingerprintText(event, message) {
    if (event === "mismatch") return "Fingerprint not recognized. Try again or enter your password."
    if (event === "ended") return /timed out/i.test(message || "") ? "Fingerprint timed out. Enter your password."
        : "Fingerprint is unavailable. Enter your password."
    return String(message || "")
}
