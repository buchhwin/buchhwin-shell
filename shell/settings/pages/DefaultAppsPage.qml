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
    spacing: Metrics.spaceLg

    readonly property var icons: ({
        browser: "󰖟", email: "󰇮", files: Icons.folder, terminal: "󰆍", text: "󰈙",
        images: "󰋩", pdf: "󰈦", video: "󰕧", music: "󰝚", archives: "󰀼"
    })
    readonly property var hints: ({
        browser: "Links · Super+B", files: "Folders · Super+E", terminal: "Super+Enter"
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

                ShellIcon { glyph: root.icons[appRow.modelData.id] || "󰀻"; size: Metrics.iconMd; color: Colors.accentForeground }
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
                        text: appRow.modelData.source === "session" ? "This session"
                            : appRow.modelData.source === "plasma" ? "From Plasma" : "System default"
                        role: "small"
                        muted: true
                    }
                    ShellButton {
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
