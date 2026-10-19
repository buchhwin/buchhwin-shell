.pragma library
.import "bar/BarLogic.js" as BarLogic
.import "quick/QuickLogic.js" as QuickLogic
.import "dashboard/DashboardLogic.js" as DashboardLogic
.import "arrange/FitLogic.js" as Fit
.import "launcher/LauncherCatalogue.js" as LauncherCatalogue
.import "lock/LockCatalogue.js" as LockCatalogue
.import "profile/ProfileLogic.js" as Profile
.import "notch/NotchLogic.js" as NotchLogic
.import "appearance/AnimationLogic.js" as AnimationLogic
.import "wallpaper/WallpaperLogic.js" as WallpaperLogic
.import "power/PowerSourceLogic.js" as PowerSourceLogic

// Pure layout operations shared by LayoutService and the unit tests.
var ANCHORS = ["left", "center", "right"]
var STYLES = ["minimal", "capsule", "card"]
var SIZES = ["small", "medium", "large"]
// How much larger a tile gets per size step. A bar item and a desktop widget
// use the same ladder, so "large" means the same thing wherever it appears.
var SIZE_SCALE = { small: 1, medium: 1.15, large: 1.3 }

function sizeScale(size) {
    return SIZE_SCALE[size] || 1
}
var SCALE_MIN = 0.7
var SCALE_MAX = 2.0
// Desktop modes, exactly one at a time: floating widgets, the top bar (pill
// or bar style) or a notch at the top centre (time only, a small overview on
// hover).
var DESKTOP_MODES = ["widgets", "pills", "notch"]
// Desktop mode names of older layouts. "both" showed widgets and the bar
// together; it becomes the bar and keeps every widget and pill in the mode.
var LEGACY_DESKTOP_MODES = { both: "pills" }
var DESKTOP_MODE_LABELS = { widgets: "Widgets", pills: "Bar", notch: "Notch" }
var ZONES = ["left", "center", "right"]
// Pill item looks: full, icon (compact) and expanded (only some widgets
// draw more, e.g. media with artist and controls; others treat it as full).
var DISPLAYS = ["full", "icon", "expanded"]
// A grid cell is at most this many columns and rows. The bounds are here and
// not at the surface so a layout file can never ask for a tile taller than the
// screen it is drawn on.
//
// `GRID_MAX_H` is what a surface gets unless it says otherwise: the bar, the
// notch, the control center and the dashboard all stop at six rows. A surface
// with a taller grid passes its own ceiling down through `sanitizeZones` - the
// launcher's is eight, because its grid is eight rows of an eighth of its card
// each. Raising the shared number instead quietly raised it for every surface,
// which `tests/qml/BarTest.qml` caught within the minute.
var GRID_MAX_W = 4
var GRID_MAX_H = 6
var FULLSCREEN = ["hide", "show"]

// A stored mode name as one of DESKTOP_MODES: legacy names migrate, unknown ones
// become "widgets".
function desktopModeName(mode) {
    const migrated = LEGACY_DESKTOP_MODES[mode] || mode
    return DESKTOP_MODES.indexOf(migrated) >= 0 ? migrated : "widgets"
}

// Which desktop surface a mode shows; exactly one of the three is true.
function desktopModeShows(mode) {
    const name = desktopModeName(mode)
    return { widgets: name === "widgets", bar: name === "pills", notch: name === "notch" }
}

