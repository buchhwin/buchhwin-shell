#!/usr/bin/env python3
"""scripts/color-picker.py: the global-point to pixel mapping, against stub
monitors and images made here. No grim, no compositor, no host screen."""
import importlib.util
import json
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "scripts", "color-picker.py")

spec = importlib.util.spec_from_file_location("color_picker", SCRIPT)
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)

failures = []


def check(name, got, expected):
    if got != expected:
        failures.append(f"{name}: expected {expected!r}, got {got!r}")


def solid(width, height, colour):
    return Image.new("RGB", (width, height), colour)


# A monitor at the origin, no scaling: a global point is a pixel.
plain = {"name": "DP-1", "x": 0, "y": 0, "width": 100, "height": 50, "scale": 1.0}
image = solid(100, 50, (18, 52, 86))
image.putpixel((10, 20), (255, 0, 0))
check("a plain pixel", picker.pixel_at(plain, image, 0, 0), "#123456")
check("the marked pixel", picker.pixel_at(plain, image, 10, 20), "#ff0000")
check("the last pixel", picker.pixel_at(plain, image, 99, 49), "#123456")

# Off the monitor is no answer at all, rather than the nearest pixel: with
# several monitors the caller asks each in turn and needs to be told no.
check("past the right edge", picker.pixel_at(plain, image, 100, 10), None)
check("past the bottom", picker.pixel_at(plain, image, 10, 50), None)
check("above the top", picker.pixel_at(plain, image, 10, -1), None)
check("left of the left edge", picker.pixel_at(plain, image, -1, 10), None)

# A monitor that is not at the origin: the point is global, the pixel is local.
moved = {"name": "DP-2", "x": 1920, "y": 0, "width": 100, "height": 50, "scale": 1.0}
check("a point on the second monitor", picker.pixel_at(moved, image, 1930, 20), "#ff0000")
check("and the same point is off the first", picker.pixel_at(plain, image, 1930, 20), None)

# A scaled monitor: a global coordinate is logical, the frame is real pixels.
# This is the one that goes wrong quietly - it answers a colour either way,
# just the wrong one.
scaled = {"name": "eDP-1", "x": 0, "y": 0, "width": 100, "height": 50, "scale": 2.0}
big = solid(200, 100, (0, 0, 0))
big.putpixel((20, 40), (0, 255, 0))
check("a scaled point reads the scaled pixel", picker.pixel_at(scaled, big, 10, 20), "#00ff00")
check("and its unscaled neighbour is not it", picker.pixel_at(scaled, big, 11, 20), "#000000")
# The last logical pixel must not round past the end of the frame.
check("the last logical pixel is inside the frame", picker.pixel_at(scaled, big, 99, 49), "#000000")

# A fractional scale, which is what many laptops actually run.
fractional = {"name": "eDP-1", "x": 0, "y": 0, "width": 1280, "height": 800, "scale": 1.5}
frame = solid(1920, 1200, (1, 2, 3))
frame.putpixel((960, 600), (200, 100, 50))
check("a fractional scale lands on the pixel", picker.pixel_at(fractional, frame, 640, 400), "#c86432")

# The monitor list, from a stand-in for `hyprctl -j monitors` - the module's
# subprocess.run is replaced, so no compositor is asked. Hyprland reports the
# mode unrotated; a monitor on its side (odd transform) must come out as tall
# as its mode is wide, or the lower part of it is "on no monitor".
HYPRCTL = json.dumps([
    {"name": "DP-1", "x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 2.0, "transform": 0},
    {"name": "DP-2", "x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 1.0, "transform": 1},
    {"name": "DP-3", "x": 4360, "y": 0, "width": 1920, "height": 1080, "scale": 1.0, "transform": 2},
    {"name": "HDMI-A-1", "x": 6280, "y": 0, "width": 1920, "height": 1080, "scale": 1.0, "transform": 7},
    {"name": "eDP-1", "x": 0, "y": 0, "width": 1920, "height": 1200, "scale": 1.0, "disabled": True},
])
calls = []


def fake_run(command, **_kwargs):
    calls.append(command)
    return subprocess.CompletedProcess(command, 0, stdout=HYPRCTL, stderr="")


real_run = picker.subprocess.run
picker.subprocess.run = fake_run
try:
    listed = {m["name"]: (m["width"], m["height"]) for m in picker.monitors()}
finally:
    picker.subprocess.run = real_run
check("only hyprctl was asked", [c[0] for c in calls], ["hyprctl"])
check("a disabled monitor is left out", "eDP-1" in listed, False)
check("an upright monitor keeps its mode, scaled", listed.get("DP-1"), (1920, 1080))
check("a monitor on its side is tall", listed.get("DP-2"), (1440, 2560))
check("upside down is still wide", listed.get("DP-3"), (1920, 1080))
check("flipped and turned is tall", listed.get("HDMI-A-1"), (1080, 1920))

# A point in the lower half of the portrait monitor, past where its unrotated
# height would end, is on it. grim's frame of it is upright (1440x2560).
portrait = {"name": "DP-2", "x": 1920, "y": 0, "width": 1440, "height": 2560, "scale": 1.0}
upright = solid(1440, 2560, (9, 9, 9))
upright.putpixel((100, 2000), (0, 0, 255))
check("the lower part of a portrait monitor is pickable", picker.pixel_at(portrait, upright, 2020, 2000), "#0000ff")

if failures:
    for failure in failures:
        print("FAIL color_picker_test: " + failure)
    print("TESTS FAILED color_picker_test (%d failed)" % len(failures))
    sys.exit(1)
print("TESTS PASSED color_picker_test")
