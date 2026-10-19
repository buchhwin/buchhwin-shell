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
# TEXT may come back as COMPOUND_TEXT, which is no UTF-8: not read.
check(pick(["TARGETS", "TEXT", "COMPOUND_TEXT"]) is None, "TEXT alone is not taken")
check(pick(["TARGETS", "TEXT", "STRING"]) == ("STRING", "text/plain;charset=utf-8"), "STRING beside TEXT is")
# STRING is Latin-1 (ICCCM); it is handed over as UTF-8.
check(bridge.as_utf8("STRING", "Größe".encode("latin-1")) == "Größe".encode("utf-8"), "STRING is converted from Latin-1")
check(bridge.as_utf8("UTF8_STRING", "Größe".encode("utf-8")) == "Größe".encode("utf-8"), "UTF8_STRING is left as it is")
check(bridge.as_utf8("STRING", None) is None, "nothing read stays nothing")
# A password manager's copy carries a hint; it is not handed over.
check(bridge.secret(["TARGETS", "UTF8_STRING", "x-kde-passwordManagerHint"]), "KDE's password manager hint is a secret")
check(bridge.secret(["ExcludeClipboardContentFromMonitorProcessing", "UTF8_STRING"]), "so is the Windows one")
check(not bridge.secret(["TARGETS", "UTF8_STRING", "_ISL_UNICODE"]), "Citrix's ordinary text is not")
# Hyprland's mirror: an owner window of the window manager's client.
same = bridge.same_client
check(same(0x00a00005, 0x00a00001, 0x1fffff), "two windows of one client")
check(not same(0x00c00005, 0x00a00001, 0x1fffff), "windows of two clients")
check(not same(0x00a00005, 0, 0x1fffff), "no window manager window known: no mirror")
check(not same(0x00a00005, 0x00a00001, 0), "no mask: no mirror")
check(not same(0x00a00005, 0x00a00001, 0x1ffeff), "a mask that is not low bits is not trusted")


# ---- what one owner change does, without X ----------------------------------
class Fake:
    """The two clipboards as dictionaries, and every read and write logged."""

    def __init__(self, x11, wayland, mirror=()):
        self.x11_data, self.wayland_data, self.mirrors = dict(x11), dict(wayland), set(mirror)
        self.reads, self.writes = [], []
        self.bridge = bridge.Bridge(x11=self.read_x11, wayland=self.read_wayland, write=self.write,
                                    mirror=lambda owner: owner in self.mirrors)

    def read_x11(self, target, _timeout):
        self.reads.append(("x11", target))
        if target == "TARGETS":
            return " ".join(self.x11_data).encode() if self.x11_data else None
        return self.x11_data.get(target)

    def read_wayland(self, mime):
        self.reads.append(("wayland", mime))
        return self.wayland_data.get(mime)

    def write(self, command, data):
        self.writes.append((command, data))
        if "--clear" in command:
            self.wayland_data = {}
        else:
            self.wayland_data = {command[-1]: data}
        return True


TEXT = "text/plain;charset=utf-8"
citrix = Fake({"TARGETS": b"", "UTF8_STRING": b"from citrix", "_ISL_UNICODE": b"x"}, {TEXT: b"old"}, mirror={0x00a00001})
check(citrix.bridge.change(0x00c00002) == "copy", "a Citrix copy is handed over")
check(citrix.writes == [(["wl-copy", "--type", TEXT], b"from citrix")], "as text: %r" % citrix.writes)
citrix.reads.clear()
check(citrix.bridge.change(0x00a00001) == "mirror", "Hyprland's mirror of it right after is recognised")
check(citrix.reads == [], "and nothing is read for it: %r" % citrix.reads)
check(citrix.bridge.change(0) == "clear" and citrix.writes[-1][0] == ["wl-copy", "--clear"],
      "the owner going away takes what it gave with it")

same_text = Fake({"TARGETS": b"", "UTF8_STRING": b"same"}, {TEXT: b"same"})
check(same_text.bridge.change(0x00c00002) == "skip" and not same_text.writes, "an equal offer is left alone")

latin = Fake({"TARGETS": b"", "STRING": "Größe".encode("latin-1"), "TEXT": b"?"}, {})
check(latin.bridge.change(0x00e00001) == "copy", "a STRING-only owner is handed over")
check(latin.writes and latin.writes[0][1] == "Größe".encode("utf-8"), "in UTF-8: %r" % latin.writes)

