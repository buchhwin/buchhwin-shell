#!/usr/bin/env python3
"""scripts/color-picker.py: the global-point to pixel mapping, against stub
monitors and images made here. No grim, no compositor, no host screen."""
import importlib.util
import os
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

# A fractional scale, which is what this machine actually runs.
fractional = {"name": "eDP-1", "x": 0, "y": 0, "width": 1280, "height": 800, "scale": 1.5}
frame = solid(1920, 1200, (1, 2, 3))
frame.putpixel((960, 600), (200, 100, 50))
check("a fractional scale lands on the pixel", picker.pixel_at(fractional, frame, 640, 400), "#c86432")

if failures:
    for failure in failures:
        print("FAIL color_picker_test: " + failure)
    print("TESTS FAILED color_picker_test (%d failed)" % len(failures))
    sys.exit(1)
print("TESTS PASSED color_picker_test")
