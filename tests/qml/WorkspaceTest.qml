import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/workspaces/WorkspaceLogic.js" as W

ShellRoot {
    Component.onCompleted: {
        const ids = list => list.map(item => item.id)
        // Windows on 2 and 7, focused 2, all on DP-1; special workspace ignored.
        const spaces = [
            { id: 7, name: "7", windows: 1, screen: "DP-1" },
            { id: 2, name: "2", windows: 3, screen: "DP-1" },
            { id: -98, name: "special:magic", windows: 1, screen: "DP-1" }
        ]

        // Settings values
        T.eq(W.normalizeMode("fixed"), "fixed", "fixed mode")
        T.eq(W.normalizeMode("bogus"), "open", "unknown mode falls back to open")
        T.eq(W.normalizeCount(8), 8, "count kept")
        T.eq(W.normalizeCount(0), 1, "count at least 1")
        T.eq(W.normalizeCount(42), 10, "count at most 10")
        T.eq(W.normalizeCount(4.6), 5, "count rounded")
        T.eq(W.normalizeCount("x"), 5, "invalid count uses default")

        // Open mode
        const open = W.entries("open", 5, spaces, "DP-1", 2)
        T.eq(ids(open), [2, 7], "open shows existing workspaces sorted")
        T.eq(open.map(item => item.active), [true, false], "focused one active")
        T.eq(open.map(item => item.occupied), [true, true], "both occupied")
        T.eq(W.entries("open", 5, spaces, "HDMI-A-1", 2), [{ id: 1, name: "1", label: "1", stray: false, active: false, focused: false, occupied: false }], "other screen without workspaces: placeholder 1")
        T.eq(W.entries("open", 5, [], "DP-1", -1), [{ id: 1, name: "1", label: "1", stray: false, active: true, focused: false, occupied: false }], "startup placeholder")
        const emptyActive = W.entries("open", 5, spaces.concat([{ id: 4, name: "4", windows: 0, screen: "DP-1" }]), "DP-1", 4)
        T.eq(emptyActive.map(item => [item.id, item.active, item.occupied]), [[2, false, true], [4, true, false], [7, false, true]], "active empty workspace")

        // Fixed mode
        const five = W.entries("fixed", 5, spaces, "DP-1", 2)
        T.eq(ids(five), [1, 2, 3, 4, 5, 7], "fixed 5 keeps occupied 7 after the slots")
        T.eq(five.map(item => item.occupied), [false, true, false, false, false, true], "empty slots dimmed")
        T.eq(five.filter(item => item.active).map(item => item.id), [2], "one active")
        T.eq(ids(W.entries("fixed", 8, spaces, "DP-1", 2)), [1, 2, 3, 4, 5, 6, 7, 8], "fixed 8 contains 7 once")
        T.eq(ids(W.entries("fixed", 3, spaces, "HDMI-A-1", 2)), [1, 2, 3], "workspaces above count only from this screen")
        const emptyFocus = W.entries("fixed", 5, [{ id: 3, name: "3", windows: 0, screen: "DP-1" }], "DP-1", 3)
        T.eq(emptyFocus.map(item => [item.id, item.active, item.occupied]), [[1, false, false], [2, false, false], [3, true, false], [4, false, false], [5, false, false]], "switch to an empty slot")
        T.eq(ids(W.entries("fixed", 2, [{ id: 9, name: "9", windows: 0, screen: "DP-1" }], "DP-1", 9)), [1, 2, 9], "active above count stays visible")
        T.eq(W.entries("fixed", 2, [{ id: 1, name: "web", windows: 1, screen: "DP-1" }], "DP-1", 1)[0].name, "web", "named workspace keeps its name")
        T.eq(ids(W.entries("fixed", "bad", null, "DP-1", -1)), [1, 2, 3, 4, 5], "defaults with broken input")
        T.eq(W.entries("fixed", 2, [], "DP-1", -1).map(item => item.active), [false, false], "no focus known: nothing active in fixed mode")
        // ---- no gaps ----------------------------------------------------

        // The complaint: windows on 1 and 3, nothing on 2, and the row becomes
        // "1 3" - so the workspace you were about to switch back to is not
        // there to click, and every number after it has moved.
        const holed = [{ id: 1, name: "1", windows: 2, screen: "DP-1" },
                       { id: 3, name: "3", windows: 1, screen: "DP-1" }]
        T.eq(ids(W.entries("open", 5, holed, "DP-1", 1)), [1, 3], "open mode shows the hole")
        T.eq(ids(W.entries("gapless", 5, holed, "DP-1", 1)), [1, 2, 3], "no gaps fills it back in")
        T.eq(W.entries("gapless", 5, holed, "DP-1", 1).map(item => item.occupied), [true, false, true],
             "and the filled-in one is empty, not pretending otherwise")
        T.eq(W.entries("gapless", 5, holed, "DP-1", 1)[1].name, "2", "an invented workspace is named after its number")

        // Two holes at once, which is the other half of what was asked for.
        const wide = [{ id: 1, name: "1", windows: 1, screen: "DP-1" },
                      { id: 4, name: "4", windows: 1, screen: "DP-1" }]
        T.eq(ids(W.entries("gapless", 5, wide, "DP-1", 1)), [1, 2, 3, 4], "both between 1 and 4")

        // Only between. An empty workspace after the last occupied one is the
        // *next* one, which belongs to whatever offers a new workspace.
        T.eq(ids(W.entries("gapless", 5, [{ id: 2, name: "2", windows: 1, screen: "DP-1" }], "DP-1", 2)), [2],
             "one workspace has no gaps, and does not grow a 1 in front of it")
        T.eq(ids(W.entries("gapless", 5, [{ id: 3, name: "3", windows: 1, screen: "DP-1" },
                                          { id: 5, name: "5", windows: 1, screen: "DP-1" }], "DP-1", 3)), [3, 4, 5],
             "the span starts where the workspaces do, not at 1")

        // Per screen, like every other mode here.
        T.eq(ids(W.entries("gapless", 5, spaces, "HDMI-A-1", 2)), [1], "another screen's workspaces do not open holes on this one")

        // And the same edges the other modes have.
        T.eq(ids(W.entries("gapless", 5, [], "DP-1", -1)), [1], "nothing known yet still shows one")
        T.eq(ids(W.entries("gapless", 5, null, "DP-1", -1)), [1], "and so does nothing at all")
        T.eq(ids(W.entries("nonsense", 5, holed, "DP-1", 1)), [1, 3], "an unknown mode is Open, as it was")

        // ---- a workspace on its way out ---------------------------------

        // 1 → 2 → 3 with 2 empty: the shell hears 3 come and be shown ~2 ms
        // before it hears 2 go, and the row was "1 2 3" in between (nested
        // trace, round 13). An empty one its screen does not show is gone.
        const passing = [{ id: 1, name: "1", windows: 1, toplevels: 1, screen: "DP-1" },
                         { id: 2, name: "2", windows: 0, toplevels: 0, screen: "DP-1" },
                         { id: 3, name: "3", windows: 0, toplevels: 0, screen: "DP-1" }]
        T.eq(ids(W.entries("open", 5, passing, "DP-1", 3)), [1, 3], "the empty one left behind is not drawn")
        T.eq(ids(W.entries("open", 5, passing, "DP-1", 2)), [1, 2], "nor the empty one not shown yet")
        T.eq(ids(W.entries("gapless", 5, passing, "DP-1", 3)), [1, 2, 3], "no gaps still fills the hole it leaves")
        T.eq(ids(W.entries("fixed", 2, passing, "DP-1", 2)), [1, 2], "fixed: an empty one above the count is not drawn")
        T.eq(ids(W.entries("open", 5, passing, "DP-1", -1)), [1, 2, 3], "nothing shown known yet: everything stays")
        T.eq(ids(W.entries("open", 5, passing.map(item => Object.assign({}, item, { toplevels: undefined })), "DP-1", 3)), [1, 2, 3],
             "without a window count everything stays, as before")
        T.eq(ids(W.entries("open", 5, [{ id: 1, name: "1", windows: 1, toplevels: 1, screen: "DP-1" },
                                       { id: 4, name: "4", windows: 0, toplevels: 1, screen: "DP-1" }], "DP-1", 1)), [1, 4],
             "a hidden helper's window keeps a workspace that the row counts as empty")
        T.eq(ids(W.entries("open", 5, passing.map(item => Object.assign({}, item, { kept: true })), "DP-1", 3)), [1, 2, 3],
             "one held open stays, empty and not shown")
        T.eq([W.leaving(null, 3), W.leaving({ id: 2, toplevels: 0 }, "x"), W.leaving({ id: 2, toplevels: "0" }, 3)],
             [false, false, true], "leaving: no workspace, an unknown active one, a count as text")

        // ---- held open, and closed again ---------------------------------

        T.eq([W.closeTarget([1, 2, 3], 2), W.closeTarget([3, 1, 2], 1), W.closeTarget([1, 3], 3)], [1, 2, 1],
             "the one before it on its monitor, else the one after")
        T.eq([W.closeTarget([1], 1), W.closeTarget([1, 2], 5), W.closeTarget(null, 1)], [-1, -1, -1],
             "the only one, one not there, nothing known: nothing to close into")
        T.eq(W.closeTarget([11, 12, 12, -98], 12), 11, "duplicates and special workspaces are not neighbours")
        // What is held open: with the monitor each one is on, so the rule
        // never moves it - a nested run without that had 670 workspaces.
        const standing = [{ id: 1, monitor: "DP-3" }, { id: 2, monitor: "DP-3" }, { id: 12, monitor: "DP-1" },
                          { id: 3, monitor: "DP-1" }, { id: 5, monitor: "" }, { id: -98, monitor: "DP-3" }]
        T.eq(W.keepPlan(standing, {}, [], ["DP-3", "DP-1"], 30), { 1: "DP-3", 2: "DP-3", 12: "DP-1" },
             "each on its monitor; not 3 (the blocks are moving it), not one without a monitor, no special one")
        T.eq(W.keepPlan(standing, {}, [], [], 30), { 1: "DP-3", 2: "DP-3", 3: "DP-1", 12: "DP-1" },
             "without per-monitor blocks nothing is about to move")
        T.eq(W.keepPlan(standing, { 1: "DP-3", 12: "DP-3" }, [2], ["DP-3", "DP-1"], 30), { 12: "DP-1" },
             "one held already is not sent again, one moved since is, one being closed is not")
        T.eq(W.keepPlan(standing, { 1: "DP-3" }, [], [], 3), { 2: "DP-3", 3: "DP-1" }, "no more than the limit held")
        T.eq(W.keepPlan(standing, { 1: "DP-2" }, [], [], 1), { 1: "DP-3" }, "a moved one still gets its rule at the limit")
        T.eq([W.keepPlan(null, null, null, null, 5), W.keepPlan([{ id: 1, monitor: "A" }], {}, [], [], 0)], [{}, {}], "nothing to hold")
        T.eq([W.keepLimit(1), W.keepLimit(3), W.keepLimit(0), W.keepLimit("x")], [20, 40, 20, 20], "a block per monitor and one more")

        // ---- numbers, dots, or a dot for the active one -------------------

        const plain = { id: 2, name: "2", active: false }
        const here = { id: 2, name: "2", active: true }
        const named = { id: 2, name: "web", active: false }
        const namedHere = { id: 2, name: "web", active: true }

        T.eq([W.showsLabel("numbers", plain), W.showsLabel("numbers", here)], [true, true], "numbers writes every one")
        T.eq([W.showsLabel("dots", plain), W.showsLabel("dots", here)], [false, false], "dots writes none of them")
        T.eq([W.showsLabel("pills", plain), W.showsLabel("pills", here)], [false, false], "pills writes none of them either")
        T.eq([W.showsLabel("activeDot", plain), W.showsLabel("activeDot", here)], [true, false],
             "a dot for the one you are on, numbers for the ones you could go to")

        // A name somebody chose is not a number and is never thrown away: that
        // is the only thing that made naming a workspace worth doing.
        T.eq(W.showsLabel("dots", named), true, "a named workspace keeps its name even in dots")
        T.eq(W.showsLabel("pills", named), true, "and in pills")
        T.eq(W.showsLabel("activeDot", namedHere), true, "and even when it is the one you are on")

        T.eq(W.normalizeStyle("dots"), "dots", "a known style is itself")
        T.eq(W.normalizeStyle("pills"), "pills", "pills is a style")
        T.eq(W.normalizeStyle("sparkles"), "numbers", "an unknown one is numbers")
        T.eq(W.normalizeStyle(undefined), "numbers", "and so is none")
        T.eq(W.showsLabel("numbers", null), true, "no workspace at all is not a reason to hide a number")

        T.eq(W.spanIds([3, 1, 2]), [1, 2, 3], "the span does not care what order it is given")
        T.eq(W.spanIds([]), [], "no ids, no span")
        T.eq(W.spanIds(null), [], "and no list is no span")
        T.eq(W.spanIds([0, -1, 2]), [2], "special workspaces are not part of it")

        // ---- workspaces per monitor -------------------------------------

        // Numbered by position, left to right then top to bottom, because the
        // Displays page and the Identify overlay number them the same way -
        // monitor 1 has to be the same monitor everywhere.
        const screens = [{ name: "DP-2", x: 5120, y: 0 }, { name: "DP-3", x: 0, y: 240 },
                         { name: "DP-1", x: 2560, y: 240 }]
        T.eq(W.monitorOrder(screens), ["DP-3", "DP-1", "DP-2"], "left to right, whatever order they arrive in")
        T.eq(W.monitorOrder([{ name: "B", x: 0, y: 100 }, { name: "A", x: 0, y: 0 }]), ["A", "B"],
             "same column: top before bottom")
        T.eq(W.monitorOrder([{ name: "B", x: 0, y: 0 }, { name: "A", x: 0, y: 0 }]), ["A", "B"],
             "same place: by name, so the answer is at least stable")
        T.eq(W.monitorOrder(null), [], "nothing known yet")

        // What a reboot leaves: the compositor gave each monitor a workspace
        // before the rules were in. 3 and 4 belong to the first block.
        const order = ["DP-3", "DP-1", "DP-2"]
        const afterBoot = [
            { id: 1, monitor: "DP-3" }, { id: 3, monitor: "DP-1" }, { id: 4, monitor: "DP-2" },
            { id: 12, monitor: "DP-1" }, { id: -98, monitor: "DP-3" }
        ]
        T.eq(W.misplaced(order, afterBoot), [{ id: 3, monitor: "DP-3" }, { id: 4, monitor: "DP-3" }],
             "the workspaces on the wrong monitor, and where they go")
        T.eq(W.misplaced(order, [{ id: 12, monitor: "DP-1" }, { id: 21, monitor: "DP-2" }]), [],
             "nothing to move when every block sits on its monitor")
        T.eq(W.misplaced(["DP-3", "DP-2"], [{ id: 12, monitor: "DP-2" }, { id: 25, monitor: "DP-2" }]),
             [], "with a monitor gone its block follows the order, and a block beyond the monitors stays")
        T.eq(W.misplaced(["DP-3", "DP-2"], [{ id: 12, monitor: "DP-3" }]), [{ id: 12, monitor: "DP-2" }],
             "the second block belongs to whoever is second now")
        // After the moves: a monitor left showing a stranger (Hyprland filled
        // it with the next free number) goes to one of its own.
        T.eq(W.homes(order, [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 12 }],
                     [{ monitor: "DP-3", id: 1 }, { monitor: "DP-1", id: 12 }, { monitor: "DP-2", id: 2 }]),
             [{ monitor: "DP-2", id: 21 }], "the third screen showing 2 goes to 21")
        T.eq(W.homes(order, [{ id: 1 }, { id: 14 }, { id: 12 }],
                     [{ monitor: "DP-1", id: 3 }]),
             [{ monitor: "DP-1", id: 12 }], "to the lowest of its own that exists")
        T.eq(W.homes(order, [], [{ monitor: "DP-3", id: 4 }, { monitor: "DP-1", id: 15 }, { monitor: "HDMI-1", id: 2 }]), [],
             "nothing to do when every screen shows its own, and an unknown screen is left alone")
        // Undocked: Hyprland hands the gone monitor's block to the laptop
        // with its ids. Those are strays to visit, not mistakes: the screen
        // showing 12 stays there (it was sent home 400 ms after the next
        // workspace came or went), just as `misplaced` leaves 11 and 12 alone.
        const undocked = [{ id: 3, monitor: "eDP-1" }, { id: 11, monitor: "eDP-1" }, { id: 12, monitor: "eDP-1" }]
        T.eq(W.homes(["eDP-1"], undocked, [{ monitor: "eDP-1", id: 12 }]), [], "a workspace from a gone monitor's block is stayed on")
        T.eq(W.misplaced(["eDP-1"], undocked), [], "and nothing moves it either")
        T.eq(W.homes(["DP-3", "DP-1"], [{ id: 1 }, { id: 25 }], [{ monitor: "DP-3", id: 25 }, { monitor: "DP-1", id: 1 }]),
             [{ monitor: "DP-1", id: 11 }], "the one beyond the blocks stays, a screen showing another's block still goes home")
        T.eq(W.homes(["eDP-1"], undocked, [{ monitor: "eDP-1", id: -1 }]), [{ monitor: "eDP-1", id: 3 }],
             "a screen whose workspace is being moved away still gets one of its own")

        // Turning the setting off takes the rules back (Lua config).
        T.eq(W.ruledIds(20).length, 20, "two monitors had twenty rules")
        T.eq([W.ruledIds(10)[0], W.ruledIds(10)[9]], [1, 10], "from 1")
        T.eq([W.ruledIds(0), W.ruledIds(undefined), W.ruledIds("x")], [[], [], []], "none sent, none to take back")
        // The command that takes them back is HyprCommands.releaseWorkspaceRule
        // (HyprCommandsTest).
        T.eq(W.misplaced([], afterBoot), [], "no monitors known, nothing moves")
        T.eq(W.misplaced(order, null), [], "no workspaces, nothing moves")
        T.eq(W.misplaced(order, [{ id: "3", monitor: "DP-2" }, { id: 4 }]),
             [{ id: 3, monitor: "DP-3" }, { id: 4, monitor: "DP-3" }], "string ids and a missing monitor")
        T.eq(W.monitorOrder([{ x: 0 }, { name: "", x: 0 }]), [], "a monitor with no name is not a monitor")
        T.eq([W.monitorIndex(screens, "DP-3"), W.monitorIndex(screens, "DP-1"), W.monitorIndex(screens, "DP-2")],
             [0, 1, 2], "each monitor's slot")
        T.eq(W.monitorIndex(screens, "nothing"), 0, "an unknown monitor is treated as the first, never as a gap")

        // The first monitor keeps 1-10, so a single screen is unchanged down to
        // the numbers in hyprctl. The others get blocks of ten.
        T.eq([W.globalId(1, 0), W.globalId(9, 0), W.globalId(10, 0)], [1, 9, 10], "monitor 1 keeps its own numbers")
        T.eq([W.globalId(1, 1), W.globalId(9, 1), W.globalId(1, 2)], [11, 19, 21], "monitor 2 and 3 get blocks")
        T.eq([W.localId(1), W.localId(10), W.localId(11), W.localId(21), W.localId(30)], [1, 10, 1, 1, 10],
             "and back to the number the user sees")
        T.eq([W.monitorIndexOf(1), W.monitorIndexOf(10), W.monitorIndexOf(11), W.monitorIndexOf(21)], [0, 0, 1, 2],
             "and to whose it is")
        T.eq([W.globalId(0, 1), W.globalId("x", 1), W.localId(0), W.localId(-3)], [0, 0, 0, 0],
             "nonsense in, zero out - never a valid id by accident")
        T.eq([W.offsetFor(screens, "DP-3"), W.offsetFor(screens, "DP-1"), W.offsetFor(screens, "DP-2")],
             [0, 10, 20], "where each block starts")

        // `fixed` inside a block: the second monitor shows its own 1-4, which
        // are 11-14 in the compositor, and the labels stay 1-4.
        const perMon = [{ id: 1, name: "1", windows: 1, screen: "DP-3" },
                        { id: 12, name: "12", windows: 1, screen: "DP-1" }]
        const second = W.entries("fixed", 4, perMon, "DP-1", 12, 10, 12)
        T.eq(ids(second), [11, 12, 13, 14], "the second monitor's own four")
        T.eq(second.map(item => item.label), ["1", "2", "3", "4"], "labelled as its own 1-4")
        T.eq(second.filter(item => item.active).map(item => item.id), [12], "and its own active one")
        T.eq(W.entries("fixed", 4, perMon, "DP-3", 1, 0, 12).map(item => item.label), ["1", "2", "3", "4"],
             "the first monitor's block is unchanged")
        T.eq(ids(W.entries("fixed", 4, perMon, "DP-3", 1, 0, 12)), [1, 2, 3, 4],
             "and it does not show the other monitor's workspaces")
        // A workspace from another block that landed here is shown rather than
        // hidden: it exists and it has windows in it.
        T.eq(ids(W.entries("fixed", 2, [{ id: 25, name: "25", windows: 1, screen: "DP-3" }], "DP-3", 1, 0, 1)),
             [1, 2, 25], "a stray from another block is not hidden")
        T.eq(W.entries("fixed", 2, [{ id: 11, name: "11", windows: 1, screen: "DP-1" }], "DP-1", 11, 10, 11)[0].label,
             "1", "an unnamed workspace shows its own monitor's number")
        T.eq(W.entries("fixed", 2, [{ id: 11, name: "web", windows: 1, screen: "DP-1" }], "DP-1", 11, 10, 11)[0].label,
             "web", "a named one keeps its name, block or no block")

        // Active is the monitor's own, focused is the one with the keyboard.
        // Comparing against the global focus left two of three bars with no
        // active pip at all.
        const third = W.entries("fixed", 2, perMon, "DP-2", 21, 20, 12)
        T.eq(third.filter(item => item.active).map(item => item.id), [21], "an unfocused monitor still shows where it is")
        T.eq(third.filter(item => item.focused).length, 0, "and does not claim the keyboard")
        T.eq(second.filter(item => item.focused).map(item => item.id), [12], "the focused monitor says so")

        // ---- a workspace from another monitor's block ---------------------
        //
        // Unplug a screen and Hyprland moves its workspaces onto a survivor.
        // Drawing 11 as this monitor's "1" would put two pips on the same
        // place and make clicking either a coin toss, so a stray keeps its
        // real number and says so.
        const stray = W.entries("fixed", 2, [{ id: 11, name: "11", windows: 1, screen: "DP-3" }], "DP-3", 1, 0, 1)
        T.eq(ids(stray), [1, 2, 11], "the stray is shown, not hidden")
        T.eq(stray.map(item => item.label), ["1", "2", "11"], "and keeps its real number")
        T.eq(stray.map(item => item.stray), [false, false, true], "and is marked as not this monitor's")
        T.eq(W.entries("fixed", 2, [{ id: 11, name: "mail", windows: 1, screen: "DP-3" }], "DP-3", 1, 0, 1)
             .filter(item => item.id === 11).map(item => [item.label, item.stray]),
             [["mail", false]], "a named stray is just its name: the name was the point")
        T.eq(W.entries("fixed", 2, [{ id: 11, name: "11", windows: 1, screen: "DP-1" }], "DP-1", 11, 10, 11)[0].stray,
             false, "on its own monitor it is not a stray at all")

        T.finish("WorkspaceTest")
    }
}
