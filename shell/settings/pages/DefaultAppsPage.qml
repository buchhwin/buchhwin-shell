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

    Component.onCompleted: DefaultAppsService.refresh()

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
        ShellText {
            visible: DefaultAppsService.loading && !DefaultAppsService.categories.length
            text: "Loading …"
            muted: true
        }

        Repeater {
            model: DefaultAppsService.categories
            RowLayout {
                id: appRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Metrics.spaceMd

                ShellIcon { glyph: root.icons[appRow.modelData.id] || "󰀻"; size: Metrics.iconMd; color: Colors.accentForeground }
                ColumnLayout {
                    Layout.fillWidth: false
                    Layout.preferredWidth: Metrics.settingsSidebarWidth
                    Layout.maximumWidth: Metrics.settingsSidebarWidth
                    spacing: 0
                    ShellText { Layout.fillWidth: true; text: appRow.modelData.label }
                    ShellText {
                        Layout.fillWidth: true
                        text: (root.hints[appRow.modelData.id] ? root.hints[appRow.modelData.id] + " · " : "")
                            + (appRow.modelData.source === "session" ? "This session"
                               : appRow.modelData.source === "plasma" ? "From Plasma" : "System default")
                        role: "caption"
                    }
                }
                ShellSelect {
                    Layout.fillWidth: true
                    options: appRow.modelData.candidates.map(app => ({ value: app.id, label: app.name }))
                    current: appRow.modelData.current
                    placeholder: "Not set"
                    onSelected: value => { if (value !== appRow.modelData.current) DefaultAppsService.setDefault(appRow.modelData.id, value) }
                }
                ShellButton {
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
