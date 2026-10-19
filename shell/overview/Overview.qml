import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets as QsWidgets
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/overview/OverviewLogic.js" as Logic
import "../../services/model/KeyedLogic.js" as Keyed
import "../../services/wallpaper/WallpaperLogic.js" as WallpaperLogic
import "SelectionLogic.js" as Selection

// Super+W: workspaces with live window previews. Type to filter, arrows to
// select a window or a workspace, Enter to focus or switch to it, Delete to
// close it; click a workspace to switch to it, drag a window onto another
// workspace to move it there.
//
// Minimized windows (services/MinimizeService.qml) are on special workspaces
// no card shows: they have a row of their own under the cards - a click or
// Enter brings one back to its workspace, a drag onto a card brings it back
// there, and a window dragged onto that row is minimized.
//
// A ShellPanel without its chrome (`showCard: false`): the overview fills the
// screen and draws its own dark backdrop, but focus, Escape, the scrim, the
// click outside and the open and close transition are the panel system's, not
// a second copy of them. It does not morph - a surface the size of the screen
// growing out of the notch reads as a stutter, not as an origin.
//
// Alt+Tab is deliberately *not* on ShellPanel (see Switcher.qml): it has to
// let go of the keyboard itself, or the Alt release never reaches the window
// underneath.
ShellPanel {
    id: window
    panelId: "overview"
    placement: "center"
    showCard: false
    shadow: false
    morph: false
    scrimColor: Colors.overviewScrim
    keyForward: search
    cardWidth: screenW
    cardHeight: screenH - Metrics.panelTopOffset - Metrics.screenMargin
    property var workspaces: []
    // The monitors as `hyprctl` last described them, for the grouping.
    property var monitors: []
    readonly property var groups: Logic.groups(workspaces, monitors, HyprlandService.perMonitor)
    // What the keys walk: the windows and, while nothing is typed, the
    // workspace cards (SelectionLogic.stops). `selected` is an index into
    // them and `selectedKey` the stop it is on, so the selection stays on a
    // window or a card while the list changes around it.
    readonly property var stops: Selection.stops(groups, search.text, minimized)
    // The minimized windows (OverviewLogic.minimizedWindows), keyed by address.
    property var minimized: []
    // A window's thumbnail is being dragged: the minimized row is there to
    // take it even while it is empty.
    property bool draggingWindow: false
    property int selected: 0
    property string selectedKey: ""
    // Until a key moves the selection, it is on the first window: Enter
    // right after Super+W, or after typing a search, focuses that one.
    property bool navigated: false
    readonly property var selectedStop: stops.length ? stops[Selection.clamp(selected, stops.length)] : null
    readonly property var selectedWindow: selectedStop && selectedStop.kind === "window" ? selectedStop.window : null
    // The accent as text and outline on the scrim, which is dark in both
    // themes. accentForeground is made for cards: the light theme darkens it
    // for light ones, and on the scrim it sank into the dark. It was then
    // made readable against the lock's base, as dark as the scrim reads over
    // a dark wallpaper - but the light theme's scrim is thinner, and over a
    // bright wallpaper the labels came to 2.5-3.2:1. Measured
    // on the scrim at its lightest now (Colors.overviewAccent), in both
    // themes; the shipped teal on the dark scrim is 6.8:1 and stays.
    readonly property color scrimAccent: Colors.overviewAccent
    // **One row per monitor.** A monitor's "New workspace" card belongs beside
    // its workspaces, not under them, so the widest row decides the column
    // count and every row lines up with it. The count used to be the *session's*
    // workspace total capped at four, which had nothing to do with how many
    // cards any one monitor has: five workspaces and their new-workspace card
    // came out as four and two.
    //
    // The cards shrink to fit rather than wrapping - down to
    // `overviewCardMinWidth`, below which a preview shows nothing at all and
    // wrapping is the lesser evil.
    readonly property int widestRow: groups.reduce(
        (most, group) => Math.max(most, group.workspaces.length + (group.newCard ? 1 : 0)), 1)
    // The room the rows really have, which is the flickable they sit in - not
    // the screen less a guess at the margins. Taking the screen made the count
    // one too high, and the card that did not fit wrapped to a line of its own,
    // which is the thing this is here to stop.
    readonly property real cardsRoom: Math.max(0, cardsFlick.width)
    readonly property int columns: Math.max(1, Math.min(widestRow,
        Math.floor((cardsRoom + Metrics.spaceXl) / (Metrics.overviewCardMinWidth + Metrics.spaceXl))))
    // Not `cardWidth`: that is the panel's own width. This is the width of one
    // workspace card inside it.
    readonly property real workspaceWidth: Math.min(Metrics.overviewCardWidth,
        (cardsRoom - Metrics.spaceXl * (columns - 1)) / columns)

    function refresh() {
        Hyprland.refreshToplevels()
        if (!loadProc.running) loadProc.running = true
    }
    function dispatch(command) {
        HyprCompat.dispatch(command)
        refreshTimer.restart()
    }
    // Dispatched after the overlay released keyboard focus; otherwise
    // Hyprland hands focus back to the previous window.
    property var pendingDispatch: null
    function afterClose(command) {
        pendingDispatch = command
        PanelService.close("overview")
        pendingTimer.restart()
    }
    function focusWindow(entry) {
        if (entry) afterClose(HyprCompat.commands.focusWindow(entry.address))
    }
    function select(index) {
        selected = Selection.clamp(index, stops.length)
        selectedKey = stops.length ? stops[selected].key : ""
        navigated = true
    }
    // Enter: a window is focused, a workspace (or the new one) switched to, a
    // minimized window brought back.
    function activate(stop) {
        if (!stop) return
        if (stop.kind === "window") focusWindow(stop.window)
        else if (stop.kind === "minimized") restoreWindow(stop.window)
        else afterClose(HyprCompat.commands.workspace(stop.workspace))
    }
    // Back to its workspace now, to the front once the overview has let the
    // keyboard go (MinimizeService.restore's delay).
    function restoreWindow(entry) {
        if (!entry) return
        MinimizeService.restore(entry.address, true, Animations.overviewDispatchDelay)
        PanelService.close("overview")
    }
    // Delete: a window is closed, a workspace card does what its × does.
    function remove(stop) {
        if (!stop) return
        if (stop.kind === "window" || stop.kind === "minimized") dispatch(HyprCompat.commands.closeWindow(stop.window.address))
        else if (stop.kind === "card" && stop.closable && HyprlandService.keepsEmpty) closeCard(stop.entry)
    }
    // The ×, by click or by Delete. A workspace with windows only asks the
    // first time, as ShellButton's `confirm` does: its windows go to the one
    // before it (HyprlandService.closeWorkspace). One card is asked about at
    // a time, and the question goes again on its own.
    property int armedWorkspace: -1
    function closeCard(entry) {
        if (!entry) return
        if ((entry.windows || []).length > 0 && armedWorkspace !== entry.id) {
            armedWorkspace = entry.id
            disarm.restart()
            return
        }
        disarm.stop()
        armedWorkspace = -1
        HyprlandService.closeWorkspace(entry.id)
    }
    Timer {
        id: disarm
        interval: Animations.confirmTimeout
        onTriggered: window.armedWorkspace = -1
    }
    function toplevelFor(address) {
        const key = Logic.normalizeAddress(address)
        return Hyprland.toplevels.values.find(item => Logic.normalizeAddress(item.address) === key) || null
    }

    onWantedChanged: {
        armedWorkspace = -1
        // A thumbnail closed in the middle of a drag never says it ended.
        draggingWindow = false
        if (!wanted) return
        search.text = ""
        navigated = false
        selected = Selection.openingIndex(stops)
        selectedKey = stops.length ? stops[selected].key : ""
        refresh()
    }
    onStopsChanged: {
        selected = navigated ? Selection.indexOf(stops, selectedKey, selected) : Selection.openingIndex(stops)
        selectedKey = stops.length ? stops[selected].key : ""
    }

    Timer { id: refreshTimer; interval: Animations.overviewRefresh; onTriggered: window.refresh() }
    Timer {
        id: pendingTimer
        interval: Animations.overviewDispatchDelay
        onTriggered: if (window.pendingDispatch) { HyprCompat.dispatch(window.pendingDispatch); window.pendingDispatch = null }
    }

    // One `hyprctl --batch` for the three answers: a shell and three hyprctl
    // were ~35 ms of CPU and as long again before the cards were right, on
    // every open and on every window or workspace event while open. A
    // Hyprland whose batch answer is not three JSON documents gets the shell
    // from then on, rather than an empty overview.
    property bool batchRefused: false
    Process {
        id: loadProc
        command: window.batchRefused
            ? ["sh", "-c", "printf '{\"clients\":'; hyprctl -j clients; printf ',\"monitors\":'; hyprctl -j monitors; printf ',\"workspaces\":'; hyprctl -j workspaces; printf '}'"]
            : ["hyprctl", "-j", "--batch", "clients; monitors; workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null
                if (!window.batchRefused) {
                    data = Logic.parseBatch(text, ["clients", "monitors", "workspaces"])
                    if (!data) {
                        window.batchRefused = true
                        refreshTimer.restart()
                        return
                    }
                }
                try {
                    if (!data) data = JSON.parse(text)
                    const monitors = data.monitors || []
                    const workspaces = Logic.build(data.clients, data.monitors, data.workspaces,
                                                   SettingsService.value("workspaces.mode"),
                                                   SettingsService.value("workspaces.count"),
                                                   HyprlandService.perMonitor)
                    // Only when something changed: the Repeaters below hold
                    // plain arrays, and a plain array assigned again rebuilds
                    // every card and every preview in it, whether or not a
                    // single window moved. Every workspace or window event
                    // comes through here, so most answers are the same answer.
                    // Workspaces and windows that did not change are handed on
                    // as the same objects: the cards' and previews' models only
                    // match those right (services/model/KeyedLogic.js) - a
                    // window that left a card used to pass every preview after
                    // it on to its neighbour, capture and all.
                    if (JSON.stringify(monitors) !== JSON.stringify(window.monitors)) window.monitors = monitors
                    if (JSON.stringify(workspaces) !== JSON.stringify(window.workspaces))
                        window.workspaces = Keyed.keep(window.workspaces, workspaces, "id", { windows: "address" })
                    const minimized = Logic.minimizedWindows(data.clients)
                    if (JSON.stringify(minimized) !== JSON.stringify(window.minimized))
                        window.minimized = Keyed.keep(window.minimized, minimized, "address")
                } catch (error) {
                    window.monitors = []
                    window.workspaces = []
                    window.minimized = []
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (window.wanted && ["openwindow", "closewindow", "movewindow", "movewindowv2", "workspace", "workspacev2", "createworkspacev2", "destroyworkspacev2"].indexOf(event.name) >= 0)
                refreshTimer.restart()
        }
    }

    // The card covers nearly the whole screen, so "click outside" would leave
    // almost nowhere to click: the gaps between the cards close it instead.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: PanelService.close("overview")
    }

    ColumnLayout {
        id: content
        // The panel gives the content its settled size; with five or more
        // workspaces the cards scroll inside the free height while the search
        // field and the hint line stay put.
        anchors.fill: parent
        spacing: Metrics.spaceXl

        ShellTextField {
            id: search
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Metrics.overviewSearchWidth
            icon: Icons.search
            placeholder: "Search windows …"
            color: Colors.panelFor("overview")
            // An outline in the ink for marks: the field's fill is the panel's
            // and the scrim under it is nearly as dark, so in the dark theme
            // the field was there at 1.03:1 and found by its placeholder.
            // Grey in both themes, and the scrim is dark in both.
            border.color: Colors.subtleText
            onAccepted: window.activate(window.selectedStop)
            onEscapePressed: if (!text.length) PanelService.close("overview")
            // Left and Right walk every stop in order; Up and Down go to the
            // card a line above or below, the next monitor's row included
            // (SelectionLogic.vertical).
            Keys.onLeftPressed: event => { if (text.length) { event.accepted = false; return } window.select(Selection.step(window.selected, -1, window.stops.length)) }
            Keys.onRightPressed: event => { if (text.length) { event.accepted = false; return } window.select(Selection.step(window.selected, 1, window.stops.length)) }
            Keys.onUpPressed: window.select(Selection.vertical(window.stops, window.selected, -1, window.columns))
            Keys.onDownPressed: window.select(Selection.vertical(window.stops, window.selected, 1, window.columns))
            onDeleteOnEmpty: window.remove(window.selectedStop)
        }

        // A search that matches nothing used to leave every card on screen
        // with its windows filtered away - up to twenty-seven empty
        // rectangles, which reads as a broken overview rather than as an
        // answer. The cards are worth showing while no search is typed,
        // because switching to an empty workspace is a thing to do; once a
        // query is on screen the question is about windows and the honest
        // reply is that there are none.
        //
        // EmptyState's centred column, in the scrim's inks: its own are panel
        // inks, and the light theme's dark grey vanished on the scrim, which
        // stays dark in both themes.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: search.text.length > 0 && window.stops.length === 0
            spacing: Metrics.spaceSm

            Item { Layout.fillHeight: true }
            ShellIcon {
                Layout.alignment: Qt.AlignHCenter
                glyph: Icons.search
                size: Metrics.iconXl
                color: Colors.scrimMutedText
            }
            ShellText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "No window matches \u201c" + search.text + "\u201d"
                color: Colors.scrimMutedText
                wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Escape clears the search"
                role: "small"
                color: Colors.scrimMutedText
                wrapMode: Text.Wrap
            }
            Item { Layout.fillHeight: true }
        }

        Flickable {
            id: cardsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(search.text.length > 0 && window.stops.length === 0)
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollFeel { view: cardsFlick }

            // One row per monitor, in the order the Displays page numbers
            // them and with the screen the overview opened on first. A single
            // flow of every workspace of every monitor stopped being readable
            // the moment there was more than one screen - and with a block of
            // numbers per monitor it can be twenty-seven cards.
            Column {
                id: cards
                x: Math.max(0, (cardsFlick.width - width) / 2)
                width: Math.min(content.width, window.columns * (window.workspaceWidth + Metrics.spaceXl) - Metrics.spaceXl)
                spacing: Metrics.spaceXl

                // Cards (with a rounded image each) only while shown; the
                // captures were already let go on close, the cards were not.
                //
                // Keyed models all the way down (monitor, workspace id, window
                // address): every window move hands the overview a new array,
                // and plain arrays rebuilt every card and every preview - each
                // capture started again and showed the window icon for a moment
                // (seen after a drag). Now only what came or went
                // is built; the rest gets its new modelData in place.
                Repeater {
                    model: ScriptModel { values: window.shown ? window.groups : []; objectProp: "monitor" }

                    ColumnLayout {
                        id: row
                        required property var modelData
                        width: cards.width
                        spacing: Metrics.spaceSm

                        ShellText {
                            // Only worth a heading when there is more than one
                            // screen to tell apart. Named by the model where
                            // the monitor names one: the connector changes
                            // with the port a dock hands out.
                            visible: window.groups.length > 1 && row.modelData.monitor.length > 0
                            text: "Monitor " + row.modelData.number + " \u00b7 " + row.modelData.title
                            role: "label"
                            color: row.modelData.focused ? window.scrimAccent : Colors.scrimMutedText
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXl

                            Repeater {
                                // The row's "New workspace" card last, with
                                // the number its row offers (OverviewLogic.groups:
                                // its own block's next free one, or without
                                // blocks the focused row only).
                                model: ScriptModel {
                                    objectProp: "id"
                                    values: row.modelData.workspaces.concat(row.modelData.newCard ? [row.modelData.newCard] : [])
                                }

                            ColumnLayout {
                                id: card
                                required property var modelData
                                readonly property bool placeholder: modelData.placeholder === true
                                readonly property bool dropHover: drop.containsDrag
                                // The keys' selection on the card itself (an
                                // empty workspace, or past its windows).
                                readonly property bool isSelected: !!window.selectedStop && window.selectedStop.kind !== "window"
                                    && window.selectedStop.key === (placeholder ? "n:" + row.modelData.monitor : "c:" + modelData.id)
                                width: window.workspaceWidth
                                spacing: Metrics.spaceSm
                                // The pointer anywhere on the card brings its
                                // × up from faint.
                                HoverHandler { id: cardHover }

                                RowLayout {
                                    Layout.fillWidth: true
                                    ShellText {
                                        // `label` and not `name`: with a block
                                        // per monitor the compositor's id can
                                        // be 23 while the card is that
                                        // monitor's third.
                                        text: card.placeholder ? "New workspace" : "Workspace " + card.modelData.label
                                        color: card.modelData.active ? window.scrimAccent : Colors.scrimText
                                    }
                                    Item { Layout.fillWidth: true }
                                    // The monitor's name is the row's heading
                                    // when there is more than one, so a card
                                    // repeating it would be noise.
                                    ShellText {
                                        visible: !card.placeholder && window.groups.length <= 1
                                        text: card.modelData.monitor
                                        role: "caption"
                                        color: Colors.scrimMutedText
                                    }
                                    // Held open (Settings > Bar & notch > Keep
                                    // empty workspaces open), a workspace is
                                    // closed here. Its windows go to the one
                                    // before it (HyprlandService.closeWorkspace),
                                    // so on one with windows the first click
                                    // only asks, as ShellButton's `confirm`
                                    // does - drawn in the scrim's inks, which a
                                    // ShellButton has not got: the scrim stays
                                    // dark in both themes. Not on the new
                                    // workspace card, nor on a monitor's only
                                    // workspace, which has nothing to close
                                    // into - there it keeps its place, unseen,
                                    // or that card's frame started 14 px higher
                                    // than its neighbours'. Nor on a workspace
                                    // the overview filled in or one of Fixed's
                                    // numbers: those are not there to close, or
                                    // come back the moment they go
                                    // (OverviewLogic.closable). Faint until the
                                    // card is pointed at. Delete on a selected
                                    // card does the same (`closeCard`).
                                    Rectangle {
                                        id: closeMark
                                        readonly property int windowCount: (card.modelData.windows || []).length
                                        readonly property bool closable: Logic.closable(card.modelData, row.modelData)
                                        readonly property bool armed: !card.placeholder && window.armedWorkspace === card.modelData.id
                                        visible: HyprlandService.keepsEmpty
                                        implicitHeight: Metrics.controlHeightSm
                                        implicitWidth: armed ? armedLabel.implicitWidth + Metrics.controlPaddingSm * 2 : implicitHeight
                                        radius: height / 2
                                        color: closeMouse.pressed ? Colors.scrimPressed
                                            : closeMouse.containsMouse || armed ? Colors.scrimHover : "transparent"
                                        opacity: !closable ? 0 : cardHover.hovered || armed ? 1 : Effects.mutedOpacity
                                        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
                                        Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }

                                        ShellIcon {
                                            anchors.centerIn: parent
                                            visible: !closeMark.armed
                                            glyph: Icons.close
                                            size: Metrics.iconSm
                                            color: closeMouse.containsMouse ? Colors.scrimText : Colors.scrimMutedText
                                        }
                                        ShellText {
                                            id: armedLabel
                                            anchors.centerIn: parent
                                            visible: closeMark.armed
                                            text: closeMark.windowCount === 1 ? "Move 1 window and close"
                                                : "Move " + closeMark.windowCount + " windows and close"
                                            role: "small"
                                            color: Colors.dangerOnDark
                                        }
                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            enabled: closeMark.closable
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: closeTip.arm()
                                            onExited: closeTip.release()
                                            onClicked: {
                                                closeTip.release()
                                                window.closeCard(card.modelData)
                                            }
                                        }
                                        // The faint × says what it does; armed, its
                                        // label says it already.
                                        ToolTipHost {
                                            id: closeTip
                                            anchorItem: closeMark
                                            text: closeMark.armed ? "" : "Close workspace " + card.modelData.label
                                        }
                                        // Disabled under the pointer (the row's other
                                        // workspace closed) or asking already (Delete
                                        // arms it too), the × takes its bubble down: a
                                        // MouseArea that is switched off says nothing
                                        // about the pointer leaving.
                                        onClosableChanged: if (!closable) closeTip.release()
                                        onArmedChanged: if (armed) closeTip.release()
                                        Accessible.ignored: !closable
                                        Accessible.role: Accessible.Button
                                        Accessible.name: closeMark.armed ? armedLabel.text : "Close workspace " + card.modelData.label
                                    }
                                }

                                Rectangle {
                                    id: frame
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width * card.modelData.aspect
                                    radius: Metrics.radiusCard
                                    color: card.dropHover ? Colors.accentSoft : Colors.panelFor("overview")
                                    // Selected by the keys: the scrim's own white,
                                    // which the accent ring of the active
                                    // workspace cannot be mistaken for.
                                    border.width: card.isSelected || card.modelData.active || card.dropHover ? Metrics.focusBorderWidth : Metrics.borderWidth
                                    border.color: card.isSelected ? Colors.scrimText
                                        : card.modelData.active || card.dropHover ? window.scrimAccent : Colors.panelBorder
                                    clip: true

                                    // The wallpaper of the monitor this workspace is
                                    // on, behind the windows. A card used to be a flat
                                    // panel colour, which was invisible behind a full
                                    // workspace and read as a black screen on an empty
                                    // one - and an empty workspace is exactly what the
                                    // overview started showing once it stopped hiding
                                    // the ones with nothing on them. This is what you
                                    // would actually find there.
                                    //
                                    // `RoundedImage`, not `Image`: the card is a
                                    // `Rectangle` and a Rectangle does not clip its
                                    // children to its radius, whatever `clip` says. A
                                    // plain Image filled it corner to corner and the
                                    // four square corners stuck out past the rounding -
                                    // which is the trap already written down in the
                                    // handout, fallen into on the day it was written.
                                    // RoundedImage masks instead of clipping.
                                    RoundedImage {
                                        anchors.fill: parent
                                        // Inside the border rather than under it, so
                                        // the accent ring of the active workspace stays
                                        // a ring.
                                        anchors.margins: frame.border.width
                                        visible: !card.placeholder && status === Image.Ready
                                        // The picker's thumbnail where there is one,
                                        // like the picker: `sourceWidth` alone did not
                                        // spare the decode, because Qt cannot decode a
                                        // PNG at a reduced size - a 6000x3750 wallpaper
                                        // cost 160-180 ms and ~90 MB per card, for 480
                                        // pixels. The thumbnails are 520 wide, so the
                                        // card still gets its 480. An image outside the
                                        // folder has none and is read as before - as
                                        // an encoded url, or a "#" or "?" in its name
                                        // read as a fragment or a query.
                                        source: card.placeholder ? ""
                                            : WallpaperService.thumbFor(WallpaperService.currentFor(card.modelData.monitor))
                                              || WallpaperLogic.folderUrl(WallpaperService.currentFor(card.modelData.monitor))
                                        // Concentric with the card: the same radius
                                        // less the border it sits inside.
                                        radius: Metrics.radiusCard - frame.border.width
                                        // A card is a few hundred pixels wide and there
                                        // is one per workspace; decoding a 5120-wide
                                        // photograph that many times over is not worth
                                        // the sharpness nobody can see at this size.
                                        sourceWidth: Metrics.overviewCardSourceWidth
                                        // The windows sit above it, the scrim below the
                                        // labels stays legible over it.
                                        opacity: Effects.overviewWallpaperOpacity
                                    }

                                    ShellIcon {
                                        anchors.centerIn: parent
                                        visible: card.placeholder
                                        glyph: Icons.add
                                        size: Metrics.iconXl
                                        color: Colors.mutedText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.afterClose(HyprCompat.commands.workspace(card.modelData.id))
                                    }

                                    DropArea {
                                        id: drop
                                        anchors.fill: parent
                                        keys: ["buchhwin-window"]
                                        onDropped: drag => {
                                            if (drag.source.workspaceId !== card.modelData.id) {
                                                window.dispatch(HyprCompat.commands.moveWindowSilent(card.modelData.id, drag.source.address))
                                                drag.source.sent = true
                                            }
                                            drag.acceptProposedAction()
                                        }
                                    }

                                    Repeater {
                                        // Every window, with the ones the search
                                        // rules out hidden rather than filtered
                                        // away: a filtered array is a new model
                                        // on every keystroke, and that threw the
                                        // previews away and captured them again
                                        // for each letter typed. A hidden thumb
                                        // keeps its place - it is positioned
                                        // from its own window's geometry, not
                                        // from its neighbours.
                                        model: ScriptModel { values: card.modelData.windows; objectProp: "address" }

                                        Rectangle {
                                            id: thumb
                                            required property var modelData
                                            visible: Logic.matches(modelData, search.text) && !sent
                                            readonly property string address: modelData.address
                                            readonly property int workspaceId: card.modelData.id
                                            // Dropped on another workspace: gone from
                                            // this card until the overview reads the
                                            // windows again, instead of springing back
                                            // home for the moment that takes. Back after
                                            // a while if the move never happened.
                                            property bool sent: false
                                            readonly property bool dragging: dragArea.drag.active
                                            readonly property bool isSelected: !!window.selectedWindow && window.selectedWindow.address === modelData.address
                                            // Kept through the close fade, not only
                                            // while wanted: without a source the capture
                                            // drops its frame at once, and every preview
                                            // turned into the window glyph while the
                                            // overview was still nearly opaque. `live`
                                            // stops at the close, so the last frame
                                            // stays; the cards (built while shown) let
                                            // every capture go when the fade ends.
                                            readonly property var toplevel: window.shown ? window.toplevelFor(modelData.address) : null
                                            property real homeX: modelData.x * frame.width
                                            property real homeY: modelData.y * frame.height
                                            x: homeX + Metrics.spaceXxs
                                            y: homeY + Metrics.spaceXxs
                                            width: Math.max(Metrics.iconXl, modelData.width * frame.width - Metrics.spaceXxs * 2)
                                            height: Math.max(Metrics.iconXl, modelData.height * frame.height - Metrics.spaceXxs * 2)
                                            z: dragArea.drag.active ? 10 : isSelected ? 2 : 1
                                            // Concentric with the card it sits in, a
                                            // gap of spaceXxs inside its border: a
                                            // window that fills its workspace has
                                            // its corners right in the card's, and
                                            // radiusInner (10 against 16) left the gap
                                            // between them wider at the corners.
                                            radius: Math.max(0, Metrics.radiusCard - frame.border.width - Metrics.spaceXxs)
                                            color: Colors.surface2
                                            border.width: isSelected || hover.hovered ? Metrics.focusBorderWidth : Metrics.borderWidth
                                            border.color: isSelected ? Colors.accentForeground : hover.hovered ? Colors.borderStrong : Colors.border
                                            clip: true
                                            Drag.active: dragArea.drag.active
                                            Drag.keys: ["buchhwin-window"]
                                            Drag.source: thumb
                                            Drag.hotSpot.x: width / 2
                                            Drag.hotSpot.y: height / 2

                                            // While dragged it lives in `dragLayer`, above
                                            // every card: the card clips its windows, and a
                                            // thumbnail taken to another workspace vanished
                                            // the moment it left its own card. ParentChange
                                            // keeps it where it is on screen; the drag and
                                            // its own setX/setY end the position bindings,
                                            // which `rehome` puts back.
                                            states: State {
                                                when: thumb.dragging
                                                ParentChange { target: thumb; parent: dragLayer }
                                            }
                                            function rehome() {
                                                x = Qt.binding(() => homeX + Metrics.spaceXxs)
                                                y = Qt.binding(() => homeY + Metrics.spaceXxs)
                                            }
                                            onDraggingChanged: {
                                                window.draggingWindow = dragging
                                                if (!dragging) Qt.callLater(rehome)
                                            }
                                            Timer {
                                                interval: Animations.overviewSentTimeout
                                                running: thumb.sent
                                                onTriggered: thumb.sent = false
                                            }
                                            Timer {
                                                id: iconDelay
                                                property bool passed: false
                                                interval: Animations.previewIconDelay
                                                running: true
                                                onTriggered: passed = true
                                            }

                                            HoverHandler { id: hover }

                                            // The capture and the title bar inside the
                                            // thumbnail's rounding: a Rectangle does not
                                            // clip its children to its radius (pitfall 4),
                                            // and the capture's square corners stood out
                                            // past it. The inset stays the thin border's,
                                            // so a hover (the thick one) does not resize
                                            // the capture and start it again.
                                            QsWidgets.ClippingRectangle {
                                                anchors.fill: parent
                                                anchors.margins: Metrics.borderWidth
                                                radius: Math.max(0, thumb.radius - Metrics.borderWidth)
                                                color: "transparent"

                                                ScreencopyView {
                                                    id: preview
                                                    anchors.fill: parent
                                                    captureSource: thumb.toplevel ? thumb.toplevel.wayland : null
                                                    // Not for a preview the search hides: a live
                                                    // view asks for the next frame whether or not
                                                    // it is drawn, and a busy hidden window kept
                                                    // being exported. Its last frame stays, and
                                                    // it captures again the moment it is back.
                                                    live: window.wanted && thumb.visible
                                                    // Capture at preview size instead of the
                                                    // window's own resolution (the switcher
                                                    // does the same); a wall of full-size
                                                    // captures made the fade-in stutter.
                                                    constraintSize: Qt.size(width, height)
                                                }

                                                ShellIcon {
                                                    anchors.centerIn: parent
                                                    visible: !preview.hasContent && iconDelay.passed
                                                    glyph: Icons.window
                                                    size: Metrics.iconLg
                                                    color: Colors.mutedText
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: label.implicitHeight + Metrics.spaceXs * 2
                                                    visible: thumb.isSelected || hover.hovered
                                                    color: Colors.pill
                                                    ShellText {
                                                        id: label
                                                        anchors.fill: parent
                                                        anchors.margins: Metrics.spaceXs
                                                        text: thumb.modelData.title || thumb.modelData.appClass
                                                        role: "caption"
                                                        color: Colors.text
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: dragArea
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                                cursorShape: Qt.PointingHandCursor
                                                drag.target: thumb
                                                drag.threshold: Metrics.dragThreshold
                                                onReleased: {
                                                    if (drag.active) thumb.Drag.drop()
                                                }
                                                onClicked: event => {
                                                    if (event.button === Qt.MiddleButton) window.dispatch(HyprCompat.commands.closeWindow(thumb.address))
                                                    else window.focusWindow(thumb.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                }

                // The minimized windows, under every monitor's row: a chip
                // each, the one used last first. A click (or Enter on it)
                // brings it back to its workspace, a middle click closes it, a
                // drag onto a card brings it back there (the card's DropArea
                // moves it). A window dragged onto this row is minimized - the
                // row is there for that while a window is dragged, even empty.
                ColumnLayout {
                    id: minimizedRow
                    width: cards.width
                    visible: window.minimized.length > 0 || window.draggingWindow
                    spacing: Metrics.spaceSm

                    ShellText {
                        text: "Minimized"
                        role: "label"
                        color: Colors.scrimMutedText
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(Metrics.rowHeight, minimizedFlow.implicitHeight) + Metrics.spaceSm * 2
                        radius: Metrics.radiusCard
                        color: minimizedDrop.containsDrag ? Colors.accentSoft : "transparent"
                        border.width: minimizedDrop.containsDrag ? Metrics.focusBorderWidth : Metrics.borderWidth
                        border.color: minimizedDrop.containsDrag ? window.scrimAccent : Colors.panelBorder

                        DropArea {
                            id: minimizedDrop
                            anchors.fill: parent
                            keys: ["buchhwin-window"]
                            onDropped: drag => {
                                if (drag.source.minimized !== true && MinimizeService.minimize(drag.source.address)) {
                                    drag.source.sent = true
                                    refreshTimer.restart()
                                }
                                drag.acceptProposedAction()
                            }
                        }

                        ShellText {
                            anchors.centerIn: parent
                            visible: window.minimized.length === 0
                            text: "Drop a window here to minimize it"
                            role: "small"
                            color: Colors.scrimMutedText
                        }

                        Flow {
                            id: minimizedFlow
                            x: Metrics.spaceSm
                            y: Metrics.spaceSm
                            width: parent.width - Metrics.spaceSm * 2
                            spacing: Metrics.spaceSm

                            Repeater {
                                model: ScriptModel { values: window.shown ? window.minimized : []; objectProp: "address" }

                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    // What a card's DropArea reads off a dragged window.
                                    readonly property string address: modelData.address
                                    readonly property int workspaceId: -1
                                    readonly property bool minimized: true
                                    property bool sent: false
                                    readonly property bool dragging: chipMouse.drag.active
                                    readonly property bool isSelected: !!window.selectedStop && window.selectedStop.kind === "minimized"
                                        && window.selectedStop.key === "m:" + modelData.address
                                    readonly property var entry: DesktopEntries.heuristicLookup(modelData.appClass)
                                    visible: Logic.matches(modelData, search.text) && !sent
                                    width: Metrics.overviewCardMinWidth
                                    height: Metrics.rowHeight
                                    z: dragging ? 10 : 0
                                    radius: Metrics.radiusInner
                                    color: Colors.panelFor("overview")
                                    border.width: isSelected || chipHover.hovered ? Metrics.focusBorderWidth : Metrics.borderWidth
                                    border.color: isSelected ? Colors.scrimText : chipHover.hovered ? Colors.borderStrong : Colors.panelBorder
                                    Drag.active: chipMouse.drag.active
                                    Drag.keys: ["buchhwin-window"]
                                    Drag.source: chip
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: height / 2
                                    // Above the cards while dragged, as a thumbnail is.
                                    states: State {
                                        when: chip.dragging
                                        ParentChange { target: chip; parent: dragLayer }
                                    }
                                    Timer {
                                        interval: Animations.overviewSentTimeout
                                        running: chip.sent
                                        onTriggered: chip.sent = false
                                    }

                                    HoverHandler { id: chipHover }

                                    Image {
                                        id: chipIcon
                                        x: Metrics.spaceSm
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Metrics.iconLg
                                        height: Metrics.iconLg
                                        source: LauncherService.iconSource([chip.entry ? chip.entry.icon : "", chip.modelData.appClass])
                                        sourceSize.width: Metrics.iconLg * 2
                                        sourceSize.height: Metrics.iconLg * 2
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    // On the chip's panel fill, so the panel's
                                    // inks: the scrim's white would vanish on
                                    // a light panel.
                                    Column {
                                        anchors.left: chipIcon.right
                                        anchors.right: parent.right
                                        anchors.leftMargin: Metrics.spaceSm
                                        anchors.rightMargin: Metrics.spaceSm
                                        anchors.verticalCenter: parent.verticalCenter
                                        ShellText {
                                            width: parent.width
                                            text: chip.modelData.title || (chip.entry ? chip.entry.name : "") || chip.modelData.appClass || "Window"
                                            role: "small"
                                            elide: Text.ElideRight
                                        }
                                        ShellText {
                                            width: parent.width
                                            visible: text.length > 0
                                            text: chip.modelData.label
                                            role: "caption"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: chip
                                        drag.threshold: Metrics.dragThreshold
                                        onReleased: if (drag.active) chip.Drag.drop()
                                        onClicked: event => {
                                            if (event.button === Qt.MiddleButton) window.dispatch(HyprCompat.commands.closeWindow(chip.address))
                                            else window.restoreWindow(chip.modelData)
                                        }
                                    }

                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Restore " + (chip.modelData.title || "window")
                                }
                            }
                        }
                    }
                }
            }
        }

        ShellText {
            Layout.alignment: Qt.AlignHCenter
            text: "Arrows select · Enter opens · Del closes · Drag moves · Middle-click closes · Esc closes"
            role: "caption"
            color: Colors.scrimMutedText
        }
    }

    // A window thumbnail being dragged (see `thumb`): above every card and
    // outside the cards' and the flickable's clips.
    Item {
        id: dragLayer
        anchors.fill: content
        z: 1
    }
}
