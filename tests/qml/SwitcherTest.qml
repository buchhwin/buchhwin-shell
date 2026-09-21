import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/switcher/SwitcherLogic.js" as S

ShellRoot {
    Component.onCompleted: {
        const clients = [
            { address: "0xc", title: "Notes", class: "org.kde.kate", workspace: { id: 3, name: "3" }, size: [800, 600], focusHistoryID: 2 },
            { address: "0xa", title: "Brave", class: "brave-browser", workspace: { id: 1, name: "1" }, size: [960, 1200], focusHistoryID: 0 },
            { address: "0xb", title: "", class: "", initialClass: "kitty", workspace: { id: 1, name: "1" }, focusHistoryID: 1 },
            { address: "0xd", title: "Scratch", class: "x", workspace: { id: -98, name: "special:scratch" }, focusHistoryID: 3 },
            { address: "0xe", title: "Hidden", class: "x", workspace: { id: 1, name: "1" }, hidden: true, focusHistoryID: 4 },
            { address: "0xf", title: "Unmapped", class: "x", workspace: { id: 1, name: "1" }, mapped: false, focusHistoryID: 5 },
            { address: "0x9", title: "No history", class: "y", workspace: { id: 2, name: "2" } },
            { address: "0x10", title: "", class: "xwaylandvideobridge", workspace: { id: -99, name: "special:buchhwin-hidden" }, focusHistoryID: 6 },
            { address: "0x11", title: "", class: "xwaylandvideobridge", workspace: { id: 1, name: "1" }, focusHistoryID: 7 }
        ]
        const windows = S.build(clients)
        T.eq(windows.map(w => w.address), ["0xa", "0xb", "0xc", "0xd", "0x9"], "most recently used first, hidden, unmapped and helper windows skipped, no history last")
        T.eq(windows[1].appClass, "kitty", "initial class when the class is empty")
        T.eq(windows[1].title, "", "windows without a title are kept")
        T.eq([windows[0].width, windows[0].height, windows[1].width], [960, 1200, 0], "window size")
        T.eq(windows.map(w => w.workspaceName), ["1", "1", "3", "scratch", "2"], "workspace badges")

        T.eq(S.openIndex(windows, "0xa", 1), 1, "first Alt+Tab selects the previously used window")
        T.eq(S.openIndex(windows, "", 1), 0, "without a focused window the last used one is selected")
        T.eq(S.openIndex(windows, "0xa", -1), 4, "Alt+Shift+Tab starts at the least recently used window")
        T.eq(S.selection(windows, "0xa", 1, 1), 2, "second Tab moves on")
        T.eq(S.selection(windows, "0xa", 1, 4), 0, "Tab wraps around to the start")
        T.eq(S.selection(windows, "0xa", 1, -2), 4, "Shift+Tab wraps around to the end")
        T.eq(S.selection(windows, "0xa", -1, 1), 0, "backward start then forward wraps")

        const single = S.build([clients[1]])
        T.eq([S.openIndex(single, "0xa", 1), S.selection(single, "0xa", 1, 3), S.selection(single, "0xa", -1, -1)], [0, 0, 0], "single window stays selected")
        T.eq([S.openIndex([], "", 1), S.selection([], "", 1, 2)], [-1, -1], "no windows")
        T.eq(S.build(null), [], "missing client list")
        T.eq(S.wrap(-1, 3), 2, "wrap negative")
        T.eq(S.normalizeAddress("0xABC"), "abc", "address normalisation")
        T.finish("SwitcherTest")
    }
}
