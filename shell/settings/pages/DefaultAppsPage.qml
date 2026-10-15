import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Default Apps: which app opens links and files in this session and
// starts with Super+B, Super+E and Super+Enter.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    readonly property var icons: ({
        browser: "󰖟", email: "󰇮", files: Icons.folder, terminal: "󰆍", text: "󰈙",
        images: "󰋩", pdf: "󰈦", video: "󰕧", music: "󰝚", archives: "󰀼"
    })
    readonly property var hints: ({
        browser: "Links · " + ShortcutService.keyHint("SUPER + B", true),
        files: "Folders · " + ShortcutService.keyHint("SUPER + E", true),
        terminal: ShortcutService.keyHint("SUPER + RETURN", true)
    })

    PageActivity { onOpened: DefaultAppsService.refresh() }

    SettingsSection {
        Layout.fillWidth: true
        title: "Default apps"
        description: "Used when links and files are opened in this session. Plasma keeps its own defaults; reset a row to follow Plasma or the system again."

        ShellText {
            Layout.fillWidth: true
            visible: DefaultAppsService.error.length > 0
            text: DefaultAppsService.error
            role: "small"
            color: Colors.warning
            wrapMode: Text.Wrap
        }
        EmptyState {
            Layout.fillWidth: true
            visible: DefaultAppsService.loading && !DefaultAppsService.categories.length
            row: true
            icon: Icons.busy
            title: "Loading …"
        }

        Repeater {
            model: DefaultAppsService.categories
            RowLayout {
                id: appRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Metrics.spaceMd

                // Pinned to the row's first line, with the text and the reset
                // button below: an open select grows the row by its list, and
                // they slid down to the middle of it.
                ShellIcon {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: (Metrics.controlHeight - implicitHeight) / 2
                    glyph: root.icons[appRow.modelData.id] || "󰀻"
                    size: Metrics.iconMd
                    color: Colors.accentForeground
                }
                // The same label column every other settings row has; the
                // hotkey is the label's explanation, where the choice came
                // from is state and stays on the row.
                SettingRow {
                    Layout.fillWidth: true
                    label: appRow.modelData.label
                    hint: root.hints[appRow.modelData.id] || ""
                    ShellSelect {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: appRow.modelData.candidates.map(app => ({ value: app.id, label: app.name }))
                        current: appRow.modelData.current
                        placeholder: "Not set"
                        onSelected: value => { if (value !== appRow.modelData.current) DefaultAppsService.setDefault(appRow.modelData.id, value) }
                    }
                    ShellText {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: (Metrics.controlHeight - implicitHeight) / 2
                        text: appRow.modelData.source === "session" ? "This session"
                            : appRow.modelData.source === "plasma" ? "From Plasma" : "System default"
                        role: "small"
                        muted: true
                    }
                    ShellButton {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: (Metrics.controlHeight - implicitHeight) / 2
                        focusOnTab: true
                        icon: Icons.reset
                        compact: true
                        variant: "ghost"
                        toolTip: "Follow Plasma or the system again"
                        enabledState: appRow.modelData.session
                        onClicked: DefaultAppsService.reset(appRow.modelData.id)
                    }
                }
            }
        }
    }
}
