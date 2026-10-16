import QtQuick
import qs.theme
import qs.services
import qs.shell.components

// One app on the dock: its icon, the dots for its windows, and the pointer.
// Dock.qml places it (x/y along the body) and sizes it; this draws it and says
// what the pointer did. Left click starts or raises it, the middle one opens
// a new window, the right one the menu, and a drag moves it among the pins.
Item {
    id: root

    required property var app
    // The icon's size as drawn (magnified, fitted) and the slot's thickness.
    property real iconSize: Metrics.iconXl
    property real across: iconSize
    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    property bool keyFocus: false
    property bool dragging: false
    // Along-axis offset while dragged, from where the drag began.
    property real dragOffset: 0

    signal activated()
    signal newWindow()
    signal menuWanted()
    signal dragStarted()
    signal dragMoved(real along)
    signal dragEnded(real along, real acrossOut)

    readonly property bool hovered: mouse.containsMouse

    // The icon sits on the body's edge side, so a magnified one grows away
    // from the screen edge, into the room the surface keeps for it.
    Image {
        id: icon
        width: root.iconSize
        height: root.iconSize
        x: root.vertical ? (root.edge === "left" ? 0 : root.width - width) : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height - height
        source: LauncherService.iconSource(root.app.icons)
        sourceSize.width: Metrics.iconXl * 2
        sourceSize.height: Metrics.iconXl * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: root.dragging ? 0.6 : 1
        transform: Translate {
            x: root.vertical ? 0 : root.dragOffset
            y: root.vertical ? root.dragOffset : 0
        }
    }

    // Hover and press: a soft square behind the icon, like a bar item's.
    Rectangle {
        anchors.fill: icon
        anchors.margins: -Metrics.spaceXxs
        radius: Metrics.radiusInner
        color: Colors.barItemHover
        opacity: mouse.pressed ? 1 : 0.8
        visible: root.hovered || mouse.pressed
        z: -1
    }

    FocusRing {
        anchors.fill: icon
        active: root.keyFocus
        controlRadius: Metrics.radiusInner
    }

    // The windows: a dot each, up to three; the active app's is a short bar in
    // the accent. On the edge side of the icon.
    Row {
        id: dots
        visible: root.app.running
        spacing: Metrics.dockDotGap
        rotation: root.vertical ? 90 : 0
        x: root.vertical ? (root.edge === "left" ? -Metrics.dockPadding / 2 - width / 2 : root.width + Metrics.dockPadding / 2 - width / 2)
                         : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height + (Metrics.dockPadding - height) / 2
        Repeater {
            model: root.app.active ? 1 : Math.min(root.app.count, Metrics.dockMaxDots)
            Rectangle {
                width: root.app.active ? Metrics.dockDotActive : Metrics.dockDot
                height: Metrics.dockDot
                radius: height / 2
                color: root.app.urgent ? Colors.warning : root.app.active ? Colors.accentFill : Colors.mutedText
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        property real startAlong: 0
        property bool moved: false
        function along(event) { return root.vertical ? event.y : event.x }
        function acrossOut(event) {
            // How far the pointer left the dock across it, away from the edge.
            if (root.edge === "bottom") return Math.max(0, -event.y)
            if (root.edge === "left") return Math.max(0, event.x - root.width)
            return Math.max(0, -event.x)
        }
        onPressed: event => {
            startAlong = along(event)
            moved = false
            if (event.button === Qt.RightButton) root.menuWanted()
        }
        onPositionChanged: event => {
            if (!pressed || !(pressedButtons & Qt.LeftButton)) return
            const delta = along(event) - startAlong
            if (!moved && Math.abs(delta) < Metrics.dragThreshold) return
            if (!moved) {
                moved = true
                root.dragStarted()
            }
            root.dragOffset = delta
            root.dragMoved(along(event))
        }
        onReleased: event => {
            if (moved) {
                root.dragEnded(along(event), acrossOut(event))
                moved = false
                root.dragOffset = 0
                return
            }
            if (!containsMouse) return
            if (event.button === Qt.LeftButton) root.activated()
            else if (event.button === Qt.MiddleButton) root.newWindow()
        }
        onCanceled: {
            if (moved) root.dragEnded(startAlong, Number.MAX_VALUE)
            moved = false
            root.dragOffset = 0
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.app.name
}
