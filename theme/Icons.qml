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
    readonly property string settings: "󰒓"
    readonly property string folder: "󰉋"
    readonly property string edit: "󰕰"

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
}
