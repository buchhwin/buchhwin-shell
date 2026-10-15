#!/usr/bin/env python3
"""Unit test for scripts/wallpaper-thumbs.py, in a temporary cache only.

Never the real ~/.cache: every run names its own --cache under a temporary
directory, and the CLI runs with XDG_CACHE_HOME pointing there too.
"""

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "wallpaper-thumbs.py"
spec = importlib.util.spec_from_file_location("wallpaper_thumbs", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


WIDTH = 320

with tempfile.TemporaryDirectory(prefix="wallpaper-thumbs-test.") as scratch:
    base = pathlib.Path(scratch)
    pictures = base / "pictures"
    cache = base / "cache" / "wallpaper-thumbs"
    pictures.mkdir()

    png = pictures / "wide #1.png"
    Image.new("RGB", (1200, 750), (30, 90, 200)).save(png)
    jpeg = pictures / "tall.jpg"
    Image.new("RGB", (600, 1000), (200, 120, 40)).save(jpeg, quality=90)
    small = pictures / "small.png"
    Image.new("RGBA", (100, 60), (10, 200, 10, 128)).save(small)
    broken = pictures / "broken.png"
    broken.write_bytes(b"\x89PNG\r\n\x1a\nnot really a png")
    folder = pictures / "__MACOSX"
    folder.mkdir()
    apple = folder / "._wide.png"
    apple.write_bytes(b"\x00\x05\x16\x07" + b"\x00" * 200)
    missing = pictures / "gone.png"

    paths = [str(p) for p in (png, jpeg, small, broken, folder, apple, missing)]
    first = module.thumbnails(str(cache), WIDTH, paths)
    check(sorted(first) == sorted([str(png), str(jpeg), str(small)]),
          "only the three images get thumbnails: %s" % sorted(first))

    for source, size in ((png, (1200, 750)), (jpeg, (600, 1000))):
        thumb = first.get(str(source), "")
        check(os.path.isfile(thumb), "%s has a thumbnail file" % source.name)
        check(pathlib.Path(thumb).parent == cache, "%s's thumbnail is in the given cache" % source.name)
        if os.path.isfile(thumb):
            with Image.open(thumb) as image:
                check(image.format == "JPEG" and image.mode == "RGB", "%s: an RGB JPEG" % source.name)
                check(image.width == WIDTH, "%s: %d wide, wanted %d" % (source.name, image.width, WIDTH))
                check(abs(image.width / image.height - size[0] / size[1]) < 0.01,
                      "%s: aspect kept (%dx%d)" % (source.name, image.width, image.height))
    if os.path.isfile(first.get(str(small), "")):
        with Image.open(first[str(small)]) as image:
            check(image.size == (100, 60), "an image narrower than the width is not enlarged")
    check(not [name for name in os.listdir(cache) if name.startswith(module.TEMP_PREFIX)],
          "no temporary file left behind")

    # A second run reuses: same name, same file (a rewrite is a new inode
    # through the rename), and the touch moved its mtime forward.
    thumb = first[str(png)]
    os.utime(thumb, (time.time() - 3600, time.time() - 3600))
    before = os.stat(thumb)
    second = module.thumbnails(str(cache), WIDTH, paths)
    check(second.get(str(png)) == thumb, "a second run names the same thumbnail")
    after = os.stat(thumb)
    check(after.st_ino == before.st_ino, "and does not write it again")
    check(after.st_mtime > before.st_mtime + 1800, "but touches it, so it stays fresh")

    # A changed mtime (an image edited in place) is a new thumbnail, and so
    # is another width.
    os.utime(png, ns=(before.st_atime_ns, os.stat(png).st_mtime_ns + 5_000_000_000))
    third = module.thumbnails(str(cache), WIDTH, [str(png)])
    check(third.get(str(png)) not in (None, thumb), "a changed mtime gives a new name")
    check(os.path.isfile(third.get(str(png), "")), "and a new file")
    wider = module.thumbnails(str(cache), WIDTH * 2, [str(png)])
    check(wider.get(str(png)) not in (None, third.get(str(png))), "another width gives a new name")

    # The sweep: thumbnails nobody asked for in KEEP_DAYS go, a stale
    # temporary file goes, anything that is not ours stays.
    old = time.time() - (module.KEEP_DAYS + 1) * 86400
    stale = cache / ("0" * 40 + ".jpg")
    stale.write_bytes(b"x")
    os.utime(stale, (old, old))
    temporary = cache / (module.TEMP_PREFIX + "abc.jpg")
    temporary.write_bytes(b"x")
    os.utime(temporary, (old, old))
    foreign = cache / "notes.txt"
    foreign.write_text("keep")
    os.utime(foreign, (old, old))
    recent = cache / ("1" * 40 + ".jpg")
    recent.write_bytes(b"x")
    module.thumbnails(str(cache), WIDTH, [str(png)])
    check(not stale.exists(), "a thumbnail untouched for %d days is swept" % module.KEEP_DAYS)
    check(not temporary.exists(), "a stale temporary file is swept")
    check(foreign.exists(), "a file that is not a thumbnail is never swept")
    check(recent.exists(), "a recent thumbnail stays")

    # The command line: one JSON object, exit 0 even with a broken file, and
    # paths after "--" that look like options.
    dashed = pictures / "-dash.png"
    Image.new("RGB", (400, 250), (1, 2, 3)).save(dashed)
    env = dict(os.environ, XDG_CACHE_HOME=str(base / "xdg-cache"))
    result = subprocess.run([sys.executable, "-I", str(SCRIPT), "--cache", str(cache), "--width", str(WIDTH),
                             "--", str(png), str(broken), str(dashed)],
                            capture_output=True, text=True, timeout=60, env=env)
    check(result.returncode == 0, "the CLI exits 0 with a broken file among the paths (%d)" % result.returncode)
    check(result.stderr == "", "and prints nothing on stderr: %r" % result.stderr)
    try:
        answer = json.loads(result.stdout)
    except ValueError:
        answer = {}
    check(sorted(answer.get("thumbs", {})) == sorted([str(png), str(dashed)]),
          "the CLI maps exactly the images it managed: %r" % result.stdout)
    check(not (base / "xdg-cache").exists(), "the CLI writes nowhere but --cache")
    bad = subprocess.run([sys.executable, "-I", str(SCRIPT), "--cache", str(cache), "--width", "0"],
                         capture_output=True, text=True, timeout=60, env=env)
    check(bad.returncode == 2, "a nonsense width is a usage error")

    # A cache that cannot be made is an empty answer, not a crash.
    blocked = base / "file-not-dir"
    blocked.write_text("")
    check(module.thumbnails(str(blocked / "cache"), WIDTH, [str(png)]) == {}, "an unusable cache gives no thumbnails")

check(module.scaled_size((6000, 3750), 520) == (520, 325), "6000x3750 at 520 is 520x325")
check(module.scaled_size((1000, 2000), 520) == (520, 1040), "a portrait image is bounded by the width, as Qt does")

for failure in failures:
    print("FAIL wallpaper_thumbs_test:", failure)
print("TESTS %s wallpaper_thumbs_test" % ("FAILED" if failures else "PASSED"))
sys.exit(1 if failures else 0)
