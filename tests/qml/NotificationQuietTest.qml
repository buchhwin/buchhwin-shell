import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/QuietLogic.js" as Q

// When popups keep quiet by themselves (QuietLogic): a portal share counted
// from PipeWire's nodes, a fullscreen Citrix desktop that holds nothing back,
// popups sent to another screen instead of being held, and the word about
// what came meanwhile.
ShellRoot {
    Component.onCompleted: {
        // Shares: xdph's video nodes by name; a webcam and audio are none.
        const nodes = [{ name: "alsa_output.pci-0000_00_1f.3.analog-stereo" }, { name: "v4l2_input.pci-0000_00_14.0-usb-0_6_1.0" },
                       { name: "xdph-streaming-0" }, { name: "Brave" }, { name: "xdph-streaming-3" }, null, {}]
        T.eq(Q.shareCount(nodes), 2, "two portal shares among the nodes")
        T.eq([Q.shareCount([]), Q.shareCount(null), Q.shareCount([{ name: "xdpw-stream-1" }])], [0, 0, 1],
             "none, nothing, and wlr's portal counts too")
        T.eq(Q.isShareNode({ name: "my-xdph-streaming" }), false, "only a name that starts with it")

        // Exceptions.
        T.eq(Q.classList(" Wfica, Example  other,"), ["wfica", "example", "other"], "commas, spaces, any case")
        T.eq([Q.isException("Wfica", "Wfica"), Q.isException("wfica", "WFICA"), Q.isException("mpv", "Wfica"),
              Q.isException("", "Wfica"), Q.isException("Wfica", "")],
             [true, true, false, false, false], "Citrix's window class is one, a player is not")

        // Where the popups go.
        const desk = [{ name: "DP-8", fullscreen: true }, { name: "DP-10", fullscreen: true }, { name: "DP-13", fullscreen: false }]
        T.eq(Q.popupScreen("DP-8", desk, true), "DP-13", "Citrix across the two big screens: the portrait one")
        T.eq(Q.popupScreen("DP-8", desk, false), "", "not with the setting off")
        T.eq(Q.popupScreen("DP-13", desk, true), "", "the focused screen without fullscreen keeps them")
        T.eq(Q.popupScreen("eDP-1", [{ name: "eDP-1", fullscreen: true }], true), "", "one screen: nowhere else to go")
        T.eq(Q.popupScreen("DP-8", [{ name: "DP-8", fullscreen: true }, { name: "DP-10", fullscreen: true }], true), "",
             "every screen covered: they stay")
        T.eq(Q.popupScreen("DP-1", desk, true), "", "a focused screen the list does not know keeps them")

        // Why it is quiet.
        const base = { suppressSharing: true, shares: 0, suppressGames: true, gameActive: false,
                       suppressFullscreen: true, fullscreenActive: false, appId: "", exceptions: "Wfica", elsewhere: false }
        const with_ = change => Object.assign({}, base, change)
        T.eq(Q.reason(base), "", "nothing going on")
        T.eq(Q.reason(with_({ shares: 1 })), "sharing", "a share")
        T.eq(Q.reason(with_({ shares: 1, suppressSharing: false })), "", "not with sharing's setting off")
        T.eq(Q.reason(with_({ gameActive: true })), "game", "a game in front")
        T.eq(Q.reason(with_({ fullscreenActive: true, appId: "mpv" })), "fullscreen", "a fullscreen film")
        T.eq(Q.reason(with_({ fullscreenActive: true, appId: "Wfica" })), "", "a fullscreen Citrix desktop holds nothing back")
        T.eq(Q.reason(with_({ fullscreenActive: true, appId: "mpv", elsewhere: true })), "",
             "popups sent to another screen are not held either")
        T.eq(Q.reason(with_({ fullscreenActive: true, appId: "steam_app_1", gameActive: true, elsewhere: true })), "game",
             "a game keeps them back on every screen")
        T.eq(Q.reason(with_({ fullscreenActive: true, suppressFullscreen: false })), "", "fullscreen's setting off")
        T.eq(Q.reason(with_({ shares: 2, gameActive: true })), "sharing", "sharing is said first")
        T.eq(Q.reason(null), "", "no state, no reason")
        T.eq(Q.reason(with_({ shares: 1, suppressSharing: "yes" })), "", "only a real true turns a setting on")

        // What came meanwhile.
        const one = Q.withMissed({}, 4)
        T.eq(one, { 4: true }, "one held back")
        T.ok(Q.withMissed(one, 4) === one, "the same one twice is the same table")
        T.eq(Q.withMissed(one, 7), { 4: true, 7: true }, "another")
        T.ok(Q.withMissed(one, undefined) === one, "no id, no change")
        const history = [{ id: 4 }, { id: 7 }, { id: 9 }]
        T.eq(Q.missedCount({ 4: true, 7: true, 8: true }, history, { 4: true, 7: true, 9: true }), 2,
             "the held ones still in the history and unread")
        T.eq(Q.missedCount({ 4: true, 7: true }, history, { 7: true }), 1, "one read in the centre meanwhile is not said")
        T.eq(Q.missedCount(null, history, null), 0, "nothing held, nothing said")
        T.eq([Q.quietCause(true, "sharing"), Q.quietCause(false, "sharing"), Q.quietCause(false, "")], ["dnd", "sharing", ""],
             "Do Not Disturb is the cause before the automatic one")
        T.eq([Q.missedTitle(3), Q.missedTitle(1), Q.missedTitle(-2), Q.missedTitle("x")],
             ["3 notifications", "1 notification", "0 notifications", "0 notifications"], "how many")
        T.eq(Q.missedBody("dnd"), "Came in while Do Not Disturb was on", "the words for Do Not Disturb")
        T.eq(Q.missedBody("sharing"), "Came in while you shared your screen", "while sharing")
        T.eq(Q.missedBody("fullscreen"), "Came in during fullscreen", "fullscreen")
        T.eq(Q.missedBody("game"), "Came in while you played", "a game")
        T.eq(Q.missedBody(""), "Came in while Do Not Disturb was on", "no cause reads as Do Not Disturb")

        T.finish("NotificationQuietTest")
    }
}
