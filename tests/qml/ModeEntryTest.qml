//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// Entering modes and profiles, through LayoutService itself.
//
// It runs under the lock screen's shell id on purpose: there NotificationService
// runs no notification server (LockLogic.lockProcess, pitfall 86), so the
// switches into gaming below - whose template turns Do Not Disturb on - reach
// no bus at all, the session's least (pitfall 82). Nothing else this test uses
// asks for the shell id.
//
// The sandbox starts with a settings.json and no layout.json: the user removed
// the layout to reset the desktop, or lost it. That is not a first start, so
// the appearance adoption gives every mode what is set - and a mode it makes
// must still take its template's desktop mode and bar when it is entered; it
// showed widgets for good (pitfall 119's placeholders, outside a nested
// sandbox too). Then Do Not Disturb across switches by hand, automatic and
// undone; then a profile switch: one write of the settings, the default
// recording folder kept as it is, a state from before a migration migrated,
// and a value this version refuses set to its default rather than kept from
// the profile left.
ShellRoot {
    id: root
    property int waits: 0
    property bool seeded: false
    property int dataChanges: 0
    FileView { id: seed; blockWrites: true; printErrors: false }

    Component.onCompleted: {
        seed.path = Paths.configDir + "/settings.json"
        seed.setText(JSON.stringify({ configVersion: 1, onboarding: { completed: true },
                                      appearance: { gapsOut: 9 } }, null, 2) + "\n")
        root.seeded = true
    }

    Connections {
        target: root.seeded ? SettingsService : null
        function onDataChanged() { root.dataChanges += 1 }
    }

    Timer {
        interval: 20
        repeat: true
        running: root.seeded
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && SettingsService.loaded && LayoutService.stateSettled
                && !LayoutService.builtinApplying.length && Object.keys(LayoutService.templates).length === 5
                && L.hasAdopted(LayoutService.config, "modeAppearance")
            if (!there && root.waits < 300) return
            stop()
            T.ok(there, "the layout, the settings and the templates are in (" + Paths.configDir + ")")
            lostLayout.start()
        }
    }

    // ---- a layout.json lost beside settings.json ---------------------------
    Timer {
        id: lostLayout
        interval: 50
        onTriggered: {
            T.eq(Quickshell.shellId, "buchhwin-shell-lock", "the test runs where no notification server is wanted")
            T.eq(NotificationService.serverWanted, false, "and NotificationService runs none")
            T.eq([LayoutService.freshDecided, LayoutService.layoutWasEmpty, LayoutService.settingsWereEmpty], [true, true, false],
                 "the layout file was missing beside the user's settings: not a first start")
            const profile = LayoutService.activeProfile
            const want = {}
            for (const name of LayoutService.modeNames)
                want[name] = L.desktopModeName((LayoutService.templates[name] || {}).desktopMode)
            // The placeholders showed widgets. A template read under a key it
            // does not have seems to ask for widgets too, and the cases below
            // would pass with the placeholders back.
            T.ok(["work", "laptop", "docked", "gaming"].every(name => want[name] !== "widgets"),
                 "the templates ask for a surface other than widgets")
            for (const name of ["work", "laptop", "docked"]) {
                T.eq(LayoutService.setActiveMode(name), true, "into " + name)
                T.eq(LayoutService.desktopMode, want[name], name + " shows its template's surface (" + want[name] + ")")
            }
            const stored = name => (L.modeConfig(LayoutService.config, profile, name).appearance || {}).gapsOut
            T.eq(stored("work"), 9, "a mode made by the adoption has the gaps that were set")
            T.eq(stored("laptop"), (LayoutService.templates.laptop.effects || {}).gapsOut, "unless its template names its own")
            dnd.start()
        }
    }

    // ---- Do Not Disturb across switches -------------------------------------
    Timer {
        id: dnd
        interval: 50
        onTriggered: {
            NotificationService.setDnd("off")
            T.eq(LayoutService.setActiveMode("gaming"), true, "into gaming")
            T.eq([NotificationService.dndActive, NotificationService.dndBy], [true, "gaming"],
                 "turns Do Not Disturb on, as gaming's")
            T.eq(LayoutService.desktopMode, L.desktopModeName(LayoutService.templates.gaming.desktopMode), "with its surface")
            T.eq(LayoutService.setActiveMode("work"), true, "out of it")
            T.eq([NotificationService.dndActive, NotificationService.dndBy], [false, ""], "turns it off again")

            T.eq(LayoutService.setActiveMode("gaming"), true, "into gaming again")
            LayoutService.undo()
            T.eq([LayoutService.activeMode, NotificationService.dndActive], ["work", false], "undoing the switch turns it off")

            NotificationService.setDnd("manual")
            LayoutService.setActiveMode("gaming")
            T.eq([NotificationService.dndActive, NotificationService.dndBy], [true, ""], "one the user set stays theirs in gaming")
            LayoutService.setActiveMode("work")
            T.eq(NotificationService.dndActive, true, "and stays on after it")
            NotificationService.setDnd("off")

            LayoutService.setActiveMode("gaming", true)
            T.eq(NotificationService.dndBy, "gaming", "an automatic switch into gaming turns it on too")
            LayoutService.setActiveMode("laptop", true)
            T.eq(NotificationService.dndActive, false, "and one out of it off")
            LayoutService.setActiveMode("docked", true)
            T.eq(NotificationService.dndActive, false, "a switch between two others leaves it alone")
            profiles.start()
        }
    }

    // ---- a profile switch ---------------------------------------------------
    property string studio: ""
    Timer {
        id: profiles
        interval: 50
        onTriggered: {
            const folder = SettingsService.defaultOf("recording.folder")
            T.eq(SettingsService.value("recording.folder"), folder, "the recording folder is at its default")
            SettingsService.set("notch.hoverMode", "off")
            root.studio = LayoutService.addProfile("Studio")
            // A state stored before the notch's hover mode was one setting:
            // settings.json is migrated when it is read, a state was not.
            LayoutService.config = L.withState(LayoutService.config, root.studio,
                { settings: { notch: { expandOnHover: false } }, notch: null, lock: null })
            root.dataChanges = 0
            T.eq(LayoutService.setActiveProfile(root.studio), true, "into a profile with a state")
            T.eq(root.dataChanges, 1, "its settings and its mode's are one write")
            T.eq(SettingsService.value("notch.hoverMode"), "click", "a state from before a migration is migrated")
            T.eq(SettingsService.value("recording.folder"), folder, "the default recording folder stays as it is")
            T.eq(LayoutService.setActiveProfile("default"), true, "back")
            T.eq(L.stateOf(LayoutService.config, root.studio).settings.recording.folder, folder,
                 "and the state left keeps it as the default, not as an absolute path")
            T.eq(SettingsService.value("notch.hoverMode"), "off", "the profile left has its own hover mode back")

            LayoutService.config = L.withState(LayoutService.config, root.studio,
                { settings: { notch: { hoverMode: "bogus" } }, notch: null, lock: null })
            LayoutService.setActiveProfile(root.studio)
            T.eq(SettingsService.value("notch.hoverMode"), SettingsService.defaultOf("notch.hoverMode"),
                 "a value this version refuses is the default, not the hover mode of the profile left")
            LayoutService.setActiveProfile("default")
            T.finish("ModeEntryTest")
        }
    }
}
