import Quickshell
import QtQuick
import QtTest
import qs.theme
import qs.shell.dock
import "Harness.js" as T
import "../../services/dock/DockLogic.js" as D

// The dock's icons as they are (shell/dock/DockItem.qml), in a Repeater over
// a keyed ScriptModel the way the apps widget holds them, driven by real
// pointer events (QtTest's TestEvent): the name handed from icon to icon
// across the gap between them and kept with an icon that moves along the
// row (DockLogic.labelAfter), a pull the system
// takes away (DockLogic.cancelOutcome) and a drag whose app goes meanwhile
// (DockLogic.dragLost). The apps widget and the dock's service need the live
// session (testing.md pitfalls 82 and 87); the few lines here hand on what
// the icons say as they do.
ShellRoot {
    id: root

    property var apps: [
        { key: "app:a", pin: "a", pinned: true, glyph: "A", name: "A", running: false, count: 0, urgent: false, icons: [] },
        { key: "app:b", pin: "b", pinned: true, glyph: "B", name: "B", running: false, count: 0, urgent: false, icons: [] },
        { key: "app:c", pin: "c", pinned: false, glyph: "C", name: "C", running: true, count: 1, urgent: false, icons: [] }
    ]
    readonly property int size: 48
    readonly property int gap: Metrics.dockGap
    // The bottom dock's room above an icon before the unpin (AppsWidget
    // unpinRoom at the defaults).
    readonly property real room: Metrics.dockLabelHeight + Metrics.dockLabelGap - Metrics.spaceSm

    // ---- the apps widget's name over the icons --------------------------------
    property int labelIndex: -1
    property bool labelShown: false
    function labelFor(index, entered) {
        const next = D.labelAfter({ index: labelIndex, shown: labelShown }, index, entered)
        labelIndex = next.index
        labelShown = next.shown
        if (next.timer === "show") { grace.stop(); delay.restart() }
        else if (next.timer === "hide") { delay.stop(); grace.restart() }
        else if (next.timer === "stop") { delay.stop(); grace.stop() }
    }
    Timer { id: delay; interval: Animations.dockLabelDelay; onTriggered: root.labelShown = true }
    Timer { id: grace; interval: Animations.dockHideDelay; onTriggered: root.labelShown = false }

    // ---- the drag, as the apps widget and the service end it ------------------
    property string dragKey: ""
    property string outcome: ""
    onAppsChanged: if (D.dragLost(dragKey, apps)) dragKey = ""

    TestEvent { id: events }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300
        color: "transparent"
        Item {
            id: row
            x: 50
            y: 150
            width: 3 * root.size + 2 * root.gap
            height: root.size
            Repeater {
                id: icons
                model: ScriptModel { values: root.apps; objectProp: "key" }
                DockItem {
                    required property var modelData
                    required property int index
                    app: modelData
                    edge: "bottom"
                    iconSize: root.size
                    x: index * (root.size + root.gap)
                    width: root.size
                    height: root.size
                    onHoveredChanged: root.labelFor(index, hovered)
                    onIndexChanged: if (hovered) root.labelIndex = index
                    onDragStarted: { root.dragKey = modelData.key; root.outcome = "" }
                    onDragEnded: (along, acrossOut) => {
                        root.outcome = D.dragOutcome(modelData, acrossOut, root.size, -1, Metrics.dockUnpinReach, root.room)
                        root.dragKey = ""
                    }
                    onDragCanceled: (along, acrossOut, rising) => {
                        if (modelData.key !== root.dragKey) return
                        root.outcome = D.cancelOutcome(modelData, acrossOut, rising, root.size, Metrics.dockUnpinReach, root.room)
                        root.dragKey = ""
                    }
                }
            }
        }
    }

    function move(x, y, buttons) { events.mouseMove(row, x, y, -1, buttons === undefined ? Qt.NoButton : buttons, Qt.NoModifier) }
    // A pull straight up from the middle of icon `index` to `top` (row
    // coordinates; negative is above the icons), in small steps.
    function pull(index, top) {
        const x = index * (size + gap) + size / 2
        events.mousePress(row, x, size / 2, Qt.LeftButton, Qt.NoModifier, -1)
        for (let y = size / 2 - 4; y > top; y -= 4) move(x, y, Qt.LeftButton)
        move(x, top, Qt.LeftButton)
    }
    // What a pointer leave does to a press on a layer surface: Qt cancels it.
    // Disabling the icon takes its grab the same way.
    function cancel(index) {
        const icon = icons.itemAt(index)
        icon.enabled = false
        icon.enabled = true
    }

    property int step: 0
    Timer {
        interval: 60
        repeat: true
        running: true
        onTriggered: {
            root.step += 1
            const between = root.size + root.gap / 2
            switch (root.step) {
            case 2:
                root.move(24, 24)
                break
            case 11:
                T.ok(root.labelShown && root.labelIndex === 0, "resting on an icon shows its name")
                // On to the next one through the gap between them.
                root.move(40, 24)
                root.move(between, 24)
                root.move(root.size + root.gap + 6, 24)
                root.move(root.size + root.gap + 24, 24)
                T.ok(root.labelShown && root.labelIndex === 1, "the next icon's name shows at once, across the gap")
                break
            case 13:
                T.ok(root.labelShown && root.labelIndex === 1, "and stays")
                root.move(24, 120)
                break
            case 14:
                T.ok(root.labelShown, "off the icons: the name stays for the grace")
                break
            case 24:
                T.ok(!root.labelShown, "then goes")
                // Pulled up past the unpin distance and off the surface: the
                // system takes the drag away.
                root.pull(0, -(root.room + 4))
                T.eq(root.dragKey, "app:a", "the pull is a drag")
                root.cancel(0)
                T.eq(root.outcome, "unpin", "taken away past the unpin distance: unpinned")
                T.eq(root.dragKey, "", "and the drag is over")
                events.mouseRelease(row, 24, -(root.room + 4), Qt.LeftButton, Qt.NoModifier, -1)
                break
            case 26:
                // A short pull, then along the dock, then taken away.
                root.pull(1, -6)
                root.move(root.size + root.gap + 30, -6, Qt.LeftButton)
                root.cancel(1)
                T.eq(root.outcome, "none", "taken away near the dock, not going away: nothing")
                events.mouseRelease(row, root.size + root.gap + 30, -6, Qt.LeftButton, Qt.NoModifier, -1)
                break
            case 28:
                // A quick pull still going away when the system took it.
                root.pull(1, -(root.room / 2 + 2))
                root.cancel(1)
                T.eq(root.outcome, "unpin", "a quick pull going away past half the distance: unpinned")
                events.mouseRelease(row, 78, -(root.room / 2 + 2), Qt.LeftButton, Qt.NoModifier, -1)
                break
            case 30:
                // A running app dragged to be pinned, whose last window
                // closes meanwhile: its icon - and the end of the drag - goes.
                root.pull(2, 10)
                T.eq(root.dragKey, "app:c", "a running app's drag")
                root.apps = root.apps.slice(0, 2)
                break
            case 32:
                T.eq(icons.count, 2, "its icon is gone")
                T.eq(root.dragKey, "", "and the drag with it, rather than for good")
                events.mouseRelease(row, 132, 10, Qt.LeftButton, Qt.NoModifier, -1)
                break
            case 34:
                root.move(root.size + root.gap + 24, 24)
                break
            case 43:
                T.ok(root.labelShown && root.labelIndex === 1, "resting on the second icon shows its name")
                // The app before it goes: it moves along the row, out from
                // under the pointer.
                root.apps = root.apps.slice(1)
                break
            case 44:
                T.eq(root.labelIndex, 0, "the name went with it to its new place")
                break
            case 54:
                T.ok(!root.labelShown, "and goes after the grace, rather than staying up with nothing under the pointer")
                T.finish("DockItemTest")
                break
            }
        }
    }
}
