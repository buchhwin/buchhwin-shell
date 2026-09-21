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
    cardWidth: Metrics.settingsWidth
    cardHeight: Metrics.launcherHeight
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

            // Two columns while the card is wide enough: the list is long and a
            // single column would make the sheet scroll for most of it.
            GridLayout {
                id: columns
                width: sheet.width
                columns: sheet.width >= Metrics.wideWidth - Metrics.panelPadding * 2 ? 2 : 1
                columnSpacing: Metrics.spaceXl
                rowSpacing: Metrics.spaceLg

                Repeater {
                    model: root.groups
                    CardSection {
                        id: group
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
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
                                    text: bindRow.modelData.title
                                    font.family: bindRow.modelData.raw ? Typography.monoFamily : Typography.family
                                    color: bindRow.modelData.raw ? Colors.mutedText : Colors.text
                                }
                                KeyChips { keys: bindRow.modelData.keys }
                            }
                        }
                    }
                }
            }
        }
    }
}
