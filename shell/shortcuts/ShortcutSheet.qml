import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Super+F1: every key combination the session knows, in the groups the
// settings page uses, with a search field. Read-only - the shortcuts
// themselves are edited in Settings > Shortcuts.
ShellPanel {
    id: root
    keyForward: search
    panelId: "shortcutSheet"
    placement: "center"
    cardWidth: Metrics.shortcutSheetWidth
    cardHeight: Metrics.shortcutSheetHeight
    scrimColor: Colors.scrimStrong

    property string query: ""
    readonly property var groups: ShortcutService.grouped(query)
    readonly property int count: groups.reduce((total, group) => total + group.rows.length, 0)

    onWantedChanged: if (wanted) query = ""

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            title: "Keyboard shortcuts"
            subtitle: root.count + " combinations · edit them in Settings > Shortcuts"

            ShellButton {
                icon: Icons.settings
                text: "Settings"
                variant: "ghost"
                compact: true
                onClicked: PanelService.open("settings", { page: "shortcuts" })
            }
        }

        ShellTextField {
            id: search
            Layout.fillWidth: true
            icon: Icons.search
            placeholder: "Search shortcuts …"
            onTextChanged: root.query = text
        }

        EmptyState {
            Layout.fillWidth: true
            visible: root.groups.length === 0
            icon: ShortcutService.binds.length ? Icons.search : Icons.busy
            title: ShortcutService.binds.length ? "No shortcut matches" : "Loading …"
        }

        Flickable {
            id: sheet
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.groups.length > 0
            contentHeight: columns.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // As many columns as the card is wide enough for, and **not** a
            // `GridLayout`. A grid makes every row as tall as its tallest cell,
            // so Apps with three rows beside Shell panels with eleven left
            // eight rows of nothing underneath it, over and over down the
            // sheet. These are real columns, each packed tight from the top;
            // `ShortcutService.columnise` decides which group goes where.
            readonly property int columnCount:
                Math.max(1, Math.min(3, Math.floor(width / Metrics.shortcutColumnWidth)))

            RowLayout {
                id: columns
                width: sheet.width
                spacing: Metrics.spaceXl

                Repeater {
                    model: ShortcutService.columnise(root.groups, sheet.columnCount)
                    ColumnLayout {
                        id: column
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 1
                        spacing: Metrics.spaceLg

                        Repeater {
                            model: column.modelData
                            CardSection {
                                id: group
                                required property var modelData
                                Layout.fillWidth: true
                                padding: Metrics.spaceMd
                                spacing: Metrics.spaceXxs
                                title: modelData.title

                                Repeater {
                                    model: group.modelData.rows
                                    RowLayout {
                                        id: bindRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.minimumHeight: Metrics.controlHeight
                                        spacing: Metrics.spaceMd
                                        ShellText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: bindRow.modelData.title
                                            font.family: bindRow.modelData.raw ? Typography.monoFamily : Typography.family
                                            color: bindRow.modelData.raw ? Colors.mutedText : Colors.text
                                        }
                                        KeyChips { keys: bindRow.modelData.keys }
                                    }
                                }
                            }
                        }

                        // The columns are level, not equal; whatever is left
                        // under the shortest one is this, not a stretched card.
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
