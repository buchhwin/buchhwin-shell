import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Terminal: Kitty appearance, Starship prompt with a live preview
// and the Fastfetch greeting. Applies to terminals started in this session.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var options: TerminalService.options
    readonly property var fontFamilies: {
        const seen = {}
        return Qt.fontFamilies().filter(name => !name.startsWith(".") && !seen[name] && (seen[name] = true))
            .map(name => ({ value: name, label: name }))
    }

    function set(key, value) { SettingsService.set("terminal." + key, value) }

    Component.onCompleted: TerminalService.pageOpen = true
    Component.onDestruction: TerminalService.pageOpen = false

    SettingsSection {
        Layout.fillWidth: true
        title: "Preview"
        description: "New Kitty windows use these settings; open windows update font, opacity and cursor right away."

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: previewLabel.implicitHeight + Metrics.spaceLg * 2
            radius: Metrics.radiusCard
            color: Colors.terminalBackground
            border.width: Metrics.borderWidth
            border.color: Colors.border

            Text {
                id: previewLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Metrics.spaceLg
                text: TerminalService.previewText.length ? TerminalService.previewText : TerminalService.previewError
                textFormat: TerminalService.previewText.length ? Text.RichText : Text.PlainText
                color: Colors.terminalForeground
                font.family: root.options.fontFamily
                font.pixelSize: Typography.bodyLargeSize
                wrapMode: Text.WrapAnywhere
                renderType: Typography.renderType
            }
        }

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show a Git repository in the preview"
            ShellToggle { checked: root.options.previewGit; onToggled: value => root.set("previewGit", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Fastfetch when a terminal opens"
            hint: "ff and fastfetch always work manually. Labels use the prompt color (the shell accent by default)."
            ShellToggle { focusOnTab: true; checked: root.options.fastfetchOnStart; onToggled: value => root.set("fastfetchOnStart", value) }
        }
        // Which logo, before anything about images. Choosing one used to be a
        // one-way door: the picker could set an image and nothing could take it
        // back short of a text editor.
        SettingRow {
            Layout.fillWidth: true
            label: "Logo"
            hint: "The distribution's own ASCII logo, or a picture of your own"
            SegmentedControl {
                Layout.fillWidth: true
                current: TerminalService.fastfetchLogo
                options: [{ value: "builtin", label: "Fedora logo" }, { value: "image", label: "Image" }]
                onSelected: value => {
                    if (value === "builtin") TerminalService.useBuiltinLogo()
                    else if (!TerminalService.fastfetchImage.length) TerminalService.chooseImage()
                }
            }
        }
        RowLayout {
            spacing: Metrics.spaceMd
            // An image picker beside an ASCII logo is a control that does
            // nothing, so it only appears once "Image" is the answer.
            visible: TerminalService.fastfetchLogo === "image"
            RoundedImage {
                Layout.preferredWidth: Metrics.thumbnailSize
                Layout.preferredHeight: Metrics.thumbnailSize
                visible: TerminalService.fastfetchImage.length > 0
                radius: Metrics.radiusInner
                source: TerminalService.fastfetchImage.length ? "file://" + TerminalService.fastfetchImage : ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: "Fastfetch image" }
                ShellText {
                    Layout.fillWidth: true
                    text: TerminalService.fastfetchError.length ? TerminalService.fastfetchError
                        : TerminalService.fastfetchImage.length ? TerminalService.fastfetchImage.split("/").pop() : "No image"
                    color: TerminalService.fastfetchError.length ? Colors.warning : Colors.mutedText
                    role: "caption"
                }
            }
            ShellButton {
                text: TerminalService.choosingImage ? "Choosing …" : "Choose image …"
                icon: "󰋩"
                compact: true
                enabledState: !TerminalService.choosingImage
                onClicked: TerminalService.chooseImage()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: TerminalService.fastfetchLogo === "image"
        title: "Fastfetch image size"
        description: "Width in terminal columns; the image keeps its proportions"

        SegmentedControl {
            Layout.fillWidth: true
            current: String(root.options.imageSize)
            options: [{ value: "20", label: "Small" }, { value: "30", label: "Medium" }, { value: "40", label: "Large" }]
            onSelected: value => root.set("imageSize", parseInt(value))
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Kitty"
        description: "Font, transparency, spacing and cursor"

        SettingRow {
            label: "Font"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: root.fontFamilies
                current: root.options.fontFamily
                previewFonts: true
                onSelected: value => root.set("fontFamily", value)
            }
        }
        SettingRow {
            label: "Font size"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 8; to: 20
                value: root.options.fontSize
                onReleased: value => root.set("fontSize", Math.round(value * 2) / 2)
            }
            ShellText { text: root.options.fontSize + " pt"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Opacity"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0.5; to: 1
                value: root.options.opacity
                onReleased: value => root.set("opacity", Math.round(value * 100) / 100)
            }
            ShellText { text: Math.round(root.options.opacity * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Padding"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 24
                value: root.options.padding
                onReleased: value => root.set("padding", Math.round(value))
            }
            ShellText { text: root.options.padding + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Cursor"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.options.cursorShape
                options: [{ value: "beam", label: "Beam" }, { value: "block", label: "Block" }, { value: "underline", label: "Underline" }]
                onSelected: value => root.set("cursorShape", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Blinking cursor"
            ShellToggle { focusOnTab: true; checked: root.options.cursorBlink; onToggled: value => root.set("cursorBlink", value) }
        }
        SettingRow {
            label: "Blink"
            hint: "Soft fades the cursor in and out instead of switching it on and off"
            visible: root.options.cursorBlink
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.options.cursorBlinkStyle
                options: [{ value: "soft", label: "Soft" }, { value: "hard", label: "Hard" }]
                onSelected: value => root.set("cursorBlinkStyle", value)
            }
        }
        SettingRow {
            label: "Trail"
            hint: "The cursor smears towards its new place; it takes the prompt color"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.options.cursorTrail
                options: [{ value: "off", label: "Off" }, { value: "short", label: "Short" }, { value: "long", label: "Long" }]
                onSelected: value => root.set("cursorTrail", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Prompt colors"
        description: "Starship prompt symbol, user and host; errors and Git changes"

        SectionLabel { text: "Accent" }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: ["shell"].concat(TerminalService.promptColors)
                Rectangle {
                    required property string modelData
                    readonly property bool active: root.options.promptColor.toLowerCase() === modelData
                    width: Metrics.controlHeight
                    height: width
                    radius: width / 2
                    color: modelData === "shell" ? Colors.accent : modelData
                    border.width: active ? Metrics.focusBorderWidth + 1 : 0
                    border.color: Colors.text
                    ShellIcon {
                        anchors.centerIn: parent
                        visible: parent.active || parent.modelData === "shell"
                        glyph: parent.active ? Icons.check : "󰏘"
                        size: Metrics.iconSm
                        color: Colors.textOn(parent.color)
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.set("promptColor", parent.modelData) }
                }
            }
        }
        SectionLabel { text: "Errors" }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: TerminalService.errorColors
                Rectangle {
                    required property string modelData
                    readonly property bool active: root.options.errorColor.toLowerCase() === modelData
                    width: Metrics.controlHeight
                    height: width
                    radius: width / 2
                    color: modelData
                    border.width: active ? Metrics.focusBorderWidth + 1 : 0
                    border.color: Colors.text
                    ShellIcon { anchors.centerIn: parent; visible: parent.active; glyph: Icons.check; size: Metrics.iconSm; color: Colors.textOn(parent.color) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.set("errorColor", parent.modelData) }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Symbols"
        description: "Press Enter to apply (up to 32 characters)"

        Repeater {
            model: [{ key: "symbol", label: "Prompt" }, { key: "errorSymbol", label: "Error" }, { key: "gitSymbol", label: "Git" }]
            SettingRow {
                id: symbolRow
                required property var modelData
                label: modelData.label
                ShellTextField {
                    focusOnTab: true
                    id: symbolField
                    Layout.fillWidth: true
                    text: root.options[symbolRow.modelData.key]
                    onAccepted: root.set(symbolRow.modelData.key, text)
                }
                ShellButton {
                    focusOnTab: true
                    icon: Icons.check
                    compact: true
                    variant: "ghost"
                    enabledState: symbolField.text !== root.options[symbolRow.modelData.key]
                    onClicked: root.set(symbolRow.modelData.key, symbolField.text)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Modules"
        description: "What the prompt shows, in this order"

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Metrics.spaceXl
            rowSpacing: Metrics.spaceSm
            Repeater {
                model: TerminalService.modules.concat([{ key: "twoLine", label: "Two-line prompt" }, { key: "newline", label: "Blank line between prompts" }])
                RowLayout {
                    id: moduleRow
                    required property var modelData
                    Layout.fillWidth: true
                    ShellText { Layout.fillWidth: true; text: moduleRow.modelData.label }
                    ShellToggle { checked: root.options[moduleRow.modelData.key]; onToggled: value => root.set(moduleRow.modelData.key, value) }
                }
            }
        }
        SettingRow {
            label: "Directory depth"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 1; to: 10
                value: root.options.directoryDepth
                onReleased: value => root.set("directoryDepth", Math.round(value))
            }
            ShellText { text: String(root.options.directoryDepth); role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Show duration after"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 100; to: 10000
                value: root.options.durationMin
                onReleased: value => root.set("durationMin", Math.round(value / 100) * 100)
            }
            ShellText { text: (root.options.durationMin / 1000).toFixed(1) + " s"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Clock format"
        description: "Used when the clock module is on. %H hour, %M minute, %S second, %p AM/PM, %d day, %m month"

        SegmentedControl {
            Layout.fillWidth: true
            current: root.options.timeFormat
            options: TerminalService.timeFormats
            onSelected: value => root.set("timeFormat", value)
        }
        SettingRow {
            label: "Custom"
            ShellTextField {
                focusOnTab: true
                id: timeField
                Layout.fillWidth: true
                text: root.options.timeFormat
                onAccepted: root.set("timeFormat", text)
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.check
                compact: true
                variant: "ghost"
                enabledState: timeField.text !== root.options.timeFormat
                onClicked: root.set("timeFormat", timeField.text)
            }
        }
    }
}
