import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets as QsWidgets
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/PreviewLogic.js" as Preview
import "../../services/overview/OverviewLogic.js" as Overview

// An app's windows over the dock (Settings > Dock > Window previews): the
// pointer resting on a running app shows a live capture of each of its
// windows with its title, where its name would show. A click brings the
// window to the front (a minimized one back to its workspace), a middle
// click closes it. DockService says which app and where its icon is
// (`previewScreen`, `previewKey`, `previewIcon`); this only draws.
//
// Its own surface, made by Dock.qml's LazyLoader while a strip is up and let
// go after its fade, so the captures - a texture about each window's size -
// exist only then. One size for as long as it is up (PreviewLogic.js and
// testing.md pitfall 57: the widest strip; the strip itself moves inside it
// from app to app), against the dock's body with the strip a bridge off it,
// and the input mask is the strip and the bridge. It never takes the
// keyboard: the window under the dock keeps the focus. The pointer on it is
// told to the service from the window itself (pitfall 100: hover stays with
// ancestors), which keeps the strip and the dock up meanwhile.
PanelWindow {
    id: window

    readonly property string screenName: DockService.previewScreen
    readonly property var target: Quickshell.screens.find(item => item.name === screenName) || null
    readonly property var room: target ? { width: target.width, height: target.height } : null
    readonly property var app: DockService.previewItem
    readonly property var windows: app ? app.windows : []
    readonly property string edge: DockService.position
    // A card as the switcher draws one: the capture, its title under it.
    readonly property real cardHeight: Metrics.spaceSm * 3 + Metrics.switcherPreviewHeight + titleMetrics.implicitHeight
    readonly property var card: ({ width: Metrics.switcherCardWidth, height: cardHeight })
    readonly property var size: Preview.surfaceSize(edge, card, Metrics.spaceSm, Metrics.spaceSm, Metrics.dockMenuWindows,
                                                    room, Metrics.dockLabelGap)
    readonly property var strip: Preview.stripSize(windows.length, card, Metrics.spaceSm, Metrics.spaceSm, Metrics.dockMenuWindows)
    // A magnifying dock's icons grow past its body (Dock.qml's mask, the same
    // sum): the strip stands off them.
    readonly property real grow: DockService.magnifies ? Math.ceil(DockService.iconSize * (Metrics.dockMagnifyScale - 1)) : 0
    readonly property var place: Preview.place(edge, DockService.previewIcon, Preview.grown(edge, DockService.placeOf(screenName), grow),
                                               size, strip, room, Metrics.dockLabelGap)
    // Faded in once it is there, out before it goes (DockService.previewShown).
    property bool ready: false
    Component.onCompleted: ready = true
    readonly property bool showing: ready && DockService.previewShown

    function toplevelFor(address) {
        const key = Overview.normalizeAddress(address)
        return Hyprland.toplevels.values.find(item => Overview.normalizeAddress(item.address) === key) || null
    }

    screen: target
    visible: target !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true }
    margins { top: place.y; left: place.x }
    implicitWidth: size.width
    implicitHeight: size.height
    WlrLayershell.namespace: "buchhwin-dock-preview"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: maskArea }
    Item {
        id: maskArea
        x: window.place.mask.x
        y: window.place.mask.y
        width: window.place.mask.width
        height: window.place.mask.height
    }
    HoverHandler { onHoveredChanged: DockService.previewPointer(hovered) }

    // The titles' height, for the cards'.
    ShellText { id: titleMetrics; visible: false; text: "Ag"; role: "small" }

    // The tooltips' look, as the name it stands in for: a solid surface and
    // the panels' border.
    Rectangle {
        id: frame
        x: window.place.stripX
        y: window.place.stripY
        width: Math.min(window.strip.width, window.size.width)
        height: window.strip.height
        radius: Metrics.panelRadius(Metrics.spaceSm)
        color: Colors.solidSurface
        border.width: Metrics.borderWidth
        border.color: Colors.panelBorder
        opacity: window.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: window.showing ? Animations.popupOpen : Animations.popupClose; easing.type: window.showing ? Animations.easingEnter : Animations.easingExit } }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: Metrics.spaceSm
            orientation: ListView.Horizontal
            spacing: Metrics.spaceSm
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Keyed by address: the dock hands its windows on as the same
            // objects while they stay (testing.md pitfall 76).
            model: ScriptModel { values: window.windows; objectProp: "address" }
            ScrollFeel { view: list }

            delegate: ShellCard {
                id: cardItem
                required property var modelData
                readonly property var toplevel: window.toplevelFor(modelData.address)
                readonly property string title: DockService.titleOf(modelData.address)
                readonly property bool minimized: modelData.minimized === true
                width: Metrics.switcherCardWidth
                height: window.cardHeight
                level: 2
                interactive: true
                hovered: hover.hovered
                pressed: cardMouse.pressed && cardMouse.containsMouse

                HoverHandler { id: hover }

                Rectangle {
                    id: shot
                    x: Metrics.spaceSm
                    y: Metrics.spaceSm
                    width: parent.width - Metrics.spaceSm * 2
                    height: Metrics.switcherPreviewHeight
                    radius: Metrics.radiusInner
                    color: Colors.surface1
                    border.width: Metrics.borderWidth
                    border.color: Colors.border
                    clip: true

                    // Inside the frame's rounding: a Rectangle does not clip to
                    // its radius (pitfall 4).
                    QsWidgets.ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: Metrics.borderWidth
                        radius: Math.max(0, shot.radius - Metrics.borderWidth)
                        color: "transparent"
                        opacity: cardItem.minimized ? Effects.mutedOpacity : 1

                        ScreencopyView {
                            id: capture
                            anchors.fill: parent
                            captureSource: cardItem.toplevel ? cardItem.toplevel.wayland : null
                            constraintSize: Qt.size(width, height)
                            live: window.showing
                        }
                        ShellIcon {
                            anchors.centerIn: parent
                            visible: !capture.hasContent
                            glyph: Icons.window
                            size: Metrics.iconLg
                            color: Colors.mutedText
                        }
                    }

                    // Where a minimized one is: it comes back there.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Metrics.spaceXs
                        visible: cardItem.minimized
                        width: minimizedLabel.implicitWidth + Metrics.spaceSm
                        height: minimizedLabel.implicitHeight + Metrics.spaceXxs * 2
                        radius: Metrics.radiusPill
                        color: Colors.pill
                        border.width: Metrics.borderWidth
                        border.color: Colors.panelBorder
                        ShellText {
                            id: minimizedLabel
                            anchors.centerIn: parent
                            text: "Minimized"
                            role: "caption"
                            color: Colors.text
                        }
                    }
                }

                ShellText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Metrics.spaceSm
                    horizontalAlignment: Text.AlignHCenter
                    text: cardItem.title.length ? cardItem.title : window.app ? window.app.name : "Window"
                    role: "small"
                    elide: Text.ElideRight
                    color: cardItem.hovered ? Colors.text : Colors.mutedText
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        const address = cardItem.modelData.address
                        DockService.hidePreview()
                        if (event.button === Qt.MiddleButton) DockService.closeWindow(address)
                        else DockService.focusWindow(address)
                    }
                }

                Accessible.role: Accessible.Button
                Accessible.name: (cardItem.minimized ? "Minimized: " : "") + (cardItem.title.length ? cardItem.title : "Window")
            }
        }
    }
}