function desktopModeLabel(mode) {
    return DESKTOP_MODE_LABELS[desktopModeName(mode)]
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

function num(value, fallback) {
    const result = Number(value)
    return isFinite(result) ? result : fallback
}

function oneOf(value, choices, fallback) {
    return choices.indexOf(value) >= 0 ? value : fallback
}

function sanitizeOptions(options) {
    const result = {}
    if (!options || typeof options !== "object") return result
    for (const key of Object.keys(options)) {
        const value = options[key]
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean")
            result[String(key)] = value
    }
    return result
}

function sanitizeWidget(widget) {
    return {
        id: String(widget.id),
        type: String(widget.type),
        screen: String(widget.screen),
        anchorX: oneOf(widget.anchorX, ANCHORS, "right"),
        x: clamp(num(widget.x, 0.5), 0, 1),
        y: clamp(num(widget.y, 0.05), 0, 1),
        scale: clamp(num(widget.scale, 1), SCALE_MIN, SCALE_MAX),
        size: oneOf(widget.size, SIZES, "small"),
        style: oneOf(widget.style, STYLES, "minimal"),
        visible: widget.visible === undefined ? true : Boolean(widget.visible),
        group: typeof widget.group === "string" ? widget.group : "",
        options: sanitizeOptions(widget.options)
    }
}

function sanitizeGroup(group) {
    return {
        id: String(group.id),
        screen: String(group.screen),
        anchorX: oneOf(group.anchorX, ANCHORS, "right"),
        x: clamp(num(group.x, 0.5), 0, 1),
        y: clamp(num(group.y, 0.05), 0, 1),
        scale: clamp(num(group.scale, 1), SCALE_MIN, SCALE_MAX),
        style: oneOf(group.style, STYLES, "minimal"),
        visible: group.visible === undefined ? true : Boolean(group.visible),
        members: Array.isArray(group.members) ? group.members.map(String) : []
    }
}

// ---- profiles and modes ----------------------------------------------------
// Two levels. A **mode** is one of the five the user switches between -
// minimal, work, gaming, laptop, docked - and holds a whole desktop: widgets,
// groups, screens, which surface it shows, the bar, the quick panel, the
// dashboard and the appearance it wants. A **profile** holds its own five of
// them. `ProfileLogic` defines both words and which settings a mode owns.
var MODE_NAMES = Profile.MODE_NAMES
var DEFAULT_PROFILE = "default"
var DEFAULT_PROFILE_LABEL = "Default"

// A mode nobody has touched yet. It is what `modeConfig` hands back for a mode
// that is not in the file, so every reader gets a whole object rather than a
// hole - and it is not written anywhere, so a mode stays absent until the first
// edit or the first materialize from its template.
function emptyMode() {
    return { widgets: [], groups: [], screens: [], desktopMode: "widgets", bar: defaultBar(),
             quick: defaultQuick(), dashboard: defaultDashboard(), launcher: defaultLauncher(),
             appearance: {} }
}

// The settings this mode owns, from the one list in ProfileLogic. Values are
// only kept when they are primitives and the key is on that list, so the file
// can never smuggle a setting into a mode that the mode is not allowed to set.
function sanitizeAppearance(appearance) {
    const result = {}
    if (!appearance || typeof appearance !== "object") return result
    for (const leaf of Profile.MODE_SCOPED) {
        const value = appearance[leaf]
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean")
            result[leaf] = value
    }
    return result
}

function sanitizeMode(mode) {
    const source = mode && typeof mode === "object" ? mode : {}
    const widgets = (Array.isArray(source.widgets) ? source.widgets : [])
        .filter(widget => widget && widget.id !== undefined && widget.type !== undefined && widget.screen !== undefined)
        .map(sanitizeWidget)
    const ids = widgets.map(widget => widget.id)
    const groups = (Array.isArray(source.groups) ? source.groups : [])
        .filter(group => group && group.id !== undefined && group.screen !== undefined)
        .map(sanitizeGroup)
        .map(group => Object.assign(group, { members: group.members.filter(id => ids.indexOf(id) >= 0) }))
        .filter(group => group.members.length > 0)
    const groupIds = groups.map(group => group.id)
    for (const widget of widgets)
        if (widget.group.length && groupIds.indexOf(widget.group) < 0) widget.group = ""
    return {
        widgets: widgets,
        groups: groups,
        screens: (Array.isArray(source.screens) ? source.screens : []).map(String),
        // `mode` was this field's name until v3, when the thing holding it
        // became a mode itself. The migration renames it; reading both keeps a
        // hand-edited or hand-restored file working.
        desktopMode: desktopModeName(source.desktopMode !== undefined ? source.desktopMode : source.mode),
        bar: sanitizeBar(source.bar),
        quick: sanitizeQuick(source.quick),
        dashboard: sanitizeDashboard(source.dashboard),
        // A mode written before the launcher had a layout simply gets the
        // default, the way one without a `quick` does - so no version bump and
        // no migration step, the same as `bar.screens` the round before.
        launcher: sanitizeLauncher(source.launcher),
        appearance: sanitizeAppearance(source.appearance)
    }
}

// `previous` is this profile in the config the caller started from, already
// sanitized (see sanitize): a mode or a state still shared with it is taken
// over unchecked, and one that comes out the same is that one.
function sanitizeProfile(profile, previous) {
    const source = profile && typeof profile === "object" ? profile : {}
    const modes = source.modes && typeof source.modes === "object" ? source.modes : {}
    const old = previous && typeof previous === "object" ? previous : null
    const oldModes = old && old.modes ? old.modes : {}
    const result = { label: typeof source.label === "string" && source.label.length ? source.label : "",
                     modes: {} }
    // Only the five: a mode name the shell has no template for has nothing to
    // switch to it and nothing to reset it from.
    for (const name of MODE_NAMES) {
        if (modes[name] === undefined) continue
        result.modes[name] = oldModes[name] !== undefined && modes[name] === oldModes[name]
            ? oldModes[name] : keepParts(oldModes[name], sanitizeMode(modes[name]))
    }
    if (old && sameMembers(result.modes, oldModes)) result.modes = oldModes
    // Which shipped profile this is (config/builtin-profiles/<id>), so it can
    // be told from a profile of the user's that happens to carry the same
    // name. Only written when set: the user's own profiles stay as they were.
    if (typeof source.builtin === "string" && source.builtin.length && Profile.slug(source.builtin) === source.builtin)
        result.builtin = source.builtin
    // Everything else the profile keeps (see sanitizeProfileState). Only
    // written once it has one: a profile that has never been left since
    // states existed simply has none yet.
    const state = old && old.state && source.state === old.state
        ? old.state : keep(old ? old.state : undefined, sanitizeProfileState(source.state))
    if (state) result.state = state
    return old && sameMembers(result, old) ? old : result
}

// ---- keeping what did not change ----------------------------------------------
// The config is never changed in place: every change is a new object, handed
// to LayoutService.config. A QML property given the very object it holds does
// not notify, so a part that came out the same as before is handed back as
// the object it was - and the notch, the dock and every mode's bar are not
// re-read on every screen for an edit somewhere else.

// `after`, or `before` when the two say the same.
function keep(before, after) {
    if (before === undefined || before === null || before === after) return after
    return JSON.stringify(before) === JSON.stringify(after) ? before : after
}

// The same one level down: each part of `after` that equals the one in
// `before` is that one, and when every part is, `before` itself.
function keepParts(before, after) {
    if (!before || typeof before !== "object" || !after || typeof after !== "object" || Array.isArray(after)) return after
    const result = {}
    for (const key of Object.keys(after)) result[key] = keep(before[key], after[key])
    return sameMembers(result, before) ? before : result
}

// Whether two objects hold the very same members under the same keys.
function sameMembers(a, b) {
    const keys = Object.keys(a)
    if (keys.length !== Object.keys(b).length) return false
    return keys.every(key => Object.prototype.hasOwnProperty.call(b, key) && a[key] === b[key])
}

// ---- a profile's own state ---------------------------------------------------
// What a profile keeps beside its five modes: every setting that is a
// profile's (ProfileLogic.isProfileSetting - not the machine's, not a mode's),
// the notch and the lock screen. LayoutService stores it when a profile is
// left and puts it back when the profile is entered again, so switching
// brings back the panel colour and the notch as well as the layouts.
//
// The shell wrote it, so it is checked loosely: the settings are kept as the
// primitive leaves of a profile's settings (whether this version knows them
// is SettingsService's question when they are restored, so a state written by
// a newer shell keeps its keys), the notch and the lock screen go through
// their own sanitizers. A part that is missing is null: restoring keeps the
// notch or the lock screen in use for it and gives the default dock
// (restoreStateLayout), the way a setting the state does not name gets its
// default (ProfileLogic.completeLeaves).
function sanitizeProfileState(state) {
    if (!state || typeof state !== "object" || Array.isArray(state)) return null
    return {
        settings: Profile.profileSettings(state.settings, ""),
        notch: state.notch && typeof state.notch === "object" ? sanitizeNotch(state.notch) : null,
        dock: state.dock && typeof state.dock === "object" ? sanitizeDock(state.dock) : null,
        lock: state.lock && typeof state.lock === "object" ? sanitizeLock(state.lock) : null
    }
}

// A profile's stored state, or null.
function stateOf(config, name) {
    const profile = config && config.profiles ? config.profiles[String(name)] : null
    return profile && profile.state ? profile.state : null
}

// The config with a profile's state replaced; null takes it away, so the next
// time the profile is entered it keeps what is set then - or, for a built-in
// one, gets its shipped state again.
function withState(config, name, state) {
    const next = copyConfig(config)
    const profile = next.profiles[String(name)]
    if (!profile) return sanitize(next)
    if (state) profile.state = JSON.parse(JSON.stringify(state))
    else delete profile.state
    return sanitize(next)
}

// ---- a state's settings, applied --------------------------------------------

// The settings migrations settings.json goes through when it is read
// (SettingsService.load), for a settings tree kept anywhere else: a profile's
// stored state and a shipped profile. A state is a copy of settings.json taken
// at a switch, and one taken before a migration still has the old form; read
// without it, the old key was dropped, the new one got its default and the
// user's choice was gone. Every step passes a tree it has nothing to do with
// through unchanged.
function migrateSettings(tree) {
    return NotchLogic.migrate(AnimationLogic.migrate(WallpaperLogic.migrate(PowerSourceLogic.migrate(tree))))
}

// A state's or a shipped profile's settings as the leaves a switch writes:
// every setting a profile owns - what `tree` names, the default (`defaults`,
// SettingsService.defaults) for what it does not (ProfileLogic.completeLeaves).
// A home path `tree` names is expanded (the export writes "~/"), but the
// defaults are left as they are: expanded, "~/Videos/Recordings" became the
// absolute path at the first switch and the folder was never at its default
// again. A path the tree names that *is* the default once expanded - every
// state stored since then, both shipped profiles - is that default.
function profileLeaves(tree, defaults, home) {
    const fallback = Profile.settingLeaves(defaults, "")
    const leaves = Profile.settingLeaves(tree, home)
    for (const path of Object.keys(leaves)) {
        const value = fallback[path]
        if (typeof value === "string" && value !== leaves[path] && Profile.expandHome(value, home) === leaves[path])
            leaves[path] = value
    }
    return Profile.completeLeaves(leaves, fallback)
}

// Of those leaves, the ones to write: each one SettingsService knows (a
// default that is not a group: `defaultOf`), as the value to set - the leaf,
// or the default where this version refuses the leaf (the wrong type, a value
// `allowed` does not list) - and only where that differs from what is set
// (`valueOf`). A refused value used to be skipped, which kept the setting of
// the profile just left, and the next switch stored that into this profile.
function knownSettings(leaves, defaultOf, allowed, valueOf) {
    const values = {}
    const lists = allowed && typeof allowed === "object" ? allowed : {}
    for (const path of Object.keys(leaves || {})) {
        const fallback = defaultOf(path)
        if (fallback === undefined || fallback === null || typeof fallback === "object") continue
        const choices = lists[path]
        const accepted = typeof leaves[path] === typeof fallback && (!choices || choices.indexOf(leaves[path]) >= 0)
        const value = accepted ? leaves[path] : fallback
        if (valueOf(path) !== value) values[path] = value
    }
    return values
}

// ---- undo ----------------------------------------------------------------
// What LayoutService.undo decides, apart from the config the step holds.

// The profiles' stored states for the config an undo step brings back. A step
// holds none (LayoutService.undoConfig): each profile keeps the state it has
// now, so undoing an edit never takes back what a switch stored or what
// entering a built-in one applied. A profile without one now takes the state
// its step was handed - the one that step's change took away: a profile
// removed (back now), or a built-in one Reset while another was in use (its
// state dropped so the next entry brings the shipped setup; undone, the
// user's own comes back with its modes). Changes and returns `stepConfig`,
// the step's own parsed copy.
function withUndoStates(stepConfig, config, handed) {
    const kept = handed && typeof handed === "object" ? handed : {}
    const profiles = stepConfig && stepConfig.profiles ? stepConfig.profiles : {}
    for (const name of Object.keys(profiles)) {
        const now = config && config.profiles ? config.profiles[name] : null
        const state = now && now.state ? now.state : kept[name] || null
        if (state) profiles[name].state = state
        else delete profiles[name].state
    }
    return stepConfig
}

// The config an undo step brings back, before it is sanitized. A step of the
// profile level (adding, duplicating, renaming, removing or resetting a
// profile) holds the whole layout without the states (LayoutService.
// undoConfig); the stored states, the saved notch presets and the one-shot
// markers are the config's at hand (withUndoStates and the lines below). Any
// other step holds only what an edit can change - which mode was in use, that
// mode and the one a switch went to (`modes.list`, null for one that was not
// there yet), and the global surfaces (notch, dock, lock screen) - and is
// laid over the config at hand: every other mode, every profile and every
// state stays as it is now. A step of the whole layout per edit was 26 KB
// with two profiles (19.10.), thirty steps deep, for a change to one pill.
// Changes `step.config` of the step's own parsed copy; the rest of `config`
// is shared, not changed.
function undoTarget(step, config) {
    const saved = step && step.config && typeof step.config === "object" ? step.config : {}
    const current = config && typeof config === "object" ? config : {}
    if (saved.profiles) {
        saved.notchPresets = current.notchPresets || []
        withUndoStates(saved, current, step.states)
        saved.adopted = current.adopted || []
        return saved
    }
    const next = Object.assign({}, current, { profiles: Object.assign({}, current.profiles || {}) })
    for (const key of ["activeMode", "notch", "dock", "lock"])
        if (saved[key] !== undefined) next[key] = saved[key]
    const part = step && step.modes && typeof step.modes === "object" ? step.modes : {}
    const profile = typeof part.profile === "string" ? next.profiles[part.profile] : undefined
    if (profile && part.list && typeof part.list === "object") {
        const modes = Object.assign({}, profile.modes || {})
        for (const name of Object.keys(part.list)) {
            if (part.list[name]) modes[name] = part.list[name]
            else delete modes[name]
        }
        next.profiles[part.profile] = Object.assign({}, profile, { modes: modes })
    }
    return next
}

// The appearance every mode has now (`current`), on the config an undo step
// brought back. A mode-scoped setting takes no undo step of its own - it is
// changed in Settings, from the launcher, anywhere - so a Ctrl+Z in the editor
// put back the gaps a mode had before an unrelated drag, while the gaps on
// screen stayed: the next time the mode was entered, the user's change was
// gone. Only a mode in both configs; one the step's own change replaced
// (`owned`, { profile: [mode, ...] } - a Reset) keeps the step's, which is
// what undoing it is for. Shares every other part with `config`.
function withCurrentAppearance(config, current, owned) {
    const mine = owned && typeof owned === "object" ? owned : {}
    const profiles = config && config.profiles ? config.profiles : {}
    let nextProfiles = null
    for (const name of Object.keys(profiles)) {
        const now = modesOf(current, name)
        const modes = profiles[name].modes || {}
        const skip = Array.isArray(mine[name]) ? mine[name] : []
        let nextModes = null
        for (const mode of Object.keys(modes)) {
            if (!now[mode] || skip.indexOf(mode) >= 0) continue
            const appearance = now[mode].appearance || {}
            if (keep(appearance, modes[mode].appearance) === appearance) continue
            if (!nextModes) nextModes = Object.assign({}, modes)
            nextModes[mode] = Object.assign({}, modes[mode], { appearance: appearance })
        }
        if (!nextModes) continue
        if (!nextProfiles) nextProfiles = Object.assign({}, profiles)
        nextProfiles[name] = Object.assign({}, profiles[name], { modes: nextModes })
    }
    return nextProfiles ? Object.assign({}, config, { profiles: nextProfiles }) : config
}

// The mode an undo step leaves in use. Every step holds the mode that was in
// use when it was taken, but only the step of a switch the user made
// (`modeSwitch`) takes the mode back. Any other keeps the mode in use now: it
// differs from the step's only after an automatic switch (a monitor plugged
// in), which takes no step - the machine chose that mode, and undoing an edit
// made before it must not switch back under the user's hands. The same holds
// for the user's switch once the machine has switched again since: the mode
// it went to (`modeSwitch.to`) is no longer in use, and switching back to the
// one before it would leave a docked laptop in Laptop.
function modeAfterUndo(step, current) {
    const switched = step && step.modeSwitch && step.config && typeof step.config.activeMode === "string"
    if (!switched) return current
    const to = step.modeSwitch.to
    return typeof to === "string" && to.length && to !== current ? current : step.config.activeMode
}

// The settings an undo step puts back: the ones every step carries (`keys`,
// LayoutService.undoKeys, kept in `step.notch`) and the ones the step's own
// change took along (`step.settings`) - a dock preset's dock.* options and
// whether the dock was on. Those are not every step's: a Ctrl+Z after an
// unrelated edit must not take back what was set in Settings > Dock since.
function undoSettings(step, keys) {
    const restored = {}
    const carried = step && step.notch && typeof step.notch === "object" ? step.notch : {}
    for (const key of Array.isArray(keys) ? keys : [])
        if (carried[key] !== undefined) restored[key] = carried[key]
    const own = step && step.settings && typeof step.settings === "object" ? step.settings : {}
    for (const key of Object.keys(own))
        if (own[key] !== undefined && own[key] !== null) restored[key] = own[key]
    return restored
}

// Do Not Disturb across a switch from mode `from` to mode `to` - by hand,
// automatic or undone. A mode whose template turns it on (gaming's
// `effects.dnd`) does so only when it finds it off, and then it is the
// mode's (`by`, kept by NotificationService): leaving that mode turns it off
// again, or hands it to the mode entered when that one turns it on too. One
// the user set, or changed since the mode set it (any other change clears
// `by`), is theirs and stays; so does one a mode found on. Entering with it
// on already changes nothing - a running "1 hour" stays an hour. null leaves
// it as it is; else `{ mode, by }` for NotificationService.setDnd.
function dndOnModeChange(by, active, from, to, toEffects) {
    if (from === to) return null
    const wanted = turnsDndOn(toEffects) ? toEffects.dnd : ""
    const owner = typeof by === "string" ? by : ""
    if (active && owner.length && owner === from)
        return wanted.length ? { mode: wanted, by: to } : { mode: "off", by: "" }
    if (!active && wanted.length) return { mode: wanted, by: to }
    return null
}

// Whether a mode's template turns Do Not Disturb on (`effects.dnd`, as
// gaming's does). Only such a mode ever owns it (dndOnModeChange), so a switch
// between two others has nothing to ask NotificationService - and a unit test
// switching modes does not start the session's notification server.
function turnsDndOn(effects) {
    return !!(effects && typeof effects.dnd === "string" && effects.dnd.length && effects.dnd !== "off")
}

// What the profile in use gets once per start (LayoutService.settleActiveState):
// "" when it has a state already; "shipped" for a built-in one whose shipped
// setup (`hasShipped`: the file was read) is to be applied; "current" when it
// takes what is set now. The first start of this version over an existing
// layout file (no `profileState` marker, not `fresh`) never applies a shipped
// setup: the built-in profile in use was entered by a version that applied it
// on every entry, and what the user changed since stays.
function settleAction(config, name, hasShipped, fresh) {
    if (stateOf(config, name)) return ""
    const first = !hasAdopted(config, "profileState")
    if (builtinOf(config, name).length && hasShipped === true && (!first || fresh === true)) return "shipped"
    return "current"
}

// A state put back: the notch and the lock screen it names replace the
// global ones. Its settings are SettingsService's to write, not this file's.
// `previous` as for sanitize: the config `config` shares its parts with.
function restoreStateLayout(config, state, previous) {
    const next = previous ? Object.assign({}, config) : copyConfig(config)
    if (state && state.notch) next.notch = copyNotch(state.notch)
    // The dock is the profile's like its settings (ProfileLogic.completeLeaves):
    // a state from before the dock gets the default one, not the dock of the
    // profile left.
    next.dock = state && state.dock ? copyDock(state.dock) : defaultDock()
    if (state && state.lock) next.lock = sanitizeLock(JSON.parse(JSON.stringify(state.lock)))
    return sanitize(next, previous)
}

// Rebuild a v3 layout from whitelisted primitive fields only.
//
// `previous`, when given, is the config `config` was made from: a result of
// this function, never changed in place since. A part of `config` that is
// still one of previous's own objects - a profile, a mode or a state an edit
// did not touch - is taken over as it is rather than checked again, and every
// part that comes out the same as before is the previous object (see keep).
// The result is the one a whole check would give; an edit of one pill used
// to copy and check every profile's state and every mode.
function sanitize(config, previous) {
    const before = previous && typeof previous === "object" ? previous : {}
    // The notch, the dock and the lock screen at the top level are the ones
    // of the profile in use - each profile keeps its own copies in its state
    // (restoreStateLayout puts them back) - and the notch presets and the
    // adoption markers are global.
    // A file without one of them simply gets the default, the way a mode without a
    // `quick` does, so no version bump and no migration step is needed.
    const result = { configVersion: 3, activeProfile: DEFAULT_PROFILE, activeMode: MODE_NAMES[0],
                     profiles: {}, notch: defaultNotch(), notchPresets: [], dock: defaultDock(), lock: defaultLock(), adopted: [] }
    if (!config || typeof config !== "object") return result
    // A part shared with `previous` is previous's; any other is checked.
    const part = (key, check) => before[key] !== undefined && config[key] === before[key]
        ? before[key] : keep(before[key], check(config[key]))
    result.adopted = part("adopted", list => Array.isArray(list)
        ? list.filter(name => typeof name === "string" && name.length).map(String) : [])
    result.notch = part("notch", notch => notch ? sanitizeNotch(notch) : defaultNotch())
    result.notchPresets = part("notchPresets", sanitizeNotchPresets)
    // The dock's zones and pins; a file without them gets the default dock.
    result.dock = part("dock", dock => dock ? sanitizeDock(dock) : defaultDock())
    result.lock = part("lock", lock => lock ? sanitizeLock(lock) : defaultLock())
    if (typeof config.activeProfile === "string" && config.activeProfile.length)
        result.activeProfile = config.activeProfile
    if (typeof config.activeMode === "string" && MODE_NAMES.indexOf(config.activeMode) >= 0)
        result.activeMode = config.activeMode
    const profiles = config.profiles && typeof config.profiles === "object" ? config.profiles : {}
    const oldProfiles = before.profiles && typeof before.profiles === "object" ? before.profiles : {}
    for (const name of Object.keys(profiles)) {
        const old = oldProfiles[String(name)]
        result.profiles[String(name)] = old !== undefined && profiles[name] === old ? old : sanitizeProfile(profiles[name], old)
    }
    // A file with no profile at all still has one to be in, and the active
    // profile always names a profile that exists - otherwise every read falls
    // through to `emptyMode` and the user's desktop is simply gone.
    if (!Object.keys(result.profiles).length)
        result.profiles[DEFAULT_PROFILE] = { label: DEFAULT_PROFILE_LABEL, modes: {} }
    if (!result.profiles[result.activeProfile])
        result.activeProfile = Object.keys(result.profiles)[0]
    if (before.profiles && sameMembers(result.profiles, oldProfiles)) result.profiles = oldProfiles
    return result
}

// ---- reading the two levels ------------------------------------------------

function profileNames(config) {
    return Object.keys(config && config.profiles ? config.profiles : {})
}

function profileLabel(config, name) {
    const profile = config && config.profiles ? config.profiles[String(name)] : null
    return profile && profile.label ? profile.label : String(name || "")
}

// The modes of one profile, always an object.
function modesOf(config, profileName) {
    const profile = config && config.profiles ? config.profiles[String(profileName)] : null
    return profile && profile.modes ? profile.modes : {}
}

// The configuration of one mode of one profile. A mode that is not in the file
// reads as an empty one rather than as nothing at all.
function modeConfig(config, profileName, modeName) {
    const modes = modesOf(config, profileName)
    return modes[String(modeName)] || emptyMode()
}

// ---- changing the profile level --------------------------------------------
// All four return a new config and never mutate the input. None of them touches
// the notch, the dock or the lock screen in use, the notch presets or the
// adoption markers: the first three are the profile in use's (LayoutService
// copies them into its state and back), the other two are global.

function copyConfig(config) {
    return JSON.parse(JSON.stringify(config))
}

// ---- one mode at a time -------------------------------------------------------
// Almost every change is to the mode in use or to the global surfaces beside
// it. These change that much and share everything else with the config they
// start from (a sanitize result), which sanitize then takes over unchecked.

// One edit, the way LayoutService makes every edit: `callback(mode, next)`
// changes `mode` - a copy of the mode `modeName` of the profile, an empty one
// when it is not in the file yet - and may replace the global surfaces on
// `next` (notch, dock, lock screen, notch presets, markers), which are copies
// too. Nothing else on `next` is the callback's: the other modes and
// profiles are `config`'s own objects. The result is the one a whole copy
// and a whole check would give, with every part that did not change the
// object it was.
function edit(config, profileName, modeName, callback) {
    const name = String(profileName)
    const source = config && config.profiles ? config.profiles[name] : null
    const profile = source || { label: DEFAULT_PROFILE_LABEL, modes: {} }
    const modes = profile.modes || {}
    const mode = copyConfig(modes[String(modeName)] || { widgets: [], groups: [], screens: [] })
    const next = Object.assign({}, config)
    for (const key of ["notch", "notchPresets", "dock", "lock", "adopted"])
        if (config[key] !== undefined) next[key] = copyConfig(config[key])
    next.profiles = Object.assign({}, config.profiles)
    next.profiles[name] = Object.assign({}, profile, { modes: Object.assign({}, modes, { [String(modeName)]: mode }) })
    callback(mode, next)
    return sanitize(next, config)
}

// The config with one mode replaced (and checked), the rest shared.
function withMode(config, profileName, modeName, mode) {
    const name = String(profileName)
    const source = config && config.profiles ? config.profiles[name] : null
    const profile = source || { label: DEFAULT_PROFILE_LABEL, modes: {} }
    const next = Object.assign({}, config, { profiles: Object.assign({}, config.profiles) })
    next.profiles[name] = Object.assign({}, profile,
        { modes: Object.assign({}, profile.modes || {}, { [String(modeName)]: mode }) })
    return sanitize(next, config)
}

// A mode entered for the first time, before its widgets are made: the desktop
// mode and the bar of its factory template. Without them a mode that is in
// the file but has never been entered - one the appearance adoption made -
// showed widgets where its template has a bar or the notch.
function freshMode(template) {
    const mode = { widgets: [], groups: [], screens: [] }
    // `desktopMode`, the layout file's own word for it; `mode` is what the
    // templates called it before.
    const desktop = template ? template.desktopMode || template.mode : ""
    if (desktop) mode.desktopMode = desktop
    if (template && template.bar) mode.bar = copyConfig(template.bar)
    return mode
}

// A new profile starts with **no** modes. Each one is then materialized from
// its factory template (`config/profiles/<mode>.json`) the first time it is
// entered, which is what "copies from the factory state, not from Default"
// means in practice - and it is the path a mode nobody had visited yet has
// always taken.
function addProfile(config, label) {
    const next = copyConfig(config)
    const name = Profile.uniqueName(label, Object.keys(next.profiles))
    next.profiles[name] = { label: String(label || "").trim() || name, modes: {} }
    return { config: sanitize(next), name: name }
}

// The other case: this profile as it stands, copied whole - its modes and
// its state. `state` is the one to copy: the caller passes the settings as
// they are now when the source is the profile in use, whose stored state is
// only as new as the last time it was left. Without one the source's own is
// copied, if it has one.
function duplicateProfile(config, source, label, state) {
    const next = copyConfig(config)
    const from = next.profiles[String(source)]
    if (!from) return { config: sanitize(next), name: "" }
    const name = Profile.uniqueName(label, Object.keys(next.profiles))
    next.profiles[name] = { label: String(label || "").trim() || name,
                            modes: JSON.parse(JSON.stringify(from.modes || {})) }
    const kept = state || from.state
    if (kept) next.profiles[name].state = JSON.parse(JSON.stringify(kept))
    return { config: sanitize(next), name: name }
}

function renameProfile(config, name, label) {
    const next = copyConfig(config)
    const profile = next.profiles[String(name)]
    if (!profile) return sanitize(next)
    profile.label = String(label || "").trim() || String(name)
    return sanitize(next)
}

// The last profile is not removable: there has to be one to be in. Nor is a
// built-in one: it would only come back on the next start.
function removeProfile(config, name) {
    const next = copyConfig(config)
    const key = String(name)
    if (!next.profiles[key] || next.profiles[key].builtin || Object.keys(next.profiles).length < 2) return sanitize(next)
    delete next.profiles[key]
    if (next.activeProfile === key) next.activeProfile = Object.keys(next.profiles)[0]
    return sanitize(next)
}

// Back to the factory state, by emptying it: the next `ensureScreens` fills
// each mode from its template again. One mode by name, or the whole profile.
//
// A built-in profile has a state of its own to go back to - the modes it
// shipped with - and `shipped` is those. A mode the shipped file does not
// carry falls back to the factory template the usual way.
//
// The profile's stored state (settings, notch, lock screen) is not touched
// here. A profile of the user's has no factory settings to go back to - the
// factory state of a setting is its default, and resetting the layouts is not
// a request to reset the accent - so it keeps its state. A built-in profile's
// shipped state comes back through LayoutService.resetProfile.
function resetProfile(config, name, modeName, shipped) {
    const next = copyConfig(config)
    const profile = next.profiles[String(name)]
    if (!profile) return sanitize(next)
    const all = modeName === undefined || modeName === null || modeName === ""
    if (profile.builtin && shipped && typeof shipped === "object") {
        const modes = JSON.parse(JSON.stringify(shipped))
        if (all) profile.modes = modes
        else if (modes[String(modeName)] !== undefined) profile.modes[String(modeName)] = modes[String(modeName)]
        else delete profile.modes[String(modeName)]
        return sanitize(next)
    }
    if (all) profile.modes = {}
    else delete profile.modes[String(modeName)]
    return sanitize(next)
}

// ---- built-in profiles -------------------------------------------------------
// A profile the repository ships: config/builtin-profiles/<id>/profile.json,
// written by scripts/profile-export.py. It is always in the layout file, marked
// with `builtin: "<id>"`; its modes and its state are the user's to change like
// any other profile's, and "Reset" brings back the shipped ones. The rest of
// the file - the notch, its presets, the lock screen, the settings, the
// default apps and fastfetch - is applied the first time the profile is
// entered (LayoutService.startBuiltin) and becomes its state; after that the
// profile keeps whatever the user makes of it.

// The shipped file, whitelisted like everything else that is read: null when
// it has no modes, because a built-in profile without them is nothing to add.
function sanitizeBuiltinProfile(data, id) {
    if (!data || typeof data !== "object") return null
    const key = String(id || "")
    if (!key.length || Profile.slug(key) !== key) return null
    if (!data.modes || typeof data.modes !== "object") return null
    const label = typeof data.label === "string" && data.label.trim().length ? data.label.trim().slice(0, 40) : key
    const apps = {}
    const sourceApps = data.defaultApps && typeof data.defaultApps === "object" ? data.defaultApps : {}
    for (const category of ["terminal", "files"]) {
        const value = sourceApps[category]
        if (typeof value === "string" && /^[A-Za-z0-9._-]+\.desktop$/.test(value)) apps[category] = value
    }
    return {
        id: key,
        label: label,
        modes: sanitizeProfile({ modes: data.modes }).modes,
        notch: sanitizeNotch(data.notch),
        notchPresets: sanitizeNotchPresets(data.notchPresets),
        lock: sanitizeLock(data.lock),
        settings: data.settings && typeof data.settings === "object" && !Array.isArray(data.settings) ? data.settings : {},
        defaultApps: apps
    }
}

// Which built-in profile a profile is, or "".
function builtinOf(config, name) {
    const profile = config && config.profiles ? config.profiles[String(name)] : null
    return profile && typeof profile.builtin === "string" ? profile.builtin : ""
}

// The profile that carries a built-in id, or "".
function builtinProfileName(config, id) {
    for (const name of profileNames(config))
        if (builtinOf(config, name) === String(id)) return name
    return ""
}

// Every built-in profile the file does not carry yet, added under its own id.
// A profile of the user's may already have that name (one they called
// "buchhwin" before there was a built-in one): it stays exactly as it is, and
// the built-in one takes the next free name instead - recognised by its
// `builtin` field from then on, never by its name. `added` is empty when
// nothing changed, so the caller writes only then.
//
// The one exception is the Default profile. Every layout file has one (the
// sanitizer makes it), and the shipped "default" is that profile rather than
// a second one beside it: an unmarked "default" is adopted - marked, with its
// label, its modes and its state kept. Only a file that is new (`fresh`: the
// layout file was missing or empty, a first start) takes the shipped modes as
// well, because there is nothing of the user's in it to keep yet.
function addBuiltinProfiles(config, builtins, fresh) {
    const next = copyConfig(config)
    const added = []
    for (const data of Array.isArray(builtins) ? builtins : []) {
        if (!data || typeof data.id !== "string" || !data.id.length) continue
        if (builtinProfileName(next, data.id).length) continue
        const own = next.profiles[data.id]
        if (data.id === DEFAULT_PROFILE && own && !own.builtin) {
            own.builtin = data.id
            if (fresh === true) own.modes = JSON.parse(JSON.stringify(data.modes || {}))
            added.push(data.id)
            continue
        }
        const name = Profile.uniqueName(data.id, Object.keys(next.profiles))
        next.profiles[name] = { label: data.label || data.id, modes: JSON.parse(JSON.stringify(data.modes || {})),
                                builtin: data.id }
        added.push(name)
    }
    return { config: added.length ? sanitize(next) : config, added: added }
}

// The global half of a built-in profile: its notch and its lock screen
// replace the ones in the file. Its notch presets come in beside the user's
// own, replacing one of the same id: a preset is saved like a file (no undo
// step, see LayoutService.undo), and activating a profile is not deleting
// one the user saved after the profile was exported.
function applyBuiltinLayout(config, data) {
    const next = copyConfig(config)
    if (!data || typeof data !== "object") return sanitize(next)
    next.notch = copyNotch(data.notch || defaultNotch())
    next.lock = sanitizeLock(JSON.parse(JSON.stringify(data.lock || defaultLock())))
    // A shipped profile without a dock of its own (both, so far) has the
    // default one - and its settings the dock off (completeLeaves).
    next.dock = data.dock && typeof data.dock === "object" ? sanitizeDock(data.dock) : defaultDock()
    const shipped = sanitizeNotchPresets(data.notchPresets)
    const ids = shipped.map(preset => preset.id)
    next.notchPresets = shipped.concat(sanitizeNotchPresets(next.notchPresets).filter(preset => ids.indexOf(preset.id) < 0))
    return sanitize(next)
}

// One-shot migrations that have already run on this file. The marker belongs
// in the same file as the data it guards: the quick tiles' one lived in
// settings.json while the sizes lived here, so restoring one file without the
// other silently reset every size the user had set by hand.
function hasAdopted(config, name) {
    return !!(config && Array.isArray(config.adopted) && config.adopted.indexOf(name) >= 0)
}

function withAdopted(config, name) {
    const list = config && Array.isArray(config.adopted) ? config.adopted.slice() : []
    if (list.indexOf(name) < 0) list.push(name)
    return list
}

function uniqueId(prefix, taken) {
    if (taken.indexOf(prefix) < 0) return prefix
    let index = 2
    while (taken.indexOf(prefix + "-" + index) >= 0) index += 1
    return prefix + "-" + index
}

// Create screen-specific widgets from a profile template.
function materialize(template, screen, existingIds, isKnownType) {
    const taken = existingIds.slice()
    const widgets = []
    const groups = []
    const idMap = {}
    for (const entry of (template && Array.isArray(template.widgets) ? template.widgets : [])) {
        if (entry.screen !== undefined && entry.screen !== "*" && entry.screen !== screen) continue
        if (isKnownType && !isKnownType(entry.type)) continue
        const id = uniqueId(entry.type + "-" + screen, taken)
        taken.push(id)
        if (entry.key) idMap[entry.key] = id
        widgets.push(sanitizeWidget(Object.assign({}, entry, { id: id, screen: screen, group: "" })))
    }
    for (const entry of (template && Array.isArray(template.groups) ? template.groups : [])) {
        const members = (entry.members || []).map(key => idMap[key]).filter(Boolean)
        if (!members.length) continue
        const id = uniqueId("group-" + screen, taken)
        taken.push(id)
        groups.push(sanitizeGroup(Object.assign({}, entry, { id: id, screen: screen, members: members })))
        for (const widget of widgets)
            if (members.indexOf(widget.id) >= 0) widget.group = id
    }
    return { widgets: widgets, groups: groups }
}

// Top-level placements (ungrouped widgets and groups) for one screen.
function placements(profile, screen, includeHidden) {
    if (!profile) return []
    const result = []
    for (const widget of profile.widgets)
        if (widget.screen === screen && !widget.group.length && (includeHidden || widget.visible))
            result.push(widget.id)
    for (const group of profile.groups)
        if (group.screen === screen && (includeHidden || group.visible))
            result.push(group.id)
    return result
}

// Screen position (top-left, logical pixels) of a placement.
function pixelPosition(item, width, height, screenWidth, screenHeight) {
    const anchorX = item.x * screenWidth
    let left = item.anchorX === "right" ? anchorX - width : item.anchorX === "center" ? anchorX - width / 2 : anchorX
    left = clamp(left, 0, Math.max(0, screenWidth - width))
    const top = clamp(item.y * screenHeight, 0, Math.max(0, screenHeight - height))
    return { x: left, y: top }
}

// Relative position for a top-left pixel position; the anchor follows the
// screen third that contains the item's centre.
function relativePosition(left, top, width, height, screenWidth, screenHeight) {
    const centre = left + width / 2
    const anchorX = centre < screenWidth / 3 ? "left" : centre > screenWidth * 2 / 3 ? "right" : "center"
    const x = anchorX === "left" ? left : anchorX === "right" ? left + width : centre
    return {
        anchorX: anchorX,
        x: clamp(x / Math.max(1, screenWidth), 0, 1),
        y: clamp(top / Math.max(1, screenHeight), 0, 1)
    }
}

// ---- pill bar --------------------------------------------------------------
// bar: { reserve, fullscreen, scale, style, position, left: [pill], center: [pill], right: [pill] }
// style "pills" (capsules) or "bar" (one continuous bar, position "floating"
// or "attached"); a missing style is "pills".
// pill: { id, items: [{ type, display, options }] }

function defaultBar() {
    return {
        reserve: true,
        fullscreen: "hide",
        scale: 1,
        style: "pills",
        position: "floating",
        edge: "top",
        panelSpot: "widget",
        notificationSpot: "widget",
        screens: [],
        left: [{ id: "pill-1", items: [{ type: "nowPlaying", display: "icon", options: {} }] }],
        center: [{ id: "pill-2", items: [{ type: "clock", display: "full", options: {} }] }],
        right: [{ id: "pill-3", items: [{ type: "network", display: "icon", options: {} }] }]
    }
}

function sanitizeBarItem(item, ceiling) {
    return {
        type: String(item.type),
        display: oneOf(item.display, DISPLAYS, "full"),
        // Each item carries its own size, so one tile can be bigger than its
        // neighbours instead of the whole bar having to grow.
        size: oneOf(item.size, SIZES, "small"),
        // How much of a grid it takes, in columns and rows - the notch overview
        // today, the dashboard next. A surface laid out along one line, like
        // the bar, ignores both.
        w: clamp(Math.round(num(item.w, 1)), 1, GRID_MAX_W),
        h: clamp(Math.round(num(item.h, 1)), 1, ceiling || GRID_MAX_H),
        options: sanitizeOptions(item.options)
    }
}

// The zone -> pill -> item model, for any surface that uses it. The bar is the
// first; the notch, the quick panel and the dashboard are meant to follow, and
// keeping the shape in one function is what makes that possible.
function sanitizeZones(config, zoneNames, maxH) {
    const zones = Array.isArray(zoneNames) && zoneNames.length ? zoneNames : ZONES
    const result = {}
    const taken = []
    for (const zone of zones) {
        result[zone] = (Array.isArray(config && config[zone]) ? config[zone] : [])
            .filter(pill => pill && Array.isArray(pill.items))
            .map(pill => {
                const items = pill.items.filter(item => item && typeof item.type === "string" && item.type.length)
                    .map(item => sanitizeBarItem(item, maxH))
                let id = typeof pill.id === "string" && pill.id.length ? pill.id : "pill"
                if (taken.indexOf(id) >= 0) id = uniqueId("pill", taken)
                taken.push(id)
                return { id: id, items: items }
            })
            .filter(pill => pill.items.length > 0)
    }
    return result
}

// ---- the notch --------------------------------------------------------
// Two zones on the same zone -> pill -> item shape as the bar: the strip that
// is always on screen, and the overview it opens into on hover. They live at
// the top level of the layout file rather than inside a mode, because the
// notch is the same in all five; each profile keeps its own copy in its state,
// put back when the profile is entered (restoreStateLayout).
//
// They cannot live in settings.json, where the rest of the notch's options
// are: SettingsService rebuilds every stored object with Object.keys, which
// turns an array into { "0": ..., "1": ... } on the first write of any
// setting. The two existing list-shaped settings are comma-strings for that
// reason, and a comma-string cannot carry a display or a size.
const NOTCH_ZONES = ["collapsed", "expanded"]
const NOTCH_COLLAPSED_DEFAULT = ["clock"]
const NOTCH_EXPANDED_DEFAULT = ["clock", "weather", "media", "events", "status"]

// The size a type starts at in the overview's four-column grid. It reproduces
// what the notch looked like before it could be sized at all: the media and
// the events beside each other, the status chips across the bottom. Anything
// else - a widget - is a small readout and starts at one cell.
const NOTCH_SIZES = { clock: { w: 2, h: 2 }, weather: { w: 2, h: 2 },
                      media: { w: 2, h: 2, minW: 2, minH: 2 }, events: { w: 2, h: 2, minH: 2 },
                      status: { w: 4, h: 1 } }

// A widget starts two rows tall rather than one. One row is the smallest cell
// the grid has, and a widget that lands on it has room for a glyph and nothing
// else - which is what every widget dropped on the notch used to get, because
// the fallback here was the smallest cell there is.
function notchSize(type) {
    return NOTCH_SIZES[String(type)] || { w: 1, h: 2 }
}

// The smallest cell an item may be pulled to in the overview.
function notchMinSize(type) {
    return Fit.minSize(NOTCH_SIZES[String(type)])
}

// `taken` carries the ids the other zone already used: ids are unique across
// both zones, and the two lists can hold the same type - a clock in the strip
// and the big one in the overview - so numbering each list on its own handed
// out the same id twice and sanitizeZones quietly renamed one of them.
function notchList(types, taken) {
    const used = Array.isArray(taken) ? taken : []
    return types.map((type, index) => {
        const id = uniqueId("notch-" + type + "-" + (index + 1), used)
        used.push(id)
        const size = notchSize(type)
        // The same key order sanitizeBarItem produces, so a default notch and
        // a sanitized one are the same text in the layout file.
        return {
            id: id,
            items: [{ type: type, display: "full", size: "small", w: size.w, h: size.h, options: {} }]
        }
    })
}

function defaultNotch() {
    const taken = []
    return { collapsed: notchList(NOTCH_COLLAPSED_DEFAULT, taken),
             expanded: notchList(NOTCH_EXPANDED_DEFAULT, taken) }
}

function sanitizeNotch(notch) {
    if (!notch || typeof notch !== "object") return defaultNotch()
    const zones = sanitizeZones(notch, NOTCH_ZONES)
    // One item per pill here too: the notch shows a row of things, not a row
    // of groups of things.
    const shape = {}
    for (const zone of NOTCH_ZONES)
        shape[zone] = zones[zone].map(pill => ({ id: pill.id, items: [pill.items[0]] }))
    // The strip draws no media, events or status block (NotchLogic.
    // stripTakes): one stored there - before the editor refused it, or by
    // hand - drew nothing and kept the type out of the overview. It goes
    // back to the overview, or away when the overview has that block already.
    const refused = shape.collapsed.filter(pill => !NotchLogic.stripTakes(pill.items[0].type))
    if (refused.length) {
        shape.collapsed = shape.collapsed.filter(pill => NotchLogic.stripTakes(pill.items[0].type))
        const there = shape.expanded.map(pill => pill.items[0].type)
        for (const pill of refused) {
            if (there.indexOf(pill.items[0].type) >= 0) continue
            shape.expanded.push(pill)
            there.push(pill.items[0].type)
        }
    }
    // An empty overview is a notch that does nothing on hover, which is a
    // choice; an empty strip is a notch that is not there, which is not.
    if (!shape.collapsed.length) shape.collapsed = notchList(NOTCH_COLLAPSED_DEFAULT)
    // The floor the editor applies is applied to the file as well: a media
    // item written one cell wide by hand, or by a version that had no floor,
    // used to load at one cell and only stop at two once it was dragged.
    for (const zone of NOTCH_ZONES)
        for (const pill of shape[zone])
            raiseToLeast(pill.items[0], notchMinSize(pill.items[0].type))
    return shape
}

function raiseToLeast(item, least) {
    item.w = Math.max(item.w, least.w)
    item.h = Math.max(item.h, least.h)
    return item
}

function notchTypes(notch, zone) {
    return notchItems(notch, zone).map(item => item.type)
}

// The zone as the editor needs it: the stored id beside the type, because the
// notch shows types and the layout file moves ids.
function notchItems(notch, zone) {
    const list = notch && Array.isArray(notch[zone]) ? notch[zone] : []
    return list.map(pill => ({ id: pill.id, type: pill.items[0].type,
                               w: pill.items[0].w, h: pill.items[0].h,
                               display: pill.items[0].display, options: pill.items[0].options || {} }))
}

// ---- notch presets ---------------------------------------------------------
// A preset is a whole notch: both lists and the options that shape it (size,
// outline, how it opens, and the collapsed body's height, corner radius and
// padding - Classic's 32 / 11 / 16 against Island's 34 / 14 / 22). The
// built-in ones are files in config/notch-presets/ written in a short form;
// the user's own live in the layout file beside the notch itself, and unlike
// it they are global: one library for every profile. Applying one is a single undo step (LayoutService.applyNotchPreset).
var NOTCH_PRESET_OPTIONS = ["shape", "collapsedWidth", "expandedWidth", "expandedHeight",
                            "hoverMode", "openDelay", "closeDelay", "clickAction", "middleAction", "rightAction", "swipe", "panelOrigin", "accentGlyphs", "eventCount",
                            "bodyHeight", "bodyRadius", "bodyPadding"]

function notchPresetOptions(options) {
    const result = {}
    const source = options && typeof options === "object" ? options : {}
    for (const key of NOTCH_PRESET_OPTIONS) {
        const value = source[key]
        if (typeof value === "string" || typeof value === "boolean" || (typeof value === "number" && isFinite(value)))
            result[key] = value
    }
    return result
}

// The short form of a built-in preset: each list a row of types, or of
// { type, w, h } where the size matters.
function notchFromSpec(spec) {
    const taken = []
    const zone = list => (Array.isArray(list) ? list : []).map((entry, index) => {
        const type = typeof entry === "string" ? entry : entry && entry.type
        if (typeof type !== "string" || !type.length) return null
        const id = uniqueId("notch-" + type + "-" + (index + 1), taken)
        taken.push(id)
        const size = notchSize(type)
        const w = entry && typeof entry.w === "number" ? entry.w : size.w
        const h = entry && typeof entry.h === "number" ? entry.h : size.h
        // "icon" draws a widget as its glyph alone (a battery without its
        // percentage); options are the widget's own, e.g. a workspace style.
        const display = entry && typeof entry.display === "string" ? entry.display : "full"
        const options = entry && entry.options && typeof entry.options === "object" ? entry.options : {}
        return { id: id, items: [{ type: type, display: display, size: "small", w: w, h: h, options: options }] }
    }).filter(pill => pill !== null)
    return sanitizeNotch({ collapsed: zone(spec && spec.collapsed), expanded: zone(spec && spec.expanded) })
}

// How long a preset's description may be. The picker wraps it under the name,
// so this only keeps a hand-edited layout file from filling the card; at 120
// it cut Island's own 143 characters off mid-word.
var PRESET_DESCRIPTION_MAX = 280

// A preset as stored or loaded: null when it has no name to show.
function sanitizeNotchPreset(preset, builtin) {
    if (!preset || typeof preset !== "object") return null
    const label = typeof preset.label === "string" ? preset.label.trim().slice(0, 40) : ""
    if (!label.length) return null
    const layout = preset.layout && typeof preset.layout === "object" ? sanitizeNotch(preset.layout) : notchFromSpec(preset)
    return { id: typeof preset.id === "string" && preset.id.length ? preset.id : Profile.slug(label),
             label: label, builtin: builtin === true,
             description: typeof preset.description === "string" ? preset.description.slice(0, PRESET_DESCRIPTION_MAX) : "",
             layout: layout, options: notchPresetOptions(preset.options) }
}

function sanitizeNotchPresets(list) {
    const taken = []
    const result = []
    for (const entry of Array.isArray(list) ? list : []) {
        const preset = sanitizeNotchPreset(entry, false)
        if (!preset) continue
        preset.id = uniqueId(preset.id, taken)
        taken.push(preset.id)
        result.push(preset)
    }
    return result
}

// The user's own: saved from the notch as it is now. `reserved` holds the ids
// of the built-in presets, which a custom one must not shadow.
function addNotchPreset(config, label, notch, options, reserved) {
    const next = JSON.parse(JSON.stringify(config))
    const presets = sanitizeNotchPresets(next.notchPresets)
    const taken = presets.map(preset => preset.id).concat(Array.isArray(reserved) ? reserved : [])
    const preset = sanitizeNotchPreset({ label: label, layout: notch, options: options }, false)
    if (!preset) return { config: config, id: "" }
    preset.id = uniqueId("custom-" + Profile.slug(preset.label), taken)
    presets.push(preset)
    next.notchPresets = presets
    return { config: next, id: preset.id }
}

function renameNotchPreset(config, id, label) {
    const text = String(label || "").trim().slice(0, 40)
    if (!text.length) return config
    const next = JSON.parse(JSON.stringify(config))
    next.notchPresets = sanitizeNotchPresets(next.notchPresets).map(preset =>
        preset.id === id ? Object.assign({}, preset, { label: text }) : preset)
    return next
}

function removeNotchPreset(config, id) {
    const next = JSON.parse(JSON.stringify(config))
    next.notchPresets = sanitizeNotchPresets(next.notchPresets).filter(preset => preset.id !== id)
    return next
}

function copyNotch(notch) {
    return sanitizeNotch(JSON.parse(JSON.stringify(notch)))
}

function findNotch(notch, zone, id) {
    return notch[zone].findIndex(pill => pill.id === id)
}

function notchZoneOf(notch, id) {
    for (const zone of NOTCH_ZONES) {
        const index = findNotch(notch, zone, id)
        if (index >= 0) return { zone: zone, index: index }
    }
    return null
}

// Move an item inside its zone or into the other one.
function moveNotchItemTo(notch, id, zone, index) {
    const next = copyNotch(notch)
    if (NOTCH_ZONES.indexOf(zone) < 0) return next
    const place = notchZoneOf(next, id)
    if (!place) return next
    // Never into the strip for a block it cannot draw (the overview tile's
    // arrow, a drag): it would be an empty spot there.
    if (zone === "collapsed" && !NotchLogic.stripTakes(next[place.zone][place.index].items[0].type)) return next
    const moved = next[place.zone].splice(place.index, 1)[0]
    next[zone].splice(Math.max(0, Math.min(next[zone].length, index)), 0, moved)
    return sanitizeNotch(next)
}

function removeNotchItem(notch, id) {
    const next = copyNotch(notch)
    const place = notchZoneOf(next, id)
    if (place) next[place.zone].splice(place.index, 1)
    return sanitizeNotch(next)
}

// Added to the overview, which is where there is room for it. A type already
// on the notch is not added twice: two clocks are a mistake, not a layout.
function addNotchItem(notch, type, zone) {
    const next = copyNotch(notch)
    const name = String(type || "")
    if (!name.length) return next
    for (const each of NOTCH_ZONES)
        if (notchTypes(next, each).indexOf(name) >= 0) return next
    const target = NOTCH_ZONES.indexOf(zone) >= 0 ? zone : "expanded"
    if (target === "collapsed" && !NotchLogic.stripTakes(name)) return next
    const taken = []
    for (const each of NOTCH_ZONES) for (const pill of next[each]) taken.push(pill.id)
    const size = notchSize(name)
    next[target].push({ id: uniqueId("notch", taken),
                        items: [{ type: name, display: "full", size: "small",
                                  w: size.w, h: size.h, options: {} }] })
    return sanitizeNotch(next)
}

// How big an item sits, in grid steps. There is no ladder of three names: a
// corner is dragged and the size is whatever it lands on, bounded by the grid
// itself rather than by a vocabulary.
function setNotchItemSize(notch, id, w, h) {
    const next = copyNotch(notch)
    const place = notchZoneOf(next, id)
    if (!place) return next
    const item = next[place.zone][place.index].items[0]
    const least = notchMinSize(item.type)
    item.w = clamp(Math.round(num(w, item.w)), least.w, GRID_MAX_W)
    item.h = clamp(Math.round(num(h, item.h)), least.h, GRID_MAX_H)
    return sanitizeNotch(next)
}

// The big time and the long date used to be a header the overview always drew,
// above whatever the list said. They are an item now, so a notch stored before
// that gets one - once, at the front, where the header was.
function adoptNotchHeader(notch) {
    const next = copyNotch(notch)
    if (notchTypes(next, "expanded").indexOf("clock") >= 0) return next
    // The strip may already carry a clock of its own; ids are unique across
    // both zones, so the new one is numbered against everything that is there.
    const taken = []
    for (const zone of NOTCH_ZONES) for (const pill of next[zone]) taken.push(pill.id)
    next.expanded = notchList(["clock"], taken).concat(next.expanded)
    return sanitizeNotch(next)
}

// ---- the launcher -----------------------------------------------------------
// The fourth surface of tiles, and the last to become one. It had stacked
// blocks with two hand-written pairing rules - the mode switch riding in the
// search field's row, the categories standing beside the result list - on the
// reasoning that a free grid is one in which you can build yourself a result
// list two rows high. The grid won anyway, for the reason that decided it:
// the rest of the shell works like that, and a surface that does not is the
// odd one out. So the pairings are gone and the launcher is a grid like the
// control center and the dashboard, with its own catalogue.
//
// **Four columns, eight rows, and a row is an eighth of the card's height.**
// Everything else here uses a fixed row height and scrolls; the launcher
// cannot, because the result list has to reach the bottom of a window the user
// drags. A grid that scales with the card does both: the default is today's
// picture, and pulling the window bigger makes every block bigger with it.
const LAUNCHER = {
    strict: true,
    maxH: LauncherCatalogue.rows,
    maxW: LauncherCatalogue.columns,
    zone: "launcher",
    defaults: LauncherCatalogue.defaults,
    sizeOf: LauncherCatalogue.size,
    leastOf: LauncherCatalogue.minSize,
    // A ceiling per type under the grid's, the counterpart of `leastOf`: the
    // search field stops at one row (see the catalogue), and a file that
    // stored it taller loads at one, the row going to the result list.
    mostOf: LauncherCatalogue.maxSize,
    knows: LauncherCatalogue.isKnown,
    // The block that may not be taken off, and that a file without it gets
    // back (see sanitizeTiles).
    fixed: LauncherCatalogue.fixed
}

// ---- a surface of tiles in one zone ---------------------------------------
// The control center's tiles and the dashboard's cards are the same thing with
// a different catalogue: one zone, one tile per pill, each carrying its own
// grid size, on the same zone -> pill -> item shape as the bar. A flat list
// would have been shorter, but the shape is what lets the surfaces share
// sanitizeZones, their ids and their move/remove/add operations.
//
// Everything below takes a `kind`, which names the zone, the id prefix, what
// the surface starts with and where a type's starting size comes from. Two
// surfaces, one set of operations: the notch and the bar each grew their own
// copy before this existed, and a third would have been the third bug.
// A tile that is not in the list is simply not shown; the picker adds it back.
const QUICK = {
    zone: "quick",
    defaults: ["wifi", "bluetooth", "vpn", "dnd", "microphone", "fingerprint", "brightness",
               "battery", "media", "audio", "drives", "phone", "shortcuts"],
    sizeOf: QuickLogic.size,
    leastOf: QuickLogic.minSize,
    knows: QuickLogic.isKnown
}
const DASHBOARD = {
    zone: "dashboard",
    defaults: ["clock", "weather", "calendar", "events"],
    sizeOf: DashboardLogic.size,
    leastOf: DashboardLogic.minSize,
    knows: DashboardLogic.isKnown
}
// The lock screen's own surface. It sits outside the modes for the same
// reason the notch does: there is one lock screen, whatever a mode says about
// monitors; each profile keeps its own copy in its state, like the notch. Its login block is not in here - avatar, name
// and password field stay where they are, because the animation that carries
// them to the centre while you type is an anchor margin, and an arranged cell
// is an x and a y. Mixing the two is a whole afternoon.
const LOCK = {
    zone: "lock",
    defaults: ["clock", "date", "media"],
    sizeOf: LockCatalogue.size,
    leastOf: LockCatalogue.minSize,
    knows: LockCatalogue.isKnown
}

function tilePill(kind, type, id) {
    // A type the catalogue knows brings its own start size; anything else is a
    // widget the surface accepts, and the catalogue's fallback is what that
    // surface thinks a one-line readout is worth.
    const size = kind.sizeOf(type)
    return { id: id, items: [{ type: type, display: "full", size: "small",
                               w: size.w, h: size.h, options: {} }] }
}

function defaultTiles(kind) {
    return { [kind.zone]: kind.defaults.map((type, index) => tilePill(kind, type, kind.zone + "-" + (index + 1))) }
}

function sanitizeTiles(kind, surface) {
    if (!surface || typeof surface !== "object") return defaultTiles(kind)
    const zones = sanitizeZones(surface, [kind.zone], kind.maxH)
    // One tile per pill: anything the file smuggled in beyond the first is
    // dropped rather than silently shown twice. The height is clamped again
    // here because `sanitizeZones` clamps to the tallest cell *any* surface
    // allows - it cannot know which one this is - and each surface's own
    // ceiling is `kind.maxH`.
    // A surface that accepts desktop widgets cannot drop what its catalogue
    // does not know - the registry is not reachable from here, and dropping
    // them would take every widget off the panel on the first load. The
    // launcher takes no widgets, so for it an unknown type is a hand-edited
    // file and goes.
    const known = kind.strict ? zones[kind.zone].filter(pill => kind.knows(pill.items[0].type))
                              : zones[kind.zone]
    // The floor the editor applies is applied to the file as well, so a tile
    // written below its catalogue's minimum loads at the minimum rather than
    // at a size it only stops at once dragged - and the ceiling likewise, so
    // a search field stored two rows tall comes back one row tall.
    const tiles = known.map(pill => ({ id: pill.id, items: [lowerToMost(raiseToLeast(pill.items[0], tileMinSize(kind, pill.items[0].type)),
                                                                         tileMaxSize(kind, pill.items[0].type))] }))
    if (!tiles.length) return defaultTiles(kind)
    // A block the surface cannot do without - the launcher's search field -
    // goes back in front when a file lost it: `removeTile` refuses to take
    // it off, and a hand-edited file must not get past that refusal.
    if (kind.fixed && !tiles.some(pill => kind.fixed(pill.items[0].type))) {
        const taken = tiles.map(pill => pill.id)
        for (const type of kind.defaults.filter(kind.fixed).reverse()) {
            const id = uniqueId(kind.zone + "-" + type, taken)
            taken.push(id)
            tiles.unshift(tilePill(kind, type, id))
        }
    }
    return { [kind.zone]: tiles }
}

function tileList(kind, surface) {
    return surface && Array.isArray(surface[kind.zone]) ? surface[kind.zone] : []
}

// The tiles as the surface places them: the stored id, type and grid size.
function tileItems(kind, surface) {
    return tileList(kind, surface).map(pill => ({
        id: pill.id, type: pill.items[0].type, w: pill.items[0].w, h: pill.items[0].h
    }))
}

function tileTypes(kind, surface) {
    return tileList(kind, surface).map(pill => pill.items[0].type)
}

function copyTiles(kind, surface) {
    return sanitizeTiles(kind, JSON.parse(JSON.stringify(surface)))
}

function findTile(kind, surface, id) {
    return surface[kind.zone].findIndex(pill => pill.id === id)
}

// How big one tile sits. Same two axes as a notch item, same bounds - and the
// same floor, which is the catalogue's when it names one. Below its minimum a
// tile is not a smaller version of itself, so the grid refuses rather than
// handing back something that only clips.
function setTileSize(kind, surface, id, w, h) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    if (index < 0) return next
    const item = next[kind.zone][index].items[0]
    const least = tileMinSize(kind, item.type)
    const most = tileMaxSize(kind, item.type)
    item.w = clamp(Math.round(num(w, item.w)), least.w, most.w)
    item.h = clamp(Math.round(num(h, item.h)), least.h, most.h)
    return sanitizeTiles(kind, next)
}

