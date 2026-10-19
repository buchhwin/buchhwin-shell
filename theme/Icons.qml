pragma Singleton
import Quickshell

// Names for the glyphs that mean an *action* or a *direction*, so the same
// meaning cannot end up with two glyphs again: "remove" was once a close cross
// in one half of a file and a trash can in the other. Icons that describe data
// - a weather condition, a battery level, a volume - stay with the service that
// knows what they describe.
Singleton {
    // Doing something
    readonly property string add: "󰐕"
    readonly property string remove: "󰆴"          // deletes for good
    readonly property string close: "󰅖"           // closes or dismisses, never deletes
    readonly property string undo: "󰕌"
    readonly property string reset: "󰑓"
    readonly property string refresh: "󰑐"
    readonly property string copy: "󰅌"
    readonly property string search: "󰍉"
    // Outlined, as the power glyph beside it in every footer and header is
    // (the start menu's, the control center's): a filled cog and padlock
    // next to a thin power ring were three weights in one row.
    readonly property string settings: "󰢻"
    // Settings as an app, not as a button: the filled cog on its accent tile
    // on the dock and in the start menu, where it stands among app icons.
    readonly property string settingsApp: "󰒓"
    readonly property string location: "󰍎"
    readonly property string folder: "󰉋"
    // Arranging tiles, cards and widgets: the 2x2 grid of the arrange button
    // in the control center's and the launcher's header. (It was `edit`,
    // which also stood for renaming and changing things; those are `modify`.)
    // Outlined, like the cog and the power ring it stands beside in those
    // headers: the filled squares were the one solid glyph in the row.
    readonly property string arrange: "\u{f11d9}"
    // Changing something that is already there - renaming a preset, editing
    // an event, another folder or wallpaper: a pencil. The grid stood for
    // these too and read as "layout" there.
    readonly property string modify: "󰏫"
    // Showing a password and hiding it again: the open eye and the closed one.
    readonly property string reveal: "󰈈"
    readonly property string conceal: "󰈉"
    // Snapping to the grid in the layout editor. Its own glyph: the toolbar
    // already shows `arrange` on the mode switch beside it, and one glyph for
    // two buttons in one row read as one button twice.
    readonly property string grid: "󰋁"

    // Playing something. The media popup, the media card, the lock screen and
    // the phone page all drew the same four glyphs.
    readonly property string play: "󰐊"
    readonly property string pause: "󰏤"
    readonly property string previous: "󰒮"
    readonly property string next: "󰒭"

    // Saying something
    readonly property string check: "󰄬"
    readonly property string warning: "󰀦"
    readonly property string busy: "󰔟"
    // The small mark after a name that has more to say. It never acts - it is
    // a place to rest the pointer, not a button - so it gets the outlined
    // glyph rather than the filled one.
    readonly property string info: "󰋼"

    // Going somewhere
    readonly property string back: "󰅁"
    readonly property string forward: "󰅂"         // one more page of this panel
    readonly property string collapse: "󰅀"
    readonly property string raise: "\u{f0143}"        // the other way from collapse
    readonly property string leavesPanel: "󰏌"     // opens Settings instead

    // Things. A window that stands for any window (no preview yet, none
    // open, the per-window transparency row): the switcher and the overview
    // drew two different ones and Settings > Appearance a third. The
    // active-window widget's glyph is data (the window that is open) and
    // stays with the registry.
    readonly property string window: "󰖲"
    // The launcher's own: its "All" category, and the dock's start button.
    readonly property string apps: "󰀻"
    // The dock: its Settings page, its OSD line. A row of apps on a base.
    readonly property string dock: "\u{f1888}"
    // Pinning an app to the dock and the launcher.
    readonly property string pin: "󰐃"
    readonly property string unpin: "󰐄"

    // Modes and states with a switch of their own. One meaning, one glyph -
    // and the other way round: the moon stood for the dark theme, for Night
    // Light and for Do Not Disturb until the morning at once, with Focus's
    // crescent beside it, and the apps grid for every profile. The moon is
    // left to the dark theme (and to a clear night in the forecast, which is
    // the weather's own glyph and why it has no name here).
    // A lamp with a moon: the warm screen at night.
    readonly property string nightLight: "\u{f1a4c}"
    // Quiet until the sun is up: Do Not Disturb until tomorrow morning.
    readonly property string untilMorning: "\u{f059c}"
    // Focus mode: a viewfinder's centre, nothing else around it.
    readonly property string focus: "\u{f02f1}"
    // A profile: a card that says whose setup this is. The cog is Settings'.
    readonly property string profile: "\u{f05d2}"
    // What starts with the session.
    readonly property string autostart: "\u{f14de}"

    // Leaving the session, and what is locked: the power menu, the lock
    // screen's buttons, the launcher's commands and the start menu drew these
    // five each on their own. `lock` is also the padlock on a secured network
    // or an encrypted drive - the same thing, shut. Outlined like `settings`
    // and `poweroff`, the line glyph they sit beside; `unlock` is its open
    // twin (a phone to unlock).
    readonly property string lock: "󰍁"
    readonly property string unlock: "󰍀"
    // A crescent drawn in a line, like the padlock, the door and the power
    // ring around it in the session menu; mdi has only a filled moon for
    // sleeping, so this one is Font Awesome's, which the font carries too.
    readonly property string suspend: "\u{f186}"
    readonly property string logout: "󰍃"
    readonly property string reboot: "󰜉"
    readonly property string poweroff: "󰐥"
}
