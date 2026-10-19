import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/workspaces/WorkspaceLogic.js" as W

// Super+Page Up/Down and Super with the wheel: the neighbouring pip of the
// monitor's row, or one new workspace past the last from one with windows,
// never out of the monitor's block (WorkspaceLogic.step).
ShellRoot {
    function pips(list) {
        return list.map(item => ({ id: item[0], occupied: item[1] === true }))
    }

    Component.onCompleted: {
        // The first monitor, the row "1 3 4" (open mode: 2 is gone).
        const row = pips([[1, true], [3, true], [4, false]])
        T.eq(W.step(row, 1, 1, 0), 3, "the next pip, past a gap the row does not draw")
        T.eq(W.step(row, 3, -1, 0), 1, "the previous pip")
        T.eq(W.step(row, 3, 1, 0), 4, "an empty pip is a pip")
        T.eq(W.step(row, 4, 1, 0), 0, "past the last from an empty one: nowhere, no march into nothing")
        T.eq(W.step(pips([[1, true], [3, true]]), 3, 1, 0), 4, "past the last from one with windows: one new workspace")
        T.eq(W.step(row, 1, -1, 0), 0, "before the first from 1: nothing, no wrap")
        T.eq(W.step(pips([[3, true]]), 3, -1, 0), 2, "before the first from 3 with windows: 2, still the monitor's own")

        // The second monitor's block (11-20).
        T.eq(W.step(pips([[11, true], [12, true]]), 12, 1, 10), 13, "a new one in the second block")
        T.eq(W.step(pips([[19, true], [20, true]]), 20, 1, 10), 0, "never past the block's end into the next monitor's")
        T.eq(W.step(pips([[11, true]]), 11, -1, 10), 0, "never below the block's start into the first monitor's")
        T.eq(W.step(pips([[1, false], [11, true], [12, true]]), 11, -1, 10), 1, "a stray pip of another block is still a pip")

        // Fixed mode: 1-5 drawn whether or not they exist.
        const fixed = pips([[1, true], [2, false], [3, false], [4, false], [5, false]])
        T.eq(W.step(fixed, 1, 1, 0), 2, "fixed: the next slot, empty or not")
        T.eq(W.step(fixed, 5, 1, 0), 0, "fixed: from the last, empty slot nowhere")

        // What the caller might hand over.
        T.eq(W.step(row, 1, 0, 0), 0, "no direction, no step")
        T.eq(W.step(row, -1, 1, 0), 0, "no active workspace (a special one), no step")
        T.eq(W.step([], 2, 1, 0), 0, "an unknown row and an unknown current: nothing")
        T.eq(W.step(null, 2, 1, 0), 0, "no row at all")
        T.eq(W.step(row, 1, 3, 0), 3, "any positive direction is the next one")
        T.eq(W.step(row, 4, -7, 0), 3, "any negative one the previous")
        T.eq(W.step(row, 3, 1, NaN), 4, "an unknown base is the first block")
        T.eq(W.step(pips([[2, true]]), 1, 1, 0), 2, "a current one the row does not draw steps by its number")

        // Through the row the widgets draw: the same entries, so the step
        // lands where the eye went. "open" without 2 here.
        const entries = W.entries("open", 5, [
            { id: 1, name: "1", windows: 1, screen: "DP-8", toplevels: 1 },
            { id: 3, name: "3", windows: 2, screen: "DP-8", toplevels: 2 },
            { id: 11, name: "11", windows: 1, screen: "DP-10", toplevels: 1 }
        ], "DP-8", 1, 0, 1, true)
        T.eq(W.step(entries, 1, 1, 0), 3, "the entries of one screen, not another's 11")
        T.eq(W.step(entries, 3, 1, 0), 4, "from 3 with windows to a new 4")
        const gapless = W.entries("gapless", 5, [
            { id: 1, name: "1", windows: 1, screen: "DP-8", toplevels: 1 },
            { id: 3, name: "3", windows: 2, screen: "DP-8", toplevels: 2 }
        ], "DP-8", 1, 0, 1, true)
        T.eq(W.step(gapless, 1, 1, 0), 2, "gapless draws 2, and the step goes there")
        T.finish("WorkspaceStepTest")
    }
}
