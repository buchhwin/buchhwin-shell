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
// right to move, Ctrl+F marks a favourite, Ctrl+Up and Ctrl+Down walk the
// chips, Tab reaches the buttons, the chips and the display choice. With
// several displays a segment chooses which one the choice applies to. It
// opens on the chip (subfolder or favourites) chosen last.
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
    // starred ones, otherwise a subfolder's name. The picker opens on the chip
    // clicked last (WallpaperService.pickerFilter, kept in wallpapers.json and
    // the same in every profile): a folder of wallpapers is a place one goes
    // back to, and opening on everything each time meant clicking the same
    // chip again after every open.
    property string filter: ""
    // The remembered chip while this open could not show it yet: at a start
    // the folder and its subfolders are read in steps after the first open.
    // Empty once it is shown, a chip is clicked or the picker closes.
    property string awaitedFilter: ""
    readonly property var filters: Logic.pickerFilters(WallpaperService.images, WallpaperService.favourites,
                                                       WallpaperService.folder)
    // A folder can empty out, be renamed or stop being a folder while the
    // picker is open, and the wallpaper folder itself can change in Settings.
    // A chip that is no longer offered would leave the grid empty with nothing
    // highlighted to click back out of - so the filter falls back to
    // everything rather than to a place that is not there. The remembered
    // chip stays as it is: a folder that comes back (a drive plugged in
    // again) is where the next open goes.
    onFiltersChanged: {
        const next = Logic.filterAfterChange(filter, filters, awaitedFilter)
        if (awaitedFilter.length && next === awaitedFilter) awaitedFilter = ""
        if (next !== filter) {
            filter = next
            select(0)
        }
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
    //
    // `reveal` scrolls the grid to the selection: for the keys, the open and
    // a filter, never for the pointer. A tile under the pointer is on screen
    // already, and pulling a half-shown one fully into view moved the grid
    // under a resting pointer, which then rested on another tile (16.10.:
    // scrolling "snapped back").
    function select(index, reveal) {
        grid.currentIndex = Math.max(0, Math.min(index, root.items.length - 1))
        if (reveal !== false) grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)
    }

    function move(delta) {
        select(Logic.moveIndex(root.currentIndex, delta, root.items.length, root.columns))
    }

    // Starring moves the image (favourites first): the selection stays on
    // it, not on its old place (PickerSelection). `reveal` for the key; the
    // pointer's right click leaves the grid where it is.
    function toggleFavourite(item, reveal) {
        if (!item) return
        keeper.hold(item.path, reveal)
        WallpaperService.toggleFavourite(item.path)
        Qt.callLater(keeper.settle)
    }
    PickerSelection { id: keeper; view: grid; items: root.items }

    // A chip, the way a click chooses it.
    function chooseFilter(key) {
        filter = key
        awaitedFilter = ""
        // Remembered for the next open, "All" included.
        WallpaperService.setPickerFilter(key)
        // The index is a place in the old list; after a filter it means
        // nothing, and leaving it behind would open the grid part-way down
        // for no reason.
        select(0)
    }
    // Ctrl+Up and Ctrl+Down walk the chips from the search field, as they
    // walk the launcher's categories.
    function stepFilter(delta) {
        if (filters.length < 2) return
        const keys = filters.map(item => item.key)
        const at = keys.indexOf(filter)
        const next = keys[Math.max(0, Math.min(keys.length - 1, (at < 0 ? 0 : at) + delta))]
        if (next !== filter) chooseFilter(next)
    }
    onWantedChanged: {
        if (wanted) {
            // The field, not the query: the panel's body lives on between
            // opens, and a field that kept its text over an unfiltered grid
            // filtered for "beachx" on the next key. The query follows it.
            search.text = ""
            const remembered = WallpaperService.pickerFilter
            filter = Logic.openingFilter(remembered, filters)
            awaitedFilter = filter === remembered ? "" : remembered
            select(0)
            if (Quickshell.screens.length <= 1) target = ""
            WallpaperService.refresh()
        } else {
            awaitedFilter = ""
        }
    }
    // The folder is read asynchronously, so the list is usually still empty
    // when the picker opens; the selection has to come back into range once it
    // arrives. A change from a star is the keeper's to settle.
    onItemsChanged: if (!keeper.holding) select(root.currentIndex)

    ColumnLayout {
        // anchors.fill, not width: the grid needs a height to fill.
        anchors.fill: parent
        spacing: Metrics.panelGap

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellTextField {
                id: search
                Layout.fillWidth: true
                // In the Tab ring too, so Shift+Tab finds the way back.
                focusOnTab: true
                icon: Icons.search
                placeholder: "Search wallpapers …"
                onTextChanged: root.query = text
                onAccepted: root.apply(root.items[root.currentIndex])
                Keys.onLeftPressed: root.move(-1)
                Keys.onRightPressed: root.move(1)
                Keys.onUpPressed: event => (event.modifiers & Qt.ControlModifier) ? root.stepFilter(-1) : root.move(-root.columns)
                Keys.onDownPressed: event => (event.modifiers & Qt.ControlModifier) ? root.stepFilter(1) : root.move(root.columns)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        root.toggleFavourite(root.items[root.currentIndex], true)
                        event.accepted = true
                    }
                }
            }
            // Tab stops, like the chips and the display choice below: Tab
            // and Shift+Tab from the field reach them (the arrows stay the
            // grid's).
            ShellButton {
                focusOnTab: true
                icon: Icons.folder; text: "Folder"; compact: true
                onClicked: { Quickshell.execDetached(["xdg-open", WallpaperService.folder]); PanelService.close("wallpaperPicker") }
            }
            // The KDE folder dialog is a window of its own; the picker holds
            // the keyboard, so it steps aside rather than sit on top of it.
            ShellButton {
                focusOnTab: true
                icon: Icons.modify; text: "Change"; compact: true
                onClicked: { PanelService.close("wallpaperPicker"); WallpaperService.chooseFolder() }
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
                    focusOnTab: true
                    title: modelData.label
                    active: root.filter === modelData.key
                    onClicked: root.chooseFilter(modelData.key)
                }
            }
        }

        SegmentedControl {
            Layout.fillWidth: true
            visible: Quickshell.screens.length > 1
            focusOnTab: true
            accessibleName: "Set it on"
            compact: true
            current: root.target
            options: [{ value: "", label: "All displays" }]
                .concat(Quickshell.screens.map(screen => ({ value: screen.name, label: screen.name })))
            onSelected: value => root.target = value
        }

        // Takes the grid's height while the grid is hidden: with no item
        // left to fill it, the column spread the spare height between its
        // rows and the search field drifted down the card.
        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
            // Only while the panel is on screen. The panel's body exists from
            // start and hides rather than closes, and every thumbnail is a
            // decoded image plus two layers and a mask effect: a folder of
            // forty wallpapers held 15-30 MB for a picker nobody had open.
            // `shown` goes false after the close animation, so the grid is
            // still there while the card fades out, and comes back before
            // the open selects (ShellPanel sets it first).
            model: root.shown ? root.items : []
            boundsBehavior: Flickable.StopAtBounds
            // A view follows its current item by itself (probed 16.10.: a
            // GridView without a highlight scrolled a half-shown current tile
            // fully into view). Here the selection follows the pointer, so
            // only `select(index)` decides when the grid moves.
            highlightFollowsCurrentItem: false
            ScrollFeel { id: feel; view: grid }
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
                        color: Colors.surface2
                        clip: true
                        border.width: tile.selected || tile.active ? Metrics.focusBorderWidth : Metrics.borderWidth
                        border.color: tile.selected ? Colors.accentLine
                            : tile.active ? Colors.accentBorder : Colors.border
                        // The one under the hand lifts, the same way a dragged
                        // tile does, so the two surfaces agree. The lift is
                        // movement, so Reduced and Off jump to it.
                        scale: tile.selected ? 1 : Effects.pickerRestScale
                        Behavior on scale {
                            NumberAnimation { duration: Animations.move(Animations.hover); easing.type: Animations.easing }
                        }

                        // RoundedImage, not an Image inside a rounded
                        // Rectangle: a Rectangle does not clip its children to
                        // its radius, so every thumbnail had square corners
                        // inside a round frame.
                        //
                        // The cached thumbnail once it exists: a 6000x3750
                        // PNG took 160-180 ms per tile to decode, its
                        // thumbnail 1-2 ms (WallpaperService, "thumbnails").
                        RoundedImage {
                            anchors.fill: parent
                            anchors.margins: parent.border.width
                            radius: parent.radius - parent.border.width
                            source: WallpaperService.thumbFor(tile.modelData.path) || Logic.folderUrl(tile.modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            sourceWidth: Metrics.wallpaperPickerTile
                        }

                        // The whole tile, under the marks: declared before
                        // them, so the slideshow tick's own area stacks above
                        // this one. Declared after, it took the tick's click
                        // too, and toggling the slideshow set the wallpaper.
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // A tile gliding under a resting pointer is
                            // "entered" too (hover is delivered again every
                            // frame): only a still grid selects, and the next
                            // real move does once it stops.
                            function point() {
                                if (!tile.selected && Logic.hoverSelects(feel.scrolling, grid.moving))
                                    root.select(tile.index, false)
                            }
                            onEntered: point()
                            onPositionChanged: point()
                            onClicked: mouse => {
                                root.select(tile.index, false)
                                if (mouse.button === Qt.RightButton) root.toggleFavourite(tile.modelData, false)
                                else root.apply(tile.modelData)
                            }
                        }

                        // Marks the image this display already shows.
                        Rectangle {
                            visible: tile.active
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Metrics.spaceXs
                            width: Metrics.thumbBadge
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
                            width: Metrics.thumbBadge
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
                + "Enter sets · Ctrl+F or right click marks a favorite · Esc closes"
            role: "caption"; muted: true
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
