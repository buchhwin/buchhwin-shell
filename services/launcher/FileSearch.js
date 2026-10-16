.pragma library

// The launcher's file search ("/" mode) over plocate's index: what it asks
// and what it keeps of the answer. Unit tested (tests/qml/LauncherTest.qml).

// How many matches plocate hands over, and how many rows the launcher shows.
var LIMIT = 5000
var SHOWN = 50

// The home folder is a pattern of its own: plocate ANDs its patterns, all
// from the index, while `-l` stops at the limit over the whole database. With
// the query alone (and -l 200) /usr, /opt and the hidden folders used it all
// up before a file of the user's came along, and "png" found nothing at home
// out of 29 000 matches (round 12). The hidden folders still count against
// the limit, and they come first: plocate answers in path order, where "."
// sorts before every letter. Here 2736 "png" paths under home sit in hidden
// folders and 330 outside them, so 1000 would still have found none; 5000
// lines are about 0.5 MB and take no longer (0.27 s, the index lookup). A
// regex that skips hidden folders scans the whole database instead (0.55 s
// on nine cores). `paths` leaves them out.
function command(home, query) {
    return ["plocate", "-i", "-l", String(LIMIT), "--", String(home) + "/", String(query)]
}

// The paths worth a row: under the home folder, nothing hidden on the way.
function paths(text, home, limit) {
    const prefix = String(home) + "/"
    return String(text || "").split("\n")
        .filter(path => path.startsWith(prefix) && !path.slice(prefix.length).split("/").some(part => !part.length || part.startsWith(".")))
        .slice(0, limit === undefined ? SHOWN : limit)
}

// How many paths under the home folder the index holds (`plocate -c`, which
// exits 1 and prints 0 when there are none); -1 when it did not answer.
function indexCommand(home) {
    return ["plocate", "-c", "--", String(home) + "/"]
}

function count(text) {
    const value = String(text || "").trim()
    return /^\d+$/.test(value) ? Number(value) : -1
}
