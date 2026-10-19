.pragma library

// Two levels, and the words for them.
//
// A **mode** is what the desktop is set to right now: minimal, work, gaming,
// laptop or docked. A **profile** holds its own five modes. The layout file
// called the five "profiles" until v3 and the user never did - they are modes,
// and this file is where both words are defined.
//
// What the mode key does, and what it does to the automatic mode:
//
// The decision, taken with the user: cycling by hand turns the automatic
// switching **off**, because otherwise the choice silently reverts the next
// time a monitor is plugged in - AdaptiveService watches the suggestion and
// the flag, never the active mode, so a mode chosen by hand sticks right
// up until it does not. A delayed surprise is worse than an immediate one.
// Landing back on one of the two modes the automatic switching itself picks
// turns it on again, so the automatic behaviour is reachable from the key
// rather than only from Settings, and the OSD says so either way.
//
// It is a function with a test rather than three lines at the call site
// because "what does the key do from each of five states, twice round" is
// exactly what a test is for and exactly what a nested session cannot show.

// The two modes AdaptiveService chooses between on its own. They may not be
// renamed or removed anywhere, because this list points at them by name.
var AUTOMATIC = ["laptop", "docked"]

// The five modes every profile has, in the order the key cycles through them.
var MODE_NAMES = ["minimal", "work", "gaming", "laptop", "docked"]

// ---- which settings belong to a mode ---------------------------------------
// The one place that says it. A setting listed here is stored per mode and
// re-applied when the mode is entered; everything else is one choice for the
// whole session.
//
// They are all in the `appearance` group, and that is not a coincidence: what
// differs between a laptop on battery and a docked desktop is how heavy the
// interface is allowed to look, not which theme or which font it uses. So the
// list is leaf names inside that one group, and `modeScopedPath` makes the
// full setting path.
//
// Deliberately **not** here: theme, accent, fonts, cursor and locale. Those
// describe the session, not the mode, and a user who changes the accent in one
// mode means it for all of them.
var MODE_SCOPED_GROUP = "appearance"
var MODE_SCOPED = ["blurStrength", "panelOpacity", "animationMode", "animationSpeed",
                   "windowRadius", "shellRadius", "borderEnabled", "borderSize",
                   "gapsIn", "gapsOut"]

function modeScopedPath(leaf) {
    return MODE_SCOPED_GROUP + "." + String(leaf || "")
}

// The leaf a full setting path names, or "" when the path is not mode-scoped.
function modeScopedLeaf(path) {
    const text = String(path || "")
    const prefix = MODE_SCOPED_GROUP + "."
    if (text.indexOf(prefix) !== 0) return ""
    const leaf = text.slice(prefix.length)
    return MODE_SCOPED.indexOf(leaf) >= 0 ? leaf : ""
}

function isModeScoped(path) {
    return modeScopedLeaf(path).length > 0
}

// ---- cycling ---------------------------------------------------------------

function names(list) {
    return (Array.isArray(list) ? list : []).filter(name => typeof name === "string" && name.length)
}

function nextIn(current, list) {
    const all = names(list)
    if (!all.length) return ""
    // An unknown current entry starts the cycle at the beginning rather than
    // going nowhere: indexOf gives -1, and -1 + 1 is the first.
    return all[(all.indexOf(String(current || "")) + 1) % all.length]
}

function nextMode(current, list) {
    return nextIn(current, list)
}

// The profile key cycles the level above. It has no automatic half: nothing
// switches a profile on its own, so there is no flag to settle.
function nextProfile(current, list) {
    return nextIn(current, list)
}

// Whether automatic switching should be on once this mode is chosen.
function autoAfter(mode) {
    return AUTOMATIC.indexOf(String(mode || "")) >= 0
}

// Everything the mode key does, from what it can see. `null` when there is
// nothing to cycle through, so the caller can leave the OSD alone.
function cycleMode(current, list, wasAuto) {
    const mode = nextMode(current, list)
    if (!mode.length) return null
    const auto = autoAfter(mode)
    return { mode: mode, auto: auto, autoChanged: auto !== Boolean(wasAuto) }
}

