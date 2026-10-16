#!/usr/bin/env python3
"""scripts/x11-clipboard-bridge.py: what one clipboard change leads to."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bridge", ROOT / "scripts" / "x11-clipboard-bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

failures = 0


def check(condition, message):
    global failures
    if not condition:
        failures += 1
        print("FAIL:", message)


decide, digest = bridge.decide, bridge.digest
# Citrix put new text on the X11 clipboard; Wayland still has the old one.
check(decide(b"from citrix", b"old", None, False) == "copy", "new X11 text is handed over")
check(decide(b"from citrix", None, None, False) == "copy", "also when Wayland offers no text (a picture)")
# Hyprland's own mirror (Wayland to X11) shows up as a change with the same text.
check(decide(b"same", b"same", None, False) == "skip", "the mirror of the Wayland clipboard is not handed back")
check(decide(None, b"old", None, False) == "skip", "an X11 owner without text (a picture) is left alone")
check(decide(b"", b"old", None, False) == "skip", "empty text is left alone")
# An owner that went away: clear only what this put there.
check(decide(None, b"secret", digest(b"secret"), True) == "clear", "a vanished owner takes the text it gave with it")
check(decide(None, b"copied here since", digest(b"secret"), True) == "skip", "but not what was copied since")
check(decide(None, b"anything", None, True) == "skip", "nothing handed over, nothing cleared")
check(digest(None) is None and digest(b"a") == digest(b"a") != digest(b"b"), "digest")
# What is read from an owner: text first, then a picture; BMP/TIFF become PNG.
pick = bridge.pick
check(pick(["TARGETS", "UTF8_STRING", "image/png"]) == ("UTF8_STRING", "text/plain;charset=utf-8"), "text wins over a picture")
check(pick(["TARGETS", "STRING"]) == ("STRING", "text/plain;charset=utf-8"), "plain STRING is text too")
check(pick(["TARGETS", "image/png", "image/bmp"]) == ("image/png", "image/png"), "a PNG goes as it is")
check(pick(["TARGETS", "image/bmp"]) == ("image/bmp", "image/png"), "a BMP is handed over as PNG")
check(pick(["TARGETS", "image/jpeg"]) == ("image/jpeg", "image/jpeg"), "a JPEG goes as it is")
check(pick(["TARGETS", "TIMESTAMP", "x-special/whatever"]) is None, "nothing usable, nothing read")
check(pick([]) is None, "no targets")
try:
    import io
    from PIL import Image
except ImportError:
    print("note: Pillow missing, BMP conversion not checked")
else:
    bmp = io.BytesIO()
    Image.new("RGB", (3, 2), (200, 30, 30)).save(bmp, format="BMP")
    png = bridge.to_png(bmp.getvalue())
    check(png is not None and png.startswith(b"\x89PNG"), "a BMP comes out as PNG")
    with Image.open(io.BytesIO(png)) as image:
        check(image.size == (3, 2) and image.getpixel((0, 0)) == (200, 30, 30), "with its pixels")
check(bridge.to_png(b"not a picture") is None, "something that is no picture converts to nothing")
check(decide(b"\x89PNG new", b"\x89PNG old", None, False) == "copy", "a new picture is handed over")
check(decide(b"\x89PNG same", b"\x89PNG same", None, False) == "skip", "the mirrored picture is not handed back")
# The event layout ctypes reads: XFixesSelectionNotifyEvent fits in an XEvent.
check(bridge.ctypes.sizeof(bridge.XFixesSelectionNotifyEvent) <= bridge.ctypes.sizeof(bridge.XEvent), "event fits the union")
check(bridge.ctypes.sizeof(bridge.XEvent) == 24 * bridge.ctypes.sizeof(bridge.ctypes.c_long), "XEvent is 24 longs")

if failures:
    print(f"TESTS FAILED x11-clipboard-bridge ({failures})")
    sys.exit(1)
print("TESTS PASSED x11-clipboard-bridge")
