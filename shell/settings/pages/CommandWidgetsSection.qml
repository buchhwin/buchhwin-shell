import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/widgets/CommandLogic.js" as Logic

// Settings > Widgets: the three command widgets ("Command 1" to "Command 3"
// in every widget picker). Each one is a command whose first line the widget
// shows, how often it runs, a glyph, a name and a command for a click
// (CommandLogic, CommandWidgetService). A command runs only while a widget of
// its own is placed and shown; "Run now" tries it from here.
SettingsSection {
    id: section
    title: "Command widgets"
    description: "Show what a command of your own prints - a VPN check, a build's state, a counter - in the bar, the notch, on the desktop or in the dashboard. Add them as Command 1 to 3 like any widget; a command that fails shows its glyph in the warning colour."
    scope: "commandWidgets.one.command"

    readonly property var intervalOptions: Logic.INTERVALS.map(seconds => ({
        value: String(seconds),
        label: seconds < 60 ? seconds + " seconds" : seconds < 3600 ? (seconds / 60) + (seconds === 60 ? " minute" : " minutes") : "1 hour"
    }))

    Repeater {
        model: Logic.SLOTS
        ColumnLayout {
            id: slotBlock
            required property string modelData
            required property int index
            readonly property string prefix: "commandWidgets." + modelData + "."
            readonly property var definition: CommandWidgetService.definition(modelData)
            readonly property var result: CommandWidgetService.results[modelData] || null
            readonly property string typed: commandField.text
            // A slot without a command is its Command field alone: three
            // slots of five rows each were fifteen rows, used or not.
            readonly property bool set: definition.command.length > 0
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            function store(leaf, value) { SettingsService.set(slotBlock.prefix + leaf, value) }

            SectionLabel {
                Layout.fillWidth: true
                Layout.topMargin: slotBlock.index > 0 ? Metrics.spaceMd : 0
                text: "Command " + (slotBlock.index + 1) + (slotBlock.definition.label.length ? " · " + slotBlock.definition.label : "")
            }
            SettingRow {
                Layout.fillWidth: true
                label: "Command"
                hint: Logic.commandError(slotBlock.typed) || "Clear it and press Enter to remove it"
                StoredTextField {
                    id: commandField
                    focusOnTab: true
                    Layout.fillWidth: true
                    icon: "\u{f018d}"
                    placeholder: "e.g. nmcli -t -f NAME connection show --active"
                    error: Logic.commandError(text).length > 0
                    storedText: SettingsService.value(slotBlock.prefix + "command") || ""
                    onCommit: value => { if (!Logic.commandError(value)) slotBlock.store("command", value.trim()) }
                }
            }
            SettingRow {
                Layout.fillWidth: true
                visible: slotBlock.set
                label: "Every"
                ShellSelect {
                    focusOnTab: true
                    Layout.fillWidth: true
                    options: section.intervalOptions
                    current: String(slotBlock.definition.interval)
                    onSelected: value => slotBlock.store("interval", parseInt(value))
                }
            }
            SettingRow {
                Layout.fillWidth: true
                visible: slotBlock.set
                label: "Name"
                hint: "Shown beside the value in a medium or large widget"
                StoredTextField {
                    focusOnTab: true
                    Layout.fillWidth: true
                    placeholder: "Command " + (slotBlock.index + 1)
                    storedText: SettingsService.value(slotBlock.prefix + "label") || ""
                    onCommit: value => slotBlock.store("label", value.trim())
                }
            }
            SettingRow {
                Layout.fillWidth: true
                visible: slotBlock.set
                label: "Glyph"
                hint: "One Nerd Font icon; empty is a console"
                StoredTextField {
                    focusOnTab: true
                    Layout.fillWidth: true
                    icon: slotBlock.definition.icon
                    storedText: SettingsService.value(slotBlock.prefix + "icon") || ""
                    onCommit: value => slotBlock.store("icon", value.trim())
                }
            }
            SettingRow {
                Layout.fillWidth: true
                visible: slotBlock.set
                label: "On click"
                hint: "Started like an app. Without one, a click runs the command again."
                StoredTextField {
                    focusOnTab: true
                    Layout.fillWidth: true
                    placeholder: "e.g. nm-connection-editor"
                    error: Logic.commandError(text).length > 0
                    storedText: SettingsService.value(slotBlock.prefix + "click") || ""
                    onCommit: value => { if (!Logic.commandError(value)) slotBlock.store("click", value.trim()) }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: slotBlock.definition.command.length > 0
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    icon: Icons.refresh
                    text: "Run now"
                    compact: true
                    onClicked: CommandWidgetService.runNow(slotBlock.modelData)
                }
                ShellText {
                    Layout.fillWidth: true
                    text: !slotBlock.result ? "" : slotBlock.result.failed
                        ? Logic.failureText(slotBlock.result) + (slotBlock.result.line.length ? ": " + slotBlock.result.line : "")
                        : slotBlock.result.line.length ? slotBlock.result.line : "No output"
                    role: "small"
                    color: slotBlock.result && slotBlock.result.failed ? Colors.warning : Colors.mutedText
                    elide: Text.ElideRight
                }
            }
        }
    }
}
