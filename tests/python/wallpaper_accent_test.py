#!/usr/bin/env python3
"""Unit test for scripts/wallpaper-accent.py with synthetic images."""

import colorsys
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import re
import sys
import tempfile

from PIL import Image

ACCENT = re.compile(r"^#[0-9a-f]{6}$")

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


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        status = module.main(list(argv))
    lines = out.getvalue().strip().splitlines()
    return status, json.loads(lines[-1]) if lines else {}


with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    picture = base / "orange.png"
    orange.save(picture)
    cache = base / "cache" / "wallpaper-accent.json"

    # ---- an image that is not there is no answer, not the default blue ---------
    status, answer = run(str(base / "gone.png"))
    check(status == 1 and answer.get("accent") == "" and answer.get("error"),
          "a missing image answers with no accent and exit 1: %r" % answer)
    (base / "broken.png").write_bytes(b"not a picture")
    status, answer = run("--cache", str(cache), str(base / "broken.png"))
    check(status == 1 and answer.get("accent") == "", "and so does one that cannot be read: %r" % answer)
    check(not cache.exists(), "neither is kept")
    Image.new("RGB", (100, 100), (128, 128, 128)).save(base / "grey.png")
    status, answer = run(str(base / "grey.png"))
    check(status == 0 and answer.get("accent") == module.DEFAULT, "a grey image is an answer: the default blue")

    # ---- the same image again is answered from the cache -------------------------
    status, answer = run("--cache", str(cache), str(picture))
    check(status == 0 and answer.get("accent") == result, "with a cache the accent is the same: %r" % answer)
    kept = json.loads(cache.read_text(encoding="utf-8"))
    info = picture.stat()
    check(kept == {"path": str(picture), "mtime": info.st_mtime_ns, "size": info.st_size, "accent": result},
          "kept with the image's path, mtime and size: %r" % kept)
    decode = module.accent_for
    module.accent_for = lambda image: check(False, "the same image again is not decoded") or "#000000"
    try:
        status, answer = run("--cache", str(cache), str(picture))
    finally:
        module.accent_for = decode
    check(status == 0 and answer.get("accent") == result, "the same image again: the kept accent: %r" % answer)

    # A new mtime is a new image, even under the same name.
    Image.new("RGB", (200, 120), (20, 90, 200)).save(picture)
    os.utime(picture, ns=(info.st_atime_ns, info.st_mtime_ns + 5_000_000_000))
    status, answer = run("--cache", str(cache), str(picture))
    check(status == 0 and 200 < hue_of(answer.get("accent", "#000000")) < 230,
          "an image changed in place is decoded again: %r" % answer)
    check(json.loads(cache.read_text(encoding="utf-8"))["mtime"] == info.st_mtime_ns + 5_000_000_000,
          "and the cache follows it")
    cache.write_text("{broken", encoding="utf-8")
    status, answer = run("--cache", str(cache), str(picture))
    check(status == 0 and ACCENT.match(answer.get("accent", "")), "a broken cache is no cache: %r" % answer)
    (base / "file").write_text("", encoding="utf-8")
    status, answer = run("--cache", str(base / "file" / "x.json"), str(picture))
    check(status == 0 and ACCENT.match(answer.get("accent", "")), "and one that cannot be written too: %r" % answer)

for failure in failures:
    print("FAIL wallpaper_accent_test:", failure)
print("TESTS %s wallpaper_accent_test" % ("FAILED" if failures else "PASSED"))
sys.exit(1 if failures else 0)
