import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Shortcuts: own shortcuts (record a combination, pick an app or
// type a command) and a searchable list of every binding Hyprland knows.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    property bool recording: false
    property var heldMods: []
    property var captured: null          // { mods, key }
    property string kind: "app"
    property string appId: ""
    property string error: ""
    property string query: ""
    // Which built-in shortcut is being moved, by the combination it sits on by
    // default. Empty means none - only ever one at a time, so the list stays a
    // list and does not grow two controls on every row.
    property string editingCombo: ""
    property string rowError: ""
    property var rowMods: []

    readonly property var groups: ShortcutService.grouped(query)
    readonly property var appOptions: DesktopEntries.applications.values
        .filter(app => app && !app.noDisplay)
        .map(app => ({ value: app.id, label: app.name || app.id }))
        .sort((a, b) => a.label.localeCompare(b.label))
    readonly property bool ready: captured !== null && (kind === "app" ? appId.length > 0 : commandField.text.trim().length > 0)

    Component.onCompleted: ShortcutService.refresh()

    function startRecording() {
        recording = true
        heldMods = []
        error = ""
        captureArea.forceActiveFocus()
    }

    function capture(event) {
        const result = ShortcutService.captureKey(event.key, event.modifiers, event.nativeScanCode)
        if (result.cancel) { recording = false; return }
        if (result.waiting) { heldMods = result.mods; return }
        if (result.unsupported) { error = "This key cannot be used"; return }
        recording = false
        captured = { mods: result.mods, key: result.key }
        const used = ShortcutService.usedBy(result.mods, result.key)
        error = ShortcutService.comboError(result.mods, result.key) || (used ? "Already used by " + used : "")
    }

    // Moving a built-in. The combination it started on is the identity,
    // because a Lua configuration hides what a binding does and four of them
    // are called "Resize window".
    function startMove(defaultCombo) {
        editingCombo = defaultCombo
        rowMods = []
        rowError = ""
    }
    function captureMove(event) {
        const result = ShortcutService.captureKey(event.key, event.modifiers, event.nativeScanCode)
        if (result.cancel) { editingCombo = ""; return }
        if (result.waiting) { rowMods = result.mods; return }
        if (result.unsupported) { rowError = "This key cannot be used"; return }
        const combo = result.mods.concat([result.key]).join(" + ").toUpperCase()
        const problem = ShortcutService.setKey(editingCombo, combo)
        if (problem) { rowError = problem; rowMods = []; return }
        editingCombo = ""
    }

    function add() {
        if (!ready) return
        const entry = kind === "app" ? { mods: captured.mods, key: captured.key, app: appId }
                                     : { mods: captured.mods, key: captured.key, command: commandField.text.trim() }
        error = ShortcutService.add(entry)
        if (error.length) return
        captured = null
        appId = ""
        commandField.text = ""
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Custom shortcuts"
        description: "Start an app or run a command with your own key combination. They are saved in shortcuts.json and applied whenever the shell starts; the Hyprland config files stay unchanged."

        Repeater {
            model: ShortcutService.custom
            ListRow {
                id: customRow
                required property var modelData
                readonly property string combo: ShortcutService.comboOf(modelData)
                readonly property bool conflict: ShortcutService.conflicts.indexOf(combo) >= 0
                Layout.fillWidth: true
                iconSource: ShortcutService.iconFor(modelData)
                icon: modelData.app ? "󰀻" : "󰆍"
                title: ShortcutService.labelFor(modelData)
                subtitle: conflict ? "Not active: the Hyprland config uses this combination too"
                    : modelData.app ? "App" : "Command"
                RowLayout {
                    spacing: Metrics.spaceSm
                    KeyChips { keys: ShortcutService.keyParts(customRow.modelData) }
                    ShellIcon { visible: customRow.conflict; glyph: Icons.warning; size: Metrics.iconSm; color: Colors.warning }
                    ShellButton {
                        icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove"
                        onClicked: ShortcutService.remove(customRow.modelData)
                    }
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: ShortcutService.custom.length === 0
            icon: "󰥻"
            title: "No shortcuts of your own yet"
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: Metrics.borderWidth; color: Colors.border }

        SettingRow {
            Layout.fillWidth: true
            label: "Keys"
            Rectangle {
                id: captureArea
                Layout.fillWidth: true
                implicitWidth: Metrics.thumbnailSize
                implicitHeight: Metrics.controlHeight
                radius: Metrics.radiusInner
                color: captureMouse.containsMouse && !root.recording ? Colors.elevatedSurface : Colors.surface
                border.width: root.recording ? Metrics.focusBorderWidth : Metrics.borderWidth
                border.color: root.recording ? Colors.accent : Colors.border
                activeFocusOnTab: true
                onActiveFocusChanged: if (!activeFocus) root.recording = false

                Keys.onPressed: event => {
                    event.accepted = true
                    if (root.recording) root.capture(event)
                    else if (event.key === Qt.Key_Escape) PanelService.close("settings")
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.startRecording()
                    else event.accepted = false
                }

                RowLayout {
                    id: captureRow
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.spaceMd
                    anchors.rightMargin: Metrics.spaceSm
                    spacing: Metrics.spaceSm
                    ShellIcon { glyph: "󰌌"; size: Metrics.iconSm; color: root.recording ? Colors.accentForeground : Colors.mutedText }
                    KeyChips {
                        visible: root.recording ? root.heldMods.length > 0 : root.captured !== null
                        accent: root.recording
                        keys: root.recording ? root.heldMods.map(mod => mod.charAt(0) + mod.slice(1).toLowerCase())
                            : root.captured ? ShortcutService.keyParts(root.captured) : []
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: root.recording ? (root.heldMods.length ? "…" : "Press a key combination · Esc cancels")
                            : root.captured ? "" : "Click and press a key combination"
                        color: root.recording ? Colors.accentForeground : Colors.subtleText
                    }
                    ShellButton {
                        visible: root.captured !== null && !root.recording
                        icon: Icons.close; variant: "ghost"; compact: true
                        onClicked: { root.captured = null; root.error = "" }
                    }
                }
                MouseArea {
                    id: captureMouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startRecording()
                }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Action"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.kind
                options: [{ value: "app", label: "Open an app", icon: "󰀻" }, { value: "command", label: "Run a command", icon: "󰆍" }]
                onSelected: value => { root.kind = value; root.error = "" }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            visible: root.kind === "app"
            label: "App"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: root.appOptions
                current: root.appId
                placeholder: "Choose an app …"
                filterable: true
                onSelected: value => root.appId = value
            }
        }
        SettingRow {
            Layout.fillWidth: true
            visible: root.kind === "command"
            label: "Command"
            hint: "Runs with sh"
            ShellTextField {
                focusOnTab: true
                id: commandField
                Layout.fillWidth: true
                icon: "󰆍"
                placeholder: "e.g. firefox --private-window"
                onAccepted: root.add()
                onTextChanged: if (root.error.length && !root.error.startsWith("Already")) root.error = ""
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd
            ShellText {
                Layout.fillWidth: true
                text: root.error.length ? root.error : ShortcutService.message
                visible: text.length > 0
                role: "small"
                color: root.error.length || ShortcutService.messageError ? Colors.danger : Colors.mutedText
                wrapMode: Text.Wrap
            }
            Item { Layout.fillWidth: true; visible: !root.error.length && !ShortcutService.message.length }
            ShellButton {
                icon: Icons.add; text: "Add shortcut"; variant: "accent"
                enabledState: root.ready && root.error.length === 0
                onClicked: root.add()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: GestureService.touchpadShown
        title: "Touchpad gestures"
        description: GestureService.rows.length ? "Change them in Settings > Input." : "Off. Turn them on in Settings > Input."

        Repeater {
            model: GestureService.rows
            RowLayout {
                id: gestureRow
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumHeight: Metrics.controlHeight
                spacing: Metrics.spaceMd
                ShellText { Layout.fillWidth: true; text: gestureRow.modelData.action }
                ShellText { text: gestureRow.modelData.label; muted: true }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "All shortcuts"
        description: "Every key binding Hyprland currently knows, including your own."

        ShellTextField {
            Layout.fillWidth: true
            icon: Icons.search
            placeholder: "Search shortcuts …"
            busy: ShortcutService.loading
            onTextChanged: root.query = text
        }
        EmptyState {
            Layout.fillWidth: true
            visible: root.groups.length === 0
            icon: ShortcutService.binds.length ? Icons.search : Icons.busy
            title: ShortcutService.binds.length ? "No shortcut matches" : "Loading …"
        }

        Repeater {
            model: root.groups
            ColumnLayout {
                id: groupColumn
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: Metrics.spaceXs
                spacing: Metrics.spaceXs

                SectionLabel { text: groupColumn.modelData.title }
                Repeater {
                    model: groupColumn.modelData.rows
                    RowLayout {
                        id: bindRow
                        required property var modelData
                        readonly property string defaultCombo: ShortcutService.defaultCombo(modelData.modmask, modelData.key)
                        readonly property bool movable: defaultCombo.length > 0
                        readonly property string movedFrom: ShortcutService.movedFrom(modelData.modmask, modelData.key)
                        // Both empty compare equal, and the rows that stand
                        // for nine bindings at once ("Go to workspace 1-9")
                        // have no single combination - so they all showed
                        // themselves as the one being edited.
                        readonly property bool editing: defaultCombo.length > 0 && root.editingCombo === defaultCombo
                        Layout.fillWidth: true
                        Layout.minimumHeight: Metrics.controlHeight
                        spacing: Metrics.spaceMd

                        // The row takes the keys while it is the one being
                        // moved; the page's own capture area belongs to the
                        // form above and must not fight it.
                        focus: bindRow.editing
                        Keys.onPressed: event => {
                            if (!bindRow.editing) return
                            event.accepted = true
                            root.captureMove(event)
                        }
                        onFocusChanged: if (focus) forceActiveFocus()
                        ShellText {
                            Layout.fillWidth: true
                            text: bindRow.modelData.title
                            font.family: bindRow.modelData.raw ? Typography.monoFamily : Typography.family
                            color: bindRow.modelData.raw ? Colors.mutedText : Colors.text
                        }
                        // What a moved shortcut started on, so the list says
                        // so instead of quietly reading differently than the
                        // documentation does.
                        ShellText {
                            visible: bindRow.movedFrom.length > 0 && !bindRow.editing
                            text: "was " + bindRow.movedFrom
                            role: "small"; muted: true
                        }
                        KeyChips {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !bindRow.editing
                            keys: bindRow.modelData.keys
                        }

                        // While one is being moved the row becomes its editor,
                        // so nothing but a single quiet button is permanent.
                        ShellText {
                            visible: bindRow.editing
                            text: root.rowError.length ? root.rowError
                                : root.rowMods.length ? "…" : "Press a key combination · Esc cancels"
                            role: "small"
                            color: root.rowError.length ? Colors.danger : Colors.accentForeground
                        }
                        KeyChips {
                            visible: bindRow.editing && root.rowMods.length > 0
                            accent: true
                            keys: root.rowMods.map(mod => mod.charAt(0) + mod.slice(1).toLowerCase())
                        }
                        ShellButton {
                            visible: bindRow.editing && bindRow.movedFrom.length > 0
                            text: "Reset"; variant: "ghost"; compact: true
                            onClicked: { ShortcutService.resetKey(bindRow.defaultCombo); root.editingCombo = "" }
                        }
                        ShellButton {
                            visible: bindRow.movable
                            icon: bindRow.editing ? Icons.close : Icons.edit
                            toolTip: bindRow.editing ? "Cancel" : "Move this shortcut"
                            variant: "ghost"; compact: true; focusOnTab: true
                            onClicked: {
                                if (bindRow.editing) root.editingCombo = ""
                                else root.startMove(bindRow.defaultCombo)
                            }
                        }
                    }
                }
            }
        }
    }
}
