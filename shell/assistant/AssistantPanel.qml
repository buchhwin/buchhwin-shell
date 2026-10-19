import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/assistant/AssistantLogic.js" as Logic

// The assistant: a chat with a language model that runs on this computer,
// through Ollama (services/AssistantService.qml). In the corner, the height
// of the screen, like the notification centre; built on its first open
// (PanelService.lazyPanels) and costing nothing before.
//
// Enter asks, Up in an empty field brings the last question back, Escape
// closes (a reply being written goes on, and is there when the panel opens
// again). Without Ollama, or without a model, the panel says what to do.
ShellPanel {
    id: root
    panelId: "assistant"
    placement: "top-right"
    // The corner, always: in notch mode the clock is the middle of the screen.
    followClock: false
    cardWidth: Metrics.compactWidth
    cardHeight: roomBelowTop
    keyForward: ready ? field : null
    onKeyForwardChanged: if (wanted && keyForward) Qt.callLater(focusEntry)

    readonly property string status: AssistantService.status
    readonly property bool ready: status === "ready"
    readonly property var said: Logic.stateText(status, AssistantService.installed, DistroService.installHint("ollama"),
                                                AssistantService.skipped, DistroService.installCommand("ollama"))
    readonly property var byId: {
        const index = {}
        for (const message of AssistantService.messages) index[message.id] = message
        return index
    }
    readonly property bool talking: AssistantService.messages.length > 0 || AssistantService.busy

    onWantedChanged: {
        AssistantService.watch(wanted)
        if (wanted) Qt.callLater(list.toEnd)
    }
    Component.onDestruction: if (wanted) AssistantService.watch(false)

    function ask() {
        const text = field.text
        if (!text.trim().length) return
        if (AssistantService.send(text)) {
            lastAsked = text
            field.text = ""
            list.following = true
        }
    }
    property string lastAsked: ""

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            title: "Assistant"
            // The model by name while there is only one; with more, the
            // select under the header names it. Nothing while the empty
            // state below says what is missing.
            subtitle: !root.ready ? ""
                : AssistantService.models.length > 1 || !AssistantService.current ? "On this computer, through Ollama"
                : AssistantService.current.label + " · on this computer"
            wrap: false

            // Tab reaches it, and the answers' copy buttons: after a question
            // the keyboard could only type, go up and close.
            ShellButton {
                visible: root.talking
                focusOnTab: true
                icon: Icons.add
                text: "New chat"
                compact: true
                variant: "ghost"
                onClicked: {
                    AssistantService.clear()
                    root.focusEntry()
                }
            }
        }

        // Which model answers, while there is more than one to choose from.
        // The choice is Settings' (assistant.model), the same in both places.
        ShellSelect {
            Layout.fillWidth: true
            visible: root.ready && AssistantService.models.length > 1
            focusOnTab: true
            accessibleName: "Model"
            options: AssistantService.models.map(entry => ({ value: entry.name, label: entry.label }))
            current: AssistantService.model
            listHeight: Metrics.popupListHeight
            onSelected: value => SettingsService.set("assistant.model", value)
        }

        // Without Ollama, a model or a local address: what to do about it.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.ready && !root.talking

            // What is the matter, the commands for it (a block each, to copy
            // into a terminal) and the buttons under them.
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Metrics.spaceLg * 2
                spacing: Metrics.spaceMd

                EmptyState {
                    Layout.fillWidth: true
                    icon: root.status === "checking" || root.status === "unknown" ? Icons.busy : Icons.assistant
                    title: root.said.title
                    description: root.said.description
                }
                Repeater {
                    model: root.said.steps
                    CommandBlock {
                        required property string modelData
                        Layout.fillWidth: true
                        command: modelData
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.status === "offline" || root.status === "noModels" || root.status === "refused"
                    spacing: Metrics.spaceSm
                    ShellButton {
                        visible: root.status !== "refused"
                        focusOnTab: true
                        icon: Icons.refresh
                        text: "Check again"
                        onClicked: AssistantService.refresh()
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.settings
                        text: "Settings"
                        variant: "ghost"
                        onClicked: PanelService.open("settings", { page: "desktop", section: "Assistant" })
                    }
                }
            }
        }

        // The conversation.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.ready || root.talking

            EmptyState {
                anchors.centerIn: parent
                width: parent.width - Metrics.spaceLg * 2
                visible: !root.talking
                icon: Icons.assistant
                title: "Ask anything"
                description: "The model runs on this computer. Nothing you ask leaves it"
                    + (AssistantService.keepHistory ? "" : ", and nothing is kept once the shell ends")
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: root.talking
                clip: true
                spacing: Metrics.spaceMd
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: AssistantService.messageIds }
                ScrollFeel { view: list }

                // Down with the answer as it is written, unless the user
                // scrolled up to read something.
                property bool following: true
                property bool scrolling: false
                function toEnd() {
                    scrolling = true
                    contentY = originY + Math.max(0, contentHeight - height)
                    scrolling = false
                }
                onContentYChanged: if (!scrolling) following = atYEnd
                onContentHeightChanged: if (following) Qt.callLater(toEnd)

                delegate: AssistantMessage {
                    required property string modelData
                    readonly property var message: root.byId[modelData] || null
                    width: ListView.view.width
                    role: message ? message.role : "assistant"
                    content: message ? message.content : ""
                    answeredBy: message ? message.model : ""
                    stopped: message ? message.stopped === true : false
                }
                footer: Item {
                    width: list.width
                    height: AssistantService.busy ? writing.height + Metrics.spaceMd : 0
                    AssistantMessage {
                        id: writing
                        y: Metrics.spaceMd
                        width: parent.width
                        visible: AssistantService.busy
                        streaming: true
                        role: "assistant"
                        content: AssistantService.streamText
                    }
                }
            }
        }

        // What happened to the last question, when something did.
        ShellText {
            Layout.fillWidth: true
            visible: AssistantService.error.length > 0 || (AssistantService.busy && !AssistantService.streamText.length)
            text: AssistantService.error.length ? AssistantService.error
                : AssistantService.thinking ? "Thinking …" : "Waiting for the model … (it loads with the first question)"
            role: "small"
            color: AssistantService.error.length ? Colors.warning : Colors.mutedText
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.ready || root.talking
            spacing: Metrics.spaceSm

            ShellTextField {
                id: field
                Layout.fillWidth: true
                icon: Icons.assistant
                placeholder: AssistantService.busy ? "Writing …" : "Ask …"
                enabledState: root.ready
                onAccepted: root.ask()
                onEscapePressed: root.requestClose()
                onKeyPressed: event => {
                    if (event.key === Qt.Key_Up && !field.text.length && root.lastAsked.length) {
                        field.text = root.lastAsked
                        event.accepted = true
                    }
                }
            }
            ShellButton {
                icon: AssistantService.busy ? Icons.stop : Icons.send
                toolTip: AssistantService.busy ? "Stop" : "Ask"
                variant: AssistantService.busy ? "surface" : "accent"
                enabledState: AssistantService.busy || (root.ready && field.text.trim().length > 0)
                onClicked: AssistantService.busy ? AssistantService.stop() : root.ask()
            }
        }

        ShellText {
            Layout.fillWidth: true
            text: AssistantService.keepHistory ? "On this computer · kept in a file only you can read"
                : "On this computer · not kept"
            role: "caption"
        }
    }
}
