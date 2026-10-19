import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "pages"
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/quick/QuickLogic.js" as Quick

// Super+O control center: quick tiles, sliders, media, audio and status chips
// with detail pages for network, Bluetooth, audio, DND, power, drives and tray.
// The arrange button in the header arranges the tiles in place (see
// OverviewPage).
ShellPanel {
    id: root
    keyNavigation: true
    panelId: "controlCenter"
    placement: "top-right"
    // The panel's own size is dragged from its corner while the tiles are
    // being arranged, the way the notch's overview is. Both ends are real
    // clamps: the panel can neither grow past the room below its own top edge,
    // which took the grip out of reach with it, nor shrink to a height at
    // which its body computed to nothing.
    readonly property real minPanelHeight: header.height + Metrics.quickGridUnit
        + Metrics.panelPadding * 2 + Metrics.panelGap
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
    // Its pages differ in height; the surface stays put while they switch
    // (see ShellPanel.stableSurfaceHeight).
    stableSurfaceHeight: true
    gripShown: LayoutService.quickEditing && root.page.length === 0
    onResized: (width, height) => LayoutService.quickResize(width, height)
    cardWidth: sizing ? dragWidth : box.width
    // The dragged height belongs to the overview. Every detail page used to
    // inherit it, so a short page left a dead area and a panel shrunk to fit
    // eight tiles had permanently shrunk the network page's scroll region.
    cardHeight: page.length ? -1 : sizing ? dragHeight : box.height
    property string page: ""
    // The overview is kept once it has been built. It was most of what an
    // open cost - some 1600 objects made in the open's own turn, before the
    // first frame (22-26 ms of the GUI thread offscreen, 2 ms kept; the
    // dashboard keeps its cards the same way) - and a trip to a detail page
    // and back made it once more. Kept, it measured no more memory while
    // closed (offscreen, within the allocator's noise). What it asks of the
    // services follows the panel rather than the page (OverviewPage.live).
    // The detail pages are still built per visit and let go on close, so
    // their scans and discovery stop. `false` builds the overview on every
    // open again.
    property bool keepOverview: true
    property bool overviewBuilt: false

    onWantedChanged: {
        if (wanted) {
            page = PanelService.args.page || ""
            BrightnessService.refresh()
            // Only when NetworkManager said something since the last read:
            // its monitor keeps the list current, and every open used to run
            // nmcli again for an answer it already had.
            NetworkService.refreshIfStale()
            MprisService.trackers += 1
        } else {
            MprisService.trackers = Math.max(0, MprisService.trackers - 1)
        }
    }
    // Arranging belongs to the overview. With the overview destroyed on the
    // way to a detail page that ended it by itself; kept, it is ended here.
    onPageChanged: if (page.length) LayoutService.quickEditing = false
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

    // Escape on a detail page goes back to the overview and keeps the panel
    // - after the page's own steps, such as an app's menu open on the
    // background apps page (`stepBack`); on the overview it closes the panel.
    // A handler, not `onEscapePressed`: that runs before the close, never
    // instead of it, and the panel went with the page it had just cleared
    // (pitfall 111).
    escapeHandler: () => {
        const shownPage = detailLoader.item
        if (shownPage && typeof shownPage.stepBack === "function" && shownPage.stepBack() === true) return true
        const next = Quick.pageAfterEscape(root.page)
        if (next === null) return false
        root.page = next
        return true
    }

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
            showBack: root.page.length > 0
            onBackPressed: root.page = ""
            title: root.page === "network" ? "Network"
                : root.page === "bluetooth" ? "Bluetooth"
                : root.page === "audio" ? "Audio"
                : root.page === "dnd" ? "Do Not Disturb"
                : root.page === "power" ? "Power"
                : root.page === "drives" ? "Drives"
                : root.page === "tray" ? "Background apps" : "Control center"

            ShellButton {
                visible: root.page.length === 0 && TrayService.items.length > 0
                icon: Icons.apps; variant: "ghost"; iconSize: Metrics.iconMd
                toolTip: "Background apps"
                onClicked: root.page = "tray"
            }
            ShellButton {
                visible: root.page.length === 0
                icon: Icons.arrange
                variant: LayoutService.quickEditing ? "accent" : "ghost"
                iconSize: Metrics.iconMd
                toolTip: LayoutService.quickEditing ? "Done arranging" : "Arrange tiles"
                onClicked: LayoutService.quickEditing = !LayoutService.quickEditing
            }
            // On a detail page, the Settings page of that page (the Power
            // page's own "Power settings" button opens the same); on the
            // overview, Settings where it was left.
            ShellButton {
                icon: Icons.settings; variant: "ghost"; iconSize: Metrics.iconMd; toolTip: "Settings"
                onClicked: {
                    const target = Quick.settingsPage(root.page)
                    if (target.length) PanelService.open("settings", { page: target })
                    else PanelService.open("settings")
                }
            }
            ShellButton { icon: Icons.poweroff; variant: "ghost"; iconSize: Metrics.iconMd; toolTip: "Power"; onClicked: PanelService.open("powerMenu") }
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
                - header.height - Metrics.panelPadding * 2 - Metrics.panelGap)

            // The overview, kept between opens (keepOverview) and hidden
            // behind a detail page; a hidden item takes no room in the list.
            // A page name it does not know shows the overview, as it did.
            // Each fades in when the page changes while the panel is open
            // (PageFade): the card's height glides between pages, and the
            // content swapped inside it in one frame.
            Loader {
                id: overviewLoader
                width: parent.width
                active: root.shown || (root.keepOverview && root.overviewBuilt)
                visible: root.detailPage === null
                sourceComponent: overview
                onLoaded: root.overviewBuilt = true
                PageFade { target: overviewLoader; key: root.page; live: root.openProgress === 1 }
            }
            // A detail page: unloaded while hidden, so pages stop scans and
            // discovery on close.
            Loader {
                id: detailLoader
                width: parent.width
                active: root.shown && root.detailPage !== null
                visible: active
                sourceComponent: root.detailPage
                PageFade { target: detailLoader; key: root.page; live: root.openProgress === 1 }
            }
        }
    }

    readonly property Component detailPage: page === "network" ? networkPage
        : page === "bluetooth" ? bluetoothPage
        : page === "audio" ? audioPage
        : page === "dnd" ? dndPage
        : page === "power" ? powerPage
        : page === "drives" ? drivesPage
        : page === "tray" ? trayPage : null
    Component { id: overview; OverviewPage { panel: root; onOpenPage: name => root.page = name } }
    Component { id: networkPage; NetworkPage {} }
    Component { id: bluetoothPage; BluetoothPage {} }
    Component { id: audioPage; AudioPage {} }
    Component { id: dndPage; DndPage {} }
    Component { id: powerPage; PowerPage {} }
    Component { id: trayPage; TrayPage {} }
    Component { id: drivesPage; DrivesPage {} }
}
