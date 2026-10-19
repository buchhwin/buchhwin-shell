import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/StayAwakeLogic.js" as S

ShellRoot {
    Component.onCompleted: {
        const plugged = { now: 1000, hasBattery: true, onBattery: false }
        const battery = { now: 1000, hasBattery: true, onBattery: true }
        const desktop = { now: 1000, hasBattery: false, onBattery: false }

        // What can be started where.
        T.eq(S.MODES.map(mode => S.offered(mode, plugged)), [true, true, true, true], "everything on the charger")
        T.eq(S.MODES.map(mode => S.offered(mode, battery)), [true, true, false, true],
             "on battery there is no charger to unplug")
        T.eq(S.offered("unplug", desktop), false, "nor on a desktop")
        T.eq([S.offered("forever", plugged), S.offered("", plugged), S.offered(undefined, plugged)], [false, false, false],
             "an unknown mode is never offered")
        T.eq(S.offered("unplug", undefined), false, "unplug needs to know there is a battery")

        // The hold a choice starts.
        T.eq(S.start("1h", plugged), { mode: "1h", until: 1000 + 3600000 }, "an hour from now")
        T.eq(S.start("manual", battery), { mode: "manual", until: 0 }, "until turned off has no deadline")
        T.eq(S.start("unplug", plugged), { mode: "unplug", until: 0 }, "until unplugged on the charger")
        T.eq(S.start("off", battery), { mode: "off", until: 0 }, "off")
        T.eq([S.start("unplug", battery), S.start("unplug", desktop), S.start("nope", plugged)], [null, null, null],
             "refused where it cannot run")
        T.eq(S.start("1h", { hasBattery: false }), null, "an hour needs a clock")

        // A quick switch starts the last choice, or an hour.
        T.eq([S.quickMode("manual", battery), S.quickMode("unplug", plugged), S.quickMode("1h", plugged)],
             ["manual", "unplug", "1h"], "the last choice")
        T.eq(S.quickMode("unplug", battery), "1h", "unplug chosen last, but no charger now: an hour")
        T.eq([S.quickMode(undefined, plugged), S.quickMode("off", plugged), S.quickMode(3, plugged)], ["1h", "1h", "1h"],
             "an hour until something was chosen")
        T.eq([S.normalLimit("manual"), S.normalLimit("off"), S.normalLimit(null)], ["manual", "1h", "1h"],
             "the remembered limit is a way to end, never off")

        // When a hold is over.
        const hour = { mode: "1h", until: 5000 }
        T.eq([S.ended(hour, { now: 4999 }), S.ended(hour, { now: 5000 }), S.ended(hour, { now: 99999 })],
             [false, true, true], "an hour ends at its deadline, and after a night in suspend at once")
        T.eq(S.ended(hour, {}), true, "a clock that cannot be read ends a timed hold rather than keep it")
        T.eq([S.ended({ mode: "unplug" }, plugged), S.ended({ mode: "unplug" }, battery),
              S.ended({ mode: "unplug" }, desktop)], [false, true, false], "unplugging ends it")
        T.eq([S.ended({ mode: "manual" }, battery), S.ended({ mode: "off" }, battery), S.ended(undefined, battery)],
             [false, false, false], "the others only end by hand")

        // The timer looks at each whole minute left and at the end.
        T.eq(S.nextCheck(3600000, 0), 60000, "a full hour: a minute")
        T.eq(S.nextCheck(3600000, 30000), 30000, "half a minute in: to the next whole minute left")
        T.eq(S.nextCheck(10000, 0), 10000, "the last seconds: to the end")
        T.eq([S.nextCheck(1000, 1000), S.nextCheck(1000, 2000)], [0, 0], "nothing to wait for once it is over")
        T.eq(S.nextCheck(1000, 999.5), 1, "never less than a millisecond while it runs")
        T.eq(S.nextCheck(NaN, 0), 60000, "no deadline: a minute")

        // What the switches, the tile and the rows say.
        T.eq(S.minutesLeft(3600000, 0), 60, "a whole hour")
        T.eq([S.minutesLeft(30000, 0), S.minutesLeft(60001, 0), S.minutesLeft(0, 5), S.minutesLeft(NaN, 0)], [1, 2, 0, 0],
             "rounded up, never below 0")
        T.eq(S.subtitle("1h", 3600000, 0), "1 h left", "the hour just started")
        T.eq(S.subtitle("1h", 3600000, 60000 * 8 + 1), "52 min left", "minutes left")
        T.eq([S.subtitle("unplug"), S.subtitle("manual"), S.subtitle("off"), S.subtitle(undefined)],
             ["Until unplugged", "Until turned off", "Off", "Off"], "the others")
        T.eq(S.MODES.map(S.title), ["Off", "For 1 hour", "Until unplugged", "Until turned off"],
             "the choices, in the same words in the control center and in Settings")
        T.finish("StayAwakeTest")
    }
}
