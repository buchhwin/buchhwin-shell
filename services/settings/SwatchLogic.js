.pragma library

// Names for the colour swatches in Settings (ColorSwatch.qml): the accent
// choices (theme/Colors.qml) and the terminal's prompt and error colours
// (services/terminal/TerminalLogic.js). A swatch used to be a coloured circle
// and nothing else: the pointer could tell them apart, a screen reader found
// nine unnamed rectangles. The panel colours bring their own labels
// (Colors.panelColorChoices).
//
// Keyed without the "#", so the table is names, not colour literals the style
// check would have to excuse line by line. A colour not in it is named by its
// hex value, which is still something a person can read out.
const NAMES = {
    "4f8ff7": "Blue",
    "6ea8fe": "Light blue",
    "8b6cf6": "Violet",
    "a28bfe": "Lavender",
    "d46ad8": "Orchid",
    "ef5f67": "Red",
    "f07178": "Coral",
    "f28b3c": "Orange",
    "e7b43c": "Yellow",
    "4fbf73": "Green",
    "62d394": "Mint",
    "2eb8a8": "Teal",
    "50e2cb": "Turquoise",
    "8f97a6": "Gray",
    "e6e8ee": "White"
}

function nameOf(color) {
    const text = String(color || "").trim().toLowerCase()
    const key = text.charAt(0) === "#" ? text.slice(1) : text
    if (NAMES[key]) return NAMES[key]
    return /^[0-9a-f]{6}$/.test(key) ? "#" + key.toUpperCase() : text
}
