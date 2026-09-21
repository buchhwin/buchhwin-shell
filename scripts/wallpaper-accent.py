#!/usr/bin/env python3
"""Pick a restrained accent color from a wallpaper.

Prints {"accent": "#rrggbb"}. The most common vivid hue wins (weighted by
saturation and brightness); the result is normalised to a calm, readable
accent so white text and toggles keep enough contrast. Images without vivid
colours fall back to the default blue.

  wallpaper-accent.py IMAGE
"""

import colorsys
import json
import sys

DEFAULT = "#4f8ff7"


def accent_for(image):
    small = image.convert("RGB").resize((64, 64))
    bins = [0.0] * 36
    hue_sum = [0.0] * 36
    data = small.tobytes()
    for offset in range(0, len(data), 3):
        red, green, blue = data[offset], data[offset + 1], data[offset + 2]
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if saturation < 0.25 or value < 0.25:
            continue
        weight = saturation * value
        index = int(hue * 36) % 36
        bins[index] += weight
        hue_sum[index] += hue * weight
    best = max(range(36), key=lambda index: bins[index])
    # Too few vivid pixels (grey, black or white images) keep the default.
    if bins[best] < 64 * 64 * 0.02:
        return DEFAULT
    hue = hue_sum[best] / bins[best]
    red, green, blue = colorsys.hls_to_rgb(hue, 0.6, 0.72)
    return "#%02x%02x%02x" % (round(red * 255), round(green * 255), round(blue * 255))


def main(argv):
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        from PIL import Image
        with Image.open(argv[0]) as image:
            accent = accent_for(image)
    except Exception:  # noqa: BLE001 - unreadable image or missing Pillow
        accent = DEFAULT
    print(json.dumps({"accent": accent}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
