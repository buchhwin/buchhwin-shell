import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/dashboard/WorldClockLogic.js" as W
import "../../services/dashboard/NotesLogic.js" as N
import "../../services/dashboard/DashboardLogic.js" as D

// The dashboard's world clock and notes cards: their places in the catalogue,
// the places as the setting keeps them, the offsets `date` reports and the
// times worked out from them, the search for a place, and the notes file's
// text. The offsets run is tried against a zone directory in the runner's
// sandbox (an empty file there is no zone, and glibc reads it as UTC).
ShellRoot {
    id: root
    readonly property string state: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string zones: state + "/world-clock-test"
    property int step: 0

    Process {
        id: shell
        property string output: ""
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: next.start()
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }
    function run(command) {
        shell.output = ""
        shell.command = command
        shell.running = true
    }

    Component.onCompleted: {
        // ---- the catalogue ------------------------------------------------------
        T.eq([D.isKnown("worldClock"), D.isKnown("notes")], [true, true], "both cards are in the catalogue")
        T.eq([D.label("worldClock"), D.label("notes")], ["World clock", "Notes"], "with their names")
        T.eq([D.minSize("worldClock"), D.minSize("notes")], [{ w: 1, h: 2 }, { w: 1, h: 2 }],
             "two rows at least: a heading and something under it")
        T.eq(D.size("worldClock").h, 3, "the world clock is added three rows high: the search and two finds fit its editor")

        // ---- the places -----------------------------------------------------------
        T.eq(W.parseZones("Europe/London, America/New_York,,Europe/London"), ["Europe/London", "America/New_York"],
             "the comma-string: trimmed, each place once")
        // (Not first in the string: the runner rewrites a literal that starts
        // with two "../" as an import path.)
        T.eq(W.parseZones("UTC,../../etc/passwd,/abs,Europe/../x,Etc/GMT+5"), ["UTC", "Etc/GMT+5"],
             "nothing that could leave the zone directory")
        T.eq(W.parseZones("A,B,C,D,E").length, W.LIMIT, "four places at most")
        T.eq(W.parseZones(undefined), [], "no setting yet: no places")
        T.eq(W.storeZones(["Asia/Tokyo", "bad name", "UTC"]), "Asia/Tokyo,UTC", "stored as one string")
        T.eq(W.withZone(["UTC"], "Asia/Tokyo"), ["UTC", "Asia/Tokyo"], "a place goes at the end")
        T.eq([W.withZone(["UTC"], "UTC"), W.withZone(["A", "B", "C", "D"], "E"), W.withZone([], "no zone")], [null, null, null],
             "not twice, not a fifth, not a name that is no zone")
        T.eq(W.withoutZone(["UTC", "Asia/Tokyo"], "UTC"), ["Asia/Tokyo"], "removed")
        T.eq([W.cityOf("America/Argentina/Buenos_Aires"), W.cityOf("UTC")], ["Buenos Aires", "UTC"], "a place by its city")

        // ---- offsets and times ------------------------------------------------------
        T.eq([W.parseOffset("+0530"), W.parseOffset("-0300"), W.parseOffset("+0000")], [330, -180, 0], "date's %z in minutes")
        T.ok(isNaN(W.parseOffset("?")) && isNaN(W.parseOffset("")) && isNaN(W.parseOffset("+5")), "anything else is no offset")
        T.eq(W.parseOffsets("Asia/Kolkata\t+0530\nGone/Zone\t?\n../x\t+0100\nnoise\n"), { "Asia/Kolkata": 330, "Gone/Zone": null },
             "the run's lines, an unknown zone as null")
        const command = W.offsetsCommand(["UTC", "bad name", "Asia/Tokyo"], "/zones")
        T.eq(command.slice(-3), ["/zones", "UTC", "Asia/Tokyo"], "the names go in as arguments, the bad one left out")

        // 2026-10-19 22:30 UTC: 04:00 the next day in Kolkata, 19:30 in
        // Buenos Aires, and here (two hours east) 00:30 the next day.
        const now = Date.UTC(2026, 9, 19, 22, 30)
        const kolkata = W.wallClock(now, 330, 0)
        T.eq([kolkata.date.getHours(), kolkata.date.getMinutes(), kolkata.dayShift], [4, 0, 1], "Kolkata is tomorrow already")
        const buenos = W.wallClock(now, -180, 120)
        T.eq([buenos.date.getHours(), buenos.date.getMinutes(), buenos.dayShift], [19, 30, -1], "and Buenos Aires yesterday, seen from here")
        T.eq(W.wallClock(now, 60, 60).dayShift, 0, "the same day")
        T.eq([W.difference(330, 120), W.difference(-180, 120), W.difference(60, 60), W.difference(NaN, 0)],
             ["+3:30 h", "−5 h", "Same time", ""], "how far ahead or behind")
        T.eq([W.dayNote(1), W.dayNote(-1), W.dayNote(0)], ["Tomorrow", "Yesterday", ""], "the day, when it is another")
        T.eq([W.offsetsDue(new Date(2026, 0, 1, 3, 45)), W.offsetsDue(new Date(2026, 0, 1, 3, 46)), W.offsetsDue(null)],
             [true, false, false], "asked again on the quarter hours")

        // ---- choosing a place --------------------------------------------------------
        const table = W.parseZoneTab("# comment\nDE\t+0000+00000\tEurope/Berlin\tmost of Germany\n"
                                     + "DE\t+0000+00000\tEurope/Busingen\tBusingen\nGB,GG\t+0000+00000\tEurope/London\n"
                                     + "US\t+0000+00000\tAmerica/New_York\tEastern (most areas)\nXX\tbroken\n")
        T.eq(table.map(row => row.zone), ["Europe/Berlin", "Europe/Busingen", "Europe/London", "America/New_York"],
             "the tz database's places, the first country of each")
        const countries = W.parseCountries("#code\tname\nDE\tGermany\nGB\tBritain (UK)\nUS\tUnited States\n")
        T.eq(countries.DE, "Germany", "and its country names")
        T.eq(W.search(table, countries, "ber", [], 5).map(row => row.zone), ["Europe/Berlin"], "a city by how it starts")
        T.eq(W.search(table, countries, "germany", [], 5).map(row => row.zone), ["Europe/Berlin", "Europe/Busingen"],
             "a country brings its places")
        T.eq(W.search(table, countries, "york", [], 5)[0], { zone: "America/New_York", label: "New York",
                                                              detail: "United States · Eastern (most areas)" },
             "a row says where the place is")
        T.eq(W.search(table, countries, "germany", ["Europe/Berlin"], 5).map(row => row.zone), ["Europe/Busingen"],
             "a place on the card already is not offered")
        T.eq(W.search(table, countries, "utc", [], 5).map(row => row.zone), ["UTC"], "UTC is always a place")
        T.eq(W.search(table, countries, "  ", [], 5), [], "nothing typed, nothing offered")

        // ---- notes --------------------------------------------------------------------
        T.eq([N.fromFile("a\nb\n"), N.fromFile("a"), N.fromFile(undefined)], ["a\nb", "a", ""], "the file's last newline is not shown")
        T.eq([N.toFile("a\nb"), N.toFile("")], ["a\nb\n", ""], "and goes back on; an empty note is an empty file")
        T.eq(N.toFile(N.fromFile("note\n")), "note\n", "read and saved again, the same file")
        T.eq([N.needsSave("x", "", true), N.needsSave("x", "x\n", true), N.needsSave("", "", false), N.needsSave("x", "", false)],
             [true, false, false, false], "only typing since the last read or write is saved, and never before the first read")
        T.eq([N.takesRead("x", "x\n", true), N.takesRead("typed", "x\n", true)], [true, false],
             "a read does not overwrite unsaved typing")
        advance()
    }

    function advance() {
        step += 1
        if (step === 1) {
            run(["sh", "-c", "mkdir -p \"$1/Test\" && : > \"$1/Test/Place\"", "sh", zones])
        } else if (step === 2) {
            run(W.offsetsCommand(["Test/Place", "Gone/Zone"], zones))
        } else if (step === 3) {
            T.eq(W.parseOffsets(shell.output), { "Test/Place": 0, "Gone/Zone": null },
                 "a zone file is asked, a missing one is unknown")
            // The real database, where the system has one.
            run(["sh", "-c", "[ -f /usr/share/zoneinfo/Asia/Kolkata ] || exit 0; TZ=:/usr/share/zoneinfo/Asia/Kolkata date +%z"])
        } else if (step === 4) {
            if (shell.output.trim().length) T.eq(W.parseOffset(shell.output), 330, "Kolkata is 5:30 east of UTC")
            run(["sh", "-c", "rm -rf -- \"$1\"", "sh", zones])
        } else {
            T.finish("DashboardExtrasTest")
        }
    }
}
