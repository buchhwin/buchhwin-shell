import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/input/GestureLogic.js" as G
import "../../services/hypr/HyprCommands.js" as H

ShellRoot {
    Component.onCompleted: {
        const defaults = {
            "gestures.enabled": true, "gestures.threeHorizontal": "workspace", "gestures.threeUp": "overview",
            "gestures.threeDown": "closePanel", "gestures.fourHorizontal": "none", "gestures.fourUp": "none",
            "gestures.fourDown": "none", "gestures.pinchIn": "launcher", "gestures.pinchOut": "none",
            "gestures.naturalSwipe": true, "gestures.createNew": false
        }
        const getter = overrides => path => (overrides && path in overrides) ? overrides[path] : defaults[path]
        const shell = "/home/user/.local/share/buchhwin-shell"

        const plan = G.plan(getter(), shell)
        T.eq(plan.gestures, [
            { fingers: 3, direction: "horizontal", action: "workspace" },
            { fingers: 3, direction: "up", command: "quickshell --path " + shell + " ipc call gestures run overview" },
            { fingers: 3, direction: "down", command: "quickshell --path " + shell + " ipc call gestures run closePanel" },
            { fingers: 4, direction: "pinchin", command: "quickshell --path " + shell + " ipc call gestures run launcher" }
        ], "default gestures")
        T.eq(plan.slots.length, 8, "every slot is managed")
        T.eq(plan.options, { "gestures:workspace_swipe_invert": true, "gestures:workspace_swipe_create_new": false,
                             "gestures:workspace_swipe_direction_lock": true }, "workspace swipe options")
        T.eq(G.plan(getter({ "gestures.naturalSwipe": false, "gestures.createNew": true }), shell).options["gestures:workspace_swipe_invert"], false, "natural direction off")
        T.eq(G.plan(getter({ "gestures.enabled": false }), shell).gestures, [], "disabled removes all")
        T.eq(G.plan(getter({ "gestures.threeUp": "fullscreen", "gestures.fourHorizontal": "workspace" }), shell).gestures.slice(0, 3), [
            { fingers: 3, direction: "horizontal", action: "workspace" },
            { fingers: 3, direction: "up", action: "fullscreen" },
            { fingers: 3, direction: "down", command: "quickshell --path " + shell + " ipc call gestures run closePanel" }
        ], "Hyprland actions")
        T.eq(G.plan(getter({ "gestures.threeHorizontal": "overview", "gestures.threeUp": "bogus" }), shell).gestures.map(g => g.direction),
             ["down", "pinchin"], "unknown or misplaced actions skipped")
        T.eq(G.plan(getter(), "/home/a b").gestures.map(g => g.direction), ["horizontal"], "unusable shell path skips panel actions")
        T.eq(G.shellCommand(shell + "/", "dashboard"), "quickshell --path " + shell + " ipc call gestures run dashboard", "trailing slash")
        T.eq(G.shellCommand(shell, "fullscreen"), "", "only panel actions run over IPC")
        T.eq(G.shellAction("controlCenter").panel, "controlCenter", "panel action")
        T.ok(G.shellAction("closePanel").closePanel, "close panel action")
        T.eq(G.shellAction("close; rm"), null, "unknown IPC action")
        T.eq(G.rows(getter()), [
            { label: "3 fingers left/right", action: "Switch workspace" }, { label: "3 fingers up", action: "Overview" },
            { label: "3 fingers down", action: "Close the open panel" }, { label: "4 fingers pinch in", action: "Launcher" }
        ], "rows for the shortcut list")
        T.eq(G.rows(getter({ "gestures.enabled": false })), [], "no rows when off")

        T.ok(G.hasTouchpad(JSON.stringify({ mice: [{ name: "tpps/2-synaptics-trackpoint" }, { name: "elan06c9:00-04f3:320b-touchpad" }] })), "touchpad found")
        T.ok(!G.hasTouchpad(JSON.stringify({ mice: [{ name: "logitech-mx-master" }], keyboards: [] })), "mouse only")
        T.ok(!G.hasTouchpad("not json"), "broken output")

        // Command builders
        const built = H.gestures(G.plan(getter(), shell).gestures.slice(0, 2), [{ fingers: 3, direction: "horizontal" }, { fingers: 3, direction: "up" }])
        T.eq(built.legacy, "keyword gesture 3, horizontal, unset ; keyword gesture 3, up, unset ; keyword gesture 3, horizontal, workspace ; "
             + "keyword gesture 3, up, dispatcher, exec, quickshell --path " + shell + " ipc call gestures run overview", "legacy gestures")
        T.eq(built.lua.split("\n"), [
            "for _, slot in ipairs(buchhwin_gestures or {}) do hl.gesture({ fingers = slot[1], direction = slot[2], action = \"unset\" }) end",
            "buchhwin_gestures = {}",
            "hl.gesture({ fingers = 3, direction = \"horizontal\", action = \"workspace\" })",
            "table.insert(buchhwin_gestures, { 3, \"horizontal\" })",
            "hl.gesture({ fingers = 3, direction = \"up\", action = function() hl.exec_cmd(\"quickshell --path " + shell + " ipc call gestures run overview\") end })",
            "table.insert(buchhwin_gestures, { 3, \"up\" })"
        ], "Lua gestures remember their slots")
        T.finish("GestureTest")
    }
}
