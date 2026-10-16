#!/usr/bin/env python3
"""Read or set the logo image of the session's Fastfetch configuration.

  fastfetch-image.py get          print {"kind": "builtin"|"image"|"text", "source": …, "width": …}
  fastfetch-image.py set IMAGE    use IMAGE (PNG, JPEG, WebP or BMP) as logo
  fastfetch-image.py builtin      go back to the distribution's own ASCII logo
  fastfetch-image.py size COLS    logo width in terminal columns (8-60)

Only the width is written: with kitty-direct a fixed height stretches the image
to that many rows (preserveAspectRatio only applies to iTerm), so kitty keeps
the aspect ratio when the height is left out.

A text logo of one's own (fastfetch's "file" type, like the Saturn the
buchhwin profile ships) is a third kind: it is neither the distribution's logo
nor an image, `size` leaves it alone, and only `builtin` or `set` replace it.

The configuration is ${XDG_CONFIG_HOME:-~/.config}/buchhwin-shell/fastfetch.jsonc
(JSON with comments). It is written atomically; comments are not preserved.
"""

import json
import os
import pathlib
import sys
import tempfile

SIGNATURES = (b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"BM")
# fastfetch's logo types by what they draw. "auto" (or no type) decides by the
# source, and so does `logo_kind` below.
IMAGE_TYPES = ("kitty", "kitty-direct", "kitty-icat", "sixel", "iterm", "chafa", "raw")
TEXT_TYPES = ("file", "file-raw", "data", "data-raw")
NAMED_TYPES = ("builtin", "small", "none")
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif")


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return pathlib.Path(base) / "buchhwin-shell" / "fastfetch.jsonc"


def strip_jsonc(text):
    """Remove // and /* */ comments and trailing commas outside strings."""
    out = []
    pending_comma = False
    i = 0
    while i < len(text):
        char = text[i]
        if char == '"':
            end = i + 1
            while end < len(text) and text[end] != '"':
                end += 2 if text[end] == "\\" else 1
            if pending_comma:
                out.append(",")
                pending_comma = False
            out.append(text[i:end + 1])
            i = end + 1
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        if char == ",":
            if pending_comma:
                out.append(",")
            pending_comma = True
        elif char.isspace():
            out.append(char)
        else:
            if pending_comma and char not in "}]":
                out.append(",")
            pending_comma = False
            out.append(char)
        i += 1
    if pending_comma:
        out.append(",")
    return "".join(out)


def load(path):
    if not path.exists():
        return {}
    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    if not isinstance(data, dict):
        raise ValueError("configuration is not an object")
    return data


def is_image(path):
    try:
        with open(path, "rb") as handle:
            head = handle.read(12)
    except OSError:
        return False
    if head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        return True
    return any(head.startswith(signature) for signature in SIGNATURES)


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=".fastfetch-", suffix=".jsonc")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


def logo_kind(logo):
    """"builtin", "image" or "text": what the logo object draws.

    A text logo used to count as an image because it has a source, and the
    settings page then tried to decode saturn.txt as a picture and called it
    "Image" - with "System logo" one click away from dropping it unasked.
    """
    source = logo.get("source", "")
    source = source if isinstance(source, str) else ""
    kind = logo.get("type")
    kind = kind.lower() if isinstance(kind, str) and kind else "auto"
    if not source or kind in NAMED_TYPES:
        return "builtin"
    if kind in TEXT_TYPES:
        return "text"
    if kind in IMAGE_TYPES:
        return "image"
    # "auto": a file is drawn as what it is, a path that is gone by its name
    # (a chosen image that was deleted is still the image setting), and a bare
    # word is the name of one of fastfetch's own logos.
    file = os.path.expanduser(source)
    if os.path.isfile(file):
        return "image" if is_image(file) else "text"
    if source.lower().endswith(IMAGE_SUFFIXES):
        return "image"
    return "text" if "/" in source else "builtin"


def get(path):
    logo = load(path).get("logo")
    logo = logo if isinstance(logo, dict) else {}
    source = logo.get("source", "")
    source = source if isinstance(source, str) else ""
    width = logo.get("width")
    # Which state the configuration is in. Without this the caller could only
    # guess from an empty source, and "no source", "an image that was deleted"
    # and "a text logo" are not the same thing to a settings page.
    kind = logo_kind(logo)
    return {"kind": kind,
            "source": source if kind != "builtin" else "",
            "width": width if isinstance(width, int) else 0}


def fit_logo(logo, columns=None):
    """Drop the stretching height; returns True when something changed."""
    changed = "height" in logo
    logo.pop("height", None)
    logo.pop("preserveAspectRatio", None)
    if columns is not None and logo.get("width") != columns:
        logo["width"] = columns
        changed = True
    return changed


def set_size(path, columns):
    columns = int(columns)
    if not 8 <= columns <= 60:
        raise ValueError("width must be between 8 and 60 columns")
    data = load(path)
    logo = data.get("logo")
    # Columns are an image's width; a text logo is as wide as its lines.
    if not isinstance(logo, dict) or logo_kind(logo) != "image":
        return {"changed": False}
    changed = fit_logo(logo, columns)
    if changed:
        write_atomic(path, data)
    return {"changed": changed}


def set_image(path, image):
    image = os.path.abspath(os.path.expanduser(image))
    if not os.path.isfile(image) or not is_image(image):
        raise ValueError("not a PNG, JPEG, WebP or BMP image")
    data = load(path)
    logo = data.get("logo") if isinstance(data.get("logo"), dict) else {}
    logo["type"] = "kitty-direct"
    logo["source"] = image
    fit_logo(logo, logo.get("width") if isinstance(logo.get("width"), int) else 30)
    data["logo"] = logo
    write_atomic(path, data)
    return {"source": image}


def set_builtin(path):
    """Back to the logo Fastfetch picks for the distribution.

    It detects Fedora on its own when nothing names a source, so the way back
    is to take the image keys out rather than to name a logo. The padding stays:
    it is layout, not logo, and losing it would move the whole greeting.
    """
    data = load(path)
    logo = data.get("logo") if isinstance(data.get("logo"), dict) else {}
    changed = any(key in logo for key in ("source", "type", "width"))
    for key in ("source", "type", "width", "height", "preserveAspectRatio"):
        logo.pop(key, None)
    data["logo"] = logo
    if changed:
        write_atomic(path, data)
    return {"kind": "builtin", "changed": changed}


def main(argv):
    try:
        if argv[:1] == ["get"] and len(argv) == 1:
            result = get(config_path())
        elif argv[:1] == ["set"] and len(argv) == 2:
            result = set_image(config_path(), argv[1])
        elif argv[:1] == ["builtin"] and len(argv) == 1:
            result = set_builtin(config_path())
        elif argv[:1] == ["size"] and len(argv) == 2:
            result = set_size(config_path(), argv[1])
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
