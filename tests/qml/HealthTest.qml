import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/health/HealthLogic.js" as H

// Settings > About's Health (HealthLogic): session-check.sh's and doctor.sh's
// JSON lines, the shell's own findings, one list with the most urgent first,
// and the words. Lines as the two scripts write them, with invented paths.
ShellRoot {
    Component.onCompleted: {
        const session = H.parseLines([
            '{"level":"ok","section":"Session","text":"Hyprland is running (0.56.2)","command":"","action":""}',
            '{"level":"warn","section":"Power and hardware","text":"/etc/pam.d/buchhwin-lock-password does not count wrong passwords","command":"sudo install -m 644 /x/session/pam/buchhwin-lock-password.arch /etc/pam.d/buchhwin-lock-password","action":""}',
            '{"level":"error","section":"Power and hardware","text":"swayidle (lock before sleep) is not running","command":"","action":"restartShell"}',
            'not json',
            '{"level":"error","section":"x","text":"","command":"","action":""}',
            '{"level":"warn","section":"Tools","text":"grim is missing","command":"sudo pacman -S grim\\nrm -rf x","action":"format"}',
            '{"kind":"result","errors":1,"warnings":2}'].join("\n"), "session")
        T.eq(session.ok, 1, "an ok is counted")
        T.eq(session.result, { kind: "result", errors: 1, warnings: 2 }, "the result line")
        T.eq(session.items.map(item => item.level), ["warn", "error", "warn"], "the findings, empty ones left out")
        T.eq(session.items[1].action, "restartShell", "a known action")
        T.eq([session.items[2].command, session.items[2].action], ["", ""], "a command with a newline and an unknown action are dropped")
        T.eq(session.items[0].section, "Power and hardware", "with its section")

        const doctor = H.parseLines('{"level":"missing","id":"plocate","text":"plocate (sudo pacman -S plocate)","command":"sudo pacman -S plocate"}\n'
            + '{"level":"note","id":"thp","text":"transparent huge pages are \\"always\\"","command":"echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"}\n'
            + '{"kind":"result","status":0}', "doctor")
        T.eq(doctor.items.map(item => [item.level, item.section, item.id]), [["warn", "Packages", "doctor:plocate"], ["note", "Packages", "doctor:thp"]], "a miss is a warning, a note a note")
        T.eq(doctor.items.map(item => item.text), ["Plocate (sudo pacman -S plocate)", "Transparent huge pages are \"always\""],
             "each starts with a capital, as a sentence on the page")
        T.eq(doctor.items[0].command, "sudo pacman -S plocate", "the command as it was")
        const folders = H.parseLines('{"level":"note","id":"icon-cache","text":"/a/icons/hicolor has no cache","command":"x"}\n'
            + '{"level":"note","id":"icon-cache","text":"/a/icons/Papirus has no cache","command":"y"}', "doctor")
        T.eq(folders.items.map(item => item.id), ["doctor:icon-cache", "doctor:icon-cache#1"], "one check's two findings keep two rows")

        // The shell's own.
        const shell = H.shellItems({ reader: { available: true, fingers: 0, pamMissing: true, onCommand: "sudo sed x" },
                                     vpn: { count: 2, tile: false },
                                     apps: [{ id: "browser", label: "Web browser", current: "", currentName: "" },
                                            { id: "terminal", label: "Terminal", current: "kitty.desktop", currentName: "kitty" },
                                            { id: "files", label: "File manager", current: "gone.desktop", currentName: "" },
                                            { id: "video", label: "Video", current: "" }] })
        T.eq(shell.map(item => item.id), ["shell:finger", "shell:vpn", "shell:app:browser", "shell:app:files"], "reader, tile and default apps")
        T.eq(shell.map(item => item.action), ["enrollFinger", "vpnTile", "defaultApps", "defaultApps"], "each with its button")
        T.eq(shell[1].text, "2 VPN connections but no VPN tile in the control center", "the tile's words")
        T.eq(shell[2].text, "No default web browser - the keys that open one do nothing", "an app's words")
        const enrolled = H.shellItems({ reader: { available: true, fingers: 1, pamMissing: true, onCommand: "sudo sed x" }, vpn: { count: 1, tile: true }, apps: [] })
        T.eq(enrolled.map(item => [item.id, item.command, item.action]), [["shell:pam", "sudo sed x", "lockScreen"]], "a finger without the PAM line")
        T.eq(H.shellItems({ reader: { available: false, fingers: 0 }, vpn: { count: 0, tile: false }, apps: [] }), [], "nothing to say")
        T.eq(H.shellItems(null), [], "no state at all")

        // One list, the most urgent first, each text once.
        const merged = H.merge([session.items, doctor.items, shell, [session.items[0]]])
        T.eq(merged.map(item => item.level), ["error", "warn", "warn", "warn", "warn", "warn", "note", "note", "note"], "errors, warnings, notes")
        T.eq(merged.filter(item => item.text === session.items[0].text).length, 1, "a text once")
        T.eq(merged[1].text, session.items[0].text, "and in their order within a level")

        T.eq([H.summary([], false, true), H.summary([], false, false), H.summary([], true, false), H.summary([1], true, false), H.summary([1, 2], true, true)],
             ["Checking the session …", "Not checked yet", "Everything is set up", "1 thing to look at", "2 things to look at"], "the summary")
        T.eq([H.actionLabel("vpnTile"), H.actionLabel("nope")], ["Add tile", ""], "button words")
        T.eq([H.levelLabel("error"), H.levelLabel("warn"), H.levelLabel("note")], ["Error", "Warning", "Note"], "level words")
        T.eq([H.due(0, 1000), H.due(1000, 30000), H.due(1000, 70000)], [true, false, true], "at most once a minute")
        T.finish("HealthTest")
    }
}