// What the OSD says. The automatic half only when the key changed it: a line
// that says the same thing every time is noise, which is the note the user
// made about the arrange row. The same for Do Not Disturb (`dnd`, from
// dndChange): a mode that turns it on says so, and so does leaving it, since
// no strip shows a bell and notifications going quiet - or coming back - is
// otherwise something only their absence tells.
function osdText(label, step, dnd) {
    const parts = [String(label || "")]
    if (step && step.autoChanged) parts.push("automatic " + (step.auto ? "on" : "off"))
    if (dnd && dnd.dndOn) parts.push("Do Not Disturb")
    else if (dnd && dnd.dndOff) parts.push("notifications back")
    return parts.join(" · ")
}

// What a switch into `mode` did to Do Not Disturb, from NotificationService's
// `{ active, by }` before and after it: on by that mode (it found it off, or
// took it over from the mode left), or off with the mode that owned it. The
// user's own Do Not Disturb is neither - a switch does not touch it.
function dndChange(before, after, mode) {
    const was = before || {}
    const now = after || {}
    const dndOn = now.active === true && String(now.by || "") === String(mode || "") && String(mode || "").length > 0
        && !(was.active === true && was.by === now.by)
    const dndOff = was.active === true && String(was.by || "").length > 0 && now.active !== true
    return { dndOn: dndOn, dndOff: dndOff }
}

// A mode's own name and glyph. Both were written out at each call site; the
// glyphs describe what a mode is for, so they live here rather than in Icons,
// which names actions.
function label(name, templates) {
    const key = String(name || "")
    const template = templates && templates[key] ? templates[key] : null
    return template && template.label ? template.label : key
}

// A profile is a set of modes, not one of them, so it gets a glyph of its own
// rather than borrowing whichever mode happens to be active.
function profileIcon() {
    return "\u{f05d2}" // Icons.profile
}

function icon(name) {
    switch (String(name || "")) {
    case "gaming": return "󰊴"
    case "laptop": return "󰌢"
    case "docked": return "󰍹"
    case "work": return "󰃖"
    }
    return "󰥔"
}

// ---- naming a profile ------------------------------------------------------
// A profile's id is what the layout file and the IPC use; its label is what the
// user typed. The id is derived from the label so `buchhwin profile set work`
// is guessable, and made unique so two profiles called "Work" can both exist.

function slug(text) {
    const cleaned = String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return cleaned.length ? cleaned : "profile"
}

function uniqueName(text, taken) {
    const list = names(taken)
    const base = slug(text)
    if (list.indexOf(base) < 0) return base
    let index = 2
    while (list.indexOf(base + "-" + index) >= 0) index += 1
    return base + "-" + index
}

// ---- which settings belong to a profile --------------------------------------
// A profile keeps everything the user sets (LayoutService, `state`): its five
// modes, the notch, the lock screen and every setting - except the ones below,
// which describe this machine or this person rather than a look, and are one
// value whatever profile is in use. The one place that says it; the export
// (scripts/profile-export.py, DROP) leaves out at least these, and a test
// holds the two together. An entry is a setting or a whole group.
//
// - settings.json's own version and the one-shot markers: they say a
//   migration has run on *this* machine's files, and a marker carried over
//   from another state either repeats a migration or skips one;
// - the onboarding tour, which is seen once per machine;
// - where this machine is: the weather place, its coordinates, and whether
//   the shell may ask ipinfo.io for them - a privacy choice that goes with
//   the place rather than with a look;
// - this person's calendars and the histories (colours picked, folders used);
// - the screens and the keyboard: X11's scale belongs to the monitors, the
//   layout to the keys printed on them;
// - where the Settings window was dragged to: restored by a switch, it would
//   move the very window the switch was made from;
// - the hardware's own answers (the user's decision): what the lid does,
//   when the screen goes off and the machine sleeps, the battery's warning
//   level and whether the lock screen asks the fingerprint reader. They
//   follow the battery and the reader this machine has, and a profile that
//   carried them set a desktop's lid action on a laptop. A state stored
//   before this still names them; the sanitizer drops them on the next read;
// - the pointer devices, like the keyboard's layout: the same touchpad acts
//   the same whatever the profile (how fast the keys repeat stays a taste
//   and the profile's);
// - the clipboard's history, a privacy choice like asking ipinfo.io: one who
//   turned it off because they copy passwords must not have a profile switch
//   turn the recorders on again;
// - what the login starts (autostart: this machine's apps, its XDG entries),
//   how the machine looks for updates and what a new drive does;
// - whether new Alacritty windows come from one running Alacritty: a way of
//   running the terminal, not a look of it;
// - which screens show the dock and the notch, like the displays.
var GLOBAL_SETTINGS = ["configVersion", "notch.headerAdopted", "desktop.quickSizesAdopted",
                       "onboarding",
                       "weather.locationName", "weather.lat", "weather.lon", "weather.autoLocate",
                       "calendar.hiddenCalendars", "calendar.newEventCalendar",
                       "colorPicker.history", "wallpaper.recentFolders",
                       "display", "input.kbLayout", "input.kbVariant",
                       "input.sensitivity", "input.accelProfile", "input.mouseNaturalScroll",
                       "input.touchpadNaturalScroll", "input.touchpadScrollFactor", "input.tapToClick",
                       "input.disableWhileTyping",
                       "desktop.settingsMoveX", "desktop.settingsMoveY",
                       "power", "lock.fingerprint", "dock.screens", "notch.screens",
                       "clipboard", "autostart", "updates", "drives", "terminal.alacrittyDaemon"]