function tileMinSize(kind, type) {
    return kind.leastOf ? kind.leastOf(type) : { w: 1, h: 1 }
}

// The largest cell one tile may be pulled to: the surface's grid, unless its
// catalogue names a lower ceiling for the type (`mostOf`; only the launcher's
// search field has one). A surface without `mostOf` stops at the grid, which
// is where it stopped before this existed.
function tileMaxSize(kind, type) {
    const grid = { w: kind.maxW || GRID_MAX_W, h: kind.maxH || GRID_MAX_H }
    const most = kind.mostOf ? kind.mostOf(type) : {}
    return { w: Math.min(grid.w, most.w || grid.w), h: Math.min(grid.h, most.h || grid.h) }
}

function lowerToMost(item, most) {
    item.w = Math.min(item.w, most.w)
    item.h = Math.min(item.h, most.h)
    return item
}

function moveTile(kind, surface, id, delta) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    const target = index + delta
    if (index < 0 || target < 0 || target >= next[kind.zone].length) return next
    const moved = next[kind.zone].splice(index, 1)[0]
    next[kind.zone].splice(target, 0, moved)
    return next
}

function moveTileTo(kind, surface, id, index) {
    const next = copyTiles(kind, surface)
    const from = findTile(kind, next, id)
    if (from < 0) return next
    const moved = next[kind.zone].splice(from, 1)[0]
    next[kind.zone].splice(Math.max(0, Math.min(next[kind.zone].length, index)), 0, moved)
    return next
}

