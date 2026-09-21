import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "pages"
import "../../services/arrange/ArrangeLogic.js" as Arrange

// Super+O control center: quick tiles, sliders, media, audio and status chips
// with detail pages for network, Bluetooth, audio, DND, power, drives and tray.
// The pencil in the header arranges the tiles in place (see OverviewPage).
ShellPanel {
    id: root
    panelId: "controlCenter"
    placement: "top-right"
    // The panel's own size is dragged from its corner while the tiles are
    // being arranged, the way the notch's overview is. Both ends are real
    // clamps: the panel can neither grow past the room below its own top edge,
    // which took the grip out of reach with it, nor shrink to a height at
    // which its body computed to nothing.
    readonly property real minPanelHeight: header.height + Metrics.quickGridUnit
        + Metrics.panelPadding * 2 + Metrics.panelGap + Metrics.spaceXs
    readonly property var sizeBounds: ({ minWidth: Metrics.controlCenterMinWidth,
                                         maxWidth: Metrics.controlCenterMaxWidth,
                                         width: Metrics.controlCenterWidth,
                                         minHeight: minPanelHeight,
                                         room: roomBelowTop })
    readonly property var box: Arrange.panelBox(SettingsService.value("desktop.quickWidth"),
                                              SettingsService.value("desktop.quickHeight"),
                                              sizeBounds)
    // While the grip is being pulled the card takes the size under the hand,
    // so the panel resizes live and the tiles reflow as it goes; the release
    // is only when it is written down.
    property bool sizing: false
    property real dragWidth: 0
    property real dragHeight: 0
    cardWidth: sizing ? dragWidth : box.width
    // The dragged height belongs to the overview. Every detail page used to
    // inherit it, so a short page left a dead area and a panel shrunk to fit
    // eight tiles had permanently shrunk the network page's scroll region.
    cardHeight: page.length ? -1 : sizing ? dragHeight : box.height
    property string page: ""

    onWantedChanged: {
        if (wanted) {
            page = PanelService.args.page || ""
            BrightnessService.refresh()
            NetworkService.refresh()
            MprisService.trackers += 1
        } else {
            MprisService.trackers = Math.max(0, MprisService.trackers - 1)
        }
    }
    // The page is let go once the panel is really gone, not when it starts to
    // close: the card is still drawn through the close animation, so clearing
    // it any earlier flashes the overview page back for those frames.
    onShownChanged: if (!shown) {
        page = ""
        LayoutService.quickEditing = false
        // A dropped pointer grab never releases the grip, and the flag used to
        // survive the panel closing - the card then reopened pinned to a drag
        // size nobody was dragging any more.
        sizing = false
    }
    Connections {
        target: PanelService
        function onArgsChanged() { if (root.wanted) root.page = PanelService.args.page || "" }
    }

    onEscapePressed: if (page.length) { page = ""; PanelService.open("controlCenter") }

    // The grip that sizes the panel, on the corner that grows: the card is
    // anchored top right, so its bottom left is the one that moves. On the
    // overlay rather than in the card, which clips. Only on the overview,
    // because only the overview keeps a dragged height.
    Rectangle {
        parent: root.overlay
        visible: LayoutService.quickEditing && root.page.length === 0
        x: root.cardRect.x + Metrics.spaceXxs
        y: root.cardRect.y + root.cardRect.height - height - Metrics.spaceXxs
        width: Metrics.iconSm
        height: width
        radius: width / 2
        // Accent and opaque, like the handle on every tile: at 11.5 % white it
        // vanished on a light panel.
        color: grip.pulling || grip.containsMouse ? Colors.accentHover : Colors.accent
        border.width: Metrics.borderWidth
        border.color: Colors.accent

        MouseArea {
            id: grip
            anchors.fill: parent
            anchors.margins: -Metrics.spaceXs
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeBDiagCursor
            readonly property bool pulling: root.sizing
            // The corner the card is anchored by, taken once at the press. The
            // live edge cannot be used: ShellPanel anchors this panel to the
            // desktop clock whenever that clock sits in the left two thirds,
            // and then both edges move with the width, so the drag chased its
            // own result - the gearing halved and it never landed where it was
            // let go.
            property real fromRight: 0
            property real fromTop: 0
            property real pressX: 0
            property real pressY: 0
            property bool moved: false
            onPressed: mouse => {
                const point = mapToItem(root.overlay, mouse.x, mouse.y)
                fromRight = root.cardRect.x + root.cardRect.width
                fromTop = root.cardRect.y
                pressX = point.x
                pressY = point.y
                moved = false
                root.dragWidth = root.cardRect.width
                root.dragHeight = root.cardRect.height
                root.sizing = true
            }
            onPositionChanged: mouse => {
                if (!root.sizing) return
                const point = mapToItem(root.overlay, mouse.x, mouse.y)
                if (!moved) {
                    if (Math.abs(point.x - pressX) + Math.abs(point.y - pressY) < Metrics.dragThreshold) return
                    moved = true
                }
                const wanted = Arrange.panelDragTo(point.x, point.y,
                                                 { right: fromRight, top: fromTop }, root.sizeBounds)
                root.dragWidth = wanted.width
                root.dragHeight = wanted.height
            }
            onReleased: {
                if (!root.sizing) return
                root.sizing = false
                // A press that never moved is not a resize. It used to write
                // the size the card happened to be clamped to at that moment,
                // which on a narrower screen silently shrank the stored one.
                if (moved) LayoutService.quickResize(root.dragWidth, root.dragHeight)
                moved = false
            }
            onCanceled: {
                root.sizing = false
                moved = false
            }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.panelGap

        PanelHeader {
            id: header
            Layout.fillWidth: true
            Layout.bottomMargin: Metrics.spaceXs
            showBack: root.page.length > 0
            onBackPressed: root.page = ""
            title: root.page === "network" ? "Network"
                : root.page === "bluetooth" ? "Bluetooth"
                : root.page === "audio" ? "Audio"
                : root.page === "dnd" ? "Do Not Disturb"
                : root.page === "power" ? "Power"
                : root.page === "drives" ? "Drives"
                : root.page === "tray" ? "Background apps" : "Control Center"

            ShellButton {
                visible: root.page.length === 0 && TrayService.items.length > 0
                icon: "󰀻"; variant: "ghost"; iconSize: Metrics.iconMd
                toolTip: "Background apps"
                onClicked: root.page = "tray"
            }
            ShellButton {
                visible: root.page.length === 0
                icon: Icons.edit
                variant: LayoutService.quickEditing ? "accent" : "ghost"
                iconSize: Metrics.iconMd
                toolTip: LayoutService.quickEditing ? "Done arranging" : "Arrange tiles"
                onClicked: LayoutService.quickEditing = !LayoutService.quickEditing
            }
            ShellButton { icon: Icons.settings; variant: "ghost"; iconSize: Metrics.iconMd; toolTip: "Settings"; onClicked: PanelService.open("settings") }
            ShellButton { icon: "󰐥"; variant: "ghost"; iconSize: Metrics.iconMd; toolTip: "Power"; onClicked: PanelService.open("powerMenu") }
        }

        // The panel caps its own height and clips, so the pages scroll rather
        // than running off the bottom of the screen. With every tile back on
        // the panel - which arranging invites - they no longer fit. A panel
        // dragged to a height is capped by that instead: what does not fit
        // scrolls, rather than being hidden behind a page nobody knows about.
        ScrollList {
            Layout.fillWidth: true
            card: false
            // The height the card was *granted*, not the one it asked for.
            // ShellPanel caps a requested height at the room there is, and this
            // read the request: whenever the two differed the list was taller
            // than the card, the card clipped, and the rows past the bottom
            // were cut off with no way to scroll to them. The granted figure
            // may only be read when a height is stored - without one the card
            // measures its own content, and reading it back here would be a
            // binding loop. The floor is one grid row, so the body can never
            // compute to nothing.
            maxHeight: Math.max(Metrics.quickGridUnit,
                (root.cardHeight > 0 ? root.cardTargetHeight : root.roomBelowTop)
                - header.height - Metrics.panelPadding * 2 - Metrics.panelGap - Metrics.spaceXs)

            // Unloaded while hidden so pages stop scans and discovery on close.
            Loader {
                width: parent.width
                active: root.shown
                sourceComponent: root.page === "network" ? networkPage
                    : root.page === "bluetooth" ? bluetoothPage
                    : root.page === "audio" ? audioPage
                    : root.page === "dnd" ? dndPage
                    : root.page === "power" ? powerPage
                    : root.page === "drives" ? drivesPage
                    : root.page === "tray" ? trayPage : overview
            }
        }
    }

    Component { id: overview; OverviewPage { panel: root; onOpenPage: name => root.page = name } }
    Component { id: networkPage; NetworkPage {} }
    Component { id: bluetoothPage; BluetoothPage {} }
    Component { id: audioPage; AudioPage {} }
    Component { id: dndPage; DndPage {} }
    Component { id: powerPage; PowerPage {} }
    Component { id: trayPage; TrayPage {} }
    Component { id: drivesPage; DrivesPage {} }
}