function isGlobalSetting(path) {
    const text = String(path || "")
    return GLOBAL_SETTINGS.some(entry => text === entry || text.indexOf(entry + ".") === 0)
}

// What a profile keeps and a switch restores: neither global nor one of the
// leaves a mode owns. Those belong to the five modes, which carry their own
// `appearance` and apply it themselves (LayoutService.applyModeSettings);
// written by a profile as well, the active mode would take the values over
// through `settingChanged` and the other four would not, which is the leak
// MODE_SCOPED exists to prevent.
function isProfileSetting(path) {
    return String(path || "").length > 0 && !isModeScoped(path) && !isGlobalSetting(path)
}

// ---- a profile's settings, and a built-in profile's ---------------------------
// A profile's stored state and a profile the repository ships
// (config/builtin-profiles/<id>/profile.json) both carry settings.json's
// groups as a tree. Applying one writes them as leaf paths - every one
// SettingsService knows - and only the ones `isProfileSetting` lets through.

// "~/..." back to a path under this home. The export writes paths under the
// home directory that way so the repository holds no user name, and the
// stored form before the export was the absolute one - which is also the form
// the login theme's installer reads with jq, unexpanded.
function expandHome(value, home) {
    if (typeof value !== "string" || !home) return value
    if (value === "~") return String(home)
    return value.indexOf("~/") === 0 ? String(home) + value.slice(1) : value
}

// { "appearance.accent": "#50e2cb", ... } from the nested groups. Primitive
// leaves only: settings.json cannot hold a list (see LayoutLogic), so an array
// in the tree is something this version would reject anyway.
function settingLeaves(tree, home) {
    const result = {}
    const walk = (node, prefix) => {
        for (const key of Object.keys(node)) {
            const path = prefix + key
            const value = node[key]
            if (value !== null && typeof value === "object") {
                if (!Array.isArray(value)) walk(value, path + ".")
                continue
            }
            if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") continue
            if (!isProfileSetting(path)) continue
            result[path] = expandHome(value, home)
        }
    }
    if (tree && typeof tree === "object" && !Array.isArray(tree)) walk(tree, "")
    return result
}

// What a profile is entered with: every setting a profile owns, the ones its
// state (or a shipped profile) names as named and every other one at its
// default (`defaults`: settingLeaves of SettingsService.defaults). A state
// stored before a setting existed - every state from before the dock - used
// to leave that setting as it was in the profile left, so the dock switched
// on in one profile came along into the other and was stored there on the
// next switch (17.10.). A profile's settings are its own now: what it does
// not name is the default, never the other profile's.
function completeLeaves(leaves, defaults) {
    return Object.assign({}, defaults || {}, leaves || {})
}

// The same leaves as a tree again, the form a profile's state keeps them in:
// settings.json's own shape, so the file stays readable next to it.
function profileSettings(tree, home) {
    const leaves = settingLeaves(tree, home)
    const result = {}
    for (const path of Object.keys(leaves)) {
        const parts = path.split(".")
        let node = result
        for (let i = 0; i < parts.length - 1; ++i) {
            if (!node[parts[i]] || typeof node[parts[i]] !== "object") node[parts[i]] = {}
            node = node[parts[i]]
        }
        node[parts[parts.length - 1]] = leaves[path]
    }
    return result
}
