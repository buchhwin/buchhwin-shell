import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/settings/SwatchLogic.js" as Swatch
import "../../../services/wallpaper/WallpaperLogic.js" as WallpaperLogic

// Settings > Terminal: kitty appearance, Starship prompt with a live preview
// and the Fastfetch greeting. Which terminal opens - for Super+Enter, the
// shell's own terminals (updates, the cursor install) and the launcher's
// terminal apps - is Settings > Default apps' choice, kitty when nothing is
// chosen (scripts/launch-terminal.sh). kitty takes everything here; Alacritty
// keeps its own configuration and takes only the opacity
// (scripts/launch-alacritty.sh).
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    readonly property var options: TerminalService.options
    readonly property var fontFamilies: {
        const seen = {}
        return Qt.fontFamilies().filter(name => !name.startsWith(".") && !seen[name] && (seen[name] = true))
            .map(name => ({ value: name, label: name }))
    }

    function set(key, value) { SettingsService.set("terminal." + key, value) }

    PageActivity {
        onOpened: TerminalService.pageOpen = true
        onClosed: TerminalService.pageOpen = false
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Shell"
        description: "Which zsh configuration kitty starts with"
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use my own zsh configuration"
            hint: "kitty then reads ~/.zshrc, like terminals outside this session, and the prompt settings below no longer apply. "
                + "To keep fastfetch, cmatrix and cava in the shell accent, add to it: source ~/.config/buchhwin-shell/shell.zsh"
            ShellToggle { focusOnTab: true; checked: root.options.personalShell; onToggled: value => root.set("personalShell", value) }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Preview"
        description: "New kitty windows use these settings; open windows update font, transparency and cursor right away."

        // The Starship preview, the Git sample and the greeting are the
        // session's own zsh; with the account's ~/.zshrc they say nothing.
        Rectangle {
            Layout.fillWidth: true
            visible: !root.options.personalShell
            implicitHeight: previewLabel.implicitHeight + Metrics.spaceLg * 2
            radius: Metrics.radiusCard
            color: Colors.terminalBackground
            border.width: Metrics.borderWidth
            border.color: Colors.border

            ShellText {
                id: previewLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Metrics.spaceLg
                role: "bodyLarge"
                text: TerminalService.previewText.length ? TerminalService.previewText : TerminalService.previewError
                textFormat: TerminalService.previewText.length ? Text.RichText : Text.PlainText
                // The terminal's own colours and font: this is a preview of
                // kitty, not a line of the shell's text.
                color: Colors.terminalForeground
                font.family: root.options.fontFamily
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideNone
            }
        }

        SettingRow {
            Layout.fillWidth: true
            visible: !root.options.personalShell
            labelFills: true
            label: "Show a Git repository in the preview"
            ShellToggle { focusOnTab: true; checked: root.options.previewGit; onToggled: value => root.set("previewGit", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            visible: !root.options.personalShell
            labelFills: true
            label: "Fastfetch when a terminal opens"
            hint: "ff and fastfetch always work manually. Labels use the prompt color (the shell accent by default)."
            ShellToggle { focusOnTab: true; checked: root.options.fastfetchOnStart; onToggled: value => root.set("fastfetchOnStart", value) }
        }
        // Which logo, before anything about images. Choosing one used to be a
        // one-way door: the picker could set an image and nothing could take it
        // back short of a text editor.
        //
        // A text logo of one's own (the buchhwin profile's Saturn) is a third
        // answer, offered only while it is the one in use: nothing here makes
        // one. It used to read as "Image" with an empty thumbnail, and "System
        // logo" took it out of fastfetch.jsonc without a word; now that asks.
        SettingRow {
            Layout.fillWidth: true
            label: "Logo"
            hint: "The distribution's own ASCII logo, or a picture of your own"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: TerminalService.fastfetchLogo
                options: [{ value: "builtin", label: "System logo" }]
                    .concat(TerminalService.fastfetchLogo === "text" ? [{ value: "text", label: "Text logo" }] : [])
                    .concat([{ value: "image", label: "Image" }])
                onSelected: value => {
                    logoRow.replacing = false
                    if (value === "builtin" && TerminalService.fastfetchLogo === "text") logoRow.replacing = true
                    else if (value === "builtin") TerminalService.useBuiltinLogo()
                    else if (value === "image" && !TerminalService.fastfetchImage.length) { PanelService.close(); TerminalService.chooseImage() }
                }
            }
        }
        // The text logo in use, and the question before it goes.
        RowLayout {
            id: logoRow
            property bool replacing: false
            readonly property string fileName: TerminalService.fastfetchTextLogo.split("/").pop()
            Layout.fillWidth: true
            visible: TerminalService.fastfetchLogo === "text"
            spacing: Metrics.spaceMd
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: "Fastfetch text logo" }
                ShellText {
                    Layout.fillWidth: true
                    text: logoRow.replacing
                        ? "Use the system logo instead? " + logoRow.fileName + " stays where it is, but fastfetch no longer shows it."
                        : logoRow.fileName + ", from fastfetch.jsonc. The system logo or an image replaces it there; the file itself stays."
                    color: logoRow.replacing ? Colors.warning : Colors.mutedText
                    role: "caption"
                    wrapMode: Text.Wrap
                }
            }
            ShellButton {
                focusOnTab: true
                visible: logoRow.replacing
                text: "Use system logo"
                compact: true
                onClicked: { logoRow.replacing = false; TerminalService.useBuiltinLogo() }
            }
            ShellButton {
                focusOnTab: true
                visible: logoRow.replacing
                text: "Keep"
                variant: "accent"
                compact: true
                onClicked: logoRow.replacing = false
            }
            ShellButton {
                focusOnTab: true
                visible: !logoRow.replacing
                text: TerminalService.choosingImage ? "Choosing …" : "Choose image …"
                icon: "󰋩"
                compact: true
                enabledState: !TerminalService.choosingImage
                onClicked: { PanelService.close(); TerminalService.chooseImage() }
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
                // Encoded: a "#" or "?" in the file's name stays part of it.
                source: WallpaperLogic.folderUrl(TerminalService.fastfetchImage)
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
                focusOnTab: true
                text: TerminalService.choosingImage ? "Choosing …" : "Choose image …"
                icon: "󰋩"
                compact: true
                enabledState: !TerminalService.choosingImage
                onClicked: { PanelService.close(); TerminalService.chooseImage() }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: TerminalService.fastfetchLogo === "image"
        title: "Fastfetch image size"
        description: "Width in terminal columns; the image keeps its proportions"

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: String(root.options.imageSize)
            options: [{ value: "20", label: "Small" }, { value: "30", label: "Medium" }, { value: "40", label: "Large" }]
            onSelected: value => root.set("imageSize", parseInt(value))
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "kitty"
        description: "Font, transparency, spacing and cursor of kitty windows. Which terminal opens is set in Default apps."

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
        // Said as Appearance and the dock say it: transparency, 0% solid.
        // The slider runs the same way as theirs (right is more solid) and
        // the stored value is still the terminals' own opacity.
        SettingRow {
            label: "Transparency"
            // Not "the session terminal": that is whatever Default apps
            // says, kitty when it says nothing.
            hint: "Alacritty takes this transparency too when it is your terminal (" + ShortcutService.keyHint("SUPER + RETURN", true) + ")"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0.5; to: 1
                value: root.options.opacity
                onReleased: value => root.set("opacity", Math.round(value * 100) / 100)
            }
            ShellText { text: Math.round((1 - root.options.opacity) * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
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

    // scripts/launch-alacritty.sh reads terminal.alacrittyDaemon itself
    // (settings.json, true when it is not there): a window from the running
    // `alacritty --daemon` instead of a new process each time, a plain
    // Alacritty when that fails.
    SettingsSection {
        Layout.fillWidth: true
        title: "Alacritty"
        scope: "terminal.alacrittyDaemon"
        description: "Alacritty keeps its own configuration and takes the transparency above."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Fast new Alacritty windows (one Alacritty process)"
            hint: "New windows open from one Alacritty that keeps running after the first, in about half the time. They share that process: if it crashes, all its windows close. Off: every window is an Alacritty of its own."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("terminal.alacrittyDaemon") !== false
                onToggled: value => SettingsService.set("terminal.alacrittyDaemon", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: !root.options.personalShell
        title: "Prompt colors"
        description: "Starship prompt symbol, user and host; errors and Git changes"

        SectionLabel { text: "Accent" }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: ["shell"].concat(TerminalService.promptColors)
                ColorSwatch {
                    required property string modelData
                    fill: modelData === "shell" ? Colors.accent : modelData // style: the swatch shows the accent itself
                    label: modelData === "shell" ? "Shell accent" : Swatch.nameOf(modelData)
                    selected: root.options.promptColor.toLowerCase() === modelData
                    mark: modelData === "shell" ? "󰏘" : ""
                    onActivated: root.set("promptColor", modelData)
                }
            }
        }
        SectionLabel { text: "Errors" }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: TerminalService.errorColors
                ColorSwatch {
                    required property string modelData
                    fill: modelData
                    label: Swatch.nameOf(modelData)
                    selected: root.options.errorColor.toLowerCase() === modelData
                    onActivated: root.set("errorColor", modelData)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: !root.options.personalShell
        title: "Symbols"
        description: "Applied with Enter or when you leave the field (up to 32 characters)"

        Repeater {
            model: [{ key: "symbol", label: "Prompt" }, { key: "errorSymbol", label: "Error" }, { key: "gitSymbol", label: "Git" }]
            SettingRow {
                id: symbolRow
                required property var modelData
                label: modelData.label
                StoredTextField {
                    focusOnTab: true
                    id: symbolField
                    Layout.fillWidth: true
                    storedText: root.options[symbolRow.modelData.key]
                    onCommit: value => root.set(symbolRow.modelData.key, value)
                }
                ShellButton {
                    focusOnTab: true
                    icon: Icons.check
                    compact: true
                    variant: "ghost"
                    toolTip: "Apply"
                    enabledState: symbolField.text !== root.options[symbolRow.modelData.key]
                    onClicked: root.set(symbolRow.modelData.key, symbolField.text)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: !root.options.personalShell
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
                    ShellToggle { focusOnTab: true; checked: root.options[moduleRow.modelData.key]; onToggled: value => root.set(moduleRow.modelData.key, value) }
                }
            }
        }
        SettingRow {
            label: "Directory depth"
            // Whole steps (IntegerSlider): the slider's own step, a twentieth
            // of the range, was rounded back and the arrow keys went nowhere.
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 1; to: 10
                value: root.options.directoryDepth
                onPicked: value => root.set("directoryDepth", value)
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
        visible: !root.options.personalShell
        title: "Clock format"
        description: "Used when the clock module is on. %H hour, %M minute, %S second, %p AM/PM, %d day, %m month"

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: root.options.timeFormat
            options: TerminalService.timeFormats
            onSelected: value => root.set("timeFormat", value)
        }
        SettingRow {
            label: "Custom"
            StoredTextField {
                focusOnTab: true
                id: timeField
                Layout.fillWidth: true
                storedText: root.options.timeFormat
                onCommit: value => root.set("timeFormat", value)
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.check
                compact: true
                variant: "ghost"
                toolTip: "Apply"
                enabledState: timeField.text !== root.options.timeFormat
                onClicked: root.set("timeFormat", timeField.text)
            }
        }
    }
}
