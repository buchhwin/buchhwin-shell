import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/BatteryLogic.js" as B

ShellRoot {
    function input(percent, extra) {
        return Object.assign({ hasBattery: true, discharging: true, percent: percent, enabled: true, level: 20 }, extra || {})
    }

    // Feeds a sequence of levels and returns the warning kinds ("" for none).
    function run(levels, extra) {
        let state = { fired: {} }
        const kinds = []
        for (const level of levels) {
            const step = typeof level === "object" ? level : input(level, extra)
            const result = B.update(state, step)
            state = result.state
            kinds.push(result.warning ? result.warning.kind : "")
        }
        return kinds
    }

    Component.onCompleted: {
        T.eq([B.lowLevel(15), B.lowLevel(12), B.lowLevel("20")], [15, 20, 20], "low level limited to the choices")
        T.eq([B.thresholds(25), B.thresholds(10)], [[25, 10, 5], [10, 5]], "thresholds without duplicates")
        T.eq(run([30, 21, 20, 19, 15, 11, 10, 9, 6, 5, 4]),
             ["", "", "low", "", "", "", "veryLow", "", "", "critical", ""], "each threshold fires once while discharging")
        T.eq(run([8]), ["veryLow"], "starting below two thresholds gives one warning")
        T.eq(run([20, 3]), ["low", "critical"], "a jump announces only the most severe threshold")
        T.eq(run([20, 22, 23, 20]), ["low", "", "", ""], "no repeat within the hysteresis")
        T.eq(run([20, 24, 20]), ["low", "", "low"], "re-armed above threshold + 3")
        T.eq(run([19, input(19, { discharging: false }), 19]), ["low", "", "low"], "charging resets the cycle")
        T.eq(run([15, 10], { hasBattery: false }), ["", ""], "no warnings without a battery")
        T.eq(run([15, 10], { discharging: false }), ["", ""], "no warnings while charging")
        T.eq(run([15, 10], { enabled: false }), ["", ""], "no warnings when switched off")
        T.eq(run([25, 12], { level: 25 }), ["low", ""], "configurable first threshold")
        T.eq(run([12, 10], { level: 10 }), ["", "veryLow"], "level 10 merges with the very low warning")
        T.eq(run([input(15, { level: 25 }), input(15, { level: 15 })]), ["low", "low"], "a changed level is its own threshold")

        const low = B.message("low", 19.6, "1 h 5 min left")
        T.eq([low.title, low.body, low.urgency], ["Battery low", "20% · 1 h 5 min left.", "normal"], "low message")
        const veryLow = B.message("veryLow", 9, "")
        T.eq([veryLow.title, veryLow.urgency], ["Battery very low", "critical"], "very low is critical")
        T.ok(veryLow.body.indexOf("9% remaining") === 0, "percent without a time estimate")
        const critical = B.message("critical", 5, "")
        T.ok(critical.urgency === "critical" && critical.body.indexOf("Plug in") >= 0, "critical asks to plug in")
        T.ok(B.TITLES.indexOf(low.title) >= 0 && B.TITLES.indexOf(veryLow.title) >= 0 && B.TITLES.indexOf(critical.title) >= 0,
             "titles are known for dismissing")
        T.finish("BatteryTest")
    }
}
