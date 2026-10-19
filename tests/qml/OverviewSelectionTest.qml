import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/overview/SelectionLogic.js" as S
import "../../services/overview/OverviewLogic.js" as O

// The overview's keyboard selection (shell/overview/SelectionLogic.js): it
// never goes below zero, so Down on an empty search no longer leaves -1
// behind for the next list to keep; the keys reach the workspace cards too,
// and Up and Down go from one monitor's row to the next.
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

        // ---- the stops: windows and, while nothing is typed, the cards ------
        const monitors = [
            { id: 0, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0, focused: true, activeWorkspace: { id: 1 } },
            { id: 1, name: "DP-2", x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0, focused: false, activeWorkspace: { id: 11 } }
        ]
        const clients = [
            { address: "0xb", title: "Below", class: "kitty", at: [0, 600], size: [960, 480], workspace: { id: 1, name: "1" }, monitor: 0 },
            { address: "0xa", title: "Above", class: "brave", at: [0, 0], size: [960, 540], workspace: { id: 1, name: "1" }, monitor: 0 },
            { address: "0xc", title: "Notes", class: "kate", at: [1920, 0], size: [960, 540], workspace: { id: 12, name: "12" }, monitor: 1 }
        ]
        const workspaces = [{ id: 1, name: "1", monitorID: 0 }, { id: 2, name: "2", monitorID: 0 }, { id: 3, name: "3", monitorID: 0 },
                            { id: 11, name: "11", monitorID: 1 }, { id: 12, name: "12", monitorID: 1 }]
        const rows = O.groups(O.build(clients, monitors, workspaces, "open", 5, true), monitors, true)
        const list = S.stops(rows, "")
        T.eq(list.map(stop => stop.key), ["w:0xa", "w:0xb", "c:1", "c:2", "c:3", "n:DP-1", "c:11", "w:0xc", "c:12", "n:DP-2"],
             "a card's windows top to bottom, then the card; each row's new workspace last")
        T.eq(list.map(stop => stop.kind), ["window", "window", "card", "card", "card", "new", "card", "window", "card", "new"],
             "and each says what it is")
        T.eq([list[2].workspace, list[5].workspace, list[9].workspace], [1, 4, 13], "a card's stop opens its workspace, the new one its number")
        T.eq(list.filter(stop => stop.kind === "card").map(stop => stop.closable), [true, true, true, true, true],
             "and knows whether Delete may close it")
        T.eq(S.stops(rows, "no").map(stop => stop.key), ["w:0xc"], "a search leaves the windows that match, no cards")
        T.eq(S.stops(rows, "zzz"), [], "and nothing when nothing matches")
        T.eq(S.stops([], ""), [], "no rows, no stops")

        T.eq(S.openingIndex(list), 0, "the overview opens on the first window")
        const emptyFirst = S.stops(O.groups(O.build([clients[2]], monitors, workspaces, "open", 5, true), monitors, true), "")
        T.eq(emptyFirst[S.openingIndex(emptyFirst)].key, "w:0xc", "even when it is on another card than the first")
        T.eq(S.openingIndex(S.stops(O.groups(O.build([], monitors, workspaces, "open", 5, true), monitors, true), "")), 0,
             "and on the first card without windows")
        T.eq(S.openingIndex([]), 0, "nothing at all is 0")

        // The selection stays on its stop while the list changes around it.
        const fewer = S.stops(O.groups(O.build(clients.slice(1), monitors, workspaces, "open", 5, true), monitors, true), "")
        T.eq(fewer[S.indexOf(fewer, "c:12", 8)].key, "c:12", "a window closed before it moves every index, not the selection")
        T.eq(S.indexOf(fewer, "w:0xb", 1), 1, "a selected window that closed leaves the selection where it was")
        T.eq([S.indexOf(fewer, "", 99), S.indexOf([], "c:1", 3)], [fewer.length - 1, 0], "held inside the list")

        // Up and Down: the nearest card a line above or below. Each row is a
        // line here (four columns); from a window they go by its card.
        T.eq(list[S.vertical(list, 2, 1, 4)].key, "c:11", "Down from DP-1's first card is DP-2's first")
        T.eq(list[S.vertical(list, 0, 1, 4)].key, "c:11", "and from a window on it, the same")
        T.eq(list[S.vertical(list, 4, 1, 4)].key, "n:DP-2", "the third card's nearest below is the new one at the third place")
        T.eq(list[S.vertical(list, 5, 1, 4)].key, "n:DP-2", "the fourth place has nothing below: the nearest, the last")
        T.eq(list[S.vertical(list, 8, -1, 4)].key, "c:2", "Up from DP-2's second card is DP-1's second")
        T.eq(list[S.vertical(list, 7, -1, 4)].key, "c:2", "and from the window on it")
        // Two columns: DP-1's four cards make two lines.
        T.eq(list[S.vertical(list, 2, 1, 2)].key, "c:3", "with two columns Down goes one line within the row")
        T.eq(list[S.vertical(list, 4, 1, 2)].key, "c:11", "and from its last line to the next row")
        T.eq(list[S.vertical(list, 6, -1, 2)].key, "c:3", "Up from the next row lands on the line above it")
        // No line that way: like Left and Right, so the arrows never go dead.
        T.eq(S.vertical(list, 2, -1, 4), 1, "Up from the first line steps back")
        T.eq(S.vertical(list, 9, 1, 4), 9, "Down at the very end stays")
        T.eq(S.vertical(list, 8, 1, 4), 9, "Down from the last line steps on")
        const typed = S.stops(rows, "e")
        T.eq(typed.map(stop => stop.key), ["w:0xa", "w:0xb", "w:0xc"], "with a search the stops are windows")
        T.eq([S.vertical(typed, 0, 1, 4), S.vertical(typed, 2, -1, 4)], [1, 1], "and Up and Down step through them as before")
        T.eq([S.vertical([], 0, 1, 4), S.vertical(list, 2, 1, 0)], [0, 3], "nothing to walk, or no columns given")

        T.finish("OverviewSelectionTest")
    }
}
