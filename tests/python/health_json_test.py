#!/usr/bin/env python3
"""The --json modes of scripts/session-check.sh and scripts/doctor.sh, which
Settings > About's Health reads (services/HealthService.qml).

session-check.sh runs against the live session and reads its PAM files, so
its reporting is taken out and run on its own, the way
tests/session-launcher-test.sh takes out faillock_gap and lid_report: each
line valid JSON with its section, a fix taken by the line it was set for and
by no other, the text report unchanged. doctor.sh runs whole, on a PATH of
stand-ins as tests/doctor-test.sh runs it: a miss with its step, the notes
with theirs, the result last, and nothing else on stdout.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def lines_of(text):
    parsed = []
    for line in text.splitlines():
        try:
            parsed.append(json.loads(line))
        except ValueError:
            failures.append("not a JSON line: %r" % line[:120])
    return parsed


# ---- session-check.sh's reporting ------------------------------------------------
functions = ["json_string", "report", "install_fix", "ok", "warn", "fail", "section", "lid_report"]
extract = " ".join("-e '/^%s() {$/,/^}$/p' -e '/^%s() { .*}$/p'" % (name, name) for name in functions)
script = """
set -uo pipefail
source "$ROOT/install/lib/distro.sh"
eval "$(sed -n %s "$ROOT/scripts/session-check.sh")"
json=$1; project_dir=/P; distro=arch; warnings=0; failures=0; fix_command=""; fix_action=""; current_section=""
exec 3>&1
if (( json )); then exec 1>/dev/null; fi
section "Power and hardware"
lid_report suspend "on battery" "" /nonexistent/50-buchhwin.conf
section "Tools"
install_fix grim
warn "grim is missing"
fix_action=restartShell
fail "clipboard history is not running"
ok "after a fix: none of its own"
install_fix "made-up-package"
warn "a \\"quoted\\" text with a back\\\\slash"
install_fix() { fix_command="package x"; }
printf 'warnings=%%d failures=%%d\\n' "$warnings" "$failures" >&2
""" % extract
for mode in ("1", "0"):
    done = subprocess.run(["bash", "-c", script, "bash", mode], env=dict(os.environ, ROOT=str(ROOT), BUCHHWIN_DISTRO="arch"),
                          capture_output=True, text=True, timeout=60)
    if mode == "1":
        items = lines_of(done.stdout)
        check(len(items) == 5, "five lines (%s)" % done.stdout)
        if len(items) == 5:
            lid, grim, clip, fine, quoted = items
            check(lid["level"] == "error" and lid["section"] == "Power and hardware"
                  and lid["command"] == "sudo /P/install/system-install.sh --logind-lid", "the lid's fix, as a command (%s)" % lid)
            check(lid["text"].startswith("lid (on battery): 'suspend' without the shell's logind inhibitor"), "and its text as before")
            check(grim["level"] == "warn" and grim["section"] == "Tools" and grim["command"] == "sudo pacman -S grim", "a tool's package (%s)" % grim)
            check(clip["action"] == "restartShell" and clip["command"] == "", "a button for the user's own (%s)" % clip)
            check(fine["level"] == "ok" and fine["command"] == "" and fine["action"] == "", "a fix goes with its line only")
            check(quoted["text"] == 'a "quoted" text with a back\\slash' and quoted["command"] == "sudo pacman -S made-up-package",
                  "quotes and backslashes survive (%s)" % quoted)
        check("warnings=2 failures=2" in done.stderr, "the counts as before (%s)" % done.stderr.strip())
    else:
        check("\x1b[33mwarn\x1b[0m    grim is missing" in done.stdout and "\x1b[31merror\x1b[0m   lid (on battery)" in done.stdout
              and "{" not in done.stdout, "without --json the report is text, as before")

# The whole script's --json switch, and its last line, as written.
source = (ROOT / "scripts" / "session-check.sh").read_text()
check("exec 3>&1 1>/dev/null" in source and '{"kind":"result","errors":%d,"warnings":%d}' in source, "session-check's switch and result line")

# ---- doctor.sh --json, on stand-ins --------------------------------------------------
with tempfile.TemporaryDirectory(prefix="buchhwin-healthjson.") as raw:
    sandbox = pathlib.Path(raw)
    bin_dir = sandbox / "bin"
    bin_dir.mkdir()
    for tool in ("bash", "sed", "awk", "grep", "dirname", "cat", "tr", "head", "readlink"):
        real = subprocess.run(["bash", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip()
        (bin_dir / tool).symlink_to(real)

    def stub(name, body="exit 0"):
        (bin_dir / name).write_text("#!/bin/sh\n%s\n" % body)
        (bin_dir / name).chmod(0o755)

    for name in ("Hyprland hyprctl quickshell setpriv kitty zsh brightnessctl wpctl pw-metadata pw-record playerctl nmcli "
                 "udevadm jq swaylock curl gammastep checkupdates flatpak hyprland-dialog gtk-launch fastfetch cmatrix cava "
                 "xclip brave dolphin qalc ollama ddcutil").split():
        stub(name)
    # The text from the screen needs a language besides Arch's own "osd".
    stub("tesseract", 'printf "List of available languages in \\"/usr/share/tessdata/\\" (2):\\neng\\nosd\\n"')
    stub("python3", "exit 1")
    stub("busctl", '[ -n "${BUS:-}" ] || exit 1\nprintf \'%b\' "$BUS"')
    qt6 = sandbox / "qt6"
    for module in ("org/kde/plasma/PimCalendars", "org/kde/plasma/workspace/calendar", "org/kde/kitemmodels", "org/kde/akonadi"):
        (qt6 / "qml" / module).mkdir(parents=True)
    (qt6 / "plugins" / "plasmacalendarplugins").mkdir(parents=True)
    (qt6 / "plugins" / "plasmacalendarplugins" / "pimevents.so").write_text("")
    home = sandbox / "home"
    (home / ".config" / "xdg-desktop-portal").mkdir(parents=True)
    (home / ".config" / "xdg-desktop-portal" / "buchhwin-shell-portals.conf").write_text("[preferred]\norg.freedesktop.impl.portal.Secret=kwallet\n")
    (sandbox / "os-arch").write_text("ID=arch\n")
    bus = ("NAME PID PROCESS USER CONNECTION UNIT SESSION DESCRIPTION\\n"
           "net.hadess.PowerProfiles 765 ppd root :1.13 ppd.service - -\\n"
           "org.bluez 683 bluetoothd root :1.4 bluetooth.service - -\\n")
    environment = {"PATH": str(bin_dir), "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
                   "BUCHHWIN_QT6_DIR": str(qt6), "BUCHHWIN_OS_RELEASE": str(sandbox / "os-arch"), "BUS": bus}
    done = subprocess.run(["bash", str(ROOT / "scripts" / "doctor.sh"), "--json"], env=environment,
                          capture_output=True, text=True, timeout=60)
    items = lines_of(done.stdout)
    by_id = {item.get("id"): item for item in items if "id" in item}
    check(items and items[-1] == {"kind": "result", "status": 0}, "the result last (%s)" % (items[-1:] or done.stdout))
    # What the machine running the test decides itself (its huge pages, its
    # KWallet portal file) may come on top.
    check({"plocate", "networkmanager"} <= set(by_id) <= {"plocate", "networkmanager", "thp", "kwallet-portal"},
          "only what is missing (%s)" % sorted(by_id))
    check(by_id.get("plocate", {}).get("command") == "sudo pacman -S plocate"
          and by_id.get("plocate", {}).get("level") == "missing", "a miss with its package (%s)" % by_id.get("plocate"))
    check(by_id.get("networkmanager", {}).get("command") == "sudo systemctl enable --now NetworkManager",
          "a service with its command (%s)" % by_id.get("networkmanager"))
    plain = subprocess.run(["bash", str(ROOT / "scripts" / "doctor.sh")], env=environment, capture_output=True, text=True, timeout=60)
    check("missing  plocate (some shell features stay unavailable; sudo pacman -S plocate)" in plain.stdout
          and "{" not in plain.stdout, "without --json the report as before")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED health_json_test")
    sys.exit(1)
print("TESTS PASSED health_json_test")