function removeTile(kind, surface, id) {
    const next = copyTiles(kind, surface)
    const index = findTile(kind, next, id)
    if (index >= 0) next[kind.zone].splice(index, 1)
    return next
}

// A type neither the catalogue nor the caller knows is refused rather than
// given a cell. The pickers only ever offer known types, so this guards the
// file and the IPC: an unknown type used to take a place on the surface and
// draw nothing, because the switch that turns a type into content has no case
// for it.
//
// `alsoKnown` is how a surface accepts desktop widgets beside its own tiles.
// It is a callback rather than another table because the widget registry is a
// QML singleton and this file is a plain library - the same reason
// `materialize` takes one.
function addTile(kind, surface, type, alsoKnown) {
    const next = copyTiles(kind, surface)
    if (!type || tileTypes(kind, next).indexOf(type) >= 0) return next
    const known = (kind.knows && kind.knows(String(type)))
        || (alsoKnown && alsoKnown(String(type)) === true)
    if (!known) return next
    const taken = next[kind.zone].map(pill => pill.id)
    const id = uniqueId(kind.zone + "-" + (next[kind.zone].length + 1), taken)
    next[kind.zone].push(tilePill(kind, String(type), id))
    return next
}

// Every tile back to the size its type starts at. The control center's tiles
// were laid out by their content until it became a grid, and a file written in
// between carries the smallest cell there is for each of them - which is not
// what anybody chose, it is what a missing field defaults to. Run once,
// guarded by a marker in this same file.
function adoptTileSizes(kind, surface) {
    const next = copyTiles(kind, surface)
    for (const pill of next[kind.zone]) {
        const size = kind.sizeOf(pill.items[0].type)
        pill.items[0].w = size.w
        pill.items[0].h = size.h
    }
    return sanitizeTiles(kind, next)
}

