import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dock/MinimizeLogic.js" as M
import "../../services/dock/DockLogic.js" as D
import "../../services/hypr/HiddenWindows.js" as H
import "../../services/overview/OverviewLogic.js" as O
import "../../services/switcher/SwitcherLogic.js" as S
import "../../shell/overview/SelectionLogic.js" as Sel

// Minimized windows (services/dock/MinimizeLogic.js, services/MinimizeService.qml):
// where one goes and comes back to, what Hyprland is told in both dialects,
// which of an app's own requests count, and that the dock, the overview and
// Alt+Tab all list them - a window on a special workspace that nothing lists
// is lost to the user.
ShellRoot {
    function win(address, workspace, name, extra) {
        return Object.assign({ address: address, appClass: "code", workspace: workspace, workspaceName: name }, extra || {})
    }

    Component.onCompleted: {
        // ---- the workspaces -------------------------------------------------------------
        T.eq([M.parkName(3), M.parkName(23), M.parkName(0), M.parkName(-98), M.parkName("x")],
             ["special:buchhwin-minimized-3", "special:buchhwin-minimized-23", "special:buchhwin-minimized",
              "special:buchhwin-minimized", "special:buchhwin-minimized"], "one special workspace per workspace it came from")
        T.eq([M.isParked("special:buchhwin-minimized-3"), M.isParked("special:buchhwin-minimized"),
              M.isParked("special:buchhwin-minimizedx"), M.isParked("special:term"), M.isParked("3"), M.isParked("")],
             [true, true, false, false, false, false], "only its own names are minimized")
        T.ok(!M.isParked(H.workspace), "the hidden helpers' special workspace is never one of them")
        T.eq([M.originOf("special:buchhwin-minimized-3"), M.originOf("special:buchhwin-minimized"),
              M.originOf("special:buchhwin-minimized-03"), M.originOf("3")], [3, 0, 0, 0], "the workspace it goes back to")
        T.eq([M.parkedLabel("special:buchhwin-minimized-3"), M.parkedLabel("special:buchhwin-minimized")],
             ["Minimized · Workspace 3", "Minimized"], "where the menu and the overview say it is")

        // ---- which windows ------------------------------------------------------------------
        T.eq([M.addressOf("0xABC"), M.addressOf("abc"), M.addressOf(""), M.addressOf("0xzz")], ["0xabc", "0xabc", "", ""],
             "addresses with their prefix, lowered")
        T.ok(M.canMinimize(win("0x1", 2, "2")), "a window on a workspace")
        T.ok(!M.canMinimize(win("0x1", 2, "2", { appClass: "xwaylandvideobridge" })), "never a hidden helper")
        T.ok(!M.canMinimize(win("0x1", -99, H.workspace)), "nor one on the helpers' workspace")
        T.ok(!M.canMinimize(win("0x1", -97, "special:buchhwin-minimized-2")), "nor one minimized already")
        T.ok(!M.canMinimize(win("0x1", 2, "2", { pinned: true })), "nor one pinned to every workspace")
        T.ok(!M.canMinimize(win("0x1", -98, "special:buchhwin-dropdown")) && !M.canMinimize(win("0x1", -99, "special:scratch"))
             && !M.canMinimize(win("0x1", -99, "special")),
             "nor one on a special workspace: the drop-down terminal and a scratchpad have their own key")
        T.ok(M.canMinimize(win("0x1", -1337, "music")), "a named workspace's window can (it comes back to the one in front)")
        T.ok(!M.canMinimize(win("", 2, "2")) && !M.canMinimize(null), "nor nothing")
        T.eq([M.originFor(win("0x1", 4, "4")), M.originFor(win("0x1", -98, "special:term")), M.originFor(win("0x1", -1337, "music"))],
             [4, 0, 0], "minimized from a numbered workspace, or from one without a number")
        T.eq([M.restoreTarget(win("0x1", -97, "special:buchhwin-minimized-4"), 2),
              M.restoreTarget(win("0x1", -97, "special:buchhwin-minimized"), 2),
              M.restoreTarget(win("0x1", -97, "special:buchhwin-minimized"), 0)], [4, 2, 1],
             "back to its own workspace, else the one in front, else the first")

        const parked = [win("0xa", -97, "special:buchhwin-minimized-1"), win("0xb", 2, "2"),
                        win("0xc", -96, "special:buchhwin-minimized-2"), win("0xd", -95, "special:buchhwin-minimized-3")]
        T.eq(M.parked(parked, {}).map(w => w.address), ["0xa", "0xc", "0xd"], "the minimized ones, in the order given")
        T.eq(M.parked(parked, { "0xc": 200, "0xa": 100 }).map(w => w.address), ["0xc", "0xa", "0xd"],
             "minimized last first, the ones from before the shell after them")
        T.eq([M.lastParked(parked, { "0xc": 200, "0xa": 100 }), M.lastParked([win("0xb", 2, "2")], {})], ["0xc", ""],
             "Super+Shift+H brings back the one minimized last")
        T.eq([M.inFront(win("0x1", 2, "2"), 2), M.inFront(win("0x1", 1, "1"), 2), M.inFront(win("0x1", -98, "special:term"), 2),
              M.inFront(win("0x1", 1, "1", { pinned: true }), 2), M.inFront(win("0x1", -97, "special:buchhwin-minimized-2"), 2)],
             [true, false, true, true, false],
             "in front: on the focused workspace, a scratchpad, pinned - never the last window Quickshell remembers, nor a minimized one")

        // ---- what Hyprland is told ------------------------------------------------------------
        T.eq(M.minimizeCommand("0xabc", 3), {
            legacy: "movetoworkspacesilent special:buchhwin-minimized-3,address:0xabc",
            lua: "hl.dsp.window.move({ workspace = \"special:buchhwin-minimized-3\", window = \"address:0xabc\", follow = false })"
        }, "minimized: to its special workspace, without the focus, in both dialects")
        T.throwsError(() => M.minimizeCommand("abc", 3), "never a window address that is not one")
        T.eq(M.restorePlan("0xabc", 3, true), [
            { legacy: "movetoworkspacesilent 3,address:0xabc",
              lua: "hl.dsp.window.move({ workspace = 3, window = \"address:0xabc\", follow = false })" },
            { legacy: "focuswindow address:0xabc", lua: "hl.dsp.focus({ window = \"address:0xabc\" })" }
        ], "restored: back first, then to the front, in one request")
        T.eq(M.restorePlan("0xabc", 3, false).length, 1, "or back without the focus")
        T.eq(M.restoreAllPlan(parked, 5).map(command => command.legacy),
             ["movetoworkspacesilent 1,address:0xa", "movetoworkspacesilent 2,address:0xc", "movetoworkspacesilent 3,address:0xd"],
             "at the start: every minimized window back where it came from, the others left alone")
        T.eq(M.restoreAllPlan([win("0xe", -97, "special:buchhwin-minimized")], 5)[0].legacy, "movetoworkspacesilent 5,address:0xe",
             "one with no workspace of its own to the one in front")
        T.eq(M.restoreAllPlan([win("0xf", -99, H.workspace, { appClass: "xwaylandvideobridge" })], 5), [],
             "the hidden helpers stay hidden")
        const client = M.fromClient({ address: "0xAB", class: "", initialClass: "Wfica", workspace: { id: -97, name: "special:buchhwin-minimized-2" },
                                      pinned: false, title: "T", focusHistoryID: 3 })
        T.eq([client.address, client.appClass, client.workspace, client.workspaceName, client.focusOrder],
             ["0xab", "Wfica", -97, "special:buchhwin-minimized-2", 3], "a client of hyprctl as a window")

        // ---- an app's own minimize button -------------------------------------------------------
        T.eq(M.parseRequest("55d0c8f0a2c0,1"), { address: "0x55d0c8f0a2c0", minimized: true }, "minimized>>ADDRESS,1")
        T.eq(M.parseRequest("0x55d0,0"), { address: "0x55d0", minimized: false }, "and back")
        T.eq([M.parseRequest(""), M.parseRequest("x,1"), M.parseRequest("55d0,2"), M.parseRequest("55d0")], [null, null, null, null],
             "anything else is no request")
        const vscode = win("0x5", 2, "2", { appClass: "code" })
        const ask = M.parseRequest("5,1")
        T.eq(M.requestAction(ask, { enabled: true, window: vscode, activeAddress: "0x5", activeClass: "code" }), "minimize",
             "the window in front asks: minimized")
        T.eq(M.requestAction(ask, { enabled: true, window: vscode, activeAddress: "0x9", activeClass: "Code" }), "minimize",
             "a window of the app in front asks (a toolbar of its own has the focus): minimized")
        T.eq(M.requestAction(ask, { enabled: true, window: vscode, activeAddress: "0x9", activeClass: "firefox" }), "none",
             "a window behind another app asks - a game minimizing itself after Alt+Tab: no")
        T.eq(M.requestAction(ask, { enabled: false, window: vscode, activeAddress: "0x5", activeClass: "code" }), "none",
             "the setting off: no")
        T.eq(M.requestAction(ask, { enabled: true, window: vscode, activeAddress: "0x5", activeClass: "code", panelOpen: true }), "none",
             "a panel of the shell's holds the keyboard - a game minimizing itself under Alt+Tab or the launcher: no")
        T.eq(M.requestAction(ask, { enabled: true, window: win("0x5", -98, "special:buchhwin-dropdown"), activeAddress: "0x5" }), "none",
             "a window on a special workspace: no")
        T.eq(M.requestAction(M.parseRequest("5,0"), { enabled: true, window: win("0x5", -97, "special:buchhwin-minimized-2"), panelOpen: true }),
             "restore", "coming back is never held up by a panel")
        T.eq(M.requestAction(ask, { enabled: true, window: null, activeAddress: "0x5" }), "none", "a window not known: no")
        T.eq(M.requestAction(ask, { enabled: true, window: win("0x5", 2, "2", { appClass: "xwaylandvideobridge" }), activeAddress: "0x5" }),
             "none", "a hidden helper: no")
        T.eq(M.requestAction(M.parseRequest("5,0"), { enabled: false, window: win("0x5", -97, "special:buchhwin-minimized-2") }), "restore",
             "a minimized window that asks to come back always may")
        T.eq(M.requestAction(M.parseRequest("5,0"), { enabled: true, window: vscode }), "none", "one that is not minimized has nothing to come back from")
        T.eq([M.openedParked("special:buchhwin-minimized-3,eDP-1"), M.openedParked("special:term,eDP-1"), M.openedParked(",eDP-1"),
              M.openedParked("")], ["special:buchhwin-minimized-3", "", "", ""],
             "a minimized window's special workspace opened over the screen: its windows come back")

        // ---- the dock ---------------------------------------------------------------------------
        const look = cls => cls === "code" ? { id: "code", name: "Code" } : null
        const items = D.build([], [{ address: "0x1", appClass: "code", seq: 1, workspace: 2, workspaceName: "2" },
                                   { address: "0x2", appClass: "code", seq: 2, workspace: -97, workspaceName: "special:buchhwin-minimized-2" }], look)
        T.eq(items.length, 1, "a minimized window stays on the dock with its app")
        T.eq([items[0].windows.map(w => w.minimized), items[0].minimized, items[0].count], [[false, true], 1, 2],
             "each window says whether it is minimized")
        T.eq(D.frontAddress({ address: "0x2", workspace: -97, parked: true }, 2), "",
             "a minimized window is never the one in front (Quickshell keeps it as the active one)")
        T.eq(D.frontAddress({ address: "0x2", workspace: -98 }, 2), "0x2", "a scratchpad's still is")
        const app = items[0]
        T.eq(D.clickPlan(app, "", [], "cycle"), { action: "focus", address: "0x1" }, "not in front: the window used first, as before")
        T.eq(D.clickPlan(app, "", ["0x2"], "cycle"), { action: "restore", address: "0x2" },
             "the window used last is minimized: it comes back rather than its special workspace opening")
        T.eq(D.clickPlan(app, "0x1", ["0x1"], "cycle"), { action: "restore", address: "0x2" }, "in front: the next window, brought back")
        T.eq(D.clickPlan(app, "0x1", ["0x1"], "minimize"), { action: "minimize", address: "0x1" },
             "in front, on a taskbar that minimizes: the window in front is minimized")
        T.eq(D.clickPlan({ entryId: "code", windows: [{ address: "0x1" }] }, "0x1", [], "cycle"), { action: "none", address: "" },
             "one window in front, cycling: nothing, as before")
        const dropdown = { entryId: "dd", windows: [{ address: "0x7", appClass: "buchhwin-dropdown", workspace: -98, workspaceName: "special:buchhwin-dropdown" }] }
        T.eq(D.clickPlan(dropdown, "0x7", ["0x7"], "minimize"), D.clickTarget(dropdown, "0x7", ["0x7"]),
             "a window that cannot be minimized (the drop-down terminal): the click it always was")
        T.eq(D.menuRows(dropdown, [], false, 6, [], { minimize: true }).map(row => row.kind).filter(kind => kind === "minimize"), [],
             "and its menu offers no minimize")
        T.eq(D.clickPlan({ entryId: "code", windows: [] }, "", [], "minimize"), { action: "launch", address: "" }, "nothing open: start it")
        T.eq(D.dotStates(app, true, false, false, 3), ["window", "minimized"], "a hollow dot for the minimized window")
        T.eq(D.dotStates(app, true, true, false, 3), ["active"], "the app in front: the bar")
        T.eq(D.dotStates({ windows: [] }, false, false, true, 3), ["launching"], "starting: one faint dot")
        T.eq(D.dotStates({ windows: [] }, true, false, false, 3), ["window"], "running without windows (Settings): one dot")
        T.eq(D.dotStates({ windows: [] }, false, false, false, 3), [], "nothing")
        T.eq(D.dotStates({ windows: [{}, {}, {}, {}, {}] }, true, false, false, 3).length, 3, "at most three")
        T.eq(D.menuRows(app, [], false, 6, [], { minimize: true }).map(row => row.kind),
             ["window", "window", "minimize", "restore", "new", "pin", "close"], "the menu minimizes and restores")
        T.eq(D.menuRows(app, [], false, 6, [], { minimize: true })[1].minimized, true, "and says which window is minimized")
        T.ok(D.menuRows(app, [], false, 6, [], { minimize: true })[0].minimized === undefined, "and only that one")
        T.eq(D.menuRows(app, [], false, 6, []).map(row => row.kind), ["window", "window", "new", "pin", "close"],
             "without the option, the rows as they were")
        T.eq(D.workspaceLabel(-97, "special:buchhwin-minimized-2"), "Minimized · Workspace 2", "the window row says where it goes back to")
        T.eq([D.optionValue("activeClick", "minimize"), D.optionValue("activeClick", "cycle"), D.optionValue("activeClick", "close")],
             ["minimize", "cycle", null], "dock setOption activeClick")

        // ---- the overview, Alt+Tab ------------------------------------------------------------------
        const clients = [
            { address: "0xa", title: "Editor", class: "code", workspace: { id: 2, name: "2" }, at: [0, 0], size: [10, 10], monitor: 0, focusHistoryID: 0 },
            { address: "0xb", title: "Teams", class: "crx_x", workspace: { id: -97, name: "special:buchhwin-minimized-3" }, at: [0, 0], size: [10, 10], monitor: 0, focusHistoryID: 1 },
            { address: "0xc", title: "Old", class: "foot", workspace: { id: -96, name: "special:buchhwin-minimized" }, at: [0, 0], size: [10, 10], monitor: 0, focusHistoryID: 4 },
            { address: "0xd", title: "", class: "xwaylandvideobridge", workspace: { id: -99, name: H.workspace }, monitor: 0, focusHistoryID: 2 },
            { address: "0xe", title: "Scratch", class: "x", workspace: { id: -98, name: "special:scratch" }, monitor: 0, focusHistoryID: 3 }
        ]
        const monitors = [{ id: 0, name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200, scale: 1, transform: 0, focused: true, activeWorkspace: { id: 2 } }]
        const minimized = O.minimizedWindows(clients)
        T.eq(minimized.map(w => [w.address, w.origin, w.label]), [["0xb", 3, "Workspace 3"], ["0xc", 0, ""]],
             "the overview lists the minimized windows, used last first - not the helpers, not a scratchpad")
        T.eq(O.build(clients, monitors, [{ id: 2, name: "2", monitorID: 0 }], "open", 5, false).map(w => w.id), [2],
             "and no card for their special workspaces")
        const rows = O.groups(O.build(clients, monitors, [{ id: 2, name: "2", monitorID: 0 }], "open", 5, false), monitors, false)
        const stops = Sel.stops(rows, "", minimized)
        T.eq(stops.map(stop => stop.kind), ["window", "card", "new", "minimized", "minimized"], "the keys reach them after the cards")
        T.eq(Sel.stops(rows, "tea", minimized).map(stop => stop.key), ["m:0xb"], "a search finds them too")
        T.eq(Sel.stops(rows, "").map(stop => stop.kind), ["window", "card", "new"], "without them, the stops as they were")
        T.eq(Sel.vertical(stops, 2, 1, 4), 3, "Down from the last line of cards reaches them")
        T.eq(Sel.vertical(stops, 3, -1, 4), 2, "and Up goes back")
        const switcher = S.build(clients)
        T.eq(switcher.map(w => w.address), ["0xa", "0xe", "0xb", "0xc"], "Alt+Tab lists them last: a quick Alt+Tab does not bring back what was just minimized")
        T.eq(switcher.map(w => [w.minimized, w.workspaceName]), [[false, "2"], [false, "scratch"], [true, "Minimized"], [true, "Minimized"]],
             "with a badge that says so")
        T.eq(S.openIndex(switcher, "0xa", 1), 1, "the first Alt+Tab still goes to the window used before")

        T.finish("MinimizeTest")
    }
}
