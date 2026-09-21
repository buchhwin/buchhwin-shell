import Quickshell
import QtQuick
import qs.shell.components
import "Harness.js" as T

// A button that destroys something asks once. The first click arms it and says
// so, the second does it, and it goes back to what it was if nothing follows
// or if it is taken off screen.
ShellRoot {
    id: root
    property int fired: 0
    property int plainFired: 0

    Item {
        width: 400
        height: 200
        ShellButton {
            id: destructive
            icon: "x"
            text: "Forget network"
            variant: "ghost"
            confirm: true
            confirmText: "Forget"
            onClicked: root.fired += 1
        }
        ShellButton {
            id: plain
            icon: "x"
            text: "Connect"
            onClicked: root.plainFired += 1
        }
        ShellButton {
            id: iconOnly
            icon: "x"
            confirm: true
            confirmText: "Remove"
            onClicked: root.fired += 1
        }
    }

    Component.onCompleted: {
        // A button that destroys nothing fires on the first click, as always.
        plain.clicked()
        T.eq(root.plainFired, 1, "an ordinary button still fires at once")

        T.eq([destructive.armed, destructive.shownText, destructive.shownVariant],
             [false, "Forget network", "ghost"], "it starts as itself")

        // The signal is what the call site listens to, so the arming has to
        // happen before it - which means driving the press, not the signal.
        destructive.activate()
        T.eq(root.fired, 0, "the first click destroys nothing")
        T.eq([destructive.armed, destructive.shownText, destructive.shownVariant],
             [true, "Forget", "danger"], "it says what the next click will do")
        destructive.activate()
        T.eq(root.fired, 1, "the second click does it")
        T.eq(destructive.armed, false, "and it goes back to itself")

        // An icon on its own grows into the words: there must be no doubt
        // about what the next click does.
        T.eq(iconOnly.shownText, "", "an icon-only button carries no words")
        iconOnly.activate()
        T.eq(iconOnly.shownText, "Remove", "until it is armed")
        T.ok(iconOnly.implicitWidth > iconOnly.implicitHeight, "and it makes room for them")

        // Left alone it disarms, so nobody finds one armed from an earlier
        // visit and destroys something with what they think is a first click.
        destructive.activate()
        T.eq(destructive.armed, true, "armed again")
        destructive.visible = false
        T.eq(destructive.armed, false, "taken off screen, it disarms")
        destructive.visible = true

        destructive.activate()
        T.eq(destructive.armed, true, "armed once more")
        destructive.enabledState = false
        T.eq(destructive.armed, false, "and a button that stops accepting clicks disarms too")

        T.finish("ConfirmTest")
    }
}
