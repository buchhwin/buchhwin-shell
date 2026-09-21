import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/wallpaper/WallpaperLogic.js" as Logic

// Super+Shift+W: switch the wallpaper without opening Settings.
//
// A grid of the folder's images, centred on the screen behind a scrim near
// enough to nothing, so the wallpaper it is choosing stays visible around it.
//
// It does **not** preview on the wall. That was tried and taken out again: the
// desktop changing under every arrow key is one more thing happening than was
// asked for.
//
// Favourites come first, then the rest of the folder. Type to filter, left and
// right to move, Ctrl+F marks a favourite. With several displays a segment
// chooses which one the choice applies to.
ShellPanel {
    id: root
    keyForward: search
    panelId: "wallpaperPicker"
    placement: "center"
    cardWidth: Metrics.wallpaperPickerWidth
    cardHeight: Metrics.wallpaperPickerHeight
    // Near enough to nothing: the wallpaper behind this panel is the thing
    // being chosen, so dimming it would defeat the point. What is left is
    // enough to lift the card off a bright image.
    scrimColor: Colors.scrimFaint
    // A click beside the card closes it, like every other panel. The faint
    // scrim makes this panel *look* less modal than it is - the surface covers
    // the whole screen either way, so a click on the wallpaper never reached
    // it, it was only being swallowed. The reason this was once off no longer
    // exists: it guarded a live preview that a stray click would have thrown
    // away, and the preview was removed.

    // "" is every display, a monitor name is that one only.
    property string target: ""
    property int currentIndex: 0
    readonly property var items: Logic.pickerItems(WallpaperService.images, WallpaperService.favourites,
                                                   query, filter, WallpaperService.folder)
    property string query: ""
    // Which chip is chosen: "" for everything, Logic.FAVOURITES for the
    // starred ones, otherwise a subfolder's name. Not stored - it is where you
    // are looking, not a preference, and the picker opens on everything.
    property string filter: ""
    readonly property var filters: Logic.pickerFilters(WallpaperService.images, WallpaperService.favourites,
                                                       WallpaperService.folder)
    // A folder can empty out, be renamed or stop being a folder while the
    // picker is open, and the wallpaper folder itself can change in Settings.
    // A chip that is no longer offered would leave the grid empty with nothing
    // highlighted to click back out of - so the filter falls back to
    // everything rather than to a place that is not there.
    onFiltersChanged: if (filter.length && !filters.some(entry => entry.key === filter)) {
        filter = ""
        select(0)
    }
    // How many thumbnails fit across the card, which is also how far up and
    // down move.
    readonly property int columns: Math.max(1, Math.floor((cardWidth - Metrics.panelPadding * 2 + Metrics.spaceSm)
        / (Metrics.wallpaperPickerTile + Metrics.spaceSm)))

    function apply(item) {
        if (!item) return
        WallpaperService.setWallpaper(item.path, root.target)
    }

    // The strip owns the index and `currentIndex` follows it. Binding the two
    // to each other instead made them fight: the view kept its old index
    // across a close, pushed it back after the reset, and the picker reopened
    // on whatever had been chosen last.
    function select(index) {
        grid.currentIndex = Math.max(0, Math.min(index, root.items.length - 1))
    }

    function move(delta) {
        select(Logic.moveIndex(root.currentIndex, delta, root.items.length, root.columns))
    }

    onCurrentIndexChanged: grid.positionViewAtIndex(currentIndex, GridView.Contain)
    onWantedChanged: {
        if (wanted) {
            query = ""
            filter = ""
            select(0)
            if (Quickshell.screens.length <= 1) target = ""
            WallpaperService.refresh()
        }
    }
    // The folder is read asynchronously, so the list is usually still empty
    // when the picker opens; the selection has to come back into range once it
    // arrives.
    onItemsChanged: select(root.currentIndex)

    ColumnLayout {
        // anchors.fill, not width: the grid needs a height to fill.
        anchors.fill: parent
        spacing: Metrics.spaceMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellTextField {
                id: search
                Layout.fillWidth: true
                icon: "󰋩"
                placeholder: "Search wallpapers …"
                onTextChanged: root.query = text
                onAccepted: root.apply(root.items[root.currentIndex])
                Keys.onLeftPressed: root.move(-1)
                Keys.onRightPressed: root.move(1)
                Keys.onUpPressed: root.move(-root.columns)
                Keys.onDownPressed: root.move(root.columns)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        const item = root.items[root.currentIndex]
                        if (item) WallpaperService.toggleFavourite(item.path)
                        event.accepted = true
                    }
                }
            }
            ShellButton {
                icon: Icons.folder; text: "Folder"; compact: true
                onClicked: { Quickshell.execDetached(["xdg-open", WallpaperService.folder]); PanelService.close("wallpaperPicker") }
            }
        }

        // One chip per subfolder of the wallpaper folder, which is how the
        // user groups their wallpapers: make a folder, get a chip. A filter
        // rather than headings in the grid, so the grid stays one rectangle
        // and the arrow keys keep walking a single run of cells.
        //
        // Hidden entirely when there is nothing to choose between: a row
        // holding only "All" is a control that does nothing.
        Flow {
            Layout.fillWidth: true
            visible: root.filters.length > 1
            spacing: Metrics.spaceXs
            Repeater {
                model: root.filters
                ChipButton {
                    required property var modelData
                    // One line and a word: the chip's compact form, which is
                    // what it has for exactly this - a row of choices in a
                    // place with no room for two lines.
                    compact: true
                    title: modelData.label
                    active: root.filter === modelData.key
                    onClicked: {
                        root.filter = modelData.key
                        // The index is a place in the old list; after a filter
                        // it means nothing, and leaving it behind would open
                        // the grid part-way down for no reason.
                        root.select(0)
                    }
                }
            }
        }

        SegmentedControl {
            Layout.fillWidth: true
            visible: Quickshell.screens.length > 1
            compact: true
            current: root.target
            options: [{ value: "", label: "All displays" }]
                .concat(Quickshell.screens.map(screen => ({ value: screen.name, label: screen.name })))
            onSelected: value => root.target = value
        }

        EmptyState {
            Layout.fillWidth: true
            visible: root.items.length === 0
            icon: "󰋩"
            title: WallpaperService.images.length === 0
                ? "No images in " + WallpaperService.folder
                : root.query.length ? "No wallpaper matches the search"
                : "Nothing in this folder"
        }

        // A grid, the way it always was - the strip read worse than the wall
        // of thumbnails it replaced. What the strip was right about stays:
        // the highlighted wallpaper is on the wall behind this card, so the
        // grid is how you pick and the screen is how you judge.
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.items.length > 0
            clip: true
            cellWidth: Math.floor(width / root.columns)
            cellHeight: Math.round(cellWidth * 9 / 16) + Metrics.rowHeight
            model: root.items
            boundsBehavior: Flickable.StopAtBounds
            // One direction only: the view is the owner, `root.currentIndex`
            // is what everything else reads.
            onCurrentIndexChanged: root.currentIndex = currentIndex
            onCountChanged: positionViewAtIndex(currentIndex, GridView.Contain)

            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool selected: index === root.currentIndex
                readonly property bool active: modelData.path === WallpaperService.currentFor(
                    root.target.length ? root.target : (root.screen ? root.screen.name : ""))
                width: grid.cellWidth
                height: grid.cellHeight

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceXs
                    spacing: Metrics.spaceXs

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Metrics.radiusInner
                        color: Colors.elevatedSurface
                        clip: true
                        border.width: tile.selected || tile.active ? Metrics.focusBorderWidth : Metrics.borderWidth
                        border.color: tile.selected ? Colors.accent
                            : tile.active ? Colors.accentBorder : Colors.border
                        // The one under the hand lifts, the same way a dragged
                        // tile does, so the two surfaces agree.
                        scale: tile.selected ? 1 : Effects.pickerRestScale
                        Behavior on scale {
                            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
                        }

                        // RoundedImage, not an Image inside a rounded
                        // Rectangle: a Rectangle does not clip its children to
                        // its radius, so every thumbnail had square corners
                        // inside a round frame.
                        RoundedImage {
                            anchors.fill: parent
                            anchors.margins: parent.border.width
                            radius: parent.radius - parent.border.width
                            source: "file://" + tile.modelData.path
                            fillMode: Image.PreserveAspectCrop
                            sourceWidth: Metrics.wallpaperPickerTile
                        }

                        // Marks the image this display already shows.
                        Rectangle {
                            visible: tile.active
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Metrics.spaceXs
                            width: Metrics.iconMd + Metrics.spaceXs
                            height: width
                            radius: width / 2
                            color: Colors.accent
                            ShellIcon { anchors.centerIn: parent; glyph: Icons.check; size: Metrics.iconXs; color: Colors.accentText }
                        }

                        ShellIcon {
                            visible: tile.modelData.favourite
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: Metrics.spaceXs
                            glyph: "󰓎"
                            size: Metrics.iconSm
                            color: Colors.warning
                        }

                        // The slideshow tick, only while the slideshow takes a
                        // chosen list.
                        Rectangle {
                            readonly property bool picked: WallpaperService.isInSlideshow(tile.modelData.path)
                            visible: WallpaperService.slideshowSource === "chosen"
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.margins: Metrics.spaceXs
                            width: Metrics.iconMd + Metrics.spaceXs
                            height: width
                            radius: Metrics.radiusInner
                            color: picked ? Colors.accent : Colors.pill
                            ShellIcon {
                                anchors.centerIn: parent
                                glyph: Icons.check
                                size: Metrics.iconXs
                                color: parent.picked ? Colors.accentText : Colors.mutedText
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: WallpaperService.toggleSlideshow(tile.modelData.path)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.select(tile.index)
                            onClicked: mouse => {
                                root.select(tile.index)
                                if (mouse.button === Qt.RightButton) WallpaperService.toggleFavourite(tile.modelData.path)
                                else root.apply(tile.modelData)
                            }
                        }
                    }

                    ShellText {
                        Layout.fillWidth: true
                        text: tile.modelData.name
                        role: "caption"
                        muted: !tile.selected
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        ShellText {
            Layout.fillWidth: true
            text: (WallpaperService.slideshowSource === "chosen"
                    ? WallpaperService.slideshowCount + " of " + WallpaperService.images.length
                      + " in the slideshow · " : "")
                + "Enter sets · Ctrl+F or right click marks a favourite · Escape closes"
            role: "caption"; muted: true
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
