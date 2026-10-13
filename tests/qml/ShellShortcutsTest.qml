import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/shortcuts/ShellShortcuts.js" as S

ShellRoot {
    Component.onCompleted: {
        T.eq([S.nameOf("launcher toggle"), S.nameOf(" recording  toggle region "), S.nameOf("workspaces switchTo 3")],
             ["launcher.toggle", "recording.toggle.region", "workspaces.switchTo.3"], "an action as a shortcut name")
        T.eq(S.parse("workspaces.switchTo.3"), { target: "workspaces", fn: "switchTo", args: [3] }, "a number is an int argument")
        T.eq(S.parse("recording.toggle.region"), { target: "recording", fn: "toggle", args: ["region"] }, "a word stays a word")
        T.eq([S.parse("launcher"), S.parse("")], [null, null], "a name without a function is none")
        T.eq([S.onRelease("switcher.confirm"), S.onRelease("switcher.next")], [true, false], "only the confirm acts on release")
        T.eq(S.names().length, 42, "24 shell actions and 2 x 9 workspace keys")
        T.ok(S.names().indexOf("power.lidClosed") < 0, "the lid switches stay on exec")
        T.eq(S.names().filter((name, i, all) => all.indexOf(name) !== i), [], "no name twice")
        T.finish("ShellShortcutsTest")
    }
}
