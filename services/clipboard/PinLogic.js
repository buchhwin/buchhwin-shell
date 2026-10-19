.pragma library

// Pinned clipboard entries (ClipboardService, the clipboard panel's Ctrl+P).
// Pure functions, unit tested in ClipboardPinTest.qml.
//
// The same snippets are copied again every day - an address, an IBAN, a
// standard reply, a ticket template - and roll out of a history that keeps
// the newest entries only. A pin is a copy of the entry's content taken out
// of cliphist: one file per pin in the shell's state directory, outside the
// history's rotation and outside "Clear history", and an index beside it
// with what the panel shows of each. Both are the user's alone, like the
// history (0700 for the directory, 0600 for every file in it and the index).
//
// What a password manager marks as sensitive never reaches the history, so
// it cannot be pinned either: a pin is always made from a history entry.

// More than this and a pin is refused with a note, as the launcher refuses
// its pins: a list of pins that only grows is a second history.
var LIMIT = 50

// The picture formats cliphist names in its list (ClipboardService.parse).
var IMAGE_FORMATS = ["png", "jpeg", "webp", "gif", "bmp"]

// What the panel shows of a pin: the preview cliphist listed for the entry
// it was made from, one line, at most this long.
var PREVIEW_MAX = 160

// A pin's id is the md5 of its content, so the same snippet pinned twice is
// one pin, and its file name cannot be anything but 32 hex digits and an
// extension.
function validId(id) {
    return typeof id === "string" && /^[0-9a-f]{32}$/.test(id)
}

function extension(pin) {
    return pin && pin.image ? pin.format : "txt"
}

function fileName(pin) {
    return pin.id + "." + extension(pin)
}

function preview(text) {
    const line = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
    return line.length > PREVIEW_MAX ? line.slice(0, PREVIEW_MAX - 1) + "…" : line
}

// One stored pin as the service keeps it, or null for anything else: an
// index edited by hand, or written by a version that knew other fields.
function sanitizePin(item) {
    if (!item || typeof item !== "object" || !validId(item.id)) return null
    const image = item.image === true
    const format = image ? String(item.format || "") : ""
    if (image && IMAGE_FORMATS.indexOf(format) < 0) return null
    return { id: item.id, image: image, format: format, text: preview(item.text) }
}

// The index file's text -> the list of pins, newest first, each id once and
// at most LIMIT of them. A file that is not JSON is no pins (the service then
// does not write over it: see `parse`).
function sanitize(list) {
    const seen = {}
    const pins = []
    for (const item of Array.isArray(list) ? list : []) {
        const pin = sanitizePin(item)
        if (!pin || seen[pin.id]) continue
        seen[pin.id] = true
        pins.push(pin)
        if (pins.length >= LIMIT) break
    }
    return pins
}

// { pins, ok }: ok is false for a text that is there but not an index, which
// the service keeps rather than replace with an empty one.
function parse(text) {
    const source = String(text || "")
    if (!source.trim().length) return { pins: [], ok: true }
    try {
        const data = JSON.parse(source)
        if (!data || typeof data !== "object" || !Array.isArray(data.pins)) return { pins: [], ok: false }
        return { pins: sanitize(data.pins), ok: true }
    } catch (error) {
        return { pins: [], ok: false }
    }
}

function serialize(pins) {
    return JSON.stringify({ pins: sanitize(pins) }, null, 1) + "\n"
}

// The list after pinning `pin`: it goes first, and pinning a snippet that is
// pinned already moves it to the top instead of adding it twice. null when
// the list is full and the pin is new.
function withPin(pins, pin) {
    const clean = sanitizePin(pin)
    if (!clean) return null
    const rest = (pins || []).filter(item => item.id !== clean.id)
    if (rest.length >= LIMIT) return null
    return [clean].concat(rest)
}

function without(pins, id) {
    return (pins || []).filter(item => item.id !== id)
}

// Whether one more pin fits.
function full(pins) {
    return (pins || []).length >= LIMIT
}

// The pins whose text holds the query, as the history is filtered.
function matching(pins, query) {
    const text = String(query || "").trim().toLowerCase()
    if (!text.length) return pins || []
    return (pins || []).filter(pin => pin.text.toLowerCase().indexOf(text) >= 0)
}

// The pins whose file is there, from the names the settle run listed: a pin
// whose file went (removed by hand, a restore without the directory) is no
// pin, and copying it would put nothing on the clipboard.
function present(pins, names) {
    const there = {}
    for (const name of names || []) there[name] = true
    return (pins || []).filter(pin => there[fileName(pin)] === true)
}

// ---- the commands -------------------------------------------------------------
// Each one runs through a shell under umask 077, with its paths as arguments
// (never in the script's text), so a database path with a space or a quote is
// still one argument.

// Takes entry `entryId` out of the history into the pins' directory and prints
// the new file's id (the md5 of its content). The content is decoded into a
// temporary file first and moved into place under its id only when it is not
// empty, so a failed decode leaves nothing behind. `cliphist` is the program's
// name or path (a stand-in in the test).
function pinCommand(dir, dbPath, entryId, ext, cliphist) {
    return ["sh", "-c",
        "umask 077; dir=$1 db=$2 id=$3 ext=$4 tool=$5; "
        + "mkdir -p -- \"$dir\" && chmod 700 -- \"$dir\" || exit 1; "
        + "tmp=\"$dir/.pin-$$\"; "
        + "if \"$tool\" -db-path \"$db\" decode \"$id\" > \"$tmp\" 2>/dev/null && [ -s \"$tmp\" ]; then :; else rm -f -- \"$tmp\"; exit 1; fi; "
        + "sum=$(md5sum < \"$tmp\") || { rm -f -- \"$tmp\"; exit 1; }; sum=${sum%% *}; "
        + "mv -f -- \"$tmp\" \"$dir/$sum.$ext\" && printf '%s\\n' \"$sum\"",
        "sh", dir, dbPath, String(entryId), ext, cliphist || "cliphist"]
}

// The id the pin run printed, or "" for a run that failed.
function pinnedId(output) {
    const line = String(output || "").trim().split("\n").pop()
    return validId(line) ? line : ""
}

// Puts a pin back on the clipboard. A picture is offered under its own type;
// text is handed over as it is, the way the history's own copy does it
// (`cliphist decode | wl-copy`).
function copyCommand(dir, pin) {
    const file = dir + "/" + fileName(pin)
    const types = pin.image ? ["--type", "image/" + pin.format] : []
    return ["sh", "-c", "file=$1; shift; exec wl-copy \"$@\" < \"$file\"", "sh", file].concat(types)
}

// The directory as the index says it should be: every file that is no pin's
// is removed (an unpin interrupted, a temporary file of a run that died), the
// modes are put right, and the names that are left are printed - `present`
// drops the pins whose file is not among them. Only plain files directly in
// the pins' own directory are touched.
function settleCommand(dir, pins) {
    return ["sh", "-c",
        "dir=$1; shift; [ -d \"$dir\" ] || exit 0; chmod 700 -- \"$dir\" 2>/dev/null; "
        + "for f in \"$dir\"/* \"$dir\"/.pin-*; do [ -f \"$f\" ] || continue; name=${f##*/}; "
        + "for k in \"$@\"; do if [ \"$k\" = \"$name\" ]; then chmod 600 -- \"$f\" 2>/dev/null; printf '%s\\n' \"$name\"; continue 2; fi; done; "
        + "rm -f -- \"$f\"; done",
        "sh", dir].concat((pins || []).map(fileName))
}

function removeCommand(dir, pin) {
    return ["rm", "-f", "--", dir + "/" + fileName(pin)]
}
