.pragma library

// When Settings may let a page go, and which of its fields hold something
// worth keeping it for (shell/settings/SettingsPanel.qml, releaseTimer and
// pendingEdits).
//
// A page is let go a minute after the panel closed, which frees its hundreds
// of items, unless a field holds what the user typed and did not hand on: a
// reload would throw that away. Any text left in any field used to count -
// a search in Shortcuts or Weather, the Input page's test line, a field the
// page itself had emptied after use, one Escape had cleared - and kept the
// page for the rest of the session.

// The first look, and then how often to look again while a draft holds it.
var CHECK_MS = 60000
// Past this, a page closed this long goes even with a draft in it: half an
// hour is long enough to come back to an unfinished form.
var CAP_MS = 30 * 60000

// Whether a ShellTextField holds a draft: typed into since its last Return,
// with something in it, which is not what the setting already holds
// (`storedText`, StoredTextField), in a field that keeps values at all -
// `scratch` marks a search or a test line.
function holdsDraft(field) {
    if (!field || field.edited !== true || field.scratch === true) return false
    var text = String(field.text === undefined || field.text === null ? "" : field.text)
    if (!text.trim().length) return false
    if (field.storedText !== undefined && text === String(field.storedText)) return false
    return true
}

// Whether to let the page go now, `closedMs` after the panel closed. Never
// while a display change waits for its answer; at once without a draft;
// with one, once the cap is reached.
function releaseNow(closedMs, confirming, drafts) {
    if (confirming) return false
    return !drafts || closedMs >= CAP_MS
}

// What a field for a stored value (StoredTextField) does as the focus leaves
// it: "restore" an emptied field to the stored value - an Escape or a
// select-all-and-delete is no "store nothing" - "commit" a changed text, and
// "none" for what is stored already.
function leaveAction(text, storedText) {
    var value = String(text === undefined || text === null ? "" : text)
    if (!value.length) return "restore"
    return value === String(storedText === undefined || storedText === null ? "" : storedText) ? "none" : "commit"
}
