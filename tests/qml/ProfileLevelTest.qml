import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../config/migrations/Migrations.js" as Migrations
import "../../services/LayoutLogic.js" as L
import "../../services/profile/ProfileLogic.js" as P

// The second level: a profile holds its own five modes.
//
// The first half of this file is the migration's acceptance test, and it is
// the reason the migration exists in this shape: **v2 → v3 must change
// nothing.** Every mode the user had, with everything in it, has to come out
// the other side identical - which is not something a nested session can show,
// because a layout that is subtly wrong still draws.
ShellRoot {
    FileView {
        id: v2
        path: Qt.resolvedUrl("../fixtures/layout-v2-modes.json").toString().replace("file://", "")
        blockLoading: true
    }

    Component.onCompleted: {
        const source = JSON.parse(v2.text())
        const result = Migrations.migrate(v2.text())
        T.ok(result.ok && result.changed && !result.readOnly, "a v2 layout migrates and is not read-only")
        T.eq([result.from, result.to], [2, 3], "from v2 to v3")
        const config = L.sanitize(result.config)

        // ---- the migration changes nothing ----------------------------------
        T.eq(config.activeProfile, "default", "everything the user had becomes the Default profile")
        T.eq(config.activeMode, "laptop", "and what activeProfile meant becomes activeMode")
        T.eq(L.profileNames(config), ["default"], "one profile, until the user makes another")
        T.eq(L.profileLabel(config, "default"), "Default", "with a name they can read")
        T.eq(Object.keys(L.modesOf(config, "default")).sort(), ["gaming", "laptop"],
             "the modes that were in the file, and only those")

        // Field by field against the v2 file, because "nothing changed" is a
        // claim about every field, not about the ones a screenshot would show.
        for (const name of ["laptop", "gaming"]) {
            const before = source.profiles[name]
            const after = L.modeConfig(config, "default", name)
            T.eq(after.widgets, before.widgets, name + ": every widget survives untouched")
            T.eq(after.groups, before.groups, name + ": and every group")
            T.eq(after.screens, before.screens, name + ": and the screens it knows")
            T.eq(after.bar, before.bar, name + ": and the whole bar, zone for zone")
            T.eq(after.quick, before.quick, name + ": and the quick panel")
            T.eq(after.dashboard, before.dashboard, name + ": and the dashboard")
        }
        T.eq(L.modeConfig(config, "default", "laptop").desktopMode, "notch",
             "`mode` becomes `desktopMode` with the same value")
        T.eq(L.modeConfig(config, "default", "gaming").desktopMode, "pills",
             "and a legacy \"both\" still migrates to the bar")

        // The three things that were never in a profile stay where they were.
        T.eq(config.notch, source.notch, "the notch is global and is not touched")
        T.eq(config.lock, source.lock, "nor the lock screen")
        T.eq(config.adopted, source.adopted, "nor the markers that say a one-shot migration has run")

        // A mode the file never had reads as an empty one rather than as
        // nothing: every caller gets a whole object.
        const untouched = L.modeConfig(config, "default", "work")
        T.eq([untouched.widgets, untouched.groups, untouched.screens], [[], [], []],
             "a mode that was never used reads as empty")
        T.eq(untouched.desktopMode, "widgets", "and shows the widgets surface")
        T.ok(untouched.bar !== undefined && untouched.quick !== undefined,
             "with a bar and a quick panel, not holes")

        // Twice is once: migrating an already-migrated file is a no-op.
        const again = Migrations.migrate(JSON.stringify(result.config))
        T.ok(again.ok && !again.changed, "a v3 file does not migrate again")
        T.eq(L.sanitize(again.config), config, "and reads back as exactly the same layout")

        // ---- the profile level ----------------------------------------------
        // A new profile has no modes at all. That is what "copies from the
        // factory state, not from Default" means in the file: each mode is
        // materialized from its template the first time it is entered, so a
        // new profile cannot inherit anything the user did to Default.
        const added = L.addProfile(config, "Studio")
        T.eq(added.name, "studio", "a profile's id comes from its name")
        T.eq(L.profileLabel(added.config, "studio"), "Studio", "and the name is kept as it was typed")
        T.eq(Object.keys(L.modesOf(added.config, "studio")), [], "a new profile starts from the factory state, not from Default")
        T.eq(L.modeConfig(added.config, "default", "laptop").widgets,
             source.profiles.laptop.widgets, "and takes nothing away from the profile it was made in")
        T.eq(added.config.activeProfile, "default", "adding one does not switch to it")

        const twice = L.addProfile(added.config, "Studio")
        T.eq(twice.name, "studio-2", "two profiles may carry the same name")
        T.eq(L.addProfile(config, "  ").name, "profile", "and a name with nothing in it still gives an id")

        // Duplicate is the other case: this profile as it stands.
        const copied = L.duplicateProfile(config, "default", "Copy")
        T.eq(L.modeConfig(copied.config, "copy", "laptop").widgets,
             source.profiles.laptop.widgets, "a duplicate carries the modes it was copied from")
        T.ok(L.duplicateProfile(config, "ghost", "X").name === "", "and a profile that is not there copies to nothing")

        // Rename, remove, reset.
        T.eq(L.profileLabel(L.renameProfile(added.config, "studio", "Desk"), "studio"), "Desk", "a profile can be renamed")
        T.eq(L.profileNames(L.removeProfile(added.config, "studio")), ["default"], "and removed")
        T.eq(L.profileNames(L.removeProfile(config, "default")), ["default"],
             "but never the last one - there has to be a profile to be in")
        const switched = L.sanitize(Object.assign(JSON.parse(JSON.stringify(added.config)), { activeProfile: "studio" }))
        T.eq(L.removeProfile(switched, "studio").activeProfile, "default",
             "removing the profile you are in lands you in another")

        // Reset empties, so the templates fill it again on the next entry.
        T.eq(Object.keys(L.modesOf(L.resetProfile(config, "default"), "default")), [],
             "resetting a profile puts every mode back to the factory state")
        T.eq(Object.keys(L.modesOf(L.resetProfile(config, "default", "gaming"), "default")), ["laptop"],
             "and one mode can be reset on its own")
        T.eq(L.modeConfig(L.resetProfile(config, "default", "gaming"), "default", "laptop").widgets,
             source.profiles.laptop.widgets, "without touching the four beside it")

        // ---- a layout file with nothing in it --------------------------------
        const empty = L.sanitize({})
        T.eq(L.profileNames(empty), ["default"], "an empty layout still has a profile")
        T.eq(empty.activeMode, "minimal", "and a mode")
        const stray = L.sanitize({ activeProfile: "ghost", profiles: { real: { modes: {} } } })
        T.eq(stray.activeProfile, "real", "an active profile that does not exist is corrected, not believed")
        const strayMode = L.sanitize({ activeMode: "nonsense", profiles: { default: { modes: {} } } })
        T.eq(strayMode.activeMode, "minimal", "and so is a mode name that is not one of the five")
        T.eq(Object.keys(L.sanitize({ profiles: { a: { modes: { nonsense: {} } } } }).profiles.a.modes), [],
             "a mode the shell has no template for is dropped")

        // ---- which settings a mode owns --------------------------------------
        // The one list, and the one thing it must not do: silently take a
        // setting that belongs to the whole session.
        T.ok(P.MODE_SCOPED.indexOf("blurStrength") >= 0 && P.MODE_SCOPED.indexOf("animationSpeed") >= 0,
             "blur and animation speed are the mode's")
        T.ok(P.MODE_SCOPED.indexOf("accent") < 0 && P.MODE_SCOPED.indexOf("theme") < 0
             && P.MODE_SCOPED.indexOf("fontFamily") < 0,
             "the theme, the accent and the font are the session's")
        T.eq(P.modeScopedPath("gapsIn"), "appearance.gapsIn", "a leaf names a whole setting path")
        T.eq(P.modeScopedLeaf("appearance.gapsIn"), "gapsIn", "and back again")
        T.eq(P.modeScopedLeaf("appearance.accent"), "", "a setting not on the list has no leaf")
        T.eq(P.modeScopedLeaf("workspaces.mode"), "", "nor one outside the group")
        T.ok(!P.isModeScoped("appearance.theme") && P.isModeScoped("appearance.panelOpacity"),
             "and that is the whole question the service asks")

        // Stored per mode, and sanitized as hard as everything else.
        const dirty = L.sanitize({ profiles: { default: { modes: { work: {
            appearance: { blurStrength: 0.8, accent: "#ff0000", gapsIn: 4, panelOpacity: { nested: 1 } } } } } } })
        const kept = L.modeConfig(dirty, "default", "work").appearance
        T.eq(kept, { blurStrength: 0.8, gapsIn: 4 },
             "a mode keeps the settings it owns, drops the rest and refuses a value that is not a primitive")
        T.eq(L.modeConfig(config, "default", "laptop").appearance, {},
             "a mode nobody has customized owns nothing, so its template still decides")

        T.finish("ProfileLevelTest")
    }
}
