//@ pragma Env HYPRLAND_INSTANCE_SIGNATURE=test-instance
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// services/LoginMark.qml, the first-start mark of PowerService and
// ClipboardService, in the runner's own runtime directory: named after the
// compositor's instance (the pragma; the runner strips the real one), so a
// quick log out and in - the directory kept - is a new login again; the first
// check leaves it, the next one finds it.
ShellRoot {
    id: root
    property var answers: []

    LoginMark {
        id: mark
        name: "test-login"
        onDecided: first => {
            root.answers = root.answers.concat([first])
            if (root.answers.length === 1) mark.check()
            else root.finish()
        }
    }

    function finish() {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || ""
        T.eq(mark.path, runtime + "/buchhwin-shell/test-login-test-instance", "in the runtime directory, after the instance")
        T.eq(answers, [true, false], "the first check is the login's first start, the next a restart")
        T.finish("LoginMarkTest")
    }

    Component.onCompleted: mark.check()
}
