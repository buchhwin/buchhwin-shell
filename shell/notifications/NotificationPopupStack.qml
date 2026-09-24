import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.theme
import qs.services
import "../../services/origin/OriginLogic.js" as Origin
import "../../services/notifications/NotificationLogic.js" as Logic

// Up to three popups directly below the clock on the focused monitor - or out
// of the notch, when there is one: a notification belongs to the notch, and
// that is what a notch is for.
PanelWindow {
    id: window
    readonly property var targetScreen: PanelService.focusedScreen()
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
    readonly property var notch: LayoutService.notchRect(screenName)
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
    readonly property var place: fromNotch !== null ? fromNotch
        : Origin.atTopRight(Metrics.notificationWidth, targetScreen ? targetScreen.width : 0,
                            cornerTop, Metrics.screenMargin)

    // The notch can be the display itself, and then the newest popup appears
    // *in* it and this stack stays away. Only the newest: the notch is a strip
    // and a stack of three in it would be the overview with notifications in
    // it, which is the thing this replaces.
    readonly property var newest: NotificationService.popups.length
        ? NotificationService.popups[0] : null
    readonly property bool inNotch: newest !== null
        && !PanelService.isOpen("notifications")
        && NotchService.takesDisplay("notification", screenName)
    onInNotchChanged: publish()
    onNewestChanged: publish()
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
            shown ? Logic.notchContent(notification, name => Quickshell.iconPath(name, true)) : null)
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

    ColumnLayout {
        id: column
        width: parent.width
        spacing: Metrics.spaceSm

        Repeater {
            model: NotificationService.popups
            NotificationCard {
                id: card
                required property var modelData
                Layout.fillWidth: true
                notification: modelData
                popup: true
                onClosed: NotificationService.hidePopup(modelData)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

                // It travels out of the notch rather than fading in below it:
                // drawn where it rests and carried back onto the notch while
                // it appears, which is the motion a panel growing out of a
                // pill already makes. `opacity` is the progress, so there is
                // one animation rather than three that have to agree.
                readonly property var homeward: window.fromNotch && Animations.motionEnabled
                    ? Origin.offsetTo(window.notch,
                                      { x: window.fromNotch.x, y: window.fromNotch.y + card.y,
                                        width: card.width, height: card.height })
                    : null
                transformOrigin: Item.Center
                scale: card.homeward ? Effects.hoverScaleFrom + (1 - Effects.hoverScaleFrom) * card.opacity : 1
                transform: Translate {
                    x: card.homeward ? card.homeward.x * (1 - card.opacity) : 0
                    y: card.homeward ? card.homeward.y * (1 - card.opacity) : 0
                }

                Timer {
                    readonly property int timeout: card.modelData.expireTimeout > 0
                        ? card.modelData.expireTimeout : SettingsService.value("notifications.popupTimeoutMs")
                    interval: timeout
                    running: !card.critical && !card.hovered
                    onTriggered: NotificationService.hidePopup(card.modelData)
                }
            }
        }
    }
}
