#!/usr/bin/env python3
"""Pick a colour off the screen.

  color-picker.py capture DIR   freeze every monitor into DIR and serve pixels

One capture, then a question-and-answer loop on stdin: each line is a pair of
**global compositor coordinates** and the answer is the hex colour of that
pixel, or an empty line when the point is on no monitor. One process rather
than one per sample, because the overlay asks on every pointer move and
re-reading a 1920x1200 frame sixty times a second is not a thing to do.

The frozen frames are what the overlay shows, so what is sampled and what is
seen are the same pixels - a live screen and a sampled capture drift apart the
moment anything under the pointer animates.

Written to DIR (0700, caller's), never to the clipboard: copying is the
shell's job, and it already knows how. The frames are screenshots of
everything on screen - a password manager, a chat - so they go again when the
picker ends: when stdin closes or the shell stops this process (SIGTERM).
"""

import io
import json
import os
import pathlib
import re
import signal
import subprocess
import sys

from PIL import Image

# The frames as PPM, which is what grim sends: the overlay's Qt reads it with
# its own handler, and writing it costs a few milliseconds. As PNG every frame
# was compressed first, one monitor after the other, before the overlay could
# open - 240 ms for 1920x1200 and about a second per 4K screen. Raw frames
# are larger (7 MB at 1920x1200, 25 MB at 4K) but live in tmpfs only while
# the picker is open.
FRAME_SUFFIX = ".ppm"
# What an earlier picker may have left of a monitor (one killed outright, or
# one from before the frames were removed at the end).
LEFTOVER_SUFFIXES = (".ppm", ".png")


def monitors():
    """Enabled monitors, with the geometry needed to map a global point."""
    output = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True,
                            text=True, timeout=5, check=True).stdout
    found = []
    for item in json.loads(output):
        if item.get("disabled"):
            continue
        scale = float(item.get("scale", 1) or 1)
        width, height = int(item["width"]), int(item["height"])
        # The mode is the panel's, unrotated. A monitor on its side (an odd
        # transform) is as wide as its mode is high, and grim's frame of it
        # is upright too.
        if int(item.get("transform", 0) or 0) % 2:
            width, height = height, width
        found.append({
            "name": item["name"],
            "x": int(item.get("x", 0)),
            "y": int(item.get("y", 0)),
            # Logical size, which is what a global coordinate is in.
            "width": round(width / scale),
            "height": round(height / scale),
            "scale": scale,
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
    # The frames are RGB from the capture on; a convert() here would copy the
    # whole frame on every pointer move.
    red, green, blue = image.getpixel((px, py))
    return "#%02x%02x%02x" % (red, green, blue)


def grab(names):
    """{name: PPM bytes or an error} for every monitor, all at once.

    One grim per monitor, started together: one after the other, the overlay
    waited for every screen's capture in turn."""
    started = []
    for name in names:
        try:
            started.append((name, subprocess.Popen(["grim", "-o", name, "-t", "ppm", "-"],
                                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)))
        except OSError as error:
            started.append((name, error))
    results = {}
    for name, process in started:
        if isinstance(process, OSError):
            results[name] = process
            continue
        try:
            out, err = process.communicate(timeout=5)
        except subprocess.TimeoutExpired as error:
            process.kill()
            process.communicate()
            results[name] = error
            continue
        if process.returncode != 0:
            results[name] = OSError("grim exited with %d: %s" % (process.returncode, err.decode(errors="replace").strip()))
        else:
            results[name] = out
    return results


def remove(paths):
    for path in paths:
        try:
            os.unlink(path)
        except OSError:
            pass


def sweep(directory, monitors_found):
    """Frames an earlier picker left of these monitors in DIR - nothing else
    there is touched, whatever DIR is."""
    remove([directory / (safe_name(monitor["name"]) + suffix)
            for monitor in monitors_found for suffix in LEFTOVER_SUFFIXES])


def capture(directory, written=None):
    """Freeze every monitor into DIR. `written` collects each file as soon as
    it exists, so a stop halfway through can still remove them."""
    directory = pathlib.Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = [] if written is None else written
    found = monitors()
    sweep(directory, found)
    raw_frames = grab([monitor["name"] for monitor in found])
    frames = []
    for monitor in found:
        try:
            raw = raw_frames.get(monitor["name"])
            if isinstance(raw, Exception):
                raise raw
            image = Image.open(io.BytesIO(raw))
            # grim's PPM is RGB already; a convert() would copy it once more.
            image = image.convert("RGB") if image.mode != "RGB" else image
            image.load()
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            print("color-picker: cannot capture %s: %s" % (monitor["name"], error), file=sys.stderr)
            continue
        path = directory / (safe_name(monitor["name"]) + FRAME_SUFFIX)
        # Created 0600, so the screenshot is never readable by others, not
        # even for a moment.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        written.append(path)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as file:
            image.save(file, format="PPM")
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


def terminate(_signum, _frame):
    # The shell stops the helper with SIGTERM when the overlay closes, and
    # Python's default for it ends the process on the spot - past every
    # `finally`, frames and all. As SystemExit it runs the clean-up below.
    sys.exit(0)


def main(argv):
    if len(argv) != 3 or argv[1] != "capture":
        print(__doc__, file=sys.stderr)
        return 2
    signal.signal(signal.SIGTERM, terminate)
    written = []
    try:
        frames = capture(argv[2], written)
        if not frames:
            print("color-picker: nothing captured", file=sys.stderr)
            return 1
        serve(frames)
        return 0
    finally:
        remove(written)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
