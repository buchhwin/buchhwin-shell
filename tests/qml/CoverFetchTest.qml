import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/media/MediaLogic.js" as M

// The cover fetch (MediaLogic.coverCommand) run for real against a stand-in
// curl in the runner's sandboxed cache: what it writes is the user's alone,
// curl follows three redirects at most, and after a fetch the cache keeps
// only its newest 200 covers and 100 MB - the new one always among them. A
// failed fetch leaves no part file. No network is used.
ShellRoot {
    id: root
    readonly property string cache: Quickshell.env("XDG_CACHE_HOME") || ""
    readonly property string base: cache + "/cover-fetch-test"
    readonly property string dir: base + "/covers"
    readonly property string stubs: base + "/bin"
    property int step: 0

    Process {
        id: shell
        property string output: ""
        property int code: -1
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: code => { shell.code = code; next.start() }
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }

    function run(command) {
        shell.output = ""
        shell.code = -1
        shell.command = command
        shell.running = true
    }
    // The cover command with the stand-in curl first on PATH.
    function fetch(name, sweep) {
        run(["sh", "-c", "PATH=\"$0:$PATH\"; export PATH; exec \"$@\"", stubs]
            .concat(M.coverCommand(dir, dir + "/" + name, "https://covers.example.invalid/" + name, sweep)))
    }

    Component.onCompleted: {
        const argv = M.coverCommand("/c", "/c/a.img", "https://e.example.invalid/a", true)
        T.eq(argv.slice(0, 2), ["sh", "-c"], "through a shell")
        T.ok(argv[2].indexOf("umask 077;") === 0, "the script starts with umask 077")
        T.ok(argv[2].indexOf("--max-redirs 3") > 0, "curl follows three redirects at most")
        T.ok(argv[2].indexOf('chmod 700 -- "$1"') > 0, "the first fetch of a session makes the directory private")
        T.ok(M.coverCommand("/c", "/c/a.img", "u", false)[2].indexOf("chmod 700") < 0, "later fetches leave it be")
        T.eq(argv.slice(3), ["sh", "/c", "/c/a.img", "https://e.example.invalid/a"], "paths and url are arguments")
        T.eq([M.COVER_FILES, M.COVER_BYTES], [200, 104857600], "the cache's limits")
        advance()
    }

    function advance() {
        step += 1
        if (step === 1) {
            // 205 covers from the last hour (the 30-day sweep keeps them),
            // oldest first by mtime, in an open directory; a curl that writes
            // what it is asked to.
            run(["sh", "-c",
                 "rm -rf \"$1\" && mkdir -p \"$2\" \"$3\" && chmod 755 \"$2\" && now=$(date +%s) && i=0; while [ $i -lt 205 ]; do "
                 + "f=$(printf '%s/old%03d.img' \"$2\" $i); printf x > \"$f\"; touch -d @$((now - 3600 + i)) \"$f\"; i=$((i+1)); done; "
                 + "printf '#!/bin/sh\\nout=\"\"\\nwhile [ $# -gt 0 ]; do [ \"$1\" = -o ] && out=$2; shift; done\\n"
                 + "case \"$out\" in *fail*) exit 22;; esac\\nprintf cover > \"$out\"\\n' > \"$3/curl\" && chmod +x \"$3/curl\"",
                 "sh", base, dir, stubs])
        } else if (step === 2) {
            fetch("new.img", true)
        } else if (step === 3) {
            T.eq(shell.code, 0, "the fetch succeeds")
            run(["sh", "-c", "cd \"$1\" && ls | wc -l; [ -s new.img ] && echo new; [ -e old000.img ] || echo oldest-gone; "
                 + "[ -e old005.img ] || echo sixth-gone; [ -e old006.img ] && echo seventh-kept; stat -c %a . new.img; ls *.part 2>/dev/null | wc -l",
                 "sh", dir])
        } else if (step === 4) {
            T.eq(shell.output.trim().split("\n"), ["200", "new", "oldest-gone", "sixth-gone", "seventh-kept", "700", "600", "0"],
                 "200 covers stay: the new one and the 199 newest from before; the directory 0700, the cover 0600, no part file")
            // Size: three sparse covers of 40 MB each (newest last) - only the
            // newest two fit in 100 MB, whatever the count.
            run(["sh", "-c", "cd \"$1\" && rm -f -- *.img && now=$(date +%s) && for n in 1 2 3; do truncate -s 40M big$n.img; touch -d @$((now - 600 + n)) big$n.img; done",
                 "sh", dir])
        } else if (step === 5) {
            fetch("small.img", false)
        } else if (step === 6) {
            T.eq(shell.code, 0, "a fetch with big covers in the cache succeeds")
            run(["sh", "-c", "cd \"$1\" && ls | sort | tr '\\n' ' '", "sh", dir])
        } else if (step === 7) {
            T.eq(shell.output.trim(), "big2.img big3.img small.img", "the oldest big cover went to stay within 100 MB")
            fetch("fail.img", false)
        } else if (step === 8) {
            T.eq(shell.code, 1, "a failed fetch fails")
            run(["sh", "-c", "cd \"$1\" && ls | sort | tr '\\n' ' '", "sh", dir])
        } else if (step === 9) {
            T.eq(shell.output.trim(), "big2.img big3.img small.img", "and leaves no part file and touches nothing")
            // A cover that is there already is not fetched again (the stub
            // would fail on this name).
            run(["sh", "-c", "printf cached > \"$1/fail.img\"", "sh", dir])
        } else if (step === 10) {
            fetch("fail.img", false)
        } else if (step === 11) {
            T.eq(shell.code, 0, "a cover in the cache is not fetched again")
            run(["rm", "-rf", "--", base])
        } else {
            T.finish("CoverFetchTest")
        }
    }
}
