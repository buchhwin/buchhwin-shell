import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/overview/OverviewLogic.js" as O

ShellRoot {
    Component.onCompleted: {
        const monitors = [
            { id: 0, name: "eDP-1", x: 0, y: 0, width: 2880, height: 1800, scale: 1.5, transform: 0, focused: true, activeWorkspace: { id: 1 } },
            { id: 1, name: "DP-1", x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 1, focused: false, activeWorkspace: { id: 3 } }
        ]
        const clients = [
            { address: "0xa", title: "Brave", class: "brave-browser", at: [0, 0], size: [960, 1200], workspace: { id: 1, name: "1" }, monitor: 0, focusHistoryID: 1 },
            { address: "0xb", title: "Kitty", class: "kitty", at: [960, 600], size: [960, 600], workspace: { id: 1, name: "1" }, monitor: 0, focusHistoryID: 0 },
            { address: "0xc", title: "Notes", class: "org.kde.kate", at: [1920, 0], size: [1920, 1080], workspace: { id: 3, name: "3" }, monitor: 1, focusHistoryID: 2 },
            { address: "0xd", title: "Scratch", class: "x", at: [0, 0], size: [10, 10], workspace: { id: -98, name: "special" }, monitor: 0 },
            { address: "0xe", title: "Hidden", class: "x", at: [0, 0], size: [10, 10], workspace: { id: 1, name: "1" }, monitor: 0, hidden: true },
            { address: "0xf", title: "", class: "xwaylandvideobridge", at: [0, 0], size: [1896, 1138], workspace: { id: 1, name: "1" }, monitor: 0, focusHistoryID: 3 }
        ]
        const workspaces = [{ id: 1, name: "1", monitorID: 0 }, { id: 2, name: "2", monitorID: 0 }, { id: 3, name: "3", monitorID: 1 }]
        const model = O.build(clients, monitors, workspaces)
        T.eq(model.map(w => w.id), [1, 2, 3], "regular workspaces sorted, special skipped")
        T.eq(model[0].windows.map(w => w.title), ["Brave", "Kitty"], "hidden and helper windows skipped, most recent on top")
        T.eq([model[0].windows[1].x, model[0].windows[1].y, model[0].windows[1].width], [0.5, 0.5, 0.5], "positions relative to the logical monitor")
        T.near(model[2].aspect, 1920 / 1080, "rotated monitor aspect", 1e-9)
        T.eq([model[0].active, model[1].active, model[2].active], [true, false, true], "active workspaces per monitor")
        T.eq(model[2].monitor, "DP-1", "monitor name")
        T.eq(O.flatWindows(model, "").map(w => w.title), ["Brave", "Kitty", "Notes"], "reading order")
        T.eq(O.flatWindows(model, "KATE").map(w => w.title), ["Notes"], "search matches class case-insensitively")
        T.eq(O.nextFreeWorkspace(model), 4, "next free workspace")
        T.eq(O.nextFreeWorkspace(O.build([], monitors, [{ id: 2, monitorID: 0 }])), 1, "gaps are reused")
        T.eq(O.normalizeAddress("0xABC"), "abc", "address normalisation")
        // ---- no gaps, the same rule the indicator uses --------------------

        // The overview built from Hyprland's own answer has the same hole the
        // indicator had: a workspace with no windows left does not exist.
        const holedClients = [
            { address: "0x1", title: "a", class: "a", workspace: { id: 1, name: "1" }, monitor: 0,
              at: [0, 0], size: [100, 100], mapped: true },
            { address: "0x2", title: "b", class: "b", workspace: { id: 3, name: "3" }, monitor: 0,
              at: [0, 0], size: [100, 100], mapped: true }
        ]
        const screens = [{ id: 0, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0,
                           activeWorkspace: { id: 1 } }]
        const spaces = [{ id: 1, name: "1", monitorID: 0 }, { id: 3, name: "3", monitorID: 0 }]

        const withHole = O.build(holedClients, screens, spaces, "open", 5)
        T.eq(withHole.map(item => item.id), [1, 3], "in Open the overview shows what exists, hole and all")

        const filled = O.build(holedClients, screens, spaces, "gapless", 5)
        T.eq(filled.map(item => item.id), [1, 2, 3], "No gaps puts the missing workspace back")
        T.eq(filled[1].windows.length, 0, "and it is empty, which is the truth")
        T.eq(filled[1].monitor, "DP-1", "on the focused monitor, because a workspace that does not exist has none")

        // The mode the user was actually on, and the one the first go at this
        // missed entirely: the pill showed 1 to 4 with the empty ones dimmed
        // and the overview showed 1 and 3.
        const fixed = O.build(holedClients, screens, spaces, "fixed", 4)
        T.eq(fixed.map(item => item.id), [1, 2, 3, 4], "Fixed shows the slots, the way the pill does")
        T.eq(fixed.filter(item => item.windows.length).map(item => item.id), [1, 3],
             "and only the two that have anything on them have windows")
        T.eq(O.build(holedClients, screens, spaces, "fixed", 2).map(item => item.id), [1, 2, 3],
             "a workspace past the count still shows, because it is really there")
        T.eq(O.build([], screens, [], "fixed", 3).map(item => item.id), [1, 2, 3],
             "an empty desktop in Fixed is still the slots")
        T.eq(O.build([], screens, [], "open", 3).length, 0, "and in Open it is nothing")

        // An unknown mode is Open, the same fallback the indicator has, so a
        // settings file from before this still shows something sensible.
        T.eq(O.build(holedClients, screens, spaces, "nonsense", 5).map(item => item.id), [1, 3],
             "an unknown mode shows what exists")

        // ---- gathered by monitor -----------------------------------------
        //
        // One flow of every workspace of every monitor is unreadable the
        // moment there is more than one screen, and with blocks it can be
        // twenty-seven cards. The rows follow the monitor order the Displays
        // page uses, with the screen the overview opened on first.
        const three = [
            { id: 0, name: "DP-8", x: 0, y: 0, width: 3840, height: 2160, scale: 1.5, transform: 0, focused: false, activeWorkspace: { id: 1 } },
            { id: 1, name: "DP-10", x: 2560, y: 0, width: 3840, height: 2160, scale: 1.5, transform: 0, focused: true, activeWorkspace: { id: 11 } },
            { id: 2, name: "DP-13", x: 5120, y: 0, width: 1920, height: 1080, scale: 1, transform: 3, focused: false, activeWorkspace: { id: 21 } }
        ]
        const spread = O.build([], three,
            [{ id: 1, name: "1", monitorID: 0 }, { id: 11, name: "11", monitorID: 1 }, { id: 21, name: "21", monitorID: 2 }],
            "fixed", 2, true)
        T.eq(spread.map(w => w.id), [1, 2, 11, 12, 21, 22], "each monitor's own block is filled in, on that monitor")
        T.eq(spread.map(w => w.monitor), ["DP-8", "DP-8", "DP-10", "DP-10", "DP-13", "DP-13"],
             "and the filled-in ones do not all land on the focused screen")
        T.eq(spread.map(w => w.label), ["1", "2", "1", "2", "1", "2"], "labelled as each monitor's own")

        const rows = O.groups(spread, three)
        T.eq(rows.map(row => row.monitor), ["DP-10", "DP-8", "DP-13"], "the focused screen first, the rest in order")
        T.eq(rows.map(row => row.number), [2, 1, 3], "but each keeps the number the Displays page gives it")
        T.eq(rows.map(row => row.workspaces.map(w => w.id)), [[11, 12], [1, 2], [21, 22]], "each row its own")
        T.near(rows[2].aspect, 1920 / 1080, "a rotated screen's row gets its own shape", 1e-9)
        T.near(rows[0].aspect, 2160 / 3840, "and a landscape one gets its", 1e-9)

        // A workspace on a monitor the list does not know keeps a row rather
        // than vanishing from the overview.
        const stray = O.build([], three, [{ id: 5, name: "5", monitorID: 9 }], "open", 2, true)
        T.eq(O.groups(stray, three).length >= 1, true, "an unknown monitor still produces rows")
        T.eq(O.groups([{ id: 5, monitor: "GONE", windows: [] }], three).map(row => row.monitor),
             ["DP-10", "DP-8", "DP-13", ""], "and the homeless one is last, not lost")

        // Without blocks nothing changes: one row per monitor, global numbers.
        const flat = O.build([], three, [{ id: 1, name: "1", monitorID: 0 }, { id: 3, name: "3", monitorID: 1 }], "open", 2, false)
        T.eq(flat.map(w => w.label), ["1", "3"], "no blocks, no relabelling")

        T.finish("OverviewTest")
    }
}
