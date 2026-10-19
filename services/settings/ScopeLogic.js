.pragma library
.import "../profile/ProfileLogic.js" as Profile

// Where a setting is kept, said where it is changed. A setting belongs to the
// profile unless ProfileLogic names it the mode's (MODE_SCOPED) or the
// machine's (GLOBAL_SETTINGS); both lists are read from there, so a setting
// moved from one to the other changes these words with it. The lid action,
// the idle times and fingerprint unlock had been the machine's for a while
// when Settings > Profiles still named only the weather place, the keyboard
// layout and the displays, and a user who set them in one profile expected
// the other to keep its own.

// The machine's settings in words, in the order they are read. An entry
// covers GLOBAL_SETTINGS entries equal to it or inside it ("weather" holds
// "weather.lat"); the first that covers one names it.
var MACHINE_LABELS = [
    { entries: ["weather"], label: "the weather place" },
    { entries: ["input.kbLayout", "input.kbVariant"], label: "the keyboard layout" },
    { entries: ["input.sensitivity", "input.accelProfile", "input.mouseNaturalScroll", "input.touchpadNaturalScroll",
                "input.touchpadScrollFactor", "input.tapToClick", "input.disableWhileTyping"],
      label: "the mouse and the touchpad" },
    { entries: ["display"], label: "the displays" },
    { entries: ["power"], label: "power and the lid" },
    { entries: ["lock.fingerprint"], label: "fingerprint unlock" },
    { entries: ["dock.screens", "notch.screens"], label: "which screens show the dock and the notch" },
    { entries: ["calendar"], label: "the calendars shown" },
    { entries: ["clipboard"], label: "the clipboard history" },
    { entries: ["autostart"], label: "what starts at login" },
    { entries: ["updates"], label: "the update checks" },
    { entries: ["drives"], label: "what drives and a full disk say" },
    { entries: ["terminal.alacrittyDaemon"], label: "how Alacritty windows start" },
    { entries: ["notifications.keepHistory"], label: "the notifications kept across restarts" },
    { entries: ["desktop.worldClocks"], label: "the world clock's places" },
    { entries: ["commandWidgets"], label: "the command widgets" },
    { entries: ["assistant"], label: "the assistant" },
    { entries: ["sharePicker"], label: "the share picker" }
]
// What nobody sets as a choice, so the sentence leaves it out: versions,
// one-shot markers and the tour, and what the shell remembers by itself (the
// colours picked, the folders used, where the Settings window was dragged).
var INTERNAL = ["configVersion", "notch.headerAdopted", "desktop.quickSizesAdopted", "onboarding",
                "colorPicker.history", "wallpaper.recentFolders", "desktop.settingsMoveX", "desktop.settingsMoveY"]

function covers(entry, path) {
    return path === entry || path.indexOf(entry + ".") === 0
}

// The label for one GLOBAL_SETTINGS entry, "" for bookkeeping, null for one
// nobody has put into words yet (a test asks for every entry).
function labelFor(entry) {
    const text = String(entry || "")
    if (INTERNAL.indexOf(text) >= 0) return ""
    const found = MACHINE_LABELS.find(item => item.entries.some(name => covers(name, text)))
    return found ? found.label : null
}

// "a", "a and b", "a, b and c".
function sentence(parts) {
    const list = (parts || []).filter(part => part && part.length)
    if (list.length <= 1) return list.join("")
    return list.slice(0, -1).join(", ") + " and " + list[list.length - 1]
}

// The machine's settings as a phrase, from `globals` (GLOBAL_SETTINGS unless
// a test hands its own), each label once.
function machineSettings(globals) {
    const labels = []
    for (const entry of globals || Profile.GLOBAL_SETTINGS) {
        const label = labelFor(entry)
        if (label && labels.indexOf(label) < 0) labels.push(label)
    }
    // In the table's order rather than the list's, so the words read the
    // same whichever order the list grows in.
    const order = MACHINE_LABELS.map(item => item.label)
    return sentence(labels.sort((a, b) => order.indexOf(a) - order.indexOf(b)))
}

// The note under a section or beside a control for the setting at `path`:
// the mode's own (named by `modeLabel`), the same in every profile, or ""
// for a setting that simply belongs to the profile, which is what every
// setting does unless it says otherwise.
function note(path, modeLabel) {
    const text = String(path || "")
    if (!text.length) return ""
    if (Profile.isModeScoped(text)) {
        const name = String(modeLabel || "")
        return name.length ? "Kept for this mode (" + name + ")" : "Kept for this mode"
    }
    if (Profile.isGlobalSetting(text)) return "The same in every profile"
    return ""
}
