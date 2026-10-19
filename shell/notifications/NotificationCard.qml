import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notifications/NotificationLogic.js" as NotificationLogic

// One notification with icon, text, actions and close button. Also one of
// the shell's own notices (NotificationService.postNotice) and one kept
// from before a restart (`earlier`), which has nothing to act on.
ShellCard {
    id: root
    required property var notification
    property bool popup: false
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property var actions: notification && notification.actions ? notification.actions : []
    readonly property var defaultAction: actions.find(action => action.identifier === "default") || null
    readonly property var visibleActions: actions.filter(action => action.identifier !== "default").slice(0, 3)
    // What it is from: a browser's site as its installed web app ("Microsoft
    // Teams (PWA)" and its icon, not "Brave"), the origin another sender
    // named beside its name (NotificationService.describe).
    readonly property var source: NotificationService.describe(notification)
    readonly property bool earlier: notification && notification.earlier === true
    // A popup while the screen is shared shows who and what, not the words
    // or the sender's picture (NotificationService.concealed).
    readonly property bool concealed: popup && NotificationService.concealed
    // KDE Connect's text messages take the answer here.
    readonly property bool replyShown: !concealed && !earlier && notification && notification.hasInlineReply === true
    // The reply field while there is one (`replyShown`), and whether it has
    // the keys: the popup's timer waits then, as it does under the pointer.
    readonly property var replyField: replyRow.item ? replyRow.item.field : null
    readonly property bool replying: replyField !== null && replyField.inputActiveFocus
    // When it came (ms since the epoch, 0 unknown) and the clock it is read
    // against, for the centre's cards: "Build finished" from this morning
    // and one from a minute ago looked the same. A popup has just come and
    // says nothing.
    property real receivedAt: 0
    property real now: 0
    readonly property string age: popup ? "" : NotificationLogic.ageLabel(receivedAt, now, SettingsService.twelveHourClock)
    signal closed()

    // A card with a default action is a button-shaped card and takes the
    // One UI feedback like the control center's tiles; so is a web app's,
    // which opens the web app. One without either still closes on a click,
    // but keeps the hand cursor off and the dip too.
    interactive: defaultAction !== null || NotificationService.opensSource(notification)
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
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: event => {
            if (event.button === Qt.RightButton) { root.dismiss(); return }
            root.activate()
        }
    }

    // The ×, a right-click: a notification leaves the history (its sender
    // hears it closed), a kept one from before leaves the file. Dismissing
    // can retire this card before the next statement runs (pitfall 20).
    function dismiss() {
        const card = root
        const notification = root.notification
        if (root.earlier) NotificationService.forgetEarlier(notification)
        else if (notification) notification.dismiss()
        if (card) card.closed()
    }

    // The default action, from the pointer or the keys - or a web app's
    // window to the front (NotificationService.activate). Invoking an action
    // can retire the notification, and this card with it, before the next
    // statement runs ("ReferenceError: root is not defined"): what is needed
    // afterwards is taken first.
    function activate() {
        const card = root
        const action = root.defaultAction
        NotificationService.activate(root.notification, action)
        if (card) card.closed()
    }

    // The answer typed into the card, sent to the sender, which closes the
    // notification as a rule; the card goes either way.
    function sendReply() {
        const card = root
        const notification = root.notification
        const field = root.replyField
        const answer = field ? field.text.trim() : ""
        if (!answer.length || !notification || notification.hasInlineReply !== true) return
        field.text = ""
        notification.sendInlineReply(answer)
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
                readonly property bool available: root.interactive
                activeFocusOnTab: focusOnTab && available
                Keys.onReturnPressed: root.activate()
                Keys.onEnterPressed: root.activate()
                Keys.onSpacePressed: root.activate()
                Accessible.role: Accessible.Button
                Accessible.ignored: !available
                Accessible.name: root.notification.summary || root.source.name || "Notification"
                Accessible.description: root.concealed ? "" : root.notification.body
                Accessible.onPressAction: if (available) root.activate()
                Image {
                    id: image
                    anchors.fill: parent
                    // The sender's own picture (an avatar) else the app's -
                    // the web app's for a browser's site; only the app's
                    // while the screen is shared.
                    source: NotificationLogic.picture({ image: root.concealed ? "" : root.notification.image,
                                                        appIcon: root.source.icon },
                                                      name => Quickshell.iconPath(name, true))
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
                    ShellText {
                        Layout.fillWidth: true
                        text: [root.source.name || "Notification", root.source.note, root.age]
                            .filter(part => part && part.length).join(" · ")
                        role: "caption"
                        elide: Text.ElideRight
                    }
                    ShellButton {
                        toolTip: "Dismiss"
                        // The compact size the notification centre's group
                        // buttons have, not a step under it: a 26 px close on
                        // each card below a 30 px "Dismiss all" read as two
                        // sizes of the same button.
                        icon: Icons.close; variant: "ghost"; compact: true
                        onClicked: root.dismiss()
                    }
                }
                ShellText { Layout.fillWidth: true; text: root.notification.summary; role: "bodyLarge"; visible: text.length > 0 }
                ShellText {
                    Layout.fillWidth: true
                    text: root.concealed ? "" : root.notification.body
                    visible: text.length > 0
                    muted: true
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 6
                }
                // In the body's place while a share hides it: a title with
                // nothing under it looked broken. The body is in the centre.
                ShellText {
                    Layout.fillWidth: true
                    visible: root.concealed && root.notification.body.length > 0
                    text: "Hidden while you share your screen"
                    role: "small"
                    muted: true
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

        // Built only on a card that takes an answer: a text field under
        // every card in the centre would be one for each notification, for
        // the few that are text messages.
        Loader {
            id: replyRow
            Layout.fillWidth: true
            active: root.replyShown
            visible: active
            sourceComponent: RowLayout {
                readonly property alias field: reply
                spacing: Metrics.spaceSm
                ShellTextField {
                    id: reply
                    Layout.fillWidth: true
                    placeholder: root.notification && root.notification.inlineReplyPlaceholder
                        ? root.notification.inlineReplyPlaceholder : "Reply"
                    accessibleName: "Reply"
                    onAccepted: root.sendReply()
                }
                ShellButton {
                    toolTip: "Send"
                    icon: Icons.send
                    compact: true
                    enabledState: reply.text.trim().length > 0
                    onClicked: root.sendReply()
                }
            }
        }
    }
}
