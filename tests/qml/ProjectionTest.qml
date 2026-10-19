import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/display/DisplayLogic.js" as D
import "../../services/display/ProjectionLogic.js" as P

// Mirrors in the monitor layout (Settings > Displays' "Mirror") and the
// display switcher's four choices (ProjectionLogic). Invented descriptions
// throughout.
ShellRoot {
    // A laptop at a meeting room's projector, as `hyprctl -j monitors all`
    // reports it: the panel at 0,0 and the projector right of it.
    readonly property var room: [
        { id: 0, name: "eDP-1", description: "Sample Panel 14", width: 1920, height: 1200, refreshRate: 60, x: 0, y: 0, scale: 1,
          mirrorOf: "none", focused: true, availableModes: ["1920x1200@60.00Hz"] },
        { id: 1, name: "HDMI-A-1", description: "Sample Beamer", width: 1920, height: 1080, refreshRate: 60, x: 1920, y: 0, scale: 1,
          mirrorOf: "none", availableModes: ["1920x1080@60.00Hz", "1280x720@60.00Hz"] }
    ]

    Component.onCompleted: {
        const live = D.parseMonitors(JSON.stringify(room))
        T.eq(live.map(m => m.mirror), ["", ""], "a monitor of its own mirrors nothing")

        // ---- Reading a mirror ------------------------------------------------
        // Hyprland 0.56 names the source by its id; older builds by name.
        const byId = D.parseMonitors(JSON.stringify([room[0], Object.assign({}, room[1], { mirrorOf: "0", x: 0, y: 0 })]))
        T.eq(byId.find(m => m.name === "HDMI-A-1").mirror, "eDP-1", "mirrorOf as the source's id")
        const byName = D.parseMonitors(JSON.stringify([room[0], Object.assign({}, room[1], { mirrorOf: "eDP-1" })]))
        T.eq(byName.find(m => m.name === "HDMI-A-1").mirror, "eDP-1", "mirrorOf as the source's name")
        T.eq(D.parseMonitors(JSON.stringify([Object.assign({}, room[1], { mirrorOf: "1" })]))[0].mirror, "", "never a mirror of itself")
        T.eq(D.parseMonitors(JSON.stringify([Object.assign({}, room[1], { mirrorOf: "7" })]))[0].mirror, "", "a source nobody lists is none")
        T.eq(D.parseMonitors(JSON.stringify([Object.assign({}, room[1], { mirrorOf: undefined })]))[0].mirror, "", "no field at all is none")
        const mirrored = byId

        // ---- A mirror has no place of its own -----------------------------------
        const beamer = mirrored.find(m => m.name === "HDMI-A-1")
        T.ok(D.isMirror(beamer) && !D.shown(beamer) && D.shown(mirrored[0]), "a mirror is on but not shown in the layout")
        T.eq(D.ruleFor(beamer), "HDMI-A-1,1920x1080@60.00,mirror,eDP-1,1,transform,0,vrr,0", "a mirror's rule has no position")
        T.ok(!D.changed(mirrored, D.update(mirrored, "HDMI-A-1", { x: 1920 })), "so a mirror read back at its source's place is no change")
        T.ok(D.changed(live, mirrored), "becoming a mirror is one")
        T.ok(!D.overlapping(mirrored), "standing on its source is no overlap")
        T.eq(D.shownCount(mirrored), 1, "one screen with a place")
        T.eq(D.normalize(D.update(mirrored, "eDP-1", { x: 100 })).map(m => [m.name, m.x]), [["eDP-1", 0], ["HDMI-A-1", 0]],
             "normalising moves the screens, a mirror keeps its own place")
        T.eq(D.spread(mirrored).map(m => [m.x, m.y]), [[0, 0], [0, 0]], "spread leaves a mirror where it is")
        T.eq(D.placeApart(mirrored, "eDP-1", 0, 0), { x: 0, y: 0 }, "and nothing is pushed out of a mirror")
        T.eq(D.snap(D.update(mirrored, "HDMI-A-1", { x: 1950 }), "eDP-1", 30, 0, 40), { x: 30, y: 0 }, "nor snapped to its edges")
        T.eq(D.mirrorChoices(mirrored, "HDMI-A-1"), ["eDP-1"], "a mirror's source can be any other screen of its own")
        T.eq(D.mirrorChoices(mirrored, "eDP-1"), [], "but never a mirror")
        T.eq(D.mirrorChoices(D.update(live, "HDMI-A-1", { disabled: true }), "eDP-1"), [], "nor a screen that is off")

        // A mirror whose source went (off, gone, a mirror itself) is a screen
        // of its own again, at the end of the layout where its place is taken.
        T.ok(D.settleMirrors(mirrored) === mirrored, "a sound layout comes back as the very same list")
        const sourceOff = D.settleMirrors(D.update(mirrored, "eDP-1", { disabled: true }))
        T.eq(sourceOff.find(m => m.name === "HDMI-A-1").mirror, "", "the source off: the mirror is a screen again")
        const orphan = D.settleMirrors(D.update(mirrored, "HDMI-A-1", { mirror: "DP-9", x: 0, y: 0 }))
        T.eq(orphan.map(m => [m.name, m.mirror, m.x, m.y]), [["eDP-1", "", 0, 0], ["HDMI-A-1", "", 1920, 0]],
             "a source nobody lists: on its own, moved out of the panel to the end of the layout")
        const chain = D.settleMirrors(D.update(D.update(mirrored, "eDP-1", { mirror: "HDMI-A-1" }), "HDMI-A-1", { mirror: "eDP-1" }))
        T.eq(chain.filter(D.isMirror).length, 0, "two that mirror each other are both screens again")
        T.ok(!D.overlapping(chain), "and nothing overlaps afterwards")

        // ---- Saved: Settings > Displays' Keep --------------------------------
        const kept = D.toSaved(mirrored)
        T.eq([kept.monitors["HDMI-A-1"].mirror, kept.monitors["HDMI-A-1"].mirrorDescription], ["eDP-1", "Sample Panel 14"],
             "a mirror is kept with its source's name and description")
        T.eq([kept.monitors["eDP-1"].mirror, kept.monitors["eDP-1"].mirrorDescription], [undefined, undefined],
             "an entry of its own is written as it always was")
        T.eq(Object.keys(D.toSaved(live).monitors["eDP-1"]).sort(),
             ["description", "disabled", "height", "refresh", "scale", "transform", "vrr", "width", "x", "y"], "the same keys as ever")
        const again = D.applySaved(live, kept, "eDP-1")
        T.eq(again.map(m => [m.name, m.mirror]), [["eDP-1", ""], ["HDMI-A-1", "eDP-1"]], "plugged in again, the projector mirrors the panel")
        const renamed = D.parseMonitors(JSON.stringify([Object.assign({}, room[0], { name: "eDP-2" }), room[1]]))
        T.eq(D.applySaved(renamed, kept).find(m => m.name === "HDMI-A-1").mirror, "eDP-2", "the source is found by its description")
        const strangerPanel = D.parseMonitors(JSON.stringify([Object.assign({}, room[0], { description: "Sample Panel 16" }), room[1]]))
        T.eq(D.applySaved(strangerPanel, kept).find(m => m.name === "HDMI-A-1").mirror, "",
             "another screen under the source's name is not the source")
        const keptOff = D.toSaved(D.update(mirrored, "eDP-1", { disabled: true }))
        keptOff.monitors["eDP-1"].lidOpen = true
        const sourceKeptOff = D.applySaved(live, keptOff, "eDP-1")
        T.eq(sourceKeptOff.find(m => m.name === "HDMI-A-1").mirror, "", "the source kept off: no mirror")
        T.ok(!D.overlapping(sourceKeptOff), "and the projector stands clear")
        T.eq(D.applySaved(mirrored, D.toSaved(live), "eDP-1").find(m => m.name === "HDMI-A-1").mirror, "",
             "a file of screens of their own ends a mirror the live state has")
        T.eq(D.repairSaved(kept, D.applySaved(mirrored, kept, "eDP-1"), "eDP-1"), null, "a kept mirror needs no repair")
        const keptOwnPlace = D.toSaved(D.update(mirrored, "HDMI-A-1", { x: 1920 }))
        T.eq(D.repairSaved(keptOwnPlace, mirrored, "eDP-1"), null,
             "a mirror read at its source's place does not overwrite its own in the file")
        T.eq(D.kept(null, mirrored, "eDP-1", false, null).monitors["HDMI-A-1"].mirror, "eDP-1", "Keep writes the mirror")

        // ---- The plan with a choice laid over it --------------------------------
        const dup = base => P.target(base, "duplicate", "eDP-1", false, "eDP-1").list
        const plan = D.savedTarget(live, null, "eDP-1", false, true, { project: dup })
        T.ok(plan !== null, "a choice is a plan without a file and with the lid open")
        T.eq(plan.target.map(m => m.mirror), ["", "eDP-1"], "the choice is in the target")
        T.eq(plan.base, live, "the base is the layout without it")
        T.eq(D.savedTarget(live, null, "eDP-1", false, true, { force: true }).target, live, "forced without a choice: the monitors as they are")
        T.eq(D.savedTarget(live, null, "eDP-1", false, true, {}), null, "no file, no choice, lid open: nothing, as before")
        const shut = D.savedTarget(live, null, "eDP-1", true, true, { project: base => P.target(base, "duplicate", "eDP-1", false, "eDP-1").list })
        T.eq(shut.target.map(m => [m.name, m.disabled, m.mirror]), [["eDP-1", true, ""], ["HDMI-A-1", false, ""]],
             "the lid takes the source: the projector is a screen of its own")

        // ---- The switcher's choices --------------------------------------------
        T.eq(P.current(live, "eDP-1"), "extend", "both on, side by side")
        T.eq(P.current(mirrored, "eDP-1"), "duplicate", "a mirror")
        T.eq(P.current(D.update(live, "eDP-1", { disabled: true }), "eDP-1"), "external", "the panel off")
        T.eq(P.current(D.update(live, "HDMI-A-1", { disabled: true }), "eDP-1"), "internal", "the projector off")
        T.eq(P.current([live[0]], "eDP-1"), "extend", "the panel alone")
        T.eq(P.current(live, ""), "extend", "no panel known")
        T.eq(P.choices(live, "eDP-1", false).map(c => c.value + (c.enabled ? "" : "-")), ["internal", "duplicate", "extend", "external"],
             "a laptop with a screen beside it: all four")
        T.eq(P.choices(live, "eDP-1", true).map(c => c.value + (c.enabled ? "" : "-")), ["internal-", "duplicate-", "extend", "external"],
             "the lid shut: not the panel alone, and nothing to duplicate with one screen left")
        T.eq(P.choices([live[0]], "eDP-1", false).map(c => c.enabled), [false, false, false, false], "one screen: nothing to choose")
        const desk = D.parseMonitors(JSON.stringify([
            { name: "DP-8", description: "Sample 4K A", width: 3840, height: 2160, refreshRate: 60, x: 0, y: 0, scale: 1.67 },
            { name: "DP-10", description: "Sample 4K B", width: 3840, height: 2160, refreshRate: 60, x: 2304, y: 0, scale: 1.67, focused: true }]))
        T.eq(P.choices(desk, "", false).map(c => c.value), ["duplicate", "extend"], "no panel: duplicate and extend")
        T.eq(P.next("extend", P.choices(live, "eDP-1", false)), "external", "the key again: the next choice")
        T.eq(P.next("external", P.choices(live, "eDP-1", false)), "internal", "round")
        T.eq(P.next("extend", P.choices(live, "eDP-1", true)), "external", "past the ones that cannot be made")
        T.eq([P.label("duplicate"), P.label("nonsense"), P.glyph("extend").length > 0], ["Duplicate", "", true], "labels and glyphs")

        const extendFrom = P.target(mirrored, "extend", "eDP-1", false, "eDP-1")
        T.eq(extendFrom.list.map(m => [m.name, m.mirror, m.x, m.y]), [["eDP-1", "", 0, 0], ["HDMI-A-1", "", 1920, 0]],
             "extend from a mirror: the projector back beside the panel, at the end")
        T.eq(extendFrom.touched, [], "extend switches nothing off")
        const dupTarget = P.target(live, "duplicate", "eDP-1", false, "HDMI-A-1")
        T.eq(dupTarget.list.map(m => m.mirror), ["", "eDP-1"], "duplicate copies the panel, wherever the focus is")
        T.eq(dupTarget.touched, ["HDMI-A-1"], "and touches the projector")
        T.eq(P.target(desk, "duplicate", "", false, "DP-10").list.map(m => m.mirror), ["DP-10", ""], "no panel: the focused screen is the source")
        T.eq(P.target(desk, "duplicate", "", false, "").list.map(m => m.mirror), ["", "DP-8"], "no focus known: the first from the left")
        const internalOnly = P.target(live, "internal", "eDP-1", false, "eDP-1")
        T.eq([internalOnly.list.map(m => m.disabled), internalOnly.touched], [[false, true], ["HDMI-A-1"]], "laptop only: the projector off")
        const externalOnly = P.target(live, "external", "eDP-1", false, "eDP-1")
        T.eq([externalOnly.list.map(m => m.disabled), externalOnly.touched], [[true, false], ["eDP-1"]], "external only: the panel off")
        T.eq(P.target(live, "internal", "eDP-1", true, "eDP-1"), null, "laptop only behind a shut lid is refused")
        T.eq(P.target([live[0]], "duplicate", "eDP-1", false, ""), null, "duplicate with one screen is refused")
        T.eq(P.target(live, "nonsense", "eDP-1", false, ""), null, "an unknown choice is refused")
        const lidDup = P.target(desk.concat([Object.assign({}, live[0], { x: 0, y: 0 })]), "duplicate", "eDP-1", true, "DP-8")
        T.eq(lidDup.list.map(m => [m.name, m.mirror]), [["DP-8", ""], ["DP-10", "DP-8"], ["eDP-1", ""]],
             "the lid shut: the panel is left to the lid, the focused screen is the source")
        // A screen that comes back keeps its place where that is free.
        const offAway = D.update(live, "HDMI-A-1", { disabled: true, x: 5000 })
        T.eq(P.target(offAway, "extend", "eDP-1", false, "").list.find(m => m.name === "HDMI-A-1").x, 5000, "a free place is kept")

        // ---- Taking a choice back -------------------------------------------
        T.eq(P.undo(D.update(live, "eDP-1", { disabled: true }), ["eDP-1"]).map(m => m.disabled), [false, false],
             "what the choice switched off is on again")
        const undone = P.undo(mirrored, ["HDMI-A-1"])
        T.eq(undone.map(m => [m.name, m.mirror, m.x]), [["eDP-1", "", 0], ["HDMI-A-1", "", 1920]], "a mirror it made is a screen again, at the end")
        T.eq(P.undo(live, []), live, "nothing touched, nothing changed")
        // Hyprland moves a mirror onto its source, so where it stood comes
        // from before the choice: a screen left of its source goes back to
        // the left, not after the others (the blocks of workspaces swapped).
        const leftOf = D.parseMonitors(JSON.stringify([Object.assign({}, room[0], { x: 1920 }), Object.assign({}, room[1], { x: 0 })]))
        const places = P.placesOf(leftOf, ["HDMI-A-1"], {})
        T.eq(places, { "HDMI-A-1": { x: 0, y: 0 } }, "the place before the choice")
        T.eq(P.placesOf(leftOf, ["HDMI-A-1"], { "HDMI-A-1": { x: 7, y: 0 } }), { "HDMI-A-1": { x: 7, y: 0 } },
             "a place an earlier choice kept stays")
        const asMirror = D.update(leftOf, "HDMI-A-1", { mirror: "eDP-1", x: 1920 })
        T.eq(P.placesOf(asMirror, ["HDMI-A-1"], {}), {}, "a mirror has no place of its own to keep")
        T.eq(P.undo(asMirror, ["HDMI-A-1"], places).map(m => [m.name, m.mirror, m.x]), [["HDMI-A-1", "", 0], ["eDP-1", "", 1920]],
             "back where it stood")
        T.eq(P.undo(asMirror, ["HDMI-A-1"]).map(m => [m.name, m.x]), [["HDMI-A-1", 3840], ["eDP-1", 1920]],
             "without a known place: at the end, as before")
        T.eq(P.undo(asMirror, ["HDMI-A-1"], { "HDMI-A-1": { x: 1920, y: 0 } }).map(m => [m.name, m.x]), [["HDMI-A-1", 3840], ["eDP-1", 1920]],
             "a known place that is taken now: at the end")

        // ---- The rule Hyprland gets -----------------------------------------
        const rule = P.monitorCommand(beamer)
        T.eq(rule.legacy, "keyword monitor HDMI-A-1,1920x1080@60.00,auto,1,transform,0,vrr,0,mirror,eDP-1", "a mirror in the conf dialect")
        T.eq(rule.lua, "hl.monitor({ output = \"HDMI-A-1\", mode = \"1920x1080@60.00\", position = \"auto\", scale = 1, transform = 0, vrr = 0, disabled = false, mirror = \"eDP-1\" })",
             "and in the Lua dialect")
        T.eq(rule.legacyEmpty, [], "nothing to send empty")
        T.eq(P.monitorCommand(live[1]).legacy, "keyword monitor HDMI-A-1,1920x1080@60.00,1920x0,1,transform,0,vrr,0",
             "a screen of its own: the rule as ever")
        T.eq(P.monitorCommand(Object.assign({}, beamer, { disabled: true })).legacy, "keyword monitor HDMI-A-1,disable", "a mirror switched off is off")
        T.throwsError(() => P.monitorCommand(Object.assign({}, beamer, { mirror: "eDP-1; exec x" })), "a source that is no connector name is refused")

        // ---- Which monitors are connected -----------------------------------
        T.eq(P.setKey(live), P.setKey(D.update(live, "eDP-1", { disabled: true })), "on or off is the same set")
        T.ok(P.setKey(live) !== P.setKey([live[0]]), "a monitor taken away is another set")
        T.ok(P.setKey(live) !== P.setKey(strangerPanel), "another screen on the same connector is another set")
        T.eq(P.mirrorNames(mirrored), ["HDMI-A-1"], "the mirrors by name")
        T.eq(P.mirrorNames(D.update(mirrored, "HDMI-A-1", { disabled: true })), [], "a mirror switched off mirrors nothing")
        T.eq(P.mirrorNames(null), [], "nothing known")

        T.finish("ProjectionTest")
    }
}
