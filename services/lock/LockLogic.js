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
// lockout keeps a message, because the shake cannot explain a wait: PAM's
// own MaxTries, or `notice`, what a lockout module said during the attempt
// (`lockoutNotice`).
function afterPam(result, results, notice) {
    if (result === results.Success) return { action: "unlock", text: "", shake: false }
    if (result === results.MaxTries) return { action: "message", text: "Too many attempts. Try again in a moment.", shake: true }
    if (notice) return { action: "message", text: String(notice), shake: true }
    return { action: "retry", text: "", shake: true }
}

// pam_faillock (in Arch's system-auth, which the lock includes there) answers
// a locked account with "The account is locked due to 3 failed logins." and
// "(9 minutes left to unlock)", then fails like a wrong password - and the
// right password went on failing with nothing but a shake for ten minutes.
// Those messages are kept; anything else PAM says in passing is not.
function lockoutNotice(messages) {
    return (messages || []).map(function (m) { return String(m).trim() })
        .filter(function (m) { return /lock/i.test(m) }).join(" ")
}

// The typed password is drawn on one screen only. Every screen's lock surface
// shares one buffer and one PAM conversation (LockScreen), and the field used
// to draw that buffer everywhere: typing on one monitor put the password's
// length on all of them. The screen that draws it is the one whose surface has
// the keyboard, since that is where the keys arrive. `inputScreenAfter`
// follows the surfaces as they gain the keyboard or receive a key (`gained`
// true for both). Losing the keyboard moves nothing - the next surface to gain
// it does - so a moment in which no surface holds it neither hides the dots
// nor spreads them to every screen again.
function inputScreenAfter(current, screenName, gained) {
    var name = String(screenName || "")
    return gained === true && name.length ? name : String(current || "")
}

