#!/usr/bin/env python3
"""Unit test for scripts/default-apps.py with a temporary XDG tree."""

import importlib.util
import os
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("default_apps", ROOT / "scripts" / "default-apps.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def desktop(directory, name, body):
    path = directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("[Desktop Entry]\nType=Application\n" + body, encoding="utf-8")


with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    config, data, system = base / "config", base / "data", base / "system"
    os.environ.update({"XDG_CONFIG_HOME": str(config), "XDG_CONFIG_DIRS": str(base / "etc"),
                       "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(system),
                       "XDG_CURRENT_DESKTOP": "buchhwin-shell:Hyprland"})
    apps = system / "applications"
    desktop(apps, "firefox.desktop", "Name=Firefox\nCategories=Network;WebBrowser;\nMimeType=text/html;x-scheme-handler/http;image/png;\n")
    desktop(apps, "brave-browser.desktop", "Name=Brave\nCategories=Network;WebBrowser;\nMimeType=text/html;x-scheme-handler/http;\n")
    desktop(apps, "org.kde.gwenview.desktop", "Name=Gwenview\nCategories=Graphics;\nMimeType=image/png;image/jpeg;inode/directory;\n")
    desktop(apps, "org.kde.dolphin.desktop", "Name=Dolphin\nCategories=System;FileManager;\nMimeType=inode/directory;\n")
    desktop(apps, "kitty.desktop", "Name=kitty\nCategories=System;TerminalEmulator;\n")
    desktop(apps, "kitty-open.desktop", "Name=kitty URL Launcher\nNoDisplay=true\nMimeType=inode/directory;\n")
    desktop(apps, "kde4/konsole.desktop", "Name=Konsole\nCategories=System;TerminalEmulator;\n")
    desktop(apps, "hidden.desktop", "Name=Hidden\nHidden=true\nCategories=TerminalEmulator;\n")
    desktop(apps, "broken.desktop", "Name=Broken\nthis line has no equals sign\nCategories=TerminalEmulator;\n")
    desktop(data / "applications", "firefox.desktop", "Name=Firefox (local)\nCategories=WebBrowser;\nMimeType=x-scheme-handler/http;\n")
    (apps / "mimeinfo.cache").write_text("[MIME Cache]\ninode/directory=kitty-open.desktop;org.kde.dolphin.desktop;\n", encoding="utf-8")
    config.mkdir(parents=True)
    (config / "mimeapps.list").write_text("[Added Associations]\ntext/plain=x.desktop;\n\n[Default Applications]\nx-scheme-handler/http=brave-browser.desktop\n", encoding="utf-8")

    listing = {item["id"]: item for item in module.list_all()["categories"]}
    check(listing["browser"]["current"] == "brave-browser.desktop" and listing["browser"]["source"] == "plasma", "Plasma default read from mimeapps.list")
    check([c["name"] for c in listing["browser"]["candidates"]] == ["Brave", "Firefox (local)"], "browsers listed, local desktop file wins")
    # kitty-open.desktop comes first in the cache, but it is a hidden helper,
    # not a file manager: the dock's Files pin and Super+E want Dolphin.
    check(listing["files"]["current"] == "org.kde.dolphin.desktop" and listing["files"]["source"] == "system",
          "mimeinfo.cache fallback, past the hidden kitty-open helper: " + listing["files"]["current"])
    check([c["id"] for c in listing["files"]["candidates"]] == ["org.kde.dolphin.desktop"], "file managers only")
    check(module.get_default("files") == "org.kde.dolphin.desktop", "get (InstalledApps) answers the same")
    check([c["id"] for c in listing["images"]["candidates"]] == ["org.kde.gwenview.desktop"], "browsers are not offered as image viewers")
    check(sorted(c["id"] for c in listing["terminal"]["candidates"]) == ["broken.desktop", "kde4-konsole.desktop", "kitty.desktop"], "terminals incl. subdirectory ids, hidden excluded")
    check(listing["terminal"]["current"] == "kitty.desktop", "kitty is the terminal fallback")

    module.set_default("browser", "firefox.desktop")
    module.set_default("files", "org.kde.dolphin.desktop")
    module.set_default("terminal", "kde4-konsole.desktop")
    check(module.get_default("browser") == "firefox.desktop", "session default wins over mimeapps.list")
    check({item["id"]: item for item in module.list_all()["categories"]}["browser"]["session"], "session source reported")
    check(module.get_default("terminal") == "kde4-konsole.desktop", "terminal list written")
    text = (config / "buchhwin-shell-mimeapps.list").read_text(encoding="utf-8")
    check("x-scheme-handler/https=firefox.desktop;" in text and "text/html=firefox.desktop;" in text, "all browser types set")
    check("brave" not in (config / "buchhwin-shell-mimeapps.list").read_text() and "brave" in (config / "mimeapps.list").read_text(), "Plasma's mimeapps.list untouched")
    module.set_default("browser", "brave-browser.desktop")
    text = (config / "buchhwin-shell-mimeapps.list").read_text(encoding="utf-8")
    check(text.count("x-scheme-handler/http=") == 1 and "inode/directory=org.kde.dolphin.desktop;" in text, "replacing keeps one entry and other categories")
    module.unset_default("browser")
    check("x-scheme-handler/http=" not in (config / "buchhwin-shell-mimeapps.list").read_text(), "unset removes the session entries")
    check(module.get_default("files") == "org.kde.dolphin.desktop", "other session defaults stay")
    module.unset_default("terminal")
    check(module.get_default("terminal") == "kitty.desktop", "terminal unset falls back")
    try:
        module.set_default("browser", "missing.desktop")
        check(False, "unknown apps rejected")
    except ValueError:
        pass
    try:
        module.set_default("nope", "firefox.desktop")
        check(False, "unknown categories rejected")
    except ValueError:
        pass

# The system's cache, in an order nobody chose: hidden helpers are passed
# over, a file manager comes first for a directory, and someone's choice in a
# mimeapps.list counts as it is.
with tempfile.TemporaryDirectory() as temp:
    base = pathlib.Path(temp)
    config, data, system = base / "config", base / "data", base / "system"
    os.environ.update({"XDG_CONFIG_HOME": str(config), "XDG_CONFIG_DIRS": str(base / "etc"),
                       "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(system),
                       "XDG_CURRENT_DESKTOP": "buchhwin-shell:Hyprland"})
    apps = system / "applications"
    desktop(apps, "kitty-open.desktop", "Name=kitty URL Launcher\nNoDisplay=true\nMimeType=inode/directory;application/pdf;\n")
    desktop(apps, "org.kde.gwenview.desktop", "Name=Gwenview\nCategories=Graphics;\nMimeType=inode/directory;\n")
    desktop(apps, "org.kde.dolphin.desktop", "Name=Dolphin\nCategories=System;FileManager;\nMimeType=inode/directory;\n")
    desktop(apps, "org.kde.okular.desktop", "Name=Okular\nMimeType=application/pdf;\n")
    cache = apps / "mimeinfo.cache"
    cache.write_text("[MIME Cache]\ninode/directory=kitty-open.desktop;org.kde.gwenview.desktop;org.kde.dolphin.desktop;\n"
                     "application/pdf=kitty-open.desktop;org.kde.okular.desktop;\n", encoding="utf-8")
    both = lambda category: (module.get_default(category),
                             {item["id"]: item for item in module.list_all()["categories"]}[category]["current"])
    check(both("files") == ("org.kde.dolphin.desktop",) * 2, "a file manager before an image viewer that opens folders: " + str(both("files")))
    check(both("pdf") == ("org.kde.okular.desktop",) * 2, "a hidden helper is no one's default, for any type: " + str(both("pdf")))
    (apps / "org.kde.dolphin.desktop").unlink()
    check(both("files") == ("org.kde.gwenview.desktop",) * 2, "no file manager: the first visible entry: " + str(both("files")))
    (apps / "org.kde.gwenview.desktop").unlink()
    check(both("files") == ("", ""), "only the hidden helper: no default: " + str(both("files")))
    config.mkdir(parents=True)
    (config / "mimeapps.list").write_text("[Default Applications]\ninode/directory=kitty-open.desktop;\n", encoding="utf-8")
    check(both("files") == ("kitty-open.desktop",) * 2, "someone's choice in a mimeapps.list counts as it is: " + str(both("files")))

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED default_apps_test")
    sys.exit(1)
print("TESTS PASSED default_apps_test")
