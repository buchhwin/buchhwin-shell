import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/SignalLogic.js" as S

// Wi-Fi strength in NetworkManager's steps, and the "!" for a connection
// without the internet (services/network/SignalLogic.js).
ShellRoot {
    Component.onCompleted: {
        // nmcli's and Plasma's steps: over 80 % four, over 55 three, over 30
        // two, over 5 one - 65 % is three bars here as in `nmcli dev wifi`.
        T.eq([0.95, 0.81, 0.80, 0.65, 0.56, 0.55, 0.31, 0.30, 0.06, 0.05, 0].map(value => S.level(value)),
             [4, 4, 3, 3, 3, 2, 2, 1, 1, 0, 0], "the four steps, each edge on the lower side")
        T.eq([S.level(0.01, true), S.level(0, true), S.level(0.9, true)], [1, 1, 4], "connected: never no bars")
        T.eq([S.level(undefined), S.level("x"), S.level(null, true)], [0, 0, 1], "no strength: none, one while connected")

        // The island's drawn bars use the same steps, spread over their count.
        T.eq([0.9, 0.65, 0.4, 0.1].map(value => S.lit(value, 4, true)), [4, 3, 2, 1], "four bars: one per step")
        T.eq([0.9, 0.65, 0.4, 0.1].map(value => S.lit(value, 8, true)), [8, 6, 4, 2], "eight bars: two per step")
        T.eq([S.lit(0.9, 0, true), S.lit(0.9, -2, true), S.lit(0.9, "x", true)], [0, 0, 0], "no bars to light")

        // Glyphs: the whole fan as an outline, the bars filled; "!" without
        // the internet.
        T.eq([0.9, 0.65, 0.4, 0.1, 0].map(value => S.glyph(value, false, true)), ["󰤨", "󰤥", "󰤢", "󰤟", "󰤟"],
             "connected: four steps, at least one bar")
        T.eq(S.glyph(0, false, false), "󰤯", "a network of the list with no signal: the empty fan")
        T.eq([0.9, 0.65, 0.4, 0.1].map(value => S.glyph(value, true, true)), ["󰤩", "󰤦", "󰤣", "󰤠"], "without the internet: the same with !")
        T.eq([S.glyph(undefined, false), S.glyph(null, true)], ["󰤨", "󰤩"], "no strength reported yet draws full")
        T.eq(S.GLYPHS.length === 5 && S.ALERT_GLYPHS.length === 5, true, "a glyph for each of 0-4 bars")

        // Connectivity in words; unknown never alarms.
        T.eq(["full", "limited", "portal", "none", "unknown", "", undefined].map(S.limited),
             [false, true, true, true, false, false, false], "limited: portal, limited, none")
        T.eq(["full", "limited", "portal", "none", "unknown"].map(S.note),
             ["", "No internet", "Sign-in required", "No internet", ""], "what the line says")

        // "No internet" only once it has held: a reconnect reports the
        // connection before NetworkManager's check reaches the internet again.
        T.eq(S.LIMITED_SETTLE_MS, 3000, "three seconds")
        T.eq([S.limitedShown(true, 1000, 3999), S.limitedShown(true, 1000, 4000), S.limitedShown(true, 1000, 9000)],
             [false, true, true], "shown from three seconds on")
        T.eq([S.limitedShown(false, 1000, 9000), S.limitedShown(true, -1, 9000)], [false, false],
             "not while it is not limited, nor without a start")
        T.eq([S.limitedShown(true, 1000, 1000, 0), S.limitedShown(true, 1000, 1400, 500)], [true, false], "another wait")
        // The service's Timer asks again for what is left: one that ends a
        // moment early must not leave the "!" away for good.
        T.eq([S.limitedWait(true, 1000, 1000), S.limitedWait(true, 1000, 3990), S.limitedWait(true, 1000, 3999.5)],
             [3000, 10, 1], "the wait from the start, and what is left after an early end")
        T.eq([S.limitedWait(true, 1000, 4000), S.limitedWait(false, 1000, 2000), S.limitedWait(true, -1, 2000)],
             [-1, -1, -1], "nothing to wait for once shown, or while not limited")
        T.eq(S.limitedWait(true, 5000, 1000), 3000, "never longer than the settle time (a clock set back)")
        T.eq(S.limitedWait(true, 1000, 1200, 500), 300, "another wait")

        T.finish("SignalTest")
    }
}
