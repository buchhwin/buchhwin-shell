#!/usr/bin/env python3
"""Pick a restrained accent color from a wallpaper.

Prints {"accent": "#rrggbb"}. The most common vivid hue wins (weighted by
saturation and brightness); the result is normalised to a calm, readable
accent so white text and toggles keep enough contrast. Images without vivid
colours fall back to the default blue.

An image that is missing or cannot be read (or a system without Pillow) is not
an image without vivid colours: it prints {"accent": "", "error": ...} and
exits 1, and the shell keeps the accent it has. The default blue in that case
turned the accent blue on every machine without the shipped wallpaper file.

With --cache FILE the answer is kept there with the image's path, mtime and
size, and the same image again is answered from it without being decoded: a
login asked for the accent of a 6000x3750 PNG that had not changed. A cache
that cannot be read or written is simply no cache.

  wallpaper-accent.py [--cache FILE] IMAGE
"""

import colorsys
import json
import os
import re
import sys
import tempfile

DEFAULT = "#4f8ff7"
ACCENT = re.compile(r"^#[0-9a-f]{6}$")


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


def image_key(path):
    """What the cached answer is for: a new mtime or size is a new image. Raises OSError when it is not there."""
    info = os.stat(path)
    return {"path": os.path.abspath(path), "mtime": info.st_mtime_ns, "size": info.st_size}


def cached(cache, key):
    """The accent kept for KEY, or None."""
    try:
        with open(cache, encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or any(data.get(name) != value for name, value in key.items()):
        return None
    accent = data.get("accent")
    return accent if isinstance(accent, str) and ACCENT.match(accent) else None


def remember(cache, key, accent):
    """Keep ACCENT for KEY, replacing what was kept; quietly nothing when it cannot be written."""
    directory = os.path.dirname(os.path.abspath(cache))
    temporary = ""
    try:
        os.makedirs(directory, exist_ok=True)
        handle, temporary = tempfile.mkstemp(dir=directory, prefix=".wallpaper-accent-")
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(dict(key, accent=accent), stream)
        os.replace(temporary, cache)
    except OSError:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def no_accent(reason):
    print(json.dumps({"accent": "", "error": reason}))
    return 1


def main(argv):
    cache = ""
    if len(argv) == 3 and argv[0] == "--cache":
        cache, argv = argv[1], argv[2:]
    if len(argv) != 1 or not argv[0]:
        print(__doc__, file=sys.stderr)
        return 2
    path = argv[0]
    try:
        key = image_key(path)
    except OSError:
        return no_accent("the image is not there")
    accent = cached(cache, key) if cache else None
    if accent:
        print(json.dumps({"accent": accent}))
        return 0
    try:
        from PIL import Image
        with Image.open(path) as image:
            accent = accent_for(image)
    except Exception:  # noqa: BLE001 - an unreadable image or no Pillow
        return no_accent("the image cannot be read")
    if cache:
        remember(cache, key, accent)
    print(json.dumps({"accent": accent}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
