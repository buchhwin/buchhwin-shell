.pragma library

// A DBusMenu entry's label as it is shown. The spec marks the mnemonic with an
// underscore before its letter ("_Open") and writes a real underscore as two
// ("Save__As" is "Save_As"); the menu has no mnemonics, so the marker goes and
// a doubled one is the underscore it stands for. Taking every underscore
// before a letter away ate both of a pair: "snake__case" came out "snakecase".
function label(text) {
    return String(text === undefined || text === null ? "" : text)
        .replace(/__|_(?=\S)/g, match => match === "__" ? "_" : "")
}
