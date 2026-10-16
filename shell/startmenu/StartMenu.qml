import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/startmenu/StartMenuLogic.js" as Logic
import "../../services/launcher/Usage.js" as Usage
import "../../services/launcher/Pinned.js" as Pinned
import "../../services/lock/LockLogic.js" as LockLogic

// The start menu: what the dock's start button opens (shell/widgets/
// StartWidget.qml), above the button on a taskbar, beside it on a side dock.
//
//   the fastfetch Saturn, user · host, the os, kernel and uptime
//   a search - the launcher's own, prefixes and all
//   Pinned: the launcher's pins          All apps ›  (A to Z)
//   Frequent: the apps started most (the launcher's history)
//   the places: Home and the user's folders
//   the user, Settings, Lock, the power button
//
// The keyboard stays in the search field the whole time; the arrows, Tab
// and Enter move and run a selection over the rest (StartMenuLogic.move).
// A right click or the menu key opens an app's menu inside the card.
//
// One size whatever it shows, so the surface never changes size while it is
// open (testing.md pitfall 57). Everything below is built while it is shown
// and gone when it closes: the panel itself is only there for a dock with a
// start button (shell.qml).
ShellPanel {
    id: root
    panelId: "startMenu"
    placement: "center"
    cardWidth: Metrics.startMenuWidth
    cardHeight: Metrics.startMenuHeight
    // A menu: it does not dim the screen.
    scrimColor: "transparent"
    followClock: false
    followBarSpot: false
    outOfNotch: false
    keyForward: searchField
    escapeHandler: () => root.face !== null && root.face.stepBack()

    // Handed over by the content, which lives in a Loader.
    property Item searchField: null
    property Item face: null

    // The display name, read once (the passwd entry does not change while
    // the session runs).
    readonly property string user: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    property string displayName: ""
    property bool nameRead: false
    Process {
        running: root.shown && !root.nameRead && root.user.length > 0
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector {
            onStreamFinished: { root.displayName = LockLogic.displayName(text, root.user); root.nameRead = true }
        }
        onExited: root.nameRead = true
    }

    // For `startMenu get`: counts and flags, never a name.
    function describe() {
        const f = face
        return JSON.stringify({
            open: wanted, shown: shown, view: f ? f.shownView : "", pinned: f ? f.pinnedApps.length : 0,
            frequent: f ? f.frequentApps.length : 0, apps: f ? f.allApps.ids.length : 0,
            results: f ? f.results.length : 0, places: f ? f.placeList.length : 0,
            zone: f ? f.selection.zone : "", index: f ? f.selection.index : 0, menuOpen: f ? f.menu !== null : false
        })
    }
    // For `startMenu rects`: the card on its screen, screen-local.
    function cardPlace() {
        return { x: Math.round(card.placedX), y: Math.round(card.placedY),
                 width: Math.round(card.targetWidth), height: Math.round(card.targetHeight) }
    }
    function openView(view) { if (face) face.view = view === "all" ? "all" : "home" }

    Loader {
        anchors.fill: parent
        active: root.shown
        sourceComponent: Component {
            Item {
                id: face
                Component.onCompleted: root.face = face
                Component.onDestruction: if (root.face === face) root.face = null

                // ---- state ------------------------------------------------------
                property string query: ""
                // "home" or "all" (`startMenu openView all`); a query shows
                // the results over either.
                property string view: root.openArgs && root.openArgs.startView === "all" ? "all" : "home"
                readonly property bool searching: query.length > 0
                readonly property string shownView: searching ? "search" : view
                property var selection: ({ zone: "", index: 0 })
                // { kind: "app" | "power", entry, source, index, dock, at } or null
                property var menu: null
                // The item the selection is on, for the menu key to open beside.
                property Item selectedItem: null

                // ---- what it shows ------------------------------------------------
                readonly property var pinnedApps: LauncherService.pinnedApps
                readonly property var frequentApps: Logic.frequent(Usage.top(LauncherService.usage, Date.now()),
                                                                   LauncherService.visibleApps(),
                                                                   pinnedApps.map(app => app.id), Metrics.startMenuFrequent)
                readonly property var allApps: view === "all" ? Logic.alphabet(LauncherService.visibleApps())
                                                              : ({ rows: [], ids: [], letters: [] })
                readonly property var allRowByKey: {
                    const table = {}
                    for (const row of allApps.rows) table[row.key] = row
                    return table
                }
                readonly property var results: searching ? LauncherService.results(query, "All") : []
                property var placeList: []
                readonly property var footerKinds: ["settings", "lock", "power"]
                property var logo: ({ rows: 0, columns: 0, runs: [] })
                property string host: ""
                property string kernel: ""
                property int uptime: -1
                readonly property var info: Logic.infoRows(DistroService.info.PRETTY_NAME || DistroService.name, kernel, uptime)

                readonly property var zones: shownView === "search" ? [{ id: "results", count: results.length, columns: 1 }]
                    : shownView === "all" ? [{ id: "all", count: allApps.ids.length, columns: 1 },
                                             { id: "footer", count: footerKinds.length, columns: footerKinds.length }]
                    : [{ id: "pinned", count: pinnedApps.length, columns: Metrics.startMenuColumns },
                       { id: "frequent", count: frequentApps.length, columns: Metrics.startMenuFrequentColumns },
                       { id: "places", count: placeList.length, columns: Metrics.startMenuPlaceColumns },
                       { id: "footer", count: footerKinds.length, columns: footerKinds.length }]

                function isSelected(zone, index) { return selection.zone === zone && selection.index === index }

                onQueryChanged: {
                    // The emoji list is read only when it is asked for.
                    if (query.charAt(0) === ":") EmojiService.load()
                    menu = null
                }
                // A query selects its first result, so Enter runs it; going
                // back to the pins or the list starts in the field again.
                onShownViewChanged: {
                    menu = null
                    selection = shownView === "search" ? { zone: "results", index: 0 } : { zone: "", index: 0 }
                }
                onResultsChanged: if (searching && selection.zone === "results")
                    selection = { zone: "results", index: Math.min(selection.index, Math.max(0, results.length - 1)) }

                // The grids keep their columns however few they hold.
                readonly property real tileWidth: (width - Metrics.spaceSm * (Metrics.startMenuColumns - 1)) / Metrics.startMenuColumns
                readonly property real placeWidth: (width - Metrics.spaceSm * (Metrics.startMenuPlaceColumns - 1)) / Metrics.startMenuPlaceColumns

                // ---- the files it reads -------------------------------------------
                FileView {
                    path: Quickshell.shellPath("config/builtin-profiles/buchhwin/saturn.txt")
                    blockLoading: true
                    printErrors: false
                    onLoaded: face.logo = Logic.asciiRuns(text())
                }
                FileView {
                    path: "/proc/sys/kernel/hostname"
                    blockLoading: true
                    printErrors: false
                    onLoaded: face.host = text().trim()
                }
                FileView {
                    path: "/proc/sys/kernel/osrelease"
                    blockLoading: true
                    printErrors: false
                    onLoaded: face.kernel = text().trim()
                }
                FileView {
                    id: uptimeFile
                    path: "/proc/uptime"
                    blockLoading: true
                    printErrors: false
                    onLoaded: face.uptime = Logic.uptimeSeconds(text())
                }
                Timer { interval: Animations.startMenuUptimeRefresh; running: true; repeat: true; onTriggered: uptimeFile.reload() }
                FileView {
                    path: (Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config") + "/user-dirs.dirs"
                    printErrors: false
                    onLoaded: face.placeList = Logic.places(text(), Paths.home)
                    onLoadFailed: face.placeList = Logic.places("", Paths.home)
                }

                // ---- what the keys and clicks do ------------------------------------
                function entryAt(zone, index) {
                    if (zone === "pinned") return pinnedApps[index] || null
                    if (zone === "frequent") return frequentApps[index] || null
                    if (zone === "all") return allApps.ids[index] ? DesktopEntries.byId(allApps.ids[index]) : null
                    if (zone === "results") {
                        const result = results[index]
                        return result && result.appId ? DesktopEntries.byId(result.appId) : null
                    }
                    return null
                }

                function launch(entry) {
                    if (!entry) return
                    PanelService.close("startMenu")
                    LauncherService.launchApp(entry)
                }

                function openPlace(place) {
                    if (!place) return
                    PanelService.close("startMenu")
                    Quickshell.execDetached(["xdg-open", place.path])
                }

                function footerAction(kind, item) {
                    if (kind === "settings") PanelService.open("settings")
                    else if (kind === "lock") { PanelService.close("startMenu"); SessionService.run("lock") }
                    else if (kind === "power") openPowerMenu(item)
                }

                function activate(zone, index, alternate) {
                    if (zone === "results") {
                        const result = results[index]
                        if (!result) return
                        PanelService.close("startMenu")
                        if (alternate && result.alternate) result.alternate()
                        else result.run()
                    } else if (zone === "places") {
                        openPlace(placeList[index])
                    } else if (zone === "footer") {
                        footerAction(footerKinds[index], selectedItem)
                    } else {
                        launch(entryAt(zone, index))
                    }
                }

                function togglePinSelected() {
                    const entry = entryAt(selection.zone, selection.index)
                    if (entry) LauncherService.togglePin(entry.id)
                }

                function moveSelection(key) {
                    selection = Logic.move(selection, key, zones, Metrics.startMenuPage)
                    if (selection.zone === "") selectedItem = null
                }

                // Escape: the menu first, then All apps; a typed query has
                // been cleared by the field before this is asked.
                function stepBack() {
                    if (menu) { closeMenu(); return true }
                    if (view === "all") { view = "home"; return true }
                    return false
                }

                // ---- the menus ------------------------------------------------------
                function placeOf(item) {
                    if (!item) return { x: 0, y: 0, width: 0, height: 0 }
                    const topLeft = item.mapToItem(menuLayer, 0, 0)
                    return { x: topLeft.x, y: topLeft.y, width: item.width, height: item.height }
                }

                function openAppMenu(entry, source, index, item) {
                    if (!entry) return
                    const pins = LayoutService.dockLayout.pins || []
                    const dock = Logic.dockState(pins, entry.id, DefaultAppsService.categories)
                    const pinned = LauncherService.isPinned(entry.id)
                    const rows = Logic.appMenuRows({
                        source: source, pinned: pinned, pinnedFull: LauncherService.pinnedFull,
                        pinIndex: pinnedApps.findIndex(app => app.id === entry.id), pinCount: pinnedApps.length,
                        dockEnabled: SettingsService.value("dock.enabled") === true, inDock: dock.pinned,
                        dockFull: LayoutService.dockPinsFull, actions: entry.actions
                    }).map(row => Object.assign(row, rowLook(row, entry)))
                    menu = { kind: "app", entry: entry, source: source, index: index, dock: dock, rows: rows, at: placeOf(item) }
                    contextMenu.forceActiveFocus()
                }

                function openPowerMenu(item) {
                    const rows = Logic.powerRows().map(row => Object.assign(row, rowLook(row, null)))
                    menu = { kind: "power", rows: rows, at: placeOf(item), above: true }
                    contextMenu.forceActiveFocus()
                }

                function closeMenu() {
                    menu = null
                    if (root.searchField) root.searchField.focusInput()
                }

                function rowLook(row, entry) {
                    switch (row.kind) {
                    case "open": return { label: "Open", iconSource: entry ? LauncherService.iconSource(entry.icon) : "" }
                    case "action": return { label: row.name, icon: Icons.forward }
                    case "pinStart": return { label: "Pin to Start", icon: Icons.pin, hint: "At most " + Pinned.LIMIT + " pinned apps" }
                    case "unpinStart": return { label: "Unpin from Start", icon: Icons.unpin }
                    case "moveLeft": return { label: "Move left", icon: Icons.back }
                    case "moveRight": return { label: "Move right", icon: Icons.forward }
                    case "pinDock": return { label: "Pin to dock", icon: Icons.dock, hint: "At most " + LayoutService.dockPinLimit + " apps on the dock" }
                    case "unpinDock": return { label: "Unpin from dock", icon: Icons.unpin }
                    case "suspend": return { label: "Sleep", icon: Icons.suspend }
                    case "logout": return { label: "Log out …", icon: Icons.logout }
                    case "reboot": return { label: "Restart …", icon: Icons.reboot }
                    case "poweroff": return { label: "Shut down …", icon: Icons.poweroff }
                    }
                    return { label: row.kind }
                }

                function runMenuRow(row) {
                    const open = menu
                    closeMenu()
                    if (!open || !row) return
                    const entry = open.entry
                    switch (row.kind) {
                    case "open": launch(entry); break
                    case "action": {
                        const action = Array.prototype.slice.call(entry.actions || []).find(item => item && item.id === row.id)
                        PanelService.close("startMenu")
                        LauncherService.launchAction(entry, action)
                        break
                    }
                    case "pinStart": case "unpinStart": LauncherService.togglePin(entry.id); break
                    case "moveLeft": LauncherService.movePinned(entry.id, -1); break
                    case "moveRight": LauncherService.movePinned(entry.id, 1); break
                    case "pinDock": LayoutService.dockPin(entry.id); break
                    case "unpinDock": LayoutService.dockUnpin(open.dock.pin); break
                    case "suspend": PanelService.close("startMenu"); SessionService.run("suspend"); break
                    // The power menu asks, as it does from the launcher.
                    case "logout": case "reboot": case "poweroff": PanelService.open("powerMenu", { confirm: row.kind }); break
                    }
                }

                function openMenuForSelection() {
                    if (selection.zone === "footer" && footerKinds[selection.index] === "power") { openPowerMenu(selectedItem); return }
                    const entry = entryAt(selection.zone, selection.index)
                    if (entry) openAppMenu(entry, selection.zone, selection.index, selectedItem)
                }

                // ---- the face ---------------------------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Metrics.panelGap

                    // fastfetch, small: the logo, and beside it its title and rows.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SaturnAscii {
                            Layout.alignment: Qt.AlignVCenter
                            logo: face.logo
                            visible: face.logo.runs.length > 0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Metrics.spaceXxs

                            Row {
                                ShellText {
                                    text: root.user
                                    color: Colors.saturnPlanet
                                    font.family: Typography.monoFamily
                                    font.weight: Typography.bold
                                }
                                ShellText {
                                    text: " · "
                                    color: Colors.saturnRing
                                    font.family: Typography.monoFamily
                                }
                                ShellText {
                                    text: face.host
                                    color: Colors.saturnPlanet
                                    font.family: Typography.monoFamily
                                    font.weight: Typography.bold
                                }
                            }
                            Row {
                                ShellText { text: "──────── "; color: Colors.saturnRing; font.family: Typography.monoFamily; role: "small" }
                                ShellText { text: "✦"; color: Colors.saturnPlanet; font.family: Typography.monoFamily; role: "small" }
                                ShellText { text: " ────────"; color: Colors.saturnRing; font.family: Typography.monoFamily; role: "small" }
                            }
                            GridLayout {
                                columns: 3
                                columnSpacing: Metrics.spaceSm
                                rowSpacing: 0
                                Repeater {
                                    model: face.info.length * 3
                                    ShellText {
                                        required property int index
                                        readonly property var row: face.info[Math.floor(index / 3)]
                                        readonly property int part: index % 3
                                        text: !row ? "" : part === 0 ? row.branch : part === 1 ? row.key : row.value
                                        color: part === 0 ? Colors.saturnRing : part === 1 ? Colors.saturnPlanet : Colors.text
                                        font.family: Typography.monoFamily
                                        role: "small"
                                        elide: part === 2 ? Text.ElideRight : Text.ElideNone
                                        Layout.fillWidth: part === 2
                                    }
                                }
                            }
                        }
                    }

                    ShellTextField {
                        id: search
                        Component.onCompleted: root.searchField = search
                        Component.onDestruction: if (root.searchField === search) root.searchField = null
                        Layout.fillWidth: true
                        // It holds the focus for as long as the menu is open.
                        focusOutline: false
                        icon: Icons.search
                        placeholder: "Search apps, settings, files …"
                        onTextChanged: face.query = text
                        onKeyPressed: event => {
                            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                            const shift = (event.modifiers & Qt.ShiftModifier) !== 0
                            const zone = face.zones.find(item => item.id === face.selection.zone)
                            // In the field, or in a list of one column, Left
                            // and Right are the text cursor's.
                            const sideways = event.key === Qt.Key_Left || event.key === Qt.Key_Right
                            if (sideways && (!zone || zone.columns <= 1)) { event.accepted = false; return }
                            event.accepted = true
                            if (event.key === Qt.Key_Down) face.moveSelection("down")
                            else if (event.key === Qt.Key_Up) face.moveSelection("up")
                            else if (event.key === Qt.Key_Left) face.moveSelection("left")
                            else if (event.key === Qt.Key_Right) face.moveSelection("right")
                            else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && shift)) face.moveSelection("backtab")
                            else if (event.key === Qt.Key_Tab) face.moveSelection("tab")
                            else if (event.key === Qt.Key_Home && ctrl) face.moveSelection("home")
                            else if (event.key === Qt.Key_End && ctrl) face.moveSelection("end")
                            else if (event.key === Qt.Key_PageDown) face.moveSelection("pageDown")
                            else if (event.key === Qt.Key_PageUp) face.moveSelection("pageUp")
                            else if (event.key === Qt.Key_P && ctrl) face.togglePinSelected()
                            else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && shift)) face.openMenuForSelection()
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (face.selection.zone.length) face.activate(face.selection.zone, face.selection.index, ctrl)
                                else if (face.searching) face.activate("results", 0, ctrl)
                            }
                            else event.accepted = false
                        }
                    }

                    // ---- home ------------------------------------------------------------
                    ColumnLayout {
                        visible: face.shownView === "home"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Metrics.panelGap

                        // Each section's label sits close to what it names.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXs
                            RowLayout {
                                Layout.fillWidth: true
                                SectionLabel { text: "Pinned"; Layout.fillWidth: true }
                                ShellButton {
                                    text: "All apps"
                                    icon: Icons.forward
                                    variant: "ghost"
                                    compact: true
                                    onClicked: face.view = "all"
                                }
                            }
                            EmptyState {
                                Layout.fillWidth: true
                                visible: face.pinnedApps.length === 0
                                row: true
                                title: "Nothing pinned yet"
                                description: "Right-click an app to pin it"
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                visible: face.pinnedApps.length > 0
                                columns: Metrics.startMenuColumns
                                columnSpacing: Metrics.spaceSm
                                rowSpacing: Metrics.spaceSm
                                Repeater {
                                    model: face.pinnedApps
                                    ShellCard {
                                        id: tile
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: face.isSelected("pinned", index)
                                        onChosenChanged: if (chosen) face.selectedItem = tile
                                        Layout.preferredWidth: face.tileWidth
                                        Layout.preferredHeight: Metrics.startMenuTileHeight
                                        level: 1
                                        interactive: true
                                        hovered: tileMouse.containsMouse
                                        pressed: tileMouse.pressed && tileMouse.containsMouse
                                        highlighted: chosen

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            width: parent.width - Metrics.spaceSm * 2
                                            spacing: Metrics.spaceXs
                                            // A plain Image, the launcher's way: an app
                                            // icon is already whatever shape it is.
                                            Image {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredWidth: Metrics.iconXl
                                                Layout.preferredHeight: Metrics.iconXl
                                                source: LauncherService.iconSource(tile.modelData.icon)
                                                sourceSize.width: Metrics.iconXl * 2
                                                sourceSize.height: Metrics.iconXl * 2
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                            }
                                            ShellText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: tile.modelData.name || tile.modelData.id
                                                role: "small"
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                        }
                                        MouseArea {
                                            id: tileMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) face.openAppMenu(tile.modelData, "pinned", tile.index, tile)
                                                else face.launch(tile.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: face.frequentApps.length > 0
                            spacing: Metrics.spaceXs
                            SectionLabel { text: "Frequent" }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: Metrics.startMenuFrequentColumns
                                columnSpacing: Metrics.spaceSm
                                rowSpacing: Metrics.spaceXxs
                                Repeater {
                                    model: face.frequentApps
                                    ListRow {
                                        id: frequentRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: face.isSelected("frequent", index)
                                        onChosenChanged: if (chosen) face.selectedItem = frequentRow
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        level: 1
                                        selected: chosen
                                        iconSource: LauncherService.iconSource(modelData.icon)
                                        title: modelData.name || modelData.id
                                        subtitle: modelData.genericName || ""
                                        onClicked: face.launch(modelData)
                                        onRightClicked: face.openAppMenu(modelData, "frequent", index, frequentRow)
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: face.placeList.length > 0
                            spacing: Metrics.spaceXs
                            SectionLabel { text: "Places" }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: Metrics.startMenuPlaceColumns
                                columnSpacing: Metrics.spaceSm
                                rowSpacing: Metrics.spaceSm
                                Repeater {
                                    model: face.placeList
                                    ChipButton {
                                        id: placeChip
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: face.isSelected("places", index)
                                        onChosenChanged: if (chosen) face.selectedItem = placeChip
                                        Layout.preferredWidth: face.placeWidth
                                        compact: true
                                        icon: modelData.glyph
                                        title: modelData.label
                                        onClicked: face.openPlace(modelData)
                                        FocusRing { active: placeChip.chosen; controlRadius: placeChip.radius }
                                    }
                                }
                            }
                        }
                    }

                    // ---- all apps ---------------------------------------------------------
                    ColumnLayout {
                        visible: face.shownView === "all"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Metrics.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            ShellButton {
                                text: "Back"
                                icon: Icons.back
                                variant: "ghost"
                                compact: true
                                onClicked: face.view = "home"
                            }
                            ShellText { text: "All apps"; role: "title"; Layout.fillWidth: true }
                            ShellText { text: face.allApps.ids.length + " apps"; role: "small"; muted: true }
                        }
                        ShellCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            level: 1

                            ListView {
                                id: allList
                                anchors.fill: parent
                                anchors.margins: Metrics.spaceSm
                                clip: true
                                spacing: Metrics.spaceXxs
                                boundsBehavior: Flickable.StopAtBounds
                                // Keyed by the rows' strings: a new scan keeps the
                                // delegates and the place in the list (pitfall 76).
                                model: ScriptModel { values: face.allApps.rows.map(row => row.key) }
                                ScrollFeel { view: allList }
                                readonly property int selectedRow: face.selection.zone === "all"
                                    ? face.allApps.rows.findIndex(row => row.kind === "app" && row.appIndex === face.selection.index) : -1
                                onSelectedRowChanged: if (selectedRow >= 0) positionViewAtIndex(selectedRow, ListView.Contain)

                                delegate: Item {
                                    id: allRow
                                    required property var modelData
                                    readonly property var row: face.allRowByKey[modelData] || null
                                    readonly property bool header: row !== null && row.kind === "header"
                                    readonly property var entry: row && !header ? DesktopEntries.byId(row.id) : null
                                    readonly property bool chosen: row !== null && !header && face.isSelected("all", row.appIndex)
                                    onChosenChanged: if (chosen) face.selectedItem = allRow
                                    width: allList.width
                                    height: header ? Metrics.controlHeightSm : Metrics.rowHeight

                                    SectionLabel {
                                        visible: allRow.header
                                        anchors.left: parent.left
                                        anchors.leftMargin: Metrics.spaceSm
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Metrics.spaceXxs
                                        text: allRow.row ? allRow.row.letter : ""
                                    }
                                    ListRow {
                                        visible: !allRow.header && allRow.entry !== null
                                        anchors.fill: parent
                                        level: 1
                                        selected: allRow.chosen
                                        iconSource: allRow.entry ? LauncherService.iconSource(allRow.entry.icon) : ""
                                        title: allRow.entry ? allRow.entry.name || allRow.entry.id : ""
                                        subtitle: allRow.entry ? allRow.entry.genericName || "" : ""
                                        onClicked: face.launch(allRow.entry)
                                        onRightClicked: face.openAppMenu(allRow.entry, "all", allRow.row.appIndex, allRow)
                                        ShellIcon {
                                            visible: allRow.entry !== null && LauncherService.isPinned(allRow.entry.id)
                                            glyph: Icons.pin
                                            size: Metrics.iconXs
                                            color: Colors.accentForeground
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- results ----------------------------------------------------------
                    ShellCard {
                        visible: face.shownView === "search"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        level: 1

                        ListView {
                            id: resultList
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceSm
                            clip: true
                            spacing: Metrics.spaceXxs
                            boundsBehavior: Flickable.StopAtBounds
                            model: face.results
                            ScrollFeel { view: resultList }
                            readonly property int selectedRow: face.selection.zone === "results" ? face.selection.index : -1
                            onSelectedRowChanged: if (selectedRow >= 0) positionViewAtIndex(selectedRow, ListView.Contain)

                            delegate: ListRow {
                                id: resultRow
                                required property var modelData
                                required property int index
                                readonly property bool chosen: face.isSelected("results", index)
                                onChosenChanged: if (chosen) face.selectedItem = resultRow
                                width: resultList.width
                                level: 1
                                implicitHeight: modelData.kind === "calculator" ? Metrics.rowHeight + Metrics.spaceLg : Metrics.rowHeight
                                selected: chosen
                                icon: modelData.icon || ""
                                iconSource: modelData.iconSource || ""
                                title: modelData.title
                                subtitle: modelData.subtitle || ""
                                trailingText: chosen ? "↵" : ""
                                onClicked: face.activate("results", index, false)
                                onRightClicked: if (modelData.appId) face.openAppMenu(DesktopEntries.byId(modelData.appId), "results", index, resultRow)
                                ShellIcon {
                                    visible: modelData.appId !== undefined && LauncherService.isPinned(modelData.appId)
                                    glyph: Icons.pin
                                    size: Metrics.iconXs
                                    color: Colors.accentForeground
                                }
                            }
                        }
                        EmptyState {
                            anchors.centerIn: parent
                            visible: face.results.length === 0
                            icon: Icons.search
                            title: "No results"
                        }
                    }

                    // ---- the user and the way out -------------------------------------------
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Metrics.borderWidth
                        color: Colors.border
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceSm

                        Rectangle {
                            implicitWidth: Metrics.startMenuAvatar
                            implicitHeight: Metrics.startMenuAvatar
                            radius: width / 2
                            color: Colors.accent
                            ShellText {
                                anchors.centerIn: parent
                                text: LockLogic.initial(root.displayName || root.user)
                                color: Colors.accentText
                                font.pixelSize: Typography.startAvatarInitialSize
                                font.weight: Typography.semibold
                            }
                        }
                        ShellText {
                            Layout.fillWidth: true
                            text: root.displayName || root.user
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: face.footerKinds
                            ShellButton {
                                id: footerButton
                                required property string modelData
                                required property int index
                                readonly property bool chosen: face.isSelected("footer", index)
                                onChosenChanged: if (chosen) face.selectedItem = footerButton
                                icon: modelData === "settings" ? Icons.settings : modelData === "lock" ? Icons.lock : Icons.poweroff
                                toolTip: modelData === "settings" ? "Settings" : modelData === "lock" ? "Lock" : "Power"
                                variant: "ghost"
                                iconSize: Metrics.iconMd
                                onClicked: face.footerAction(modelData, footerButton)
                                FocusRing { active: footerButton.chosen; controlRadius: footerButton.radius }
                            }
                        }
                    }
                }

                // ---- the menu, over everything in the card ---------------------------------
                Item {
                    id: menuLayer
                    anchors.fill: parent
                    z: 10
                    visible: face.menu !== null

                    // A click anywhere else closes it.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: face.closeMenu()
                    }
                    StartContextMenu {
                        id: contextMenu
                        readonly property var at: face.menu ? face.menu.at : ({ x: 0, y: 0, width: 0, height: 0 })
                        readonly property bool above: face.menu !== null && face.menu.above === true
                        rows: face.menu ? face.menu.rows : []
                        x: Math.max(0, Math.min(menuLayer.width - width,
                                                above ? at.x + at.width - width : at.x + Metrics.spaceSm))
                        y: !above && at.y + at.height + Metrics.spaceXs + height <= menuLayer.height
                            ? at.y + at.height + Metrics.spaceXs
                            : Math.max(0, at.y - height - Metrics.spaceXs)
                        onPicked: row => face.runMenuRow(row)
                        onDismissed: face.closeMenu()
                        onTyped: text => {
                            face.closeMenu()
                            if (root.searchField) root.searchField.text += text
                        }
                    }
                }
            }
        }
    }
}
