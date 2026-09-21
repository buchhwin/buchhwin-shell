import QtQuick
import QtQuick.Layouts
import qs.theme

// Compact status chip used in the control-center bottom row.
ShellCard {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool showChevron: false
    // See QuickTile: Settings is not another page of this panel.
    property bool leavesPanel: false
    // See QuickTile: opt-in, so a row of chips does not add a dozen tab stops
    // to a panel that navigates with the arrow keys.
    property bool focusOnTab: false
    // A row of chips in a cell one grid row tall: the second line and the
    // chevron go, and the chip stops asking for a height the cell does not
    // have. A glyph and a word is still a chip; two lines cut in half is not.
    property bool compact: false
    signal clicked()

    readonly property bool down: chipMouse.pressed && chipMouse.containsMouse

    activeFocusOnTab: focusOnTab
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    interactive: true
    hovered: chipMouse.containsMouse
    pressed: down
    highlighted: active
    // A chip is a card, not a panel: same rounding as the tiles beside it.
    radius: Metrics.radiusCard
    implicitHeight: root.compact ? Metrics.controlHeightSm : Metrics.tileHeight - Metrics.spaceSm
    implicitWidth: chipRow.implicitWidth + Metrics.spaceLg * 2

    RowLayout {
        id: chipRow
        anchors.fill: parent
        anchors.leftMargin: root.compact ? Metrics.spaceMd : Metrics.spaceLg
        anchors.rightMargin: root.compact ? Metrics.spaceMd : Metrics.spaceMd
        spacing: Metrics.spaceSm
        ShellIcon { glyph: root.icon; size: Metrics.iconMd; color: root.active ? Colors.accentForeground : Colors.mutedText }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ShellText { Layout.fillWidth: true; text: root.title; role: "small"; color: root.active ? Colors.accentForeground : Colors.text }
            ShellText { Layout.fillWidth: true; text: root.subtitle; role: "caption"; visible: text.length > 0 && !root.compact }
        }
        ShellIcon { visible: root.showChevron && !root.compact; glyph: root.leavesPanel ? Icons.leavesPanel : Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
