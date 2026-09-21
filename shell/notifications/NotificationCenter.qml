import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notifications/NotificationLogic.js" as Logic

// Super+N notification history with Do Not Disturb.
ShellPanel {
    id: root
    keyForward: search
    panelId: "notifications"
    placement: "top-right"
    // The corner, always. It used to follow the desktop clock like any other
    // hotkey panel, and in notch mode the clock is the notch in the middle of
    // the screen - so a list that belongs in the corner opened dead centre.
    followClock: false
    cardWidth: Metrics.notificationCenterWidth
    cardHeight: height - topOffset - Metrics.screenMargin

    // Group keys the user expanded ("N more").
    property var expanded: ({})
    property string query: ""
    readonly property var matching: Logic.search(NotificationService.history, query)
    readonly property var groups: Logic.group(matching)

    onWantedChanged: if (wanted) { NotificationService.markRead(); query = "" }

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            title: "Notifications"

            ShellButton {
                visible: NotificationService.history.length > 0
                text: "Clear all"; compact: true; variant: "ghost"
                onClicked: NotificationService.clearAll()
            }
        }

        ShellTextField {
            id: search
            Layout.fillWidth: true
            visible: NotificationService.history.length > 0
            icon: Icons.search
            placeholder: "Search notifications …"
            onTextChanged: root.query = text
        }

        QuickTile {
            Layout.fillWidth: true
            icon: NotificationService.dndActive ? "󰂛" : "󰂚"
            title: "Do Not Disturb"
            subtitle: NotificationService.dndLabel
            checked: NotificationService.dndActive
            onToggled: value => NotificationService.setDnd(value ? "manual" : "off")
            onActivated: PanelService.open("controlCenter", { page: "dnd" })
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                visible: root.matching.length === 0
                icon: root.query.length ? Icons.search : "󰂜"
                title: root.query.length ? "No notification matches" : "No notifications"
            }

            Flickable {
                id: list
                anchors.fill: parent
                visible: root.matching.length > 0
                clip: true
                contentHeight: groupColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: groupColumn
                    width: list.width
                    spacing: Metrics.spaceLg

                    Repeater {
                        model: root.groups

                        ColumnLayout {
                            id: groupItem
                            required property var modelData
                            readonly property bool isExpanded: root.expanded[modelData.key] === true
                            readonly property var shown: Logic.visibleItems(modelData, isExpanded)
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Metrics.spaceXs
                                spacing: Metrics.spaceSm
                                Image {
                                    visible: groupItem.modelData.icon.length > 0 && status === Image.Ready
                                    Layout.preferredWidth: Metrics.iconSm
                                    Layout.preferredHeight: Metrics.iconSm
                                    // appIcon is an icon name or an absolute file path.
                                    source: groupItem.modelData.icon.startsWith("/") ? "file://" + groupItem.modelData.icon
                                        : groupItem.modelData.icon.length ? Quickshell.iconPath(groupItem.modelData.icon, true) : ""
                                    sourceSize.width: Metrics.iconSm * 2
                                }
                                SectionLabel { text: groupItem.modelData.name }
                                ShellText { text: String(groupItem.modelData.items.length); role: "caption" }
                                Item { Layout.fillWidth: true }
                                ShellButton {
                                    visible: groupItem.modelData.items.length > groupItem.shown.length || groupItem.isExpanded && groupItem.modelData.items.length > 3
                                    text: groupItem.isExpanded ? "Show less" : (groupItem.modelData.items.length - groupItem.shown.length) + " more"
                                    compact: true; variant: "ghost"
                                    onClicked: {
                                        const next = Object.assign({}, root.expanded)
                                        next[groupItem.modelData.key] = !groupItem.isExpanded
                                        root.expanded = next
                                    }
                                }
                                ShellButton {
                                    readonly property string rule: NotificationService.appRule(groupItem.modelData.key)
                                    icon: rule === "mute" ? "󰂛" : rule === "critical" ? Icons.warning : "󰂚"
                                    compact: true
                                    variant: rule === "default" ? "ghost" : "surface"
                                    toolTip: rule === "mute" ? "Muted · click for always urgent"
                                        : rule === "critical" ? "Always urgent · click for normal"
                                        : "Normal · click to mute this app"
                                    onClicked: NotificationService.setAppRule(groupItem.modelData.key,
                                        rule === "default" ? "mute" : rule === "mute" ? "critical" : "default")
                                }
                                ShellButton {
                                    icon: Icons.close; compact: true; variant: "ghost"
                                    toolTip: "Dismiss all from this app"
                                    onClicked: groupItem.modelData.items.slice().forEach(notification => notification.dismiss())
                                }
                            }

                            Repeater {
                                model: groupItem.shown
                                NotificationCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    notification: modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
