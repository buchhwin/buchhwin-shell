import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/color/ColorLogic.js" as C

ShellRoot {
    Component.onCompleted: {
        T.eq(C.isColour("#a1b2c3"), true, "a six-digit hex is a colour")
        T.eq(C.isColour("#A1B2C3"), true, "in either case")
        T.eq(C.isColour("a1b2c3"), false, "without the hash it is not")
        T.eq(C.isColour("#abc"), false, "nor is the short form")
        T.eq(C.isColour("#a1b2c3x"), false, "nor anything longer")
        T.eq(C.isColour(""), false, "nor nothing")
        T.eq(C.isColour(null), false, "nor nothing at all")
        T.eq(C.normalize("  #A1B2C3 "), "#a1b2c3", "trimmed and lower-cased")
        T.eq(C.normalize("nonsense"), "", "and anything else is empty")

        // The history is a comma-string because SettingsService cannot store
        // a list: `sanitizedNode` turns an array into {"0": ...} on the next
        // write of any setting.
        T.eq(C.parseHistory("#111111,#222222"), ["#111111", "#222222"], "a stored list reads back")
        T.eq(C.parseHistory(""), [], "an empty one is empty")
        T.eq(C.parseHistory(null), [], "and so is nothing")
        T.eq(C.parseHistory("#111111,rubbish,,#222222"), ["#111111", "#222222"], "rubbish between commas is dropped")
        T.eq(C.parseHistory("#111111,#111111"), ["#111111"], "and a repeat is one entry")
        T.eq(C.parseHistory(Array(30).fill("#111111").map((c, i) => "#0000" + (10 + i)).join(",")).length,
             C.HISTORY_MAX, "a long list is cut to the maximum")

        T.eq(C.addToHistory([], "#abcdef"), "#abcdef", "the first pick")
        T.eq(C.addToHistory(["#111111"], "#222222"), "#222222,#111111", "a new pick goes in front")
        // Picking the same colour again is not a second entry: it moves up.
        T.eq(C.addToHistory(["#111111", "#222222"], "#222222"), "#222222,#111111", "a repeat moves to the front")
        T.eq(C.addToHistory(["#111111"], "nonsense"), "#111111", "and nothing that is not a colour is kept")
        const long = Array.from({ length: C.HISTORY_MAX }, (_, i) => "#0000" + (10 + i))
        T.eq(C.parseHistory(C.addToHistory(long, "#ffffff")).length, C.HISTORY_MAX,
             "a full history stays its size")
        T.eq(C.parseHistory(C.addToHistory(long, "#ffffff"))[0], "#ffffff", "with the newest in front")
        T.eq(C.parseHistory(C.addToHistory(long, "#ffffff")).indexOf(long[long.length - 1]), -1,
             "and the oldest falls off the end")

        // Which ink reads on a swatch. A judgement, not a colour: naming the
        // two colours is the theme's job and this file may not do it.
        T.eq(C.isLight("#ffffff"), true, "white wants dark ink")
        T.eq(C.isLight("#000000"), false, "black wants light ink")
        T.eq(C.isLight("#ffff00"), true, "and so does yellow")
        T.eq(C.isLight("#0000ff"), false, "while blue does not")
        T.eq(C.isLight("nonsense"), false, "nothing readable is treated as dark")

        T.finish("ColorTest")
    }
}
