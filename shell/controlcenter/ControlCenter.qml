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
    sizeBounds: ({ minWidth: Metrics.controlCenterMinWidth,
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
    // The grip and the drag live in ShellPanel; this says when the grip is
    // reachable and where the result goes.
    resizable: true
    gripShown: LayoutService.quickEditing && root.page.length === 0
    onResized: (width, height) => LayoutService.quickResize(width, height)
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
