import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/DockLogic.js" as Logic

// One app on the dock: its icon, the dots for its windows, and the pointer.
// The apps widget places it and sizes its slot; this draws it and says what
// the pointer did. Left click starts or raises it, the middle one opens a new
// window, the right one the menu, and a drag moves it among the pins - or,
// pulled off the dock, unpins it (AppsWidget).
//
// The icon fills Metrics.dockIconFill of its slot: an app icon drawn edge to
// edge (Alacritty's is a full square) stood on the dock's rounded border.
Item {
    id: root

    required property var app
    // The slot's size as laid out (magnified when the pointer is near).
    property real iconSize: Metrics.iconXl
    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    property bool keyFocus: false
    property bool dragging: false
    // Pulled far enough off the dock that letting go unpins it.
    property bool removing: false
    // Along-axis offset while dragged, from where the drag began.
    property real dragOffset: 0

    signal activated()
    signal newWindow()
    signal menuWanted()
    signal dragStarted()
    // `acrossOut`: how far the pointer is off the dock, away from the edge;
    // Infinity for a drag the system took away (nothing is dropped then).
    signal dragMoved(real along, real acrossOut)
    signal dragEnded(real along, real acrossOut)

    readonly property bool hovered: mouse.containsMouse
    readonly property real drawn: Math.round(iconSize * Metrics.dockIconFill)

    // Started and not open yet: the icon breathes - smaller and back in Full,
    // fainter and back in Reduced, a steady faint in Off.
    readonly property bool launching: app.launching === true
    property real breath: 0
    SequentialAnimation on breath {
        running: root.launching && Animations.enabled
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: Animations.dockLaunchPulse / 2; easing.type: Animations.easingBreathe }
        NumberAnimation { to: 0; duration: Animations.dockLaunchPulse / 2; easing.type: Animations.easingBreathe }
        onRunningChanged: if (!running) root.breath = 0
    }
    readonly property real launchScale: launching && Animations.motionEnabled ? 1 - breath * Effects.dockLaunchShrink : 1
    readonly property real launchOpacity: !launching ? 1
        : Animations.motionEnabled ? 1
        : Animations.enabled ? 1 - breath * Effects.dockLaunchFade : 1 - Effects.dockLaunchFade

    Item {
        id: art
        width: root.drawn
        height: root.drawn
        // In the middle of the slot, the slot on its edge side, so a
        // magnified icon grows away from the screen edge.
        x: root.vertical ? (root.edge === "left" ? (root.iconSize - width) / 2 : root.width - root.iconSize + (root.iconSize - width) / 2)
                         : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height - root.iconSize + (root.iconSize - height) / 2
        opacity: (root.removing ? Effects.dockRemoveOpacity : root.dragging ? Effects.disabledOpacity : 1) * root.launchOpacity
        scale: root.launchScale
        transform: Translate {
            x: root.vertical ? 0 : root.dragOffset
            y: root.vertical ? root.dragOffset : 0
        }

        Image {
            anchors.fill: parent
            visible: root.app.glyph.length === 0
            source: visible ? LauncherService.iconSource(root.app.icons) : ""
            sourceSize.width: Metrics.iconXl * 2
            sourceSize.height: Metrics.iconXl * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        // The shell's own Settings: its glyph on an accent tile. A default
        // that names no app yet (DockLogic.defaultPlaceholder): its
        // category's glyph on a quiet tile.
        Rectangle {
            anchors.fill: parent
            visible: root.app.glyph.length > 0
            readonly property bool settings: root.app.special === "settings"
            radius: Metrics.radiusInner
            color: settings ? Colors.accentFill : Colors.surface2
            ShellIcon {
                anchors.centerIn: parent
                glyph: root.app.glyph
                size: parent.width * Metrics.dockGlyphFill
                color: parent.settings ? Colors.accentText : Colors.mutedText
            }
        }
    }

    // Hover and press: a soft square behind the icon, like a bar item's.
    Rectangle {
        anchors.fill: art
        anchors.margins: -Metrics.spaceXs
        radius: Metrics.radiusInner
        color: Colors.barItemHover
        opacity: mouse.pressed ? 1 : Effects.dockHoverOpacity
        visible: (root.hovered || mouse.pressed) && !root.dragging
        z: -1
    }

    FocusRing {
        anchors.fill: art
        active: root.keyFocus
        controlRadius: Metrics.radiusInner
    }

    // The windows: a dot each, up to three; the active app's is a short bar in
    // the accent. A starting app gets one faint dot. On the edge side.
    Row {
        id: dots
        visible: root.app.running || root.launching
        spacing: Metrics.dockDotGap
        rotation: root.vertical ? 90 : 0
        x: root.vertical ? (root.edge === "left" ? -Metrics.dockPadding / 2 - width / 2 : root.width + Metrics.dockPadding / 2 - width / 2)
                         : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height + (Metrics.dockPadding - height) / 2
        Repeater {
            model: root.app.active ? 1 : Math.max(1, Math.min(root.app.count, Metrics.dockMaxDots))
            Rectangle {
                width: root.app.active ? Metrics.dockDotActive : Metrics.dockDot
                height: Metrics.dockDot
                radius: height / 2
                color: root.app.urgent ? Colors.warning : root.app.active ? Colors.accentFill : Colors.mutedText
                opacity: !root.app.running ? Effects.disabledOpacity : 1
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
        property real startAway: 0
        property bool moved: false
        function along(event) { return root.vertical ? event.y : event.x }
        // How far the pointer is from the dock's edge, across it: what a
        // pull off the dock grows.
        function away(event) {
            if (root.edge === "bottom") return -event.y
            if (root.edge === "left") return event.x
            return -event.x
        }
        function acrossOut(event) {
            // How far the pointer left the dock across it, away from the edge.
            if (root.edge === "bottom") return Math.max(0, -event.y)
            if (root.edge === "left") return Math.max(0, event.x - root.width)
            return Math.max(0, -event.x)
        }
        onPressed: event => {
            startAlong = along(event)
            startAway = away(event)
            moved = false
            if (event.button === Qt.RightButton) root.menuWanted()
        }
        onPositionChanged: event => {
            if (!pressed || !(pressedButtons & Qt.LeftButton) || !root.app.pin) return
            const delta = along(event) - startAlong
            // A pull away from the edge starts a drag from where it was
            // pressed, inside the icon: counted from the icon's own edge,
            // a straight pull off a taskbar left the body (a leave, and Qt
            // cancels) before it ever started.
            if (!moved && !Logic.dragStarts(delta, Math.max(0, away(event) - startAway), Metrics.dragThreshold)) return
            if (!moved) {
                moved = true
                root.dragStarted()
            }
            root.dragOffset = delta
            root.dragMoved(along(event), acrossOut(event))
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
            if (moved) root.dragEnded(startAlong, Infinity)
            moved = false
            root.dragOffset = 0
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.app.name
}
