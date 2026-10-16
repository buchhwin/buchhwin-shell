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
    // A glyph after the words, for a link that goes somewhere ("All apps ›",
    // Icons.forward): the leading slot put the chevron before them, which
    // reads as going back (round 12, D13 a). Drawn like the leading one.
    property string trailingIcon: ""
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
    // An accent button that cannot act drops the accent: faded, the accent
    // disc read as the accentSoft tint a selected thing wears on a light card
    // rather than as off (the media popup's Play with no player; round 12,
    // D14). It takes the grey of a card inside a card and the muted ink, and
    // fades like every other disabled button.
    readonly property bool accentOff: shownVariant === "accent" && !enabledState
    // A danger button's label sits on its own red wash, so it takes the red
    // made for that wash (Colors.dangerOnSoft): the plain one was under 4:1.
    readonly property color foreground: accentOff ? Colors.mutedText
        : shownVariant === "accent" ? Colors.accentText
        : shownVariant === "danger" ? Colors.dangerOnSoft : Colors.text

    activeFocusOnTab: focusOnTab && enabledState
    implicitHeight: compact ? Metrics.controlHeightSm : Metrics.controlHeight
    // The air on each side of the words. A ghost button at the edge of a row
    // of content takes it back with a negative margin of this size, so its
    // words, not its invisible capsule, line up with the content's edge.
    readonly property real sidePadding: compact ? Metrics.controlPaddingSm : Metrics.controlPadding
    implicitWidth: shownText.length ? row.implicitWidth + sidePadding * 2 : implicitHeight
    radius: Metrics.pillRadius(height)
    opacity: enabledState ? 1 : Effects.disabledOpacity
    color: accentOff ? Colors.surface2
        : shownVariant === "accent"
        ? (down ? Colors.accentPressed : hovered ? Colors.accentHover : Colors.accent)
        : shownVariant === "ghost"
            ? (down ? Colors.pressed : hovered ? Colors.hover : "transparent")
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
            Layout.maximumWidth: Metrics.buttonTextMax
            text: root.shownText
            role: root.compact ? "small" : "body"
            color: root.foreground
        }
        ShellIcon {
            visible: root.trailingIcon.length > 0
            glyph: root.trailingIcon
            size: root.iconSize
            color: root.foreground
        }
    }

    // What a press does, wherever it came from. The keyboard used to emit
    // `clicked` directly, which would have walked straight past the question a
    // destructive button asks.
    function activate() {
        root.hideTip()
        // A disabled button keeps the focus it had when it was disabled (a
        // play button the player went away under), and Return or Space on it
        // still arrived here: the mouse was the only way in that checked.
        if (!root.enabledState) return
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
    Keys.onEnterPressed: root.activate()
    Keys.onSpacePressed: root.activate()

    // Named for screen readers by its words, or by its tip when it is an icon.
    Accessible.role: Accessible.Button
    Accessible.name: root.shownText || root.toolTip
    Accessible.onPressAction: root.activate()

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
