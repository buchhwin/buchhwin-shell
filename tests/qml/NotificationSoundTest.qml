import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/SoundLogic.js" as S

// Notification sounds (SoundLogic): which file plays, when one plays at all,
// and the command that plays it.
ShellRoot {
    Component.onCompleted: {
        const theme = S.THEME_DIR
        T.eq(S.soundFile({}, false), theme + "message-new-instant.oga", "the default")
        T.eq(S.soundFile(null, true), theme + "dialog-warning.oga", "an urgent one's")
        T.eq(S.soundFile({ "sound-name": "phone-incoming-call" }, false), theme + "phone-incoming-call.oga", "a theme name it has")
        T.eq(S.soundFile({ "sound-name": "../../etc/passwd" }, false), theme + "message-new-instant.oga", "a name it has not")
        T.eq(S.soundFile({ "sound-file": "/home/user/ding.ogg" }, false), "/home/user/ding.ogg", "the sender's own file")
        T.eq(S.soundFile({ "sound-file": "file:///home/user/My%20Ding.wav" }, false), "/home/user/My Ding.wav", "as a file url")
        T.eq(S.soundFile({ "sound-file": "/home/user/notes.txt" }, false), theme + "message-new-instant.oga", "not a sound file")
        T.eq(S.soundFile({ "sound-file": "relative.ogg" }, false), theme + "message-new-instant.oga", "not an absolute path")
        T.eq(S.soundFile({ "sound-file": "file:///bad%E0%A4%A.ogg" }, true), theme + "dialog-warning.oga", "a broken url")

        const base = { enabled: true, shown: true, suppressed: false, hints: {}, appSound: true, now: 10000, last: 0 }
        const with_ = change => Object.assign({}, base, change)
        T.eq(S.wantsSound(base), true, "a shown popup plays")
        T.eq(S.wantsSound(with_({ enabled: false })), false, "not with sounds off")
        T.eq(S.wantsSound(with_({ shown: false })), false, "not for one held back")
        T.eq(S.wantsSound(with_({ suppressed: true })), false, "not in Do Not Disturb or while muted, urgent or not")
        T.eq(S.wantsSound(with_({ appSound: false })), false, "not for an app whose sound is off")
        T.eq([S.wantsSound(with_({ hints: { "suppress-sound": true } })), S.wantsSound(with_({ hints: { "suppress-sound": "1" } })),
              S.wantsSound(with_({ hints: { "suppress-sound": false } }))], [false, false, true], "the sender's own silence")
        T.eq(S.wantsSound(with_({ last: 9000 })), false, "a burst is one sound")
        T.eq(S.wantsSound(with_({ last: 8500 })), true, "a moment later another")
        T.eq(S.wantsSound(null), false, "no state, no sound")

        T.eq(S.command("/x/y.oga"), ["timeout", "10", "pw-play", "--volume", "0.8", "/x/y.oga"], "pw-play, bounded")

        T.finish("NotificationSoundTest")
    }
}
