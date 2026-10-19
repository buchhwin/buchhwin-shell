import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// What LayoutService.undo decides besides the config a step holds - pure, so
// it runs without the service (and without Do Not Disturb, which would reach
// the session's notification server): the profiles' stored states, the mode
// left in use and Do Not Disturb after a switch is undone, what a step of one
// mode and a step of the whole layout bring back, and the appearance every
// mode keeps through an undo. And a preset's description, which the sanitizer
// once cut short.
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

        // ---- a mode's own Do Not Disturb choice ------------------------------
        // Settings > Profiles, "Do Not Disturb in this mode". Without a
        // choice a mode does what its template says, so a layout from before
        // the switch keeps gaming's and the other four's as they were.
        T.eq([L.modeDnd({}, gaming), L.modeDnd({}, {}), L.modeDnd(undefined, { dnd: "1h" }), L.modeDnd(null, undefined)],
             ["manual", "", "1h", ""], "no choice: the template's - gaming's on, the other four's none")
        T.eq([L.modeDnd({ dnd: true }, {}), L.modeDnd({ dnd: true }, { dnd: "1h" }), L.modeDnd({ dnd: false }, gaming)],
             ["manual", "1h", ""], "on takes the template's kind or else until turned off; off is none, gaming's too")
        T.eq(L.modeDnd({ dnd: "yes" }, {}), "", "only a real choice counts")
        T.eq(L.modeDndEffects({ dnd: false }, gaming), { dnd: "off", animationMode: "reduced" },
             "the effects with the choice in them, the rest as the template has them")
        T.eq(L.dndOnModeChange("", false, "gaming", "work", L.modeDndEffects({ dnd: true }, {})), { mode: "manual", by: "work" },
             "a mode switched on takes Do Not Disturb as gaming does")
        T.eq(L.dndOnModeChange("", false, "work", "gaming", L.modeDndEffects({ dnd: false }, gaming)), null,
             "and gaming switched off leaves it off")
        const choices = { profiles: { p: { modes: { work: { dnd: true }, laptop: { dnd: false } } }, q: { modes: { docked: { dnd: true } } } } }
        T.eq(["gaming", "work", "laptop", "docked", "minimal"].map(name => L.modeMayOwnDnd(choices, name, name === "gaming" ? gaming : {})),
             [true, true, false, true, false],
             "a mode can own it when its template turns it on or a profile's mode of its name chose to")
        T.eq(L.modeMayOwnDnd({ profiles: { p: { modes: { gaming: { dnd: false } } } } }, "gaming", gaming), true,
             "gaming switched off still counts: one it owns from before must still end as it is left")
        // The choice changed while the mode is in use acts at once.
        T.eq(L.dndOnModeChoice("", false, "work", "manual"), { mode: "manual", by: "work" }, "switched on: on now, as the mode's")
        T.eq(L.dndOnModeChoice("", true, "work", "manual"), null, "unless it is on already")
        T.eq(L.dndOnModeChoice("work", true, "work", ""), { mode: "off", by: "" }, "switched off: the mode's own ends")
        T.eq(L.dndOnModeChoice("", true, "work", ""), null, "one the user set stays")
        T.eq(L.dndOnModeChoice("focus", true, "work", ""), null, "and so does Focus's")
        // Kept in the mode as a choice only: a mode without one reads back
        // without the field, so files from before stay as they were.
        T.eq([L.sanitizeMode({ dnd: true }).dnd, L.sanitizeMode({ dnd: false }).dnd, "dnd" in L.sanitizeMode({}),
              "dnd" in L.sanitizeMode({ dnd: "on" })], [true, false, false, false], "a boolean choice is kept, nothing else")

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

        // Only a mode whose template turns it on can own it, so a switch
        // between two others asks NotificationService nothing.
        T.eq([L.turnsDndOn(gaming), L.turnsDndOn({ dnd: "off" }), L.turnsDndOn({ dnd: "" }), L.turnsDndOn({}),
              L.turnsDndOn(undefined), L.turnsDndOn({ dnd: "1h" })],
             [true, false, false, false, false, true], "which templates turn Do Not Disturb on")

        // ---- what a step brings back ----------------------------------------
        // A step of one mode holds that mode (and the one a switch went to,
        // null when it was not there yet) and the global surfaces; it is laid
        // over the config at hand, whose other modes, profiles, states,
        // presets and markers stay.
        const mode = (gaps, desktop) => ({ widgets: [], groups: [], screens: ["eDP-1"], desktopMode: desktop || "notch",
                                           appearance: { gapsOut: gaps } })
        const current = { activeProfile: "p", activeMode: "work", notch: { n: "now" }, dock: { d: "now" }, lock: { l: "now" },
                          notchPresets: [{ id: "mine" }], adopted: ["m"],
                          profiles: { p: { label: "P", state: { s: 1 }, modes: { minimal: mode(5), work: mode(13, "pills"), laptop: mode(8) } },
                                      q: { label: "Q", modes: { minimal: mode(2) } } } }
        const editStep = { config: { activeMode: "minimal", notch: { n: "then" }, dock: { d: "then" }, lock: { l: "then" } },
                           modes: { profile: "p", list: { minimal: mode(3, "widgets"), docked: null } } }
        const laid = L.undoTarget(editStep, current)
        T.eq([laid.notch, laid.dock, laid.lock, laid.activeMode], [{ n: "then" }, { d: "then" }, { l: "then" }, "minimal"],
             "a step of one mode brings back the global surfaces and the mode it was taken in")
        T.eq(laid.profiles.p.modes.minimal.desktopMode, "widgets", "and the mode it holds")
        T.ok(laid.profiles.p.modes.work === current.profiles.p.modes.work && laid.profiles.q === current.profiles.q
             && laid.profiles.p.state === current.profiles.p.state && laid.notchPresets === current.notchPresets
             && laid.adopted === current.adopted, "every other mode, profile, state, preset and marker is the config's")
        T.eq("docked" in laid.profiles.p.modes, false, "a mode the step held as not there yet is not")
        T.eq([current.profiles.p.modes.minimal.desktopMode, current.notch.n], ["notch", "now"], "and the config at hand is not changed")
        const wholeStep = { config: { activeMode: "work", profiles: { p: { label: "P", modes: { minimal: mode(1) } } } },
                            states: { p: { s: 2 } } }
        const whole = L.undoTarget(wholeStep, current)
        T.eq([Object.keys(whole.profiles.p.modes), whole.profiles.p.state, whole.notchPresets, whole.adopted],
             [["minimal"], { s: 1 }, [{ id: "mine" }], ["m"]],
             "a step of the profile level is the whole layout, with the states, presets and markers of the config at hand")

        // ---- the appearance after an undo ------------------------------------
        // A mode-scoped setting takes no step, so every mode keeps the
        // appearance it has now - unless the step's own change replaced it.
        const restoredConfig = { profiles: { p: { modes: { minimal: mode(5), work: mode(7), gaming: mode(1) } },
                                             gone: { modes: { minimal: mode(4) } } } }
        const nowConfig = { profiles: { p: { modes: { minimal: mode(13), work: mode(7), laptop: mode(9) } } } }
        const carried = L.withCurrentAppearance(restoredConfig, nowConfig, null)
        T.eq(carried.profiles.p.modes.minimal.appearance.gapsOut, 13, "a mode keeps the appearance it has now")
        T.eq(carried.profiles.p.modes.minimal.desktopMode, "notch", "and the rest of the mode the step brought back")
        T.ok(carried.profiles.p.modes.work === restoredConfig.profiles.p.modes.work, "an equal one is left as it is")
        T.eq(carried.profiles.p.modes.gaming.appearance.gapsOut, 1, "a mode only in the step keeps the step's")
        T.eq(carried.profiles.gone.modes.minimal.appearance.gapsOut, 4, "and so does a profile only in the step")
        T.eq("laptop" in carried.profiles.p.modes, false, "a mode only in the config at hand is not brought in")
        T.eq(restoredConfig.profiles.p.modes.minimal.appearance.gapsOut, 5, "the config it is handed is not changed")
        T.eq(L.withCurrentAppearance(restoredConfig, nowConfig, { p: ["minimal"] }).profiles.p.modes.minimal.appearance.gapsOut, 5,
             "a mode the step's change replaced (a Reset) gets the step's back")
        T.ok(L.withCurrentAppearance(restoredConfig, restoredConfig, null) === restoredConfig, "nothing to carry, nothing new")
        // A mode's Do Not Disturb choice takes no step either.
        const chose = (gaps, dnd) => Object.assign(mode(gaps), dnd === undefined ? {} : { dnd: dnd })
        const choiceThen = { profiles: { p: { modes: { work: chose(7), laptop: chose(8, true), docked: chose(9, false) } } } }
        const choiceNow = { profiles: { p: { modes: { work: chose(7, true), laptop: chose(8), docked: chose(9, false) } } } }
        const kept = L.withCurrentAppearance(choiceThen, choiceNow, null).profiles.p.modes
        T.eq([kept.work.dnd, "dnd" in kept.laptop, kept.docked.dnd], [true, false, false],
             "each mode keeps the choice it has now, none where it has none")
        T.ok(kept.docked === choiceThen.profiles.p.modes.docked, "an equal one is left as it is")
        T.eq(L.withCurrentAppearance(choiceThen, choiceNow, { p: ["work"] }).profiles.p.modes.work.dnd, undefined,
             "and a mode a Reset replaced gets the step's")

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
