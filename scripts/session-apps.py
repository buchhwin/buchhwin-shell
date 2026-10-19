#!/usr/bin/env python3
"""The apps of a session, kept for the next login (services/SessionAppsService.qml).

  session-apps.py snapshot STATE WINDOWS   keep the session's windows in STATE
  session-apps.py mark-offered STATE       the next login offers them no more
  session-apps.py forget STATE             STATE removed
  session-apps.py wait-login LOG [SECONDS] wait for the login's wallet step

`snapshot` runs as the session ends, before scripts/session-action.sh logs
out, restarts or shuts down: WINDOWS is the shell's list (JSON: address, the
desktop entry, the window class, the screen and the workspace of its block),
and Hyprland is asked only for what the shell does not track - whether a
window floats, and where and how large it is then, relative to its screen.
The file holds desktop ids, classes and places, never a title, and is
written atomically and readable by the user alone (0600). A failure writes
nothing and still exits 0: the session ends either way.

`wait-login` reads scripts/session-init.sh's timeline (startup.log) until the
wallet step has marked its result, so the work apps a login starts come up
after the one KWallet prompt of the login and not under it. It never asks
D-Bus anything. Exit 0 once the step has run, 2 without a timeline or after
SECONDS (default 120: the step itself gives up after 90).
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import time

VERSION = 1
MAX_ENTRIES = 60
CLASS = re.compile(r"^[^\x00-\x1f\x7f]{1,255}$")
MONITOR_NAME = re.compile(r"^[A-Za-z0-9_.:@-]{1,64}$")
ADDRESS = re.compile(r"^(0x)?[0-9a-fA-F]{1,16}$")
# The marks session-init.sh writes once the wallet step is over (or once it
# is done altogether, for a login without the KWallet hand-over).
LOGIN_DONE = re.compile(r"ms (kwallet( unlocked| LOCKED| NOT available)?:|session-init finished)")


def address_key(value):
    text = str(value or "").strip().lower()
    if not ADDRESS.match(text):
        return ""
    return text[2:] if text.startswith("0x") else text


def integer(value, low, high):
    try:
        number = int(round(float(value)))
    except (TypeError, ValueError, OverflowError):
        return None
    return number if low <= number <= high else None


def clean_window(raw):
    """One window of the shell's list, only the fields a place needs."""
    if not isinstance(raw, dict):
        return None
    address = address_key(raw.get("address"))
    cls = str(raw.get("cls") or "").strip().lower()
    workspace = integer(raw.get("workspace"), 1, 9999)
    if not address or not CLASS.match(cls) or workspace is None:
        return None
    app = raw.get("app") if isinstance(raw.get("app"), str) and CLASS.match(raw.get("app")) else ""
    monitor = raw.get("monitor") if isinstance(raw.get("monitor"), str) and len(raw.get("monitor")) <= 255 \
        and not re.search(r"[\x00-\x1f]", raw.get("monitor")) else ""
    name = raw.get("monitorName") if isinstance(raw.get("monitorName"), str) \
        and MONITOR_NAME.match(raw.get("monitorName")) else ""
    return {"address": address, "app": app, "cls": cls, "monitor": monitor, "monitorName": name,
            "workspace": workspace, "local": raw.get("local") is True}


