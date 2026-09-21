#!/usr/bin/env python3
"""scripts/app-scroll.py against scratch files; the host's VS Code is untouched."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "scripts", "app-scroll.py")

def run(*args):
    result = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    return result.returncode, json.loads(result.stdout or "{}")


def check(name, got, expected):
    if got != expected:
        print(f"FAIL {name}: expected {expected!r}, got {got!r}")
        sys.exit(1)
    print(f"ok   {name}")


def main():
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "settings.json")

        code, report = run("status", "--path", path)
        check("status without a file", [code, report["problem"], report["changed"]], [0, "missing", False])
        code, _ = run("apply", "--path", path, "--factor", "1")
        check("apply without a file fails", code, 1)

        with open(path, "w", encoding="utf-8") as handle:
            handle.write("""{
    // a comment VS Code wrote
    "editor.fontSize": 14,
    "window.zoomLevel": 0, /* another */
}
""")
        code, report = run("apply", "--path", path, "--factor", "1.5")
        data = json.load(open(path, encoding="utf-8"))
        check("apply writes both keys", [code, report["changed"], data["editor.mouseWheelScrollSensitivity"],
                                         data["workbench.list.mouseWheelScrollSensitivity"]],
              [0, True, 0.67, 0.67])
        check("other settings survive", [data["editor.fontSize"], data["window.zoomLevel"]], [14, 0])
        backup_text = open(path + ".buchhwin-backup", encoding="utf-8").read()
        check("backup keeps the original text with its comments",
              ["// a comment VS Code wrote" in backup_text, "mouseWheelScrollSensitivity" in backup_text], [True, False])

        code, report = run("apply", "--path", path, "--factor", "1.5")
        check("second apply changes nothing", [code, report["changed"]], [0, False])

        code, report = run("status", "--path", path, "--factor", "0.5")
        check("status reports both values", [report["current"], report["wanted"]], [0.67, 2.0])

        code, report = run("apply", "--path", path, "--factor", "5")
        data = json.load(open(path, encoding="utf-8"))
        check("factor clamped", data["editor.mouseWheelScrollSensitivity"], 0.5)

        code, report = run("reset", "--path", path)
        data = json.load(open(path, encoding="utf-8"))
        check("reset removes the keys", [report["changed"], "editor.mouseWheelScrollSensitivity" in data,
                                         data["editor.fontSize"]], [True, False, 14])
        code, report = run("reset", "--path", path)
        check("second reset changes nothing", report["changed"], False)

        code, report = run("apply", "--path", path, "--factor", "1", "--dry-run")
        data = json.load(open(path, encoding="utf-8"))
        check("dry run writes nothing", ["editor.mouseWheelScrollSensitivity" in data, report["wanted"]], [False, 1.0])

    print("app-scroll tests passed")


if __name__ == "__main__":
    main()