manager = Fake({"TARGETS": b"", "UTF8_STRING": b"hunter2", "x-kde-passwordManagerHint": b"secret"}, {TEXT: b"old"})
check(manager.bridge.change(0x00e00001) == "secret", "a password manager's copy is recognised")
check(not manager.writes, "and not handed over")
check(("x11", "UTF8_STRING") not in manager.reads, "not even read: %r" % manager.reads)

# Handed over earlier, then a secret copied over it and cleared: what was
# handed over is no longer that owner's to take away.
earlier = Fake({"TARGETS": b"", "UTF8_STRING": b"from citrix"}, {TEXT: b"old"})
earlier.bridge.change(0x00c00002)
earlier.x11_data = {"TARGETS": b"", "UTF8_STRING": b"hunter2", "x-kde-passwordManagerHint": b"secret"}
earlier.bridge.change(0x00e00001)
check(earlier.bridge.change(0) == "skip" and earlier.wayland_data == {TEXT: b"from citrix"},
      "a password manager clearing its copy leaves the earlier handover alone")

nothing = Fake({"TARGETS": b"", "TIMESTAMP": b"", "x-special/whatever": b"?"}, {TEXT: b"old"})
check(nothing.bridge.change(0x00c00002) == "skip" and not nothing.writes, "nothing usable, nothing handed over")
gone = Fake({}, {TEXT: b"old"})
check(gone.bridge.change(0) == "skip" and not gone.writes, "an owner going away with nothing handed over clears nothing")
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
    paint = Fake({"TARGETS": b"", "image/bmp": bmp.getvalue()}, {"image/png": b"\x89PNG old"})
    check(paint.bridge.change(0x00c00002) == "copy", "a BMP from Citrix is handed over")
    check(paint.writes and paint.writes[0][0] == ["wl-copy", "--type", "image/png"]
          and paint.writes[0][1].startswith(b"\x89PNG"), "as PNG")
check(bridge.to_png(b"not a picture") is None, "something that is no picture converts to nothing")
check(decide(b"\x89PNG new", b"\x89PNG old", None, False) == "copy", "a new picture is handed over")
check(decide(b"\x89PNG same", b"\x89PNG same", None, False) == "skip", "the mirrored picture is not handed back")
# The event layout ctypes reads: XFixesSelectionNotifyEvent fits in an XEvent.
check(bridge.ctypes.sizeof(bridge.XFixesSelectionNotifyEvent) <= bridge.ctypes.sizeof(bridge.XEvent), "event fits the union")
check(bridge.ctypes.sizeof(bridge.XEvent) == 24 * bridge.ctypes.sizeof(bridge.ctypes.c_long), "XEvent is 24 longs")

# The libraries load by soname, without find_library's ldconfig run; the
# lookup is only the fallback, and nothing found is no library.
loaded, looked_up = [], []


def fake_load(name, available=("libX11.so.6", "/opt/lib/libXfixes.so.7")):
    loaded.append(name)
    if name not in available:
        raise OSError(name)
    return "lib:" + name


def fake_find(name):
    looked_up.append(name)
    return {"Xfixes": "/opt/lib/libXfixes.so.7"}.get(name)


check(bridge.load_library("X11", fake_load, fake_find) == "lib:libX11.so.6" and not looked_up,
      "the soname loads without a lookup")
check(bridge.load_library("Xfixes", fake_load, fake_find) == "lib:/opt/lib/libXfixes.so.7" and looked_up == ["Xfixes"],
      "a soname that does not load falls back to the lookup")
check(bridge.load_library("Xfixes", lambda name: fake_load(name, ()), lambda name: None) is None,
      "nothing found is no library")
check(bridge.load_library("Xfixes", lambda name: fake_load(name, ()), fake_find) is None,
      "a looked-up path that does not load either is no library")
check(bridge.load_library("X11") is not None or bridge.ctypes.util.find_library("X11") is None,
      "libX11 loads by its soname wherever it is installed")

if failures:
    print(f"TESTS FAILED x11-clipboard-bridge ({failures})")
    sys.exit(1)
print("TESTS PASSED x11-clipboard-bridge")
