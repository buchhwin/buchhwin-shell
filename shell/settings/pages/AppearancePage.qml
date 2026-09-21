import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

GridLayout {
    id: root
    columns: width >= Metrics.wideWidth - Metrics.settingsSidebarWidth ? 2 : 1
    columnSpacing: Metrics.spaceLg
    rowSpacing: Metrics.spaceLg

    readonly property var accents: Colors.accentChoices
    readonly property var fontFamilies: {
        const seen = {}
        return Qt.fontFamilies().filter(name => !name.startsWith(".") && !seen[name] && (seen[name] = true))
            .map(name => ({ value: name, label: name }))
    }

    // Transparency slider row of the Panels section (shown as transparency,
    // stored as opacity). `highlighted` marks an own value; reset returns to the default.
    component OpacityRow: RowLayout {
        id: opacityRow
        property string label: ""
        property string caption: ""
        property bool highlighted: true
        property bool resettable: true
        property real opacityValue: 1
        signal preview(real value)
        signal commit(real value)
        signal reset()
        Layout.fillWidth: true
        spacing: Metrics.spaceMd

        ColumnLayout {
            Layout.preferredWidth: Metrics.settingsSidebarWidth
            Layout.fillWidth: false
            spacing: 0
            ShellText { Layout.fillWidth: true; text: opacityRow.label }
            ShellText {
                Layout.fillWidth: true
                text: opacityRow.caption
                role: "caption"
                color: opacityRow.highlighted && opacityRow.resettable ? Colors.accentForeground : Colors.mutedText
            }
        }
        ShellSlider {
            Layout.fillWidth: true
            from: PanelStyleService.minOpacity; to: 1
            value: opacityRow.opacityValue
            opacity: opacityRow.highlighted || pressed ? 1 : Effects.mutedOpacity
            onMoved: value => opacityRow.preview(value)
            onReleased: value => opacityRow.commit(value)
        }
        ShellText {
            Layout.minimumWidth: Metrics.iconXl
            text: Math.round((1 - opacityRow.opacityValue) * 100) + "%"
            role: "small"; muted: !opacityRow.highlighted
        }
        ShellButton {
            icon: Icons.reset; variant: "ghost"; compact: true
            toolTip: "Use default"
            opacity: opacityRow.resettable ? (opacityRow.highlighted ? 1 : Effects.disabledOpacity) : 0
            enabledState: opacityRow.resettable && opacityRow.highlighted
            onClicked: opacityRow.reset()
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Theme"
        description: "Light, dark or automatic (dark from 19:00 to 07:00)"

        SegmentedControl {
            Layout.fillWidth: true
            current: SettingsService.theme
            options: [
                { value: "dark", label: "Dark", icon: "󰖔" },
                { value: "light", label: "Light", icon: "󰖙" },
                { value: "auto", label: "Automatic", icon: "󰔎" }
            ]
            onSelected: value => SettingsService.set("appearance.theme", value)
        }

        // Opt-in: switches the colour scheme shared with Plasma (AppThemeService).
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Apps follow theme"
            hint: "Also switches KDE and GTK apps. This changes the color scheme shared with Plasma."
            ShellToggle {
                checked: AppThemeService.enabled
                onToggled: value => SettingsService.set("appearance.appsFollowTheme", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use the shell accent in apps"
            hint: "KDE apps such as Dolphin use the accent for folder icons and selections. Plasma keeps its own colors: they are restored when you log out."
            ShellToggle {
                checked: AppThemeService.accentEnabled
                onToggled: value => SettingsService.set("appearance.appsAccent", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: AppThemeService.anyEnabled
            label: "Restore Plasma colors at logout"
            hint: "Plasma gets its previous colors back when you log out of this session, or at its next login after a crash. Turning the options above off restores them right away."
            ShellToggle {
                focusOnTab: true
                checked: AppThemeService.restoreOnLogout
                onToggled: value => SettingsService.set("appearance.appsRestoreOnLogout", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: AppThemeService.statusText.length > 0
            text: AppThemeService.statusText
            role: "caption"
            color: AppThemeService.statusIsError ? Colors.danger : Colors.mutedText
            wrapMode: Text.Wrap
        }

        RowLayout {
            ShellText { Layout.fillWidth: true; text: "Accent color" }
            ShellText { text: "From wallpaper"; role: "small"; muted: true }
            ShellToggle {
                checked: SettingsService.value("appearance.accentFromWallpaper")
                onToggled: value => SettingsService.set("appearance.accentFromWallpaper", value)
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: root.accents
                Rectangle {
                    required property string modelData
                    readonly property bool active: SettingsService.accent.toLowerCase() === modelData
                    width: Metrics.controlHeight
                    height: width
                    radius: width / 2
                    color: modelData
                    border.width: active ? Metrics.focusBorderWidth + 1 : 0
                    border.color: Colors.text
                    ShellIcon { anchors.centerIn: parent; visible: parent.active; glyph: Icons.check; size: Metrics.iconSm; color: Colors.textOn(parent.color) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { SettingsService.set("appearance.accentFromWallpaper", false); SettingsService.set("appearance.accent", parent.modelData) } }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Night Light"
        description: "Warmer colors in the evening are easier on the eyes. " + NightLightService.summary

        SegmentedControl {
            Layout.fillWidth: true
            current: SettingsService.value("nightLight.mode")
            options: [{ value: "off", label: "Off" }, { value: "manual", label: "Always" }, { value: "schedule", label: "Schedule" }, { value: "sun", label: "Sunset" }]
            onSelected: value => SettingsService.set("nightLight.mode", value)
        }
        SettingRow {
            label: "Color temperature"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("nightLight.temperature"))
                options: [{ value: "5000", label: "Low" }, { value: "4000", label: "Medium" }, { value: "3200", label: "Strong" }]
                onSelected: value => SettingsService.set("nightLight.temperature", parseInt(value))
            }
        }
        SettingRow {
            visible: SettingsService.value("nightLight.mode") === "schedule"
            label: "Hours"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("nightLight.start") + "-" + SettingsService.value("nightLight.end")
                options: [{ value: "19:00-07:00", label: "19–7" }, { value: "20:00-07:00", label: "20–7" }, { value: "21:00-06:00", label: "21–6" }, { value: "22:00-07:00", label: "22–7" }]
                onSelected: value => {
                    SettingsService.set("nightLight.start", value.split("-")[0])
                    SettingsService.set("nightLight.end", value.split("-")[1])
                }
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: NightLightService.sunNeedsLocation
            text: "Sunset and sunrise use the weather location. Set it under Weather."
            role: "small"; color: Colors.warning; wrapMode: Text.Wrap
        }
    }

    // Background colour and transparency of every shell surface; the window
    // groups come from PanelStyleService and sliders preview live.
    SettingsSection {
        id: panelSection
        Layout.fillWidth: true
        Layout.columnSpan: root.columns
        title: "Panels"
        description: "Background color and transparency of panels, popups, pills and widgets. A light color switches to the Light theme and a dark one to the Dark theme, so text stays readable."

        readonly property var choice: Colors.panelColorChoices.find(item => item.value === PanelStyleService.color)
        readonly property int ownCount: PanelStyleService.groups.filter(group => PanelStyleService.hasOwnOpacity(group.key)).length
        property bool individualOpen: ownCount > 0
        property string customError: ""

        RowLayout {
            ShellText { Layout.fillWidth: true; text: "Background color" }
            ShellText {
                text: PanelStyleService.color === "auto" ? "Theme colors"
                    : panelSection.choice ? panelSection.choice.label : "Custom " + PanelStyleService.color
                role: "small"; muted: true
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: [{ value: "auto", label: "Theme colors" }].concat(Colors.panelColorChoices)
                Rectangle {
                    required property var modelData
                    readonly property bool isAuto: modelData.value === "auto"
                    readonly property bool active: PanelStyleService.color === modelData.value
                    width: Metrics.controlHeight
                    height: width
                    radius: width / 2
                    color: isAuto ? Colors.surface : modelData.value
                    border.width: active ? Metrics.focusBorderWidth + 1 : Metrics.borderWidth
                    border.color: active ? Colors.accent : Colors.borderStrong
                    ShellIcon {
                        anchors.centerIn: parent
                        visible: parent.isAuto || parent.active
                        glyph: parent.isAuto && !parent.active ? "󰔎" : Icons.check
                        size: Metrics.iconSm
                        color: parent.isAuto ? Colors.text : PanelStyleService.isLight(parent.modelData.value) ? Colors.onLightSwatch : Colors.onDarkSwatch
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: PanelStyleService.setColor(parent.modelData.value, Colors.dark) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellTextField {
                id: customColor
                Layout.fillWidth: true
                icon: "󰏘"
                placeholder: "Custom color, e.g. #1e2433"
                onAccepted: panelSection.applyCustom()
                onTextChanged: panelSection.customError = ""
            }
            Rectangle {
                readonly property string hex: PanelStyleService.normalizeHex(customColor.text)
                visible: hex.length > 0
                implicitWidth: Metrics.controlHeight
                implicitHeight: Metrics.controlHeight
                radius: Metrics.radiusInner
                color: visible ? hex : "transparent"
                border.width: Metrics.borderWidth
                border.color: Colors.borderStrong
            }
            ShellButton {
                text: "Apply"
                enabledState: customColor.text.trim().length > 0
                onClicked: panelSection.applyCustom()
            }
        }
        function applyCustom() {
            if (PanelStyleService.setColor(customColor.text, Colors.dark)) customColor.text = ""
            else customError = "Enter a hex color like #1e2433 or #234."
        }
        ShellText {
            Layout.fillWidth: true
            visible: panelSection.customError.length > 0
            text: panelSection.customError
            role: "small"; color: Colors.danger; wrapMode: Text.Wrap
        }
        // Text colours follow the theme (all components read Colors.text). Choosing
        // a colour switches the theme; a later theme change can disagree again.
        RowLayout {
            Layout.fillWidth: true
            visible: PanelStyleService.customColor && !PanelStyleService.matchesTheme(Colors.dark)
            spacing: Metrics.spaceSm
            ShellIcon { glyph: "󰋽"; size: Metrics.iconSm; color: Colors.warning }
            ShellText {
                Layout.fillWidth: true
                text: PanelStyleService.lightColor
                    ? "Text colors follow the theme and are hard to read on a light panel color."
                    : "Text colors follow the theme and are hard to read on a dark panel color."
                role: "small"; color: Colors.warning; wrapMode: Text.Wrap
            }
            ShellButton {
                text: PanelStyleService.lightColor ? "Use Light theme" : "Use Dark theme"
                compact: true
                onClicked: SettingsService.set("appearance.theme", PanelStyleService.lightColor ? "light" : "dark")
            }
        }

        OpacityRow {
            label: "Transparency"
            caption: "Default for all windows"
            opacityValue: PanelStyleService.defaultOpacity
            resettable: false
            onPreview: value => PanelStyleService.setPreview("default", value)
            onCommit: value => PanelStyleService.setDefaultOpacity(value)
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: Metrics.borderWidth; color: Colors.border }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Item {
                Layout.fillWidth: true
                implicitHeight: individualHeader.implicitHeight
                RowLayout {
                    id: individualHeader
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Metrics.spaceSm
                    ShellIcon { glyph: panelSection.individualOpen ? Icons.collapse : Icons.forward; size: Metrics.iconSm; color: Colors.mutedText }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ShellText { text: "Individual windows" }
                        ShellText {
                            Layout.fillWidth: true
                            text: panelSection.ownCount === 0 ? "All windows use the default transparency"
                                : panelSection.ownCount === 1 ? "1 window has its own transparency"
                                : panelSection.ownCount + " windows have their own transparency"
                            role: "caption"
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panelSection.individualOpen = !panelSection.individualOpen
                }
            }
            ShellButton {
                visible: panelSection.ownCount > 0
                icon: Icons.reset; text: "Use default for all"; compact: true
                onClicked: PanelStyleService.resetAllOpacities()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: panelSection.individualOpen
            spacing: Metrics.spaceSm

            Repeater {
                model: PanelStyleService.groups
                OpacityRow {
                    required property var modelData
                    readonly property bool own: PanelStyleService.hasOwnOpacity(modelData.key)
                    label: modelData.label
                    caption: own ? "Own value" : "Default"
                    highlighted: own
                    opacityValue: PanelStyleService.opacity(modelData.key)
                    onPreview: value => PanelStyleService.setPreview(modelData.key, value)
                    onCommit: value => PanelStyleService.setOwnOpacity(modelData.key, value)
                    onReset: PanelStyleService.useDefaultOpacity(modelData.key)
                }
            }
            ShellText {
                Layout.fillWidth: true
                text: "Pill popups & dialogs also covers the Wi-Fi password and Bluetooth pairing dialogs and panels without their own entry."
                role: "caption"; wrapMode: Text.Wrap
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Windows & Effects"
        description: "Blur, corners, borders, gaps and animations"

        SettingRow {
            label: "Blur"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                value: SettingsService.blurStrength
                onReleased: value => SettingsService.set("appearance.blurStrength", Math.round(value * 100) / 100)
            }
            ShellText { text: Math.round(SettingsService.blurStrength * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Window corners"
            hint: "App windows"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 32
                value: SettingsService.windowRadius
                onReleased: value => SettingsService.set("appearance.windowRadius", Math.round(value))
            }
            ShellText { text: SettingsService.windowRadius + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Shell corners"
            hint: "Panels, popups, cards and buttons"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 32
                value: SettingsService.value("appearance.shellRadius")
                onReleased: value => SettingsService.set("appearance.shellRadius", Math.round(value))
            }
            ShellText { text: SettingsService.value("appearance.shellRadius") + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Round the screen corners"
            hint: "The display itself takes the window rounding, like a laptop bezel"
            ShellToggle {
                focusOnTab: true
                checked: AppearanceService.screenCorners
                onToggled: value => SettingsService.set("appearance.screenCorners", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Window borders"
            ShellToggle {
                checked: SettingsService.borderEnabled
                onToggled: value => SettingsService.set("appearance.borderEnabled", value)
            }
        }
        SettingRow {
            label: "Border width"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 1; to: 8
                enabledState: SettingsService.borderEnabled
                value: SettingsService.borderSize
                onReleased: value => SettingsService.set("appearance.borderSize", Math.round(value))
            }
            ShellText { text: SettingsService.borderSize + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Gap between windows"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 30
                value: SettingsService.gapsIn
                onReleased: value => SettingsService.set("appearance.gapsIn", Math.round(value))
            }
            ShellText { text: SettingsService.gapsIn + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Gap to screen edge"
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 60
                value: SettingsService.gapsOut
                onReleased: value => SettingsService.set("appearance.gapsOut", Math.round(value))
            }
            ShellText { text: SettingsService.gapsOut + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Animations"
            hint: "Full animates everything. Reduced keeps the fades and drops the movement, including a dragged window following the pointer. Off stops them entirely."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.animationMode
                // Three, not four. Fast and Normal differed in a duration
                // factor and nothing else, which is exactly what the slider
                // below does - the two were a choice between a thing and
                // itself. Reduced and Off stay because they turn movement off
                // rather than shortening it, and no pace can say that.
                options: [
                    { value: "full", label: "Full" },
                    { value: "reduced", label: "Reduced" }, { value: "off", label: "Off" }
                ]
                onSelected: value => SettingsService.set("appearance.animationMode", value)
            }
        }
        SettingRow {
            label: "Animation speed"
            hint: "How fast the motion runs, on the desktop and in the shell alike. Nothing that travels goes below ten frames however far this is turned up, or it stops reading as motion at all."
            // The mode above chooses the character of the motion, this chooses
            // its pace - and it drives the compositor's own animations too, so
            // a window and the panel over it move at one rhythm. Off has
            // nothing to pace.
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                enabledState: SettingsService.animationMode !== "off"
                from: 0.25; to: 3
                value: SettingsService.animationSpeed
                // Snapped to twentieths: the difference between 1.00 and 1.03
                // is not a difference anyone can see, and a stored 1.0374 only
                // makes the file harder to read.
                onReleased: value => SettingsService.set("appearance.animationSpeed",
                    Math.round(value * 20) / 20)
            }
            ShellText {
                text: SettingsService.animationSpeed.toFixed(2) + "x"
                role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Font"
        description: "Interface font and monospace font of the shell"

        SettingRow {
            label: "Interface"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: root.fontFamilies
                current: SettingsService.fontFamily
                previewFonts: true
                onSelected: value => SettingsService.set("appearance.fontFamily", value)
            }
        }
        SettingRow {
            label: "Monospace"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: root.fontFamilies
                current: SettingsService.monoFontFamily
                previewFonts: true
                onSelected: value => SettingsService.set("appearance.monoFontFamily", value)
            }
        }
        SettingRow {
            label: "Text size"
            hint: "Scales every text in the shell; the settings window grows with it"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("appearance.fontScale"))
                options: [{ value: "0.9", label: "Small" }, { value: "1", label: "Normal" },
                          { value: "1.1", label: "Large" }, { value: "1.25", label: "Larger" }]
                onSelected: value => SettingsService.set("appearance.fontScale", Number(value))
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Cursor"
        description: "Applies to Hyprland and apps started afterwards in this session"

        SettingRow {
            label: "Theme"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: AppearanceService.cursorThemes.map(theme => ({ value: theme.name, label: theme.label }))
                current: SettingsService.cursorTheme
                onSelected: value => SettingsService.set("appearance.cursorTheme", value)
            }
        }
        SettingRow {
            label: "Size"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.cursorSize)
                options: [{ value: "24", label: "24" }, { value: "32", label: "32" }, { value: "48", label: "48" }]
                onSelected: value => SettingsService.set("appearance.cursorSize", parseInt(value))
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: !AppearanceService.macCursorInstalled
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                text: "The macOS cursor is not installed."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            ShellButton {
                text: "Install …"
                compact: true
                onClicked: {
                    Quickshell.execDetached([Paths.script("launch-kitty.sh"), "--hold", Paths.script("install-cursor-macos.sh")])
                    PanelService.close()
                }
            }
            ShellButton { icon: Icons.refresh; compact: true; variant: "ghost"; onClicked: AppearanceService.refreshCursorThemes() }
        }
    }
}
