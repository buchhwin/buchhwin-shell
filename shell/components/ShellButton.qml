import QtQuick
import QtQuick.Layouts
import qs.theme

// One UI button: a filled capsule with generous padding, a calm fill that
// steps once per state and a short press dip. variant: ghost, surface,
// accent, danger.
//
// A button that destroys something sets `confirm`: the first click arms it and
// says so, the second does it, and it disarms itself if nothing follows. The
// same "click again" the event editor has always used rather than a dialog -
// these sit in lists, and a dialog over a list takes the row with it.
Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property string variant: "surface"
    property int iconSize: Metrics.iconSm
    property bool compact: false
    property bool enabledState: true
    // What the button is for, shown once the pointer has rested on it. The
    // bubble is drawn by one ToolTipLayer per window; a window without one
    // shows nothing, which is what every window did before there was a layer
    // at all.
    property string toolTip: ""
    // Opt-in keyboard focus (forms); the ring shows wherever focus arrives.
    property bool focusOnTab: false
    signal clicked()

    property bool confirm: false
    property string confirmText: "Click again"
    // Armed, and what the button looks like while it is. An armed button always
    // shows the words, even one that is otherwise an icon on its own: there is
    // no room for a doubt about what the next click will do.
    property bool armed: false
    readonly property string shownText: armed ? confirmText : text
    readonly property string shownVariant: armed ? "danger" : variant

    readonly property bool hovered: mouse.containsMouse
    readonly property bool down: mouse.pressed && mouse.containsMouse
    readonly property color foreground: shownVariant === "accent" ? Colors.accentText
        : shownVariant === "danger" ? Colors.danger : Colors.text

    activeFocusOnTab: focusOnTab && enabledState
    implicitHeight: compact ? Metrics.controlHeightSm : Metrics.controlHeight
    implicitWidth: shownText.length
        ? row.implicitWidth + (compact ? Metrics.controlPaddingSm : Metrics.controlPadding) * 2
        : implicitHeight
    radius: Metrics.pillRadius(height)
    opacity: enabledState ? 1 : Effects.disabledOpacity
    color: shownVariant === "accent"
        ? (down ? Colors.accentPressed : hovered ? Colors.accentHover : Colors.accent)
        : shownVariant === "ghost"
            ? (down ? Colors.ghostPressed : hovered ? Colors.ghostHover : "transparent")
            : shownVariant === "danger"
                ? (down ? Colors.dangerSoftPressed : hovered ? Colors.dangerSoftHover : Colors.dangerSoft)
                : (down ? Colors.controlFillPressed : hovered ? Colors.controlFillHover : Colors.controlFill)
    scale: down ? Effects.pressScale : 1
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceSm
        ShellIcon {
            visible: root.icon.length > 0
            glyph: root.icon
            size: root.iconSize
            color: root.foreground
        }
        ShellText {
            visible: root.shownText.length > 0
            text: root.shownText
            role: root.compact ? "small" : "body"
            color: root.foreground
        }
    }

    // What a press does, wherever it came from. The keyboard used to emit
    // `clicked` directly, which would have walked straight past the question a
    // destructive button asks.
    function activate() {
        root.hideTip()
        // The first press on a button that destroys something only arms it.
        if (root.confirm && !root.armed) {
            root.armed = true
            disarm.restart()
            return
        }
        root.disarmNow()
        root.clicked()
    }

    Keys.onReturnPressed: root.activate()
    Keys.onSpacePressed: root.activate()

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
        onEntered: tip.arm()
        onExited: tip.release()
    }

    // The walk, the wait and the three ways out all live in ToolTipHost, which
    // the "i" beside a setting's label uses too. `tipLayer` stays as a
    // function because ToolTipTest drives it directly.
    ToolTipHost {
        id: tip
        anchorItem: root
        text: root.toolTip
    }
    function tipLayer() { return tip.findLayer() }
    function showTip() { tip.show() }
    function hideTip() { tip.release() }
    // An armed button that is left alone goes back to what it was, so nobody
    // finds one still armed from an earlier visit and destroys something with
    // what they thought was the first click.
    function disarmNow() {
        root.armed = false
        disarm.stop()
    }
    Timer {
        id: disarm
        interval: Animations.confirmTimeout
        onTriggered: root.armed = false
    }
    onVisibleChanged: if (!visible) root.disarmNow()
    onEnabledStateChanged: if (!enabledState) { tip.release(); root.disarmNow() }
    Component.onDestruction: root.hideTip()
}
