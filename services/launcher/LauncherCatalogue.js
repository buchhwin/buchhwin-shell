.pragma library
.import "../arrange/FitLogic.js" as Fit

// The blocks the launcher can show, for the picker and for the labels in its
// edit mode. The blocks themselves live in shell/launcher/Launcher.qml; this
// is only what they are called and how big they start.
//
// **Four columns and up to eight rows**, and a row is a share of the card's
// height rather than a fixed number of pixels: the result list has to fill the
// window, and a grid with a fixed row height cannot do that. Pull the window
// bigger and every block grows with it; take a row off and the rest share it
// (Launcher.qml's `gridRows`). Eight is the ceiling a cell may be pulled to.
//
// The starting sizes below are today's picture exactly - the search field with
// the mode switch beside it, the pinned row under them, the categories down
// the left of the results:
//
//   +-----------------------+-----+
//   | search 3x1            |modes|
//   +-----------------------+-----+
//   | pinned 4x1                  |
//   +-----+-----------------------+
//   | cat |  results 3x6          |
//   | 1x6 |                       |
//   +-----+-----------------------+
//
// The launcher had stacked blocks and two hand-written pairing rules before
// this, on the reasoning that a free grid is one in which you can build
// yourself a result list two rows high. The user asked for the grid anyway,
// twice, and the second time named the reason: the rest of the shell works
// like that, and a surface that does not is the odd one out. A result list two
// rows high is now possible and is theirs to make.

var columns = 4
var rows = 8

var catalogue = [
    { type: "search", label: "Search field", icon: "", w: 3, h: 1, minW: 1, minH: 1 },
    { type: "modes", label: "Modes", icon: "", w: 1, h: 1, minW: 1, minH: 1 },
    { type: "pinned", label: "Pinned apps", icon: "", w: 4, h: 1, minW: 1, minH: 1 },
    { type: "categories", label: "Categories", icon: "", w: 1, h: 6, minW: 1, minH: 1 },
    { type: "results", label: "Results", icon: "", w: 3, h: 6, minW: 1, minH: 2 }
]

// The order the default lays them out in, which is also the order the packer
// fills the grid in, so the picture above comes out of `defaults` alone.
var defaults = ["search", "modes", "pinned", "categories", "results"]

function entry(type) {
    return catalogue.find(block => block.type === String(type || "")) || null
}

function label(type) {
    const found = entry(type)
    return found ? found.label : String(type || "")
}

function icon(type) {
    const found = entry(type)
    return found ? found.icon : ""
}

function size(type) {
    const found = entry(type)
    // A type the launcher does not know gets a modest cell rather than none:
    // the sanitizer drops it anyway, and a fallback that returns nothing is a
    // fallback that crashes the packer instead of the file.
    return found ? { w: found.w, h: found.h } : { w: 1, h: 1 }
}

function minSize(type) {
    return Fit.minSize(entry(type))
}

// **The search field is the one block that may not be taken off.** A launcher
// with no field to type in cannot be got out of again; one with no result list
// still answers the next keystroke and says so, which is why the result list
// is removable and was asked to be.
function fixed(type) {
    return String(type) === "search"
}

function isKnown(type) {
    return entry(type) !== null
}

// What the picker offers: everything that is not on the launcher already.
function missing(types) {
    const shown = types || []
    return catalogue.filter(block => shown.indexOf(block.type) < 0)
}
