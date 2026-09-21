#!/usr/bin/env python3
"""Unit test for scripts/fastfetch-image.py with temporary files."""

import importlib.util
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("fastfetch_image", ROOT / "scripts" / "fastfetch-image.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


jsonc = """{
  // comment with "quotes", and a comma,
  "$schema": "https://example.invalid/a//b",
  "logo": { "type": "kitty-direct", "source": "/old/x.png", "width": 30, /* inline */ },
  "display": { "separator": "a,}\\\\" },
  "modules": ["title", "os",],
}
"""
parsed = json.loads(module.strip_jsonc(jsonc))
check(parsed["$schema"] == "https://example.invalid/a//b", "// inside strings kept")
check(parsed["display"]["separator"] == "a,}\\", "commas, braces and escaped backslashes inside strings kept")
check(parsed["modules"] == ["title", "os"], "trailing commas removed")

with tempfile.TemporaryDirectory() as directory:
    base = pathlib.Path(directory)
    config = base / "fastfetch.jsonc"
    config.write_text(jsonc, encoding="utf-8")
    png = base / "logo.png"
    png.write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(16))
    webp = base / "logo.webp"
    webp.write_bytes(b"RIFF\x00\x00\x00\x00WEBPVP8 ")
    text = base / "notes.png"
    text.write_text("not an image", encoding="utf-8")

    check(module.get(config) == {"kind": "image", "source": "/old/x.png", "width": 30},
          "get reads the current logo")
    check(module.set_image(config, str(png)) == {"source": str(png)}, "set accepts PNG")
    saved = json.loads(config.read_text(encoding="utf-8"))
    check(saved["logo"]["source"] == str(png) and saved["logo"]["width"] == 30, "logo replaced, other logo keys kept")
    check("height" not in saved["logo"], "set drops the stretching height")
    stretched = base / "stretched.jsonc"
    stretched.write_text('{"logo": {"source": "/x.png", "width": 30, "height": 15, "preserveAspectRatio": true}}', encoding="utf-8")
    check(module.set_size(stretched, "40") == {"changed": True}, "size changes width and height")
    fitted = json.loads(stretched.read_text(encoding="utf-8"))["logo"]
    check(fitted == {"source": "/x.png", "width": 40}, "only the width is kept")
    before = stretched.stat().st_mtime_ns
    check(module.set_size(stretched, "40") == {"changed": False} and stretched.stat().st_mtime_ns == before, "unchanged size does not rewrite")
    try:
        module.set_size(stretched, "200")
        check(False, "absurd widths rejected")
    except ValueError:
        pass
    check(saved["modules"] == ["title", "os"], "other sections kept")
    check(module.is_image(webp), "WebP detected")
    try:
        module.set_image(config, str(text))
        check(False, "non-images rejected")
    except ValueError:
        pass
    check(json.loads(config.read_text(encoding="utf-8"))["logo"]["source"] == str(png), "failed set leaves the file unchanged")
    missing = base / "new" / "fastfetch.jsonc"
    check(module.get(missing) == {"kind": "builtin", "source": "", "width": 0},
          "missing config has no logo")
    module.set_image(missing, str(png))
    check(json.loads(missing.read_text(encoding="utf-8"))["logo"]["type"] == "kitty-direct", "set creates a config")
    check(not [name for name in missing.parent.iterdir() if name.name.startswith(".fastfetch-")], "no temporary files left")

    # The way back. Before this there was none: once an image was chosen, only
    # a text editor could undo it.
    back = base / "back.jsonc"
    back.write_text('{"logo": {"type": "kitty-direct", "source": "/x.png", "width": 30,'
                    ' "padding": {"left": 1}}, "display": {"separator": "  "}}', encoding="utf-8")
    check(module.set_builtin(back) == {"kind": "builtin", "changed": True}, "builtin reports the change")
    saved = json.loads(back.read_text(encoding="utf-8"))
    check("source" not in saved["logo"] and "type" not in saved["logo"], "builtin drops the image keys")
    check(saved["logo"]["padding"] == {"left": 1}, "builtin keeps the padding, which is layout")
    check(saved["display"]["separator"] == "  ", "builtin leaves the rest of the file alone")
    check(module.get(back)["kind"] == "builtin", "get agrees afterwards")
    check(module.set_builtin(back)["changed"] is False, "a second builtin changes nothing")
    round_trip = module.set_image(back, str(png))
    check(round_trip == {"source": str(png)}, "an image can be chosen again afterwards")
    check(module.get(back)["kind"] == "image", "and get says so")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED fastfetch_image_test")
    sys.exit(1)
print("TESTS PASSED fastfetch_image_test")
