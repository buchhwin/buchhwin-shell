import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/shortcuts/ShortcutLogic.js" as L

// Where a built-in shortcut sits, as opposed to what it does.
//
// With a Lua configuration `hyprctl -j binds` answers `dispatcher: "__lua"`,
// so the action of a binding cannot be read from outside and neither can the
// combination it started on once it has moved. hypr/hyprland.lua is therefore
// the only place that knows, and these three functions are the reading, the
// storing and the writing of that.
ShellRoot {
    readonly property string sample: 'local function exec(command) return hl.dsp.exec_cmd(command) end\n'
        + 'hl.bind(keyFor("SUPER + D"), exec(ipc .. "launcher toggle"), { description = "Launcher" })\n'
        + 'hl.bind(keyFor("SUPER + RIGHT"), hl.dsp.window.resize({ x = 30, y = 0, relative = true }),'
        + ' { repeating = true, description = "Resize window" })\n'
        + 'hl.bind(keyFor("SUPER + LEFT"), hl.dsp.window.resize({ x = -30, y = 0, relative = true }),'
        + ' { repeating = true, description = "Resize window" })\n'
        + 'hl.bind(keyFor("ALT + ALT_L"), exec(ipc .. "switcher confirm"),'
        + ' { release = true, transparent = true, description = "Switch to selected window" })\n'

    Component.onCompleted: {
        // ---- reading the defaults out of the configuration ---------------

        const defaults = L.parseDefaults(sample)
        T.eq(defaults.length, 4, "every binding is found")
        T.eq(defaults[0].combo, "SUPER + D", "the combination is the one the file writes")
        T.eq(defaults[0].description, "Launcher", "and it carries its name")
        // The option table comes before the description on this one, which is
        // where a lazier pattern stops matching.
        T.eq(defaults[3].description, "Switch to selected window", "options before the description are skipped")
        T.eq(defaults[1].description, "Resize window", "a multi-line action is still read")
        // Four bindings really are called "Resize window", which is why the
        // combination and not the description is the identity.
        T.eq(defaults[1].combo !== defaults[2].combo, true, "two bindings share a name and differ by combination")
        T.eq(L.parseDefaults("").length, 0, "an empty file has none")
        T.eq(L.parseDefaults(null).length, 0, "and so does no file at all")

        // ---- the override store ------------------------------------------

        const store = L.parseKeyOverrides('# a comment\n\nSUPER + D = SUPER + SPACE\n  SUPER + O =  SUPER + C  \n')
        T.eq(store["SUPER + D"], "SUPER + SPACE", "a line is read")
        T.eq(store["SUPER + O"], "SUPER + C", "and trimmed on both sides")
        T.eq(Object.keys(store).length, 2, "comments and blank lines are not entries")
        T.eq(Object.keys(L.parseKeyOverrides("SUPER + D =\n")).length, 0, "an empty replacement is not one")

        const written = L.serializeKeyOverrides({ "SUPER + D": "SUPER + SPACE", "SUPER + O": "SUPER + O" })
        T.eq(written.indexOf("SUPER + D = SUPER + SPACE") >= 0, true, "a move is written")
        // Writing "it stays where it is" would leave a line that does nothing
        // and would have to be read back as an override.
        T.eq(written.indexOf("SUPER + O") < 0, true, "a shortcut left where it is writes no line")
        T.eq(written.indexOf("#") === 0, true, "the file says who wrote it")

        // A round trip has to be lossless, or an edit made by hand is lost the
        // next time the page saves.
        const round = L.parseKeyOverrides(L.serializeKeyOverrides({ "SUPER + ALT + P": "SUPER + P" }))
        T.eq(round["SUPER + ALT + P"], "SUPER + P", "what is written can be read again")

        // ---- one spelling to compare two combinations by ------------------

        // The configuration writes "SUPER + D", Hyprland answers modmask 64
        // and "D". Neither the case nor the order of the modifiers agrees, and
        // matching by description or by order was measured and does not work:
        // four bindings share a description, and the workspace keys are
        // generated in a loop so the order diverges after the 39th.
        T.eq(L.canonicalCombo("SUPER + D"), L.canonicalBind(64, "D"), "the simple case")
        T.eq(L.canonicalCombo("Print"), L.canonicalBind(0, "PRINT"), "a key with no modifier, and the case differs")
        T.eq(L.canonicalCombo("SUPER + SHIFT + S"), L.canonicalCombo("SHIFT + SUPER + S"),
             "the order of the modifiers does not matter")
        T.eq(L.canonicalCombo("SUPER + CTRL + R"), L.canonicalBind(64 | 4, "R"), "two modifiers")
        T.eq(L.canonicalCombo("SUPER + D") === L.canonicalCombo("SUPER + E"), false,
             "and two different shortcuts stay different")

        // ---- hints that name a key (ShortcutService.keyHint) ---------------

        // Where a shortcut sits now: the move if there is one, the default
        // otherwise - keyFor() in hyprland.lua does the same.
        const moved = { "SUPER + K": "SUPER + SHIFT + SPACE", "SUPER + M": "  " }
        T.eq(L.currentCombo(moved, "SUPER + K"), "SUPER + SHIFT + SPACE", "a moved shortcut is where it was moved")
        T.eq(L.currentCombo(moved, "SUPER + D"), "SUPER + D", "one left alone is where the configuration puts it")
        T.eq(L.currentCombo(moved, "SUPER + M"), "SUPER + M", "an empty move is none, as in keyFor()")
        T.eq(L.currentCombo(undefined, "SUPER + D"), "SUPER + D", "and before the file is read")

        // With nothing moved every hint reads exactly as the text it replaced.
        const spaced = { "SUPER + K": "Super + K", "SUPER + M": "Super + M", "SUPER + V": "Super + V",
                         "SUPER + ALT + E": "Super + Alt + E", "SUPER + SHIFT + R": "Super + Shift + R",
                         "SUPER + CTRL + SHIFT + R": "Super + Ctrl + Shift + R" }
        const compact = { "SUPER + L": "Super+L", "SUPER + ALT + E": "Super+Alt+E", "SUPER + SHIFT + C": "Super+Shift+C",
                          "SUPER + B": "Super+B", "SUPER + E": "Super+E", "SUPER + RETURN": "Super+Enter",
                          "SUPER + F1": "Super+F1", "SUPER + I": "Super+I", "SUPER + 3": "Super+3" }
        for (const combo of Object.keys(spaced)) T.eq(L.comboLabel(combo), spaced[combo], "hint for " + combo)
        for (const combo of Object.keys(compact)) T.eq(L.comboLabel(combo, true), compact[combo], "compact hint for " + combo)
        T.eq([L.comboParts("SUPER + D"), L.comboParts("SUPER + ALT + E"), L.comboParts("SUPER + F1")],
             [["Super", "D"], ["Super", "Alt", "E"], ["Super", "F1"]], "the welcome tour's key chips")
        // After a move: what the shortcuts page writes, in the hint's words.
        T.eq(L.comboLabel(L.currentCombo(moved, "SUPER + K")), "Super + Shift + Space", "a moved shortcut's hint follows it")
        T.eq(L.comboLabel("SHIFT + SUPER + PERIOD", true), "Super+Shift+.", "modifiers in display order, keys by their sheet names")
        T.eq([L.comboLabel(""), L.comboParts("SUPER + ")], ["", []], "no key, no hint")

        // Every combination a hint asks for is one hyprland.lua starts a
        // shortcut on; a misspelt one would never follow a move.
        const builtIn = L.parseDefaults(config.text()).map(item => item.combo)
        T.ok(builtIn.length > 40, "the configuration's shortcuts are read")
        for (const combo of Object.keys(spaced).concat(Object.keys(compact)).concat(["SUPER + D", "SUPER + O"]))
            T.ok(builtIn.indexOf(combo) >= 0, combo + " is a built-in shortcut")

        T.finish("ShortcutKeysTest")
    }

    FileView { id: config; path: Qt.resolvedUrl("../../hypr/hyprland.lua").toString().replace("file://", ""); blockLoading: true }
}
