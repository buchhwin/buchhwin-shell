import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/DockLogic.js" as Logic
import "../../services/dock/BadgeLogic.js" as Badges
import "../components/WheelLogic.js" as Wheel

// One app on the dock: its icon, the dots for its windows, and the pointer.
// The apps widget places it and sizes its slot; this draws it and says what
// the pointer did. Left click starts or raises it, the middle one opens a new
// window, the right one the menu, and a drag moves it among the pins - or,
// pulled off the dock, unpins it (AppsWidget).
//
// The icon fills Metrics.dockIconFill of its slot: an app icon drawn edge to
// edge (Alacritty's is a full square) stood on the dock's rounded border.
//
// A minimized window's dot is hollow, and with the dock's badges on an
// unread count stands on the icon's corner (`app.badge`, dock/BadgeLogic.js).
// The wheel turns the app's volume only where the apps widget says so
// (`wheelTurns`, dock.wheelVolume); otherwise it is handed on.
Item {
    id: root

    required property var app
    // The slot's size as laid out (magnified when the pointer is near).
    property real iconSize: Metrics.iconXl
    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    property bool keyFocus: false
    // Whether it runs and is in front: handed in by the apps widget
    // (DockService.runningOf/activeOf) - the shell's Settings runs while its
    // panel is open, and which app is in front is not part of `app`, so a
    // focus change rebuilds no app.
    property bool running: app.running === true
    property bool active: app.active === true
    property bool dragging: false
    // Pulled far enough off the dock that letting go unpins it.
    property bool removing: false
    // Along-axis offset while dragged, from where the drag began.
    property real dragOffset: 0

    signal activated()
    signal newWindow()
    signal menuWanted()
    signal dragStarted()
    // `acrossOut`: how far the pointer is off the dock, away from the edge.
    signal dragMoved(real along, real acrossOut)
    signal dragEnded(real along, real acrossOut)
    // The system took the drag away - a pull past the dock's surface is
    // one (a pointer leave cancels the press): where it was last, and
    // whether it was still going away from the dock (DockLogic.cancelOutcome).
    signal dragCanceled(real along, real acrossOut, bool rising)
    // The wheel over the icon, in whole steps (WheelLogic.step: a notch, or a
    // stretch of a swipe), positive up - while `wheelTurns`.
    property bool wheelTurns: false
    signal wheeled(int steps)

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
                color: parent.settings ? Colors.accentFillText : Colors.mutedText
            }
        }

        // The unread count, on the icon's corner and moving with it (a drag,
        // the launch breath). A fill that carries a label: the accent fill
        // and its text.
        Rectangle {
            id: badge
            readonly property string label: Badges.badgeText(root.app.badge)
            visible: label.length > 0
            height: Metrics.iconSm
            width: Math.max(height, count.implicitWidth + Metrics.spaceXs * 2)
            x: parent.width - width + Metrics.spaceXs
            y: -Metrics.spaceXs
            radius: height / 2
            color: Colors.accentFill
            border.width: Metrics.borderWidth
            border.color: Colors.panelFor("dock")
            ShellText {
                id: count
                anchors.centerIn: parent
                text: badge.label
                role: "caption"
                color: Colors.accentFillText
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

    // The windows: a dot each, up to three, a minimized one's hollow; the
    // active app's is a short bar in the accent. A starting app gets one faint
    // dot. On the edge side (DockLogic.dotStates).
    readonly property var dotStates: Logic.dotStates(app, running, active, launching, Metrics.dockMaxDots)
    Row {
        id: dots
        visible: root.dotStates.length > 0
        spacing: Metrics.dockDotGap
        rotation: root.vertical ? 90 : 0
        x: root.vertical ? (root.edge === "left" ? -Metrics.dockPadding / 2 - width / 2 : root.width + Metrics.dockPadding / 2 - width / 2)
                         : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height + (Metrics.dockPadding - height) / 2
        Repeater {
            model: root.dotStates
            Rectangle {
                required property string modelData
                readonly property bool hollow: modelData === "minimized"
                readonly property color ink: root.app.urgent ? Colors.warning : modelData === "active" ? Colors.accentFill : Colors.mutedText
                width: modelData === "active" ? Metrics.dockDotActive : Metrics.dockDot
                height: Metrics.dockDot
                radius: height / 2
                color: hollow ? "transparent" : ink
                border.width: hollow ? Metrics.borderWidth : 0
                border.color: ink
                opacity: modelData === "launching" ? Effects.disabledOpacity : 1
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
        // The drag's last place, for a cancel: Qt reports none with it.
        property real lastAlong: 0
        property real lastOut: 0
        property bool rising: false
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
            lastAlong = startAlong
            lastOut = 0
            rising = false
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
            const out = acrossOut(event)
            rising = out > lastOut
            lastOut = out
            lastAlong = along(event)
            root.dragOffset = delta
            root.dragMoved(lastAlong, out)
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
            const was = moved
            moved = false
            root.dragOffset = 0
            if (was) root.dragCanceled(lastAlong, lastOut, rising)
        }
        // A MouseArea's wheel, not a WheelHandler's: one that is not taken is
        // handed on (testing.md pitfall 90).
        property var wheelCarry: null
        onWheel: wheel => {
            if (!root.wheelTurns) {
                wheel.accepted = false
                return
            }
            wheelCarry = Wheel.step(wheelCarry, wheel.phase, wheel.angleDelta.y, wheel.pixelDelta.y)
            if (wheelCarry.steps !== 0) root.wheeled(wheelCarry.steps)
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.app.name
}
