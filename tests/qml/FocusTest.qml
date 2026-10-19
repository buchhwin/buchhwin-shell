import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/adaptive/FocusLogic.js" as F
import "../../services/LayoutLogic.js" as L
import "../../services/notifications/NotificationLogic.js" as N

// Focus mode's Do Not Disturb (services/adaptive/FocusLogic.js): Focus owns
// the one it turns on, as a mode owns its own, and a mode switch under Focus
// leaves it alone. Pure, so it runs without the services (NotificationService
// would reach the session's notification server, pitfall 82).
ShellRoot {
    // Do Not Disturb as NotificationService holds it, moved by a list of
    // steps: ["focus", true|false] or ["mode", from, to]. Each change goes
    // through the same functions the services call, and dndOwner keeps an
    // owner only while on, as setDnd does.
    function play(steps, start) {
        let dnd = Object.assign({ active: false, by: "" }, start || {})
        let mode = dnd.mode || "work"
        const effects = { gaming: { dnd: "manual" }, work: {}, docked: {} }
        const apply = change => {
            if (!change) return
            dnd = { active: change.mode !== "off", by: N.dndOwner(change.mode, change.by) }
        }
        for (const step of steps) {
            if (step[0] === "focus") apply(F.dndOnFocus(step[1], dnd.by, dnd.active, mode, effects[mode]))
            else { apply(L.dndOnModeChange(dnd.by, dnd.active, step[1], step[2], effects[step[2]])); mode = step[2] }
        }
        return { active: dnd.active, by: dnd.by }
    }

    Component.onCompleted: {
        // ---- starting and ending Focus ---------------------------------------
        T.eq(F.dndOnFocus(true, "", false, "work", {}), { mode: "manual", by: "focus" },
             "Focus finds Do Not Disturb off: it turns it on and owns it")
        T.eq(F.dndOnFocus(false, "focus", true, "work", {}), { mode: "off", by: "" }, "and ending Focus turns it off")
        T.eq(F.dndOnFocus(true, "", true, "work", {}), null, "the user's own stays theirs")
        T.eq(F.dndOnFocus(false, "", true, "work", {}), null, "and ending Focus leaves it on")
        T.eq(F.dndOnFocus(true, "gaming", true, "gaming", { dnd: "manual" }), { mode: "manual", by: "focus" },
             "a mode's own is taken over")
        T.eq(F.dndOnFocus(false, "focus", true, "gaming", { dnd: "manual" }), { mode: "manual", by: "gaming" },
             "ending Focus in a mode that wants it hands it back to that mode")
        T.eq(F.dndOnFocus(false, "focus", false, "work", {}), null, "one that is off already stays off")
        T.eq(F.dndOnFocus(true, "focus", true, "work", {}), null, "Focus's own found on again asks nothing")
        T.eq(F.dndOnFocus(false, "focus", true, "", { dnd: "manual" }), { mode: "off", by: "" },
             "no mode to hand it to: off")

        // ---- with the mode switches (LayoutLogic.dndOnModeChange) ------------
        T.eq(play([["mode", "work", "gaming"], ["focus", true], ["mode", "gaming", "work"]]), { active: true, by: "focus" },
             "Focus turned on in gaming: leaving gaming no longer ends Do Not Disturb under Focus")
        T.eq(play([["mode", "work", "gaming"], ["focus", true], ["mode", "gaming", "work"], ["focus", false]]),
             { active: false, by: "" }, "and ending Focus later does")
        T.eq(play([["mode", "work", "gaming"], ["focus", true], ["focus", false]]), { active: true, by: "gaming" },
             "ending Focus while still in gaming keeps gaming's, as gaming's")
        T.eq(play([["mode", "work", "gaming"], ["focus", true], ["focus", false], ["mode", "gaming", "work"]]),
             { active: false, by: "" }, "which leaving gaming then ends")
        T.eq(play([["focus", true], ["mode", "work", "gaming"], ["mode", "gaming", "docked"]]), { active: true, by: "focus" },
             "Focus first: gaming finds it on and takes nothing, and leaving gaming keeps it")
        T.eq(play([["focus", true], ["mode", "work", "docked"], ["focus", false]]), { active: false, by: "" },
             "ending Focus in a mode without Do Not Disturb turns it off")
        T.eq(play([["focus", true], ["focus", false]], { active: true, by: "" }), { active: true, by: "" },
             "the user's own, on before Focus, outlives it")

        // ---- a restart ---------------------------------------------------------
        T.eq([F.focusRestored("focus", true), F.focusRestored("focus", false), F.focusRestored("", true),
              F.focusRestored("gaming", true)], [true, false, false, false],
             "Focus comes back after a restart only with its own Do Not Disturb still on")
        T.eq(N.dndOwner("manual", F.OWNER), "focus", "and the owner's name is one state.json keeps")

        T.finish("FocusTest")
    }
}
