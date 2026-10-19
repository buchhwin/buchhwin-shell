import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/display/ProjectionLogic.js" as Projection

// The display switcher: Super+Shift+P, or the projector key (XF86Display) -
// what Windows' Win+P and KDE's Meta+P are. Laptop only, the same picture on
// every screen, one desktop over all of them, or the external screens only,
// as tiles like the session menu's. A choice is applied at once and closes
// the switcher; it lasts while the same displays are connected, and
// unplugging one ends it (ProjectionLogic) - which is also the way back from
// "External only" on a screen that shows nothing. Settings > Displays is
// where a layout is kept for good.
//
// Built on its first open (shell.qml's LazyLoader, PanelService.lazyPanels):
// most sessions never meet a projector.
ShellPanel {
    id: root
    keyForward: keyHandler
    panelId: "displaySwitcher"
    placement: "center"
    cardWidth: Metrics.powerMenuWidth

    readonly property var choices: DisplayService.projectionChoices
    // The tile the keys are on; where the switcher opens, the choice in use.
    property string focusValue: ""
    readonly property int focusIndex: Math.max(0, choices.findIndex(item => item.value === focusValue))
    readonly property bool anyChoice: choices.some(item => item.enabled)

    onWantedChanged: if (wanted) focusValue = DisplayService.currentProjection

    function move(delta) {
        if (!choices.length) return
        let index = focusIndex
        for (let tries = 0; tries < choices.length; ++tries) {
            index = (index + delta + choices.length) % choices.length
            if (choices[index].enabled) { focusValue = choices[index].value; return }
        }
    }

    // Closed first, applied a turn later: "External only" takes the panel's
    // own screen away, and the card should not be on it when it goes.
    function choose(value) {
        const item = choices.find(entry => entry.value === value) || null
        if (!item || !item.enabled) return
        PanelService.close(panelId)
        Qt.callLater(() => DisplayService.setProjection(value))
    }

    // The projector key again while open: the next choice, as Windows'.
    Connections {
        target: DisplayService
        function onSwitcherStepped() {
            if (!root.wanted) return
            root.focusValue = Projection.next(root.focusValue, root.choices)
        }
    }

    Item {
        id: keyHandler
        width: parent.width
        height: column.implicitHeight
        focus: true
        // The arrows walk the tiles; Tab leaves them for "Display settings"
        // and comes back - it cycled the tiles, and the button was out of
        // the keyboard's reach.
        activeFocusOnTab: true
        Keys.onLeftPressed: root.move(-1)
        Keys.onRightPressed: root.move(1)
        Keys.onReturnPressed: root.choose(root.focusValue)
        Keys.onEnterPressed: root.choose(root.focusValue)
        Keys.onEscapePressed: PanelService.close(root.panelId)
        // 1-4: a tile by its place, as it is drawn.
        Keys.onPressed: event => {
            const index = event.key - Qt.Key_1
            if (index < 0 || index >= root.choices.length) return
            root.choose(root.choices[index].value)
            event.accepted = true
        }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Metrics.panelGap

            PanelHeader {
                Layout.fillWidth: true
                title: "Displays"
                subtitle: Projection.label(DisplayService.currentProjection)
                shortcut: "SUPER + SHIFT + P"
            }

            // The gap of every grid of cards, as the session menu's tiles.
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.cardGridGap

                Repeater {
                    // Values, not the objects: the list is made anew on every
                    // monitor read, and strings keep their delegates.
                    model: root.choices.map(item => item.value)
                    delegate: ShellCard {
                        id: tile
                        required property string modelData
                        required property int index
                        readonly property var choice: root.choices.find(item => item.value === modelData) || null
                        readonly property bool usable: choice !== null && choice.enabled
                        readonly property bool inUse: DisplayService.currentProjection === modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: Metrics.powerMenuTileHeight
                        interactive: usable
                        hovered: tileMouse.containsMouse
                        pressed: tileMouse.pressed && tileMouse.containsMouse
                        highlighted: usable && root.focusValue === modelData
                        opacity: usable ? 1 : Effects.disabledOpacity
                        Accessible.role: Accessible.Button
                        Accessible.name: choice ? choice.label : ""

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Metrics.spaceSm
                            ShellIcon {
                                Layout.alignment: Qt.AlignHCenter
                                glyph: tile.choice ? tile.choice.glyph : ""
                                size: Metrics.powerMenuIcon
                                color: tile.usable ? Colors.accentForeground : Colors.mutedText
                            }
                            ShellText {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.choice ? tile.choice.label : ""
                                role: "bodyLarge"
                            }
                            // The tile's digit key, and which one the screens
                            // are in now beside where the keys are (the two can
                            // differ while choosing): "In use" alone took the
                            // place of its digit.
                            ShellText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(tile.index + 1) + (tile.inUse ? " · In use" : "")
                                role: "caption"
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: tile.usable
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.focusValue = tile.modelData
                            onClicked: root.choose(tile.modelData)
                        }
                    }
                }
            }

            // The note and the way to a layout kept for good on one row: the
            // button says the rest.
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    muted: true
                    role: "small"
                    text: !root.anyChoice || DisplayService.monitors.length < 2
                        ? "Only one display is connected."
                        : DisplayService.lidClosed && DisplayService.internalName.length
                        ? "The lid is shut, so the laptop screen stays off. A choice lasts until a display is plugged in or out."
                        : "A choice lasts until a display is plugged in or out."
                }
                ShellButton {
                    Layout.alignment: Qt.AlignTop
                    focusOnTab: true
                    text: "Display settings"
                    icon: Icons.settings
                    variant: "ghost"
                    onClicked: PanelService.open("settings", { page: "displays" })
                }
            }
        }
    }
}
