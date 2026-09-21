import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ShellPanel {
    id: root
    keyForward: keyHandler
    panelId: "powerMenu"
    placement: "center"
    cardWidth: Metrics.powerMenuWidth
    scrimColor: Colors.scrimStrong

    // Plain, not a binding: request() assigns to it, which would destroy a
    // binding for good and leave a confirmation armed across opens. The open
    // handler below is the single place that decides its value.
    property string pendingAction: ""
    property int focusIndex: 0
    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "󰌾", confirm: false },
        { id: "suspend", label: "Sleep", icon: "󰤄", confirm: false },
        { id: "logout", label: "Log out", icon: "󰍃", confirm: true },
        { id: "reboot", label: "Restart", icon: "󰜉", confirm: true },
        { id: "poweroff", label: "Shut down", icon: "󰐥", confirm: true }
    ]
    readonly property var pending: actions.find(action => action.id === pendingAction) || null

    // ShellPanel focuses `keyForward` itself, so there is no second focus owner
    // here. A menu always opens on the menu; only an explicit `confirm`
    // argument opens it on a confirmation.
    onWantedChanged: if (wanted) {
        focusIndex = 0
        pendingAction = String(PanelService.args.confirm || "")
    }

    function run(actionId) {
        PanelService.close("powerMenu")
        SessionService.run(actionId)
    }

    function request(action) {
        if (action.confirm) pendingAction = action.id
        else run(action.id)
    }

    Item {
        id: keyHandler
        width: parent.width
        height: column.implicitHeight
        focus: true
        Keys.onLeftPressed: root.focusIndex = Math.max(0, root.focusIndex - 1)
        Keys.onRightPressed: root.focusIndex = Math.min(root.actions.length - 1, root.focusIndex + 1)
        Keys.onReturnPressed: root.pending ? root.run(root.pending.id) : root.request(root.actions[root.focusIndex])
        Keys.onEnterPressed: root.pending ? root.run(root.pending.id) : root.request(root.actions[root.focusIndex])
        Keys.onEscapePressed: root.pending ? root.pendingAction = "" : PanelService.close("powerMenu")

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Metrics.spaceLg

            RowLayout {
                Layout.fillWidth: true
                ShellText { text: root.pending ? root.pending.label + "?" : "Session"; role: "headline" }
                Item { Layout.fillWidth: true }
                SectionLabel { text: "SUPER + M"; visible: !root.pending }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.pending
                spacing: Metrics.spaceSm

                Repeater {
                    model: root.actions
                    delegate: ShellCard {
                        id: tile
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: Metrics.powerMenuTileHeight
                        interactive: true
                        hovered: tileMouse.containsMouse
                        pressed: tileMouse.pressed && tileMouse.containsMouse
                        highlighted: root.focusIndex === index

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Metrics.spaceSm
                            ShellIcon {
                                Layout.alignment: Qt.AlignHCenter
                                glyph: tile.modelData.icon
                                size: Metrics.powerMenuIcon
                                color: tile.modelData.id === "poweroff" ? Colors.danger : Colors.accentForeground
                            }
                            ShellText { Layout.alignment: Qt.AlignHCenter; text: tile.modelData.label; role: "bodyLarge" }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.focusIndex = tile.index
                            onClicked: root.request(tile.modelData)
                        }
                    }
                }
            }

            ShellText {
                Layout.fillWidth: true
                visible: root.pending !== null
                text: root.pendingAction === "logout"
                    ? "All open apps in this session will be closed."
                    : "Unsaved changes may be lost."
                muted: true
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.pending !== null
                spacing: Metrics.spaceSm
                Item { Layout.fillWidth: true }
                ShellButton { text: "Cancel"; onClicked: root.pendingAction = "" }
                ShellButton {
                    text: root.pending ? root.pending.label : ""
                    variant: "accent"
                    onClicked: root.run(root.pendingAction)
                }
            }
        }
    }
}