// ---- the two surfaces, by name --------------------------------------------
// Thin wrappers so a call site reads as what it is working on rather than as
// a descriptor plus a generic verb.

// The launcher, on the same operations. `launcherAdd` refuses a type the
// catalogue does not know rather than taking widgets as well: the objection on
// the record is that a search surface is at heart its result list, and it is
// why pinned apps was the module that got built instead of a widget grid.
function defaultLauncher() { return defaultTiles(LAUNCHER) }
function sanitizeLauncher(surface) { return sanitizeTiles(LAUNCHER, surface) }
function launcherItems(surface) { return tileItems(LAUNCHER, surface) }
function launcherTypes(surface) { return tileTypes(LAUNCHER, surface) }
function moveLauncherBlockTo(surface, id, index) { return moveTileTo(LAUNCHER, surface, id, index) }
function setLauncherBlockSize(surface, id, w, h) { return setTileSize(LAUNCHER, surface, id, w, h) }
function addLauncherBlock(surface, type) { return addTile(LAUNCHER, surface, type) }
function launcherBlockMinSize(type) { return tileMinSize(LAUNCHER, type) }

// The search field is the one block that may not be taken off - see the
// catalogue for why - so this is `removeTile` with that one refusal in front.
function removeLauncherBlock(surface, id) {
    const found = findTile(LAUNCHER, surface, id)
    if (found >= 0 && LauncherCatalogue.fixed(tileList(LAUNCHER, surface)[found].items[0].type)) return copyTiles(LAUNCHER, surface)
    return removeTile(LAUNCHER, surface, id)
}

