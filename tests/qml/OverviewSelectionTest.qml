import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/overview/SelectionLogic.js" as S

// The overview's keyboard selection (shell/overview/SelectionLogic.js): it
// never goes below zero, so Down on an empty search no longer leaves -1
// behind for the next list to keep.
ShellRoot {
    Component.onCompleted: {
        T.eq(S.step(0, 1, 0), 0, "Down with no windows stays at 0, not -1")
        T.eq(S.step(0, -1, 0), 0, "Up with no windows")
        T.eq(S.clamp(S.step(0, 1, 0), 3), 0, "the next list starts at its first window")
        T.eq(S.clamp(-1, 3), 0, "a -1 left from before is taken back to 0")
        T.eq(S.step(0, 1, 3), 1, "Down moves on")
        T.eq(S.step(2, 1, 3), 2, "and stops at the last")
        T.eq(S.step(0, -1, 3), 0, "Up stops at the first")
        T.eq(S.clamp(5, 2), 1, "a shorter list keeps the last one selected")
        T.eq(S.clamp(1.7, 3), 1, "a whole index")
        T.eq([S.clamp(undefined, 3), S.clamp(NaN, 3), S.clamp(0, undefined)], [0, 0, 0], "nothing sensible is the first")
        T.finish("OverviewSelectionTest")
    }
}
