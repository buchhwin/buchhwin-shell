import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// ClipboardService's previews against the runner's sandboxed cache: a read of
// the list keeps the marks and files its entries need and lets the rest go.
// The first read looks into the directory (files from before the session),
// later ones delete only what the marks name; a directory or a file beside
// the preview directory is never touched, and an empty read prunes nothing.
// The recorders are switched off before the service is first touched, so no
// wl-paste starts.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property string dir: ""
    readonly property string listing: "1\t[[ binary data 1 KiB png 10x10 ]]\n2\thello\n3\t[[ binary data 2 KiB png 20x20 ]]\n"

    Process {
        id: shell
        property string output: ""
        stdout: StdioCollector { onStreamFinished: shell.output = text }
    }
    function run(script) {
        shell.output = ""
        shell.command = ["sh", "-c", script, "sh", root.dir, Paths.cacheDir]
        shell.running = true
    }

    Timer {
        id: settled
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!SettingsService.loaded && root.waits < 250) return
            stop()
            SettingsService.set("clipboard.history", false)
            files.start()
        }
    }

    Timer {
        id: files
        interval: 50
        onTriggered: {
            T.eq(ClipboardService.enabled, false, "the recorders are off in the test")
            root.dir = ClipboardService.thumbDir
            T.ok(root.dir.indexOf(Paths.cacheDir + "/") === 0, "previews live in the shell's cache directory (" + root.dir + ")")
            root.run('mkdir -p "$1/kept-dir" && cd "$1" && touch 1-10x10-1KiB.png 3-20x20-2KiB.png 5-30x30-3KiB.png && touch "$2/beside.png"')
            first.start()
        }
    }

    Timer {
        id: first
        interval: 100
        onTriggered: {
            const list = ClipboardService.parse(root.listing)
            T.eq(list.filter(entry => entry.image).map(entry => entry.thumb), ["1-10x10-1KiB.png", "3-20x20-2KiB.png"],
                 "the list names its previews")
            ClipboardService.readyThumbs = { "1-10x10-1KiB.png": true, "9-40x40-4KiB.png": true }
            ClipboardService.pruneThumbnails(list)
            T.eq(ClipboardService.readyThumbs, { "1-10x10-1KiB.png": true }, "a mark whose entry is gone goes")
            root.tries = 0
            swept.start()
        }
    }

    Timer {
        id: swept
        interval: 50
        repeat: true
        onTriggered: {
            if (shell.running) return
            if (root.tries > 0 && shell.output.indexOf("5-30x30-3KiB.png") < 0) {
                stop()
                T.eq(shell.output.trim().split("\n"), ["1-10x10-1KiB.png", "3-20x20-2KiB.png", "kept-dir", "beside"],
                     "the first read deletes a file from before the session that no entry names, and only that")
                ClipboardService.readyThumbs = { "1-10x10-1KiB.png": true, "3-20x20-2KiB.png": true }
                ClipboardService.pruneThumbnails(ClipboardService.parse(root.listing.split("\n").slice(0, 2).join("\n")))
                T.eq(ClipboardService.readyThumbs, { "1-10x10-1KiB.png": true }, "a later read drops the mark of an entry cliphist dropped")
                ClipboardService.pruneThumbnails([])
                T.eq(ClipboardService.readyThumbs, { "1-10x10-1KiB.png": true }, "an empty read prunes nothing")
                root.tries = 0
                dropped.start()
                return
            }
            root.tries += 1
            if (root.tries > 60) {
                stop()
                T.ok(false, "the sweep did not finish: " + shell.output)
                T.finish("ClipboardPrune")
                return
            }
            root.run('ls -1 "$1"; [ -e "$2/beside.png" ] && echo beside')
        }
    }

    Timer {
        id: dropped
        interval: 50
        repeat: true
        onTriggered: {
            if (shell.running) return
            if (root.tries > 0 && shell.output.indexOf("3-20x20-2KiB.png") < 0) {
                stop()
                T.eq(shell.output.trim().split("\n"), ["1-10x10-1KiB.png", "kept-dir", "beside"],
                     "and deletes that entry's file, nothing else")
                T.finish("ClipboardPrune")
                return
            }
            root.tries += 1
            if (root.tries > 60) {
                stop()
                T.ok(false, "the dropped preview was not deleted: " + shell.output)
                T.finish("ClipboardPrune")
                return
            }
            root.run('ls -1 "$1"; [ -e "$2/beside.png" ] && echo beside')
        }
    }
}
