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
//   the fastfetch logo (the user's, else the Saturn), user · host, the os,
//     kernel and uptime - one line of it in All apps and the results
//   a search - the launcher's own, prefixes and all
//   Pinned: the launcher's pins          All apps ›  (A to Z)
//     with nothing pinned: the default apps and Settings, suggested
//   Frequent: the apps started most (the launcher's history)
//   the places: Home and the user's folders
//   the user, Settings, Lock, the power button
//
// The keyboard stays in the search field the whole time; the arrows, Tab
// and Enter move and run a selection over the rest (StartMenuLogic.move).
// A right click or the menu key opens an app's menu inside the card.
//
// One size whatever it shows, so the surface never changes size while it is
// open (testing.md pitfall 57). The face is built while it is shown and gone
// when it closes; what does not change while the session runs (the logo,
// the host, the kernel, the places) is read once, here. The panel itself is
// built on its first open (shell.qml, PanelService.demanded).
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

    // ---- read once ------------------------------------------------------------
    // The logo the user's fastfetch draws (StartMenuLogic.textLogo): written
    // into its configuration, or a file - the configuration's, the user's
    // Saturn, the shipped one, the first that holds one. Watched, so a logo
    // picked in Settings > Terminal shows at the next open.
    readonly property var emptyLogo: ({ rows: 0, columns: 0, runs: [] })
    property var logoSpec: ({})
    readonly property var inlineLogo: logoSpec.text !== undefined ? Logic.asciiRuns(logoSpec.text) : emptyLogo
    readonly property var logoPaths: Logic.logoPaths(logoSpec, Paths.configDir + "/saturn.txt",
                                                     Quickshell.shellPath("config/builtin-profiles/buchhwin/saturn.txt"))
    property int logoTry: 0
    onLogoPathsChanged: logoTry = 0
    property var fileLogo: emptyLogo
    readonly property var logo: inlineLogo.runs.length ? inlineLogo : fileLogo
    // On to the next file when `path` held none - unless the list moved on
    // meanwhile (the configuration read after the first try failed).
    function skipLogo(path) {
        if (logoPaths[logoTry] !== path) return
        if (logoTry + 1 < logoPaths.length) logoTry += 1
        else fileLogo = emptyLogo
    }
    function takeLogo(path, text) {
        const parsed = Logic.asciiRuns(text)
        if (!parsed.runs.length) { Qt.callLater(skipLogo, path); return }
        fileLogo = parsed
    }
    // Not there when the panel was built (a first start, before the profile
    // put the files in place): asked again at the next open, as is a logo
    // that fell back to a later file.
    property bool configRead: false
    onShownChanged: if (shown) {
        if (!configRead) configFile.reload()
        if (logoTry > 0) logoTry = 0
    }
    FileView {
        id: configFile
        path: Paths.configDir + "/fastfetch.jsonc"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.configRead = true; root.logoSpec = Logic.textLogo(text(), Paths.home) }
        onLoadFailed: { root.configRead = false; root.logoSpec = ({}) }
    }
    FileView {
        path: root.inlineLogo.runs.length ? "" : root.logoPaths[root.logoTry] || ""
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.takeLogo(path, text())
        // The next file becomes this FileView's path: not from inside its
        // own handler.
        onLoadFailed: Qt.callLater(root.skipLogo, path)
    }

    property string host: ""
    property string kernel: ""
    FileView {
        path: "/proc/sys/kernel/hostname"
        blockLoading: true
        printErrors: false
        onLoaded: root.host = text().trim()
    }
    FileView {
        path: "/proc/sys/kernel/osrelease"
        blockLoading: true
        printErrors: false
        onLoaded: root.kernel = text().trim()
    }
    // Read before the first frame, so Places are there as the card grows.
    property var placeList: []
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config") + "/user-dirs.dirs"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.placeList = Logic.places(text(), Paths.home)
        onLoadFailed: root.placeList = Logic.places("", Paths.home)
    }
    // The suggestions name the session's default apps (default-apps.py list):
    // asked once, while nothing is pinned. Settings > Default apps keeps the
    // list current after that.
    property bool defaultsAsked: false
    function wantDefaults() {
        if (defaultsAsked || LauncherService.pinnedApps.length) return
        defaultsAsked = true
        if (!DefaultAppsService.categories.length && !DefaultAppsService.loading) DefaultAppsService.refresh()
    }

    // For `startMenu get`: counts and flags, never a name.
    function describe() {
        const f = face
        return JSON.stringify({
            open: wanted, shown: shown, view: f ? f.shownView : "", pinned: f ? f.pinnedApps.length : 0,
            suggested: f && f.tileZone === "suggested" ? f.tiles.length : 0,
            frequent: f ? f.frequentApps.length : 0, apps: f ? f.allApps.ids.length : 0,
            results: f ? f.results.length : 0, places: placeList.length, logo: logo.runs.length > 0,
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
                Component.onCompleted: { root.face = face; root.wantDefaults() }
                Component.onDestruction: if (root.face === face) root.face = null

                // ---- state ------------------------------------------------------
                property string query: ""
                // "home" or "all" (`startMenu openView all`); a query shows
                // the results over either.
                property string view: root.openArgs && root.openArgs.startView === "all" ? "all" : "home"
                readonly property bool searching: query.length > 0
                readonly property string shownView: searching ? "search" : view
                readonly property bool atHome: shownView === "home"
                property var selection: ({ zone: "", index: 0 })
                // { kind: "app" | "power", entry, source, index, dock, at } or null
                property var menu: null
                // The item the selection is on, for the menu key to open beside.
                property Item selectedItem: null

                // ---- what it shows ------------------------------------------------
                readonly property var pinnedApps: LauncherService.pinnedApps
                onPinnedAppsChanged: root.wantDefaults()
                // The pins, or with none the suggestions: [{ kind: "app", entry }
                // | { kind: "settings" }] (StartMenuLogic.suggested).
                readonly property string tileZone: pinnedApps.length ? "pinned" : "suggested"
                readonly property var tiles: pinnedApps.length ? pinnedApps.map(app => ({ kind: "app", entry: app }))
                    : Logic.suggested(DefaultAppsService.categories, id => DesktopEntries.byId(id))
                readonly property var frequentApps: Logic.frequent(Usage.top(LauncherService.usage, Date.now()),
                                                                   LauncherService.visibleApps(),
                                                                   pinnedApps.map(app => app.id), frequentLimit)
                // As many rows of them as there is room for, one at least: the
                // card is one size, and with ten pins, four of them and six
                // places the last row of places was cut off at the bottom
                // (offscreen, 13 px), which reads as broken - the launcher
                // shows whole rows for that reason (13.10.). The Flickable
                // around home is for what does not fit even then (a large font).
                readonly property int frequentLimit: {
                    const room = homeView.height - pinnedSection.implicitHeight
                        - (placesSection.visible ? placesSection.implicitHeight + Metrics.panelGap : 0)
                        - Metrics.panelGap - frequentLabel.implicitHeight - Metrics.spaceXs + Metrics.spaceXxs
                    const rows = Math.floor(room / (Metrics.rowHeight + Metrics.spaceXxs))
                    return Math.max(Metrics.startMenuFrequentColumns,
                                    Math.min(Metrics.startMenuFrequent, rows * Metrics.startMenuFrequentColumns))
                }
                readonly property var allApps: view === "all" ? Logic.alphabet(LauncherService.visibleApps())
                                                              : ({ rows: [], ids: [], letters: [] })
                readonly property var allRowByKey: {
                    const table = {}
                    for (const row of allApps.rows) table[row.key] = row
                    return table
                }
                readonly property var results: searching ? LauncherService.results(query, "All") : []
                readonly property var footerKinds: ["settings", "lock", "power"]
                // The one thing in the header that changes while the session runs.
                property int uptime: -1
                readonly property var info: Logic.infoRows(DistroService.info.PRETTY_NAME || DistroService.name, root.kernel, uptime)

                readonly property var zones: shownView === "search" ? [{ id: "results", count: results.length, columns: 1 }]
                    : shownView === "all" ? [{ id: "all", count: allApps.ids.length, columns: 1 },
                                             { id: "footer", count: footerKinds.length, columns: footerKinds.length }]
                    : [{ id: tileZone, count: tiles.length, columns: Metrics.startMenuColumns },
                       { id: "frequent", count: frequentApps.length, columns: Metrics.startMenuFrequentColumns },
                       { id: "places", count: root.placeList.length, columns: Metrics.startMenuPlaceColumns },
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
                // A selection the keys moved out of sight at home is brought back.
                onSelectedItemChanged: if (atHome && selectedItem) homeView.reveal(selectedItem)

                // The grids keep their columns however few they hold.
                readonly property real tileWidth: (width - Metrics.spaceSm * (Metrics.startMenuColumns - 1)) / Metrics.startMenuColumns
                readonly property real placeWidth: (width - Metrics.spaceSm * (Metrics.startMenuPlaceColumns - 1)) / Metrics.startMenuPlaceColumns

                FileView {
                    id: uptimeFile
                    path: "/proc/uptime"
                    blockLoading: true
                    printErrors: false
                    onLoaded: face.uptime = Logic.uptimeSeconds(text())
                }
                Timer { interval: Animations.startMenuUptimeRefresh; running: true; repeat: true; onTriggered: uptimeFile.reload() }

                // ---- what the keys and clicks do ------------------------------------
                function entryAt(zone, index) {
                    if (zone === "pinned") return pinnedApps[index] || null
                    if (zone === "suggested") return tiles[index] && tiles[index].entry ? tiles[index].entry : null
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

                // A tile: an app, or the shell's Settings among the suggestions.
                function openTile(zone, index) {
                    const tile = tiles[index]
                    if (tile && tile.kind === "settings") footerAction("settings", null)
                    else launch(entryAt(zone, index))
                }

                function activate(zone, index, alternate) {
                    if (zone === "results") {
                        const result = results[index]
                        if (!result) return
                        PanelService.close("startMenu")
                        if (alternate && result.alternate) result.alternate()
                        else result.run()
                    } else if (zone === "places") {
                        openPlace(root.placeList[index])
                    } else if (zone === "footer") {
                        footerAction(footerKinds[index], selectedItem)
                    } else if (zone === "pinned" || zone === "suggested") {
                        openTile(zone, index)
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

                // Escape: the menu, then the query, then All apps, then the
                // panel closes (StartMenuLogic.escapeStep). The field puts its
                // text back first, which clears a query typed since the focus.
                // A query it passes on is the one it would put back, so that
                // goes too: the next Escape would bring the query back
                // instead of going on to All apps.
                function stepBack() {
                    switch (Logic.escapeStep(menu !== null, query, view)) {
                    case "menu": closeMenu(); return true
                    case "query":
                        if (root.searchField) { root.searchField.savedText = ""; root.searchField.text = "" }
                        else query = ""
                        return true
                    case "view": view = "home"; return true
                    }
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
                        dockFull: LayoutService.dockPinsFull || !LayoutService.dockPinnable(entry.id), actions: entry.actions
                    }).map(row => Object.assign(row, rowLook(row, entry)))
                    menu = { kind: "app", entry: entry, source: source, index: index, dock: dock, rows: rows, at: placeOf(item) }
                    contextMenu.forceActiveFocus()
                }

                function openPowerMenu(item) {
                    const rows = Logic.powerRows().map(row => Object.assign(row, rowLook(row, null)))
                    menu = { kind: "power", rows: rows, at: placeOf(item), above: true }
                    contextMenu.forceActiveFocus()
                }

                // The keys back to the field. It takes what it holds now as
                // the text Escape goes back to; nothing was typed into it
                // since the menu opened, so that is the empty field again, or
                // an Escape after a menu would leave the query standing.
                function closeMenu() {
                    menu = null
                    if (!root.searchField) return
                    root.searchField.focusInput()
                    root.searchField.savedText = ""
                }

                function rowLook(row, entry) {
                    switch (row.kind) {
                    case "open": return { label: "Open", iconSource: entry ? LauncherService.iconSource(entry.icon) : "" }
                    case "action": return { label: row.name, icon: Icons.forward }
                    case "pinStart": return { label: "Pin to Start", icon: Icons.pin, hint: "At most " + Pinned.LIMIT + " pinned apps" }
                    case "unpinStart": return { label: "Unpin from Start", icon: Icons.unpin }
                    case "moveLeft": return { label: "Move left", icon: Icons.back }
                    case "moveRight": return { label: "Move right", icon: Icons.forward }
                    case "pinDock": return { label: "Pin to dock", icon: Icons.dock,
                        hint: LayoutService.dockPinsFull ? "At most " + LayoutService.dockPinLimit + " apps on the dock" : "The dock cannot hold this app" }
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
                    id: faceColumn
                    anchors.fill: parent
                    spacing: Metrics.panelGap
                    // Home and All apps fade into each other. `face.view`, not
                    // what is shown: typing into the search must not fade on
                    // its first key.
                    PageFade { target: faceColumn; key: face.view; live: root.openProgress === 1 }

                    // fastfetch, small: the logo, and beside it its title and
                    // rows. All apps and the results need the room: there it
                    // is the title alone, one line.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SaturnAscii {
                            Layout.alignment: Qt.AlignVCenter
                            visible: face.atHome && root.logo.runs.length > 0
                            logo: root.logo
                            boxColumns: Logic.LOGO_BOX.columns
                            boxRows: Logic.LOGO_BOX.rows
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
                                    text: root.host
                                    color: Colors.saturnPlanet
                                    font.family: Typography.monoFamily
                                    font.weight: Typography.bold
                                }
                            }
                            Row {
                                visible: face.atHome
                                ShellText { text: "──────── "; color: Colors.saturnRing; font.family: Typography.monoFamily; role: "small" }
                                ShellText { text: "✦"; color: Colors.saturnPlanet; font.family: Typography.monoFamily; role: "small" }
                                ShellText { text: " ────────"; color: Colors.saturnRing; font.family: Typography.monoFamily; role: "small" }
                            }
                            GridLayout {
                                visible: face.atHome
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
                    // In a Flickable for when it holds more than the card has
                    // room for even with fewer frequent apps (a large font):
                    // then it scrolls, and nothing below it is pushed out of
                    // the card.
                    Flickable {
                        id: homeView
                        visible: face.atHome
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: home.height
                        interactive: contentHeight > height
                        clip: interactive
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollFeel { view: homeView }

                        function reveal(item) {
                            if (!interactive || !item) return
                            const top = item.mapToItem(home, 0, 0).y
                            if (top < contentY) contentY = Math.max(0, top - Metrics.spaceXs)
                            else if (top + item.height > contentY + height)
                                contentY = Math.min(contentHeight - height, top + item.height - height + Metrics.spaceXs)
                        }

                        ColumnLayout {
                            id: home
                            width: homeView.width
                            // At least as tall as the view, so Places stay at the bottom.
                            height: Math.max(homeView.height, implicitHeight)
                            spacing: Metrics.panelGap

                            // Each section's label sits close to what it names.
                            ColumnLayout {
                                id: pinnedSection
                                Layout.fillWidth: true
                                spacing: Metrics.spaceXs
                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionLabel { text: "Pinned"; Layout.fillWidth: true }
                                    // A link forward, its chevron after the
                                    // words; a ghost button's padding is
                                    // invisible, so its words end where the
                                    // content does.
                                    ShellButton {
                                        id: allAppsButton
                                        Layout.rightMargin: -allAppsButton.sidePadding
                                        text: "All apps"
                                        trailingIcon: Icons.forward
                                        variant: "ghost"
                                        compact: true
                                        onClicked: face.view = "all"
                                    }
                                }
                                EmptyState {
                                    Layout.fillWidth: true
                                    visible: face.tileZone === "suggested"
                                    row: true
                                    title: "Nothing pinned yet"
                                    description: "Right-click an app in All apps to pin it"
                                }
                                SectionLabel {
                                    Layout.topMargin: Metrics.spaceSm
                                    visible: face.tileZone === "suggested"
                                    text: "Suggested"
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    visible: face.tiles.length > 0
                                    columns: Metrics.startMenuColumns
                                    columnSpacing: Metrics.spaceSm
                                    rowSpacing: Metrics.spaceSm
                                    Repeater {
                                        model: face.tiles
                                        ShellCard {
                                            id: tile
                                            required property var modelData
                                            required property int index
                                            readonly property bool isSettings: modelData.kind === "settings"
                                            readonly property var entry: modelData.entry || null
                                            readonly property bool chosen: face.isSelected(face.tileZone, index)
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
                                                    visible: !tile.isSettings
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.preferredWidth: Metrics.iconXl
                                                    Layout.preferredHeight: Metrics.iconXl
                                                    source: tile.entry ? LauncherService.iconSource(tile.entry.icon) : ""
                                                    sourceSize.width: Metrics.iconXl * 2
                                                    sourceSize.height: Metrics.iconXl * 2
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                }
                                                // The shell's own Settings: its glyph on an
                                                // accent tile, as on the dock.
                                                Rectangle {
                                                    visible: tile.isSettings
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.preferredWidth: Metrics.iconXl
                                                    Layout.preferredHeight: Metrics.iconXl
                                                    radius: Metrics.radiusInner
                                                    color: Colors.accentFill
                                                    ShellIcon {
                                                        anchors.centerIn: parent
                                                        glyph: Icons.settingsApp
                                                        size: parent.width * Metrics.dockGlyphFill
                                                        color: Colors.accentFillText
                                                    }
                                                }
                                                ShellText {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: tile.isSettings ? "Settings" : tile.entry ? tile.entry.name || tile.entry.id : ""
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
                                                    if (mouse.button === Qt.RightButton) face.openAppMenu(tile.entry, face.tileZone, tile.index, tile)
                                                    else face.openTile(face.tileZone, tile.index)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Metrics.spaceXs
                                SectionLabel { id: frequentLabel; text: "Frequent" }
                                EmptyState {
                                    Layout.fillWidth: true
                                    visible: face.frequentApps.length === 0
                                    row: true
                                    title: "Nothing used often yet"
                                    description: "Apps you open often show up here"
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    visible: face.frequentApps.length > 0
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

                            // At the bottom, whatever is above: the room
                            // left is taken inside the section, so it costs
                            // no second gap when there is none.
                            ColumnLayout {
                                id: placesSection
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.placeList.length > 0
                                spacing: Metrics.spaceXs
                                Item { Layout.fillHeight: true }
                                SectionLabel { text: "Places" }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: Metrics.startMenuPlaceColumns
                                    columnSpacing: Metrics.spaceSm
                                    rowSpacing: Metrics.spaceSm
                                    Repeater {
                                        model: root.placeList
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
                    }

                    // ---- all apps ---------------------------------------------------------
                    ColumnLayout {
                        visible: face.shownView === "all"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Metrics.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            // Its chevron on the content's edge, like the
                            // forward link's words on the other side.
                            ShellButton {
                                id: backButton
                                Layout.leftMargin: -backButton.sidePadding
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
                            color: Colors.accent // style: the avatar's disc, as on the lock screen
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
