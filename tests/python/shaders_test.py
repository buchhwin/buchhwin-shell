#!/usr/bin/env python3
"""The color filters' shaders are there and are shaders Hyprland can run.

services/hypr/ScreenEffectsLogic.js names a file under shaders/ for each
filter, and Hyprland compiles the one chosen when the shell sets
decoration:screen_shader - a missing file or one that does not compile shows
up only on screen, as a filter that does nothing (and a line in Hyprland's
log). This holds every named file to the frame Hyprland hands a screen
shader (`tex`, `v_texcoord`, GLSL ES 3.00), checks that no file under
shaders/ is left without a filter, and compiles each one with
glslangValidator where it is installed. The filters keep white white, which
is the first thing a broken matrix would lose.
"""

import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOGIC = ROOT / "services" / "hypr" / "ScreenEffectsLogic.js"
SHADERS = ROOT / "shaders"

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


block = re.search(r"var FILTERS = \[(.*?)\n\]", LOGIC.read_text(encoding="utf-8"), re.S)
named = re.findall(r'file: "([^"]+)"', block.group(1)) if block else []
check(len(named) >= 5, f"the filters' files were read from ScreenEffectsLogic.js ({named})")

present = sorted(path.name for path in SHADERS.glob("*.frag"))
check(sorted(named) == present, f"every filter has its file and every file a filter: {sorted(named)} vs {present}")

compiler = shutil.which("glslangValidator")
for name in named:
    path = SHADERS / name
    if not path.is_file():
        failures.append(f"shaders/{name} is missing")
        continue
    text = path.read_text(encoding="utf-8")
    check(text.startswith("#version 300 es\n"), f"shaders/{name}: GLSL ES 3.00 on its first line")
    check(re.search(r"^uniform sampler2D tex;$", text, re.M) is not None, f"shaders/{name}: reads the frame as `tex`")
    check(re.search(r"^in vec2 v_texcoord;$", text, re.M) is not None, f"shaders/{name}: and the place as `v_texcoord`")
    check("fragColor" in text, f"shaders/{name}: writes fragColor")
    if compiler:
        result = subprocess.run([compiler, "-S", "frag", str(path)], capture_output=True, text=True)
        check(result.returncode == 0, f"shaders/{name} does not compile: {result.stdout.strip()} {result.stderr.strip()}")


# The daltonize matrices, as the three correction shaders write them: white
# and a grey must come out as they went in (nothing lost, nothing shifted).
def matrix(text, name):
    found = re.search(name + r" = mat3\((.*?)\);", text, re.S)
    numbers = [float(value) for value in re.findall(r"-?\d+\.\d+", found.group(1))] if found else []
    # GLSL fills a mat3 column by column.
    return [[numbers[column * 3 + row] for column in range(3)] for row in range(3)] if len(numbers) == 9 else None


def times(m, v):
    return [sum(m[row][k] * v[k] for k in range(3)) for row in range(3)]


# What the eye without one kind of cone sees, as the shader's own `seen` line
# writes it: three sums of `factor * lms.c` (or a bare `lms.c`), one per cone.
# Read from the file rather than copied here, so a wrong factor there fails.
def simulation(text):
    found = re.search(r"vec3 seen = vec3\((.*?)\);", text)
    parts = found.group(1).split(",") if found else []
    if len(parts) != 3:
        return None
    rows = []
    for part in parts:
        terms = re.findall(r"([+-]?)\s*(?:(\d+\.\d+)\s*\*\s*)?lms\.([xyz])", part)
        if not terms:
            return None
        rows.append([((-1.0 if sign == "-" else 1.0) * (float(factor) if factor else 1.0), "xyz".index(cone))
                     for sign, factor, cone in terms])
    return lambda lms: [sum(factor * lms[cone] for factor, cone in row) for row in rows]


for name in ("protanopia.frag", "deuteranopia.frag", "tritanopia.frag"):
    path = SHADERS / name
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    to_lms, to_rgb, simulate = matrix(text, "rgbToLms"), matrix(text, "lmsToRgb"), simulation(text)
    check(None not in (to_lms, to_rgb, simulate), f"shaders/{name}: both matrices and the simulation are read")
    if None in (to_lms, to_rgb, simulate):
        continue
    for grey in (1.0, 0.5):
        rgb = [grey, grey, grey]
        lost = [a - b for a, b in zip(rgb, times(to_rgb, simulate(times(to_lms, rgb))))]
        check(all(abs(value) < 0.02 for value in lost), f"shaders/{name}: grey {grey} loses nothing ({lost})")

if failures:
    for failure in failures:
        print("FAIL shaders: " + failure)
    sys.exit(1)
print(f"TESTS PASSED shaders ({len(named)} filters{', compiled' if compiler else ''})")
