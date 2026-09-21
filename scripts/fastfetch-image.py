#!/usr/bin/env python3
"""Read or set the logo image of the session's Fastfetch configuration.

  fastfetch-image.py get          print {"source": "<path or empty>", "width": columns}
  fastfetch-image.py set IMAGE    use IMAGE (PNG, JPEG, WebP or BMP) as logo
  fastfetch-image.py size COLS    logo width in terminal columns (8-60)

Only the width is written: with kitty-direct a fixed height stretches the image
to that many rows (preserveAspectRatio only applies to iTerm), so Kitty keeps
the aspect ratio when the height is left out.

The configuration is ${XDG_CONFIG_HOME:-~/.config}/buchhwin-shell/fastfetch.jsonc
(JSON with comments). It is written atomically; comments are not preserved.
"""

import json
import os
import pathlib
import sys
import tempfile

SIGNATURES = (b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"BM")


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


def get(path):
    logo = load(path).get("logo")
    logo = logo if isinstance(logo, dict) else {}
    source = logo.get("source", "")
    width = logo.get("width")
    return {"source": source if isinstance(source, str) else "",
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
    if not isinstance(logo, dict):
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


def main(argv):
    try:
        if argv[:1] == ["get"] and len(argv) == 1:
            result = get(config_path())
        elif argv[:1] == ["set"] and len(argv) == 2:
            result = set_image(config_path(), argv[1])
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
