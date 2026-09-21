import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.spaceLg
    property string addId: ""

    readonly property var appOptions: DesktopEntries.applications.values
        .filter(app => app && !app.noDisplay && AutostartService.apps.indexOf(app.id) < 0)
        .map(app => ({ value: app.id, label: app.name || app.id }))
        .sort((a, b) => a.label.localeCompare(b.label))

    SettingsSection {
        Layout.fillWidth: true
        title: "Apps at login"
        description: "Start only in buchhwin-shell, once per login. Plasma stays unchanged."

        Repeater {
            model: AutostartService.apps
            ListRow {
                required property string modelData
                readonly property var app: AutostartService.entry(modelData)
                Layout.fillWidth: true
                iconSource: app ? LauncherService.iconSource(app.icon) : ""
                icon: app ? "" : "󰀻"
                title: app ? app.name : modelData
                subtitle: app ? (app.genericName || app.comment || "") : "No longer installed"
                ShellButton { icon: Icons.remove; variant: "ghost"; compact: true; onClicked: AutostartService.remove(modelData) }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: AutostartService.apps.length === 0
            icon: "󰒲"
            title: "No apps start with the session yet"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellSelect {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                options: appOptions
                current: addId
                placeholder: "Choose an app …"
                filterable: true
                onSelected: value => addId = value
            }
            ShellButton {
                Layout.alignment: Qt.AlignTop
                icon: Icons.add; text: "Add"
                enabledState: addId.length > 0
                onClicked: { AutostartService.add(addId); addId = "" }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "System autostart"
        description: "Standard entries from /etc/xdg/autostart and ~/.config/autostart that apply to this session, e.g. KDE Connect, calendar reminders and screen sharing for X11 apps. Plasma-only services stay off. Takes effect at the next login."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Run standard autostart"
            ShellToggle {
                checked: SettingsService.value("autostart.system")
                onToggled: value => SettingsService.set("autostart.system", value)
            }
        }
    }
}
