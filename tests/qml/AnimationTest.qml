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
        // ---- the pace ---------------------------------------------------

        T.eq([A.SPEED_MIN, A.SPEED_MAX], [0.5, 2], "the slider runs from half speed to double")
        T.eq([A.speed(1), A.speed(0.1), A.speed(9), A.speed("x"), A.speed(0)], [1, 0.5, 2, 1, 1],
             "a stored speed is clamped to the slider, nonsense is the designed pace")

        // ---- the floor ---------------------------------------------------

        T.eq(A.FLOOR_MS, 100, "six frames at 60 Hz, in milliseconds")
        T.eq(A.FLOOR_SPEED, 1, "the same six frames in Hyprland's deciseconds")
        T.eq(A.travel(340, 1, true), 340, "1x leaves a panel alone")
        T.eq(A.travel(340, 2, true), 680, "half speed doubles the duration")
        // The regression the old four-fifths floor caused: from 1.25x up every
        // travelling motion stayed where it was, so the slider's top half only
        // reached hover tints. Now 2x is twice as fast.
        T.eq(A.travel(340, 1 / 2, true), 170, "2x halves a panel")
        T.eq(A.travel(200, 1 / 2, true), 100, "and a workspace switch, down to the six frames")
        T.eq(A.travel(150, 1 / 2, true), 100, "which hold below that")
        T.eq(A.travel(70, 1 / 2, true), 70, "a motion shorter than the floor is not lengthened by it")
        T.eq(A.travel(340, 0.6, false), 204, "Reduced keeps its short duration")
        T.eq(A.travel(340, 0, false), 0, "and Off is nothing at all")
        T.eq(A.travelSpeed(2.0, 1 / 2, true), 1, "a 2.0 leaf at 2x")
        T.eq(A.travelSpeed(1.5, 1 / 2, true), 1, "held at six frames")
        T.eq(A.travelSpeed(0.8, 1 / 2, true), 0.8, "a leaf already shorter keeps its base")
        T.eq(A.travelSpeed(2.0, 0.6, false), 1.2, "Reduced is exempt here too")

        // ---- springs -----------------------------------------------------

        // The speed setting scales a spring itself: stiffness by s², damping
        // by s, so the same motion plays s times as fast with the same
        // overshoot.
        const at1 = A.spring("standard", 1)
        const at2 = A.spring("standard", 2)
        T.eq([at1.spring, at1.damping, at1.mass], [4.5, 0.42, 1], "the standard spring at 1x")
        T.eq([at2.spring, at2.damping], [18, 0.84], "at 2x: four times as stiff, twice the damping")
        T.eq(A.spring("standard", 0.5).spring, 1.13, "at half speed a quarter as stiff")
        T.eq(A.spring("nonsense", 1), at1, "an unknown spring is the standard one")
        T.ok(A.spring("fast", 1).spring > at1.spring && A.spring("slow", 1).spring < at1.spring, "fast is stiffer, slow softer")
        T.ok(A.spring("slow", 2).damping <= 1, "damping never goes past critical")
        const scaled = A.scaleSpring({ name: "s", mass: 1, stiffness: 380, dampening: 34 }, 2)
        T.eq([scaled.stiffness, scaled.dampening], [1520, 68], "a Hyprland spring scaled the same way")
        // The damping ratio d / (2·√(k·m)) is what makes it the same motion.
        const ratio = curve => curve.dampening / (2 * Math.sqrt(curve.stiffness * curve.mass))
        T.ok(Math.abs(ratio(scaled) - ratio({ stiffness: 380, dampening: 34, mass: 1 })) < 0.001, "and keeps its damping ratio")

        // ---- and through the compositor's table ---------------------------

        const plain = H.entries("full")
        T.eq(JSON.stringify(plain), JSON.stringify(H.entries("full", 1)), "one argument and 1x are the same table")
        T.eq(plain.filter(e => e.leaf === "windows")[0].spring, "buchhwinSpatial", "windows move on a spatial spring")
        T.eq(plain.filter(e => e.leaf === "layers")[0].spring, "", "layers keep a timed curve")
        T.ok(plain.every(e => e.spring === "" || H.SPRINGS.some(c => c.name === e.spring)), "every spring a leaf names exists")
        T.eq(H.curves("full", 1).filter(c => c.name === "buchhwinSpatial")[0], { name: "buchhwinSpatial", mass: 1, stiffness: 380, dampening: 34 },
             "the springs at 1x are the configuration as written")
        T.eq(H.curves("full", 2).filter(c => c.name === "buchhwinSpatial")[0].stiffness, 1520, "at 2x they are stiffer")
        T.ok(H.curves("reduced", 1)[0].stiffness > H.curves("full", 1)[0].stiffness, "Reduced is quicker, springs too")
        T.ok(H.SPRINGS.every(c => c.dampening / (2 * Math.sqrt(c.stiffness * c.mass)) >= 0.85),
             "no spring rings: every damping ratio is 0.85 or more")
        T.eq(H.entries("full", 2).filter(e => e.leaf === "windows")[0].speed, 1, "the bezier stand-in at 2x")
        T.eq(H.entries("off", 2).every(e => e.enabled === false), true, "Off enables nothing")
        const borderangle = H.entries("full", 2).filter(e => e.leaf === "borderangle")[0]
        T.eq([borderangle.speed, borderangle.enabled], [1, false], "borderangle keeps its base and stays off")
        const tooShort = H.entries("full").filter(e => e.enabled && e.speed < A.FLOOR_SPEED)
        T.eq(tooShort.map(e => e.leaf), [], "no leaf that animates is under six frames at the designed pace")
        T.eq(H.entries("full").filter(e => e.leaf === "windows")[0].style, "popin 87%", "a window grows far enough to be seen")
        T.eq(H.entries("full").filter(e => e.leaf === "windowsOut")[0].style, "popin 87%", "and shrinks the same way")

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
        T.eq(A.speedFor("normal", 0.25), 0.5, "clamped to the bottom of the slider")
        T.eq(A.speedFor("full", 3), 2, "and the top of it")
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
