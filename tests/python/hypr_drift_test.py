#!/usr/bin/env python3
"""The parser behind `checks.py hypr`: the two Hyprland dialects read alike.

The check itself runs against the real hypr/ files in scripts/test.sh. This
holds the reading of them to account, because a parser that quietly returns
nothing would make the check pass for the wrong reason.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "lib"))
import checks  # noqa: E402

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


CONF = """
general {
    gaps_in = 6
    border_size = 1
    col.active_border = rgba(4f8ff7cc)
    layout = dwindle
}

decoration {
    rounding = 16
    blur {
        enabled = true
        size = 6
    }
}

misc {
    # a comment, and a blank line follow
    animate_mouse_windowdragging = true
}

render {
    new_render_scheduling = false
}

animations {
    enabled = true
    bezier = curveA, 0.22, 1.0, 0.36, 1.0
    animation = windows, 1, 2.0, curveA, popin 96%
    animation = border, 1, 2.0, curveA
    animation = borderangle, 0, 1, curveA
}
"""

LUA = """
hl.config({
    general = {
        gaps_in = 6,
        border_size = 1,
        col = { active_border = "rgba(4f8ff7cc)" },
        layout = "dwindle",
    },
    decoration = {
        rounding = 16,
        blur = { enabled = true, size = 6 },
    },
    misc = {
        -- a comment that mentions size = 99 is not a setting
        --[[ and a block comment
             with force_default_wallpaper = 1 is not one either ]]
        animate_mouse_windowdragging = true,
    },
    render = { new_render_scheduling = false },
    animations = { enabled = true },
})
hl.curve("curveA", { type = "bezier", points = { {0.22, 1.0}, {0.36, 1.0} } })
hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "curveA", style = "popin 96%" })
hl.animation({ leaf = "border", enabled = true, speed = 2.0, bezier = "curveA" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "curveA" })
"""

conf = checks._hypr_conf(CONF)
lua = checks._hypr_lua(LUA)

check(conf, "the conf parser returns something")
check(lua, "the lua parser returns something")
check(set(conf) == set(lua), f"both dialects yield the same keys: only in conf {sorted(set(conf) - set(lua))}, only in lua {sorted(set(lua) - set(conf))}")
for key in sorted(set(conf) & set(lua)):
    check(str(conf[key]) == str(lua[key]), f"{key}: conf {conf[key]!r} vs lua {lua[key]!r}")

# The shapes that used to read differently and must not.
check(conf.get("general:col:active_border") == "rgba(4f8ff7cc)",
      "a dotted conf key flattens like the Lua's nested table")
check(conf.get("decoration:blur:size") == 6, "a nested conf block flattens")
check(lua.get("decoration:blur:size") == 6, "and so does a nested Lua table")
check(conf.get("animation:windows") == "1,2.0,curveA,popin 96%",
      f"a style with a space survives: {conf.get('animation:windows')!r}")
check(conf.get("animation:border") == "1,2.0,curveA", "a leaf without a style has no trailing comma")
check(conf.get("animation:borderangle") == "0,1.0,curveA",
      f"an off leaf keeps its flag: {conf.get('animation:borderangle')!r}")
check(conf.get("bezier:curveA") == "0.22,1.0,0.36,1.0", "the curve's points are read")

# A comment must not be read as a value, in either dialect.
check("misc:animate_mouse_windowdragging" in conf, "a commented block still yields its keys")
check(lua.get("misc:animate_mouse_windowdragging") == "true", "a commented Lua block still yields its keys")
check("misc:size" not in lua, f"a `--` comment inside a Lua section is not a setting: {sorted(lua)}")
check("misc:force_default_wallpaper" not in lua, "nor is a `--[[ ]]` comment")
check(not any(key.startswith("animation:") and key.startswith("animations:") for key in conf),
      "the animation leaves are not under the animations section")
check(conf.get("animations:enabled") == "true" and lua.get("animations:enabled") == "true",
      "the animations switch is compared")
check(conf.get("render:new_render_scheduling") == "false" and lua.get("render:new_render_scheduling") == "false",
      "the frame scheduling flag is compared")

# The config table is taken by brace count: a `})` later in the file - a
# window rule's - must not pull that rule into the config.
lua_with_rule = LUA + '\nhl.window_rule({ name = "r", match = { class = "^(x)$" }, misc = { size = 7 },\n})\n'
check(checks._hypr_lua(lua_with_rule).get("misc:size") is None, "a table after hl.config is not part of it")

# A drift is a difference, in a section that used to be outside the check.
drifted = checks._hypr_lua(LUA.replace("new_render_scheduling = false", "new_render_scheduling = true"))
problems = checks.hypr_drift(conf, drifted)
check(any(problem.startswith("render:new_render_scheduling") for problem in problems),
      f"a render drift is reported: {problems}")
check(checks.hypr_drift(conf, lua) == [], f"no drift between the two fixtures: {checks.hypr_drift(conf, lua)}")

# ---- the shell's copy of the animation table ---------------------------
JS = """
var BASE = [
    { leaf: "windows", speed: 2.0, bezier: "curveA", style: "popin 96%" },
    // fields in another order, and a comment with leaf: "not one" in it
    { style: "", bezier: "curveA", speed: 2.0, leaf: "border" },
    { leaf: "borderangle", speed: 1, bezier: "curveA", style: "", off: true }
]
function entries() { return BASE.map(entry => ({ leaf: entry.leaf })) }
"""
table = checks.animation_table(JS)
check([entry["leaf"] for entry in table] == ["windows", "border", "borderangle"],
      f"entries are read by field name, whatever the order: {table}")
check(table[2]["off"] is True and table[1]["off"] is False, "the off flag is read")
check(checks.animation_drift(conf, JS) == [], f"a table that matches the conf has no drift: {checks.animation_drift(conf, JS)}")
missing = checks.animation_drift(conf, JS.replace('    { style: "", bezier: "curveA", speed: 2.0, leaf: "border" },\n', ""))
check(missing == ["animation:border: in hyprland.conf but not in HyprAnimations.js"],
      f"a leaf the conf has and the table lacks is reported: {missing}")
extra = checks.animation_drift(conf, JS.replace('leaf: "border" }', 'leaf: "border" },\n    { leaf: "fade", speed: 1, bezier: "curveA", style: "" }'))
check(extra == ["animation:fade: in HyprAnimations.js but not in hyprland.conf"],
      f"a leaf the table has and the conf lacks is reported: {extra}")
changed = checks.animation_drift(conf, JS.replace("speed: 2.0, leaf: \"border\"", "speed: 3.0, leaf: \"border\""))
check(len(changed) == 1 and changed[0].startswith("animation:border: HyprAnimations.js '1,3.0,curveA'"),
      f"a changed speed is reported: {changed}")
unreadable = checks.animation_drift(conf, JS.replace('{ leaf: "windows",', '{ leaf: "windows", extra: { nested: 1 },'))
check(len(unreadable) == 1 and "3 leaves but 2 entries" in unreadable[0],
      f"an entry the reader cannot parse is an error, not a shorter table: {unreadable}")

# ---- springs: Lua only, the curve is where the dialects may differ ---------
SPRING_LUA = LUA.replace('hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "curveA", style = "popin 96%" })',
                         'hl.curve("springA", { type = "spring", mass = 1, stiffness = 380, dampening = 34 })\n'
                         'hl.animation({ leaf = "windows", enabled = true, speed = 2.0, spring = "springA", style = "popin 96%" })')
spring_lua = checks._hypr_lua(SPRING_LUA)
check(spring_lua.get("spring:springA") == "1.0,380.0,34.0", f"a spring curve is read by field name: {spring_lua.get('spring:springA')!r}")
check(spring_lua.get("animation:windows") == "1,2.0,springA,popin 96%", f"a leaf with a spring names it: {spring_lua.get('animation:windows')!r}")
check(checks.hypr_drift(conf, spring_lua) == [], f"a spring in Lua and a bezier in the conf is not drift: {checks.hypr_drift(conf, spring_lua)}")
check(any(p.startswith("animation:windows") for p in checks.hypr_drift(conf, checks._hypr_lua(SPRING_LUA.replace("speed = 2.0, spring", "speed = 3.0, spring")))),
      "but a different speed still is")
SPRING_JS = JS.replace('{ leaf: "windows", speed: 2.0, bezier: "curveA", style: "popin 96%" }',
                       '{ leaf: "windows", speed: 2.0, spring: "springA", bezier: "curveA", style: "popin 96%" }') + \
    '\nvar SPRINGS = [\n    { name: "springA", mass: 1, stiffness: 380, dampening: 34 }\n]\n'
check(checks.animation_drift(conf, SPRING_JS, spring_lua) == [],
      f"Lua's spring, the conf's bezier and the table agree: {checks.animation_drift(conf, SPRING_JS, spring_lua)}")
stiffer = checks.animation_drift(conf, SPRING_JS.replace("stiffness: 380", "stiffness: 400"), spring_lua)
check(len(stiffer) == 1 and stiffer[0].startswith("spring:springA"), f"a spring that drifts is reported: {stiffer}")
wrong_curve = checks.animation_drift(conf, SPRING_JS, lua)
check(any("animates with 'curveA'" in p for p in wrong_curve), f"a Lua leaf on the bezier where the table has a spring is reported: {wrong_curve}")

# The environment, the window rules, the panels' no_anim rule and the hidden
# helpers' classes, which the settings above do not cover.
ENV_CONF = "env = XCURSOR_SIZE,24\nenv = XDG_CURRENT_DESKTOP,buchhwin-shell:Hyprland  # why\n"
ENV_LUA = 'hl.env("XCURSOR_SIZE", "24")\n-- hl.env("XCURSOR_SIZE", "32")\nhl.env("XDG_CURRENT_DESKTOP", "buchhwin-shell:Hyprland")\n'
conf_env, lua_env = checks._conf_env(ENV_CONF), checks._lua_env(ENV_LUA)
check(conf_env == {"XCURSOR_SIZE": "24", "XDG_CURRENT_DESKTOP": "buchhwin-shell:Hyprland"}, f"env lines are read: {conf_env}")
check(checks.env_drift(conf_env, lua_env) == [], f"the same env in both dialects is no drift: {checks.env_drift(conf_env, lua_env)}")
drifted = checks.env_drift(conf_env, checks._lua_env(ENV_LUA.replace('"24"', '"32"', 1)))
check(len(drifted) == 1 and drifted[0].startswith("env XCURSOR_SIZE"), f"a value in one dialect only is: {drifted}")
check(checks.env_drift(conf_env, {"XCURSOR_SIZE": "24"}) != [], "and so is a line missing in one")

RULES_CONF = """windowrule {
    name = buchhwin-hidden-windows
    match:class = ^(helper|other)$
    workspace = special:hidden silent
    float = on
    opacity = 0.0 override
}
"""
RULES_LUA = """hl.window_rule({
    name = "buchhwin-hidden-windows",
    match = { class = "^(helper|other)$" },
    workspace = "special:hidden silent",
    float = true,
    opacity = "0.0 override",
})
"""
conf_rules, lua_rules = checks._conf_window_rules(RULES_CONF), checks._lua_window_rules(RULES_LUA)
rule = conf_rules.get("buchhwin-hidden-windows", {})
check(rule.get("match:class") == "^(helper|other)$" and len(rule) == 4,
      f"a conf window rule is read field by field: {conf_rules}")
check(checks.window_rule_drift(conf_rules, lua_rules) == [], f"the same rule in both dialects is no drift: {checks.window_rule_drift(conf_rules, lua_rules)}")
off = checks.window_rule_drift(conf_rules, checks._lua_window_rules(RULES_LUA.replace("float = true", "float = false")))
check(len(off) == 1 and "float" in off[0], f"a field that differs is reported: {off}")
check(any("only in" in p for p in checks.window_rule_drift(conf_rules, {})), "a rule in one dialect only is reported")
check(checks.hidden_window_problems(["helper"], conf_rules, lua_rules) == [], "a hidden class both rules match passes")
hidden = checks.hidden_window_problems(["helper", "bridge"], conf_rules, lua_rules)
check(len(hidden) == 2 and all("bridge" in p for p in hidden), f"a class the rules do not match is reported in each dialect: {hidden}")
check(checks.hidden_window_classes('var classes = ["a", "b"]\n') == ["a", "b"], "HiddenWindows.js's classes are read")

layers = checks._conf_layer_rules("layerrule = no_anim on, match:namespace ^(buchhwin-(launcher|osd))$\n")
check(checks.no_anim_problems({"launcher", "colorPicker"}, layers, "conf") == [],
      "a panel in the no_anim rule passes, and the colour picker is left out on purpose")
missing_panel = checks.no_anim_problems({"launcher", "startMenu"}, layers, "conf")
check(len(missing_panel) == 1 and "startMenu" in missing_panel[0], f"a panel outside it is reported: {missing_panel}")

if failures:
    for failure in failures:
        print("FAIL hypr_drift: " + failure)
    print(f"TESTS FAILED hypr_drift ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED hypr_drift")
