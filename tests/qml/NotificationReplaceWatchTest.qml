import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T

// How NotificationService hears a sender replace a notification in place:
// one watcher per notification in the history, a Variants of Connections
// (services/NotificationService.qml, `replaced`). The service's history is
// the server's, and a test runs no server (pitfall 82), so the pattern is
// checked here on stand-ins, and the service's file for the same wiring.
//
// - A watcher hears a summary or a body that changes, once per change.
// - The watchers of the ones that stay are kept as the history grows: a
//   Variants that made them anew would have dropped one change in between.
// - A notification gone from the history is no longer heard: Variants lets
//   its watcher go a turn later (deleteLater), and a closed notification is
//   not updated any more, so that turn does no harm.
ShellRoot {
    id: root

    component Note: QtObject {
        property string summary: ""
        property string body: ""
    }
    Note { id: anna; summary: "Anna" }
    Note { id: bob; summary: "Bob" }

    property var history: [anna]
    property var heard: []
    property int watchers: 0
    function replaced(notification) { heard = heard.concat([notification.summary + ": " + notification.body]) }

    Variants {
        model: root.history
        Connections {
            required property var modelData
            target: modelData
            function onSummaryChanged() { root.replaced(modelData) }
            function onBodyChanged() { root.replaced(modelData) }
            Component.onCompleted: root.watchers += 1
        }
    }

    Component { id: fileReader; FileView { blockLoading: true; printErrors: false } }
    function read(path) {
        const view = fileReader.createObject(root, { path: Quickshell.shellPath(path) })
        const text = view.text()
        view.destroy()
        return text
    }

    Timer {
        id: gone
        interval: 100
        onTriggered: {
            root.heard = []
            anna.body = "too late"
            T.eq(root.heard, [], "one gone from the history is no longer heard")
            T.eq(bob.summary, "Bob", "the one that stays is untouched")
            bob.summary = "Bob again"
            T.eq(root.heard, ["Bob again: "], "and still heard")

            // The service as it is: the same watchers over its own history.
            const service = root.read("services/NotificationService.qml")
            const at = service.indexOf("    Variants {\n        model: root.history\n")
            T.ok(at >= 0, "NotificationService watches its history with a Variants")
            const block = at >= 0 ? service.slice(at, service.indexOf("\n    }\n", at)) : ""
            T.ok(block.indexOf("target: modelData") >= 0
                 && block.indexOf("function onSummaryChanged() { root.replaced(modelData) }") >= 0
                 && block.indexOf("function onBodyChanged() { root.replaced(modelData) }") >= 0,
                 "and each watcher hands a new summary or body to replaced()")
            T.finish("NotificationReplaceWatchTest")
        }
    }

    Component.onCompleted: {
        T.eq(root.watchers, 1, "a watcher for the one notification")
        anna.summary = "Anna (2)"
        anna.body = "Where are you?"
        T.eq(root.heard, ["Anna (2): ", "Anna (2): Where are you?"], "a new summary and a new body, each heard once")
        root.history = [anna, bob]
        T.eq(root.watchers, 2, "the history grown: one more watcher, the first one kept")
        root.heard = []
        anna.body = "Here"
        T.eq(root.heard, ["Anna (2): Here"], "and the kept one still hears its notification, once")
        root.history = [bob]
        gone.start()
    }
}
