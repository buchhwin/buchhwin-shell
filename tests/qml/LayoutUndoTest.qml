import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// What LayoutService.undo decides besides the config a step holds - pure, so
// it runs without the service (and without Do Not Disturb, which would reach
// the session's notification server): the profiles' stored states, the mode
// left in use and Do Not Disturb after a switch is undone. And a preset's
// description, which the sanitizer once cut short.
ShellRoot {
    id: root
    FileView { id: islandFile; path: Qt.resolvedUrl("../../config/notch-presets/island.json").toString().replace("file://", ""); blockLoading: true }

    function profile(state) {
        const entry = { label: "P", modes: {} }
        if (state) entry.state = state
        return entry
    }

    Component.onCompleted: {
        // ---- the profiles' states -------------------------------------------
        const mine = { settings: { appearance: { accent: "#123456" } }, notch: null, lock: null }
        const applied = { settings: { appearance: { accent: "#654321" } }, notch: null, lock: null }
        const now = { profiles: { "default": root.profile(applied), buchhwin: root.profile(null), work: root.profile(mine) } }

        // A step holds no states: each profile keeps the one it has now.
        let step = { profiles: { "default": root.profile(null), buchhwin: root.profile(null), work: root.profile(null) } }
        L.withUndoStates(step, now, null)
        T.eq(step.profiles["default"].state, applied, "a profile keeps the state it has now")
        T.eq("state" in step.profiles.buchhwin, false, "one without a state stays without")
        T.eq(step.profiles.work.state, mine, "and every other keeps its own")

        // Reset of a built-in profile not in use dropped its state and handed
        // it to the step: undone, it comes back with the modes.
        step = { profiles: { "default": root.profile(null), buchhwin: root.profile(null) } }
        L.withUndoStates(step, now, { buchhwin: mine })
        T.eq(step.profiles.buchhwin.state, mine, "a state the step was handed comes back to a profile without one")
        T.eq(step.profiles["default"].state, applied, "and the others are the config's")

        // A state the profile has now wins over the one handed: what entering
        // it applied since is not taken back.
        step = { profiles: { work: root.profile(null) } }
        L.withUndoStates(step, now, { work: applied })
        T.eq(step.profiles.work.state, mine, "a profile with a state now keeps it")

        // A removal undone: the profile is not in the config any more.
        step = { profiles: { gone: root.profile(null), work: root.profile(null) } }
        L.withUndoStates(step, now, { gone: mine })
        T.eq(step.profiles.gone.state, mine, "a removed profile comes back with its state")
        step = { profiles: { gone: root.profile(null) } }
        L.withUndoStates(step, now, undefined)
        T.eq("state" in step.profiles.gone, false, "and without one when its step had none")
        T.eq(L.withUndoStates({}, now, null), {}, "a step without profiles is left alone")

        // ---- the mode -------------------------------------------------------
        // Only the step of a switch the user made takes the mode back.
        T.eq(L.modeAfterUndo({ config: { activeMode: "minimal" }, modeSwitch: { dnd: "" } }, "gaming"), "minimal",
             "undoing a switch switches back")
        T.eq(L.modeAfterUndo({ config: { activeMode: "laptop" } }, "docked"), "docked",
             "undoing an edit from before an automatic switch keeps the mode the machine chose")
        T.eq(L.modeAfterUndo({ config: { activeMode: "work" } }, "work"), "work", "an edit in the same mode keeps it")
        T.eq(L.modeAfterUndo({ config: {}, modeSwitch: { dnd: "" } }, "work"), "work", "a step without a mode keeps the one in use")
        T.eq(L.modeAfterUndo(null, "work"), "work", "and so does no step")
        // The user's switch to gaming, then a monitor plugged in: the machine
        // chose Docked since, and undoing the switch must not take a docked
        // laptop back to Laptop.
        const intoGaming = { config: { activeMode: "laptop" }, modeSwitch: { dnd: "manual", to: "gaming" } }
        T.eq(L.modeAfterUndo(intoGaming, "gaming"), "laptop", "a switch whose mode is still in use switches back")
        T.eq(L.modeAfterUndo(intoGaming, "docked"), "docked", "one the machine switched away from since keeps its mode")

        // ---- Do Not Disturb across a mode switch -----------------------------
        // By hand, automatic or undone: gaming turns it on when it finds it
        // off, and it ends with the mode - unless the user changed it since.
        const gaming = { dnd: "manual", animationMode: "reduced" }
        T.eq(L.dndOnModeChange("", false, "work", "gaming", gaming), { mode: "manual", by: "gaming" },
             "entering gaming with it off turns it on, as gaming's")
        T.eq(L.dndOnModeChange("", true, "work", "gaming", gaming), null,
             "entering with it on already changes nothing - a running hour stays an hour")
        T.eq(L.dndOnModeChange("gaming", true, "gaming", "work", {}), { mode: "off", by: "" },
             "leaving gaming turns its own off")
        T.eq(L.dndOnModeChange("", true, "gaming", "work", {}), null,
             "one the user set (or set again in gaming) stays after leaving")
        T.eq(L.dndOnModeChange("gaming", false, "gaming", "work", {}), null, "one that is off already stays off")
        T.eq(L.dndOnModeChange("gaming", true, "gaming", "focus", { dnd: "manual" }), { mode: "manual", by: "focus" },
             "a mode entered that turns it on too takes it over")
        T.eq(L.dndOnModeChange("laptop", true, "gaming", "work", {}), null, "another mode's is not gaming's to end")
        T.eq(L.dndOnModeChange("gaming", true, "gaming", "gaming", gaming), null, "staying in the mode changes nothing")
        T.eq(L.dndOnModeChange("", false, "gaming", "work", undefined), null, "a mode without effects leaves it")
        T.eq(L.dndOnModeChange(undefined, false, "work", "laptop", { dnd: "off" }), null, "\"off\" is no wish to turn it on")

        // ---- the settings a step puts back -----------------------------------
        // Every step carries the notch's options (undoKeys); a dock preset's
        // step also carries the dock.* options it changed. Undone, the
        // layout came back and the taskbar's options stayed: the old dock
        // stretched along the whole edge with a reserved zone.
        const keys = ["notch.reserve", "desktop.quickWidth"]
        const presetStep = { notch: { "notch.reserve": true, "desktop.quickWidth": 0, "notch.other": 1 },
                             settings: { "dock.visibility": "intellihide", "dock.span": "fit", "dock.iconSize": 48,
                                         "dock.margin": 8, "dock.enabled": false } }
        T.eq(L.undoSettings(presetStep, keys),
             { "notch.reserve": true, "desktop.quickWidth": 0, "dock.visibility": "intellihide", "dock.span": "fit",
               "dock.iconSize": 48, "dock.margin": 8, "dock.enabled": false },
             "a preset undone: the carried keys and the dock's options, the dock off again")
        T.eq(L.undoSettings({ notch: { "notch.reserve": false } }, keys), { "notch.reserve": false },
             "an ordinary step: only the carried keys - Settings > Dock since is not taken back")
        T.eq(L.undoSettings({ settings: { "dock.span": null } }, keys), {}, "nothing for a value that is not there")
        T.eq(L.undoSettings(null, keys), {}, "no step, nothing")

        // ---- a preset's description -----------------------------------------
        // Island's own text is 143 characters; the sanitizer cut it at 120.
        const islandData = JSON.parse(islandFile.text())
        const island = L.sanitizeNotchPreset(islandData, true)
        T.ok(islandData.description.length > 120, "Island's description is longer than the old limit")
        T.eq(island.description, islandData.description, "and the preset keeps all of it")
        const lengthy = L.sanitizeNotchPreset({ label: "Long", description: "x".repeat(1000) }, false)
        T.eq(lengthy.description.length, L.PRESET_DESCRIPTION_MAX, "a hand-edited one is still capped")
        T.eq(L.sanitizeNotchPreset({ label: "None" }, false).description, "", "and a missing one is empty")

        T.finish("LayoutUndoTest")
    }
}
