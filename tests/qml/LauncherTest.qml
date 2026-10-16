import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/LaunchLogic.js" as Launch

// How the launcher starts an entry: always through scripts/launch-app.sh (a
// unit named after the entry, and the session's environment instead of the
// shell's own settings), the entry's working directory kept, overrides by
// their session launcher, and a Terminal=true entry in the session's
// terminal (scripts/launch-terminal.sh, which ends in launch-app.sh too).
ShellRoot {
    Component.onCompleted: {
        const script = name => "/s/" + name
        const overrides = { "kitty": "launch-kitty.sh", "brave-browser": "launch-brave.sh" }

        T.eq(Launch.launchContext({ id: "org.kde.dolphin", command: ["dolphin", "--new-window"], workingDirectory: "" }, overrides, script),
             { command: ["/s/launch-app.sh", "org.kde.dolphin", "dolphin", "--new-window"] },
             "an entry runs through launch-app.sh, named after its id")
        T.eq(Launch.launchContext({ id: "game", command: ["./run"], workingDirectory: "/opt/game" }, overrides, script),
             { command: ["/s/launch-app.sh", "game", "./run"], workingDirectory: "/opt/game" },
             "the entry's Path= goes along, as execute() passed it")
        T.eq(Launch.launchContext({ id: "htop", command: ["htop"], runInTerminal: true }, overrides, script),
             { command: ["/s/launch-terminal.sh", "--", "htop"] },
             "a Terminal=true entry runs in the session's terminal (execute() ran it with no terminal at all)")
        T.eq(Launch.launchContext({ id: "btop", command: ["btop", "--utf-force"], runInTerminal: true, workingDirectory: "/srv" }, overrides, script),
             { command: ["/s/launch-terminal.sh", "--", "btop", "--utf-force"], workingDirectory: "/srv" },
             "its arguments after --, never read as the terminal's options, and its Path= kept")
        T.eq(Launch.launchContext({ id: "htop", command: ["htop"], runInTerminal: false }, overrides, script).command,
             ["/s/launch-app.sh", "htop", "htop"], "Terminal=false: launch-app.sh as before")
        T.eq(Launch.launchContext({ id: "kitty", command: ["kitty"], runInTerminal: true }, overrides, script),
             { command: ["/s/launch-kitty.sh"] }, "an override wins over Terminal=true")
        T.eq(Launch.launchContext({ id: "kitty", command: ["kitty"] }, overrides, script),
             { command: ["/s/launch-kitty.sh"] }, "an override starts its session launcher")
        T.eq(Launch.launchContext({ id: "toString", command: ["x"] }, overrides, script).command[0], "/s/launch-app.sh",
             "an id that is a property of every object is no override")
        T.eq(Launch.launchContext({ id: "empty", command: [] }, overrides, script), null, "no command: nothing to run")
        T.eq(Launch.launchContext({ id: "", command: ["x"] }, overrides, script), null, "no id: launch-app.sh would refuse it")
        T.eq(Launch.launchContext(null, overrides, script), null, "no entry")
        // DesktopEntry.command is a list type, not a JS array.
        const listLike = { length: 2, 0: "code", 1: "--new-window" }
        T.eq(Launch.launchContext({ id: "code", command: listLike }, overrides, script).command,
             ["/s/launch-app.sh", "code", "code", "--new-window"], "a list-like command is copied")
        T.finish("LauncherTest")
    }
}
