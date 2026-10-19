pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "system/SystemLogic.js" as SystemLogic

// What Settings > About shows: the system, the versions it runs on and the
// hardware. Read once, the first time the page asks, and kept: none of it
// changes while the shell runs (an update of the shell restarts it, and the
// Hyprland and Quickshell a system update installs run from the next start).
// The page is built again on every visit, and it used to run its own
// reading each time - a shell and some fifteen processes, among them a
// second Hyprland and quickshell for their versions and lspci, about 0.3 s
// and 80-100 ms of CPU.
Singleton {
    id: root

    // key -> text: os, kernel, host, hyprland, quickshell, cpu, gpu, ram,
    // session. Empty until the reading has come back.
    property var info: ({})
    property bool asked: false
    // How many times it was read (once per session; the test counts).
    property int reads: 0

    function load() {
        if (asked) return
        asked = true
        reader.running = true
    }

    // The reading's `key=value` lines; memory comes as KiB and is written
    // out in the decimal units the System popup uses, which said "14.3 GB"
    // while this page said "13.3 GiB" for the same memory.
    function parse(text) {
        const result = {}
        for (const line of String(text || "").split("\n")) {
            const index = line.indexOf("=")
            if (index > 0) result[line.slice(0, index)] = line.slice(index + 1)
        }
        if (Number(result.ramKib) > 0) result.ram = SystemLogic.formatBytes(Number(result.ramKib) * 1024)
        return result
    }

    Process {
        id: reader
        command: ["sh", "-c", [
            ". /etc/os-release 2>/dev/null; echo \"os=$PRETTY_NAME\"",
            "echo \"kernel=$(uname -r)\"",
            "echo \"host=$(cat /etc/hostname 2>/dev/null || uname -n)\"",
            "echo \"hyprland=$(Hyprland --version 2>/dev/null | head -n1 | cut -d' ' -f2)\"",
            // "quickshell 0.2.1, revision …" (Fedora, Leap) and "Quickshell
            // 0.3.2 (revision , distributed by Arch Linux)": the number alone.
            "echo \"quickshell=$(quickshell --version 2>/dev/null | head -n1 | sed -E 's/^[Qq]uickshell //; s/ \\(.*//; s/,.*//')\"",
            "echo \"cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')\"",
            "echo \"gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 | cut -d: -f3- | sed 's/^ //')\"",
            "echo \"ramKib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)\"",
            "echo \"session=${XDG_SESSION_DESKTOP:-unknown}\""
        ].join("; ")]
        onStarted: root.reads += 1
        stdout: StdioCollector {
            onStreamFinished: root.info = root.parse(text)
        }
    }
}
