import QtQuick
import QtQuick.Layouts
import qs.theme

// Selectable list row with icon, title, subtitle and a trailing item.
// One UI: strongly rounded, a calm fill on hover and a short press dip.
Rectangle {
    id: root
    // The surface the row sits on, so hover and press stay visible on it:
    // 0 = straight on a panel, 1 = on a card, 2 = in a card inside a card.
    // Colors.hover is 0.06 and Colors.surface1 is 0.07, so a level-0 hover on
    // a card would be all but invisible.
    property int level: 0
    // A row in a dense list (menus, the launcher, the editor's pickers).
    property bool compact: false
    property string icon: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property string trailingText: ""
    property bool selected: false
    // The row the keyboard is standing on, which is not the same thing as the
    // one that is chosen: an open list has both at once.
    property bool highlighted: false
    property bool active: false
    property bool chevron: false
    // Opt-in keyboard focus. Most lists in the shell are driven by the arrow
    // keys of the field above them, and those must not gain a tab stop per row.
    property bool focusOnTab: false
    default property alias trailing: trailingSlot.data
    signal clicked()
    signal rightClicked()

    activeFocusOnTab: focusOnTab
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    readonly property bool down: rowMouse.pressed && rowMouse.containsMouse
    readonly property color hoverColor: level >= 2 ? Colors.surface2Hover
        : level === 1 ? Colors.surface1Hover : Colors.hover
    readonly property color pressedColor: level >= 2 ? Colors.surface2Pressed
        : level === 1 ? Colors.surface1Pressed : Colors.pressed

    implicitHeight: compact ? Metrics.controlHeight + Metrics.spaceXs : Metrics.rowHeight
    radius: Metrics.radiusCard
    color: selected ? Colors.accentSoft : down ? pressedColor
        : rowMouse.containsMouse || highlighted ? hoverColor : "transparent"
    scale: down ? Effects.pressScaleWide : 1
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => event.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.compact ? Metrics.spaceMd : Metrics.spaceLg
        anchors.rightMargin: root.compact ? Metrics.spaceMd : Metrics.spaceLg
        spacing: Metrics.spaceMd

        Image {
            visible: root.iconSource.length > 0
            Layout.preferredWidth: Metrics.iconLg
            Layout.preferredHeight: Metrics.iconLg
            source: root.iconSource
            sourceSize.width: Metrics.iconLg * 2
            sourceSize.height: Metrics.iconLg * 2
            fillMode: Image.PreserveAspectFit
            // Theme icons (image://icon) must load on the GUI thread.
            asynchronous: !String(source).startsWith("image://")
        }
        ShellIcon {
            visible: root.icon.length > 0 && root.iconSource.length === 0
            Layout.preferredWidth: Metrics.iconLg
            glyph: root.icon
            size: Metrics.iconMd
            color: root.active || root.selected ? Colors.accentForeground : Colors.mutedText
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ShellText { Layout.fillWidth: true; text: root.title; color: root.active ? Colors.accentForeground : Colors.text }
            ShellText { Layout.fillWidth: true; text: root.subtitle; role: "small"; muted: true; visible: text.length > 0 }
        }
        ShellText { visible: root.trailingText.length > 0; text: root.trailingText; role: "small"; muted: true }
        Item {
            id: trailingSlot
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            visible: children.length > 0
        }
        ShellIcon { visible: root.chevron; glyph: Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
    }
}
