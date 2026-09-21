#!/usr/bin/env python3
"""Unit test for scripts/lock-backdrop.py: backdrops must not be readable."""

import importlib.util
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("lock_backdrop", ROOT / "scripts" / "lock-backdrop.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


# A "screen" with dense black text on white, like a terminal or document.
screen = Image.new("RGB", (1920, 1200), (250, 250, 250))
draw = ImageDraw.Draw(screen)
font = ImageFont.load_default()
for row in range(0, 1200, 14):
    draw.text((10, row), "password: hunter2 secret mail from boss 0123456789 " * 4, fill=(0, 0, 0), font=font)
draw.rectangle((1400, 100, 1900, 500), fill=(40, 90, 200))

small = module.blur(screen)
check(max(small.size) <= module.MAX_SIDE, "backdrop is at most MAX_SIDE pixels")
check(abs(small.size[0] / small.size[1] - 1920 / 1200) < 0.05, "aspect ratio kept")

pixels = small.load()
width, height = small.size
# Text area: neighbouring pixels differ only slightly (no glyph edges left).
jumps = [abs(sum(pixels[x, y]) - sum(pixels[x + 1, y])) for y in range(height) for x in range(width // 2 - 1)]
check(max(jumps) < 60, "no sharp edges remain in the text area (max %d)" % max(jumps))
# Colours survive: the blue block is still bluish.
r, g, b = pixels[int(width * 0.86), int(height * 0.25)]
check(b > r + 30, "colours and rough shapes remain")
# A tiny image stays tiny and valid.
check(module.blur(Image.new("RGB", (10, 5))).size[0] <= module.MAX_SIDE, "small inputs work")
check(module.safe_name("DP-1/../x") == "DP-1_.._x", "monitor names are safe file names")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED lock_backdrop_test")
    sys.exit(1)
print("TESTS PASSED lock_backdrop_test")
