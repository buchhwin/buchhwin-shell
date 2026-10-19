import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/widgets/CommandLogic.js" as C

// The command widgets: which of the three a widget is, the settings as one
// definition, what a run's output shows, and the run itself - a real `bash`
// with the repository's app-env.sh, so the command gets the session's
// environment back and not the shell's own settings, and a failing command
// is told apart, and one that prints without end is cut off. No service is
// started.
ShellRoot {
    id: root
    property int step: 0

    Process {
        id: shell
        property string output: ""
        property int code: -1
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: exitCode => { shell.code = exitCode; next.start() }
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }
    function run(command, environment) {
        shell.output = ""
        shell.code = -1
        shell.environment = environment || {}
        shell.command = command
        shell.running = true
    }

    Component.onCompleted: {
        T.eq([C.slotOf("command1"), C.slotOf("command3"), C.slotOf("clock"), C.slotOf("command1", { slot: "two" })],
             ["one", "three", "", "two"], "a widget's slot: from its options, else from its type")
        T.eq(C.slotOf("command2", { slot: "nonsense" }), "two", "an option that names no slot is no slot")
        T.eq([C.typeOf("one"), C.typeOf("three"), C.typeOf("four")], ["command1", "command3", ""], "and back")

        T.eq([C.interval(60), C.interval(7), C.interval(100000), C.interval("x"), C.interval(-5)], [60, 5, 3600, 60, 60],
             "the nearest interval offered, the default for nonsense")
        T.eq([C.timeoutFor(5), C.timeoutFor(60), C.timeoutFor(3600)], [4, 30, 30],
             "a run ends before the next one is due, after half a minute at most")

        T.eq(C.commandError("nmcli -t -f NAME connection show --active"), "", "a command")
        T.eq(C.commandError("a; b && c | d"), "", "a shell line with ; is fine here: it runs as a shell line")
        T.eq([C.commandError("a\nb"), C.commandError("x".repeat(1001))], ["Commands must be on one line", "The command is too long"],
             "one line, not too long")
        T.eq([C.glyph(""), C.glyph("\u{f0582}"), C.glyph("not a glyph")], [C.DEFAULT_ICON, "\u{f0582}", C.DEFAULT_ICON],
             "a glyph or the console")

        const settings = { label: " VPN ", icon: "", command: " wg show ", interval: 17, click: "nm-connection-editor" }
        T.eq(C.definition(leaf => settings[leaf]),
             { label: "VPN", icon: C.DEFAULT_ICON, command: "wg show", click: "nm-connection-editor", interval: 10 },
             "the settings as one tidy definition")
        T.eq(C.definition(leaf => undefined),
             { label: "", icon: C.DEFAULT_ICON, command: "", click: "", interval: C.DEFAULT_INTERVAL },
             "nothing set: a widget that says so")
        T.eq(C.definition(leaf => leaf === "command" ? "a\nb" : "").command, "", "a command that is no line is not run")

        T.eq(C.parseOutput("\n  up 3 h \nwg0\nrest\n"), { line: "up 3 h", detail: "wg0" }, "the first line, the second as detail")
        T.eq(C.parseOutput("\x1b[32mgreen\x1b[0m\tok"), { line: "green ok", detail: "" }, "colours and tabs taken out")
        T.eq(C.parseOutput(""), { line: "", detail: "" }, "no output")
        T.eq(C.parseOutput("y".repeat(300)).line.length, C.LINE_MAX, "a line is cut")
        T.eq([C.failed(0), C.failed(1), C.failed(124)], [false, true, true], "a failure or a timeout")
        T.eq([C.failureText({ failed: true, exitCode: 2 }), C.failureText({ failed: true }), C.failureText({ failed: false, exitCode: 0 }),
              C.failureText(null)], ["Failed (exit 2)", "Failed", "", ""], "a failure in words, with its exit status")

        const click = C.clickCommand("nm-connection-editor", "/x/launch-app.sh")
        T.eq(click, ["/x/launch-app.sh", "buchhwin-shell-command", "sh", "-c", "nm-connection-editor"],
             "a click starts like an app, in a scope of its own")
        advance()
    }

    function advance() {
        step += 1
        const appEnv = Quickshell.shellPath("scripts/lib/app-env.sh")
        if (step === 1) {
            // The shell's own allocator setting, recorded as start-shell.sh
            // records it: the command must not see it.
            run(C.runCommand("echo \"${MALLOC_CONF-none}\"; echo second; exit 3", 60, appEnv),
                { BUCHHWIN_APP_ENV_UNSET: "MALLOC_CONF", MALLOC_CONF: "narenas:2" })
        } else if (step === 2) {
            T.eq(C.parseOutput(shell.output), { line: "none", detail: "second" }, "the command runs with the session's environment")
            T.eq(C.failed(shell.code), true, "and its exit status is kept")
            run(C.runCommand("echo fine 1>&2; echo out", 5, "/nonexistent/app-env.sh"))
        } else if (step === 3) {
            T.eq([shell.code, shell.output.trim()], [0, "out"], "without app-env.sh it runs as it is, its stderr dropped")
            // The positional parameters are the command's own again (none),
            // not what the run handed over.
            run(C.runCommand("echo \"[$#${1-}]\"; yes", 5, appEnv))
        } else if (step === 4) {
            T.eq([shell.output.length, shell.output.split("\n")[0], C.failed(shell.code)], [C.OUTPUT_MAX, "[0]", true],
                 "a command that prints without end is cut off, and counts as failed")
            T.finish("CommandWidgetTest")
        }
    }
}
