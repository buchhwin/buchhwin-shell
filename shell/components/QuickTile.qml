import QtQuick
import QtQuick.Layouts
import qs.theme

// Control-center tile: icon, title, status, optional toggle and a chevron
// that opens a detail page.
//
// Three forms, one per shape of the cell it was given (`shape`, from
// FitLogic; the surface hands it over). They show different things rather
// than more or less of the same thing:
//
//   icon     a single row - the glyph alone, and the card itself carries the
//            on/off state, because a switch does not fit beside it
//   stacked  four rows or more in one column - the glyph above the title,
//            which is what height without width is good for
//   row      everything else, and what this tile has always been
ShellCard {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool showToggle: true
    property bool showChevron: false
    // The chevron leads to another page of this panel; leavesPanel says the
    // click opens Settings instead, which is a different promise.
    property bool leavesPanel: false
    property bool available: true
    // Opt-in keyboard focus, like ShellButton and ShellToggle: only surfaces
    // where arrow keys do not already navigate switch it on.
    property bool focusOnTab: false
    signal toggled(bool checked)
    signal activated()
    signal detailsRequested()

    // The shape of the cell, as FitLogic names it. A tile used outside a
    // surface the user sizes keeps the row it always had.
    property string shape: "small"
    readonly property bool iconOnly: shape === "icon"
    readonly property bool stacked: shape === "tall"

    readonly property bool down: tileMouse.pressed && tileMouse.containsMouse

    // With no switch on it, the only thing a click can mean is the switch.
    // A chevron has nowhere to go at this size either, so the tile stops
    // promising a detail page and does the one thing it is for.
    readonly property bool clickToggles: root.iconOnly && root.showToggle

    activeFocusOnTab: focusOnTab && available
    Keys.onSpacePressed: root.showToggle ? root.toggled(!root.checked) : root.activated()
    Keys.onReturnPressed: root.showChevron && !root.iconOnly ? root.detailsRequested() : root.activated()
    Keys.onEnterPressed: root.showChevron && !root.iconOnly ? root.detailsRequested() : root.activated()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    interactive: true
    hovered: tileMouse.containsMouse
    pressed: down
    implicitHeight: Metrics.tileHeight
    opacity: available ? 1 : Effects.disabledOpacity
    // At icon size the state has nowhere else to go: the switch is gone, so
    // the card is what says on or off.
    highlighted: root.iconOnly && root.checked && root.available

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.clickToggles) root.toggled(!root.checked)
            else if (root.showChevron && !root.iconOnly) root.detailsRequested()
            else root.activated()
        }
    }

    // ---- icon: the glyph alone ------------------------------------------
    ShellIcon {
        anchors.centerIn: parent
        visible: root.iconOnly
        glyph: root.icon
        size: Metrics.iconLg
        color: root.checked ? Colors.accentForeground : Colors.mutedText
    }

    // ---- stacked: the glyph over the title ------------------------------
    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Metrics.spaceMd
        anchors.rightMargin: Metrics.spaceMd
        visible: root.stacked
        spacing: Metrics.spaceSm

        ShellIcon {
            Layout.alignment: Qt.AlignHCenter
            glyph: root.icon
            size: Metrics.iconXl
            color: root.checked ? Colors.accentForeground : Colors.mutedText
        }
        ShellText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            role: "bodyLarge"
        }
        ShellText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.subtitle
            role: "small"
            muted: true
            visible: text.length > 0
        }
        ShellToggle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.showToggle
            checked: root.checked
            enabledState: root.available
            onToggled: value => root.toggled(value)
        }
    }

    // ---- row: what a tile has always looked like ------------------------
    RowLayout {
        visible: !root.iconOnly && !root.stacked
        // Centred in the cell rather than stretched across it. The cell decides
        // the height now, and a layout that fills it hands every spare pixel to
        // whichever child happens to be a layout itself - which is how a tall
        // tile ended up with its text pinned to the top and a growing empty
        // band under it. Centred, a cell that is too short overflows instead,
        // and QuickSlot clips that to the cell's own edge.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceMd
        spacing: Metrics.spaceMd

        ShellIcon {
            Layout.preferredWidth: Metrics.iconLg + Metrics.spaceXs
            glyph: root.icon
            size: Metrics.iconLg
            color: root.checked ? Colors.accentForeground : Colors.mutedText
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXxs
            ShellText { Layout.fillWidth: true; text: root.title; role: "bodyLarge" }
            ShellText { Layout.fillWidth: true; text: root.subtitle; role: "small"; muted: true; visible: text.length > 0 }
        }

        ColumnLayout {
            spacing: Metrics.spaceXxs
            ShellToggle {
                visible: root.showToggle
                checked: root.checked
                enabledState: root.available
                onToggled: value => root.toggled(value)
            }
            ShellIcon {
                Layout.alignment: Qt.AlignRight
                visible: root.showChevron
                glyph: root.leavesPanel ? Icons.leavesPanel : Icons.forward
                size: Metrics.iconXs
                color: Colors.mutedText
            }
        }
    }
}
