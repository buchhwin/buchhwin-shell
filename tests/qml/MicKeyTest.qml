import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/audio/MicLogic.js" as M

// The microphone key mutes every microphone, and push to talk
// (services/audio/MicLogic.js).
ShellRoot {
    Component.onCompleted: {
        const mic = (name, muted) => ({ name: name, muted: muted })

        // A headset (the default) and the laptop's microphone, which an app
        // opened: the key used to mute the headset alone.
        let step = M.plan([mic("headset", false), mic("internal", false)], "headset", [])
        T.eq(step, { mute: true, changes: [{ name: "headset", muted: true }, { name: "internal", muted: true }],
                     remember: ["headset", "internal"] }, "both live: both go")
        step = M.plan([mic("headset", true), mic("internal", true)], "headset", step.remember)
        T.eq(step, { mute: false, changes: [{ name: "headset", muted: false }, { name: "internal", muted: false }],
                     remember: [] }, "pressed again: the two it muted come back")

        // The default muted by hand, the other live: the key still mutes,
        // and never turns on one that was muted before it.
        step = M.plan([mic("headset", true), mic("internal", false)], "headset", [])
        T.eq([step.mute, step.changes, step.remember], [true, [{ name: "internal", muted: true }], ["internal"]],
             "any live microphone: the press mutes")
        step = M.plan([mic("headset", true), mic("internal", true)], "headset", step.remember)
        T.eq(step.changes, [{ name: "headset", muted: false }, { name: "internal", muted: false }],
             "back: the one it muted and the default, which is the one meant for talking")
        step = M.plan([mic("headset", true), mic("internal", true), mic("usb", true)], "headset", ["internal"])
        T.eq(step.changes.map(change => change.name), ["headset", "internal"], "a microphone muted before stays muted")

        // A microphone whose state is not known yet counts as live.
        T.eq(M.plan([mic("headset", true), { name: "internal" }], "headset", []).mute, true, "unknown is live")
        // A remembered one that is gone, nameless entries, nothing at all.
        T.eq(M.plan([mic("headset", true)], "headset", ["unplugged"]).changes, [{ name: "headset", muted: false }],
             "a remembered microphone that is gone is skipped")
        T.eq(M.plan([null, { name: "" }, mic("a", false)], "a", null).changes, [{ name: "a", muted: true }], "nameless ones skipped")
        T.eq(M.plan([], "", []), { mute: false, changes: [], remember: [] }, "no microphones")

        // What the OSD says: the plain microphone display with one; with
        // more, that every one is off, or how many came back.
        T.eq([M.message(true, 0, 1), M.message(true, 0, 2), M.message(true, 0, 3)],
             ["", "All microphones muted", "All microphones muted"], "muted")
        T.eq([M.message(false, 1, 2), M.message(false, 2, 2), M.message(false, 3, 3)],
             ["", "2 microphones on", "3 microphones on"], "back on")
        // The OSD holds a press's message over the default input's mute
        // arriving after it; a press with none lets the plain display through,
        // even right after "All microphones muted".
        T.eq([M.messageHold("All microphones muted", 1000, 1400), M.messageHold("", 1000, 1400), M.messageHold(undefined, 1000, 1400)],
             [2400, 0, 0], "how long a message holds the microphone's display back")

        // Push to talk: on while held, back the way it was when let go.
        let talk = M.talkStep({ talking: false }, true, true)
        T.eq([talk.state, talk.set], [{ talking: true, restore: true }, false], "held with a muted microphone: on")
        // Pressed again while held: the release was never heard (Super let go
        // first), so this ends the hold the way the release would have.
        const again = M.talkStep(talk.state, true, false)
        T.eq([again.state.talking, again.set], [false, true], "a press while held ends the hold: muted again")
        talk = M.talkStep(talk.state, false, false)
        T.eq([talk.state.talking, talk.set], [false, true], "let go: muted again")
        talk = M.talkStep({ talking: false }, true, false)
        T.eq([talk.state.restore, talk.set], [false, null], "held with a live microphone: nothing to do")
        T.eq(M.talkStep(talk.state, false, false).set, null, "and let go: it stays on - a key pressed by mistake never mutes")
        T.eq(M.talkStep(talk.state, true, false), { state: { talking: false, restore: false }, set: null },
             "nor pressed again while held")
        T.eq(M.talkStep({ talking: false }, false, true).set, null, "a release without a press does nothing")
        T.eq(M.talkStep(null, false, true), { state: { talking: false, restore: false }, set: null }, "no state")
        T.eq(M.TALK_LIMIT_MS, 300000, "five minutes at most")

        T.finish("MicKeyTest")
    }
}
