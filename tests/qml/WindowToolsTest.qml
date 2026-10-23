import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/WindowToolsLogic.js" as W
import "../../services/hypr/HyprCommands.js" as H

// Keep on top, the drop-down terminal and a Citrix session over the desk's
// screens (WindowToolsLogic), and the dispatchers they are sent with.
ShellRoot {
    Component.onCompleted: {
        // Keep on top: floated first, let go back into the layout.
        T.eq(W.keepOnTop({ address: "0xa1", floating: false, pinned: false }, false), { steps: ["float", "pin"], floated: true },
             "a tiled window is floated, then pinned")
        T.eq(W.keepOnTop({ address: "0xa1", floating: true, pinned: false }, false), { steps: ["pin"], floated: false },
             "a floating one is only pinned")
        T.eq(W.keepOnTop({ address: "0xa1", floating: true, pinned: true }, true), { steps: ["pin", "float"], floated: false },
             "let go, the one the shell floated goes back into the layout")
        T.eq(W.keepOnTop({ address: "0xa1", floating: true, pinned: true }, false), { steps: ["pin"], floated: false },
             "one that floated on its own stays floating")
        T.eq([W.keepOnTop(null, false), W.keepOnTop({ address: "a1" }, false)], [null, null], "no window, nothing")

        const clients = [
            { address: "0xa1", focusHistoryID: 1, title: "one" },
            { address: "0xb2", focusHistoryID: 0, title: "two" },
            { address: "0xc3", focusHistoryID: 2, hidden: true }
        ]
        T.eq(W.activeClient(clients).address, "0xb2", "the active window is the one used last")
        T.eq(W.activeClient([{ address: "0xd4", focusHistoryID: 0, workspace: { id: -98, name: "special:buchhwin-minimized-3" } }]), null,
             "not one minimized a moment ago, which Hyprland may still count as focused")
        T.eq([W.clientAt(clients, "").address, W.clientAt(clients, "a1").address, W.clientAt(clients, "0xA1").address],
             ["0xb2", "0xa1", "0xa1"], "by address, with or without 0x, or the active one")
        T.eq(W.clientAt(clients, "0xff"), null, "an address that has gone")

        T.eq(H.toggleFloating("0xa1"), { legacy: "togglefloating address:0xa1",
                                         lua: "hl.dsp.window.float({ action = \"toggle\", window = \"address:0xa1\" })" }, "float")
        T.eq(H.togglePin("0xa1"), { legacy: "pin address:0xa1",
                                    lua: "hl.dsp.window.pin({ action = \"toggle\", window = \"address:0xa1\" })" }, "pin")
        T.throwsError(() => H.togglePin("a1; exec x"), "an address is an address")
        T.eq(H.moveActive(4), { legacy: "movetoworkspace 4", lua: "hl.dsp.window.move({ workspace = 4 })" }, "a window along to a workspace")
        T.eq(H.dispatchBatch([H.toggleFloating("0xa1"), H.togglePin("0xa1")]).legacy,
             "dispatch togglefloating address:0xa1 ; dispatch pin address:0xa1", "one request, in order")

        // The drop-down terminal.
        T.eq([W.dropdownAction(["org.kde.dolphin", "buchhwin-dropdown"]), W.dropdownAction(["Alacritty"]), W.dropdownAction(null)],
             ["toggle", "launch", "launch"], "shown or put away while its window is there, started otherwise")
        T.eq(H.toggleSpecial(W.DROPDOWN_WORKSPACE), { legacy: "togglespecialworkspace buchhwin-dropdown",
                                                      lua: "hl.dsp.workspace.toggle_special(\"buchhwin-dropdown\")" }, "its workspace")
        T.throwsError(() => H.toggleSpecial("a b"), "a special workspace is a word")

        // A Citrix session over the desk: DP-8 and DP-10 side by side, the
        // portrait DP-13 beside them, the laptop's panel.
        const desk = [
            { name: "DP-10", x: 2304, y: 0, width: 2304, height: 1296 },
            { name: "DP-8", x: 0, y: 0, width: 2304, height: 1296 },
            { name: "DP-13", x: 4608, y: 0, width: 1296, height: 2304 },
            { name: "eDP-1", x: 5904, y: 0, width: 1920, height: 1200 }
        ]
        T.eq(W.spanTarget(desk), { x: 0, y: 0, width: 4608, height: 1296, names: ["DP-8", "DP-10"] },
             "the two 4K screens together, not the portrait one or the panel")
        T.eq(W.spanTarget([desk[1], desk[3]]), null, "one external screen and the panel: nothing to spread over")
        T.eq(W.spanTarget([{ name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200 }]), null, "the laptop alone")
        T.eq(W.spanTarget([{ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 }, { name: "DP-2", x: 1920, y: 200, width: 1920, height: 1080 }]),
             null, "two screens at different heights make no rectangle")
        T.eq(W.spanTarget([{ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 }, { name: "DP-2", x: 2000, y: 0, width: 1920, height: 1080 }]),
             null, "nor two with a gap between them")
        T.eq(W.spanTarget([{ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 }, { name: "DP-2", x: 1921, y: 1, width: 1920, height: 1080 },
                           { name: "DP-3", x: 3841, y: 0, width: 1920, height: 1080 }]).names, ["DP-1", "DP-2", "DP-3"],
             "three in a row, a pixel of rounding apart")
        T.eq(W.spanTarget(null), null, "no screens")

        const sessions = [
            { address: "0xd1", class: "Wfica", title: "wfica", focusHistoryID: 0 },
            { address: "0xd2", class: "Wfica", title: "RDS-Desk", focusHistoryID: 3, floating: false, fullscreen: 0 },
            { address: "0xd3", class: "Wfica", title: "RDS-Other", focusHistoryID: 1, floating: true, fullscreen: 0 },
            { address: "0xd4", class: "brave-browser", title: "Citrix Workspace", focusHistoryID: 2 }
        ]
        T.eq(W.citrixWindow(sessions).address, "0xd3", "the session used last, not its dialog or a browser")
        T.eq(W.citrixWindow([sessions[0], sessions[3]]), null, "no session window")
        const target = W.spanTarget(desk)
        T.eq(W.spanPlan(sessions[1], target), { steps: [{ kind: "float" }, { kind: "size", width: 4608, height: 1296 },
                                                         { kind: "place", x: 0, y: 0 }], reason: "" }, "floated, sized, placed")
        T.eq(W.spanPlan(sessions[2], target).steps.length, 2, "one floating already is only sized and placed")
        T.eq(W.spanPlan(Object.assign({}, sessions[1], { fullscreen: 2 }), target),
             { steps: [], reason: "Leave Citrix full screen first" }, "never a session in full screen")
        T.eq(W.spanPlan(sessions[1], null).steps, [], "never without the screens")
        T.eq(W.spanPlan(null, target).reason, "No Citrix session window", "never without the session")
        T.eq(W.spanText(target), "Citrix on 2 screens", "what the OSD says: short, without the connectors' names")
        T.eq(H.resizeExact("0xd2", 4608, 1296), { legacy: "resizewindowpixel exact 4608 1296,address:0xd2",
             lua: "hl.dsp.window.resize({ x = 4608, y = 1296, relative = false, window = \"address:0xd2\" })" }, "the size")
        T.eq(H.moveExact("0xd2", 0, 0), { legacy: "movewindowpixel exact 0 0,address:0xd2",
             lua: "hl.dsp.window.move({ x = 0, y = 0, relative = false, window = \"address:0xd2\" })" }, "the place")
        T.throwsError(() => H.resizeExact("0xd2", 0, 10), "no window of nothing")
        T.throwsError(() => H.moveExact("0xd2", "x", 0), "a place is numbers")
        // Super+C: a tiled window floats smaller and centred on its screen.
        const deskScreens = [{ name: "DP-8", x: 0, y: 120, width: 1920, height: 1080 }, { name: "DP-12", x: 1920, y: 0, width: 1920, height: 1200 }]
        T.eq(W.floatPlan({ address: "0xb1", floating: false, at: [1932, 40], size: [1896, 1148] }, deskScreens),
             { steps: [{ kind: "float" }, { kind: "size", width: 1152, height: 780 }, { kind: "move", x: 2304, y: 210 }] },
             "a full tile on the right screen: 60 % x 65 % of it, in its middle")
        T.eq(W.floatPlan({ address: "0xb2", floating: false, at: [10, 130], size: [940, 1060] }, deskScreens).steps[2],
             { kind: "move", x: 384, y: 309 }, "the left screen's tile stays on the left screen")
        T.eq(W.floatPlan({ address: "0xb3", floating: true, at: [100, 100], size: [800, 600] }, deskScreens), { steps: [{ kind: "float" }] },
             "a floating window goes back into the layout as it is")
        T.eq(W.floatPlan({ address: "0xb4", floating: false, at: [0, 0], size: [100, 100] }, []), { steps: [{ kind: "float" }] },
             "no screen known: floating as Hyprland does it")
        T.eq([W.floatPlan(null, deskScreens), W.floatPlan({ address: "nope" }, deskScreens)], [null, null], "no window, nothing")

        T.finish("WindowToolsTest")
    }
}
