.pragma library

// The microphone key and push to talk (AudioService).
//
// The key muted only the default input (`wpctl set-mute @DEFAULT_AUDIO_SOURCE@`):
// with a headset and the laptop's own microphone, an app that had opened the
// one that is not the default stayed live - in a call, the key the user
// trusts left a microphone open. It mutes every microphone now, and pressed
// again it turns back on the ones it muted (and the default one, which is the
// one the user means to talk into) - never one that was muted before.

// sources: [{ name, muted }] - every microphone (no monitors, no streams);
// a microphone whose state is not known yet counts as live, so a press never
// leaves one open for not knowing. `defaultName`: the default input's name.
// `remembered`: the names the last press muted.
// → { mute, changes: [{ name, muted }], remember }: `mute` true when any
// microphone is live (all of them go), false when all are muted already
// (the remembered ones and the default come back).
function plan(sources, defaultName, remembered) {
    const list = (sources || []).filter(source => source && String(source.name || "").length)
    const live = list.filter(source => source.muted !== true)
    if (live.length)
        return { mute: true, changes: live.map(source => ({ name: source.name, muted: true })),
                 remember: live.map(source => source.name) }
    const back = (remembered || []).map(String)
    const wanted = list.filter(source => back.indexOf(source.name) >= 0 || source.name === String(defaultName || ""))
    return { mute: false, changes: wanted.map(source => ({ name: source.name, muted: false })), remember: [] }
}

// What the OSD says after a press (Osd.qml), or "" for the plain microphone
// display: with one microphone the key does what it always did, and the
// OSD shows "Muted" as before. `total` is how many microphones there are,
// `changed` how many the press turned back on.
function message(muted, changed, total) {
    if (muted === true) return Number(total) > 1 ? "All microphones muted" : ""
    return Number(changed) > 1 ? Number(changed) + " microphones on" : ""
}

// Until when the OSD keeps a press's message over the default input's own
// mute change, which arrives a moment after it: a message's time on screen.
// A press with no message of its own (one microphone back on) holds nothing,
// and it ends the hold of the press before - "All microphones muted" must not
// stay up over a microphone that is on again.
function messageHold(text, now, timeout) {
    return String(text || "").length ? Number(now) + Number(timeout) : 0
}

// ---- push to talk --------------------------------------------------------------
// A key held turns the default microphone on, and letting go puts it back
// the way it was: muted again when the key had turned it on, left alone when
// it was on before. So a key pressed by mistake in a call never mutes the
// user, and one used with a muted microphone is push to talk.

// The longest hold that counts: a release the shell never hears (a lost key
// event, the session locked while the key was down) must not leave the
// microphone on for good. Five minutes is longer than anyone talks through
// a held key.
var TALK_LIMIT_MS = 5 * 60 * 1000

// state: { talking, restore } - `restore` whether the release mutes again.
// `down` the key's edge, `muted` the default microphone's state now.
// → { state, set }: `set` true to mute, false to unmute, null for nothing.
// A press while the key is held already ends the hold, as the release
// would have: one key cannot be pressed twice without being let go, so the
// shell missed that release (Super let go first, a bind that reports the
// press alone), and the microphone it left on is one press away from
// muted again, not five minutes.
function talkStep(state, down, muted) {
    const talking = !!(state && state.talking)
    if (down === true && !talking)
        return { state: { talking: true, restore: muted === true }, set: muted === true ? false : null }
    if (!talking) return { state: { talking: false, restore: false }, set: null }
    return { state: { talking: false, restore: false }, set: state.restore === true ? true : null }
}