function defaultQuick() { return defaultTiles(QUICK) }
function sanitizeQuick(quick) { return sanitizeTiles(QUICK, quick) }
function quickItems(quick) { return tileItems(QUICK, quick) }
function quickTypes(quick) { return tileTypes(QUICK, quick) }
function setQuickTileSize(quick, id, w, h) { return setTileSize(QUICK, quick, id, w, h) }
function moveQuickTile(quick, id, delta) { return moveTile(QUICK, quick, id, delta) }
function moveQuickTileTo(quick, id, index) { return moveTileTo(QUICK, quick, id, index) }
function removeQuickTile(quick, id) { return removeTile(QUICK, quick, id) }
function addQuickTile(quick, type, alsoKnown) { return addTile(QUICK, quick, type, alsoKnown) }
function adoptQuickSizes(quick) { return adoptTileSizes(QUICK, quick) }

function defaultDashboard() { return defaultTiles(DASHBOARD) }
function sanitizeDashboard(dashboard) { return sanitizeTiles(DASHBOARD, dashboard) }
function dashboardItems(dashboard) { return tileItems(DASHBOARD, dashboard) }
function dashboardTypes(dashboard) { return tileTypes(DASHBOARD, dashboard) }
function setDashboardCardSize(dashboard, id, w, h) { return setTileSize(DASHBOARD, dashboard, id, w, h) }
function moveDashboardCardTo(dashboard, id, index) { return moveTileTo(DASHBOARD, dashboard, id, index) }
function removeDashboardCard(dashboard, id) { return removeTile(DASHBOARD, dashboard, id) }
function addDashboardCard(dashboard, type, alsoKnown) { return addTile(DASHBOARD, dashboard, type, alsoKnown) }

