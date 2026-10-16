import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/launcher/LauncherCatalogue.js" as LauncherCatalogue

// Super+D launcher with apps, commands (>), files (/), settings (@) and a
// calculator (=). Keyboard: arrows, PageUp/PageDown, Home/End, Tab switches
// mode, Ctrl+Up/Down switches category, Enter runs, Ctrl+Enter alternate
// action, Esc clears then closes.
//
// **Its parts are arranged, like every other large surface.** Five blocks in
// two zones (`LayoutLogic`, the `launcher` surface of the layout file): the
// column, and the sidebar beside the result list that only the categories may
// sit in. Stacked blocks and not the dashboard's free grid, because on a
// search surface a free grid is one in which you can build yourself a result
// list two rows high.
ShellPanel {
    id: root
    keyForward: searchField
    panelId: "launcher"
    placement: "center"
    // Pulled from the grip on the card's bottom-left corner, like the control
    // center and the dashboard - and behind the arrange mode like both of
    // them. It used to be always on, on the reasoning that the launcher had no
    // arrange mode to put it behind. It has one now, and a permanent accent
    // dot on the corner was reported as a bug before that reasoning expired.
    resizable: true
    gripShown: root.editing
    sizeBounds: ({ minWidth: Metrics.launcherMinWidth,
                   maxWidth: Metrics.launcherMaxWidth,
                   width: Metrics.launcherWidth,
                   minHeight: Metrics.launcherMinHeight,
                   room: roomBelowTop })
    readonly property var box: Arrange.panelBox(SettingsService.value("desktop.launcherWidth"),
                                                SettingsService.value("desktop.launcherHeight"),
                                                sizeBounds)
    onResized: (width, height) => SettingsService.setAll({ "desktop.launcherWidth": Math.round(width),
                                                           "desktop.launcherHeight": Math.round(height) })
    cardWidth: sizing ? dragWidth : box.width
    cardHeight: sizing ? dragHeight : (box.height > 0 ? box.height : Metrics.launcherFactoryHeight)
    scrimColor: Colors.scrim

    property string query: ""
    property string category: "All"
    // The search field lives inside the `search` block's component, so the
    // panel cannot name it by id. The block hands it over instead, which is
    // what `keyForward` and every `focusInput()` below reach it through.
    property Item searchField: null
    property int selectedIndex: 0
    readonly property var mode: LauncherService.modeFor(query)
    // Only evaluated while the launcher is visible.
    readonly property var results: shown ? LauncherService.results(query, category) : []

    readonly property bool editing: LayoutService.launcherEditing

    readonly property var modeOptions: LauncherService.modes.map(
        item => ({ value: item.id, label: item.label, icon: item.icon }))

    // Every block is a cell of the grid, always, in use and while arranging.
    // The launcher used to stack them and keep two hand-written pairings - the
    // mode switch riding in the search field's row, the categories standing
    // beside the result list - and gave way to the grid the rest of the shell
    // has. A block goes where it is put and is the size it is dragged to;
    // nothing here decides that for it any more.
    readonly property var blocks: LayoutService.launcherItems
    // The slots' blocks by id (their Repeater runs on the ids alone).
    readonly property var blockById: {
        const table = {}
        for (const block of blocks) table[block.id] = block
        return table
    }

    onWantedChanged: {
        if (wanted) {
            if (searchField) searchField.text = ""
            query = ""
            category = "All"
            selectedIndex = 0
            // The emoji list is read on first use rather than at start; the
            // first use is now, while the panel is still opening, so a ":"
            // search answers on its first keystroke.
            EmojiService.load()
        }
    }
    onResultsChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, results.length - 1))
    // Arranging is a mode of the panel, not of the session: it must not still
    // be on the next time Super+D is pressed.
    onShownChanged: {
        if (shown) return
        LayoutService.launcherEditing = false
        LayoutService.reportLauncherCells({})
    }

    function run(alternate) {
        const entry = results[selectedIndex]
        if (!entry) return
        PanelService.close("launcher")
        if (alternate && entry.alternate) entry.alternate()
        else entry.run()
    }

    function move(delta) {
        if (!results.length) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
    }

    function cycleCategory(step) {
        const list = LauncherService.availableCategories
        const index = Math.max(0, list.findIndex(item => item.name === category))
        category = list[(index + step + list.length) % list.length].name
        selectedIndex = 0
    }

    function setMode(prefix) {
        if (!searchField) return
        const rest = mode.prefix.length ? query.slice(1) : query
        searchField.text = prefix + rest
        searchField.focusInput()
    }

    // The pinned row is the one fixed thing on a search surface that earns its
    // place, and it earns it by answering "nothing typed yet": it is there
    // before the query and gone the moment there is one, so it never competes
    // with the results for the room or the attention.
    readonly property bool pinnedShown: mode.id === "apps" && query.length === 0
        && LauncherService.showPinned && LauncherService.pinnedApps.length > 0

    function togglePin() {
        const entry = results[selectedIndex]
        if (entry && entry.appId) LauncherService.togglePin(entry.appId)
    }

    function cycleMode(step) {
        const modes = LauncherService.modes
        const index = modes.indexOf(mode)
        const next = modes[(index + step + modes.length) % modes.length]
        const rest = mode.prefix.length ? query.slice(1) : query
        if (searchField) searchField.text = next.prefix + rest
    }

    // **A row is a share of the card, not a number of pixels.** Every other
    // surface of tiles has a fixed row height and scrolls what does not fit;
    // the launcher cannot, because the result list has to reach the bottom of
    // a window the user drags. So the grid scales with the card, and the
    // default comes out as the picture the launcher has always had.
    //
    // **And the share is one over the rows in use, not over the ceiling.**
    // Take the pinned row off and the layout is seven rows; divided by eight,
    // the eighth stood under the result list as a band of nothing, and was
    // reported as one. While arranging it is the ceiling that shows - the
    // eighth row has to be there to drop something on.
    //
    // Read off **the card**, never off the grid: the grid's height is the sum
    // of its rows and its rows are a share of this, so measuring here from the
    // grid computes the layout from itself. The log says `Binding loop
    // detected` and nothing else does - this file has had three of them.
    // `rowsUsed` is safe to read: it counts steps and knows no pixel.
    readonly property real gridRoom: Math.max(Metrics.rowHeight * 2,
        root.cardTargetHeight - Metrics.panelPadding * 2
            - (root.editing ? editBar.implicitHeight + Metrics.panelGap : 0))
    readonly property int gridRows: root.editing ? LauncherCatalogue.rows : Math.max(1, grid.rowsUsed)
    readonly property real gridUnit:
        (gridRoom - Metrics.spaceMd * (gridRows - 1)) / gridRows

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.panelGap

        ArrangeArea {
            id: grid
            Layout.fillWidth: true
            Layout.preferredHeight: root.gridRoom
            columns: LauncherCatalogue.columns
            gap: Metrics.spaceMd
            unit: root.gridUnit
            maxRows: LauncherCatalogue.rows
            editing: root.editing
            animated: !root.sizing
            dragLayer: root.overlay
            model: root.blocks.map(item => ({ id: item.id, w: item.w, h: item.h,
                minW: LayoutService.launcherMinSize(item.type).w,
                minH: LayoutService.launcherMinSize(item.type).h }))
            onCommitted: (id, index) => LayoutService.launcherMoveTo(id, index)
            onPlacementChanged: reportTimer.restart()
            onWidthChanged: reportTimer.restart()

            // Matched by id, not rebuilt: `blocks` is a new list on every write
            // of the layout file, and on a plain array every block - the field
            // with its focus, the result list - was thrown away and built
            // again, hidden or not. The model is the ids, not the blocks with
            // `objectProp` (see DashboardPanel: Quickshell 0.3.2 hands rows on
            // by position after the first one it updates in place), and a slot
            // reads its block by its id. The motion is the old one: the
            // rebuilt blocks were made at their old cells and glided to the new
            // ones, because this Repeater hears of a new list before the area
            // does; a kept block glides the same way from where it stands.
            Repeater {
                model: ScriptModel { values: root.blocks.map(block => block.id) }
                LauncherSlot {
                    required property string modelData
                    required property int index
                    // Empty for the turn in which its block is taken off: it
                    // unloads rather than build a block on its way out.
                    readonly property var block: root.blockById[modelData] || null
                    readonly property string blockType: block ? block.type : ""
                    area: grid
                    blockId: modelData
                    type: blockType
                    label: LayoutService.launcherLabel(blockType)
                    removable: !LauncherCatalogue.fixed(blockType)
                    // The pinned row is there before the query and gone the
                    // moment there is one - gone, not blank: a block that
                    // shows nothing holds no row, and the result list takes
                    // it. While arranging it holds its place, or it could not
                    // be dragged.
                    holds: blockType !== "pinned" || root.editing || root.pinnedShown
                    slotIndex: index
                    content: block ? root.blockFor(blockType) : null
                    onResized: (w, h) => LayoutService.launcherSetSize(modelData, w, h)
                }
            }
        }

        // One compact row while arranging: the blocks that are off, undo, the
        // way back, and Done. The arrange button sits in the search field's
        // row, which wiggles and dims while arranging - so unlike the
        // dashboard's, it cannot be the way out and there is a button here
        // for it.
        CardSection {
            id: editBar
            Layout.fillWidth: true
            visible: root.editing
            padding: Metrics.spaceSm
            spacing: Metrics.spaceXs

            Flow {
                Layout.fillWidth: true
                spacing: Metrics.spaceXs

                Repeater {
                    model: LayoutService.launcherChoices()
                    // Labels and no icons: there are four of them, the names
                    // are two words each, and inventing a glyph for "the
                    // result list" says less than the words do.
                    ShellButton {
                        required property var modelData
                        text: modelData.label
                        variant: "surface"
                        compact: true
                        onClicked: LayoutService.launcherAdd(modelData.type)
                    }
                }
                ShellButton {
                    icon: Icons.undo
                    variant: "ghost"
                    compact: true
                    enabledState: LayoutService.undoStack.length > 0
                    toolTip: "Undo"
                    onClicked: LayoutService.undo()
                }
                ShellButton {
                    icon: Icons.reset
                    variant: "ghost"
                    compact: true
                    toolTip: "Reset the launcher's layout"
                    // Like the dashboard's and the control center's resets:
                    // the arrangement goes, so it asks twice.
                    confirm: true
                    confirmText: "Reset"
                    onClicked: LayoutService.launcherReset()
                }
                ShellButton {
                    text: "Done"
                    icon: Icons.check
                    variant: "accent"
                    compact: true
                    onClicked: LayoutService.launcherEditing = false
                }
            }
        }
    }

    // Where the blocks are resting, for a test: a drag is over before a
    // screenshot can catch it, and whether two blocks share a row is not
    // something a picture answers either.
    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: {
            const cells = {}
            for (const item of root.blocks) {
                const cell = grid.cellOf(item.id)
                if (cell) cells[item.type] = { x: Math.round(cell.x), y: Math.round(cell.y),
                                               width: Math.round(cell.width),
                                               height: Math.round(cell.height) }
            }
            LayoutService.reportLauncherCells(cells)
        }
    }
    // ---- the blocks --------------------------------------------------------
    // One component per type. They are declared here rather than in files of
    // their own because each is a handful of lines that reads the launcher's
    // own state; a file each would be five files of `property Item root`.

    function blockFor(type) {
        return type === "search" ? searchBlock
            : type === "modes" ? modesBlock
            : type === "pinned" ? pinnedBlock
            : type === "categories" ? categoriesBlock
            : resultsBlock
    }

    Component {
        id: searchBlock
        // The search field and the mode switch are two controls, not one: the
        // switch used to sit inside the field, so the focus ring drew a box
        // around both and the field stopped looking like a field.
        RowLayout {
            spacing: Metrics.spaceSm

            // The plain field, not the hero one: `large` was a 56-px box in
            // the title size with a border, in a row the user's layout gives
            // 77 px, on a surface opened forty times a day. The capsule every
            // other panel searches in is the field; the emoji picker keeps
            // the large one.
            ShellTextField {
                id: search
                Component.onCompleted: root.searchField = search
                Component.onDestruction: if (root.searchField === search) root.searchField = null
                Layout.fillWidth: true
                // The field holds the focus for as long as the launcher is
                // open; an accent outline that is always there is no marker.
                focusOutline: false
                icon: root.mode.id === "apps" ? Icons.search : root.mode.icon
                placeholder: root.mode.id === "apps" ? "Search …" : root.mode.label + " …"
                onTextChanged: { root.query = text; root.selectedIndex = 0 }
                onKeyPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                    event.accepted = true
                    if (event.key === Qt.Key_Down && ctrl) root.cycleCategory(1)
                    else if (event.key === Qt.Key_Up && ctrl) root.cycleCategory(-1)
                    else if (event.key === Qt.Key_Down) root.move(1)
                    else if (event.key === Qt.Key_Up) root.move(-1)
                    else if (event.key === Qt.Key_PageDown) root.move(8)
                    else if (event.key === Qt.Key_PageUp) root.move(-8)
                    else if (event.key === Qt.Key_Home && ctrl) root.selectedIndex = 0
                    else if (event.key === Qt.Key_End && ctrl) root.selectedIndex = Math.max(0, root.results.length - 1)
                    else if (event.key === Qt.Key_Tab) root.cycleMode(1)
                    else if (event.key === Qt.Key_Backtab) root.cycleMode(-1)
                    else if (event.key === Qt.Key_P && ctrl) root.togglePin()
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.run(ctrl)
                    else event.accepted = false
                }
            }

            // The way in, the way the control center and the dashboard do it.
            // The launcher is a panel, not a desktop mode, so it belongs with
            // those and not behind Super+Alt+E.
            ShellButton {
                Layout.alignment: Qt.AlignVCenter
                visible: !root.editing
                icon: Icons.arrange
                variant: "ghost"
                compact: true
                toolTip: "Arrange the launcher"
                onClicked: LayoutService.launcherEditing = true
            }
        }
    }

    Component {
        id: modesBlock
        // The switch where it fits, and where it does not - one column holds
        // no seven modes - a stepper: the current mode by name and icon, and
        // two arrows that walk the ring the way Tab walks it. The block asks
        // its own width, so it is right at any card size and at any scale,
        // and the last mode is never clipped off the edge, which is what the
        // switch in a cell too small for it did.
        Item {
            id: modesCell
            readonly property bool fits: width >= modeSwitch.implicitWidth
            SegmentedControl {
                id: modeSwitch
                visible: modesCell.fits
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                current: root.mode.id
                options: root.modeOptions
                onSelected: value => root.setMode(LauncherService.modes.find(item => item.id === value).prefix)
            }
            RowLayout {
                id: stepper
                visible: !modesCell.fits
                anchors.fill: parent
                spacing: Metrics.spaceXs
                // The mode's name whole or not at all. Elided to the room
                // between the arrows of the launcher's narrowest card (520
                // px, one column of four) it read "A…", which names nothing;
                // there the glyph stands alone, centred, and the name is its
                // tooltip. Measured from the cell and the arrows, never from
                // the label the answer hides.
                readonly property bool named: modeName.implicitWidth <= modesCell.width
                    - previousMode.implicitWidth - nextMode.implicitWidth - modeGlyph.implicitWidth
                    - Metrics.spaceXs * 3
                ShellButton {
                    id: previousMode
                    icon: Icons.back
                    compact: true
                    toolTip: "Previous mode"
                    onClicked: root.cycleMode(-1)
                }
                Item { Layout.fillWidth: true; visible: !stepper.named }
                ShellIcon {
                    id: modeGlyph
                    glyph: root.mode.icon
                    size: Metrics.iconSm
                    color: Colors.accentForeground
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.mode.label
                    ToolTipHost {
                        id: modeTip
                        anchorItem: modeGlyph
                        text: stepper.named ? "" : root.mode.label
                        onTextChanged: if (!text.length) release()
                    }
                    HoverHandler { onHoveredChanged: hovered ? modeTip.arm() : modeTip.release() }
                }
                ShellText {
                    id: modeName
                    Layout.fillWidth: true
                    visible: stepper.named
                    text: root.mode.label
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: !stepper.named }
                ShellButton {
                    id: nextMode
                    icon: Icons.forward
                    compact: true
                    toolTip: "Next mode"
                    onClicked: root.cycleMode(1)
                }
            }
        }
    }

    Component {
        id: pinnedBlock
        // Pinned apps, above the results and only while nothing is typed -
        // and always while arranging, or the block would have no place to be
        // dragged by.
        ColumnLayout {
            spacing: 0

            // Nothing pinned yet, and the block is being arranged: it still
            // needs a face, or it is a row of air with a remove badge on it.
            EmptyState {
                Layout.fillWidth: true
                visible: root.editing && LauncherService.pinnedApps.length === 0
                row: true
                title: "Nothing pinned yet"
                description: "Right-click an app to pin it"
            }

        Flow {
            Layout.fillWidth: true
            visible: root.pinnedShown || (root.editing && LauncherService.pinnedApps.length > 0)
            spacing: Metrics.spaceSm

            Repeater {
                // Hidden, no tiles: DesktopEntries rescans on any file made or
                // removed in $HOME (19 times in 8 minutes, measured), and each
                // rescan is a new list. `shown` turns on before the first
                // frame of the open, so the row is there when it is drawn.
                model: root.shown && (root.pinnedShown || root.editing) ? LauncherService.pinnedApps : []

                ShellCard {
                    id: tile
                    required property var modelData
                    level: 1
                    interactive: true
                    hovered: tileMouse.containsMouse
                    pressed: tileMouse.pressed && tileMouse.containsMouse
                    implicitWidth: tileRow.implicitWidth + Metrics.spaceMd * 2
                    implicitHeight: Metrics.rowHeight

                    RowLayout {
                        id: tileRow
                        anchors.centerIn: parent
                        spacing: Metrics.spaceSm
                        // A plain Image, the way `ListRow` draws the same icon
                        // a few pixels below: an app icon is already whatever
                        // shape it is, and masking it to a rounded square turns
                        // every one of them into the same blob.
                        Image {
                            // `Layout.preferred*`, not `implicit*`: an Image
                            // derives its implicit size from the picture and
                            // will not be told otherwise.
                            Layout.preferredWidth: Metrics.iconMd
                            Layout.preferredHeight: Metrics.iconMd
                            source: LauncherService.iconSource(tile.modelData.icon)
                            sourceSize.width: Metrics.iconMd * 2
                            sourceSize.height: Metrics.iconMd * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        ShellText { text: tile.modelData.name || tile.modelData.id; role: "small" }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: !root.editing
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                LauncherService.togglePin(tile.modelData.id)
                                return
                            }
                            PanelService.close("launcher")
                            LauncherService.launchApp(tile.modelData)
                        }
                    }
                }
            }
        }
        }
    }

    // The categories have two shapes and their place decides which: the list
    // down the side of the result list when they stand one step in front of
    // it, a row of chips anywhere else. One component each, and the sidebar is
    // shared - the result block draws it while the categories are riding
    // along, the categories block draws it while they are a block of their
    // own beside it, and it has to be the same list either way.
    Component {
        id: categorySidebar
        ShellCard {
            id: sidebar
            level: 1
            // Hidden, no rows; see the pinned row.
            readonly property var categories: root.shown ? LauncherService.availableCategories : []
            // **Names only where they can be read.** In the launcher's
            // narrowest card (520 px, the categories one column of four) a
            // row had seven pixels left for its name, between the glyph and
            // the count: every name was "…" or nothing. There the rows are a
            // glyph and a count, and the name is the row's tooltip and its
            // accessible name; from a form label's width up they say it.
            // The room is what a compact ListRow leaves its title: the
            // insets, the glyph slot, the two gaps and the widest count.
            readonly property real nameRoom: categoryFlick.width - Metrics.spaceMd * 4
                - Metrics.iconLg - widestCount.implicitWidth
            readonly property bool named: nameRoom >= Metrics.formLabelWidth

            ShellText {
                id: widestCount
                visible: false
                role: "small"
                text: String(sidebar.categories.reduce((most, item) => Math.max(most, item.count), 0))
            }

            Flickable {
                id: categoryFlick
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                contentHeight: categoryColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollFeel { view: categoryFlick }

                ColumnLayout {
                    id: categoryColumn
                    width: categoryFlick.width
                    spacing: Metrics.spaceXxs
                    Repeater {
                        model: sidebar.categories
                        Item {
                            id: categoryEntry
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: categoryRow.implicitHeight

                            ListRow {
                                id: categoryRow
                                anchors.fill: parent
                                compact: true
                                level: 1
                                icon: categoryEntry.modelData.icon
                                title: sidebar.named ? categoryEntry.modelData.name : ""
                                Accessible.name: categoryEntry.modelData.name
                                trailingText: String(categoryEntry.modelData.count)
                                selected: root.category === categoryEntry.modelData.name
                                onClicked: {
                                    nameTip.release()
                                    root.category = categoryEntry.modelData.name
                                    root.selectedIndex = 0
                                }
                            }
                            // Over the row rather than in it: what a ListRow
                            // holds goes to its trailing slot, and a parent's
                            // hover is not a promise once the row's own
                            // MouseArea takes it. A HoverHandler does not block
                            // what is under it, so the row keeps its hover.
                            Item {
                                anchors.fill: parent
                                HoverHandler { onHoveredChanged: hovered ? nameTip.arm() : nameTip.release() }
                                ToolTipHost {
                                    id: nameTip
                                    anchorItem: categoryRow
                                    text: sidebar.named ? "" : categoryEntry.modelData.name
                                    onTextChanged: if (!text.length) release()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: categoriesBlock
        // **The shape follows the cell**, which is the whole point of a grid:
        // a tall narrow block is the list down the side, a wide short one is a
        // row of chips. There is no rule about where the categories sit any
        // more - drag them anywhere, pull them to any size, and they draw
        // whichever way fits what you made.
        // Measured on the block itself, which the slot sizes to the cell;
        // its parent is null for the first moment, and "null" read as chips.
        Loader {
            readonly property bool tall: height > width
            sourceComponent: tall ? categorySidebar : categoryChips
        }
    }

    Component {
        id: categoryChips
        Flow {
            spacing: Metrics.spaceXs

            Repeater {
                // Hidden, no chips; see the pinned row.
                model: root.shown ? LauncherService.availableCategories : []
                ChipButton {
                    required property var modelData
                    title: modelData.name + "  " + modelData.count
                    icon: modelData.icon
                    active: root.category === modelData.name
                    compact: true
                    onClicked: { root.category = modelData.name; root.selectedIndex = 0 }
                }
            }
        }
    }

    Component {
        id: resultsBlock
        RowLayout {
            spacing: Metrics.spaceMd


            ShellCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                level: 1

                ListView {
                    id: list
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Metrics.spaceSm
                    clip: true
                    spacing: Metrics.spaceXxs
                    // Whole rows only. The cell's height is a share of the
                    // grid and no multiple of a row, so the list used to end
                    // on a row cut in half, which read as a bug. The last row
                    // is now complete and the remainder is card below it;
                    // n rows take n pitches less one spacing.
                    readonly property real pitch: Metrics.rowHeight + spacing
                    readonly property real room: parent.height - Metrics.spaceSm * 2
                    height: Math.max(pitch, Math.floor((room + spacing) / pitch) * pitch) - spacing
                    model: root.results
                    currentIndex: root.selectedIndex
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !root.editing
                    ScrollFeel { view: list }

                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        level: 1
                        width: list.width
                        // The row height, no more: a list of forty-eight-pixel
                        // rows reads as a list, and the four pixels on top of
                        // each were a quarter of a row lost over eight of them.
                        // The calculator's row keeps its room for the big result.
                        implicitHeight: modelData.kind === "calculator" ? Metrics.rowHeight + Metrics.spaceLg : Metrics.rowHeight
                        selected: index === root.selectedIndex
                        icon: modelData.icon || ""
                        iconSource: modelData.iconSource || ""
                        title: modelData.title
                        subtitle: modelData.subtitle || ""
                        trailingText: index === root.selectedIndex ? "↵" : ""
                        onClicked: { root.selectedIndex = index; root.run(false) }
                        // Right-click pins an app, and pins are what the row
                        // above shows. Ctrl+P does the same for whatever is
                        // selected, so it is reachable without the pointer.
                        onRightClicked: if (modelData.appId) LauncherService.togglePin(modelData.appId)
                        ShellIcon {
                            visible: modelData.appId !== undefined && LauncherService.isPinned(modelData.appId)
                            glyph: "󰐃"
                            size: Metrics.iconXs
                            color: Colors.accentForeground
                        }
                    }
                }
                // Beside the list, not in it: a ListView hands its children to
                // its content item, which is 0 px tall while there are no
                // results, so the hint was centred on the list's top edge and
                // its upper half clipped away.
                EmptyState {
                    anchors.centerIn: list
                    visible: root.results.length === 0
                    icon: root.mode.id === "files" && LauncherService.fileSearchRunning ? Icons.busy : root.mode.icon
                    title: root.mode.id === "files" ? (root.query.length < 3 ? "Type a file name" : LauncherService.fileSearchRunning ? "Searching …" : "No files found")
                        : root.mode.id === "calculator" ? "Calculator"
                        : "No results"
                    description: root.mode.id === "calculator" ? "Type an expression, e.g. = 12 * (3 + 4)" : ""
                }
            }
        }
    }
}
