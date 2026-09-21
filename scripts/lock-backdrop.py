#!/usr/bin/env python3
"""Blurred lock screen backdrops from the current screen contents.

  lock-backdrop.py capture DIR    one DIR/<monitor>.png per enabled monitor

Every monitor is captured with grim through a pipe, reduced to at most
MAX_SIDE pixels and blurred, so text and details cannot be recovered; only
colours and rough shapes remain. The unblurred frame is never written to disk.
"""

import io
import json
import os
import pathlib
import re
import subprocess
import sys

from PIL import Image, ImageFilter

MAX_SIDE = 64


def blur(image):
    """A tiny, blurred copy of `image` (RGB)."""
    image = image.convert("RGB")
    width, height = image.size
    scale = MAX_SIDE / max(width, height, 1)
    small = image.resize((max(1, round(width * scale)), max(1, round(height * scale))), Image.Resampling.BOX)
    return small.filter(ImageFilter.GaussianBlur(1.2))


def monitors():
    output = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, timeout=5, check=True).stdout
    return [item["name"] for item in json.loads(output) if not item.get("disabled")]


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9._-]", "_", name)


def capture(directory):
    directory = pathlib.Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = []
    for name in monitors():
        try:
            frame = subprocess.run(["grim", "-o", name, "-t", "ppm", "-"], capture_output=True, timeout=5, check=True).stdout
            small = blur(Image.open(io.BytesIO(frame)))
        except (subprocess.SubprocessError, OSError, ValueError):
            continue
        target = directory / (safe_name(name) + ".png")
        handle = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(handle, "wb") as stream:
            small.save(stream, "PNG")
        written.append(name)
    return written


def main(argv):
    if len(argv) != 2 or argv[0] != "capture":
        print(__doc__, file=sys.stderr)
        return 2
    try:
        print(json.dumps({"monitors": capture(argv[1])}))
    except (subprocess.SubprocessError, OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
