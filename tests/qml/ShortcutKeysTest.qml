import Quickshell
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

        T.finish("ShortcutKeysTest")
    }
}
