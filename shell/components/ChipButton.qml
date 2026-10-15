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
    // Dimmed, and then it neither lights up nor answers: every way in asks,
    // the keys and a screen reader as well as the mouse, the way QuickTile
    // asks `available` and ShellButton `enabledState`.
    property bool enabledState: true
    signal clicked()

    readonly property bool down: chipMouse.pressed && chipMouse.containsMouse
    function activate() { if (root.enabledState) root.clicked() }

    activeFocusOnTab: focusOnTab && enabledState
    Keys.onSpacePressed: root.activate()
    Keys.onReturnPressed: root.activate()
    Keys.onEnterPressed: root.activate()
    Accessible.role: Accessible.Button
    Accessible.name: root.title
    Accessible.onPressAction: root.activate()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    interactive: true
    hovered: chipMouse.containsMouse && root.enabledState
    pressed: down && root.enabledState
    opacity: enabledState ? 1 : Effects.disabledOpacity
    highlighted: active
    // A chip is a card, not a panel: same rounding as the tiles beside it.
    radius: Metrics.radiusCard
    implicitHeight: root.compact ? Metrics.controlHeightSm : Metrics.tileHeight - Metrics.spaceSm
    // A chip without a glyph is a word on a capsule and gets the same air on
    // both sides. Its air used to come from an empty glyph that still took
    // its gap (20/20 when compact, 24/16 when not); TileContent leaves an
    // empty glyph out, so the air is asked for here instead.
    readonly property bool wordOnly: root.icon.length === 0
    implicitWidth: chipRow.implicitWidth + (root.wordOnly ? Metrics.spaceXl : Metrics.spaceLg) * 2

    RowLayout {
        id: chipRow
        anchors.fill: parent
        anchors.leftMargin: root.wordOnly ? Metrics.spaceXl : root.compact ? Metrics.spaceMd : Metrics.spaceLg
        anchors.rightMargin: root.wordOnly ? Metrics.spaceXl : Metrics.spaceMd
        spacing: Metrics.spaceSm
        // The row's glyph, gap and two lines (TileContent), as on the tiles
        // above the chips and the rows behind them.
        TileContent {
            Layout.fillWidth: true
            icon: root.icon
            title: root.title
            subtitle: root.subtitle
            singleLine: root.compact
            iconColor: root.active ? Colors.accentForeground : Colors.mutedText
            titleColor: root.active ? Colors.accentForeground : Colors.text
        }
        ShellIcon { visible: root.showChevron && !root.compact; glyph: root.leavesPanel ? Icons.leavesPanel : Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }
}
