import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/profile/ProfileLogic.js" as P

// The profile key, from every state it can be pressed in. A nested session can
// show that the key fires; it cannot show what two rounds of it do to the
// automatic profile, which is the part that can surprise the user.
ShellRoot {
    readonly property var all: ["minimal", "work", "gaming", "laptop", "docked"]

    Component.onCompleted: {
        // ---- the order ------------------------------------------------------
        T.eq(all.map(name => P.nextMode(name, all)),
             ["work", "gaming", "laptop", "docked", "minimal"], "each profile leads to the next, and the last wraps")
        T.eq(P.nextMode("nonsense", all), "minimal", "an unknown profile starts at the beginning")
        T.eq(P.nextMode("minimal", []), "", "and with nothing to cycle through there is no next")
        T.eq(P.nextMode("minimal", null), "", "nor with no list at all")
        T.eq(P.nextMode("a", ["a"]), "a", "one profile leads to itself")

        // ---- what happens to the automatic profile ---------------------------
        // The two AdaptiveService picks between turn it back on; every other
        // one turns it off, because a hand-picked profile that silently
        // reverts at the next monitor change is worse than one that does not.
        T.eq(all.map(P.autoAfter), [false, false, false, true, true], "only the two it chooses between")

        // A whole round from minimal with automatic off: it stays off until
        // the cycle reaches laptop, and comes back off after docked.
        let current = "minimal"
        let auto = false
        const seen = []
        for (let step = 0; step < all.length; ++step) {
            const next = P.cycleMode(current, all, auto)
            seen.push([next.mode, next.auto, next.autoChanged])
            current = next.mode
            auto = next.auto
        }
        T.eq(seen, [["work", false, false], ["gaming", false, false], ["laptop", true, true],
                    ["docked", true, false], ["minimal", false, true]],
             "a round from minimal: automatic comes on at laptop and goes off again at minimal")
        T.eq([current, auto], ["minimal", false], "and it ends where it started")

        // The same round again is the same round: nothing accumulates.
        const again = []
        for (let step = 0; step < all.length; ++step) {
            const next = P.cycleMode(current, all, auto)
            again.push([next.mode, next.auto, next.autoChanged])
            current = next.mode
            auto = next.auto
        }
        T.eq(again, seen, "a second round does exactly what the first did")

        // Pressed from laptop with automatic already off - which is what the
        // old behaviour left behind - it is turned back on rather than left.
        T.eq(P.cycleMode("gaming", all, false).autoChanged, true, "on at laptop even from automatic off")
        T.eq(P.cycleMode("work", all, true).autoChanged, true, "and off at gaming even from automatic on")
        T.eq(P.cycleMode("minimal", [], false), null, "nothing to cycle through is nothing to do")

        // ---- what the OSD says ------------------------------------------------
        const templates = { gaming: { label: "Gaming" }, laptop: { label: "Laptop" } }
        T.eq(P.label("gaming", templates), "Gaming", "a profile's own name")
        T.eq(P.label("gaming", null), "gaming", "and its id when there is no template")
        T.eq(P.label("nothing", templates), "nothing", "or when the template has none")
        T.eq(P.osdText("Gaming", P.cycleMode("work", all, true)), "Gaming · automatic off",
             "the OSD says what became of the automatic profile")
        T.eq(P.osdText("Docked", P.cycleMode("laptop", all, true)), "Docked",
             "and says nothing when nothing became of it")
        T.eq(P.osdText("Gaming", null), "Gaming", "nor when there was no step at all")
        T.ok(all.every(name => P.icon(name).length > 0), "every profile has a glyph")
        T.eq(P.icon("nonsense"), P.icon("minimal"), "and an unknown one borrows the plain one")

        T.finish("ProfileTest")
    }
}
