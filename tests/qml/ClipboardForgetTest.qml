import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/clipboard/ClipboardLogic.js" as Logic

// "Forget entries after …": cliphist keeps no times, so the service notes the
// highest id at each read of the list, and an entry already there at a note
// older than the limit goes. Off unless chosen; an unknown choice is "never".
ShellRoot {
    Component.onCompleted: {
        const hour = 3600000
        const t = 1760000000000
        T.eq([0, 1, 8, 24, 168].map(Logic.maxAgeHours), [0, 1, 8, 24, 168], "the offered limits")
        T.eq([undefined, null, "", 5, -1, "24", "abc"].map(Logic.maxAgeHours), [0, 0, 0, 0, 0, 24, 0],
             "anything else is never")

        let marks = Logic.withMark([], t, 10, hour)
        T.eq(marks, [[t, 10]], "the first read notes its highest id")
        T.eq(Logic.withMark(marks, t + 60000, 10, hour), marks, "no new entries: no new note")
        marks = Logic.withMark(marks, t + 30 * 60000, 14, hour)
        T.eq(marks, [[t, 10], [t + 30 * 60000, 14]], "new entries: a new note")
        const ids = ["14", "13", "12", "11", "10", "9", "1"]
        T.eq(Logic.expiredIds(ids, marks, t + 50 * 60000, hour), [], "nothing is an hour old yet")
        T.eq(Logic.expiredIds(ids, marks, t + 61 * 60000, hour), ["10", "9", "1"],
             "an hour after the first note, what was there then goes")
        T.eq(Logic.expiredIds(ids, marks, t + 91 * 60000, hour), ids, "and half an hour later the rest")
        T.eq(Logic.expiredIds(ids, marks, t + 91 * 60000, 0), [], "no limit, nothing goes")

        marks = Logic.withMark([[t, 10], [t + hour, 14], [t + 2 * hour, 20]], t + 3.5 * hour, 20, hour)
        T.eq(marks, [[t + 2 * hour, 20]], "of the notes older than the limit only the newest is kept")
        T.eq(Logic.withMark([[t, 10], [t + hour, 14]], t + 2 * hour, 3, hour), [[t + 2 * hour, 3]],
             "ids that went back (a wipe) start the notes anew")
        T.eq(Logic.withMark([[t, 10]], t + hour, 0, hour), [], "an empty history keeps no notes")
        T.eq(Logic.withMark([["x", 1], [t], null, [t, 5]], t + 60000, 5, hour), [[t, 5]], "broken notes are dropped")

        const argv = Logic.deleteCommand("/c/cliphist.db", ["3", "1"])
        T.eq(argv.slice(0, 2), ["sh", "-c"], "deleted through a shell")
        T.eq(argv.slice(3), ["sh", "/c/cliphist.db", "3", "1"], "the database and the ids are arguments")
        T.ok(argv[2].indexOf("cliphist -db-path \"$db\" delete") > 0, "one cliphist delete reads them all")
        T.finish("ClipboardForgetTest")
    }
}
