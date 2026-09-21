import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/AnimationLogic.js" as A
import "../../services/hypr/HyprAnimations.js" as H

// The floor that keeps a motion at ten frames however fast the speed setting
// is turned up. This is the test that would have caught the regression it was
// written for: the shell's durations enforced the rule themselves until the
// speed setting arrived and divided what they had already chosen.
ShellRoot {
    Component.onCompleted: {
        // ---- the floor itself ------------------------------------------

        T.eq(A.FLOOR_MS, 167, "ten frames at 60 Hz, in milliseconds")
        T.eq(A.FLOOR_SPEED, 1.67, "the same ten frames in Hyprland's deciseconds")

        // At the designed pace nothing moves: the table was already above the
        // floor, so the floor is invisible at 1x. This is what keeps the
        // checked-in Hyprland configuration valid.
        T.eq(A.travel(340, 1, true), 340, "1x leaves a panel alone")
        T.eq(A.travel(240, 1, true), 240, "and the close too")

        // Slower than designed is never touched - the floor is a minimum.
        T.eq(A.travel(340, 2, true), 680, "half speed doubles the duration")

        // The regression, in numbers. 1.5x is what the user's session had.
        T.eq(A.travel(340, 1 / 1.5, true), 227, "1.5x would rush a panel to 227 ms")
        T.eq(A.travel(340, 1 / 1.5, true) >= A.FLOOR_MS, true, "but 227 is still above the floor")
        T.eq(A.travel(210, 1 / 1.5, true), 167, "navigation is caught and held at ten frames")
        T.eq(A.travel(200, 1 / 1.5, true), 167, "so is a workspace switch")
        T.eq(A.travel(340, 1 / 3, true), 167, "and three times speed cannot go below it either")

        // The cap at the base. Without it, asking for a 70 ms shake swing
        // would come back as 167 and the speed setting would stop reaching
        // anything short at all.
        T.eq(A.travel(70, 1, true), 70, "a duration below the floor is not lengthened by it")
        T.eq(A.travel(70, 1 / 3, true), 70, "and stays at its base however fast it is asked to be")
        T.eq(A.travel(120, 1 / 2, true), 120, "the cap is the base, not the floor")

        // Reduced and Off are exempt: there the shortness is the point.
        T.eq(A.travel(340, 0.6, false), 204, "Reduced keeps its short duration")
        T.eq(A.travel(340, 0, false), 0, "and Off is nothing at all")

        // ---- the compositor's half -------------------------------------

        T.eq(A.travelSpeed(2.0, 1, true), 2.0, "a leaf at the designed pace is untouched")
        T.eq(A.travelSpeed(2.0, 1 / 1.5, true), 1.67, "and is held at ten frames when rushed")
        T.eq(A.travelSpeed(1, 1, true), 1, "a leaf whose base is already short keeps its base")
        T.eq(A.travelSpeed(2.0, 0.6, false), 1.2, "Reduced is exempt here too")

        // ---- and through the table it drives ---------------------------

        // The checked-in configuration is `entries(mode)` with one argument,
        // and scripts/lib/checks.py compares it against hypr/. If the floor
        // changed anything at 1x, that check would start failing.
        const plain = H.entries("fast")
        const atOne = H.entries("fast", 1)
        T.eq(JSON.stringify(plain), JSON.stringify(atOne), "one argument and 1x are the same table")
        T.eq(plain.filter(e => e.leaf === "windows")[0].speed, 2.0, "the window leaf is the table as written")

        const rushed = H.entries("fast", 1.5)
        T.eq(rushed.filter(e => e.leaf === "windows")[0].speed, 1.67, "at 1.5x the window leaf stops at the floor")
        T.eq(rushed.filter(e => e.leaf === "workspaces")[0].speed, 1.67, "and so does a workspace switch")

        // borderangle is off in every mode and its base is 1; the floor must
        // not quietly lengthen a leaf nobody sees.
        T.eq(rushed.filter(e => e.leaf === "borderangle")[0].speed, 1, "borderangle keeps its base")
        T.eq(rushed.filter(e => e.leaf === "borderangle")[0].enabled, false, "and stays off")

        // Off still clears the lot, floor or no floor.
        T.eq(H.entries("off", 3).every(e => e.enabled === false), true, "Off enables nothing")

        // The table itself has to obey the rule, not just the scaling of it.
        // Three leaves did not - windowsOut at 1.4 was 8.4 frames, fade and
        // layers at 1.6 were 9.6 - and no floor behind the division could
        // rescue them, because that floor is capped at the base. This is the
        // assertion that stops the next edit putting one back.
        const short = H.entries("fast").filter(e => e.enabled && e.speed < A.FLOOR_SPEED)
        T.eq(short.map(e => e.leaf), [], "no leaf that animates is under ten frames at the designed pace")

        // And the travel: `popin 96%` is 4 % of movement, which is nothing to
        // look at however many frames it gets. Hyprland's own table uses 87 %.
        T.eq(H.entries("fast").filter(e => e.leaf === "windows")[0].style, "popin 87%", "a window grows far enough to be seen")
        T.eq(H.entries("fast").filter(e => e.leaf === "windowsOut")[0].style, "popin 87%", "and shrinks the same way")

        // ---- three modes, and what happens to the sessions that had four --

        T.eq(A.MODES, ["full", "reduced", "off"], "three modes")
        T.eq(A.mode("full"), "full", "a stored Full is Full")
        T.eq(A.mode("reduced"), "reduced", "Reduced survives")
        T.eq(A.mode("off"), "off", "so does Off")
        T.eq(A.mode("fast"), "full", "Fast was the default mode and becomes Full")
        T.eq(A.mode("normal"), "full", "and so does Normal")
        T.eq(A.mode("nonsense"), "full", "an unknown mode is Full, the way an unknown theme is dark")
        T.eq(A.mode(undefined), "full", "and so is none at all")

        // The migration has to keep the session *looking* the same, and the
        // arithmetic is the whole point: factor = modeFactor / speed, so
        // Normal's 1.25 goes into the speed, divided, because a larger speed
        // is a shorter animation.
        T.eq(A.speedFor("fast", 1), 1, "Fast kept its pace")
        T.eq(A.speedFor("fast", 1.5), 1.5, "whatever it was")
        T.eq(A.speedFor("normal", 1), 0.8, "Normal at 1x was Full at 0.8x")
        T.eq(A.speedFor("normal", 1.25), 1, "and Normal at 1.25x was the designed pace exactly")
        T.eq(A.speedFor("normal", 0.25), 0.25, "clamped to the bottom of the slider")
        T.eq(A.speedFor("full", 3), 3, "and the top of it")
        T.eq(A.speedFor("fast", 0), 1, "a stored nothing is the designed pace")
        T.eq(A.speedFor("fast", "x"), 1, "and so is a stored nonsense")

        // And the same duration comes out the other side, which is the only
        // promise that matters to somebody who never asked for this change.
        const before = A.travel(340, 1.25 / 1.25, true)
        const after = A.travel(340, 1 / A.speedFor("normal", 1.25), true)
        T.eq(after, before, "a migrated Normal session opens a panel in the same time")

        const migrated = A.migrate({ appearance: { animationMode: "normal", animationSpeed: 1.25, theme: "dark" } })
        T.eq(migrated.appearance.animationMode, "full", "the document says Full afterwards")
        T.eq(migrated.appearance.animationSpeed, 1, "with the pace carried across")
        T.eq(migrated.appearance.theme, "dark", "and everything else left alone")

        const fast = A.migrate({ appearance: { animationMode: "fast", animationSpeed: 1.5 } })
        T.eq([fast.appearance.animationMode, fast.appearance.animationSpeed], ["full", 1.5], "Fast keeps its speed")

        // Total and idempotent: running it twice is running it once, and
        // anything it does not understand passes through untouched.
        T.eq(JSON.stringify(A.migrate(migrated)), JSON.stringify(migrated), "migrating twice changes nothing")
        const kept = { appearance: { animationMode: "reduced", animationSpeed: 2 } }
        T.eq(JSON.stringify(A.migrate(kept)), JSON.stringify(kept), "Reduced is not touched")
        T.eq(JSON.stringify(A.migrate({ appearance: { animationMode: "off" } })),
             JSON.stringify({ appearance: { animationMode: "off" } }), "nor is Off")
        T.eq(A.migrate(null), null, "no document is no document")
        T.eq(JSON.stringify(A.migrate({})), "{}", "a document with no appearance survives")
        T.eq(JSON.stringify(A.migrate({ appearance: null })), JSON.stringify({ appearance: null }),
             "and so does one whose appearance is not an object")

        // The compositor's plan lost a branch with Normal; Full is the table.
        T.eq(H.entries("full").filter(e => e.leaf === "windows")[0].speed, 2, "Full is the table as written")
        T.eq(H.entries("reduced").filter(e => e.leaf === "windows")[0].speed, 1.2, "Reduced is shorter")
        T.eq(H.pointerAnimated("full"), true, "a dragged window follows the pointer in Full")
        T.eq(H.pointerAnimated("reduced"), false, "and stops in Reduced, which no pace could say")

        T.finish("AnimationTest")
    }
}
