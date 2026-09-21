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

animations {
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
        animate_mouse_windowdragging = true,
    },
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

# A comment must not be read as a value, and a section outside the scope is
# left alone rather than half-compared.
check("misc:animate_mouse_windowdragging" in conf, "a commented block still yields its keys")
check(not any(key.startswith("animations:") for key in conf), "the animations block itself is not a scalar section")

if failures:
    for failure in failures:
        print("FAIL hypr_drift: " + failure)
    print(f"TESTS FAILED hypr_drift ({len(failures)} failed)")
    sys.exit(1)
print("TESTS PASSED hypr_drift")
