import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// StatusNotifier items: left click activates, middle click secondary action,
// right click opens the application's menu inside the shell.
ColumnLayout {
    id: root
    spacing: Metrics.spaceSm
    property var menuItem: null

    // Escape's steps on this page (ControlCenter.escapeHandler): out of a
    // submenu, then out of the menu, before the page itself goes back.
    function stepBack() {
        if (root.menuItem === null) return false
        if (trayMenu.stack.length) trayMenu.stack = trayMenu.stack.slice(0, -1)
        else root.menuItem = null
        return true
    }

    EmptyState {
        Layout.fillWidth: true
        Layout.margins: Metrics.spaceSm
        visible: TrayService.items.length === 0
        icon: "󰍜"
        title: "No background apps"
    }

    Flow {
        Layout.fillWidth: true
        visible: root.menuItem === null
        spacing: Metrics.spaceSm
        Repeater {
            model: TrayService.items
            ShellCard {
                id: tile
                required property var modelData
                width: Metrics.trayIconCell
                height: Metrics.trayIconCell
                interactive: true
                hovered: tileMouse.containsMouse
                pressed: tileMouse.pressed && tileMouse.containsMouse
                readonly property string name: tile.modelData.tooltipTitle || tile.modelData.title || tile.modelData.id
                // What a left click does; the menu key does what the right
                // button does.
                function activate() {
                    if (tile.modelData.onlyMenu && tile.modelData.hasMenu) { root.menuItem = tile.modelData; return }
                    tile.modelData.activate()
                    PanelService.close()
                }
                function openMenu() { if (tile.modelData.hasMenu) root.menuItem = tile.modelData }
                // A stop for the panel's keys (NavLogic), like every tile.
                property bool focusOnTab: false
                activeFocusOnTab: focusOnTab
                Keys.onReturnPressed: tile.activate()
                Keys.onEnterPressed: tile.activate()
                Keys.onSpacePressed: tile.activate()
                Keys.onMenuPressed: tile.openMenu()
                Accessible.role: Accessible.Button
                Accessible.name: tile.name
                Accessible.onPressAction: tile.activate()
                FocusRing { active: tile.activeFocus; controlRadius: tile.radius }
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Metrics.spaceSm * 2
                    spacing: Metrics.spaceXs
                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Metrics.iconLg
                        Layout.preferredHeight: Metrics.iconLg
                        source: tile.modelData.icon
                        sourceSize.width: Metrics.iconLg * 2
                        sourceSize.height: Metrics.iconLg * 2
                    }
                    ShellText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.name
                        role: "caption"
                    }
                }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.RightButton || (tile.modelData.onlyMenu && tile.modelData.hasMenu)) tile.openMenu()
                        else if (event.button === Qt.MiddleButton) tile.modelData.secondaryActivate()
                        else tile.activate()
                    }
                    onWheel: event => tile.modelData.scroll(event.angleDelta.y, false)
                }
            }
        }
    }

    TrayMenu {
        id: trayMenu
        Layout.fillWidth: true
        visible: root.menuItem !== null
        handle: root.menuItem ? root.menuItem.menu : null
        title: root.menuItem ? (root.menuItem.tooltipTitle || root.menuItem.title || root.menuItem.id) : ""
        onDone: root.menuItem = null
        onTriggered: PanelService.close()
    }
}
