#!/usr/bin/env python3
"""Small JPEG thumbnails of the wallpapers, for the picker and Settings.

  wallpaper-thumbs.py --cache DIR --width W [--] PATH...

Prints {"thumbs": {PATH: THUMBNAIL}, "sizes": {PATH: [WIDTH, HEIGHT]}} for
every PATH that has a thumbnail. A thumbnail is DIR/<sha1 of the path, mtime,
size and W>.jpg, W pixels wide (never wider than the image), and it is only
made when it is missing, so a run over a folder that has not changed only
stats and hashes. Thumbnails a run finds are touched; those nobody asked for
in KEEP_DAYS are removed at the end. A file that is not an image, a folder or
a broken image is left out quietly, and the exit status is 0 with whatever
could be done.

The sizes are each picture's own, as stored (no EXIF turn, like Qt's Image):
the desktop decodes only the part of a wallpaper its screen shows, and for
that it needs the picture's size before it decodes. They are read with the
thumbnail and kept in DIR/sizes.json by thumbnail name, so a run over a
folder that has not changed still needs no Pillow.

Why: Qt cannot decode a PNG at a reduced size. A 6000x3750 wallpaper of ~4 MB
cost 140-340 ms per picker tile (measured with PIL), and the picker took about
a second until the last tile was there.
"""

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import time
import warnings

QUALITY = 85
KEEP_DAYS = 60
# Left behind only by a run killed while it wrote; never older than a run.
TEMP_PREFIX = ".thumb-"
TEMP_KEEP = 86400
THUMB_NAME = re.compile(r"[0-9a-f]{40}\.jpg")
# {thumbnail name: [width, height]} of the pictures the thumbnails are of.
SIZES_NAME = "sizes.json"


def thumb_name(path, info, width):
    """The cache name: a new mtime, size or width is a new thumbnail."""
    key = "\0".join((os.path.abspath(path), str(info.st_mtime_ns), str(info.st_size), str(width)))
    return hashlib.sha1(key.encode("utf-8", "surrogateescape"), usedforsecurity=False).hexdigest() + ".jpg"


def scaled_size(size, width):
    """`width` wide with the aspect kept, never larger than the image.

    Bounded by the width alone and not by a square: the tiles ask Qt for
    `sourceSize.width` with PreserveAspectCrop, which scales any image to that
    width, a portrait one included - so this is what a tile drew before.
    """
    original_width, original_height = size
    if original_width <= width:
        return original_width, original_height
    return width, max(1, round(original_height * width / original_width))


