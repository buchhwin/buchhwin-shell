#!/usr/bin/env python3
"""Hand what an X11 program copies - text or a picture - on to the Wayland clipboard.

Hyprland mirrors the clipboard between Wayland and XWayland, but an X11
program that takes the clipboard while none of its windows has the focus is
not mirrored: Citrix's client puts what was copied in the remote session on
the X11 clipboard only as its window loses the focus, and by then a Wayland
window has it. Text copied in Citrix could not be pasted here (16.10.; the
X11 clipboard held it, the Wayland one still the previous picture).

This watches the X11 CLIPBOARD through XFixes and, when its owner changes,
reads what it offers with xclip and hands it to wl-copy - only when it differs
from what the Wayland clipboard already offers. Hyprland's own mirror (Wayland
to X11, after every Wayland copy and again when an X11 window gets the focus)
is recognised by its owner and left alone without reading anything. An X11
owner that goes away with something this put there (a program clearing its
copy) clears the Wayland copy too.

Text wins when both are offered (a spreadsheet's cells come as text and as a
picture of them); a picture alone goes over as PNG or JPEG as offered, and a
BMP or TIFF - what Windows programs hand out - is turned into PNG first, which
Wayland programs take (with Pillow; without it, as it came). What an owner
marks as a secret (a password manager's copy) is not handed over at all.

Quiet: without xclip, wl-copy or an X display it waits and prints nothing,
and a display that goes away ends it without a word (the shell's log is
checked for warnings).

  x11-clipboard-bridge.py --display :1
"""

import argparse
import ctypes
import ctypes.util
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import time

TIMEOUT = 2
# A picture can be several megabytes, and the owner sends it in pieces.
IMAGE_TIMEOUT = 8
SETTLE = 0.12
# No TEXT: an owner may answer it with COMPOUND_TEXT, which is neither UTF-8
# nor Latin-1. STRING is Latin-1 (ICCCM) and is converted (as_utf8).
TEXT_TARGETS = ("UTF8_STRING", "text/plain;charset=utf-8", "STRING")
IMAGE_TARGETS = ("image/png", "image/jpeg", "image/bmp", "image/x-bmp", "image/tiff")
TO_PNG = ("image/bmp", "image/x-bmp", "image/tiff")
TEXT_MIME = "text/plain;charset=utf-8"
# What a password manager offers beside the secret: KDE's hint (KeePassXC and
# other Qt programs on X11 set it to "secret"), and the Windows format KeePass
# and others register, in case a remote session hands that on. wl-paste --watch
# turns the hint into "sensitive", which cliphist does not store; wl-copy offers
# one type and cannot carry it, so a handed-over password would land in the
# clipboard history and outlive the manager's own clear.
SECRET_TARGETS = ("x-kde-passwordManagerHint", "ExcludeClipboardContentFromMonitorProcessing")


