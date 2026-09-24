.pragma library

// v2: { configVersion: 2, activeProfile, profiles: { <name>: { widgets, groups,
//       screens, mode, bar, quick, dashboard } }, notch, lock, adopted }
// v3: { configVersion: 3, activeProfile, activeMode,
//       profiles: { <profile>: { label, modes: { <mode>: { …, desktopMode } } } },
//       notch, lock, adopted }
//
// The five entries in v2 were never profiles. `minimal`, `work`, `gaming`,
// `laptop` and `docked` are **modes** - what the desktop is set to right now -
// and `laptop`/`docked` are the two AdaptiveService switches between on its
// own. The profile is the level above, and each one carries its own five modes.
//
// So all of v2 becomes the modes of one profile named "default", and
// `activeProfile` becomes `activeMode`, which is what it always meant. The
// notch, the lock screen and the adoption markers are global and stay at the
// top level, untouched.
//
// The one rename inside a mode: `mode` becomes `desktopMode`. A mode with a
// field called `mode` in it is two different words for two different things,
// and the file is being rewritten anyway - this is the cheapest moment it will
// ever have.
//
// **This migration must not change anything the user can see.** That is its
// acceptance test (tests/qml/MigrationTest.qml), not a hope.

var DEFAULT_PROFILE = "default"
var DEFAULT_LABEL = "Default"
var DEFAULT_MODE = "minimal"

function migrate(v2) {
    const source = v2 && typeof v2 === "object" ? v2 : {}
    const modes = source.profiles && typeof source.profiles === "object" ? source.profiles : {}
    const carried = {}
    for (const name of Object.keys(modes)) {
        const mode = modes[name] && typeof modes[name] === "object" ? modes[name] : {}
        const next = {}
        for (const key of Object.keys(mode))
            if (key !== "mode") next[key] = mode[key]
        if (mode.mode !== undefined) next.desktopMode = mode.mode
        carried[name] = next
    }
    const result = {
        configVersion: 3,
        activeProfile: DEFAULT_PROFILE,
        activeMode: typeof source.activeProfile === "string" && source.activeProfile.length
            ? source.activeProfile : DEFAULT_MODE,
        profiles: { [DEFAULT_PROFILE]: { label: DEFAULT_LABEL, modes: carried } }
    }
    // Global and not the migration's business: copied across as they are.
    for (const key of ["notch", "lock", "adopted"])
        if (source[key] !== undefined) result[key] = source[key]
    return result
}
