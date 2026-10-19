.pragma library

// Notification sounds (Settings > Notifications "Play a sound", off by
// default): one short sound for a popup that is shown, never for one held
// back by Do Not Disturb, a share or a fullscreen window, never when the
// sender asks for silence (the `suppress-sound` hint) or the app's sound is
// off. Played by pw-play (PipeWire's, in the package list) from the
// freedesktop sound theme. Unit tested (NotificationSoundTest).

var THEME_DIR = "/usr/share/sounds/freedesktop/stereo/"
// What the freedesktop theme (sound-theme-freedesktop) has; a name it does
// not have plays the default instead of nothing.
var THEME_SOUNDS = ["alarm-clock-elapsed", "audio-volume-change", "bell", "camera-shutter", "complete",
                    "device-added", "device-removed", "dialog-error", "dialog-information", "dialog-warning",
                    "message", "message-new-instant", "network-connectivity-established",
                    "network-connectivity-lost", "phone-incoming-call", "phone-outgoing-busy",
                    "phone-outgoing-calling", "power-plug", "power-unplug", "screen-capture", "service-login",
                    "service-logout", "suspend-error", "trash-empty", "window-attention", "window-question"]
var DEFAULT_SOUND = "message-new-instant"
var URGENT_SOUND = "dialog-warning"
// Files pw-play reads.
var AUDIO_FILE = /\.(oga|ogg|opus|wav|flac)$/i
// A burst of notifications (a chat catching up) is one sound.
var MIN_GAP_MS = 1500

// A hint that says yes: true, 1, "true", "1".
function yes(value) {
    return value === true || value === 1 || value === "1" || String(value).toLowerCase() === "true"
}

// The file a notification's sound is: the sender's own file when it is a
// local sound file, else the theme sound it names, else the default for its
// urgency. `hints` holds `sound-file`/`sound-name` as the server kept them.
// Unit tested.
function soundFile(hints, critical) {
    const it = hints || {}
    let file = String(it["sound-file"] || "")
    if (/^file:\/\//i.test(file)) {
        try { file = decodeURIComponent(file.replace(/^file:\/\//i, "")) } catch (error) { file = "" }
    }
    if (file.charAt(0) === "/" && file.indexOf("/../") < 0 && AUDIO_FILE.test(file)) return file
    const name = String(it["sound-name"] || "").trim()
    if (THEME_SOUNDS.indexOf(name) >= 0) return THEME_DIR + name + ".oga"
    return THEME_DIR + (critical ? URGENT_SOUND : DEFAULT_SOUND) + ".oga"
}

// Whether this notification plays its sound. `state`: `enabled` (the
// setting), `shown` (it became a popup), `suppressed` (Do Not Disturb or an
// automatic reason), `hints`, `appSound` (false for an app whose sound is
// off), `now` and `last` (ms; when the last sound played). Unit tested.
function wantsSound(state) {
    const it = state || {}
    if (it.enabled !== true || it.shown !== true || it.suppressed === true) return false
    if (it.appSound === false) return false
    if (yes((it.hints || {})["suppress-sound"])) return false
    return !(Number(it.last) > 0) || Number(it.now) - Number(it.last) >= MIN_GAP_MS
}

// The command that plays `file`, bounded so a stuck output never leaves it
// waiting.
function command(file) {
    return ["timeout", "10", "pw-play", "--volume", "0.8", String(file)]
}