def digest(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def secret(targets):
    """Whether an owner marks what it offers as a secret."""
    return any(target in SECRET_TARGETS for target in targets)


def pick(targets):
    """(X11 target to read, MIME type to hand over) for what an owner offers,
    text first; None when it offers neither."""
    offered = set(targets)
    for target in TEXT_TARGETS:
        if target in offered:
            return target, TEXT_MIME
    for target in IMAGE_TARGETS:
        if target in offered:
            return target, "image/png" if target in TO_PNG else target
    return None


def as_utf8(target, data):
    """X11 text as the UTF-8 it is handed over as: an owner that offers only
    STRING sends Latin-1, and 'Größe' from it used to paste as 'Gr��e'."""
    if data is None or target != "STRING":
        return data
    return data.decode("latin-1").encode("utf-8")


def to_png(data):
    """A BMP or TIFF as PNG; None when Pillow is missing or cannot read it."""
    try:
        import io
        from PIL import Image
        with Image.open(io.BytesIO(data)) as image:
            out = io.BytesIO()
            image.save(out, format="PNG")
            return out.getvalue()
    except Exception:
        return None


def decide(x11_data, wayland_data, bridged, owner_gone):
    """What to do with one change: "copy", "clear" or "skip".

    x11_data / wayland_data are the bytes each side offers in the type that
    is handed over (None when it offers none), bridged the digest of the
    last thing this handed over in that type.
    """
    if owner_gone:
        return "clear" if bridged is not None and digest(wayland_data) == bridged else "skip"
    if not x11_data:
        return "skip"
    if x11_data == wayland_data:
        return "skip"
    return "copy"


def same_client(window, other, mask):
    """Whether two X11 resources were made by the same client. The server
    gives each client its own id base and leaves it the bits under the mask,
    so the bits above it name the client."""
    if not window or not other or not mask or mask & (mask + 1):
        return False
    return (window & ~mask) == (other & ~mask)


class Bridge:
    """One owner change after another. Reading and writing are handed in, so
    what a change leads to can be tested without an X server:
    x11(target, timeout) and wayland(mime) return bytes or None,
    write(command, data) returns whether it worked, and mirror(owner) says
    whether the owner is Hyprland's own copy of the Wayland clipboard."""

    def __init__(self, x11, wayland, write, mirror=lambda _owner: False):
        self.x11 = x11
        self.wayland = wayland
        self.write = write
        self.mirror = mirror
        # (MIME type, digest) of the last thing handed over.
        self.bridged = None

    def change(self, owner):
        """What one change did: "copy", "clear", "skip", "mirror" or "secret"."""
        if owner == 0:
            if self.bridged and decide(None, self.wayland(self.bridged[0]), self.bridged[1], True) == "clear":
                self.write(["wl-copy", "--clear"], None)
                self.bridged = None
                return "clear"
            return "skip"
        # After every Wayland copy - this one's own wl-copy included - and at
        # the next X11 focus. Its data is the Wayland clipboard's, so reading
        # it only to find it equal pulled a picture through the compositor
        # twice, and the source program had to serve it once more.
        if self.mirror(owner):
            return "mirror"
        targets = self.x11("TARGETS", TIMEOUT)
        offered = targets.decode("utf-8", "replace").split() if targets else []
        if secret(offered):
            # Nothing of it is read. Whatever was handed over before is no
            # longer this owner's, so its going away clears nothing.
            self.bridged = None
            return "secret"
        choice = pick(offered)
        if not choice:
            return "skip"
        target, mime = choice
        data = as_utf8(target, self.x11(target, TIMEOUT if mime == TEXT_MIME else IMAGE_TIMEOUT))
        if data and target in TO_PNG:
            converted = to_png(data)
            if converted is None:
                mime = target
            else:
                data = converted
        if decide(data, self.wayland(mime), None, False) != "copy":
            return "skip"
        if not self.write(["wl-copy", "--type", mime], data):
            return "skip"
        self.bridged = (mime, digest(data))
        return "copy"


def run(command, env=None, timeout=TIMEOUT):
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout if result.returncode == 0 else None


def hand_over(command, data=None):
    """wl-copy stays behind to serve the clipboard: nothing of ours may be
    open in it, or waiting for its output would wait for that."""
    try:
        result = subprocess.run(command, input=data, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=IMAGE_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


class XFixesSelectionNotifyEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("subtype", ctypes.c_int),
                ("owner", ctypes.c_ulong), ("selection", ctypes.c_ulong), ("timestamp", ctypes.c_ulong),
                ("selection_timestamp", ctypes.c_ulong)]


class XEvent(ctypes.Union):
    _fields_ = [("type", ctypes.c_int), ("selection", XFixesSelectionNotifyEvent), ("pad", ctypes.c_long * 24)]


class DisplayHead(ctypes.Structure):
    """The start of Xlib's Display (Xlib.h names it _XPrivDisplay): private3
    and private4 are the connection's resource_base and resource_mask
    (Xlibint.h), which Xlib has no call for."""
    _fields_ = [("ext_data", ctypes.c_void_p), ("private1", ctypes.c_void_p), ("fd", ctypes.c_int),
                ("private2", ctypes.c_int), ("proto_major_version", ctypes.c_int),
                ("proto_minor_version", ctypes.c_int), ("vendor", ctypes.c_void_p),
                ("private3", ctypes.c_ulong), ("private4", ctypes.c_ulong)]


def wayland(mime):
    """What the Wayland clipboard offers in this type, as it is (no newline
    taken off a picture)."""
    command = ["wl-paste", "--type", mime]
    if mime == TEXT_MIME:
        command[1:1] = ["--no-newline"]
    return run(command, timeout=IMAGE_TIMEOUT if mime != TEXT_MIME else TIMEOUT)


def wait_forever():
    signal.pause()
    return 0


# The libraries by their sonames first: ctypes.util.find_library runs
# ldconfig (and gcc where that finds nothing) to look a name up, at every
# start of the shell, for two libraries whose sonames have not changed in
# decades. The lookup stays as the fallback for a system that names them
# otherwise.
SONAMES = {"X11": "libX11.so.6", "Xfixes": "libXfixes.so.3"}


def load_library(name, load=ctypes.CDLL, find=ctypes.util.find_library):
    """The library for `name` ("X11", "Xfixes"), or None when there is none."""
    try:
        return load(SONAMES[name])
    except OSError:
        pass
    path = find(name)
    if not path:
        return None
    try:
        return load(path)
    except OSError:
        return None


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ""))
    args = parser.parse_args(argv)
    if not args.display or not shutil.which("xclip") or not shutil.which("wl-copy") or not shutil.which("wl-paste"):
        return wait_forever()
    libx11 = load_library("X11")
    libxfixes = load_library("Xfixes")
    if libx11 is None or libxfixes is None:
        return wait_forever()
    libx11.XOpenDisplay.restype = ctypes.c_void_p
    libx11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    libx11.XDefaultRootWindow.restype = ctypes.c_ulong
    libx11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    libx11.XInternAtom.restype = ctypes.c_ulong
    libx11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    libx11.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.POINTER(XEvent)]
    libx11.XPending.argtypes = [ctypes.c_void_p]
    libx11.XGetWindowProperty.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_long, ctypes.c_long, ctypes.c_int,
        ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_void_p)]
    libx11.XFree.argtypes = [ctypes.c_void_p]
    libxfixes.XFixesQueryExtension.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
    libxfixes.XFixesSelectSelectionInput.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]

    # Xlib's own handler prints "XIO: fatal IO error" when the display goes
    # away (a nested session ending) - which the shell's log would show.
    io_handler_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)
    io_handler = io_handler_type(lambda _display: os._exit(0))
    libx11.XSetIOErrorHandler(io_handler)

    display = libx11.XOpenDisplay(args.display.encode())
    if not display:
        return wait_forever()
    event_base, error_base = ctypes.c_int(), ctypes.c_int()
    if not libxfixes.XFixesQueryExtension(display, ctypes.byref(event_base), ctypes.byref(error_base)):
        return wait_forever()
    root = libx11.XDefaultRootWindow(display)
    clipboard = libx11.XInternAtom(display, b"CLIPBOARD", 0)
    # XFixesSetSelectionOwnerNotifyMask | SelectionWindowDestroyNotifyMask | SelectionClientCloseNotifyMask
    libxfixes.XFixesSelectSelectionInput(display, root, clipboard, 1 | 2 | 4)

    # Hyprland's window manager is one X11 client: the window it names in
    # _NET_SUPPORTING_WM_CHECK and the one it holds the clipboard with for its
    # mirror come from the same connection. The mask is the same for every
    # client of a server, so this connection's own tells which bits to compare.
    # Read once it is there (XWayland may start before its window manager);
    # without it every owner is read and compared as before.
    mask = ctypes.cast(display, ctypes.POINTER(DisplayHead)).contents.private4
    wm_check = libx11.XInternAtom(display, b"_NET_SUPPORTING_WM_CHECK", 0)
    wm_window = [0]

    def window_manager():
        if wm_window[0]:
            return wm_window[0]
        actual_type, actual_format = ctypes.c_ulong(), ctypes.c_int()
        items, after, value = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.c_void_p()
        # XA_WINDOW is atom 33; Success is 0.
        if libx11.XGetWindowProperty(display, root, wm_check, 0, 1, 0, 33, ctypes.byref(actual_type),
                                     ctypes.byref(actual_format), ctypes.byref(items), ctypes.byref(after),
                                     ctypes.byref(value)) != 0:
            return 0
        if value.value:
            if actual_format.value == 32 and items.value == 1:
                # Format 32 comes back as C longs.
                wm_window[0] = ctypes.cast(value, ctypes.POINTER(ctypes.c_ulong))[0]
            libx11.XFree(value)
        return wm_window[0]

    x11_env = dict(os.environ, DISPLAY=args.display)
    bridge = Bridge(
        x11=lambda target, timeout: run(["xclip", "-selection", "clipboard", "-o", "-t", target],
                                        env=x11_env, timeout=timeout),
        wayland=wayland,
        write=hand_over,
        mirror=lambda owner: same_client(owner, window_manager(), mask))
    event = XEvent()
    while True:
        libx11.XNextEvent(display, ctypes.byref(event))
        if event.type != event_base.value:  # XFixesSelectionNotify
            continue
        owner = event.selection.owner
        # A burst of changes (an owner set twice, a mirror right after) is
        # one change: settle, keep the last.
        time.sleep(SETTLE)
        while libx11.XPending(display):
            libx11.XNextEvent(display, ctypes.byref(event))
            if event.type == event_base.value:
                owner = event.selection.owner
        bridge.change(owner)


if __name__ == "__main__":
    sys.exit(main())
