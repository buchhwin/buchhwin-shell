import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/timer/TimerLogic.js" as L
import "../../services/notifications/NotificationLogic.js" as N

// The countdowns TimerService keeps (services/timer/TimerLogic.js): a timer
// and a Focus session side by side, kept across a restart in timer.json, and
// what the end of one does - the notification, the shell's own notice
// through Do Not Disturb, the alarm. Pure; no service is started.
ShellRoot {
    Component.onCompleted: {
        // ---- runs -------------------------------------------------------------------
        T.eq([L.kindOf("focus"), L.kindOf("timer"), L.kindOf(""), L.kindOf(undefined), L.kindOf("tea")],
             ["focus", "timer", "timer", "timer", "timer"], "two kinds, a timer unless it says Focus")
        T.eq(L.run("focus", 5000, 25), { kind: "focus", endsAt: 5000, total: 25 }, "a run")
        T.eq([L.run("timer", 0, 5), L.run("timer", 5000, 0), L.run("timer", 5000, L.MAX_SECONDS + 1),
              L.run("timer", NaN, 5)], [null, null, null, null], "no end, no length or past a day is no run")

        const tea = L.run("timer", 9000, 300)
        const focus = L.run("focus", 4000, 1500)
        const both = L.withRun(L.withRun([], tea), focus)
        T.eq(both.map(item => item.kind), ["focus", "timer"], "a timer and a session side by side, the first to end first")
        T.eq(L.withRun(both, L.run("timer", 2000, 60)).map(item => item.kind + ":" + item.endsAt),
             ["timer:2000", "focus:4000"], "a new timer replaces the timer, never the session")
        T.eq(L.withRun(both, L.run("focus", 12000, 600)).map(item => item.kind + ":" + item.endsAt),
             ["timer:9000", "focus:12000"], "and a new session the session")
        T.eq(L.withoutRun(both, "focus").map(item => item.kind), ["timer"], "one stopped, the other runs on")
        T.eq(L.withoutRun(both, "tea").map(item => item.kind), ["focus"], "a kind it does not know is the timer")
        const alone = [tea]
        T.ok(L.withoutRun(alone, "focus") === alone, "the very same list when nothing goes, so no binding runs again")
        T.eq([L.find(both, "focus").endsAt, L.find([tea], "focus"), L.find(null, "timer")], [4000, null, null], "found by kind")
        T.eq([L.shown(both).kind, L.shown([]), L.shown(undefined)], ["focus", null, null], "the one shown ends first")
        T.eq(L.due(both, 5000).map(item => item.kind), ["focus"], "due by now")
        T.eq(L.due(both, 9000).map(item => item.kind), ["focus", "timer"], "both at once, in their order")
        T.eq(L.due(both, 100), [], "none before their ends")
        T.eq(L.describe(both, 3000), [{ kind: "focus", remaining: 1 }, { kind: "timer", remaining: 6 }],
             "`timer get` lists each with its seconds left")

        // ---- across a restart ----------------------------------------------------------
        const text = L.stateText(both, "boot-a")
        T.eq(JSON.parse(text), { boot: "boot-a", runs: [{ kind: "focus", endsAt: 4000, total: 1500 },
                                                       { kind: "timer", endsAt: 9000, total: 300 }] },
             "timer.json: the boot and the runs")
        T.eq(L.restored(text, "boot-a", 3000), both, "read back in the same boot")
        T.eq(L.restored(text, "boot-b", 3000), [], "a reboot ends them")
        T.eq(L.restored(text, "", 3000), [], "and so does a boot that cannot be read")
        T.eq(L.restored(text, "boot-a", 9000 + L.STALE_MS).map(item => item.kind), ["timer"],
             "one that ran out while the shell was away is still there to ring")
        T.eq(L.restored(text, "boot-a", 9001 + L.STALE_MS), [], "unless that was too long ago to be news")
        T.eq([L.restored("", "boot-a", 0), L.restored("{", "boot-a", 0), L.restored("[]", "boot-a", 0),
              L.restored('{"boot":"boot-a","runs":{}}', "boot-a", 0)], [[], [], [], []], "no file, a broken one: none")
        T.eq(L.restored(JSON.stringify({ boot: "x", runs: [{ kind: "tea", endsAt: 5000, total: 5 }, null,
                                                             { kind: "timer", endsAt: 5000, total: 99999999 },
                                                             { kind: "timer", endsAt: 6000, total: 6 },
                                                             { kind: "timer", endsAt: 7000, total: 7 }] }), "x", 0),
             [{ kind: "timer", endsAt: 7000, total: 7 }], "unknown kinds and lengths out, one of a kind - the last")

        // ---- the end ---------------------------------------------------------------------
        T.eq(L.endTexts("timer", 300), { summary: "Timer done", body: "Your timer of 5 minutes has run out" },
             "a timer's words, as before")
        T.eq(L.endTexts("focus", 1500), { summary: "Focus session done", body: "The Focus session of 25 minutes has ended" },
             "a session's")

        const plan = (popsUp, extra) => L.endActions(Object.assign({ real: true, popsUp: popsUp, rule: "default",
                                                                    sound: true, canNotice: true }, extra || {}))
        T.eq(plan(true), { send: true, notice: false, sound: true },
             "it pops up anyway: the notification as always, and the alarm")
        T.eq(plan(false), { send: true, notice: true, sound: true },
             "held back by Do Not Disturb: in the history still, and the shell's own notice says it")
        T.eq(plan(false, { sound: false }), { send: true, notice: true, sound: false }, "the alarm only with its setting")
        T.eq(plan(false, { canNotice: false }), { send: true, notice: false, sound: true },
             "a shell without the notices: the notification alone, as before")
        T.eq(plan(false, { rule: "mute" }), { send: true, notice: false, sound: false },
             "the timer muted in Settings > Notifications: the history only")
        T.eq(plan(true, { real: false }), { send: false, notice: true, sound: false },
             "nested: nothing sent, nothing played on the host's speakers, the notice stands in")

        // What NotificationService decides for the timer's urgent notification,
        // which `popsUp` is: the Do Not Disturb the user turned on holds it
        // back, an owned one (gaming, Focus) lets it through.
        const urgent = (state, rule) => N.shouldPopup(state, true, rule || N.ruleFor({}, { appName: L.APP_NAME, hints: {} }))
        T.eq([urgent({ suppressed: false, dndMode: "off", dndBy: "" }),
              urgent({ suppressed: true, dndMode: "manual", dndBy: "" }),
              urgent({ suppressed: true, dndMode: "manual", dndBy: "focus" }),
              urgent({ suppressed: true, dndMode: "1h", dndBy: "" })], [true, false, true, true],
             "the user's own manual Do Not Disturb is the one the notice is for")
        T.eq(N.ruleFor({ timer: "mute" }, { appName: L.APP_NAME, hints: {} }), "mute", "the timer's rule is the app Timer's")

        T.eq(L.notifyCommand(L.endTexts("timer", 300), true),
             ["notify-send", "--app-name=Timer", "--icon=alarm-symbolic", "--urgency=critical",
              "--hint=boolean:suppress-sound:true", "--", "Timer done", "Your timer of 5 minutes has run out"],
             "the notification, urgent, asking for no sound of its own while the alarm plays")
        T.eq(L.notifyCommand(L.endTexts("focus", 1500), false),
             ["notify-send", "--app-name=Timer", "--icon=alarm-symbolic", "--urgency=critical", "--",
              "Focus session done", "The Focus session of 25 minutes has ended"],
             "without the alarm, the notification sounds may play for it")
        T.eq([L.announceStep(true, true), L.announceStep(true, false), L.announceStep(false, true),
              L.announceStep(false, false)], ["now", "wait", "none", "none"],
             "an end at the start waits for the Do Not Disturb read back; the lock screen announces nothing")

        T.eq(L.soundCommand(), ["timeout", "15", "pw-play", "--media-role", "Notification",
                                "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
             "the alarm through pw-play, bounded")
        T.eq(L.soundCommand(L.ALARM_SOUND)[5], L.ALARM_SOUND, "the freedesktop alarm clock")

        T.finish("TimerRunsTest")
    }
}
