import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/launcher/WebSearch.js" as Web

// Settings > Launcher: what the launcher does besides finding apps.
ColumnLayout {
    id: root
    spacing: Metrics.panelGap
    readonly property string engine: SettingsService.value("launcher.searchEngine")
    readonly property string template: SettingsService.value("launcher.searchUrl")

    SettingsSection {
        Layout.fillWidth: true
        title: "Web search"
        description: "Type ? followed by what you are looking for. An address you type is offered as “Open” without a prefix."

        SettingRow {
            Layout.fillWidth: true
            label: "Search with"
            ShellSelect {
                Layout.fillWidth: true
                focusOnTab: true
                options: Web.engines.map(entry => ({ value: entry.value, label: entry.label }))
                current: root.engine
                onSelected: value => SettingsService.set("launcher.searchEngine", value)
            }
        }

        SettingRow {
            Layout.fillWidth: true
            visible: root.engine === "custom"
            label: "Address"
            hint: "Put %s where the search term belongs"
            ShellTextField {
                Layout.fillWidth: true
                focusOnTab: true
                text: root.template
                placeholder: "https://example.org/search?q=%s"
                border.color: Web.customError(text).length ? Colors.danger
                    : inputActiveFocus ? Colors.accentBorder : Colors.border
                onTextChanged: SettingsService.set("launcher.searchUrl", text)
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: root.engine === "custom" && Web.customError(root.template).length > 0
            text: Web.customError(root.template)
            role: "small"
            color: Colors.danger
            wrapMode: Text.Wrap
        }

        ShellText {
            Layout.fillWidth: true
            visible: Web.searchUrl("example", root.engine, root.template).length > 0
            text: "Example: ?example opens " + Web.searchUrl("example", root.engine, root.template)
            role: "small"
            muted: true
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Files"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Search files with /"
            hint: "Uses plocate; results open in the default app"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("launcher.fileSearch")
                onToggled: value => SettingsService.set("launcher.fileSearch", value)
            }
        }
    }
}
