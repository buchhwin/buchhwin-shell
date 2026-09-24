import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/overview/OverviewLogic.js" as Logic

// Super+W: workspaces with live window previews. Type to filter, arrows to
// select, Enter to focus, Delete to close; click a workspace to switch to it,
// drag a window onto another workspace to move it there.
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
    cardWidth: width
    cardHeight: height - Metrics.panelTopOffset - Metrics.screenMargin
    property var workspaces: []
    // The monitors as `hyprctl` last described them, for the grouping.
    property var monitors: []
    readonly property var groups: Logic.groups(workspaces, monitors)
    property int selected: 0
    readonly property var flat: Logic.flatWindows(workspaces, search.text)
    readonly property var selectedWindow: flat.length ? flat[Math.min(selected, flat.length - 1)] : null
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
        (most, group) => Math.max(most, group.workspaces.length + 1), 1)
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
    function toplevelFor(address) {
        const key = Logic.normalizeAddress(address)
        return Hyprland.toplevels.values.find(item => Logic.normalizeAddress(item.address) === key) || null
    }

    onWantedChanged: {
        if (!wanted) return
        search.text = ""
        selected = 0
        refresh()
    }
    onFlatChanged: selected = Math.min(selected, Math.max(0, flat.length - 1))

    Timer { id: refreshTimer; interval: 250; onTriggered: window.refresh() }
    Timer {
        id: pendingTimer
        interval: 120
        onTriggered: if (window.pendingDispatch) { HyprCompat.dispatch(window.pendingDispatch); window.pendingDispatch = null }
    }

    Process {
        id: loadProc
        command: ["sh", "-c", "printf '{\"clients\":'; hyprctl -j clients; printf ',\"monitors\":'; hyprctl -j monitors; printf ',\"workspaces\":'; hyprctl -j workspaces; printf '}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    window.monitors = data.monitors || []
                    window.workspaces = Logic.build(data.clients, data.monitors, data.workspaces,
                                                   SettingsService.value("workspaces.mode"),
                                                   SettingsService.value("workspaces.count"),
                                                   HyprlandService.perMonitor)
                } catch (error) {
                    window.monitors = []
                    window.workspaces = []
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
            Layout.preferredWidth: Metrics.launcherWidth * 0.7
            icon: Icons.search
            placeholder: "Search windows …"
            color: Colors.panelFor("overview")
            onAccepted: window.focusWindow(window.selectedWindow)
            onEscapePressed: if (!text.length) PanelService.close("overview")
            Keys.onLeftPressed: event => { if (text.length) { event.accepted = false; return } window.selected = Math.max(0, window.selected - 1) }
            Keys.onRightPressed: event => { if (text.length) { event.accepted = false; return } window.selected = Math.min(window.flat.length - 1, window.selected + 1) }
            Keys.onUpPressed: window.selected = Math.max(0, window.selected - 1)
            Keys.onDownPressed: window.selected = Math.min(window.flat.length - 1, window.selected + 1)
            onDeleteOnEmpty: if (window.selectedWindow) window.dispatch(HyprCompat.commands.closeWindow(window.selectedWindow.address))
        }

        // A search that matches nothing used to leave every card on screen
        // with its windows filtered away - up to twenty-seven empty
        // rectangles, which reads as a broken overview rather than as an
        // answer. The cards are worth showing while no search is typed,
        // because switching to an empty workspace is a thing to do; once a
        // query is on screen the question is about windows and the honest
        // reply is that there are none.
        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: search.text.length > 0 && window.flat.length === 0
            icon: Icons.search
            title: "No window matches \u201c" + search.text + "\u201d"
            description: "Escape clears the search"
        }

        Flickable {
            id: cardsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(search.text.length > 0 && window.flat.length === 0)
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

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

                Repeater {
                    model: window.groups

                    ColumnLayout {
                        id: row
                        required property var modelData
                        width: cards.width
                        spacing: Metrics.spaceSm

                        ShellText {
                            // Only worth a heading when there is more than one
                            // screen to tell apart.
                            visible: window.groups.length > 1 && row.modelData.monitor.length > 0
                            text: "Monitor " + row.modelData.number + " \u00b7 " + row.modelData.monitor
                            role: "label"
                            color: row.modelData.focused ? Colors.scrimAccent : Colors.scrimMutedText
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXl

                            Repeater {
                                // The row's own next free number, not the
                                // session's: a global one would offer the
                                // third monitor a number belonging to the first.
                                model: row.modelData.workspaces.concat([{ id: Logic.nextFreeIn(row.modelData.workspaces, row.modelData.base),
                                    label: "", name: "", windows: [], aspect: row.modelData.aspect, active: false,
                                    monitor: row.modelData.monitor, placeholder: true }])

                            ColumnLayout {
                                id: card
                                required property var modelData
                                readonly property bool placeholder: modelData.placeholder === true
                                readonly property bool dropHover: drop.containsDrag
                                width: window.workspaceWidth
                                spacing: Metrics.spaceSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    ShellText {
                                        // `label` and not `name`: with a block
                                        // per monitor the compositor's id can
                                        // be 23 while the card is that
                                        // monitor's third.
                                        text: card.placeholder ? "New workspace" : "Workspace " + card.modelData.label
                                        color: card.modelData.active ? Colors.scrimAccent : Colors.scrimText
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
                                }

                                Rectangle {
                                    id: frame
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width * card.modelData.aspect
                                    radius: Metrics.radiusCard
                                    color: card.dropHover ? Colors.accentSoft : Colors.panelFor("overview")
                                    border.width: card.modelData.active || card.dropHover ? Metrics.focusBorderWidth : Metrics.borderWidth
                                    border.color: card.modelData.active || card.dropHover ? Colors.scrimAccent : Colors.panelBorder
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
                                        source: card.placeholder ? ""
                                            : WallpaperService.currentFor(card.modelData.monitor)
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
                                            window.dispatch(HyprCompat.commands.moveWindowSilent(card.modelData.id, drag.source.address))
                                            drag.acceptProposedAction()
                                        }
                                    }

                                    Repeater {
                                        model: card.modelData.windows.filter(entry => Logic.matches(entry, search.text))

                                        Rectangle {
                                            id: thumb
                                            required property var modelData
                                            readonly property string address: modelData.address
                                            readonly property bool isSelected: window.selectedWindow !== null && window.selectedWindow.address === modelData.address
                                            readonly property var toplevel: window.wanted ? window.toplevelFor(modelData.address) : null
                                            property real homeX: modelData.x * frame.width
                                            property real homeY: modelData.y * frame.height
                                            x: dragArea.drag.active ? x : homeX + Metrics.spaceXxs
                                            y: dragArea.drag.active ? y : homeY + Metrics.spaceXxs
                                            width: Math.max(Metrics.iconXl, modelData.width * frame.width - Metrics.spaceXxs * 2)
                                            height: Math.max(Metrics.iconXl, modelData.height * frame.height - Metrics.spaceXxs * 2)
                                            z: dragArea.drag.active ? 10 : isSelected ? 2 : 1
                                            radius: Metrics.radiusInner
                                            color: Colors.elevatedSurface
                                            border.width: isSelected || hover.hovered ? Metrics.focusBorderWidth : Metrics.borderWidth
                                            border.color: isSelected ? Colors.scrimAccent : hover.hovered ? Colors.borderStrong : Colors.border
                                            clip: true
                                            Drag.active: dragArea.drag.active
                                            Drag.keys: ["buchhwin-window"]
                                            Drag.source: thumb
                                            Drag.hotSpot.x: width / 2
                                            Drag.hotSpot.y: height / 2

                                            HoverHandler { id: hover }

                                            ScreencopyView {
                                                id: preview
                                                anchors.fill: parent
                                                anchors.margins: Metrics.borderWidth
                                                captureSource: thumb.toplevel ? thumb.toplevel.wayland : null
                                                live: window.wanted
                                                // Capture at preview size instead of the
                                                // window's own resolution (the switcher
                                                // does the same); a wall of full-size
                                                // captures made the fade-in stutter.
                                                constraintSize: Qt.size(width, height)
                                            }

                                            ShellIcon {
                                                anchors.centerIn: parent
                                                visible: !preview.hasContent
                                                glyph: Icons.window
                                                size: Metrics.iconLg
                                                color: Colors.mutedText
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                // Inside the thumbnail's border, with its
                                                // bottom corners rounded to match: a
                                                // Rectangle does not clip its children to
                                                // its radius (see the wallpaper above), so
                                                // a square bar stuck out of the round
                                                // corners.
                                                anchors.margins: Metrics.borderWidth
                                                bottomLeftRadius: Math.max(0, Metrics.radiusInner - Metrics.borderWidth)
                                                bottomRightRadius: Math.max(0, Metrics.radiusInner - Metrics.borderWidth)
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
            }
        }

        ShellText {
            Layout.alignment: Qt.AlignHCenter
            text: "Enter focuses · Del closes · Drag moves · Middle-click closes · Esc closes"
            role: "caption"
            color: Colors.scrimMutedText
        }
    }
}