def write_atomic(picture, target):
    handle, temporary = tempfile.mkstemp(dir=os.path.dirname(target), prefix=TEMP_PREFIX, suffix=".jpg")
    try:
        with os.fdopen(handle, "wb") as stream:
            picture.save(stream, "JPEG", quality=QUALITY, optimize=True)
        os.replace(temporary, target)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def read_sizes(cache):
    """The sizes the last run kept, {} for none or a broken file."""
    try:
        with open(os.path.join(cache, SIZES_NAME), encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    kept = {}
    for name, size in data.items():
        if (THUMB_NAME.fullmatch(name) and isinstance(size, list) and len(size) == 2
                and all(type(value) is int and value > 0 for value in size)):
            kept[name] = size
    return kept


def write_sizes(cache, sizes):
    """Replaces DIR/sizes.json at once; a failure only costs the next run a header read."""
    try:
        handle, temporary = tempfile.mkstemp(dir=cache, prefix=TEMP_PREFIX, suffix=".json")
    except OSError:
        return
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(sizes, stream, sort_keys=True)
        os.replace(temporary, os.path.join(cache, SIZES_NAME))
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass


def image_size(path):
    """A picture's own size from its header, or None; nothing is decoded."""
    try:
        from PIL import Image

        with Image.open(path) as image:
            return [image.width, image.height]
    except Exception:  # noqa: BLE001 - not an image, broken, or no Pillow
        return None


def make(source, target, width):
    """Writes the thumbnail and returns the picture's own [width, height]."""
    # Imported here: a run with nothing to make (every start after the first)
    # never needs Pillow.
    from PIL import Image

    with Image.open(source) as image:
        # Before draft(), which shrinks a JPEG's size to the drafted one.
        original = [image.width, image.height]
        size = scaled_size(image.size, width)
        # A JPEG decodes straight from its DCT at 1/2, 1/4 or 1/8, kept at
        # least twice the target (Pillow's own reducing gap) so the resample
        # still has detail; PNG has no reduced decode and is decoded whole,
        # once, here. Not thumbnail((W, big)): Pillow 12 drafts at the box it
        # is given, and a box bounded by the width alone drafted nothing.
        drafted = image.draft("RGB", (size[0] * 2, size[1] * 2))
        picture = image if image.mode == "RGB" else image.convert("RGB")
        if picture.size != size:
            picture = picture.resize(size, Image.Resampling.LANCZOS,
                                     box=drafted[1] if drafted else None, reducing_gap=2.0)
        write_atomic(picture, target)
    return original


def sweep(cache, now):
    """Remove thumbnails untouched for KEEP_DAYS and stale temporary files."""
    removed = 0
    try:
        entries = list(os.scandir(cache))
    except OSError:
        return removed
    for entry in entries:
        if THUMB_NAME.fullmatch(entry.name):
            limit = now - KEEP_DAYS * 86400
        elif entry.name.startswith(TEMP_PREFIX):
            limit = now - TEMP_KEEP
        else:
            continue
        try:
            if entry.is_file(follow_symlinks=False) and entry.stat(follow_symlinks=False).st_mtime < limit:
                os.unlink(entry.path)
                removed += 1
        except OSError:
            pass
    return removed


def thumbnails(cache, width, paths, now=None, sizes=None):
    """{path: thumbnail} for every path that has or got one.

    With a dict as `sizes`, it gets {path: [width, height]} for each of them
    whose size is known.
    """
    found = {}
    try:
        os.makedirs(cache, exist_ok=True)
    except OSError:
        return found
    known = read_sizes(cache) if sizes is not None else {}
    seen = {}
    for path in paths:
        try:
            info = os.stat(path)
        except OSError:
            continue
        # A folder among the images (__MACOSX) or anything else that is not a
        # plain file.
        if not stat.S_ISREG(info.st_mode):
            continue
        target = os.path.join(cache, thumb_name(path, info, width))
        made = None
        try:
            # Touched, so a wallpaper still in use is never swept.
            os.utime(target)
        except FileNotFoundError:
            try:
                made = make(path, target, width)
            except Exception:  # noqa: BLE001 - not an image, broken, or no Pillow
                continue
        except OSError:
            continue
        found[path] = target
        if sizes is not None:
            name = os.path.basename(target)
            size = made or known.get(name) or image_size(path)
            if size:
                sizes[path] = seen[name] = size
    sweep(cache, time.time() if now is None else now)
    if sizes is not None:
        # The sizes of thumbnails that are still there, this run's first.
        kept = {name: size for name, size in {**known, **seen}.items()
                if os.path.isfile(os.path.join(cache, name))}
        if kept != known:
            write_sizes(cache, kept)
    return found


def main(argv):
    parser = argparse.ArgumentParser(description="Small JPEG thumbnails of wallpapers.")
    parser.add_argument("--cache", required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args(argv)
    if not 16 <= args.width <= 4096:
        parser.error("--width must be between 16 and 4096")
    # Pillow warns about files it still reads (palette transparency, very
    # large images); every line on stderr lands in the shell log as a warning
    # (ErrorLog), and the smoke test fails on those.
    warnings.simplefilter("ignore")
    sizes = {}
    found = thumbnails(args.cache, args.width, args.paths, sizes=sizes)
    print(json.dumps({"thumbs": found, "sizes": sizes}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
