#!/usr/bin/env python3
"""Unit test for scripts/wallpaper-accent.py with synthetic images."""

import colorsys
import importlib.util
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("accent", ROOT / "scripts" / "wallpaper-accent.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def hue_of(hex_colour):
    red, green, blue = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return colorsys.rgb_to_hsv(red, green, blue)[0] * 360


orange = Image.new("RGB", (200, 120), (230, 120, 40))
result = module.accent_for(orange)
check(abs(hue_of(result) - 26) < 8, "orange wallpaper gives an orange accent: " + result)

mixed = Image.new("RGB", (200, 120), (20, 90, 200))
mixed.paste((200, 40, 40), (0, 0, 40, 120))
check(200 < hue_of(module.accent_for(mixed)) < 230, "dominant blue wins over a red stripe")

check(module.accent_for(Image.new("RGB", (100, 100), (128, 128, 128))) == module.DEFAULT, "grey image keeps the default")
check(module.accent_for(Image.new("RGB", (100, 100), (5, 5, 30))) == module.DEFAULT, "near-black image keeps the default")

red, green, blue = (int(result[i:i + 2], 16) / 255 for i in (1, 3, 5))
lightness = colorsys.rgb_to_hls(red, green, blue)[1]
check(0.55 < lightness < 0.65, "accent lightness is normalised")

for failure in failures:
    print("FAIL wallpaper_accent_test:", failure)
print("TESTS %s wallpaper_accent_test" % ("FAILED" if failures else "PASSED"))
sys.exit(1 if failures else 0)
