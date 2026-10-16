#!/usr/bin/env python3
"""Hand text an X11 program copies on to the Wayland clipboard.

Hyprland mirrors the clipboard between Wayland and XWayland, but an X11
program that takes the clipboard while none of its windows has the focus is
not mirrored: Citrix's client puts what was copied in the remote session on
the X11 clipboard only as its window loses the focus, and by then a Wayland
window has it. Text copied in Citrix could not be pasted here (16.10.; the
X11 clipboard held it, the Wayland one still the previous picture).

This watches the X11 CLIPBOARD through XFixes and, when its owner changes,
reads the text with xclip and hands it to wl-copy - only when it differs from
what the Wayland clipboard already offers, which is also what keeps Hyprland's
own mirror (Wayland to X11, whenever an X11 window gets the focus) from coming
back here as a change. An X11 owner that goes away with text this put there
(a password manager clearing its copy) clears the Wayland copy too.

Text only. Quiet: without xclip, wl-copy or an X display it waits and prints
nothing, and a display that goes away ends it without a word (the shell's log
is checked for warnings).

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
SETTLE = 0.12


def digest(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def decide(x11_text, wayland_text, bridged, owner_gone):
    """What to do with one change: "copy", "clear" or "skip".

    x11_text / wayland_text are the bytes each side offers as text (None when
    it offers none), bridged the digest of the last text this handed over.
    """
    if owner_gone:
        return "clear" if bridged is not None and digest(wayland_text) == bridged else "skip"
    if not x11_text:
        return "skip"
    if x11_text == wayland_text:
        return "skip"
    return "copy"


def run(command, env=None):
    try:
        result = subprocess.run(command, capture_output=True, timeout=TIMEOUT, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout if result.returncode == 0 else None


def hand_over(command, data=None):
    """wl-copy stays behind to serve the clipboard: nothing of ours may be
    open in it, or waiting for its output would wait for that."""
    try:
        result = subprocess.run(command, input=data, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=TIMEOUT)
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


def wait_forever():
    signal.pause()
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ""))
    args = parser.parse_args(argv)
    if not args.display or not shutil.which("xclip") or not shutil.which("wl-copy") or not shutil.which("wl-paste"):
        return wait_forever()
    x11 = ctypes.util.find_library("X11")
    xfixes = ctypes.util.find_library("Xfixes")
    if not x11 or not xfixes:
        return wait_forever()
    libx11 = ctypes.CDLL(x11)
    libxfixes = ctypes.CDLL(xfixes)
    libx11.XOpenDisplay.restype = ctypes.c_void_p
    libx11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    libx11.XDefaultRootWindow.restype = ctypes.c_ulong
    libx11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    libx11.XInternAtom.restype = ctypes.c_ulong
    libx11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    libx11.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.POINTER(XEvent)]
    libx11.XPending.argtypes = [ctypes.c_void_p]
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
    clipboard = libx11.XInternAtom(display, b"CLIPBOARD", 0)
    # XFixesSetSelectionOwnerNotifyMask | SelectionWindowDestroyNotifyMask | SelectionClientCloseNotifyMask
    libxfixes.XFixesSelectSelectionInput(display, libx11.XDefaultRootWindow(display), clipboard, 1 | 2 | 4)

    x11_env = dict(os.environ, DISPLAY=args.display)
    bridged = None
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
        wayland_text = run(["wl-paste", "--no-newline", "--type", "text/plain"])
        if owner == 0:
            if decide(None, wayland_text, bridged, True) == "clear":
                hand_over(["wl-copy", "--clear"])
                bridged = None
            continue
        x11_text = run(["xclip", "-selection", "clipboard", "-o", "-t", "UTF8_STRING"], env=x11_env)
        if decide(x11_text, wayland_text, bridged, False) == "copy":
            if hand_over(["wl-copy", "--type", "text/plain;charset=utf-8"], data=x11_text):
                bridged = digest(x11_text)


if __name__ == "__main__":
    sys.exit(main())