// Whether `screenName` draws what is typed: the dots, the submit arrow and the
// shake. Every other screen shows the empty field ("Enter password", or
// "Checking …" while PAM works), the calmer of the two choices: a hint naming
// the screen that takes the input would put words on every other monitor,
// where the empty field already says enough. Until a surface has reported the
// keyboard every screen draws, as before - with nothing typed yet that is the
// empty field.
function showsInput(screenName, inputScreen) {
    var input = String(inputScreen || "")
    return !input.length || String(screenName || "") === input
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

// The lock screen's own process: lock.qml names itself with
// `//@ pragma ShellId buchhwin-shell-lock` (LockTest checks that the two
// agree). The lock face reads PowerService, and PowerService used to ask
// IdleService whether this is the real session - which started a second
// IdleService in the lock process, with its own before-sleep swayidle, lid
// inhibitor and lid-at-start check. That check disabled or blanked the laptop
// panel when the lock started with the lid shut, and the shell's own
// DisplayService never knew to turn it back on (16.10. review). The session's
// services stay inert in this process; the lock only displays.
var LOCK_SHELL_ID = "buchhwin-shell-lock"

// The shell id of this process: from the Quickshell singleton, or an id as
// such. `Quickshell.shellId` came with Quickshell 0.3, and Fedora packages a
// 0.2.1 snapshot: there it is undefined, and the lock's process read as the
// session's - its services did what they keep to the session, a notification
// server beside the shell's, settings writes, weather requests. The shell's
// cache directory names the same id on every version
// (`…/quickshell/by-shell/<id>`, or what a CacheDir pragma says - lock.qml
// and shell.qml set none), so 0.2.1 reads it from there.
function shellIdOf(shell) {
    if (shell === undefined || shell === null || typeof shell !== "object") return String(shell || "")
    if (shell.shellId !== undefined) return String(shell.shellId || "")
    var match = /\/by-shell\/([^/]+)\/*$/.exec(String(shell.cacheDir || ""))
    return match ? match[1] : ""
}

function lockProcess(shell) {
    return shellIdOf(shell) === LOCK_SHELL_ID
}

// The test hooks - a PAM fixture instead of the real service, the lid
// override, the preview windows instead of a session lock - need more than
// BUCHHWIN_NESTED=1. A flag can leak into a real session's environment (the
// user manager's, or a shell restarted from a terminal set up for nested
// tests), and a lock that then took test-permit would accept any password
// without a word. The lock directory says who started it:
// scripts/session-action.sh names it `…/lock` for the real session and
// `…/lock-nested` for a nested one, so a directory that is not the nested
// one refuses the hooks. So does none at all: a same-user process that ended
// the real lock (Hyprland stays locked and lets a new lock client take over)
// could start `BUCHHWIN_NESTED=1 quickshell -p lock.qml` with test-permit and
// unlock with any input. A lock started by hand for nested screenshots
// passes BUCHHWIN_LOCK_DIR=…/lock-nested.
function testHooksAllowed(nested, lockDir) {
    if (nested !== true) return false
    return /\/lock-nested\/?$/.test(String(lockDir || ""))
}

// Only nested test sessions may use the test PAM services (tests/fixtures/pam).
// `hooks` is testHooksAllowed.
var TEST_SERVICES = ["test-permit", "test-deny", "test-fingerprint", "test-password", "test-fingerprint-late"]

function pamService(hooks, requested) {
    if (hooks === true && TEST_SERVICES.indexOf(requested) >= 0) return requested
    return "buchhwin-lock"
}

// Service for a password-only conversation, without pam_fprintd. It is used
// when the password is submitted while the fingerprint reader still blocks the
// prompt. `installed`: /etc/pam.d/buchhwin-lock-password exists; without it
// the main service is kept (the password is checked after the reader gives up).
// The nested fixture test-fingerprint pairs with test-permit, and
// test-fingerprint-late with test-password.
function passwordService(service, installed) {
    if (service === "buchhwin-lock") return installed ? "buchhwin-lock-password" : "buchhwin-lock"
    if (service === "test-fingerprint") return "test-permit"
    if (service === "test-fingerprint-late") return "test-password"
    return service
}

// A password submitted before the conversation had said anything waits to be
// asked for (`pending`). When the reader then announces itself instead, the
// password prompt would only come after the reader gives up - pam_fprintd
// waits 30 s for a finger, with every key dropped meanwhile. pam_fprintd
// speaks ~0.6 s after a conversation starts, and one starts 1 s after every
// rejected attempt, so a quick retry after a typo landed in that gap. The
// password then goes the password-only way at once, as it does when it is
// submitted while the reader waits - when there is such a service.
function passwordInstead(stage, pending, service, passwordOnlyService) {
    return stage === true && pending === true && passwordOnlyService !== service
}

// Whether the fastfetch logo (the `logo` object of the shell's
// fastfetch.jsonc) can be a picture, which the lock shows as the avatar.
// Only scripts/fastfetch-image.py can say for certain - with no type
// ("auto") fastfetch decides by what the file holds - and asking it costs a
// Python start at every lock (~76 ms) for an answer the configuration often
// gives itself: no source, a named logo, a text one (the buchhwin profile's
// saturn.txt) or a .txt file is no picture. The types as logo_kind reads them.
var LOGO_NAMED_TYPES = ["builtin", "small", "none"]
var LOGO_TEXT_TYPES = ["file", "file-raw", "data", "data-raw"]
var LOGO_IMAGE_TYPES = ["kitty", "kitty-direct", "kitty-icat", "sixel", "iterm", "chafa", "raw"]

function logoMayBePicture(logo) {
    if (!logo || typeof logo !== "object") return false
    var source = typeof logo.source === "string" ? logo.source : ""
    var type = typeof logo.type === "string" && logo.type.length ? logo.type.toLowerCase() : "auto"
    if (!source.length || LOGO_NAMED_TYPES.indexOf(type) >= 0 || LOGO_TEXT_TYPES.indexOf(type) >= 0) return false
    if (LOGO_IMAGE_TYPES.indexOf(type) >= 0) return true
    return !/\.txt$/i.test(source)
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
// (read UPower). Ignored without the test hooks (`hooks`, testHooksAllowed).
function lidOverride(hooks, value) {
    if (hooks !== true) return null
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
    return service === "buchhwin-lock" || service === "buchhwin-lock-password" || service === "buchhwin-lock-key"
}

// Security key unlock (setting lock.securityKey): "auto" asks a plugged-in
// key first, "off" never. Unknown modes count as "auto".
var SECURITY_KEY_MODES = ["auto", "off"]
// The nested fixtures for the key's conversation: test-key asks a PIN
// ("lock-test-pin") and a touch, test-key-absent ends at once, as pam_u2f
// does without a key, and test-key-error ends as a system error.
var KEY_TEST_SERVICES = ["test-key", "test-key-absent", "test-key-error"]

// The key's own service (pam_u2f, session/pam/buchhwin-lock-key) or "": off,
// not installed by scripts/security-key.py, or a test lock without a key
// fixture. `requested` counts only with the test hooks.
function keyService(hooks, requested, installed, mode) {
    if (mode === "off") return ""
    if (hooks === true) return KEY_TEST_SERVICES.indexOf(requested) >= 0 ? requested : ""
    return installed === true ? "buchhwin-lock-key" : ""
}

// Whether a start begins with the key's conversation: there is one, the lock
// has not used its turn (the first start, or a click on "Use security key"),
// and no password is waiting to be checked - a password already sent never
// meets the key's PIN prompt.
function startsWithKey(service, turn, pending) {
    return String(service || "").length > 0 && turn === true && pending !== true
}

// A message of the key's conversation. pam_u2f asks for the PIN only once it
// found a key holding one of the user's credentials ("Please enter the PIN:
// ", the one prompt in that service), then says "Please touch the FIDO
// authenticator." (cue).
//   pin   – the PIN is asked
//   touch – the key waits for a touch
//   ""    – anything else
function keyEvent(message, responseRequired) {
    if (responseRequired === true) return "pin"
    return /touch|authenticator|security key/i.test(String(message || "")) ? "touch" : ""
}

// What the end of the key's conversation leads to.
//   unlock  – the key took
//   next    – it asked nothing (no key plugged in): the usual start, at once
//   refused – the PIN was asked and the key said no (a wrong PIN, no touch):
//             say so, then the usual start a moment later
// `manual`: the user asked for the key, so "no key" is said in words.
function afterKey(success, asked, manual) {
    if (success === true) return { action: "unlock", text: "" }
    if (asked === true) return { action: "refused", text: "The security key did not unlock. Enter your password." }
    return { action: "next", text: manual === true ? "No security key found" : "" }
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
