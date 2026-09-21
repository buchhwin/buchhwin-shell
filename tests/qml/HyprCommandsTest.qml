import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/HyprCommands.js" as H
import "../../services/hypr/HyprAnimations.js" as A

ShellRoot {
    Component.onCompleted: {
        const opts = H.options({ "decoration:blur:enabled": true, "decoration:blur:size": 6, "decoration:rounding": 16,
                                 "input:kb_variant": "", "input:touchpad:tap-to-click": false })
        T.eq(opts.legacy, "keyword decoration:blur:enabled true ; keyword decoration:blur:size 6 ; keyword decoration:rounding 16 ; keyword input:touchpad:tap-to-click false", "legacy keywords without empty values")
        T.eq(opts.legacyEmpty, ["input:kb_variant"], "empty values listed separately")
        T.eq(opts.lua, "hl.config({ decoration = { blur = { enabled = true, size = 6 }, rounding = 16 }, input = { kb_variant = \"\", touchpad = { tap_to_click = false } } })", "nested Lua table with underscores")
        const general = H.options({ "general:border_size": 0, "general:gaps_in": 4, "general:gaps_out": 10 })
        T.eq(general.legacy, "keyword general:border_size 0 ; keyword general:gaps_in 4 ; keyword general:gaps_out 10", "legacy border and gaps")
        T.eq(general.lua, "hl.config({ general = { border_size = 0, gaps_in = 4, gaps_out = 10 } })", "Lua border and gaps")
        T.throwsError(() => H.options({ "input:kb_layout": "de ; exec rm" }), "legacy separators rejected")
        T.throwsError(() => H.options({ "input:kb layout": "de" }), "invalid keys rejected")
        T.eq(H.options({ "input:kb_layout": "de\"x" }).lua, "hl.config({ input = { kb_layout = \"de\\\"x\" } })", "Lua strings escaped")

        const m = H.monitor({ name: "DP-1", width: 2560, height: 1440, refresh: 143.97, x: 1920, y: 0, scale: 1.25, transform: 0, vrr: 1 })
        T.eq(m.legacy, "keyword monitor DP-1,2560x1440@143.97,1920x0,1.25,transform,0,vrr,1", "legacy monitor rule")
        T.eq(m.lua, "hl.monitor({ output = \"DP-1\", mode = \"2560x1440@143.97\", position = \"1920x0\", scale = 1.25, transform = 0, vrr = 1 })", "Lua monitor")
        T.eq(H.monitor({ name: "eDP-1", disabled: true }).lua, "hl.monitor({ output = \"eDP-1\", disabled = true })", "disabled monitor")

        T.eq(H.env("XCURSOR_SIZE", "24"), { legacy: "keyword env XCURSOR_SIZE,24", legacyEmpty: [], lua: "hl.env(\"XCURSOR_SIZE\", \"24\")" }, "environment")
        T.eq(H.workspace(3), { legacy: "workspace 3", lua: "hl.dsp.focus({ workspace = 3 })" }, "workspace")
        T.eq(H.moveWindowSilent(5, "0xabc").lua, "hl.dsp.window.move({ workspace = 5, window = \"address:0xabc\", follow = false })", "move window")
        T.eq(H.closeWindow("0xabc").legacy, "closewindow address:0xabc", "close window")
        T.eq(H.focusWindow("0xabc").lua, "hl.dsp.focus({ window = \"address:0xabc\" })", "focus window")
        T.throwsError(() => H.focusWindow("0xabc\") hl.dsp.exit("), "window address validated")
        T.eq(H.dpms(false), { legacy: "dpms off", lua: "hl.dsp.dpms({ action = \"off\" })" }, "dpms")
        T.eq(H.dpms(true, "eDP-1"), { legacy: "dpms on eDP-1", lua: "hl.dsp.dpms({ action = \"on\", monitor = \"eDP-1\" })" }, "dpms for one monitor")
        T.eq(H.combine([H.env("A", "1"), H.env("B", "2")]).lua, "hl.env(\"A\", \"1\")\nhl.env(\"B\", \"2\")", "combined Lua statements")
        const bindT = H.bindExec(["SHIFT", "super"], "T", "kitty --title \"a,b\" $HOME ## x", "Custom: kitty")
        T.eq(bindT.legacy, "keyword bindd SUPER SHIFT,T,Custom: kitty,exec,kitty --title \"a,b\" ${HOME} #### x", "legacy bind with description, hyprlang escaped")
        T.eq(bindT.lua, "hl.bind(\"SUPER + SHIFT + T\", hl.dsp.exec_cmd(\"kitty --title \\\"a,b\\\" $HOME ## x\"), { description = \"Custom: kitty\" })", "Lua bind")
        T.eq(H.bindExec([], "F9", "true").legacy, "keyword bind ,F9,exec,true", "legacy bind without modifiers")
        T.eq(H.bindExec([], "F9", "true").lua, "hl.bind(\"F9\", hl.dsp.exec_cmd(\"true\"))", "Lua bind without description")
        T.eq(H.unbind(["SUPER", "CTRL"], "F5"), { legacy: "keyword unbind SUPER CTRL,F5", legacyEmpty: [], lua: "hl.unbind(\"SUPER + CTRL + F5\")" }, "unbind")
        T.throwsError(() => H.bindExec(["SUPER"], "T", "a ; keyword exit"), "semicolon in command rejected")
        T.throwsError(() => H.bindExec(["SUPER"], "T", "a\nb"), "newline in command rejected")
        T.throwsError(() => H.bindExec(["SUPER"], "T,exec", "true"), "invalid key rejected")
        T.throwsError(() => H.bindExec(["HYPER"], "T", "true"), "invalid modifier rejected")
        T.throwsError(() => H.bindExec(["SUPER"], "T", "true", "a,b"), "description separators rejected")
        const gesture = H.gestures([{ fingers: 3, direction: "horizontal", action: "workspace" }, { fingers: 4, direction: "pinchin", command: "notify-send hi" }],
                                   [{ fingers: 3, direction: "horizontal" }, { fingers: 4, direction: "pinchin" }])
        T.eq(gesture.legacy, "keyword gesture 3, horizontal, unset ; keyword gesture 4, pinchin, unset ; keyword gesture 3, horizontal, workspace ; keyword gesture 4, pinchin, dispatcher, exec, notify-send hi", "legacy gestures replace their slots")
        T.eq(gesture.lua.split("\n").slice(4), ["hl.gesture({ fingers = 4, direction = \"pinchin\", action = function() hl.exec_cmd(\"notify-send hi\") end })",
                                                "table.insert(buchhwin_gestures, { 4, \"pinchin\" })"], "Lua gesture with a command")
        T.eq(H.gestures([], []).lua, "for _, slot in ipairs(buchhwin_gestures or {}) do hl.gesture({ fingers = slot[1], direction = slot[2], action = \"unset\" }) end\nbuchhwin_gestures = {}", "Lua removal only")
        T.eq(H.gestures([{ fingers: 3, direction: "up", command: "echo $HOME # x" }], []).legacy, "keyword gesture 3, up, dispatcher, exec, echo ${HOME} ## x", "legacy command escaped")
        T.throwsError(() => H.gestures([{ fingers: 3, direction: "diagonal", action: "workspace" }], []), "invalid direction")
        T.throwsError(() => H.gestures([{ fingers: 2, direction: "up", action: "workspace" }], []), "invalid finger count")
        T.throwsError(() => H.gestures([{ fingers: 3, direction: "up", action: "exec" }], []), "invalid action")
        T.throwsError(() => H.gestures([{ fingers: 3, direction: "up", command: "a ; keyword exit" }], []), "semicolon rejected")
        T.throwsError(() => H.gestures([{ fingers: 3, direction: "up", command: "a, b" }], []), "comma rejected")
        T.throwsError(() => H.gestures([], [{ fingers: "3; x", direction: "up" }]), "slot validated")
        // ---- animations ---------------------------------------------------
        const one = H.animation({ leaf: "windows", enabled: true, speed: 2.5, bezier: "buchhwinSpring", style: "popin 96%" })
        T.eq(one.legacy, "keyword animation windows,1,2.5,buchhwinSpring,popin 96%", "legacy animation line keeps the style's space")
        T.eq(one.lua, "hl.animation({ leaf = \"windows\", enabled = true, speed = 2.5, bezier = \"buchhwinSpring\", style = \"popin 96%\" })", "Lua animation line")
        const bare = H.animation({ leaf: "border", enabled: false, speed: 2, bezier: "buchhwinFast", style: "" })
        T.eq(bare.legacy, "keyword animation border,0,2,buchhwinFast", "a leaf with no style has no trailing comma")
        T.ok(bare.lua.indexOf("style") < 0, "and no style in Lua either")
        T.throwsError(() => H.animation({ leaf: "windows", enabled: true, speed: 0, bezier: "buchhwinFast" }), "a speed of zero is refused")
        T.throwsError(() => H.animation({ leaf: "windows", enabled: true, speed: 2, bezier: "f", style: "a ; keyword exit" }), "a style cannot smuggle a command")

        // The four modes, as they reach the compositor.
        T.ok(!A.enabled("off"), "off turns the compositor's animations off")
        T.ok(A.enabled("reduced") && A.enabled("full"), "every other mode leaves them on")
        T.ok(!A.pointerAnimated("off") && !A.pointerAnimated("reduced"), "a dragged window stops interpolating in off and reduced")
        T.ok(A.pointerAnimated("full"), "and keeps it in the mode that moves")
        const fast = A.entries("full")
        const windowsFast = fast.find(entry => entry.leaf === "windows")
        T.eq(windowsFast.speed, 2, "the default mode is the table as written")
        T.eq(A.entries("reduced").find(entry => entry.leaf === "windows").speed, 1.2, "reduced is shorter")
        // Normal is gone: it differed from the default mode in a duration
        // factor and nothing else, which is what the speed setting does. An
        // unknown mode is the default one, so a session written before the
        // change still animates rather than falling silent.
        T.eq(A.entries("normal").find(entry => entry.leaf === "windows").speed, 2, "a mode nobody knows any more is the default one")
        T.ok(A.entries("full").every(entry => entry.speed > 0), "no mode produces a speed Hyprland would refuse")
        T.ok(!A.entries("full").find(entry => entry.leaf === "borderangle").enabled, "the hue cycle stays off in every mode")
        // The user's speed setting divides the duration, so twice the speed is
        // half the number - Hyprland's `speed` counts deciseconds. Up to the
        // floor: a window may not be rushed below ten frames however far the
        // slider is turned, which is why "twice as fast" stops at 1.67 rather
        // than reaching 1. The floor itself is AnimationTest's subject.
        const windowsOf = speed => A.entries("full", speed).find(entry => entry.leaf === "windows").speed
        T.eq(windowsOf(undefined), 2, "no speed given is the designed pace")
        T.eq(windowsOf(2), 1.67, "twice as fast is held at ten frames, not halved")
        T.eq(windowsOf(0.5), 4, "half as fast is twice as long - the floor is only a minimum")
        T.eq(windowsOf(0), 2, "a speed of nothing is not a speed")
        T.ok(A.entries("full", 3).every(entry => entry.speed > 0), "even at the top of the slider nothing reaches zero")

        const off = H.animationMode(A.entries("off"), A.enabled("off"), A.pointerAnimated("off"))
        T.ok(off.legacy.indexOf("animations:enabled false") >= 0, "off says so")
        T.ok(off.legacy.indexOf("keyword animation ") < 0, "and does not bother re-emitting the leaves")
        T.ok(off.legacy.indexOf("misc:animate_mouse_windowdragging false") >= 0, "a dragged window stops interpolating too")
        const on = H.animationMode(A.entries("full"), true, true)
        T.ok(on.legacy.indexOf("keyword animation windows,1,2,") >= 0, "a moving mode re-emits every leaf")
        T.eq(on.legacy.split("keyword animation ").length - 1, A.entries("full").length, "every leaf, once")

        // A key press moves the *active* window, so no address at all.
        T.eq(H.moveActiveSilent(3).legacy, "movetoworkspacesilent 3", "move the active window, legacy")
        T.eq(H.moveActiveSilent(3).lua, "hl.dsp.window.move({ workspace = 3, follow = false })",
             "move the active window, Lua")
        // Pinning a workspace to a monitor, so an unplugged screen does not
        // scatter its block across the survivors.
        T.eq(H.workspaceRule(11, "DP-10").legacy, "keyword workspace 11,monitor:DP-10",
             "workspace rule, legacy")
        T.eq(H.workspaceRule(11, "DP-10").lua,
             "hl.workspace_rule({ workspace = \"11\", monitor = \"DP-10\" })",
             "workspace rule, Lua")
        // Not persistent: that would call thirty workspaces into existence for
        // three monitors, whether or not anything is in them.
        T.ok(H.workspaceRule(11, "DP-10").legacy.indexOf("persistent") < 0, "and it creates nothing")

        // Frame scheduling follows the screen count, not taste: on one output
        // it is what a stepping animation needs, on several it decides which
        // output gets asked for a frame at all - and an unfocused monitor that
        // stops being asked looks like a frozen video.
        T.eq([A.frameScheduling(1), A.frameScheduling(2), A.frameScheduling(3)], [true, false, false],
             "one screen on, more than one off")
        T.eq([A.frameScheduling(0), A.frameScheduling(-1)], [false, false],
             "no screen counted yet is answered with the value that cannot starve one")
        T.eq([A.frameScheduling("1"), A.frameScheduling("2"), A.frameScheduling("x"), A.frameScheduling(null)],
             [true, false, false, false], "only a count of exactly one turns it on")

        T.finish("HyprCommandsTest")
    }
}
