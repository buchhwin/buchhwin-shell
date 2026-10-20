import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.theme
import qs.services
import "../../services/origin/OriginLogic.js" as Origin
import "../../services/notifications/NotificationLogic.js" as Logic
import "../components/PanelPlaceLogic.js" as Place

// Up to three popups directly below the clock on the focused monitor - or out
// of the notch, when there is one: a notification belongs to the notch, and
// that is what a notch is for. With a fullscreen window on the focused
// monitor and another one free, on that one instead
// (NotificationService.popupScreenName).
PanelWindow {
    id: window
    readonly property var targetScreen: NotificationService.popupScreenName.length
        ? (Quickshell.screens.find(item => item.name === NotificationService.popupScreenName) || PanelService.focusedScreen())
        : PanelService.focusedScreen()
    readonly property var clockRect: LayoutService.clockRect(targetScreen ? targetScreen.name : "")
    readonly property bool clockOnRight: clockRect !== null && targetScreen !== null && clockRect.x > targetScreen.width / 2
    readonly property real barBottom: LayoutService.barBottom(targetScreen ? targetScreen.name : "")
    // The collapsed notch on this screen, or null: another desktop mode, or a
    // notch hidden behind a fullscreen window, reports none and the popups go
    // back to the corner they have always used.
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    // What they come out of: the notch, or - in bar mode - the notification
    // widget they belong to, or the bar's end when that widget is not on it.
    readonly property string barEdge: LayoutService.barEdge(screenName)
    readonly property bool barAtBottom: barEdge === "bottom"
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    // Where the bar says notifications open. "widget" is what it always did -
    // out of the notification pill when there is one, out of the bar's end
    // when there is not - and the other three pin them to a place regardless.
    // Separate from the panels' own spot on purpose: wanting the control
    // center under your hand and the notifications out of the way is one
    // wish, not two conflicting ones.
    readonly property string spot: LayoutService.barNotificationSpot()
    readonly property var barPlace: Origin.barSpot(LayoutService.barBottom(screenName),
                          targetScreen ? targetScreen.width : 0,
                          spot === "widget" ? "end" : spot, Metrics.screenMargin,
                          barEdge, targetScreen ? targetScreen.height : 0)
    readonly property var notch: Origin.notchBody(LayoutService.notchRect(screenName), NotchService.states[screenName])
        || (spot === "widget" ? LayoutService.barItemRect(screenName, "notificationIndicator") : null)
        || barPlace
    // Downwards from a top edge, upwards from a bottom one, sideways from a
    // bar that runs down the screen: the stack grows away from the thing it
    // came out of in every case.
    readonly property var fromNotch: barVertical
        ? Origin.beside(notch, Metrics.notificationWidth, window.implicitHeight,
                        targetScreen ? targetScreen.width : 0,
                        targetScreen ? targetScreen.height : 0,
                        Metrics.screenMargin, Metrics.spaceSm, barEdge === "right")
        : barAtBottom
        ? Origin.above(notch, Metrics.notificationWidth, window.implicitHeight,
                       targetScreen ? targetScreen.width : 0,
                       Metrics.screenMargin, Metrics.spaceSm)
        : Origin.under(notch, Metrics.notificationWidth,
                       targetScreen ? targetScreen.width : 0,
                       Metrics.screenMargin, Metrics.spaceSm)
    // The corner they have always used, when there is no notch to come out of.
    readonly property real cornerTop: Math.max(
        clockOnRight ? clockRect.y + clockRect.height + Metrics.spaceSm : Metrics.screenMargin,
        // A bar on a side takes nothing off the top, so it must not be
        // subtracted from it.
        !barAtBottom && !barVertical && window.barBottom >= 0 ? window.barBottom + Metrics.spaceSm : 0)
    readonly property var settled: fromNotch !== null ? fromNotch
        : Origin.atTopRight(Metrics.notificationWidth, targetScreen ? targetScreen.width : 0,
                            cornerTop, Metrics.screenMargin)
    // The dock beyond the bar, or beside the corner: the stack stands clear
    // of it rather than over it - a bottom bar's popups came up right where
    // the dock stands beyond it, and the corner ones covered a right dock
    // (the OSD already did this). Read only while the
    // dock is on, so a popup never starts the dock's service (pitfall 101).
    readonly property var dockState: SettingsService.value("dock.enabled") === true
        ? Object.assign({ position: DockService.position, shown: DockService.shownOn[screenName] === true,
             reach: DockService.reachOn[screenName] || 0 },
           Place.dockSpan(DockService.bodies[screenName], DockService.position,
                          targetScreen ? targetScreen.x : 0, targetScreen ? targetScreen.y : 0))
        : null
    readonly property var place: Place.clearOfDock(settled, Metrics.notificationWidth, window.implicitHeight,
        targetScreen ? targetScreen.width : 0, targetScreen ? targetScreen.height : 0,
        dockState, barEdge, barBottom, Metrics.spaceSm)

    // The notch can be the display itself, and then the newest popup appears
    // *in* it and this stack stays away. Only the newest: the notch is a strip
    // and a stack of three in it would be the overview with notifications in
    // it, which is the thing this replaces. The notch's click holds the same
    // one (NotificationService.notchPopup).
    readonly property var newest: NotificationService.notchPopup
    readonly property bool inNotch: newest !== null
        && !PanelService.isOpen("notifications")
        && NotchService.takesDisplay("notification", screenName)
    onInNotchChanged: publish()
    onNewestChanged: publish()
    // The notch shows what `publish` took from the notification at that
    // moment; a sender that replaces it in place (replaces_id) changes the
    // object, and the notch kept the old words while the card had the new.
    Connections {
        target: window.newest
        function onSummaryChanged() { window.publish() }
        function onBodyChanged() { window.publish() }
        function onImageChanged() { window.publish() }
        function onAppIconChanged() { window.publish() }
        function onUrgencyChanged() { window.publish() }
    }
    // Worked out from what `newest` is *now*, not from `inNotch`: this runs
    // from `onNewestChanged`, and `inNotch` is a binding on `newest` that has
    // not been re-evaluated yet when the handler fires - so the popup that
    // had just left the notch still read as in it, and `newest.image` threw
    // on null on the way out. `onInNotchChanged` publishes again once the
    // binding has caught up, and both arrive at the same answer.
    function publish() {
        const notification = newest
        const shown = notification !== null && notification !== undefined
            && !PanelService.isOpen("notifications")
            && NotchService.takesDisplay("notification", screenName)
        NotchService.setDisplay("notification", screenName,
            shown ? Logic.notchContent(notification, name => Quickshell.iconPath(name, true),
                                       NotificationService.isCritical(notification),
                                       NotificationService.concealed) : null)
    }
    // A share that starts or ends while the notch shows one: its words go or
    // come back with it.
    Connections {
        target: NotificationService
        function onConcealedChanged() { window.publish() }
    }

    screen: targetScreen
    // Nothing until there is somewhere to be: a place worked out from a screen
    // whose width is not known yet is the left-hand margin.
    visible: !inNotch && place !== null && NotificationService.popups.length > 0 && !PanelService.isOpen("notifications")
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // One pair of anchors for the surface's whole life; only the margins move.
    // A mapped layer surface does not reliably take a new anchor - the bar
    // remaps itself for exactly that reason.
    anchors { top: true; left: true }
    margins {
        top: window.place ? window.place.y : 0
        left: window.place ? window.place.x : 0
    }
    implicitWidth: Metrics.notificationWidth
    implicitHeight: Math.max(1, column.implicitHeight)
    WlrLayershell.namespace: "buchhwin-notification-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard only while a popup has a reply field (KDE Connect's
    // messages) and the pointer is over the popups, or while a reply is
    // typed. Hyprland gives a layer that takes the keys on demand the focus
    // the moment it maps, and again whenever the pointer moves over it: a
    // stack that came up asking for the keys took them from the window
    // being typed in. Asked for once the pointer is here, they come with
    // its next move, and go back to that window when it leaves.
    readonly property bool hasReplies: NotificationService.popups.some(item => item && item.hasInlineReply === true)
        && !NotificationService.concealed
    // The card whose reply field has the keys, or null.
    property var replyCard: null
    readonly property bool takesReplies: hasReplies && (stackHover.hovered || replyCard !== null)
    WlrLayershell.keyboardFocus: takesReplies ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    ColumnLayout {
        id: column
        width: parent.width
        spacing: Metrics.spaceSm

        // On the cards' parent: an ancestor keeps the hover while the pointer
        // is over a card's own handlers and buttons (pitfall 100).
        HoverHandler { id: stackHover }

        Repeater {
            // A ScriptModel, not the array itself: a Repeater on a plain array
            // throws every delegate away and builds them again whenever the
            // array is assigned, so closing the middle one of three made the
            // other two fade in from nothing a second time. The model diffs by
            // identity and keeps the cards that are still there.
            model: ScriptModel { values: NotificationService.popups }
            NotificationCard {
                id: card
                required property var modelData
                Layout.fillWidth: true
                notification: modelData
                popup: true
                onClosed: NotificationService.hidePopup(modelData)
                onReplyingChanged: {
                    if (replying) window.replyCard = card
                    else if (window.replyCard === card) window.replyCard = null
                }
                Component.onDestruction: if (window.replyCard === card) window.replyCard = null
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

                // It travels out of the notch rather than fading in below it:
                // drawn where it rests and carried back onto the notch while
                // it appears, which is the motion a panel growing out of a
                // pill already makes. `opacity` is the progress, so there is
                // one animation rather than three that have to agree.
                // From where the stack really stands (`place`, which keeps off
                // the dock), so the card still lands on its origin.
                readonly property var homeward: window.fromNotch && window.place && Animations.motionEnabled
                    ? Origin.offsetTo(window.notch,
                                      { x: window.place.x, y: window.place.y + card.y,
                                        width: card.width, height: card.height })
                    : null
                transformOrigin: Item.Center
                scale: card.homeward ? Effects.hoverScaleFrom + (1 - Effects.hoverScaleFrom) * card.opacity : 1
                transform: Translate {
                    x: card.homeward ? card.homeward.x * (1 - card.opacity) : 0
                    y: card.homeward ? card.homeward.y * (1 - card.opacity) : 0
                }

                Timer {
                    id: expiry
                    readonly property int timeout: card.modelData.expireTimeout > 0
                        ? card.modelData.expireTimeout : SettingsService.value("notifications.popupTimeoutMs")
                    interval: timeout
                    running: !card.critical && !card.hovered && !card.replying
                        && NotificationService.heldPopup !== card.modelData
                    onTriggered: NotificationService.hidePopup(card.modelData)
                }
                // Replaced in place while it is up (a new message in the same
                // thread): the new words get the whole time again. Only a
                // running timer - one held by the pointer or the notch stays
                // held.
                Connections {
                    target: card.modelData
                    function onSummaryChanged() { if (expiry.running) expiry.restart() }
                    function onBodyChanged() { if (expiry.running) expiry.restart() }
                }
            }
        }
    }
}
