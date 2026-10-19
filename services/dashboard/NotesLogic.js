.pragma library

// The dashboard's notes card (shell/dashboard/NotesCard.qml): one plain text
// file in the state directory, saved as it is typed. Pure functions, unit
// tested in DashboardExtrasTest.qml.
//
// Scratch text - a number to call back, what to say in the next meeting -
// without opening an editor. The file is the user's alone (0600, in the 0700
// state directory) and ends in a newline like any text file; the card shows
// it without that newline, so a note read and saved again is the same file.

// A pause in the typing this long saves; closing the dashboard saves at once.
var SAVE_DELAY_MS = 800

// The file's text -> what the card shows.
function fromFile(text) {
    const value = String(text === undefined || text === null ? "" : text)
    return value.endsWith("\n") ? value.slice(0, -1) : value
}

// What the card holds -> the file's text: one newline at the end, none for
// an empty note (an empty file, not a file with an empty line).
function toFile(text) {
    const value = String(text === undefined || text === null ? "" : text)
    return value.length ? value + "\n" : ""
}

// Whether the card holds something the file does not: typed since the last
// read or write. Before the first read there is nothing to save - an empty
// card is not a note that was emptied.
function needsSave(shown, saved, read) {
    return read === true && toFile(shown) !== String(saved === undefined || saved === null ? "" : saved)
}

// A read that comes in while the card holds unsaved typing is not taken: the
// typing is newer than any file the shell itself wrote.
function takesRead(shown, saved, read) {
    return !needsSave(shown, saved, read)
}
