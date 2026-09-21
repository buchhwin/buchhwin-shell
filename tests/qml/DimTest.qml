import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/DimLogic.js" as D

ShellRoot {
    function context(current, extra) {
        return Object.assign({ allowed: true, current: current, maximum: 255, screenOff: false }, extra || {})
    }

    Component.onCompleted: {
        T.eq([D.dimTimeout(10), D.dimTimeout(1), D.dimTimeout(0), D.dimTimeout("x")], [570, 30, 0, 0], "dim 30 s before screen off")
        T.eq([D.dimTarget(200, 255), D.dimTarget(2, 255), D.dimTarget(1, 255), D.dimTarget(0, 255), D.dimTarget(50, 0)],
             [60, 1, 1, 0, 50], "30% of the current value, never 0")

        let result = D.next({ dimmed: false, saved: 0 }, "idle", context(173))
        T.eq([result.state, result.write], [{ dimmed: true, saved: 173 }, 52], "idle dims and saves the raw value")
        const dimmed = result.state
        T.eq(D.next(dimmed, "idle", context(52)).write, -1, "no second dim")
        T.eq(D.next(dimmed, "active", context(52)), { state: { dimmed: false, saved: 0 }, write: 173 }, "activity restores exactly")
        T.eq(D.next(dimmed, "screenOn", context(52)).write, 173, "screen on restores")
        T.eq(D.next(dimmed, "disabled", context(52)).write, 173, "switching off restores")
        T.eq(D.next({ dimmed: false, saved: 0 }, "active", context(100)).write, -1, "activity without dim writes nothing")

        T.eq(D.next({ dimmed: false, saved: 0 }, "idle", context(173, { allowed: false })).write, -1, "not allowed (nested, setting, no backlight)")
        T.eq(D.next({ dimmed: false, saved: 0 }, "idle", context(173, { screenOff: true })).write, -1, "screen already off")
        result = D.next({ dimmed: false, saved: 0 }, "idle", context(1))
        T.eq([result.state.dimmed, result.write], [false, -1], "already at the minimum")
        T.eq(D.next({ dimmed: false, saved: 0 }, "idle", context(0, { maximum: 0 })).write, -1, "no backlight")
        T.finish("DimTest")
    }
}
