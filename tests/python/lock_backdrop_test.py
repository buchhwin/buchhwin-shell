#!/usr/bin/env python3
"""Unit test for scripts/lock-backdrop.py: backdrops must not be readable."""

import importlib.util
import os
import pathlib
import stat
import sys
import tempfile

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
# grim's PPM opens as RGB, and that frame is reduced without a copy; other
# modes are still converted.
check(module.blur(Image.new("RGBA", (40, 20), (10, 20, 30, 0))).mode == "RGB", "other modes are converted")
check(module.blur(Image.new("L", (40, 20), 128)).mode == "RGB", "greyscale too")

# The capture, against stub hyprctl and grim on PATH: one backdrop per enabled
# monitor, private, and every monitor's grim started before the first frame
# is read (each stub takes 0.4 s; one after another, the second would start
# only once the first had ended).
with tempfile.TemporaryDirectory() as sandbox:
    sandbox = pathlib.Path(sandbox)
    stubs = sandbox / "bin"
    stubs.mkdir()
    log = sandbox / "grim.log"
    (stubs / "hyprctl").write_text(
        "#!/bin/sh\n"
        "echo '[{\"name\": \"eDP-1\"}, {\"name\": \"DP-1/x\"}, {\"name\": \"HDMI-A-1\", \"disabled\": true}, {\"name\": \"DP-9\"}]'\n")
    # DP-9's grim fails: that monitor gets no backdrop, the others do.
    (stubs / "grim").write_text(
        "#!/bin/sh\n"
        "echo \"start $2 $(date +%s%N)\" >> \"$GRIM_LOG\"\n"
        "sleep 0.4\n"
        "[ \"$2\" = DP-9 ] && exit 1\n"
        "printf 'P6\\n4 2\\n255\\n'\n"
        "head -c 24 /dev/zero | tr '\\000' '\\200'\n"
        "echo \"end $2 $(date +%s%N)\" >> \"$GRIM_LOG\"\n")
    for stub in stubs.iterdir():
        stub.chmod(0o755)
    saved = dict(os.environ)
    os.environ["PATH"] = str(stubs) + os.pathsep + os.environ.get("PATH", "")
    os.environ["GRIM_LOG"] = str(log)
    try:
        target = sandbox / "lock"
        written = module.capture(target)
    finally:
        os.environ.clear()
        os.environ.update(saved)
    check(written == ["eDP-1", "DP-1/x"], "a backdrop for each enabled monitor whose capture worked (%r)" % (written,))
    files = sorted(path.name for path in target.iterdir())
    check(files == ["DP-1_x.png", "eDP-1.png"], "named safely, nothing else written (%r)" % (files,))
    for path in target.iterdir():
        mode = stat.S_IMODE(path.stat().st_mode)
        check(mode == 0o600, "%s is the user's alone (%o)" % (path.name, mode))
        with Image.open(path) as image:
            check(image.mode == "RGB" and max(image.size) <= module.MAX_SIDE, "%s is a small RGB image" % path.name)
    check(stat.S_IMODE(target.stat().st_mode) == 0o700, "and so is the directory")
    events = [line.split() for line in log.read_text().splitlines()]
    starts = [int(stamp) for kind, _, stamp in events if kind == "start"]
    ends = [int(stamp) for kind, _, stamp in events if kind == "end"]
    check(len(starts) == 3 and len(ends) == 2, "three monitors captured (%d starts, %d ends)" % (len(starts), len(ends)))
    check(starts and ends and max(starts) < min(ends), "every capture started before the first one ended")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED lock_backdrop_test")
    sys.exit(1)
print("TESTS PASSED lock_backdrop_test")
