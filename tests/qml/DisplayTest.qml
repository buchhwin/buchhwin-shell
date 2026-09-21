import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/display/DisplayLogic.js" as D

ShellRoot {
    readonly property var sample: [
        { name: "DP-1", description: "Sample Monitor 27", make: "Sample", model: "27", width: 2560, height: 1440, refreshRate: 143.97,
          x: 1920, y: 0, scale: 1, transform: 0, vrr: false, disabled: false, focused: false,
          availableModes: ["2560x1440@143.97Hz", "2560x1440@59.95Hz", "1920x1080@60.00Hz", "garbage"] },
        { name: "eDP-1", description: "", width: 2880, height: 1800, refreshRate: 120, x: 0, y: 0, scale: 1.5,
          transform: 0, vrr: true, disabled: false, focused: true, availableModes: [] }
    ]

    Component.onCompleted: {
        const monitors = D.parseMonitors(JSON.stringify(sample))
        T.eq(monitors.map(m => m.name), ["eDP-1", "DP-1"], "sorted by position")
        const dp = monitors[1], edp = monitors[0]
        T.eq(dp.modes.length, 3, "invalid modes dropped, duplicates merged")
        T.eq(edp.modes.length, 1, "current mode always available")
        T.eq([edp.vrr, dp.vrr], [1, 0], "vrr normalised")
        T.eq(D.resolutions(dp).map(r => r.value), ["2560x1440", "1920x1080"], "unique resolutions, largest first")
        T.eq(D.refreshRates(dp, 2560, 1440).map(r => r.label), ["144 Hz", "60 Hz"], "refresh rates per resolution")
        T.eq(D.scaleChoices(1.6), [1, 1.25, 1.5, 1.6, 1.75, 2], "custom scale kept in choices")
        T.eq(D.logicalSize(edp), { width: 1920, height: 1200 }, "logical size uses scale")
        T.eq(D.logicalSize(Object.assign({}, dp, { transform: 1 })), { width: 1440, height: 2560 }, "rotation swaps size")

        T.eq(D.ruleFor(dp), "DP-1,2560x1440@143.97,1920x0,1,transform,0,vrr,0", "monitor rule")
        T.eq(D.ruleFor(Object.assign({}, dp, { disabled: true })), "DP-1,disable", "disable rule")

        const moved = D.update(monitors, "DP-1", { x: 1950, y: 30 })
        T.ok(D.changed(monitors, moved) && !D.changed(monitors, monitors.slice()), "change detection")
        T.eq(D.snap(moved, "DP-1", 1935, 12, 40), { x: 1920, y: 0 }, "snaps to the right edge and top")
        T.eq(D.snap(moved, "DP-1", -2540, 1210, 40), { x: -2560, y: 1200 }, "snaps to the left and below")
        T.eq(D.snap(moved, "DP-1", 5000, 700, 40), { x: 5000, y: 700 }, "far away does not snap")

        // Arrow-key nudging. The step is in logical pixels and the snap
        // threshold is the step, so the last press before an edge lands on it
        // rather than one step short - which is the misalignment the keys
        // exist to remove.
        const apart = D.update(monitors, "DP-1", { x: 2000, y: 300 })
        T.eq(D.nudge(apart, "DP-1", 1, 0, 10, 10), { x: 2010, y: 300 }, "right by one step")
        T.eq(D.nudge(apart, "DP-1", -1, 0, 10, 10), { x: 1990, y: 300 }, "left by one step")
        T.eq(D.nudge(apart, "DP-1", 0, 1, 10, 10), { x: 2000, y: 310 }, "down by one step")
        T.eq(D.nudge(apart, "DP-1", 0, -1, 10, 10), { x: 2000, y: 290 }, "up by one step")
        T.eq(D.nudge(apart, "DP-1", 0, 0, 10, 10), { x: 2000, y: 300 }, "no direction, no move")
        T.eq(D.nudge(apart, "DP-1", 1, 0, 1, 1), { x: 2001, y: 300 }, "a fine step is one pixel")
        // eDP-1 sits at 0,0 and is 1920 logical wide, so its right edge is
        // 1920: a monitor eight pixels past it comes back onto it.
        T.eq(D.nudge(D.update(monitors, "DP-1", { x: 1928, y: 0 }), "DP-1", -1, 0, 10, 10),
             { x: 1920, y: 0 }, "a step towards a near edge lands on the edge, not past it")
        T.eq(D.nudge(apart, "sideways", 1, 0, 10, 10), null, "a monitor nobody knows is refused, not answered")
        T.eq(D.nudge(apart, "DP-1", 1, 0, 0, 0).x, 2001, "a step of zero is still one pixel, never a freeze")
        T.ok(D.overlapping(D.update(monitors, "DP-1", { x: 100 })) && !D.overlapping(monitors), "overlap detection")
        T.eq(D.normalize(D.update(D.update(monitors, "eDP-1", { x: -1920 }), "DP-1", { x: 0, y: -200 })).map(m => [m.x, m.y]),
             [[0, 200], [1920, 0]], "layout normalised to 0,0")
        T.eq(D.enabledCount(D.update(monitors, "DP-1", { disabled: true })), 1, "enabled count")

        const saved = D.toSaved(D.update(monitors, "DP-1", { width: 1920, height: 1080, refresh: 60, scale: 1.25, x: 1920 }))
        const restored = D.applySaved(monitors, saved)
        T.eq([restored[1].width, restored[1].scale, restored[1].refresh], [1920, 1.25, 60], "saved settings applied")
        const unknownMode = D.toSaved(D.update(monitors, "DP-1", { width: 800, height: 600, refresh: 75 }))
        T.eq(D.applySaved(monitors, unknownMode)[1].width, 2560, "unavailable saved mode keeps the current one")
        const allOff = D.toSaved(monitors.map(m => Object.assign({}, m, { disabled: true })))
        T.eq(D.enabledCount(D.applySaved(monitors, allOff)), 2, "saved settings never disable every monitor")
        T.eq(D.applySaved(monitors, { version: 9 }), monitors, "unknown file version ignored")
        const docked = [{ name: "eDP-1", disabled: false }, { name: "DP-2", disabled: false }]
        T.ok(D.isInternal("eDP-1") && D.isInternal("LVDS-1") && !D.isInternal("DP-2"), "internal panels detected")
        T.eq(D.lidPlan(docked, "eDP-1"), "disable", "lid closed with a dock disables the panel")
        T.eq(D.lidPlan([docked[0], { name: "DP-2", disabled: true }], "eDP-1"), "dpms", "lid closed without another display only turns the panel off")
        T.eq(D.lidPlan(docked, "missing"), "none", "no internal panel")
        T.eq(D.lidAdjusted(docked, "eDP-1", true).map(m => m.disabled), [true, false], "panel stays off while closed")
        T.eq(D.lidAdjusted([{ name: "eDP-1", disabled: true }], "eDP-1", true)[0].disabled, false, "last display unplugged: panel enabled again")
        T.eq(D.lidAdjusted(docked, "eDP-1", false), docked, "open lid leaves the layout alone")
        T.finish("DisplayTest")
    }
}
