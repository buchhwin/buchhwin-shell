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
        // 59.94 and 60.00 both round to 60: two segments saying "60 Hz" would
        // be a choice nobody can make, so those two keep their decimals while
        // a rate of its own stays whole - and only within the one resolution.
        const ntsc = D.parseMonitors(JSON.stringify([{ name: "HDMI-A-1", width: 1920, height: 1080, refreshRate: 60, x: 0, y: 0, scale: 1,
            availableModes: ["1920x1080@60.00Hz", "1920x1080@59.94Hz", "1920x1080@50.00Hz", "1280x720@60.00Hz"] }]))[0]
        T.eq(D.refreshRates(ntsc, 1920, 1080).map(r => r.label), ["60.00 Hz", "59.94 Hz", "50 Hz"], "colliding whole-hertz labels keep their decimals")
        T.eq(D.refreshRates(ntsc, 1920, 1080).map(r => r.value), ["60.00", "59.94", "50.00"], "values stay two-decimal")
        T.eq(D.refreshRates(ntsc, 1280, 720).map(r => r.label), ["60 Hz"], "a rate alone at its resolution stays whole")
        T.eq(D.scaleChoices(1.6), [1, 1.25, 1.5, 1.6, 1.75, 2], "custom scale kept in choices")
        T.eq(D.logicalSize(edp), { width: 1920, height: 1200 }, "logical size uses scale")
        T.eq(D.logicalSize(Object.assign({}, dp, { transform: 1 })), { width: 1440, height: 2560 }, "rotation swaps size")

        // Hyprland corrects a scale that does not divide the mode into whole
        // logical pixels (nearest 1/120, then the first clean multiple up or
        // down), and the geometry has to agree with it: 1.67 on a 4K screen is
        // 200/120 and 2304 wide, not 2299.
        T.eq(D.effectiveScale(1.67, 3840, 2160), 200 / 120, "1.67 on 4K is Hyprland's 200/120")
        T.eq(D.effectiveScale(1.5, 2880, 1800), 1.5, "a clean scale is kept")
        T.eq(D.effectiveScale(1.75, 3840, 2160), 200 / 120, "1.75 on 4K has no clean multiple above it within reach, so it is 200/120 too")
        T.eq(D.effectiveScale(1.6, 3840, 2160), 1.6, "1.6 is 192/120 and clean")
        T.eq(D.effectiveScale(1.33, 1920, 1080), 160 / 120, "1.33 on full HD is 160/120")
        const uhd = { name: "DP-4", width: 3840, height: 2160, scale: 1.67, transform: 0, x: 0, y: 300, disabled: false }
        T.eq(D.logicalSize(uhd), { width: 2304, height: 1296 }, "the logical size follows the effective scale")
        T.eq(D.logicalSize({ width: 1920, height: 1080, scale: 1, transform: 3 }), { width: 1080, height: 1920 }, "270 degrees swaps the size")

        // The one scale X11 gets: the largest any enabled screen runs at.
        T.eq(D.x11Scale(monitors), 1.5, "x11 scale is the largest screen's")
        T.eq(D.x11Scale([dp]), 1, "nothing scaled, nothing to tell")
        T.eq(D.x11Scale(D.update(monitors, "eDP-1", { disabled: true })), 1, "a disabled screen does not count")
        T.eq(D.x11Scale([]), 1, "no monitors is 1")
        T.eq(D.x11Scale(monitors.concat([Object.assign({}, dp, { name: "DP-2", scale: 2 })])), 2, "two scaled screens: the larger")

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

        // A layout written with the old widths: positions summed from
        // 2299-px widths, five pixels short of Hyprland's 2304 - two overlaps
        // that the old width never showed.
        const desk = [
            uhd,
            Object.assign({}, uhd, { name: "DP-5", x: 2299 }),
            { name: "DP-6", width: 1920, height: 1080, scale: 1, transform: 3, x: 4598, y: 0, disabled: false }
        ]
        T.ok(D.overlapping(desk), "the old layout overlaps once the widths are right")
        T.eq(D.spread(desk).map(m => m.x), [0, 2304, 4608], "spread pushes each monitor out of its left neighbour")
        T.ok(!D.overlapping(D.spread(desk)), "and nothing overlaps afterwards")
        T.eq(D.spread(D.spread(desk)).map(m => m.x), [0, 2304, 4608], "spreading a clean layout changes nothing")
        T.eq(D.spread(D.update(desk, "DP-5", { disabled: true })).map(m => m.x), [0, 2299, 4598], "a disabled monitor is neither moved nor in the way")
        // Dropping a monitor onto another pops it out along the axis that
        // needs the smaller move, on the side its centre is.
        T.eq(D.snap(monitors, "DP-1", 1500, 100, 40), { x: 1920, y: 100 }, "dropped half onto the neighbour: out to its right edge")
        T.eq(D.snap(monitors, "DP-1", -2500, 0, 40), { x: -2560, y: 0 }, "dropped onto it from the left: out to its left edge")
        T.eq(D.snap(monitors, "DP-1", 0, 1100, 40), { x: 0, y: 1200 }, "dropped onto its lower part: below it")
        T.eq(D.snap(monitors, "DP-1", 100, 0, 40), { x: 100, y: 1200 }, "dropped squarely onto it: below, the nearer way out")
        T.eq(D.nudge(monitors, "DP-1", -1, 0, 10, 10), { x: 1920, y: 0 }, "a nudge into the neighbour stays on its edge")
        T.ok(!D.overlapping(D.applySaved(monitors, D.toSaved(D.update(monitors, "DP-1", { x: 100 })))), "a saved layout that overlaps loads spread apart")
        // The file is then corrected once: only the positions that moved, and
        // entries of monitors that are not connected stay as they were.
        const overlapFile = D.toSaved(D.update(monitors, "DP-1", { x: 100 }))
        overlapFile.monitors["HDMI-A-9"] = { description: "elsewhere", width: 1920, height: 1080, refresh: 60, x: 7000, y: 0, scale: 1, transform: 0, vrr: 0, disabled: false }
        const corrected = D.repairSaved(overlapFile, D.applySaved(monitors, overlapFile))
        T.ok(corrected !== null && corrected.monitors["DP-1"].x === 100 && corrected.monitors["DP-1"].y === 1200, "the corrected file carries the spread position")
        T.eq(corrected.monitors["HDMI-A-9"].x, 7000, "an entry for a monitor that is not connected is kept")
        T.eq(D.repairSaved(corrected, D.applySaved(monitors, corrected)), null, "a corrected file needs no second correction")
        T.eq(D.repairSaved(D.toSaved(monitors), D.applySaved(monitors, D.toSaved(monitors))), null, "a clean file is left alone")
        T.eq(D.normalize(D.update(D.update(monitors, "eDP-1", { x: -1920 }), "DP-1", { x: 0, y: -200 })).map(m => [m.x, m.y]),
             [[0, 200], [1920, 0]], "layout normalised to 0,0")
        T.eq(D.enabledCount(D.update(monitors, "DP-1", { disabled: true })), 1, "enabled count")

        const saved = D.toSaved(D.update(monitors, "DP-1", { width: 1920, height: 1080, refresh: 60, scale: 1.25, x: 1920 }))
        const restored = D.applySaved(monitors, saved)
        T.eq([restored[1].width, restored[1].scale, restored[1].refresh], [1920, 1.25, 60], "saved settings applied")
        const unknownMode = D.toSaved(D.update(monitors, "DP-1", { width: 800, height: 600, refresh: 75 }))
        T.eq(D.applySaved(monitors, unknownMode)[1].width, 2560, "unavailable saved mode keeps the current one")
        const allOff = D.toSaved(monitors.map(m => Object.assign({}, m, { disabled: true })))
        // The panel's "off" counts only when kept with the lid open (below);
        // marked so, both offs count, and the file is still refused.
        allOff.monitors["eDP-1"].lidOpen = true
        T.eq(D.enabledCount(D.applySaved(monitors, allOff)), 2, "saved settings never disable every monitor")
        T.eq(D.applySaved(monitors, { version: 9 }), monitors, "unknown file version ignored")
        // A saved scale is taken within a range, not against a list that the
        // value itself was appended to (which refused nothing).
        const scaled = value => D.applySaved(monitors, D.toSaved(D.update(monitors, "DP-1", { scale: value })))[1].scale
        T.eq(scaled(1.6), 1.6, "a custom scale is kept")
        T.eq(scaled(0.5), 0.5, "down to a half")
        T.eq(scaled(3), 3, "and up to three")
        T.eq(scaled(0), dp.scale, "zero keeps the monitor's own scale")
        T.eq(scaled(7), dp.scale, "so does a scale no panel runs at")
        T.eq(scaled("x"), dp.scale, "and a scale that is not a number")
        T.eq([D.validScale(0.49), D.validScale(3.01), D.validScale(-1)], [false, false, false], "the edges of the range")
        const docked = [{ name: "eDP-1", disabled: false }, { name: "DP-2", disabled: false }]
        T.ok(D.isInternal("eDP-1") && D.isInternal("LVDS-1") && !D.isInternal("DP-2"), "internal panels detected")
        T.eq(D.lidPlan(docked, "eDP-1"), "disable", "lid closed with a dock disables the panel")
        T.eq(D.lidPlan([docked[0], { name: "DP-2", disabled: true }], "eDP-1"), "dpms", "lid closed without another display only turns the panel off")
        T.eq(D.lidPlan(docked, "missing"), "none", "no internal panel")
        T.eq(D.lidAdjusted(docked, "eDP-1", true).map(m => m.disabled), [true, false], "panel stays off while closed")
        T.eq(D.lidAdjusted([{ name: "eDP-1", disabled: true }], "eDP-1", true)[0].disabled, false, "last display unplugged: panel enabled again")
        T.eq(D.lidAdjusted(docked, "eDP-1", false), docked, "open lid leaves the layout alone")

        // Before the lid is known (a shell restart at the dock with the lid
        // shut): a panel that is off now stays off at the startup apply, and
        // nothing else is held back.
        const panelOff = [{ name: "eDP-1", disabled: true }, { name: "DP-2", disabled: false }]
        T.eq(D.lidPending(docked, panelOff, "eDP-1").map(m => m.disabled), [true, false], "a saved \"on\" waits for the lid")
        T.eq(D.lidPending(docked, docked, "eDP-1"), docked, "a panel that is on now is left alone")
        const savedOff = [{ name: "eDP-1", disabled: true }, { name: "DP-2", disabled: false }]
        T.eq(D.lidPending(savedOff, panelOff, "eDP-1"), savedOff, "a saved \"off\" needs no holding")
        const onlyPanel = [{ name: "eDP-1", disabled: false }, { name: "DP-2", disabled: true }]
        T.eq(D.lidPending(onlyPanel, panelOff, "eDP-1"), onlyPanel, "never holds the last screen off")
        T.eq(D.lidPending(docked, panelOff, ""), docked, "no laptop panel, nothing to hold")
        T.eq(D.lidPending(docked, [{ name: "DP-2", disabled: false }], "eDP-1"), docked, "a panel the compositor does not list")

        // ---- Keep with the lid shut (16.10.) ---------------------------
        //
        // Docked with the lid shut, the lid has switched the panel off at
        // runtime, and `hyprctl monitors all` reports it off at its last
        // place - on top of the screen below it. Keep saved that "off" as
        // the user's, and the panel went dark at every desk afterwards,
        // lid open or not. (Invented descriptions throughout.)
        const dockDesk = [
            { name: "eDP-1", description: "Sample Panel 14", width: 1920, height: 1200, refreshRate: 60, x: 0, y: 0, scale: 1,
              disabled: true, availableModes: ["1920x1200@60.00Hz"] },
            { name: "DP-4", description: "Sample FHD B2", width: 1920, height: 1080, refreshRate: 60, x: 0, y: 120, scale: 1,
              availableModes: ["1920x1080@60.00Hz"] },
            { name: "DP-6", description: "Sample WUXGA C3", width: 1920, height: 1200, refreshRate: 59.95, x: 1920, y: 0, scale: 1,
              availableModes: ["1920x1200@59.95Hz"] }
        ]
        const lidShut = D.parseMonitors(JSON.stringify(dockDesk))
        const lidOpen = D.update(lidShut, "eDP-1", { disabled: false })
        const keptShut = D.kept(null, lidShut, "eDP-1", true, null)
        T.eq([keptShut.monitors["eDP-1"].disabled, keptShut.monitors["eDP-1"].lidOpen], [false, false],
             "kept with the lid shut: the panel is saved on, and marked as not kept with the lid open")
        T.eq([keptShut.monitors["DP-4"].lidOpen, keptShut.monitors["DP-6"].lidOpen], [undefined, undefined],
             "only the panel carries the mark")
        T.ok(!D.overlapping(D.update(lidOpen, "eDP-1", { x: keptShut.monitors["eDP-1"].x, y: keptShut.monitors["eDP-1"].y })),
             "and at a place clear of the screens arranged while it was off")
        // At the end of them: the nearest way out was above the left screen,
        // which made the panel monitor 1 and moved every workspace block.
        T.eq([keptShut.monitors["eDP-1"].x, keptShut.monitors["eDP-1"].y], [3840, 0], "right of them, level with the top")
        T.eq(D.placeAfter([{ name: "A", x: 0, y: 0, width: 100, height: 100, scale: 1, transform: 0 }], "A"), { x: 0, y: 0 },
             "alone, a monitor stays where it is")
        const reopened = D.applySaved(lidOpen, keptShut, "eDP-1")
        T.eq(reopened.map(m => [m.name, m.disabled, m.x, m.y]).filter(m => m[0] !== "eDP-1"), [["DP-4", false, 0, 120], ["DP-6", false, 1920, 0]],
             "lid open at the desk: the screens stay where they were kept")
        T.eq(reopened.find(m => m.name === "eDP-1").disabled, false, "and the panel is on")
        T.eq(D.repairSaved(keptShut, reopened, "eDP-1"), null, "a file kept with the lid shut needs no correction")
        // The finding's case: laptop on the desk, lid open, a projector
        // plugged in - the target had the panel off.
        const projector = D.parseMonitors(JSON.stringify([
            { name: "eDP-1", description: "Sample Panel 14", width: 1920, height: 1200, refreshRate: 60, x: 0, y: 0, scale: 1, availableModes: [] },
            { name: "HDMI-A-1", description: "Sample Beamer", width: 1920, height: 1080, refreshRate: 60, x: 1920, y: 0, scale: 1, availableModes: [] }]))
        T.eq(D.applySaved(projector, keptShut, "eDP-1").map(m => m.disabled), [false, false], "a projector at another desk leaves the panel on")

        // What the panel is saved as: its kept entry first (an "off" chosen
        // with the lid open stays), then the panel before the lid took it.
        const chosenOff = D.toSaved(lidOpen)
        chosenOff.monitors["eDP-1"] = Object.assign({}, chosenOff.monitors["eDP-1"], { disabled: true, lidOpen: true })
        const keptChosen = D.kept(chosenOff, lidShut, "eDP-1", true, null)
        T.eq([keptChosen.monitors["eDP-1"].disabled, keptChosen.monitors["eDP-1"].lidOpen], [true, true],
             "an off chosen with the lid open survives a Keep with the lid shut")
        T.eq(D.applySaved(lidOpen, keptChosen, "eDP-1").find(m => m.name === "eDP-1").disabled, true, "and is applied")
        const before = Object.assign({}, lidOpen[0], { scale: 1.25 })
        T.eq(D.kept(null, lidShut, "eDP-1", true, before).monitors["eDP-1"].scale, 1.25, "no entry yet: the panel as it was before the lid")
        const scaledFile = D.toSaved(D.update(lidOpen, "eDP-1", { scale: 1.5, x: -1280, y: 0 }))
        T.eq(D.kept(scaledFile, lidShut, "eDP-1", true, before).monitors["eDP-1"].scale, 1.5, "a kept entry wins over it")
        T.eq(D.kept(null, lidOpen, "eDP-1", false, null).monitors["eDP-1"].lidOpen, true, "kept with the lid open: marked")
        const userOff = D.kept(null, D.update(lidOpen, "eDP-1", { disabled: true }), "eDP-1", false, null)
        T.eq(D.applySaved(lidOpen, userOff, "eDP-1").find(m => m.name === "eDP-1").disabled, true,
             "switched off with the lid open, it stays off")
        T.eq(D.kept(null, D.update(lidShut, "eDP-1", { disabled: false }), "eDP-1", true, null).monitors["eDP-1"].disabled, false,
             "lid shut but the panel on (the only screen): saved as it is")

        // Files written before the mark: a panel "off" is not applied, the
        // panel goes last so the desk's screens keep their places, and the
        // repair clears the flag in the file.
        const oldFile = D.toSaved(lidShut)
        const healed = D.applySaved(lidOpen, oldFile, "eDP-1")
        T.eq(healed.find(m => m.name === "eDP-1").disabled, false, "an old file's panel off is not applied")
        T.eq(healed.filter(m => m.name !== "eDP-1").map(m => [m.x, m.y]), [[0, 120], [1920, 0]], "the screens keep their saved places")
        T.ok(!D.overlapping(healed), "the panel is moved out of them instead")
        T.eq(healed.filter(m => m.name === "eDP-1").map(m => [m.x, m.y]), [[3840, 0]], "to the end of the layout")
        T.eq(D.spread(D.update(lidOpen, "eDP-1", { x: -1920 }), "eDP-1").find(m => m.name === "eDP-1").x, -1920,
             "a panel that lands on nobody keeps its place")
        T.eq(D.applySaved(lidOpen, oldFile).find(m => m.name === "eDP-1").disabled, false, "the connector name finds the panel without a name passed")
        const cleaned = D.repairSaved(oldFile, healed, "eDP-1")
        T.ok(cleaned !== null && cleaned.monitors["eDP-1"].disabled === false, "the repair clears the old off")
        T.eq([cleaned.monitors["DP-4"].x, cleaned.monitors["DP-4"].y], [0, 120], "and leaves the screens' places alone")
        T.eq(D.repairSaved(cleaned, D.applySaved(lidOpen, cleaned, "eDP-1"), "eDP-1"), null, "once")
        T.eq(D.applySaved(lidOpen, D.toSaved(D.update(lidOpen, "DP-4", { disabled: true })), "eDP-1")
             .find(m => m.name === "DP-4").disabled, true, "an external screen's off is applied as before")

        // ---- Two desks, the same connector names -----------------------
        //
        // A dock names its screens in the order it finds them: DP-4 is a 4K
        // screen at one desk and a Full HD one at the other.
        const deskA = D.parseMonitors(JSON.stringify([
            { name: "DP-4", description: "Sample 4K A1", width: 3840, height: 2160, refreshRate: 60, x: 0, y: 0, scale: 1.67,
              availableModes: ["3840x2160@60.00Hz", "1920x1080@60.00Hz"] },
            { name: "DP-5", description: "Sample 4K A2", width: 3840, height: 2160, refreshRate: 60, x: 2304, y: 0, scale: 1.67,
              availableModes: ["3840x2160@60.00Hz", "1920x1080@60.00Hz"] }]))
        const deskB = D.parseMonitors(JSON.stringify([dockDesk[1]]))
        const fileB = D.kept(null, deskB, "", false, null)
        T.eq(D.matchKey(fileB.monitors, deskA[0], deskA), null, "another screen under the same name is not a match")
        T.eq(D.applySaved(deskA, fileB).map(m => [m.width, m.scale]), [[3840, 1.67], [3840, 1.67]],
             "so the 4K screen keeps its own mode and scale")
        const fileA = D.kept(null, deskA, "", false, null)
        const backAtB = D.kept(fileA, deskB, "", false, null)
        T.eq(Object.keys(backAtB.monitors).sort(), ["DP-4", "DP-4@Sample 4K A1", "DP-5"],
             "Keep merges: the other desk's screens stay, the one on a taken name moves aside")
        T.eq(backAtB.monitors["DP-4"].description, "Sample FHD B2", "the connected screen has its name")
        const atA = D.applySaved(D.update(D.update(deskA, "DP-4", { scale: 1 }), "DP-5", { scale: 1 }), backAtB)
        T.eq(atA.map(m => [m.name, m.scale, m.x]), [["DP-4", 1.67, 0], ["DP-5", 1.67, 2304]], "back at the first desk, both find their entries")
        const backAtA = D.kept(backAtB, deskA, "", false, null)
        T.eq(Object.keys(backAtA.monitors).sort(), ["DP-4", "DP-4@Sample FHD B2", "DP-5"], "and the round trip loses nothing and piles nothing up")
        T.eq(D.matchKey({ "DP-7": backAtB.monitors["DP-4@Sample 4K A1"] }, deskA[0], deskA), "DP-7",
             "the same screen on another connector finds its entry")
        T.eq(D.matchKey({ "DP-4": { description: "" } }, deskA[0], deskA), "DP-4", "no description on one side: the name decides")
        T.eq(D.matchKey(fileA.monitors, Object.assign({}, deskA[0], { description: "" }), deskA), "DP-4", "on the other side too")
        // Twins (same description): each keeps the entry under its own
        // name, and a twin on a new connector does not take the other's.
        const twinFile = { version: 1, monitors: {
            "DP-1": { description: "Sample Twin", width: 1920, height: 1080, refresh: 60, x: 0, y: 0, scale: 1, transform: 0, vrr: 0, disabled: false },
            "DP-2": { description: "Sample Twin", width: 1920, height: 1080, refresh: 60, x: 1920, y: 0, scale: 1, transform: 0, vrr: 0, disabled: false } } }
        const twins = [{ name: "DP-1", description: "Sample Twin" }, { name: "DP-3", description: "Sample Twin" }]
        T.eq(twins.map(m => D.matchKey(twinFile.monitors, m, twins)), ["DP-1", "DP-2"], "twins never share an entry")
        T.eq(D.matchKey({ "DP-1": twinFile.monitors["DP-1"] }, twins[1], twins), null, "and the one already held is not taken")
        T.eq(D.matchKey({ "DP-1": null, "DP-2": "x" }, twins[0], twins), null, "an entry that is not an object is no entry")
        T.eq(D.kept({ version: 1, monitors: { "DP-4": { description: "" } } }, deskB, "", false, null).monitors["DP-4"].description,
             "Sample FHD B2", "an entry without a description under the connected name is replaced, as before")

        // ---- Automatic Laptop / Docked mode ----------------------------
        T.eq(D.suggestedMode(["DP-4", "DP-6"], "eDP-1"), "docked", "docked with the lid shut: the panel is off but there")
        T.eq(D.suggestedMode(["eDP-1", "DP-4"], "eDP-1"), "docked", "docked with the lid open")
        T.eq(D.suggestedMode(["eDP-1"], "eDP-1"), "laptop", "the panel alone")
        T.eq(D.suggestedMode(["eDP-1", "DP-4"], ""), "docked", "before the monitors are read the screens decide")
        T.eq(D.suggestedMode(["DP-1", "HDMI-A-1"], ""), "", "a desktop keeps its mode")
        T.eq(D.suggestedMode(["WAYLAND-1", "BUCHTEST"], "WAYLAND-1"), "docked", "a named panel counts like eDP")
        T.eq([D.hasInternalPanel(["DP-4"], "eDP-1"), D.hasInternalPanel(["DP-4"], ""), D.externalCount(["eDP-1", "DP-4", "DP-6"], "eDP-1")],
             [true, false, 2], "the two halves")
        T.eq(D.suggestedMode(null, undefined), "", "nothing known")
        T.finish("DisplayTest")
    }
}
