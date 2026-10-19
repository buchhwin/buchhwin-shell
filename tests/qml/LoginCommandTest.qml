import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/settings/LoginLogic.js" as L

// The commands Settings > Login screen hands out to be pasted into a
// terminal. Each one is parsed by sh, bash and zsh (where installed) with a
// stand-in sudo that prints the words it was given, so what is checked is
// what a shell makes of the line, not how it looks. The names carry only
// `echo INJECTED` as their payload: a quote that broke would print it, and
// nothing else could run.
ShellRoot {
    id: root
    readonly property string script: "/opt/sample shell/install/system-install.sh"
    readonly property string plainScript: "/home/sample/.local/share/buchhwin-shell-stable/install/system-install.sh"
    readonly property var cases: [
        { name: "an ordinary name", script: root.plainScript, wallpaper: "/home/sample/Pictures/beach.jpg" },
        { name: "an apostrophe", script: root.plainScript, wallpaper: "/home/sample/Pictures/Tom's beach.jpg" },
        { name: "a name that closes the quote and adds commands", script: root.plainScript,
          wallpaper: "/home/sample/Pictures/a' ; echo INJECTED ; sudo echo INJECTED ; : '.jpg" },
        { name: "a command substitution", script: root.plainScript, wallpaper: "/home/sample/Pictures/x'$(echo INJECTED)'.jpg" },
        { name: "$, backquotes, a backslash and !", script: root.plainScript,
          wallpaper: "/home/sample/P/$HOME `echo INJECTED` \\ !! ~x.jpg" },
        { name: "a newline", script: root.plainScript, wallpaper: "/home/sample/P/a\necho INJECTED\nb.jpg" },
        { name: "no wallpaper", script: root.plainScript, wallpaper: "" },
        { name: "a script path with a space and a quote", script: "/opt/sample's shell/install/system-install.sh",
          wallpaper: "/home/sample/Pictures/beach.jpg" }
    ]
    readonly property var lines: cases.map(entry => L.installCommand(entry.script, entry.wallpaper))
        .concat([L.removeCommand(root.script)])
    // What the stand-in sudo prints for one line: the number of words, then
    // each word in brackets.
    function expected(words) {
        return words.length + "\n" + words.map(word => "[" + word + "]").join("\n") + "\n"
    }
    readonly property var wanted: cases.map(entry => root.expected([entry.script, "--sddm-theme"]
            .concat(entry.wallpaper.length ? ["--wallpaper", entry.wallpaper] : [])))
        .concat([root.expected([root.script, "--sddm-theme-remove"])])

    Process {
        id: parse
        command: ["sh", "-c",
            'stub=\'sudo() { printf "%s\\n" "$#"; for word in "$@"; do printf "[%s]\\n" "$word"; done; }\'\n'
            + 'for shell in sh bash zsh; do\n'
            + '  command -v "$shell" >/dev/null 2>&1 || continue\n'
            + '  case $shell in zsh) opt=-f ;; bash) opt=--norc ;; *) opt=-e ;; esac\n'
            + '  for line in "$@"; do\n'
            + '    printf "== %s\\n" "$shell"\n'
            + '    "$shell" "$opt" -c "$stub"\'\n eval "$1"\' parse "$line" 2>&1\n'
            + '  done\n'
            + 'done\n', "parse"].concat(root.lines)
        stdout: StdioCollector {
            onStreamFinished: {
                const blocks = text.split(/^== /m).filter(block => block.length)
                const shells = {}
                blocks.forEach(block => {
                    const newline = block.indexOf("\n")
                    const shell = block.slice(0, newline)
                    const body = block.slice(newline + 1)
                    const index = (shells[shell] = (shells[shell] === undefined ? 0 : shells[shell] + 1))
                    const label = index < root.cases.length ? root.cases[index].name : "the undo command"
                    // Exactly the words, and nothing printed besides them: a
                    // payload that ran would add a line of its own.
                    T.eq(body, root.wanted[index], shell + " reads " + label + " as the words it names")
                })
                T.ok(shells.sh === root.lines.length - 1 && shells.bash === root.lines.length - 1,
                     "sh and bash parsed every line")
                T.finish("LoginCommandTest")
            }
        }
    }

    Component.onCompleted: {
        // The text itself: an ordinary name reads as it always did, apart
        // from the installer's absolute path.
        T.eq(L.installCommand(root.plainScript, "/home/sample/Pictures/beach.jpg"),
             "sudo " + root.plainScript + " --sddm-theme --wallpaper '/home/sample/Pictures/beach.jpg'",
             "an ordinary name keeps its quotes and the script goes bare")
        T.eq(L.installCommand(root.plainScript, ""), "sudo " + root.plainScript + " --sddm-theme",
             "no wallpaper, no option")
        T.eq(L.installCommand(root.plainScript, "/p/Tom's.jpg"),
             "sudo " + root.plainScript + " --sddm-theme --wallpaper '/p/Tom'\\''s.jpg'", "a quote is closed, escaped and opened")
        T.eq(L.removeCommand(root.plainScript), "sudo " + root.plainScript + " --sddm-theme-remove", "the way back")
        T.ok(L.installCommand(root.plainScript, "").indexOf("sudo /") === 0, "the installer goes by an absolute path")
        T.eq(L.shellWord("/a b/c"), "'/a b/c'", "a space is quoted")
        T.eq(L.shellWord("=ls"), "'=ls'", "a leading = is quoted (zsh looks it up as a command)")
        T.eq(L.shellWord("a=b"), "a=b", "an = inside a word is not")
        T.eq(L.shellWord(""), "''", "an empty word is still a word")
        parse.running = true
    }
}
