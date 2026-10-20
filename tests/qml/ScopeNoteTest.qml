import Quickshell
import QtQuick
import qs.shell.components
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/settings/ScopeLogic.js" as S
import "../../services/profile/ProfileLogic.js" as P

// Where a setting is kept, said where it is changed: the sentence on Settings >
// Profiles that names the machine's settings, built from GLOBAL_SETTINGS, and
// the note a section shows for its `scope`. A setting moved to the machine (or
// to the mode) without words for it fails here, rather than leaving the page
// to say something it no longer means.
ShellRoot {
    id: root

    Item {
        id: host
        width: 600
        height: 800
        Column {
            width: parent.width
            SettingsSection { id: machine; width: 600; title: "Lid"; scope: "power" }
            SettingsSection { id: plain; width: 600; title: "Look" }
            SettingsSection { id: profileOwned; width: 600; title: "Search"; scope: "launcher.searchUrl" }
            SettingsSection { id: explained; width: 600; title: "Low battery"; scope: "power"; hint: "Warnings while running on battery" }
            SettingRow { id: row; width: 600; label: "Speed"; hint: "Pointer speed"; scope: "input.sensitivity" }
        }
    }

    function note(section) {
        const found = []
        function walk(item) {
            if (item.path !== undefined && item.role === "caption") found.push(item)
            for (const child of item.children) walk(child)
        }
        walk(section)
        return found.length === 1 ? found[0] : null
    }

    Component.onCompleted: {
        // Every machine setting has words, or is bookkeeping nobody sets.
        const unnamed = P.GLOBAL_SETTINGS.filter(entry => S.labelFor(entry) === null)
        T.eq(unnamed, [], "every GLOBAL_SETTINGS entry is named on Settings > Profiles (ScopeLogic.MACHINE_LABELS)")
        T.eq(S.labelFor("configVersion"), "", "the file's version is bookkeeping")
        T.eq(S.labelFor("colorPicker.history"), "", "and so is a history the shell keeps by itself")
        T.eq(S.labelFor("weather.lat"), "the weather place", "a group covers its leaves")
        T.eq(S.labelFor("input.kbVariant"), "the keyboard layout", "a setting named on its own")
        T.eq([S.labelFor("input.tapToClick"), S.labelFor("clipboard.history"), S.labelFor("notch.screens")],
             ["the mouse and the touchpad", "the clipboard history", "which screens show the dock and the notch"],
             "the pointer, the clipboard history and the notch's screens are named too")
        T.eq(S.labelFor("input.repeatRate"), null, "the keys' repeat is a profile's")
        T.eq(S.labelFor("appearance.accent"), null, "a profile setting has no machine label")

        // The list as the page reads it today: each label once, in the table's
        // order, and the lid, fingerprint and the dock's screens among them.
        const today = S.machineSettings()
        T.ok(today.indexOf("power and the lid") >= 0 && today.indexOf("fingerprint unlock") >= 0
             && today.indexOf("which screens show the dock") >= 0 && today.indexOf("the calendars shown") >= 0,
             "the sentence names what moved to the machine: " + today)
        T.eq(S.machineSettings(["power", "weather.lat", "weather.lon", "configVersion", "input.kbLayout"]),
             "the weather place, the keyboard layout and power and the lid", "in the table's order, each once")
        T.eq(S.machineSettings(["lock.fingerprint"]), "fingerprint unlock", "one alone")
        T.eq(S.sentence([]), "", "nothing")
        T.eq(S.sentence(["a", "b"]), "a and b", "two")
        T.eq(S.sentence(["a", "", "b", "c"]), "a, b and c", "three, an empty one dropped")

        // The note for one setting.
        T.eq(S.note("appearance.blurStrength", "Docked"), "Kept for this mode (Docked)", "a mode's own setting names the mode")
        T.eq(S.note("appearance.gapsIn", ""), "Kept for this mode", "and reads without a name too")
        T.eq(S.note("power.lidAction"), "The same in every profile", "a machine setting")
        T.eq(S.note("lock.fingerprint"), "The same in every profile", "fingerprint unlock is the machine's")
        T.eq(S.note("dock.screens"), "The same in every profile", "and so are the dock's screens")
        T.eq(S.note("dock.enabled"), "", "the rest of the dock is the profile's, which goes without saying")
        T.eq(S.note(""), "", "no path, no note")

        // A section says it in its title's "i", after its own hint, and only
        // when it has one - never as a line of small print of its own.
        T.eq(machine.hintText, "The same in every profile", "a section with a machine scope says so")
        T.eq(root.note(machine), null, "in the bubble, not as a line under the title")
        T.eq(plain.hintText, "", "a section without a scope says nothing")
        T.eq(profileOwned.hintText, "", "nor does one whose setting belongs to the profile")
        T.eq(explained.hintText, "Warnings while running on battery\n\nThe same in every profile", "the section's own hint first")
        T.eq(row.hintText, "Pointer speed\n\nThe same in every profile", "a row says its setting's scope in its own bubble")

        T.finish("ScopeNoteTest")
    }
}
