import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/adaptive/FocusLogic.js" as F
import "../../services/timer/TimerLogic.js" as Timer
import "../../services/notifications/NotificationLogic.js" as N

// A Focus session (AdaptiveService.focusFor, services/adaptive/FocusLogic.js):
// Focus with a countdown of its own beside any timer, whose end ends Focus -
// and the Do Not Disturb Focus owns - and rings; what the control center's
// tile says; and a restart in the middle of one. Pure, as FocusTest: the
// services would reach the session's notification server (pitfall 82).
ShellRoot {
    // AdaptiveService and TimerService in miniature, driven by the same
    // functions they call: `focus` and the Do Not Disturb it finds, the runs.
    // Steps: ["session", seconds], ["timer", seconds], ["focus", true|false],
    // ["stop", kind], ["tick", at]. The end of a session turns Focus off as
    // `sessionRanOut` does; a stopped one as `onStopped` does.
    function play(steps) {
        const s = { focus: false, dnd: { active: false, by: "" }, runs: [], now: 0, rang: [] }
        const setDnd = change => {
            if (change) s.dnd = { active: change.mode !== "off", by: N.dndOwner(change.mode, change.by) }
        }
        const setFocus = active => {
            if (!active) s.runs = Timer.withoutRun(s.runs, "focus")
            if (active === s.focus) return
            setDnd(F.dndOnFocus(active, s.dnd.by, s.dnd.active, "work", {}))
            s.focus = active
        }
        for (const step of steps) {
            if (step[0] === "session") {
                setFocus(true)
                s.runs = Timer.withRun(s.runs, Timer.run("focus", s.now + step[1] * 1000, step[1]))
            } else if (step[0] === "timer") {
                s.runs = Timer.withRun(s.runs, Timer.run("timer", s.now + step[1] * 1000, step[1]))
            } else if (step[0] === "focus") {
                setFocus(step[1])
            } else if (step[0] === "stop") {
                const had = Timer.find(s.runs, step[1]) !== null
                s.runs = Timer.withoutRun(s.runs, step[1])
                if (had && step[1] === "focus") setFocus(false)
            } else if (step[0] === "tick") {
                s.now = step[1] * 1000
                for (const item of Timer.due(s.runs, s.now)) {
                    s.runs = Timer.withoutRun(s.runs, item.kind)
                    if (item.kind === "focus") setFocus(false)
                    s.rang.push(item.kind)
                }
            }
        }
        return { focus: s.focus, dnd: s.dnd.active ? s.dnd.by || "user" : "off",
                 runs: s.runs.map(item => item.kind), rang: s.rang }
    }

    Component.onCompleted: {
        // ---- a session ---------------------------------------------------------------
        T.eq(play([["session", 1500]]), { focus: true, dnd: "focus", runs: ["focus"], rang: [] },
             "Focus for 25 minutes: Focus on, its own Do Not Disturb, a countdown")
        T.eq(play([["session", 1500], ["tick", 1499]]).focus, true, "still on a second before the end")
        T.eq(play([["session", 1500], ["tick", 1500]]), { focus: false, dnd: "off", runs: [], rang: ["focus"] },
             "the end: Focus off, its Do Not Disturb with it, and it rings")
        T.eq(play([["session", 1500], ["timer", 300], ["tick", 300]]), { focus: true, dnd: "focus", runs: ["focus"], rang: ["timer"] },
             "a tea timer during the session rings on its own and leaves the session running")
        T.eq(play([["session", 1500], ["timer", 300], ["tick", 1500]]).rang, ["timer", "focus"], "both ring, each at its end")
        T.eq(play([["session", 1500], ["focus", false]]), { focus: false, dnd: "off", runs: [], rang: [] },
             "Focus ended by hand ends the session without a ring")
        T.eq(play([["session", 1500], ["focus", false], ["tick", 1500]]).rang, [], "and nothing rings later")
        T.eq(play([["session", 1500], ["stop", "focus"]]), { focus: false, dnd: "off", runs: [], rang: [] },
             "stopping the countdown ends Focus")
        T.eq(play([["session", 1500], ["timer", 60], ["stop", "timer"]]), { focus: true, dnd: "focus", runs: ["focus"], rang: [] },
             "stopping the timer leaves the session")
        T.eq(play([["focus", true], ["session", 600], ["tick", 600]]).focus, false, "a Focus already on gets an end")
        T.eq(play([["session", 1500], ["session", 600], ["tick", 600]]), { focus: false, dnd: "off", runs: [], rang: ["focus"] },
             "a new session replaces the running one")

        // ---- the tile -------------------------------------------------------------------
        const end = new Date(2026, 9, 19, 14, 25, 0).getTime()
        T.eq([F.focusLabel(false, end, false), F.focusLabel(true, 0, false), F.focusLabel(true, end, false),
              F.focusLabel(true, end, true)], ["Off", "On", "\u2192 14:25", "\u2192 2:25 PM"],
             "the control center says Off, On, or when the session ends, as the clock is set")

        // ---- a restart in the middle of one --------------------------------------------
        T.eq([F.restartStep("focus", true, false), F.restartStep("focus", true, true), F.restartStep("", true, true),
              F.restartStep("focus", false, false), F.restartStep("gaming", true, false)],
             ["restore", "end", "off", "off", "off"],
             "Focus comes back with its own Do Not Disturb, only to end when its session ran out meanwhile")
        T.eq([F.sessionAfterRestart(true, true), F.sessionAfterRestart(false, true), F.sessionAfterRestart(false, false),
              F.sessionAfterRestart(true, false)], ["keep", "drop", "keep", "keep"],
             "a countdown whose Focus did not come back goes; an open Focus stays open")

        // The whole way: a session's runs in timer.json and its Do Not Disturb
        // in state.json, read back by a shell started again halfway through.
        const started = 1000000
        const runs = [Timer.run("focus", started + 1500 * 1000, 1500)]
        const back = Timer.restored(Timer.stateText(runs, "boot"), "boot", started + 600 * 1000)
        T.eq([back.length, Timer.due(back, started + 600 * 1000).length, F.restartStep("focus", true, false)],
             [1, 0, "restore"], "a deploy ten minutes in: the session and its Focus both come back")
        const late = Timer.restored(Timer.stateText(runs, "boot"), "boot", started + 1560 * 1000)
        T.eq([Timer.due(late, started + 1560 * 1000).length, F.restartStep("focus", true, true)], [1, "end"],
             "a shell away across the end: the countdown rings at the start, and Focus ends")

        T.finish("FocusSessionTest")
    }
}
