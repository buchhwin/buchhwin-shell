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
# The event layout ctypes reads: XFixesSelectionNotifyEvent fits in an XEvent.
check(bridge.ctypes.sizeof(bridge.XFixesSelectionNotifyEvent) <= bridge.ctypes.sizeof(bridge.XEvent), "event fits the union")
check(bridge.ctypes.sizeof(bridge.XEvent) == 24 * bridge.ctypes.sizeof(bridge.ctypes.c_long), "XEvent is 24 longs")

if failures:
    print(f"TESTS FAILED x11-clipboard-bridge ({failures})")
    sys.exit(1)
print("TESTS PASSED x11-clipboard-bridge")