function defaultLock() { return defaultTiles(LOCK) }
function sanitizeLock(lock) { return sanitizeTiles(LOCK, lock) }
function lockItems(lock) { return tileItems(LOCK, lock) }
function lockTypes(lock) { return tileTypes(LOCK, lock) }
function setLockItemSize(lock, id, w, h) { return setTileSize(LOCK, lock, id, w, h) }
function moveLockItemTo(lock, id, index) { return moveTileTo(LOCK, lock, id, index) }
function removeLockItem(lock, id) { return removeTile(LOCK, lock, id) }
function addLockItem(lock, type) { return addTile(LOCK, lock, type) }

// ---- the dock ---------------------------------------------------------------
// The dock's zones (shell/dock/Dock.qml): the bar's zone -> pill -> item shape,
// so the bar's operations and the bar's editor serve it as well, plus the
// dock's own pinned apps. Outside the modes like the notch - one dock in all
// five - and kept in a profile's state. Its pill ids start with "dock-": the
// layout editor finds the bar's pills and the dock's in one table of
// rectangles (LayoutService.surfaceRects), and "pill-1" was both.
//
// Two item types are the dock's own: "apps" (the pinned and running apps)
// and "start" (a button for the launcher). Every bar widget may sit beside
// them.
//
// A pin is a desktop entry id, or one of the session's defaults, which the
// dock resolves when it draws: @files, @terminal, @browser (Settings >
// Default apps), and @settings, the shell's own Settings.
const DOCK_PIN_LIMIT = 12
const DOCK_TOKENS = ["@files", "@terminal", "@browser", "@settings"]

function dockPill(id, type, display) {
    return { id: id, items: [{ type: type, display: display || "full", options: {} }] }
}

const DOCK_DEFAULT_PINS = ["@files", "@terminal", "@settings", "@browser"]

// Sanitized like a stored one, so a default written and read back is the
// same text.
function defaultDock() {
    return sanitizeDock({ left: [], center: [dockPill("dock-apps", "apps")], right: [], pins: DOCK_DEFAULT_PINS })
}

// A pin as stored, or "" for none. An id is whatever the entry's file is
// called, and that is not always a tidy name: Citrix calls its subscribed
// apps "Citrix_subscribed_XenApp 7.x.RDS-Name $S101-255", spaces and '$'
// included (launch-app.sh escapes a unit name itself). So only what no
// desktop id holds is refused: nothing, a control character, a slash, an @
// name that is not one of the tokens - and a leading dash, which a command
// line would read as an option.
const DOCK_PIN_MAX_LENGTH = 255
function dockPinName(entry) {
    const pin = typeof entry === "string" ? entry.trim().replace(/\.desktop$/, "") : ""
    if (DOCK_TOKENS.indexOf(pin) >= 0) return pin
    if (!pin.length || pin.length > DOCK_PIN_MAX_LENGTH || /^[@-]/.test(pin) || /[\u0000-\u001f\u007f/]/.test(pin)) return ""
    return pin
}

function sanitizeDockPins(list) {
    const result = []
    for (const entry of Array.isArray(list) ? list : []) {
        const pin = dockPinName(entry)
        if (pin.length && result.indexOf(pin) < 0) result.push(pin)
        if (result.length >= DOCK_PIN_LIMIT) break
    }
    return result
}

