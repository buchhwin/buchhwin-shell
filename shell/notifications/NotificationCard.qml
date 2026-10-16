import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notifications/NotificationLogic.js" as NotificationLogic

// One notification with icon, text, actions and close button.
ShellCard {
    id: root
    required property var notification
    property bool popup: false
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property var actions: notification ? notification.actions : []
    readonly property var defaultAction: actions.find(action => action.identifier === "default") || null
    readonly property var visibleActions: actions.filter(action => action.identifier !== "default").slice(0, 3)
    signal closed()

    // A card with a default action is a button-shaped card and takes the
    // One UI feedback like the control center's tiles; one without still
    // closes on a click, but keeps the hand cursor off and the dip too.
    interactive: defaultAction !== null
    hovered: hover.hovered
    pressed: mouse.pressed && mouse.containsMouse

    // A popup is a floating panel, a card in the notification centre is a
    // card: the semantic radii, not sizes off the ladder, and the content
    // sits the inset that radius was derived from.
    readonly property int inset: popup ? Metrics.panelPadding : Metrics.spaceLg
    // A popup is a floating panel and keeps the panel colour; in the centre
    // the card steps like any other card.
    color: popup ? Colors.panelFor("notificationPopups")
        : interactive && pressed ? pressedColor
        : interactive && hovered ? hoverColor : baseColor
    border.color: critical ? Colors.warning : popup ? Colors.panelBorder : Colors.border
    radius: popup ? Metrics.radiusPanel : Metrics.radiusCard
    implicitHeight: content.implicitHeight + inset * 2

    HoverHandler { id: hover }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: event => {
            if (event.button === Qt.RightButton) { const card = root; card.notification.dismiss(); if (card) card.closed(); return }
            root.activate()
        }
    }

    // The default action, from the pointer or the keys. Invoking an action can
    // retire the notification, and this card with it, before the next
    // statement runs ("ReferenceError: root is not defined"): what is needed
    // afterwards is taken first.
    function activate() {
        const card = root
        const action = root.defaultAction
        if (action) action.invoke()
        if (card) card.closed()
    }
    FocusRing { active: picture.activeFocus; controlRadius: root.radius }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.inset
        spacing: Metrics.spaceSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            Item {
                id: picture
                Layout.preferredWidth: Metrics.iconXl
                Layout.preferredHeight: Metrics.iconXl
                Layout.alignment: Qt.AlignTop
                // The click on the card from the keys: a stop for the panel's
                // keys (NavLogic stops on `focusOnTab`), only on a card with a
                // default action, and Return or Space invokes it. On the
                // picture rather than on the card, because NavLogic does not
                // look inside a stop and the card's own buttons have to stay
                // reachable; the ring goes round the card, which is what acts.
                property bool focusOnTab: false
                readonly property bool available: root.defaultAction !== null
                activeFocusOnTab: focusOnTab && available
                Keys.onReturnPressed: root.activate()
                Keys.onEnterPressed: root.activate()
                Keys.onSpacePressed: root.activate()
                Accessible.role: Accessible.Button
                Accessible.ignored: !available
                Accessible.name: root.notification.summary || root.notification.appName || "Notification"
                Accessible.description: root.notification.body
                Accessible.onPressAction: if (available) root.activate()
                Image {
                    id: image
                    anchors.fill: parent
                    source: NotificationLogic.picture(root.notification, name => Quickshell.iconPath(name, true))
                    sourceSize.width: Metrics.notificationImageSize
                    sourceSize.height: Metrics.notificationImageSize
                    fillMode: Image.PreserveAspectFit
                    // A theme icon (image://icon) on the GUI thread although
                    // it loads off it too (TileContent): one icon per card,
                    // and asynchronously the bell below would stand in its
                    // place until it arrives, as the popup comes in. Files
                    // and pictures load off it.
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
                        toolTip: "Dismiss"
                        // The compact size the notification centre's group
                        // buttons have, not a step under it: a 26 px close on
                        // each card below a 30 px "Dismiss all" read as two
                        // sizes of the same button.
                        icon: Icons.close; variant: "ghost"; compact: true
                        onClicked: { const card = root; card.notification.dismiss(); if (card) card.closed() }
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
                    // See the card's MouseArea: invoke() can take the card away.
                    onClicked: {
                        const card = root
                        modelData.invoke()
                        if (card) card.closed()
                    }
                }
            }
        }
    }
}
