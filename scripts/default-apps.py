#!/usr/bin/env python3
"""Default applications for the buchhwin-shell session.

  default-apps.py list              JSON: categories, current default, candidates
  default-apps.py get CATEGORY      print the default desktop id (may be empty)
  default-apps.py set CATEGORY ID   make ID the session default
  default-apps.py unset CATEGORY    drop the session default (Plasma's applies)

MIME defaults go to ${XDG_CONFIG_HOME}/buchhwin-shell-mimeapps.list, which GLib,
xdg-utils and KDE read before mimeapps.list when XDG_CURRENT_DESKTOP starts with
buchhwin-shell, so Plasma keeps its own defaults. The terminal (no MIME type)
goes to buchhwin-shell-xdg-terminals.list (xdg-terminal-exec format).
"""

import json
import os
import pathlib
import sys
import tempfile

SESSION = "buchhwin-shell"

# id, label, MIME types (the first decides the current default), candidate filter
CATEGORIES = [
    ("browser", "Web browser", ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"], "browser"),
    ("email", "Email", ["x-scheme-handler/mailto"], "mime"),
    ("files", "File manager", ["inode/directory"], "files"),
    ("terminal", "Terminal", [], "terminal"),
    ("text", "Text editor", ["text/plain"], "media"),
    ("images", "Images", ["image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp", "image/tiff", "image/svg+xml"], "media"),
    ("pdf", "PDF documents", ["application/pdf"], "mime"),
    ("video", "Video", ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg"], "media"),
    ("music", "Music", ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/x-wav", "audio/mp4", "audio/aac"], "media"),
    ("archives", "Archives", ["application/zip", "application/x-tar", "application/x-compressed-tar", "application/x-7z-compressed", "application/gzip"], "mime"),
]


def home():
    return pathlib.Path(os.path.expanduser("~"))


def config_home():
    return pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or home() / ".config")


def data_home():
    return pathlib.Path(os.environ.get("XDG_DATA_HOME") or home() / ".local" / "share")


def config_dirs():
    return [config_home()] + [pathlib.Path(p) for p in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if p]


def data_dirs():
    dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [data_home()] + [pathlib.Path(p) for p in dirs.split(":") if p]


def desktops():
    names = [name.lower() for name in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if name]
    return names or [SESSION]


def session_list():
    return config_home() / (SESSION + "-mimeapps.list")


def terminal_list():
    return config_home() / (SESSION + "-xdg-terminals.list")


def read_entry(path):
    """The [Desktop Entry] group of a desktop file, or None if it is not a visible app."""
    entry = {}
    in_group = False
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return None
    for line in lines:
        text = line.strip()
        if text.startswith("[") and text.endswith("]"):
            in_group = text == "[Desktop Entry]"
        elif in_group and "=" in text and not text.startswith("#"):
            key, value = text.split("=", 1)
            entry.setdefault(key.strip(), value.strip())
    if not entry or entry.get("Type", "Application") != "Application" or entry.get("Hidden", "false") == "true":
        return None
    split = lambda key: [item for item in entry.get(key, "").split(";") if item]
    return {
        "name": entry.get("Name", ""),
        "icon": entry.get("Icon", ""),
        "mimes": split("MimeType"),
        "categories": split("Categories"),
        "noDisplay": entry.get("NoDisplay", "false") == "true",
    }


def applications():
    """Desktop id -> entry; earlier data dirs win like in the XDG spec."""
    apps = {}
    for base in data_dirs():
        root = base / "applications"
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.desktop")):
            desktop_id = str(path.relative_to(root)).replace(os.sep, "-")
            if desktop_id in apps:
                continue
            entry = read_entry(path)
            apps[desktop_id] = entry  # None hides lower-priority copies too
    return {key: value for key, value in apps.items() if value}


class InstalledApps:
    """Membership only, without reading every desktop file on the system.

    `applications()` walks every XDG data directory and parses all of it -
    322 files and 74 ms on this machine - and `get` then uses the result for
    nothing but `desktop_id in apps`. That ran on every `Super+Enter`, to
    answer a question whose answer never changes between two launches, and it
    was the largest project-controlled part of the delay before a terminal
    appeared.

    The same answer, one file at a time: a desktop id is the file's path below
    `applications/` with the separators turned into dashes, so the common case
    is one `is_file()`. The catalogue is only built when an id contains a dash
    that might be a subdirectory instead, which no id on this machine does.

    Earlier data directories win *and an unreadable entry in an earlier one
    hides a good copy in a later one* - `applications()` stores None for those
    and filters afterwards - so this stops at the first directory that has the
    file, exactly as the catalogue would.
    """

    def __init__(self):
        self._catalogue = None

    def __contains__(self, desktop_id):
        if not desktop_id or not desktop_id.endswith(".desktop"):
            return False
        for base in data_dirs():
            path = base / "applications" / desktop_id
            if path.is_file():
                return read_entry(path) is not None
        if "-" not in desktop_id:
            return False
        # A dash may be a directory separator. Rare enough to be worth a full
        # scan rather than guessing at every way to split it.
        if self._catalogue is None:
            self._catalogue = applications()
        return desktop_id in self._catalogue


def mime_lists():
    """mimeapps.list files in lookup order (desktop-specific first per dir)."""
    files = []
    for base in config_dirs() + [d / "applications" for d in data_dirs()]:
        files += [base / (name + "-mimeapps.list") for name in desktops()]
        files.append(base / "mimeapps.list")
    return files


def read_groups(path):
    groups = {}
    current = None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return groups
    for line in lines:
        text = line.strip()
        if text.startswith("[") and text.endswith("]"):
            current = groups.setdefault(text[1:-1], {})
        elif current is not None and "=" in text and not text.startswith("#"):
            key, value = text.split("=", 1)
            current[key.strip()] = [item for item in value.strip().split(";") if item]
    return groups


def default_for(mime, apps):
    """(desktop id, source): source is session, plasma (another mimeapps.list) or system."""
    for path in mime_lists():
        for desktop_id in read_groups(path).get("Default Applications", {}).get(mime, []):
            if desktop_id in apps:
                return desktop_id, "session" if path == session_list() else "plasma"
    for base in data_dirs():
        cache = read_groups(base / "applications" / "mimeinfo.cache").get("MIME Cache", {})
        for desktop_id in cache.get(mime, []):
            if desktop_id in apps:
                return desktop_id, "system"
    return "", "system"


def terminal_default(apps):
    try:
        lines = terminal_list().read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    for line in lines:
        desktop_id = line.strip()
        if desktop_id and not desktop_id.startswith("#") and desktop_id in apps:
            return desktop_id, "session"
    return ("kitty.desktop" if "kitty.desktop" in apps else ""), "system"


def candidates(kind, mimes, apps):
    result = []
    for desktop_id, entry in apps.items():
        if entry["noDisplay"]:
            continue
        cats = entry["categories"]
        supports = any(mime in entry["mimes"] for mime in mimes)
        if kind == "terminal":
            ok = "TerminalEmulator" in cats
        elif kind == "files":
            ok = "FileManager" in cats
        elif kind == "browser":
            ok = "WebBrowser" in cats or "x-scheme-handler/http" in entry["mimes"]
        elif kind == "media":
            ok = supports and "WebBrowser" not in cats
        else:
            ok = supports
        if ok:
            result.append(desktop_id)
    return result


def category(category_id):
    for item in CATEGORIES:
        if item[0] == category_id:
            return item
    raise ValueError("unknown category: " + category_id)


def describe(desktop_id, apps):
    entry = apps.get(desktop_id) or {}
    return {"id": desktop_id, "name": entry.get("name") or desktop_id.removesuffix(".desktop"), "icon": entry.get("icon", "")}


def list_all():
    apps = applications()
    out = []
    for category_id, label, mimes, kind in CATEGORIES:
        current, source = terminal_default(apps) if kind == "terminal" else default_for(mimes[0], apps)
        ids = candidates(kind, mimes, apps)
        if current and current not in ids:
            ids.append(current)
        items = sorted((describe(i, apps) for i in ids), key=lambda item: item["name"].lower())
        out.append({"id": category_id, "label": label, "current": current, "source": source, "session": source == "session",
                    "currentName": describe(current, apps)["name"] if current else "", "candidates": items})
    return {"categories": out}


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + "-")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


def update_defaults(path, mimes, desktop_id):
    """Set (or with desktop_id None remove) Default Applications keys, keeping the rest."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        lines = []
    out = []
    in_defaults = False
    seen_defaults = False
    for line in lines:
        text = line.strip()
        if text.startswith("[") and text.endswith("]"):
            if in_defaults and desktop_id:
                out += [mime + "=" + desktop_id + ";" for mime in mimes]
            in_defaults = text == "[Default Applications]"
            seen_defaults = seen_defaults or in_defaults
            out.append(line)
            continue
        if in_defaults and "=" in text and text.split("=", 1)[0].strip() in mimes:
            continue
        out.append(line)
    if in_defaults and desktop_id:
        out += [mime + "=" + desktop_id + ";" for mime in mimes]
    if not seen_defaults and desktop_id:
        if out and out[-1].strip():
            out.append("")
        out.append("[Default Applications]")
        out += [mime + "=" + desktop_id + ";" for mime in mimes]
    write_atomic(path, "\n".join(out) + "\n")


def set_default(category_id, desktop_id):
    _, _, mimes, kind = category(category_id)
    apps = applications()
    if desktop_id not in apps:
        raise ValueError("unknown application: " + desktop_id)
    if kind == "terminal":
        write_atomic(terminal_list(), desktop_id + "\n")
    else:
        update_defaults(session_list(), mimes, desktop_id)


def unset_default(category_id):
    _, _, mimes, kind = category(category_id)
    if kind == "terminal":
        try:
            terminal_list().unlink()
        except FileNotFoundError:
            pass
    elif session_list().exists():
        update_defaults(session_list(), mimes, None)


def get_default(category_id):
    _, _, mimes, kind = category(category_id)
    # Both paths ask only whether an id is installed, so they get an answer
    # that does not read the whole system to give it. This is on the critical
    # path of every terminal, browser and file-manager launch.
    apps = InstalledApps()
    return (terminal_default(apps) if kind == "terminal" else default_for(mimes[0], apps))[0]


def main(argv):
    try:
        if argv == ["list"]:
            print(json.dumps(list_all()))
        elif len(argv) == 2 and argv[0] == "get":
            print(get_default(argv[1]))
        elif len(argv) == 3 and argv[0] == "set":
            set_default(argv[1], argv[2])
            print(json.dumps({"ok": True}))
        elif len(argv) == 2 and argv[0] == "unset":
            unset_default(argv[1])
            print(json.dumps({"ok": True}))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
