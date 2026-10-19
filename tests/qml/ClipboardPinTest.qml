import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/clipboard/PinLogic.js" as Pin

// Pinned clipboard entries: the index as it is read back, what a pin and an
// unpin do to the list, and the commands - run against a stand-in cliphist in
// the runner's sandboxed state directory, never the real history. No service
// is started.
ShellRoot {
    id: root
    readonly property string state: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string base: state + "/clipboard-pin-test"
    readonly property string dir: base + "/clipboard-pins"
    readonly property string tool: base + "/cliphist"
    readonly property string sum: "5d41402abc4b2a76b9719d911017c592"
    property int step: 0

    Process {
        id: shell
        property string output: ""
        property int code: -1
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: exitCode => { shell.code = exitCode; next.start() }
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }

    function run(command) {
        shell.output = ""
        shell.code = -1
        shell.command = command
        shell.running = true
    }

    function pin(id, text, image, format) {
        // In the order sanitizePin writes them: the harness compares JSON.
        return { id: id, image: image === true, format: format || "", text: text }
    }

    Component.onCompleted: {
        const a = pin("0123456789abcdef0123456789abcdef", "IBAN DE00 1234")
        const b = pin("fedcba9876543210fedcba9876543210", "Image · 10x10 · 1 KiB", true, "png")

        // ---- the index ----------------------------------------------------------
        T.eq(Pin.parse(""), { pins: [], ok: true }, "no file yet: no pins")
        T.eq(Pin.parse("{"), { pins: [], ok: false }, "a file that is not JSON is kept, not replaced")
        T.eq(Pin.parse("[1, 2]").ok, false, "nor one without a list of pins")
        T.eq(Pin.parse(Pin.serialize([a, b])).pins, [a, b], "what is written reads back the same")
        T.eq(Pin.sanitize([a, a, { id: "../../etc", text: "x" }, { id: b.id, image: true, format: "svg" }, null, 7]), [a],
             "each id once; an id that is not 32 hex digits and a format cliphist does not list are dropped")
        T.eq(Pin.sanitize([pin(a.id, "line one\n\tline  two")])[0].text, "line one line two", "the preview is one line")
        T.eq(Pin.preview("x".repeat(400)).length, Pin.PREVIEW_MAX, "and no longer than the history's")
        T.eq(Pin.sanitizePin(pin(a.id, "t", false, "png")).format, "", "text has no picture format")

        // ---- pinning and unpinning ------------------------------------------------
        T.eq(Pin.withPin([b], a).map(item => item.id), [a.id, b.id], "a new pin goes first")
        T.eq(Pin.withPin([b, a], a).map(item => item.id), [a.id, b.id], "the same snippet again moves to the top, once")
        const many = Array.from({ length: Pin.LIMIT }, (unused, index) =>
            pin(("00000000000000000000000000000000" + index.toString(16)).slice(-32), "n" + index))
        T.eq(Pin.full(many), true, "fifty pins are all there may be")
        T.eq(Pin.withPin(many, a), null, "and one more is refused")
        T.eq(Pin.withPin(many, many[7])[0].id, many[7].id, "but one of them still moves to the top")
        T.eq(Pin.withPin([], { id: "nope" }), null, "nothing that is not a pin")
        T.eq(Pin.without([a, b], a.id), [b], "unpinned")
        T.eq(Pin.matching([a, b], "iban"), [a], "the search finds pins by their text")
        T.eq(Pin.matching([a, b], "  "), [a, b], "an empty query is every pin")
        T.eq(Pin.present([a, b], [Pin.fileName(b), "other.txt"]), [b], "a pin whose file went is no pin")
        T.eq([Pin.fileName(a), Pin.fileName(b)], [a.id + ".txt", b.id + ".png"], "text and pictures by their kind")
        T.eq([Pin.pinnedId(root.sum + "\n"), Pin.pinnedId(""), Pin.pinnedId("nope")], [root.sum, "", ""],
             "the id a pin run printed")
        T.eq(Pin.copyCommand("/d", b).slice(-2), ["--type", "image/png"], "a picture goes back under its type")
        T.eq(Pin.copyCommand("/d", a).slice(-1), ["/d/" + a.id + ".txt"], "text as it is")
        T.eq(Pin.removeCommand("/d", a), ["rm", "-f", "--", "/d/" + a.id + ".txt"], "an unpin removes the file")
        advance()
    }

    function advance() {
        step += 1
        if (step === 1) {
            // A cliphist stand-in that decodes entry 7 to "hello" and fails
            // for everything else, the way a stale id fails.
            run(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' '#!/bin/sh' '[ \"$3\" = decode ] && [ \"$4\" = 7 ] && printf hello && exit 0' 'exit 1' > \"$2\" && chmod 700 \"$2\"",
                 "sh", base, tool])
        } else if (step === 2) {
            run(Pin.pinCommand(dir, base + "/db", "7", "txt", tool))
        } else if (step === 3) {
            T.eq([shell.code, Pin.pinnedId(shell.output)], [0, root.sum], "the pin run prints the content's md5")
            run(["stat", "-c", "%a %n", dir, dir + "/" + root.sum + ".txt"])
        } else if (step === 4) {
            T.eq(shell.output.trim().split("\n").map(line => line.split(" ")[0]), ["700", "600"],
                 "the pins' directory and the pin are the user's alone")
            run(["cat", dir + "/" + root.sum + ".txt"])
        } else if (step === 5) {
            T.eq(shell.output, "hello", "the whole content, not the preview")
            run(Pin.pinCommand(dir, base + "/db", "8", "txt", tool))
        } else if (step === 6) {
            T.eq([shell.code === 0, Pin.pinnedId(shell.output)], [false, ""], "an entry that does not decode is no pin")
            run(["sh", "-c", "ls -A \"$1\"", "sh", dir])
        } else if (step === 7) {
            T.eq(shell.output.trim(), root.sum + ".txt", "and leaves no temporary file behind")
            // An orphan, a run's leftover, and the pin opened up by hand.
            run(["sh", "-c", ": > \"$1/orphan.png\"; : > \"$1/.pin-123\"; chmod 644 \"$1/$2.txt\"", "sh", dir, root.sum])
        } else if (step === 8) {
            run(Pin.settleCommand(dir, [pin(root.sum, "hello")]))
        } else if (step === 9) {
            T.eq(shell.output.trim().split("\n"), [root.sum + ".txt"], "the settle run lists the pins that are there")
            run(["sh", "-c", "ls -A \"$1\"; stat -c %a \"$1/$2.txt\"", "sh", dir, root.sum])
        } else if (step === 10) {
            T.eq(shell.output.trim().split("\n"), [root.sum + ".txt", "600"], "and removes what is no pin's, and puts the mode right")
            run(Pin.settleCommand(base + "/missing", []))
        } else if (step === 11) {
            T.eq([shell.code, shell.output], [0, ""], "no directory yet: nothing to settle")
            run(["sh", "-c", "rm -rf -- \"$1\"", "sh", base])
        } else {
            T.finish("ClipboardPinTest")
        }
    }
}
