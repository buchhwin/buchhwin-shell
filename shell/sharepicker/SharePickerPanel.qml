import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets as QsWidgets
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/sharepicker/SharePickerLogic.js" as Logic
import "../components/NavLogic.js" as Nav

// What an app may see when it asks to share the screen (Teams, a browser,
// OBS): the screens and windows with live previews, as the overview shows
// them, and a region drawn with slurp - on the screen the user is looking
// at, in the shell's own look rather than the portal's plain dialog
// (scripts/share-picker.sh, services/SharePickerService.qml).
//
// The arrow keys walk the choices, Enter shares the selected one, Escape or
// a click beside the card cancels the share; a click selects and a double
// click shares. The selection starts on this screen, so Enter right after
// the picker opens shares the screen in front of the user.
ShellPanel {
    id: root
    panelId: "sharePicker"
    placement: "center"
    cardWidth: Metrics.wallpaperPickerWidth
    cardHeight: Metrics.wallpaperPickerHeight
    keyForward: keys
    // The portal waits for the answer: a click beside the card is "no".
    dismissOnOutsideClick: true

    // "Remember" for the portal: the app may get a token and share the same
    // thing again later without asking. Starts as the portal's own setting
    // says (`allow_token_by_default`).
    property bool allowToken: false
    property int selected: 0
    property string selectedKey: ""
    // The windows Hyprland knows, by address: where they are and how big,
    // read once per open (the order and the previews' shapes).
    property var windowInfo: ({})

    readonly property var screenEntries: shown ? Quickshell.screens.map(screen => ({
        name: screen.name, width: screen.width, height: screen.height })) : []
    readonly property var windows: shown ? Logic.orderWindows(SharePickerService.windows, windowInfo) : []
    readonly property var stops: Logic.stops(screenEntries, windows, SharePickerService.regionAvailable)
    readonly property var stopByKey: {
        const index = {}
        for (const stop of stops) index[stop.key] = stop
        return index
    }
    // The keys the views are made of: strings, so a row is kept while its
    // data changes (testing.md pitfall 76).
    readonly property var screenKeys: stops.filter(stop => stop.kind === "screen").map(stop => stop.key)
    readonly property var windowKeys: stops.filter(stop => stop.kind === "window").map(stop => stop.key)
    readonly property bool regionShown: stops.some(stop => stop.kind === "region")

    readonly property real innerWidth: Math.max(0, cardTargetWidth - Metrics.panelPadding * 2)
    // A third of the card at most: a laptop's one screen across the whole
    // card pushed every window below the fold, and two screens across half
    // of it each still left the windows' names and the region under it.
    readonly property int screenColumns: 3
    readonly property int windowColumns: 4
    readonly property real screenTileWidth: Math.floor((innerWidth - Metrics.spaceMd * (screenColumns - 1)) / screenColumns)
    readonly property real windowTileWidth: Math.floor((innerWidth - Metrics.spaceMd * (windowColumns - 1)) / windowColumns)
    readonly property var columns: ({ screens: screenColumns, windows: windowColumns, region: 1 })

    onWantedChanged: {
        if (!wanted) {
            SharePickerService.closed()
            return
        }
        allowToken = SharePickerService.allowTokenDefault
        Hyprland.refreshToplevels()
        readWindowInfo()
        // Once the lists are there: they are made while the panel is shown,
        // and ShellPanel turns `shown` on in its own handler of this change.
        Qt.callLater(() => root.select(Logic.openingIndex(root.stops, PanelService.screenName)))
    }
    onStopsChanged: {
        const at = Logic.indexOfKey(stops, selectedKey)
        selected = at >= 0 ? at : Math.max(0, Math.min(stops.length - 1, selected))
        selectedKey = stops.length ? stops[selected].key : ""
    }

    function readWindowInfo() {
        const shownIds = Hyprland.monitors.values
            .map(monitor => monitor.activeWorkspace ? monitor.activeWorkspace.id : null)
            .filter(id => id !== null)
        const info = {}
        for (const toplevel of Hyprland.toplevels.values) {
            const ipc = toplevel.lastIpcObject || {}
            const size = Array.isArray(ipc.size) ? ipc.size : [0, 0]
            const workspace = toplevel.workspace ? toplevel.workspace.id : 0
            info[Logic.addressKey(toplevel.address)] = { workspace: workspace, shown: shownIds.indexOf(workspace) >= 0,
                                                         width: Number(size[0]) || 0, height: Number(size[1]) || 0 }
        }
        windowInfo = info
    }
    function toplevelFor(address) {
        const key = Logic.addressKey(address)
        if (!key.length) return null
        return Hyprland.toplevels.values.find(item => Logic.addressKey(item.address) === key) || null
    }
    function screenFor(name) {
        return Quickshell.screens.find(screen => screen.name === name) || null
    }
    function select(index) {
        if (!stops.length) return
        selected = Math.max(0, Math.min(stops.length - 1, index))
        selectedKey = stops[selected].key
        const item = keyItems[selectedKey]
        if (item) Nav.reveal(item, Metrics.spaceMd)
    }
    function share(key) {
        const stop = stopByKey[key === undefined ? selectedKey : key]
        if (stop) SharePickerService.choose(stop, allowToken)
    }
    // The delegates by key, so the keys can scroll the selected one into
    // view.
    property var keyItems: ({})
    function register(key, item, on) {
        const next = Object.assign({}, keyItems)
        if (on) next[key] = item
        else if (next[key] === item) delete next[key]
        keyItems = next
    }

    // The keyboard's place while the picker is open.
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const direction = { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down" }[event.key]
            if (direction) {
                root.select(Logic.move(root.stops, root.selected, direction, root.columns))
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.share()
                event.accepted = true
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            title: "Share your screen"
            subtitle: SharePickerService.preview ? "A preview: choosing here shares nothing"
                : "An app asks to see your screen. Choose what it may see."
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: sections.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollFeel { id: feel; view: flick }

                ColumnLayout {
                    id: sections
                    width: flick.width
                    spacing: Metrics.spaceMd

                    SectionLabel { text: "Screens"; visible: root.screenKeys.length > 0 }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceMd
                        Repeater {
                            model: ScriptModel { values: root.screenKeys }
                            ChoiceCard {
                                required property string modelData
                                readonly property var screen: root.screenFor(root.stopByKey[modelData] ? root.stopByKey[modelData].name : "")
                                choiceKey: modelData
                                width: root.screenTileWidth
                                boxHeight: Math.round(root.screenTileWidth * 10 / 16)
                                sourceWidth: screen ? screen.width : 0
                                sourceHeight: screen ? screen.height : 0
                                source: root.shown ? screen : null
                                glyph: "\u{f0379}"
                                label: Logic.screenLabel(screen, screen ? DisplayService.monitor(screen.name) : null,
                                                         screen !== null && screen.name === DisplayService.internalName)
                            }
                        }
                    }

                    SectionLabel {
                        Layout.topMargin: Metrics.spaceSm
                        text: "Windows"
                    }
                    ShellText {
                        Layout.fillWidth: true
                        visible: root.windowKeys.length === 0
                        text: "No window the portal can share"
                        role: "small"
                        muted: true
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: root.windowKeys.length > 0
                        spacing: Metrics.spaceMd
                        Repeater {
                            model: ScriptModel { values: root.windowKeys }
                            ChoiceCard {
                                required property string modelData
                                readonly property var entry: root.stopByKey[modelData] ? root.stopByKey[modelData].entry : null
                                readonly property var info: entry ? root.windowInfo[Logic.addressKey(entry.address)] || null : null
                                readonly property var toplevel: root.shown && entry ? root.toplevelFor(entry.address) : null
                                choiceKey: modelData
                                width: root.windowTileWidth
                                boxHeight: Math.round(root.windowTileWidth * 10 / 16)
                                sourceWidth: info ? info.width : 0
                                sourceHeight: info ? info.height : 0
                                source: toplevel ? toplevel.wayland : null
                                glyph: Icons.window
                                label: Logic.windowLabel(entry)
                                detail: entry && entry.title.length ? entry.appClass : ""
                            }
                        }
                    }

                    SectionLabel {
                        Layout.topMargin: Metrics.spaceSm
                        visible: root.regionShown
                        text: "Region"
                    }
                    ChoiceCard {
                        visible: root.regionShown
                        choiceKey: "region"
                        // A window's tile: one choice among the others, not a bar
                        // across the picker.
                        Layout.preferredWidth: root.windowTileWidth
                        boxHeight: Math.round(root.windowTileWidth * 10 / 16)
                        glyph: "\u{f0a6d}"
                        label: "Select a region …"
                        detail: "Drawn once this closes"
                    }
                }
            }

            // A hint that there is more below, as ScrollList draws it: the
            // windows' names and the region were under the fold without a
            // word.
            Rectangle {
                visible: flick.contentHeight > flick.height + 1
                x: flick.width - width
                y: flick.visibleArea.yPosition * flick.height
                width: Metrics.scrollHintWidth
                height: Math.max(Metrics.spaceLg, flick.visibleArea.heightRatio * flick.height)
                radius: width / 2
                color: Colors.scrollHint
                opacity: flick.moving || feel.scrolling ? 1 : Effects.mutedOpacity
                Behavior on opacity {
                    NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            ShellToggle {
                focusOnTab: true
                accessibleName: "Allow sharing it again without asking"
                checked: root.allowToken
                onToggled: value => root.allowToken = value
            }
            ShellText {
                Layout.fillWidth: true
                text: "Allow sharing it again without asking"
                role: "small"
                muted: true
                elide: Text.ElideRight
            }
            // A preview shares nothing: one Close, without the share glyph,
            // rather than a Cancel beside a "Close" that looked like Share.
            ShellButton {
                visible: !SharePickerService.preview
                text: "Cancel"
                variant: "ghost"
                onClicked: root.requestClose()
            }
            ShellButton {
                icon: SharePickerService.preview ? "" : Icons.share
                text: SharePickerService.preview ? "Close" : "Share"
                variant: "accent"
                enabledState: root.stopByKey[root.selectedKey] !== undefined
                onClicked: root.share()
            }
        }
    }

    // One choice: a live preview (or a glyph), its name under it, the
    // selection's outline. A click selects, a double click shares.
    component ChoiceCard: Item {
        id: card
        property string choiceKey: ""
        property real boxHeight: 0
        property real sourceWidth: 0
        property real sourceHeight: 0
        property var source: null
        property string glyph: ""
        property string label: ""
        property string detail: ""
        readonly property bool isSelected: root.selectedKey === choiceKey
        readonly property var fitted: Logic.fitInside(sourceWidth, sourceHeight, width - Metrics.spaceSm * 2,
                                                      boxHeight - Metrics.spaceSm * 2)
        implicitHeight: frame.height + Metrics.spaceXs + caption.implicitHeight
        Component.onCompleted: root.register(choiceKey, card, true)
        // At the shell's exit the panel can be gone before its cards: built
        // from its file (shell.qml), its own context goes with it, and a card
        // then finds no `root` to take its record back from.
        Component.onDestruction: if (root) root.register(choiceKey, card, false)
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: root.share(choiceKey)

        Rectangle {
            id: frame
            width: parent.width
            height: card.boxHeight
            radius: Metrics.radiusCard
            color: hover.hovered ? Colors.surface2Hover : Colors.surface2
            border.width: card.isSelected ? Metrics.focusBorderWidth : Metrics.borderWidth
            border.color: card.isSelected ? Colors.accentForeground : hover.hovered ? Colors.borderStrong : Colors.border

            // Inside the rounding (a Rectangle does not clip to its radius,
            // pitfall 4), at the source's own shape.
            QsWidgets.ClippingRectangle {
                anchors.centerIn: parent
                visible: card.source !== null
                width: card.fitted.width
                height: card.fitted.height
                radius: Metrics.radiusInner
                color: "transparent"

                ScreencopyView {
                    id: preview
                    anchors.fill: parent
                    captureSource: card.source
                    // Only while the picker is open; the last frame stays
                    // through the close.
                    live: root.wanted
                    constraintSize: Qt.size(width, height)
                }
            }
            ShellIcon {
                anchors.centerIn: parent
                visible: card.source === null || !preview.hasContent
                glyph: card.glyph
                size: Metrics.iconXl
                color: Colors.mutedText
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: root.select(Logic.indexOfKey(root.stops, card.choiceKey))
                onDoubleTapped: root.share(card.choiceKey)
            }
        }
        ColumnLayout {
            id: caption
            anchors.top: frame.bottom
            anchors.topMargin: Metrics.spaceXs
            width: parent.width
            spacing: 0
            ShellText {
                Layout.fillWidth: true
                text: card.label
                role: "small"
                color: card.isSelected ? Colors.accentForeground : Colors.text
            }
            ShellText {
                Layout.fillWidth: true
                visible: card.detail.length > 0
                text: card.detail
                role: "caption"
            }
        }
    }
}
