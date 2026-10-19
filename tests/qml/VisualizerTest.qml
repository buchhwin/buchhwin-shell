import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/media/VisualizerLogic.js" as V

// The media popup's visualizer: when cava runs and when the bars show, its
// configuration, a frame as cava prints it, and the run itself - against a
// stand-in cava in the runner's sandbox that prints what it was handed (the
// stream's name, the configuration and its file's mode), and against none.
ShellRoot {
    id: root
    readonly property string state: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string base: state + "/visualizer-test"
    property int step: 0

    Process {
        id: shell
        property string output: ""
        property int code: -1
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: exitCode => { shell.code = exitCode; next.start() }
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }
    function run(command, path) {
        shell.output = ""
        shell.code = -1
        shell.environment = path ? { PATH: path } : {}
        shell.command = command
        shell.running = true
    }

    Component.onCompleted: {
        T.eq(V.wanted(1, true, false), true, "the popup shows the bars and something plays")
        T.eq([V.wanted(0, true, false), V.wanted(1, false, false), V.wanted(1, true, true)], [false, false, false],
             "not while the popup is closed, nothing plays, or cava is missing")
        T.eq(V.shown(true, true, true), true, "the switch, full motion and a player")
        T.eq([V.shown(false, true, true), V.shown(true, false, true), V.shown(true, true, false), V.shown(undefined, true, true)],
             [false, false, false, false], "off by default, never with reduced motion")

        const frame = V.parseFrame("0;50;100;120;-3;x;", 8)
        T.eq(frame, [0, 0.5, 1, 1, 0, 0, 0, 0], "a frame: 0 to 1, clamped, missing bars at 0")
        T.eq(V.parseFrame("", 3), [0, 0, 0], "an empty line is silence")
        T.eq(V.parseFrame("10;20", 0).length, V.BARS, "the default count")

        const config = V.config(16, 30)
        T.ok(config.indexOf("bars = 16") >= 0 && config.indexOf("method = raw") >= 0 && config.indexOf("data_format = ascii") >= 0
             && config.indexOf("channels = mono") >= 0 && config.indexOf("method = pipewire") >= 0,
             "raw ASCII frames of one row of bars from PipeWire")
        T.ok(V.streamProps().indexOf("node.name = \"" + V.NODE_NAME + "\"") >= 0, "the stream carries the name AudioService leaves out")
        advance()
    }

    function advance() {
        step += 1
        if (step === 1) {
            // A cava that prints what it was given: its stream's properties,
            // the mode of its configuration file and the file itself.
            run(["sh", "-c", "mkdir -p \"$1/bin\" && printf '%s\\n' '#!/bin/sh' 'printf \"%s\\n\" \"$PIPEWIRE_PROPS\"; stat -c %a \"$2\"; cat \"$2\"' > \"$1/bin/cava\" && chmod 700 \"$1/bin/cava\"",
                 "sh", base])
        } else if (step === 2) {
            run(V.command(base + "/run/visualizer.conf", V.config(4, 30)), base + "/bin:/usr/bin:/bin")
        } else if (step === 3) {
            const lines = shell.output.split("\n")
            T.eq(shell.code, 0, "the stand-in ran")
            T.eq(lines[0], V.streamProps(), "with the stream's name in its environment")
            T.eq(lines[1], "600", "its configuration is the user's alone")
            T.ok(lines.indexOf("bars = 4") >= 0, "and is the one asked for")
            // No cava on the path at all: only what the command needs besides.
            run(["sh", "-c", "mkdir -p \"$1/tools\" && ln -sf \"$(command -v mkdir)\" \"$1/tools/mkdir\"", "sh", base])
        } else if (step === 4) {
            run(V.command(base + "/run/visualizer.conf", V.config(4, 30)), base + "/tools")
        } else if (step === 5) {
            T.eq(shell.code, 127, "without cava the run says so the way a shell does")
            run(["sh", "-c", "rm -rf -- \"$1\"", "sh", base])
        } else {
            T.finish("VisualizerTest")
        }
    }
}
