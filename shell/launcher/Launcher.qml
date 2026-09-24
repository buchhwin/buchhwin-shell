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
    cardHeight: sizing ? dragHeight : (box.height > 0 ? box.height : Metrics.launcherHeight)
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
    // beside the result list - and the user asked for the grid the rest of the
    // shell has instead, twice. A block goes where it is put and is the size
    // it is dragged to; nothing here decides that for it any more.
    readonly property var blocks: LayoutService.launcherItems

    onWantedChanged: {
        if (wanted) {
            if (searchField) searchField.text = ""
            query = ""
            category = "All"
            selectedIndex = 0
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
            - (root.editing ? editBar.implicitHeight + Metrics.spaceMd : 0))
    readonly property int gridRows: root.editing ? LauncherCatalogue.rows : Math.max(1, grid.rowsUsed)
    readonly property real gridUnit:
        (gridRoom - Metrics.spaceMd * (gridRows - 1)) / gridRows

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.spaceMd

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

            Repeater {
                model: root.blocks
                LauncherSlot {
                    required property var modelData
                    required property int index
                    area: grid
                    blockId: modelData.id
                    type: modelData.type
                    label: LayoutService.launcherLabel(modelData.type)
                    removable: !LauncherCatalogue.fixed(modelData.type)
                    // The pinned row is there before the query and gone the
                    // moment there is one - gone, not blank: a block that
                    // shows nothing holds no row, and the result list takes
                    // it. While arranging it holds its place, or it could not
                    // be dragged.
                    holds: modelData.type !== "pinned" || root.editing || root.pinnedShown
                    slotIndex: index
                    content: root.blockFor(modelData.type)
                    onResized: (w, h) => LayoutService.launcherSetSize(modelData.id, w, h)
                }
            }
        }

        // One compact row while arranging: the blocks that are off, undo, the
        // way back, and Done. The pencil sits in the search field's row, which
        // wiggles and dims while arranging - so unlike the dashboard's, it
        // cannot be the way out and there is a button here for it.
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
            spacing: Metrics.spaceMd

            ShellTextField {
                id: search
                Component.onCompleted: root.searchField = search
                Component.onDestruction: if (root.searchField === search) root.searchField = null
                Layout.fillWidth: true
                large: true
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
                icon: Icons.edit
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
                visible: !modesCell.fits
                anchors.fill: parent
                spacing: Metrics.spaceXs
                ShellButton {
                    icon: Icons.back
                    compact: true
                    toolTip: "Previous mode"
                    onClicked: root.cycleMode(-1)
                }
                ShellIcon {
                    glyph: root.mode.icon
                    size: Metrics.iconSm
                    color: Colors.accentForeground
                }
                ShellText {
                    Layout.fillWidth: true
                    text: root.mode.label
                    elide: Text.ElideRight
                }
                ShellButton {
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
                model: root.pinnedShown || root.editing ? LauncherService.pinnedApps : []

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
            level: 1

            Flickable {
                id: categoryFlick
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                contentHeight: categoryColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: categoryColumn
                    width: categoryFlick.width
                    spacing: Metrics.spaceXxs
                    Repeater {
                        model: LauncherService.availableCategories
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            compact: true
                            level: 1
                            icon: modelData.icon
                            title: modelData.name
                            trailingText: String(modelData.count)
                            selected: root.category === modelData.name
                            onClicked: { root.category = modelData.name; root.selectedIndex = 0 }
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
                model: LauncherService.availableCategories
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
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceSm
                    clip: true
                    spacing: Metrics.spaceXxs
                    model: root.results
                    currentIndex: root.selectedIndex
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !root.editing

                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        level: 1
                        width: list.width
                        implicitHeight: modelData.kind === "calculator" ? Metrics.rowHeight + Metrics.spaceLg : Metrics.rowHeight + Metrics.spaceXs
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

                    EmptyState {
                        anchors.centerIn: parent
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
}
