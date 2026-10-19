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

    // The rows by category id. The list comes anew after every read - and a
    // choice is a write and a read - so a Repeater over it built all ten
    // rows again: the select the keyboard had just picked from lost the
    // focus, and a list open on another row closed.
    readonly property var categoryIds: DefaultAppsService.categories.map(category => category.id)
    function categoryById(id) {
        return DefaultAppsService.categories.find(entry => entry.id === id)
            || { id: id, label: "", candidates: [], current: "", source: "", session: false }
    }
    // Where a row's choice comes from, at the width of the widest of the
    // three (measured by a copy that is never drawn): the selects beside it
    // ended at different x, and moved when a row changed between them.
    function sourceLabel(source) {
        return source === "session" ? "This session" : source === "plasma" ? "From Plasma" : "System default"
    }
    readonly property real sourceWidth: Math.max(sessionProbe.implicitWidth, plasmaProbe.implicitWidth, systemProbe.implicitWidth)
    ShellText { id: sessionProbe; visible: false; role: "small"; text: root.sourceLabel("session") }
    ShellText { id: plasmaProbe; visible: false; role: "small"; text: root.sourceLabel("plasma") }
    ShellText { id: systemProbe; visible: false; role: "small"; text: root.sourceLabel("system") }

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
            model: ScriptModel { values: root.categoryIds }
            RowLayout {
                id: appRow
                required property string modelData
                readonly property var category: root.categoryById(modelData)
                Layout.fillWidth: true
                spacing: Metrics.spaceMd

                // Pinned to the row's first line, with the text and the reset
                // button below: an open select grows the row by its list, and
                // they slid down to the middle of it.
                ShellIcon {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: (Metrics.controlHeight - implicitHeight) / 2
                    glyph: root.icons[appRow.category.id] || Icons.apps
                    size: Metrics.iconMd
                    color: Colors.accentForeground
                }
                // The same label column every other settings row has; the
                // hotkey is the label's explanation, where the choice came
                // from is state and stays on the row.
                SettingRow {
                    Layout.fillWidth: true
                    label: appRow.category.label
                    hint: root.hints[appRow.category.id] || ""
                    ShellSelect {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: appRow.category.candidates.map(app => ({ value: app.id, label: app.name }))
                        current: appRow.category.current
                        placeholder: "Not set"
                        onSelected: value => { if (value !== appRow.category.current) DefaultAppsService.setDefault(appRow.category.id, value) }
                    }
                    ShellText {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: (Metrics.controlHeight - implicitHeight) / 2
                        Layout.preferredWidth: root.sourceWidth
                        horizontalAlignment: Text.AlignRight
                        text: root.sourceLabel(appRow.category.source)
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
                        enabledState: appRow.category.session
                        onClicked: DefaultAppsService.reset(appRow.category.id)
                    }
                }
            }
        }
    }
}