def entries(windows, clients, monitors):
    """The kept windows: the shell's list with Hyprland's floating state and
    geometry joined by address, the geometry relative to the window's screen.
    A window Hyprland does not list (it closed meanwhile) is left out; with
    no answer from Hyprland at all (`clients` None) every window is kept as
    tiled."""
    by_address = {}
    for client in clients or []:
        if isinstance(client, dict):
            key = address_key(client.get("address"))
            if key:
                by_address[key] = client
    origins = {}
    for monitor in monitors or []:
        if isinstance(monitor, dict) and isinstance(monitor.get("id"), int):
            origins[monitor["id"]] = (integer(monitor.get("x"), -100000, 100000) or 0,
                                      integer(monitor.get("y"), -100000, 100000) or 0)
    result = []
    for raw in windows if isinstance(windows, list) else []:
        window = clean_window(raw)
        if not window:
            continue
        client = by_address.get(window["address"])
        if clients is not None and client is None:
            continue
        entry = {key: window[key] for key in ("app", "cls", "monitor", "monitorName", "workspace", "local")}
        entry["floating"] = False
        if client and client.get("floating") is True:
            at, size = client.get("at"), client.get("size")
            origin = origins.get(client.get("monitor"), (0, 0))
            if isinstance(at, list) and isinstance(size, list) and len(at) == 2 and len(size) == 2:
                x, y = integer(at[0], -100000, 100000), integer(at[1], -100000, 100000)
                width, height = integer(size[0], 1, 100000), integer(size[1], 1, 100000)
                if None not in (x, y, width, height):
                    entry.update({"floating": True, "x": x - origin[0], "y": y - origin[1],
                                  "width": width, "height": height})
        result.append(entry)
        if len(result) >= MAX_ENTRIES:
            break
    return result


def hyprctl_json(what):
    """`hyprctl -j WHAT` parsed, or None when Hyprland does not answer."""
    try:
        done = subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True, timeout=2, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if done.returncode != 0:
        return None
    try:
        value = json.loads(done.stdout)
    except ValueError:
        return None
    return value if isinstance(value, list) else None


def write_private(path, data):
    """`data` as JSON at `path`, replaced in one step, mode 0600 from the
    first byte (mkstemp creates the file so)."""
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, mode=0o700, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".session-apps.", dir=directory)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=1)
            stream.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def read_state(path):
    try:
        with open(path, encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def snapshot(path, windows_json, now=None):
    try:
        windows = json.loads(windows_json)
    except ValueError:
        windows = []
    clients = hyprctl_json("clients")
    monitors = hyprctl_json("monitors") if clients is not None else None
    stamp = (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    write_private(path, {"version": VERSION, "savedAt": stamp, "offered": False,
                         "entries": entries(windows, clients, monitors)})


def mark_offered(path):
    state = read_state(path)
    if state is None:
        return
    state["offered"] = True
    write_private(path, state)


def forget(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def login_done(text):
    return any(LOGIN_DONE.search(line) for line in str(text or "").splitlines())


def wait_login(log, seconds=120.0, interval=0.5, sleep=time.sleep, clock=time.monotonic):
    """0 once `log` shows the wallet step's result, 2 without a log (after a
    short grace: session-init.sh writes its first line before it starts the
    shell) or when the time is up."""
    start = clock()
    while True:
        try:
            with open(log, encoding="utf-8", errors="replace") as stream:
                if login_done(stream.read()):
                    return 0
        except FileNotFoundError:
            if clock() - start >= 3:
                return 2
        except OSError:
            return 2
        if clock() - start >= seconds:
            return 2
        sleep(interval)


def main(argv):
    if len(argv) == 4 and argv[1] == "snapshot":
        try:
            snapshot(argv[2], argv[3])
        except (OSError, ValueError) as error:
            print("session-apps: not kept: %s" % error, file=sys.stderr)
        return 0
    if len(argv) == 3 and argv[1] == "mark-offered":
        try:
            mark_offered(argv[2])
        except (OSError, ValueError) as error:
            print("session-apps: %s" % error, file=sys.stderr)
            return 1
        return 0
    if len(argv) == 3 and argv[1] == "forget":
        try:
            forget(argv[2])
        except OSError as error:
            print("session-apps: %s" % error, file=sys.stderr)
            return 1
        return 0
    if len(argv) in (3, 4) and argv[1] == "wait-login":
        try:
            seconds = float(argv[3]) if len(argv) == 4 else 120.0
        except ValueError:
            seconds = 120.0
        return wait_login(argv[2], max(0.0, min(seconds, 600.0)))
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
