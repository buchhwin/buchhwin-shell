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
    spacing: Metrics.pageGap

    property bool recording: false
    property var heldMods: []
    property var captured: null          // { mods, key }
    property string kind: "app"
    property string appId: ""
    // A shell action (ShortcutService.shellActions: the start menu), for
    // the third kind: the same IPC call a built-in shell bind makes.
    property string shellAction: ""
    property string error: ""
    property string query: ""
    // Which built-in shortcut is being moved, by the combination it sits on by
    // default. Empty means none - only ever one at a time, so the list stays a
    // list and does not grow two controls on every row.
    property string editingCombo: ""
    property string rowError: ""
    property var rowMods: []

    readonly property var groups: ShortcutService.grouped(query)
    // The list is keyed by strings - the groups by id, the rows by
    // ShortcutService.rowKeys - and each one reads its data from here. A
    // Repeater on the groups themselves built every group and every row still
    // shown again on each letter typed into the search (about 120 ms for 60
    // rows), and on every fresh read of the binds when the page opens.
    readonly property var groupById: {
        const table = {}
        for (const group of root.groups) table[group.id] = group
        return table
    }
    readonly property var appOptions: DesktopEntries.applications.values
        .filter(app => app && !app.noDisplay)
        .map(app => ({ value: app.id, label: app.name || app.id }))
        .sort((a, b) => a.label.localeCompare(b.label))
    readonly property bool ready: captured !== null && (kind === "app" ? appId.length > 0
        : kind === "shell" ? shellAction.length > 0 : commandField.text.trim().length > 0)

    PageActivity { onOpened: ShortcutService.refresh() }

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
            : kind === "shell" ? { mods: captured.mods, key: captured.key, shell: shellAction }
            : { mods: captured.mods, key: captured.key, command: commandField.text.trim() }
        error = ShortcutService.add(entry)
        if (error.length) return
        captured = null
        appId = ""
        shellAction = ""
        commandField.text = ""
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Custom shortcuts"
        description: "Start an app, run a command or open a part of the shell with your own key combination. They are saved in shortcuts.json and applied whenever the shell starts; the Hyprland config files stay unchanged."

        Repeater {
            model: ShortcutService.custom
            ListRow {
                interactive: false
                id: customRow
                required property var modelData
                readonly property string combo: ShortcutService.comboOf(modelData)
                readonly property bool conflict: ShortcutService.conflicts.indexOf(combo) >= 0
                Layout.fillWidth: true
                iconSource: ShortcutService.iconFor(modelData)
                icon: modelData.app ? Icons.apps : modelData.shell ? Icons.window : "󰆍"
                title: ShortcutService.labelFor(modelData)
                subtitle: conflict ? "Not active: the Hyprland config uses this combination too"
                    : modelData.app ? "App" : modelData.shell ? "Shell action" : "Command"
                RowLayout {
                    spacing: Metrics.spaceSm
                    KeyChips { keys: ShortcutService.keyParts(customRow.modelData) }
                    ShellIcon { visible: customRow.conflict; glyph: Icons.warning; size: Metrics.iconSm; color: Colors.warning }
                    // The combination and the command typed for it go with
                    // it, and nothing brings them back: it asks first.
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove"
                        confirm: true; confirmText: "Remove?"
                        onClicked: ShortcutService.remove(customRow.modelData)
                    }
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: ShortcutService.custom.length === 0
            row: true
            icon: "󰥻"
            title: "No shortcuts of your own yet"
        }

        Divider {}

        SettingRow {
            Layout.fillWidth: true
            label: "Keys"
            Rectangle {
                id: captureArea
                Layout.fillWidth: true
                implicitWidth: Metrics.thumbnailSize
                implicitHeight: Metrics.controlHeight
                radius: Metrics.radiusInner
                color: captureMouse.containsMouse && !root.recording ? Colors.surface1Hover : Colors.surface1
                border.width: root.recording ? Metrics.focusBorderWidth : Metrics.borderWidth
                border.color: root.recording ? Colors.accentLine : Colors.border
                activeFocusOnTab: true
                onActiveFocusChanged: if (!activeFocus) root.recording = false
                // The same ring every other control shows: the accent border
                // only says "recording", so a tab that landed here was invisible.
                FocusRing { active: captureArea.activeFocus && !root.recording; controlRadius: captureArea.radius }

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
                        // Words, so mutedText: subtleText is for marks.
                        color: root.recording ? Colors.accentForeground : Colors.mutedText
                    }
                    ShellButton {
                        focusOnTab: true
                        visible: root.captured !== null && !root.recording
                        icon: Icons.close; variant: "ghost"; compact: true; toolTip: "Clear"
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
                options: [{ value: "app", label: "Open an app", icon: Icons.apps }, { value: "command", label: "Run a command", icon: "󰆍" },
                          { value: "shell", label: "Shell action", icon: Icons.window }]
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
            visible: root.kind === "shell"
            label: "Opens"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: ShortcutService.shellActions
                current: root.shellAction
                placeholder: "Choose …"
                onSelected: value => { root.shellAction = value; if (!root.error.startsWith("Already")) root.error = "" }
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
                focusOnTab: true
                icon: Icons.add; text: "Add shortcut"; variant: "accent"
                enabledState: root.ready && root.error.length === 0
                onClicked: root.add()
            }
        }
    }

    // The keyboard passthrough (hypr/, services/hypr/PassthroughLogic.js) and
    // the Citrix session over the desk's screens: what a remote desktop needs
    // from the keys and the screens of this one.
    SettingsSection {
        Layout.fillWidth: true
        title: "Keyboard passthrough"
        description: "Every key goes to the window in front - Alt+Tab, the Windows key and " + ShortcutService.keyHint("SUPER + L", true)
            + " reach a Citrix session or a virtual machine instead of this desktop - until the same key again. Volume, brightness, media keys and the lid stay with this desktop; a chip in the corner says the keys are away."

        // The key caps at the right, where every key cap of the list above
        // stands.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Key"
            hint: "In and out again. A click on the chip, or another window taking the focus, gives the keys back too."
            KeyChips { keys: ShortcutService.keyHintParts("SUPER + Escape") }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "On by itself while Citrix is in full screen"
            hint: "Hand the keys over by itself while a Citrix session in full screen has the focus, and take them back when it leaves full screen or another window is in front."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("input.passthroughCitrix") === true
                onToggled: value => SettingsService.set("input.passthroughCitrix", value)
            }
        }
        SettingRow {
            id: spanRow
            Layout.fillWidth: true
            labelFills: true
            label: "Spread Citrix over the screens"
            // What the last try came to, said here as well as in the OSD.
            property string result: ""
            hint: (result.length ? result + ". " : "")
                + "Hyprland's full screen covers one screen. Start the session in a window, then spread it: it becomes a floating window as large as the external screens side by side, and the session fills it."
            Connections {
                target: HyprlandService
                function onSpanFinished(message, ok) { spanRow.result = message }
            }
            // A button that looks like one: a bare ghost word read as a
            // label. The display switcher's "Extend" glyph.
            ShellButton {
                focusOnTab: true
                icon: "\u{f037a}"
                text: "Spread"
                variant: "surface"
                onClicked: HyprlandService.spanCitrix()
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
            SettingRow {
                id: gestureRow
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumHeight: Metrics.controlHeight
                labelFills: true
                label: gestureRow.modelData.action
                ShellText { text: gestureRow.modelData.label; muted: true }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "All shortcuts"
        description: "Every key binding Hyprland currently knows, including your own."

        ShellTextField {
            focusOnTab: true
            // A search: text left in it keeps no page loaded (pendingEdits).
            property bool scratch: true
            Layout.fillWidth: true
            icon: Icons.search
            placeholder: "Search shortcuts …"
            busy: ShortcutService.loading
            onTextChanged: root.query = text
        }
        EmptyState {
            Layout.fillWidth: true
            visible: root.groups.length === 0
            row: true
            icon: ShortcutService.binds.length ? Icons.search : Icons.busy
            title: ShortcutService.binds.length ? "No shortcut matches" : "Loading …"
        }

        Repeater {
            model: ScriptModel { values: root.groups.map(group => group.id) }
            ColumnLayout {
                id: groupColumn
                required property string modelData
                // Gone in the same turn as its column: an empty one until then.
                readonly property var group: root.groupById[modelData] || ({ id: modelData, title: "", rows: [] })
                readonly property var keys: ShortcutService.rowKeys(group.rows)
                readonly property var rowByKey: {
                    const table = {}
                    keys.forEach((key, at) => table[key] = group.rows[at])
                    return table
                }
                Layout.fillWidth: true
                Layout.topMargin: Metrics.spaceXs
                spacing: Metrics.spaceXs

                SectionLabel { text: groupColumn.group.title }
                Repeater {
                    model: ScriptModel { values: groupColumn.keys }
                    RowLayout {
                        id: bindRow
                        required property string modelData
                        readonly property var entry: groupColumn.rowByKey[modelData]
                            || ({ modmask: 0, key: "", keys: [], combo: "", title: "", raw: false })
                        readonly property string defaultCombo: ShortcutService.defaultCombo(entry.modmask, entry.key)
                        readonly property bool movable: defaultCombo.length > 0
                        readonly property string movedFrom: ShortcutService.movedFrom(entry.modmask, entry.key)
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
                            text: bindRow.entry.title
                            font.family: bindRow.entry.raw ? Typography.monoFamily : Typography.family
                            color: bindRow.entry.raw ? Colors.mutedText : Colors.text
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
                            keys: bindRow.entry.keys
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
                            focusOnTab: true
                            visible: bindRow.editing && bindRow.movedFrom.length > 0
                            text: "Reset"; variant: "ghost"; compact: true
                            onClicked: { ShortcutService.resetKey(bindRow.defaultCombo); root.editingCombo = "" }
                        }
                        ShellButton {
                            visible: bindRow.movable
                            icon: bindRow.editing ? Icons.close : Icons.modify
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
