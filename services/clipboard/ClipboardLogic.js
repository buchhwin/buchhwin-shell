.pragma library

// The commands ClipboardService runs on the history's files. Pure functions,
// unit tested in ClipboardPrivacyTest.qml.
//
// The history holds every text and picture copied - a password included when
// the program it came from did not mark it - and cliphist created its database
// with the default mode (0644), the previews' directory 0755: readable by every
// local account wherever the home directory is not private (older openSUSE
// defaults, a shared or NFS home). So both are the user's alone: the recorders
// run under umask 077, which cliphist inherits when it creates the database,
// and a database from before is set to 0600 as they start; the previews'
// directory is made 0700, and what is decoded into it 0600.
//
// The previews from before that fix were left as they were: their directory
// 0755 and the decoded pictures in it 0644, until a panel opened with an image
// preview missing (only that run chmodded the directory, and never a file in
// it). So the recorders take the previews' directory too as they start: the
// group's and the others' bits come off it and off everything in it.

// A recorder's argv (or the wipe's, which creates a missing database too),
// run through a shell that sets the mode first and then becomes the command
// itself (exec), so the command line start-shell.sh looks for when it reaps
// helpers stays the recorder's own. `previewsDir` is optional (the wipe
// removes the directory instead); a directory that is not there is left so.
function privately(dbPath, command, previewsDir) {
    return ["sh", "-c",
        "umask 077; [ -e \"$1\" ] && chmod 600 -- \"$1\"; [ -n \"$2\" ] && [ -d \"$2\" ] && chmod -R go= -- \"$2\" 2>/dev/null; shift 2; exec \"$@\"",
        "sh", dbPath, previewsDir || ""].concat(command)
}

// Decodes previews: pairs of [cliphist id, file name]. A file that is there
// already is kept; one that comes out empty is removed (a failed decode is
// tried again next time); every file that is there afterwards is printed.
function previewsCommand(thumbDir, dbPath, pairs) {
    const args = []
    for (const pair of pairs) args.push(pair[0], pair[1])
    return ["sh", "-c",
        "umask 077; mkdir -p \"$1\" && { chmod 700 \"$1\" || true; } && dir=\"$1\" && db=\"$2\" && shift 2 && while [ $# -gt 1 ]; do [ -s \"$dir/$2\" ] || cliphist -db-path \"$db\" decode \"$1\" > \"$dir/$2\"; if [ -s \"$dir/$2\" ]; then echo \"$2\"; else rm -f \"$dir/$2\"; fi; shift 2; done",
        "sh", thumbDir, dbPath].concat(args)
}

// ---- the X11 bridge (scripts/x11-clipboard-bridge.py) ------------------------
// The bridge hands on what an X11 program copies (Citrix's client above all),
// and on most days no X11 program runs at all: it held 12 MB and a connection
// to XWayland from login to logout for nothing. It starts with the first X11
// window of the session and stays until the shell ends - stopping it again
// could lose its "the owner went away, clear the copy" step. An X11 program
// that copies without ever mapping a window (xclip from a script) is not
// bridged until some X11 window has been there.

// Whether the bridge runs: an X display, an X11 window seen this session, and
// no restart pause.
function bridgeWanted(display, sawX11, paused) {
    return String(display || "").length > 0 && sawX11 === true && paused !== true
}

// Whether any of Hyprland's windows is an X11 one, by their IPC objects
// (HyprlandToplevel.lastIpcObject, which only refreshToplevels() fills).
function anyX11(ipcObjects) {
    return (ipcObjects || []).some(item => !!item && item.xwayland === true)
}

// The pause before the bridge starts again after its `failures`-th end in a
// row: 5 s, doubling, and -1 after the fifth - a bridge that cannot stay up
// is not restarted forever. One that ran for a minute starts the count anew.
function bridgeRestartDelay(failures) {
    if (failures < 1) return 0
    if (failures > 5) return -1
    return 5000 * Math.pow(2, failures - 1)
}

// ---- forgetting (Settings > Desktop extras > Clipboard, both off by default) --
// The history keeps every unmarked password and every screenshot until 200
// newer entries push it out. Two settings forget sooner: the whole history
// when the session ends, and every entry once it is older than a limit.
//
// cliphist keeps no times, only ids that grow with every copy (and start at 1
// again after a wipe). So the service notes, at each read of the list, the
// highest id there is and when: [[epoch ms, id], ...]. An entry whose id was
// already there at a note older than the limit is older than the limit.

var AGE_CHOICES = [0, 1, 8, 24, 168]

// The limit in hours from the setting: 0 (never) for anything not offered.
function maxAgeHours(value) {
    const hours = Number(value)
    return AGE_CHOICES.indexOf(hours) >= 0 ? hours : 0
}

// The notes after a read whose highest id is `maxId`: a new note when there
// are new entries, all notes anew when the ids went back (a wipe), and none
// older than the limit kept but the newest of them - it is the one that
// decides.
function withMark(marks, nowMs, maxId, maxAgeMs) {
    const list = (Array.isArray(marks) ? marks : [])
        .filter(mark => Array.isArray(mark) && mark.length === 2 && isFinite(mark[0]) && isFinite(mark[1]))
    if (!(maxId > 0)) return []
    let next = list.length && list[list.length - 1][1] > maxId ? [] : list.slice()
    if (!next.length || next[next.length - 1][1] < maxId) next.push([nowMs, maxId])
    const old = next.filter(mark => mark[0] <= nowMs - maxAgeMs)
    if (old.length > 1) next = next.slice(next.indexOf(old[old.length - 1]))
    return next
}

// The ids of `ids` (strings, as cliphist lists them) older than the limit.
function expiredIds(ids, marks, nowMs, maxAgeMs) {
    if (!(maxAgeMs > 0)) return []
    let boundary = 0
    for (const mark of marks || []) if (mark[0] <= nowMs - maxAgeMs) boundary = Math.max(boundary, mark[1])
    if (!boundary) return []
    return (ids || []).filter(id => Number(id) > 0 && Number(id) <= boundary)
}

// argv that deletes these entries: cliphist reads them on stdin, one per line.
function deleteCommand(dbPath, ids) {
    return ["sh", "-c", "db=\"$1\"; shift; printf '%s\\n' \"$@\" | cliphist -db-path \"$db\" delete", "sh", dbPath].concat(ids)
}