// In two passes: every pill whose id starts with "dock-" keeps it, and only
// the rest - a pill one of the bar's operations has just made, named in the
// bar's own way ("pill-3", see dockZoneOp) - is named around them. In one
// pass, in zone order, a new pill in an earlier zone could take the id of an
// untouched one further on, which was renamed instead: the editor then
// selected the wrong pill, and its Remove acted on that one.
function sanitizeDock(dock) {
    if (!dock || typeof dock !== "object" || Array.isArray(dock)) return defaultDock()
    const zones = sanitizeZones(dock, ZONES)
    const taken = []
    const kept = {}
    for (const zone of ZONES)
        zones[zone].forEach((pill, index) => {
            if (pill.id.indexOf("dock-") !== 0 || taken.indexOf(pill.id) >= 0) return
            taken.push(pill.id)
            kept[zone + "/" + index] = pill.id
        })
    const result = { pins: Array.isArray(dock.pins) ? sanitizeDockPins(dock.pins) : DOCK_DEFAULT_PINS.slice() }
    for (const zone of ZONES) {
        result[zone] = zones[zone].map((pill, index) => {
            let id = kept[zone + "/" + index]
            if (!id) {
                const wanted = pill.id.indexOf("dock-") === 0 ? "dock-pill" : "dock-" + pill.id
                id = taken.indexOf(wanted) < 0 ? wanted : uniqueId("dock-pill", taken)
                taken.push(id)
            }
            return { id: id, items: pill.items }
        })
    }
    return result
}

function copyDock(dock) {
    return sanitizeDock(JSON.parse(JSON.stringify(dock || defaultDock())))
}

// A bar operation (addPill, movePillTo, removeItem …) on the dock's zones:
// the same function, handed the zones as a bar, and the pins kept.
function dockZoneOp(dock, operation, args) {
    const current = sanitizeDock(dock)
    const asBar = sanitizeBar({ left: current.left, center: current.center, right: current.right })
    const result = operation.apply(null, [asBar].concat(Array.prototype.slice.call(args || [])))
    return sanitizeDock({ left: result.left, center: result.center, right: result.right, pins: current.pins })
}

// The pins: added at the end or at a place, moved, taken out. Never more than
// DOCK_PIN_LIMIT; a pin that is there already is moved rather than doubled.
function dockPinAt(dock, pin, index) {
    const next = copyDock(dock)
    const name = dockPinName(pin)
    if (!name) return next
    const list = next.pins.filter(item => item !== name)
    if (list.length >= DOCK_PIN_LIMIT) return next
    const at = index === undefined || index === null ? list.length : Math.max(0, Math.min(list.length, Math.round(Number(index) || 0)))
    list.splice(at, 0, name)
    next.pins = list
    return next
}
function dockUnpin(dock, pin) {
    const next = copyDock(dock)
    const name = String(pin || "").replace(/\.desktop$/, "")
    next.pins = next.pins.filter(item => item !== name)
    return next
}
// Whether any pill on the dock holds a widget of this type (the start button:
// the start menu is built only for a dock that has one).
function dockHasType(dock, type) {
    if (!dock || typeof dock !== "object") return false
    return ["left", "center", "right"].some(zone => Array.isArray(dock[zone]) && dock[zone].some(pill =>
        pill && Array.isArray(pill.items) && pill.items.some(item => item && item.type === type)))
}

function dockPinned(dock, pin) {
    return copyDock(dock).pins.indexOf(String(pin || "").replace(/\.desktop$/, "")) >= 0
}

// Dock presets (config/dock-presets/*.json): its options in settings.json
// (dock.*) and its layout here, applied together as one step.
const DOCK_PRESET_OPTIONS = ["visibility", "position", "span", "iconSize", "margin", "showRunning", "magnification"]

// The dock a preset makes of the one there is: the preset's zones, and its
// pins only where the pins are still the defaults or none at all. Apps the
// user pinned (or put in an order of their own) are theirs; a preset is how
// the dock looks, and both shipped ones say "your apps".
function dockFromPreset(current, layout) {
    const next = copyDock(layout)
    const pins = copyDock(current).pins
    const own = pins.length > 0 && JSON.stringify(pins) !== JSON.stringify(DOCK_DEFAULT_PINS)
    if (own) next.pins = pins
    return next
}
function sanitizeDockPreset(preset) {
    if (!preset || typeof preset !== "object") return null
    const label = typeof preset.label === "string" ? preset.label.trim().slice(0, 40) : ""
    if (!label.length) return null
    const options = {}
    const source = preset.options && typeof preset.options === "object" ? preset.options : {}
    for (const key of DOCK_PRESET_OPTIONS)
        if (source[key] !== undefined && source[key] !== null && typeof source[key] !== "object") options[key] = source[key]
    return { id: typeof preset.id === "string" && preset.id.length ? preset.id : Profile.slug(label), label: label,
             description: typeof preset.description === "string" ? preset.description.slice(0, PRESET_DESCRIPTION_MAX) : "",
             icon: typeof preset.icon === "string" ? preset.icon.slice(0, 8) : "",
             layout: sanitizeDock(preset.layout), options: options }
}

function sanitizeBar(bar) {
    if (!bar || typeof bar !== "object") return defaultBar()
    const result = {
        reserve: bar.reserve === undefined ? true : Boolean(bar.reserve),
        fullscreen: oneOf(bar.fullscreen, FULLSCREEN, "hide"),
        scale: clamp(num(bar.scale, 1), SCALE_MIN, 1.5),
        style: BarLogic.style(bar.style),
        position: BarLogic.position(bar.position),
        // Sanitizing is total, so a file written before there was an edge
        // simply gets "top" when it is read. No version bump, no migration.
        edge: BarLogic.edge(bar.edge),
        // Where a panel and where a notification open along the bar. Both
        // default to "widget", which is the behaviour every bar had before
        // there was a choice, so a file written without them reads as one that
        // asked for what it already had.
        panelSpot: BarLogic.spot(bar.panelSpot),
        notificationSpot: BarLogic.spot(bar.notificationSpot),
        // Which screens carry the bar. **Empty means every screen**, which is
        // what every bar did before there was a choice - so a file written
        // without it reads as one that asked for what it already had, and a
        // monitor plugged in later is included rather than left bare.
        screens: Array.isArray(bar.screens)
            ? bar.screens.filter(name => typeof name === "string" && name.length) : []
    }
    const zones = sanitizeZones(bar, ZONES)
    for (const zone of ZONES) result[zone] = zones[zone]
    return result
}

function barPillIds(bar) {
    return ZONES.reduce((ids, zone) => ids.concat(bar[zone].map(pill => pill.id)), [])
}

// { zone, index } of a pill, or null.
function findPill(bar, pillId) {
    for (const zone of ZONES) {
        const index = bar[zone].findIndex(pill => pill.id === pillId)
        if (index >= 0) return { zone: zone, index: index }
    }
    return null
}

function copyBar(bar) {
    return sanitizeBar(JSON.parse(JSON.stringify(bar)))
}

// All operations return a new, sanitized bar and never mutate the input.
function addPill(bar, zone, type, display) {
    const next = copyBar(bar)
    if (ZONES.indexOf(zone) < 0 || !type) return next
    const id = uniqueId("pill-" + (barPillIds(next).length + 1), barPillIds(next))
    next[zone].push({ id: id, items: [{ type: String(type), display: oneOf(display, DISPLAYS, "full"), options: {} }] })
    return sanitizeBar(next)
}

function addItem(bar, pillId, type, display) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !type) return next
    next[place.zone][place.index].items.push({ type: String(type), display: oneOf(display, DISPLAYS, "full"), options: {} })
    return sanitizeBar(next)
}

function removeItem(bar, pillId, itemIndex) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    next[place.zone][place.index].items.splice(itemIndex, 1)
    return sanitizeBar(next)
}

function moveItem(bar, pillId, itemIndex, delta) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    const items = next[place.zone][place.index].items
    const target = itemIndex + delta
    if (itemIndex < 0 || itemIndex >= items.length || target < 0 || target >= items.length) return next
    const moved = items.splice(itemIndex, 1)[0]
    items.splice(target, 0, moved)
    return next
}

function setItemDisplay(bar, pillId, itemIndex, display) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !next[place.zone][place.index].items[itemIndex]) return next
    next[place.zone][place.index].items[itemIndex].display = oneOf(display, DISPLAYS, "full")
    return next
}

function setItemSize(bar, pillId, itemIndex, size) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !next[place.zone][place.index].items[itemIndex]) return next
    next[place.zone][place.index].items[itemIndex].size = oneOf(size, SIZES, "small")
    return next
}

// Move a pill within its zone (delta) and across zone borders: moving past
// the end of a zone places it at the start of the next zone and vice versa.
function movePill(bar, pillId, delta) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || !delta) return next
    const list = next[place.zone]
    const target = place.index + delta
    if (target >= 0 && target < list.length) {
        const moved = list.splice(place.index, 1)[0]
        list.splice(target, 0, moved)
        return next
    }
    const zoneIndex = ZONES.indexOf(place.zone) + (delta > 0 ? 1 : -1)
    if (zoneIndex < 0 || zoneIndex >= ZONES.length) return next
    const moved = list.splice(place.index, 1)[0]
    if (delta > 0) next[ZONES[zoneIndex]].unshift(moved)
    else next[ZONES[zoneIndex]].push(moved)
    return next
}

// Move a pill to an exact place (editor drag and drop): `index` counts the
// target zone without the pill itself and is clamped to its ends.
function movePillTo(bar, pillId, zone, index) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || ZONES.indexOf(zone) < 0) return next
    const moved = next[place.zone].splice(place.index, 1)[0]
    const list = next[zone]
    list.splice(clamp(Math.round(num(index, list.length)), 0, list.length), 0, moved)
    return next
}

// Split one item out into its own pill right after the original pill.
function splitItem(bar, pillId, itemIndex) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place) return next
    const pill = next[place.zone][place.index]
    if (pill.items.length < 2 || !pill.items[itemIndex]) return next
    const item = pill.items.splice(itemIndex, 1)[0]
    const id = uniqueId("pill-" + (barPillIds(next).length + 1), barPillIds(next))
    next[place.zone].splice(place.index + 1, 0, { id: id, items: [item] })
    return next
}

// Merge a pill into the following pill of the same zone.
function mergeWithNext(bar, pillId) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (!place || place.index + 1 >= next[place.zone].length) return next
    const list = next[place.zone]
    list[place.index].items = list[place.index].items.concat(list[place.index + 1].items)
    list.splice(place.index + 1, 1)
    return next
}

function removePill(bar, pillId) {
    const next = copyBar(bar)
    const place = findPill(next, pillId)
    if (place) next[place.zone].splice(place.index, 1)
    return next
}
