#!/usr/bin/env python3
"""Pick a colour off the screen.

  color-picker.py capture DIR   freeze every monitor into DIR and serve pixels

One capture, then a question-and-answer loop on stdin: each line is a pair of
**global compositor coordinates** and the answer is the hex colour of that
pixel, or an empty line when the point is on no monitor. One process rather
than one per sample, because the overlay asks on every pointer move and
re-reading a 1920x1200 PNG sixty times a second is not a thing to do.

The frozen frames are what the overlay shows, so what is sampled and what is
seen are the same pixels - a live screen and a sampled capture drift apart the
moment anything under the pointer animates.

Written to DIR (0700, caller's), never to the clipboard: copying is the
shell's job, and it already knows how.
"""

import io
import json
import os
import pathlib
import re
import subprocess
import sys

from PIL import Image


def monitors():
    """Enabled monitors, with the geometry needed to map a global point."""
    output = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True,
                            text=True, timeout=5, check=True).stdout
    found = []
    for item in json.loads(output):
        if item.get("disabled"):
            continue
        found.append({
            "name": item["name"],
            "x": int(item.get("x", 0)),
            "y": int(item.get("y", 0)),
            # Logical size, which is what a global coordinate is in.
            "width": round(int(item["width"]) / float(item.get("scale", 1) or 1)),
            "height": round(int(item["height"]) / float(item.get("scale", 1) or 1)),
            "scale": float(item.get("scale", 1) or 1),
        })
    return found


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9._-]", "_", name)


def pixel_at(monitor, image, gx, gy):
    """The colour at a global point, or None when it is off this monitor."""
    local_x = gx - monitor["x"]
    local_y = gy - monitor["y"]
    if not (0 <= local_x < monitor["width"] and 0 <= local_y < monitor["height"]):
        return None
    # A global coordinate is logical; the captured frame is in real pixels.
    px = min(image.width - 1, max(0, round(local_x * monitor["scale"])))
    py = min(image.height - 1, max(0, round(local_y * monitor["scale"])))
    red, green, blue = image.convert("RGB").getpixel((px, py))
    return "#%02x%02x%02x" % (red, green, blue)


def capture(directory):
    directory = pathlib.Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    frames = []
    for monitor in monitors():
        try:
            raw = subprocess.run(["grim", "-o", monitor["name"], "-t", "ppm", "-"],
                                 capture_output=True, timeout=5, check=True).stdout
            image = Image.open(io.BytesIO(raw)).convert("RGB")
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            print("color-picker: cannot capture %s: %s" % (monitor["name"], error), file=sys.stderr)
            continue
        path = directory / (safe_name(monitor["name"]) + ".png")
        image.save(path)
        os.chmod(path, 0o600)
        frames.append((monitor, image, path))
    return frames


def serve(frames):
    """One hex colour per line of "x y" on stdin, flushed as it goes."""
    print(json.dumps([{"name": m["name"], "x": m["x"], "y": m["y"],
                       "width": m["width"], "height": m["height"],
                       "file": str(path)} for m, _, path in frames]), flush=True)
    for line in sys.stdin:
        parts = line.split()
        if len(parts) != 2:
            print("", flush=True)
            continue
        try:
            gx, gy = round(float(parts[0])), round(float(parts[1]))
        except ValueError:
            print("", flush=True)
            continue
        answer = ""
        for monitor, image, _ in frames:
            found = pixel_at(monitor, image, gx, gy)
            if found:
                answer = found
                break
        print(answer, flush=True)


def main(argv):
    if len(argv) != 3 or argv[1] != "capture":
        print(__doc__, file=sys.stderr)
        return 2
    frames = capture(argv[2])
    if not frames:
        print("color-picker: nothing captured", file=sys.stderr)
        return 1
    serve(frames)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
