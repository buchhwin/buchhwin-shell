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
        T.eq([S.runsOn("launcher.toggle", true), S.runsOn("launcher.toggle", false),
              S.runsOn("switcher.confirm", true), S.runsOn("switcher.confirm", false)],
             [true, false, false, true], "a key acts on press, the confirm on release")
        T.eq(S.names().length, 54, "29 shell actions, 2 x 9 workspace keys and 7 swipes")
        // The start menu's key (Super+Space) acts only with the taskbar's
        // start button; that action is the one Settings > Shortcuts offers for
        // a key of one's own, not IPC's toggle, which works without a dock.
        T.ok(S.names().indexOf("startMenu.key") >= 0 && S.names().indexOf("startMenu.toggle") >= 0, "the start menu's key and IPC's toggle")
        T.eq([S.bindable("startMenu key"), S.bindable("startMenu toggle"), S.bindable("launcher toggle"), S.bindable("")],
             [true, false, false, false], "only the start menu's key is offered for one")
        T.eq(S.shortcutName("startMenu toggle"), "buchhwin:startMenu.toggle", "the global shortcut a bind sends")
        T.ok(S.names().indexOf("brightness.up") >= 0 && S.names().indexOf("brightness.down") >= 0, "the brightness keys")
        T.ok(S.names().indexOf("gestures.run.closePanel") >= 0, "the swipes")
        T.ok(S.names().indexOf("power.lidClosed") < 0, "the lid switches stay on exec")
        T.eq(S.names().filter((name, i, all) => all.indexOf(name) !== i), [], "no name twice")
        T.finish("ShellShortcutsTest")
    }
}
