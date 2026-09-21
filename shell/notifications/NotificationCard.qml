import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.theme
import qs.services
import qs.shell.components

// One notification with icon, text, actions and close button.
ShellCard {
    id: root
    required property var notification
    property bool popup: false
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property var actions: notification ? notification.actions : []
    readonly property var defaultAction: actions.find(action => action.identifier === "default") || null
    readonly property var visibleActions: actions.filter(action => action.identifier !== "default").slice(0, 3)
    readonly property bool hovered: hover.hovered
    signal closed()

    color: popup ? Colors.panelFor("notificationPopups") : Colors.surface
    border.color: critical ? Colors.warning : popup ? Colors.panelBorder : Colors.border
    radius: popup ? Metrics.radiusXl : Metrics.radiusLg
    implicitHeight: content.implicitHeight + Metrics.spaceLg * 2

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: event => {
            if (event.button === Qt.RightButton) { root.notification.dismiss(); root.closed(); return }
            if (root.defaultAction) root.defaultAction.invoke()
            root.closed()
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Metrics.spaceLg
        spacing: Metrics.spaceSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            Item {
                Layout.preferredWidth: Metrics.iconXl
                Layout.preferredHeight: Metrics.iconXl
                Layout.alignment: Qt.AlignTop
                Image {
                    id: image
                    anchors.fill: parent
                    source: root.notification.image || (root.notification.appIcon ? Quickshell.iconPath(root.notification.appIcon, true) : "")
                    sourceSize.width: Metrics.iconXl * 2
                    sourceSize.height: Metrics.iconXl * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: !String(source).startsWith("image://")
                    visible: status === Image.Ready
                }
                ShellIcon { anchors.centerIn: parent; visible: image.status !== Image.Ready; glyph: root.critical ? Icons.warning : "󰂚"; size: Metrics.iconLg; color: root.critical ? Colors.warning : Colors.accentForeground }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs
                RowLayout {
                    Layout.fillWidth: true
                    ShellText { Layout.fillWidth: true; text: root.notification.appName || "Notification"; role: "caption" }
                    ShellButton {
                        icon: Icons.close; variant: "ghost"; compact: true
                        implicitHeight: Metrics.controlHeightSm - Metrics.spaceXs
                        onClicked: { root.notification.dismiss(); root.closed() }
                    }
                }
                ShellText { Layout.fillWidth: true; text: root.notification.summary; role: "bodyLarge"; visible: text.length > 0 }
                ShellText {
                    Layout.fillWidth: true
                    text: root.notification.body
                    visible: text.length > 0
                    muted: true
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 6
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.visibleActions.length > 0
            spacing: Metrics.spaceSm
            Repeater {
                model: root.visibleActions
                ShellButton {
                    required property var modelData
                    Layout.fillWidth: true
                    compact: true
                    text: modelData.text
                    onClicked: { modelData.invoke(); root.closed() }
                }
            }
        }
    }
}
