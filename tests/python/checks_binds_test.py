#!/usr/bin/env python3
"""The bind reader behind `checks.py binds`: both Hyprland dialects, read alike.

The check itself runs against the real hypr/ files in scripts/test.sh; this
holds the reading of them to account, in the shapes that used to be misread
(a `bindd` line, whose description sits where the dispatcher was counted) or
not read at all (the Lua's `hl.bind` calls, and its workspace loop).
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "lib"))
import checks  # noqa: E402

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


# ---- one conf line ---------------------------------------------------------
check(checks.ipc_action("bind = SUPER, D, exec, quickshell --path $p ipc call launcher toggle") == "launcher toggle",
      "a plain bind's shell action is read")
check(checks.ipc_action("bindd = SUPER, D, Open the launcher, exec, quickshell --path $p ipc call launcher toggle") == "launcher toggle",
      "a described bind's action is read past the description")
check(checks.ipc_action("bindd = SUPER, D, Open the launcher, killactive") is None,
      "a described bind with no exec has no shell action")
check(checks.ipc_action("bind = SUPER, Q, killactive") is None, "a dispatcher that is not exec has no action")
check(checks.ipc_action("bindel = , XF86MonBrightnessUp, exec, brightnessctl set 5%+ && quickshell --path $p ipc call brightness refresh") is None,
      "a command that only ends in a call is not that call")
check(checks.conf_bind("bindm = SUPER, mouse:272, movewindow")[0] == "m", "the flags are read")
check(checks.conf_bind("bindd = SUPER, D, Launcher, exec, x")[3] == "exec", "the dispatcher of a described bind")
check(checks.conf_bind("layerrule = blur on, match:namespace ^(x)$") is None, "a line that is not a bind")
check(checks.global_action_of("buchhwin:audio.talk") == "audio talk", "a conf bind on the shell's global shortcut names its action")
check(checks.global_action_of("otherapp:thing") is None, "another program's global shortcut is no shell action")

# ---- the Lua dialect -------------------------------------------------------
LUA = '''
local ipc = "quickshell --path " .. projectPath .. " ipc call "
local function exec(command) return hl.dsp.exec_cmd(command) end
-- hl.bind(keyFor("SUPER + X"), exec(ipc .. "commented out"), { description = "no" })
hl.bind(keyFor("SUPER + RETURN"), exec(terminal), { description = "Terminal" })
hl.bind(keyFor("SUPER + CTRL + R"), exec(projectPath .. "/scripts/reload-shell.sh"), { description = "Restart" })
hl.bind(keyFor("SUPER + D"), exec(ipc .. "launcher toggle"), { description = "Launcher" })
hl.bind(keyFor("SUPER + Q"), hl.dsp.window.close(), { description = "Close window" })
hl.bind(keyFor("ALT + ALT_L"), exec(ipc .. "switcher confirm"), { release = true, transparent = true, description = "Switch" })
hl.bind(keyFor("Print"), exec(projectPath .. "/scripts/screenshot.sh region"), { description = "Screenshot" })
for i = 1, 3 do
    hl.bind("SUPER + " .. i, exec(ipc .. "workspaces switchTo " .. i .. " || hyprctl dispatch workspace " .. i),
            { description = "Go to workspace " .. i })
end
hl.bind(keyFor("SUPER + mouse:272"), hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind(keyFor("switch:on:Lid Switch"), exec(ipc .. "power lidClosed"), { locked = true, description = "Lid closed" })
'''
lua = checks.lua_binds(LUA)
by_combo = {combo: (namespace, action, where) for namespace, combo, action, where in lua}
check(len(lua) == 11, f"every call is read, the loop once per round, the comment not at all: {len(lua)}")
check(by_combo.get(("SUPER", "D")) == (("key", "SUPER", "D"), "launcher toggle", "hyprland.lua:7"),
      f"combo, action and line of a plain call: {by_combo.get(('SUPER', 'D'))}")
check(by_combo.get(("CTRL SUPER", "R"), (None, 1))[1] is None, "an exec that is not an ipc call has no action")
check(by_combo.get(("SUPER", "RETURN"), (None, 1))[1] is None, "an exec of a bare name has no action")
check(by_combo.get(("SUPER", "Q"), (None, 1))[1] is None, "a dispatcher call has no action")
check(by_combo.get(("ALT", "ALT_L"), (None, None))[1] == "switcher confirm", "options after the action do not hide it")
check(("", "PRINT") in by_combo, f"a key without modifiers: {sorted(by_combo)}")
check(("", "SWITCH:ON:LID SWITCH") in by_combo, "a key with a space in its name")
check(by_combo.get(("SUPER", "MOUSE:272"), (None,))[0] == ("mouse", "SUPER", "MOUSE:272"), "a mouse binding has its own namespace")
for round_ in (1, 2, 3):
    check(by_combo.get(("SUPER", str(round_)), (None, None))[1] == f"workspaces switchTo {round_}",
          f"the loop's round {round_} is one binding with its own action, the fallback after || not part of it")

# Global shortcuts: `shell("…")` and `shellOr("…", fallback)` carry the action.
shortcuts = checks.lua_binds('hl.bind(keyFor("SUPER + O"), shell("controlCenter toggle"), { description = "CC" })\n'
                             'hl.bind(keyFor("SUPER + 4"), shellOr("workspaces switchTo 4", hl.dsp.focus({ workspace = 4 })), { description = "W" })\n')
check([action for _, _, action, _ in shortcuts] == ["controlCenter toggle", "workspaces switchTo 4"],
      f"a global shortcut is the IPC call it names: {shortcuts}")
check(checks.shortcut_problems('hl.bind("SUPER + Z", shell("launcher nonsense"))\n') != [],
      "a shortcut the shell does not register is a problem")
check(checks.shortcut_problems('hl.bind("SUPER + D", shell("launcher toggle"))\n') == [],
      "a registered one with its IpcHandler function is not")

# ---- both dialects against each other ---------------------------------------
conf = [(("key", "SUPER", "D"), ("SUPER", "D"), "launcher toggle", "keybinds.conf:1"),
        (("key", "SUPER", "1"), ("SUPER", "1"), "workspaces switchTo 1", "keybinds.conf:2"),
        (("mouse", "SUPER", "MOUSE:272"), ("SUPER", "MOUSE:272"), None, "keybinds.conf:3")]
same = [(("key", "SUPER", "D"), ("SUPER", "D"), "launcher toggle", "hyprland.lua:1"),
        (("key", "SUPER", "1"), ("SUPER", "1"), "workspaces switchTo 1", "hyprland.lua:2"),
        (("mouse", "SUPER", "MOUSE:272"), ("SUPER", "MOUSE:272"), None, "hyprland.lua:3")]
check(checks.bind_drift(conf, same) == [], "the same bindings in both dialects are no drift")
only_conf = checks.bind_drift(conf, same[1:])
check(only_conf == ["SUPER + D: bound only in the conf (keybinds.conf:1)"], f"a key only the conf binds: {only_conf}")
only_lua = checks.bind_drift(conf[1:], same)
check(only_lua == ["SUPER + D: bound only in the Lua (hyprland.lua:1)"], f"a key only the Lua binds: {only_lua}")
other = checks.bind_drift(conf, [(("key", "SUPER", "D"), ("SUPER", "D"), "settings toggle", "hyprland.lua:1")] + same[1:])
check(other == ["SUPER + D: conf calls 'launcher toggle', Lua calls 'settings toggle' (hyprland.lua:1)"],
      f"one key doing two things is reported: {other}")

# ---- within one dialect -----------------------------------------------------
problems, _, _ = checks._bind_problems(same + [(("key", "SUPER", "D"), ("SUPER", "D"), None, "hyprland.lua:9")])
check(problems == ["duplicate binding SUPER + D at hyprland.lua:9 and hyprland.lua:1"], f"a duplicate combo: {problems}")
problems, _, _ = checks._bind_problems(same + [(("key", "SUPER", "O"), ("SUPER", "O"), "launcher toggle", "hyprland.lua:9")])
check(problems == ["two bindings call the same action 'launcher toggle' at hyprland.lua:9 and hyprland.lua:1"],
      f"two keys for one action: {problems}")

volume_conf = [(("key", "", "XF86AUDIORAISEVOLUME"), ("", "XF86AUDIORAISEVOLUME"), None, "keybinds.conf:1")]
volume_lua = [(("key", "", "XF86AUDIORAISEVOLUME"), ("", "XF86AUDIORAISEVOLUME"), "audio up", "hyprland.lua:1")]
check(checks.bind_drift(volume_conf, volume_lua) == [], "a volume key the conf runs as wpctl and the Lua sends to the shell is no drift")
other_lua = [(("key", "", "XF86AUDIORAISEVOLUME"), ("", "XF86AUDIORAISEVOLUME"), "launcher toggle", "hyprland.lua:1")]
check(len(checks.bind_drift(volume_conf, other_lua)) == 1, "any other shell action against a plain command still is")

# ---- submaps -----------------------------------------------------------------
# A bind inside a submap is a key of that submap, in both dialects: the
# keyboard passthrough's way out is the key that leads into it, and no
# duplicate of it.
SUBMAP_LUA = '''
hl.bind(keyFor("SUPER + Escape"), hl.dsp.submap("passthrough"), { description = "In" })
hl.define_submap("passthrough", function()
    hl.bind(keyFor("SUPER + Escape"), hl.dsp.submap("reset"), { description = "Out" })
end)
hl.bind(keyFor("SUPER + F"), hl.dsp.window.fullscreen(), { description = "After" })
'''
SUBMAPPED = [("key", "SUPER", "ESCAPE"), ("key", "SUPER", "ESCAPE", "passthrough"), ("key", "SUPER", "F")]
submapped = checks.lua_binds(SUBMAP_LUA)
check([namespace for namespace, _, _, _ in submapped] == SUBMAPPED,
      f"a Lua bind in a submap is that submap's, the one after it the normal map's: {submapped}")
check(checks._bind_problems(submapped)[0] == [], "the same key in and out of a submap is no duplicate")
with tempfile.TemporaryDirectory() as folder:
    (Path(folder) / "hypr").mkdir()
    (Path(folder) / "hypr" / "keybinds.conf").write_text(
        "bind = SUPER, Escape, submap, passthrough\nsubmap = passthrough\nbind = SUPER, Escape, submap, reset\n"
        "submap = reset\nbind = SUPER, F, fullscreen, 0\n")
    root, checks.ROOT = checks.ROOT, Path(folder)
    try:
        conf_submapped = checks.conf_binds()
    finally:
        checks.ROOT = root
check([namespace for namespace, _, _, _ in conf_submapped] == SUBMAPPED,
      f"and a conf bind between `submap = NAME` and `submap = reset`: {conf_submapped}")
check(checks.bind_drift(conf_submapped, submapped) == [], "the two dialects' submaps agree")

# ---- the shell's side of a Lua key ------------------------------------------
# A Lua key reaches the shell as a global shortcut, which shell.qml answers
# through `shortcutTargets`: an IpcHandler left out of it is a key that only
# logs "unknown shortcut", though `ipc call` (the conf dialect) works.
TARGETS_QML = """ShellRoot {
    IpcHandler {
        id: alphaIpc
        target: "alpha"
        function go(): void {}
    }
    IpcHandler {
        id: betaIpc
        target: "beta"
        function go(): void {}
    }
    readonly property var shortcutTargets: ({
        alpha: alphaIpc
    })
}
"""
with tempfile.TemporaryDirectory() as folder:
    (Path(folder) / "services" / "shortcuts").mkdir(parents=True)
    (Path(folder) / "services" / "shortcuts" / "ShellShortcuts.js").write_text('var ACTIONS = [\n    "alpha go", "beta go"\n]\n\n')
    (Path(folder) / "shell.qml").write_text(TARGETS_QML)
    root, checks.ROOT = checks.ROOT, Path(folder)
    try:
        unreached = checks.shortcut_problems('hl.bind(keyFor("SUPER + A"), shell("alpha go"), {})\n'
                                             'hl.bind(keyFor("SUPER + B"), shellOr("beta go", x), {})\n')
    finally:
        checks.ROOT = root
check(len(unreached) == 1 and '"beta"' in unreached[0] and "shortcutTargets" in unreached[0],
      f"a handler missing from shortcutTargets is named, the one in it is not: {unreached}")

# ---- the real files ---------------------------------------------------------
real_conf = checks.conf_binds()
real_lua = checks.lua_binds((checks.ROOT / "hypr" / "hyprland.lua").read_text())
check(len(real_conf) == len(real_lua) and len(real_lua) > 60,
      f"the shipped files bind the same number of keys once the loop is expanded: {len(real_conf)} vs {len(real_lua)}")
check(checks.bind_drift(real_conf, real_lua) == [], f"the shipped files agree: {checks.bind_drift(real_conf, real_lua)}")

if failures:
    for failure in failures:
        print("FAIL checks_binds: " + failure)
    print(f"TESTS FAILED checks_binds ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED checks_binds")
