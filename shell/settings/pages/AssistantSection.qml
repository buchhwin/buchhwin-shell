import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/assistant/AssistantLogic.js" as Logic

// Settings > Desktop extras > Assistant (shell/assistant/AssistantPanel.qml):
// where Ollama listens, which model answers and whether the conversation is
// kept. Ollama is asked for its models while this section is on screen, and
// at no other time but while the panel is open.
SettingsSection {
    id: section
    title: "Assistant"
    scope: "assistant.url"
    hint: "A chat with a language model that runs on this computer, through Ollama. Nothing goes to the internet: no cloud model, no account, no key."

    readonly property string status: AssistantService.status
    readonly property var said: Logic.stateText(status, AssistantService.installed, DistroService.installHint("ollama"),
                                                AssistantService.skipped, DistroService.installCommand("ollama"))

    PageActivity {
        onOpened: AssistantService.watch(true)
        onClosed: AssistantService.watch(false)
    }

    ShellText {
        Layout.fillWidth: true
        text: section.status === "ready"
            ? "Ollama is running · " + AssistantService.models.length + (AssistantService.models.length === 1 ? " model" : " models")
                + (AssistantService.skipped > 0 ? " · cloud models left out" : "")
            : section.said.title + (section.said.description.length ? ". " + section.said.description : "")
        role: "small"
        color: section.status === "ready" || section.status === "checking" || section.status === "unknown"
            ? Colors.mutedText : Colors.warning
        wrapMode: Text.Wrap
    }
    // The steps as the panel shows them: commands to copy, not prose.
    Repeater {
        model: section.status === "ready" ? [] : section.said.steps
        CommandBlock {
            required property string modelData
            Layout.fillWidth: true
            command: modelData
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Address"
        hint: "On this computer only: 127.0.0.1, localhost or ::1, with Ollama's port. Clear it and press Enter for the default"
        StoredTextField {
            focusOnTab: true
            Layout.fillWidth: true
            icon: Icons.assistant
            placeholder: Logic.DEFAULT_URL
            error: text.trim().length > 0 && Logic.endpoint(text).length === 0
            storedText: SettingsService.value("assistant.url") || ""
            onCommit: value => {
                const address = Logic.endpoint(value)
                if (address.length) SettingsService.set("assistant.url", address)
            }
        }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Model"
        hint: AssistantService.models.length ? "" : "Pull one in a terminal, for example: ollama pull llama3.2"
        ShellSelect {
            focusOnTab: true
            Layout.fillWidth: true
            accessibleName: "Model"
            enabledState: AssistantService.models.length > 0
            options: [{ value: "", label: "The first one Ollama has" }]
                .concat(AssistantService.models.map(entry => ({ value: entry.name, label: entry.label })))
            current: SettingsService.value("assistant.model") || ""
            listHeight: Metrics.popupListHeight
            onSelected: value => SettingsService.set("assistant.model", value)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        labelFills: true
        label: "Keep the conversation"
        hint: "Across restarts, in a file only you can read (assistant-history.json in the shell's state folder). Off deletes it"
        ShellToggle {
            focusOnTab: true
            accessibleName: "Keep the conversation"
            checked: SettingsService.value("assistant.keepHistory") === true
            onToggled: value => SettingsService.set("assistant.keepHistory", value)
        }
    }
    RowLayout {
        spacing: Metrics.spaceSm
        ShellButton {
            focusOnTab: true
            icon: Icons.assistant
            text: "Open assistant"
            onClicked: PanelService.open("assistant")
        }
        ShellButton {
            focusOnTab: true
            icon: Icons.refresh
            text: "Check again"
            variant: "ghost"
            onClicked: AssistantService.refresh()
        }
    }
}
