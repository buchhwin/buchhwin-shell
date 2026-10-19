import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/appearance/AnimationLogic.js" as AnimationLogic
import "../../../services/settings/SwatchLogic.js" as Swatch

GridLayout {
    id: root
    columns: width >= Metrics.wideWidth - Metrics.settingsSidebarWidth ? 2 : 1
    columnSpacing: Metrics.pageGap
    rowSpacing: Metrics.pageGap

    // The choices, and the accent in use after them when it is none of them
    // (Colors.accentSwatches), so there is always a chosen swatch.
    readonly property var accents: Colors.accentSwatches
    readonly property var fontFamilies: {
        const seen = {}
        return Qt.fontFamilies().filter(name => !name.startsWith(".") && !seen[name] && (seen[name] = true))
            .map(name => ({ value: name, label: name }))
    }

    // Transparency slider row of the Panels section (shown as transparency,
    // stored as opacity). `highlighted` marks an own value; reset returns to the default.
    // The same label column every other settings row has. `caption` is the
    // row's state - "Own value" or "Default" - and sits after the value, where
    // the accent can mark it; an explanation goes in `hint` like anywhere else.
    component OpacityRow: SettingRow {
        id: opacityRow
        property string caption: ""
        property bool highlighted: true
        property bool resettable: true
        property real opacityValue: 1
        // The lowest the slider goes: the dock may go to nothing.
        property real minimum: PanelStyleService.minOpacity
        signal preview(real value)
        signal commit(real value)
        signal reset()
        Layout.fillWidth: true

        ShellSlider {
            focusOnTab: true
            Layout.fillWidth: true
            from: opacityRow.minimum; to: 1
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
        ShellText {
            visible: opacityRow.caption.length > 0
            Layout.minimumWidth: Metrics.formLabelWidth
            text: opacityRow.caption
            role: "caption"
            color: opacityRow.highlighted && opacityRow.resettable ? Colors.accentForeground : Colors.mutedText
        }
        ShellButton {
            focusOnTab: true
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
        description: "Light, dark or automatic: by the clock or from sunset to sunrise"

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: SettingsService.theme
            options: [
                { value: "dark", label: "Dark", icon: "󰖔" },
                { value: "light", label: "Light", icon: "󰖙" },
                { value: "auto", label: "Automatic", icon: "󰔎" }
            ]
            onSelected: value => SettingsService.set("appearance.theme", value)
        }
        // How Automatic decides (SunService): by the clock, or by the sun at
        // the weather place - the one Night Light's sun mode uses.
        SettingRow {
            Layout.fillWidth: true
            visible: SettingsService.theme === "auto"
            label: "Automatic switches"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("appearance.autoTheme")
                options: [{ value: "clock", label: "By the clock" }, { value: "sun", label: "By the sun" }]
                onSelected: value => SettingsService.set("appearance.autoTheme", value)
            }
        }
        // Today's times in sight under the choice, as Night Light's line says
        // its state: in the info dot alone, "By the sun" gave no answer - least
        // of all without a weather place to take the sun from.
        ShellText {
            Layout.fillWidth: true
            visible: SettingsService.theme === "auto" && text.length > 0
            text: SettingsService.value("appearance.autoTheme") === "sun" ? SunService.summary : "Dark from 19:00 to 07:00"
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
        // Qt reads the icon theme once, when the shell starts, and
        // scripts/start-shell.sh picks it by the panels' brightness: after a
        // switch some app icons keep the old theme's ink (light grey on
        // light cards) until a restart (SessionService.iconThemeStale).
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: SessionService.iconThemeStale
            label: "App icons need a restart"
            hint: "Some app icons keep the previous theme's color until the shell restarts."
            ShellButton {
                focusOnTab: true
                compact: true
                text: "Restart shell"
                onClicked: { PanelService.close(); SessionService.restartShell() }
            }
        }

        // Opt-in: switches the colour scheme shared with Plasma (AppThemeService).
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Apps follow theme"
            hint: "Also switches KDE and GTK apps. This changes the color scheme shared with Plasma."
            ShellToggle {
                focusOnTab: true
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
                focusOnTab: true
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

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Accent color"
            ShellText { text: "From wallpaper"; role: "small"; muted: true }
            ShellToggle {
                focusOnTab: true
                // Its own name: SettingRow would give it the row's, "Accent color".
                accessibleName: "Accent color from wallpaper"
                checked: SettingsService.value("appearance.accentFromWallpaper")
                onToggled: value => SettingsService.set("appearance.accentFromWallpaper", value)
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: root.accents
                ColorSwatch {
                    required property string modelData
                    fill: modelData
                    label: Swatch.nameOf(modelData)
                    selected: SettingsService.accent.toLowerCase() === modelData
                    onActivated: { SettingsService.set("appearance.accentFromWallpaper", false); SettingsService.set("appearance.accent", modelData) }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Night Light"
        description: "Warmer colors in the evening are easier on the eyes. " + NightLightService.summary

        SegmentedControl {
            focusOnTab: true
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

    // A color filter over the whole screen (ScreenEffectsService): Hyprland
    // runs one of the shaders in shaders/ over every frame while it is on.
    SettingsSection {
        Layout.fillWidth: true
        title: "Color filter"
        description: "Grayscale, colors that stay apart for color-blind eyes, or the colors inverted, over the whole screen. "
            + ShortcutService.keyHint("SUPER + CTRL + C", true) + " turns it on and off. While it is on, every frame goes through it, which costs the graphics card a little."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "On"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("display.colorFilterOn") === true
                onToggled: value => ScreenEffectsService.setFilterOn(value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Filter"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: ScreenEffectsService.filters
                current: ScreenEffectsService.filter
                onSelected: value => SettingsService.set("display.colorFilter", value)
            }
        }
    }

    // Background colour and transparency of every shell surface; the window
    // groups come from PanelStyleService and sliders preview live.
    SettingsSection {
        id: panelSection
        Layout.fillWidth: true
        Layout.columnSpan: root.columns
        title: "Panels"
        description: "Background color and transparency of panels, popups, pills and widgets. A light color switches to the light theme and a dark one to the dark theme, so the desktop and apps go along."

        readonly property var choice: Colors.panelColorChoices.find(item => item.value === PanelStyleService.color)
        readonly property int ownCount: PanelStyleService.groups.filter(group => PanelStyleService.hasOwnOpacity(group.key)).length
        property bool individualOpen: ownCount > 0
        property string customError: ""

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Background color"
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
                ColorSwatch {
                    required property var modelData
                    readonly property bool isAuto: modelData.value === "auto"
                    fill: isAuto ? Colors.surface1 : modelData.value
                    label: modelData.label
                    outlined: true
                    selected: PanelStyleService.color === modelData.value
                    mark: isAuto ? "󰔎" : ""
                    markColor: isAuto ? Colors.text : PanelStyleService.isLight(modelData.value) ? Colors.onLightSwatch : Colors.onDarkSwatch
                    onActivated: PanelStyleService.setColor(modelData.value, Colors.dark)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellTextField {
                focusOnTab: true
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
                focusOnTab: true
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
        // Choosing a colour switches the theme; a later theme change can
        // disagree again. That is no warning any more: the panels' text
        // follows the panel colour (Colors.surfaceDark), and only the desktop
        // and the applications go by the theme - which the button offers to
        // bring along.
        RowLayout {
            Layout.fillWidth: true
            visible: PanelStyleService.customColor && !PanelStyleService.matchesTheme(Colors.dark)
            spacing: Metrics.spaceSm
            ShellIcon { glyph: Icons.info; size: Metrics.iconSm; color: Colors.mutedText }
            ShellText {
                Layout.fillWidth: true
                text: "Panels keep readable text in any color; the theme sets the desktop and apps."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            ShellButton {
                focusOnTab: true
                text: PanelStyleService.lightColor ? "Use light theme" : "Use dark theme"
                compact: true
                onClicked: SettingsService.set("appearance.theme", PanelStyleService.lightColor ? "light" : "dark")
            }
        }

        OpacityRow {
            label: "Transparency"
            // A light panel has a floor (PanelStyleLogic.LIGHT_MIN_OPACITY),
            // so a slider set further does less than it says; the hint says why.
            hint: Colors.surfaceDark ? "Default for all windows"
                : "Default for all windows. A light panel stays at most "
                  + Math.round((1 - PanelStyleService.lightMinOpacity) * 100)
                  + "% transparent, so its text keeps its contrast."
            opacityValue: PanelStyleService.defaultOpacity
            resettable: false
            onPreview: value => PanelStyleService.setPreview("default", value)
            onCommit: value => PanelStyleService.setDefaultOpacity(value)
        }
        ScopeNote { path: "appearance.panelOpacity" }

        Divider {}

        // The row that folds the per-window sliders away: a list row on the
        // card, like the expandable rows on the Updates page.
        ListRow {
            Layout.fillWidth: true
            level: 1
            focusOnTab: true
            icon: Icons.window
            title: "Individual windows"
            subtitle: panelSection.ownCount === 0 ? "All windows use the default transparency"
                : panelSection.ownCount === 1 ? "1 window has its own transparency"
                : panelSection.ownCount + " windows have their own transparency"
            onClicked: panelSection.individualOpen = !panelSection.individualOpen
            Row {
                spacing: Metrics.spaceSm
                ShellButton {
                    anchors.verticalCenter: parent.verticalCenter
                    focusOnTab: true
                    visible: panelSection.ownCount > 0
                    icon: Icons.reset; text: "Use default for all"; compact: true
                    onClicked: PanelStyleService.resetAllOpacities()
                }
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: panelSection.individualOpen ? Icons.collapse : Icons.forward
                    size: Metrics.iconXs
                    color: Colors.mutedText
                }
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
                    minimum: PanelStyleService.minOpacityFor(modelData.key)
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
        title: "Windows & effects"
        description: "Blur, corners, borders, gaps and animations"
        // Most of these are the mode's own; the two that are not say so.
        scope: "appearance.blurStrength"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Dim behind panels"
            hint: "The rest of the screen darkens a little while a panel is open. One setting for all of them: they share a single scrim. It is the same in every mode."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("appearance.panelScrim")
                onToggled: value => SettingsService.set("appearance.panelScrim", value)
            }
        }
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
        // The lighter effects on battery (Settings > Power) take the blur and
        // Full motion away while their power source applies; the values here
        // stay the user's and are back the moment it no longer does.
        ShellText {
            Layout.fillWidth: true
            visible: SettingsService.lightEffects === true
            text: "Lighter effects are on (Settings > Power): no blur, and Full motion runs as Reduced"
            role: "small"; muted: true
            wrapMode: Text.Wrap
        }
        // The pixel sliders below take whole steps (IntegerSlider): the
        // slider's own step is a twentieth of the range, and rounded it went
        // nowhere on Border width and unevenly on the gaps.
        SettingRow {
            label: "Window corners"
            hint: "App windows"
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 32
                value: SettingsService.windowRadius
                onPicked: value => SettingsService.set("appearance.windowRadius", value)
            }
            ShellText { text: SettingsService.windowRadius + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Shell corners"
            hint: "Panels, popups, cards and buttons"
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 32
                value: SettingsService.value("appearance.shellRadius")
                onPicked: value => SettingsService.set("appearance.shellRadius", value)
            }
            ShellText { text: SettingsService.value("appearance.shellRadius") + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Round the screen corners"
            hint: "The display itself takes the window rounding, like a laptop bezel. It is the same in every mode."
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
                focusOnTab: true
                checked: SettingsService.borderEnabled
                onToggled: value => SettingsService.set("appearance.borderEnabled", value)
            }
        }
        SettingRow {
            label: "Border width"
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 1; to: 8
                enabledState: SettingsService.borderEnabled
                value: SettingsService.borderSize
                onPicked: value => SettingsService.set("appearance.borderSize", value)
            }
            ShellText { text: SettingsService.borderSize + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Gap between windows"
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 30
                value: SettingsService.gapsIn
                onPicked: value => SettingsService.set("appearance.gapsIn", value)
            }
            ShellText { text: SettingsService.gapsIn + " px"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Gap to screen edge"
            IntegerSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: 0; to: 60
                value: SettingsService.gapsOut
                onPicked: value => SettingsService.set("appearance.gapsOut", value)
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
            hint: "How fast the motion runs, on the desktop and in the shell alike - the springs included, which play the same curve faster or slower. From half speed to double."
            // The mode above chooses the character of the motion, this chooses
            // its pace - and it drives the compositor's own animations too, so
            // a window and the panel over it move at one rhythm. Off has
            // nothing to pace.
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                enabledState: SettingsService.animationMode !== "off"
                from: AnimationLogic.SPEED_MIN; to: AnimationLogic.SPEED_MAX
                value: SettingsService.animationSpeed
                // Snapped to twentieths: the difference between 1.00 and 1.03
                // is not a difference anyone can see, and a stored 1.0374 only
                // makes the file harder to read.
                onReleased: value => SettingsService.set("appearance.animationSpeed",
                    Math.round(value * 20) / 20)
            }
            // As wide as its longest reading, with even digits: "1.00x ·
            // normal" is more than twice the 36 px the other values here get,
            // and the slider changed length with every step.
            ShellText {
                id: paceLabel
                readonly property real pace: SettingsService.animationSpeed
                text: pace.toFixed(2) + "x · " + (pace < 0.9 ? "slow" : pace > 1.1 ? "fast" : "normal")
                role: "small"; muted: true
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
                Layout.minimumWidth: Math.max(Metrics.iconXl, Math.ceil(paceWidest.advanceWidth))
                TextMetrics { id: paceWidest; font: paceLabel.font; text: "0.00x · normal" }
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
                focusOnTab: true
                text: "Install …"
                compact: true
                onClicked: {
                    Quickshell.execDetached([Paths.script("launch-terminal.sh"), "--hold", "--title", "macOS cursor install", "--", Paths.script("install-cursor-macos.sh")])
                    PanelService.close()
                }
            }
            ShellButton { focusOnTab: true; icon: Icons.refresh; compact: true; variant: "ghost"; toolTip: "Refresh"; onClicked: AppearanceService.refreshCursorThemes() }
        }
    }
}
