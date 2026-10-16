import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/clipboard/ClipboardLogic.js" as Logic

// The clipboard history's files are the user's alone: what the recorders
// create comes out 0600 (umask 077, inherited by cliphist), a database from
// before is set to 0600 as they start, and the previews' directory is 0700 -
// the one from before too, with the pictures already decoded into it, as the
// recorders start (they stayed 0755/0644 until a panel decoded a new one).
// Run against files in the runner's sandboxed cache, never the real one; no
// service is started (the recorder is a stand-in shell).
ShellRoot {
    id: root
    readonly property string cache: Quickshell.env("XDG_CACHE_HOME") || ""
    readonly property string dir: cache + "/clipboard-privacy"
    readonly property string db: dir + "/cliphist.db"
    readonly property string previews: dir + "/clipboard-previews"
    property int step: 0

    Process {
        id: shell
        property string output: ""
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: next.start()
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }

    function run(command) {
        shell.output = ""
        shell.command = command
        shell.running = true
    }

    function advance() {
        step += 1
        if (step === 1) {
            // What was there before: the modes the defaults used to give, and
            // a picture decoded into the previews before they were private.
            run(["sh", "-c", "mkdir -p \"$1\" \"$3\" && chmod 755 \"$1\" \"$3\" && : > \"$2\" && chmod 644 \"$2\" && : > \"$3/7-1x1-1KiB.png\" && chmod 644 \"$3/7-1x1-1KiB.png\"",
                 "sh", dir, db, previews])
        } else if (step === 2) {
            // The recorder stand-in reports its umask and creates a file the
            // way cliphist creates its database.
            const command = ["sh", "-c", "umask; : >> \"$0\"", dir + "/created.db"]
            const wrapped = Logic.privately(db, command, previews)
            T.eq(wrapped.slice(wrapped.length - command.length), command, "the recorder's own argv comes last, unchanged")
            T.eq(wrapped[0], "sh", "through a shell")
            run(wrapped)
        } else if (step === 3) {
            T.eq(shell.output.trim(), "0077", "the recorder runs under umask 077")
            run(["stat", "-c", "%a %n", db, dir + "/created.db", previews, previews + "/7-1x1-1KiB.png"])
        } else if (step === 4) {
            const modes = shell.output.trim().split("\n").map(line => line.split(" ")[0])
            T.eq(modes, ["600", "600", "700", "600"],
                 "as the recorders start: database from before, new database, previews directory, a preview from before")
            // The panel's own run still makes a directory it finds open 0700.
            run(["chmod", "755", previews])
        } else if (step === 5) {
            run(Logic.previewsCommand(previews, db, []))
        } else if (step === 6) {
            run(["stat", "-c", "%a", previews])
        } else if (step === 7) {
            T.eq(shell.output.trim(), "700", "the previews directory after a decode run")
            // The wipe's form names no directory, and a directory that is not
            // there is not made: the command runs either way.
            run(["sh", "-c", "chmod 755 \"$1\"", "sh", previews])
        } else if (step === 8) {
            run(Logic.privately(db, ["sh", "-c", "echo ran"], dir + "/missing"))
        } else if (step === 9) {
            T.eq(shell.output.trim(), "ran", "a missing previews directory does not stop the recorder")
            run(Logic.privately(db, ["sh", "-c", "stat -c %a \"$0\"; [ -e \"$1\" ] && echo made || echo absent", previews, dir + "/missing"]))
        } else if (step === 10) {
            T.eq(shell.output.trim().split("\n"), ["755", "absent"],
                 "without a previews directory the wrapper leaves directories alone, and makes none")
            run(["sh", "-c", "rm -rf -- \"$1\"", "sh", dir])
        } else {
            T.finish("ClipboardPrivacyTest")
        }
    }

    Component.onCompleted: {
        // A sandbox cache only: the runner sets one under its own temporary
        // directory, and without it nothing here may run.
        if (cache.indexOf("buchhwin-qmltest") < 0) {
            T.ok(false, "XDG_CACHE_HOME is not the test runner's sandbox (" + cache + ")")
            T.finish("ClipboardPrivacyTest")
            return
        }
        T.eq(Logic.previewsCommand("/d", "/db", [["7", "7-1x1-1KiB.png"]]).slice(-4), ["/d", "/db", "7", "7-1x1-1KiB.png"],
             "previews: directory, database, then id and file name pairs")
        advance()
    }
}
