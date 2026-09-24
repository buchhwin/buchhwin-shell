import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.spaceLg

    // A touchpad may have been connected since the page was last on screen,
    // and VS Code's own scroll setting may have changed.
    PageActivity {
        onOpened: {
            GestureService.refreshDevices()
            InputService.refreshAppScroll()
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Keyboard"

        SettingRow {
            label: "Layout"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: InputService.layouts
                current: SettingsService.value("input.kbLayout")
                onSelected: value => {
                    SettingsService.set("input.kbVariant", "")
                    SettingsService.set("input.kbLayout", value)
                }
            }
        }
        SettingRow {
            label: "Variant"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: InputService.variantsFor(SettingsService.value("input.kbLayout"))
                current: SettingsService.value("input.kbVariant")
                onSelected: value => SettingsService.set("input.kbVariant", value)
            }
        }
        SettingRow {
            label: "Repeat rate"
            hint: "Characters per second"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("input.repeatRate"))
                options: [{ value: "20", label: "20" }, { value: "25", label: "25" }, { value: "35", label: "35" }, { value: "50", label: "50" }]
                onSelected: value => SettingsService.set("input.repeatRate", parseInt(value))
            }
        }
        SettingRow {
            label: "Delay"
            hint: "Before repeating starts"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("input.repeatDelay"))
                options: [{ value: "250", label: "Short" }, { value: "400", label: "Medium" }, { value: "600", label: "Long" }]
                onSelected: value => SettingsService.set("input.repeatDelay", parseInt(value))
            }
        }
        ShellTextField {
            focusOnTab: true
            Layout.fillWidth: true
            icon: "󰌌"
            placeholder: "Type here to test layout and repeat"
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Mouse and pointer"

        SettingRow {
            label: "Speed"
            // Written on release like the Appearance sliders - every tick of a
            // drag used to be a settings write and a Hyprland option apply.
            // The number beside the slider follows the handle meanwhile.
            ShellSlider {
                id: speedSlider
                focusOnTab: true
                Layout.fillWidth: true
                value: (SettingsService.value("input.sensitivity") + 1) / 2
                onReleased: value => SettingsService.set("input.sensitivity", Math.round((value * 2 - 1) * 20) / 20)
            }
            ShellText {
                text: Math.round((speedSlider.pressed ? speedSlider.liveValue * 2 - 1 : SettingsService.value("input.sensitivity")) * 100) + "%"
                role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl
            }
        }
        SettingRow {
            label: "Acceleration"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("input.accelProfile")
                options: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }]
                onSelected: value => SettingsService.set("input.accelProfile", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Natural scrolling (mouse)"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("input.mouseNaturalScroll"); onToggled: value => SettingsService.set("input.mouseNaturalScroll", value) }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Touchpad"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Natural scrolling"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("input.touchpadNaturalScroll"); onToggled: value => SettingsService.set("input.touchpadNaturalScroll", value) }
        }
        SettingRow {
            label: "Scroll speed"
            hint: "How far two fingers scroll. Apps with their own scrolling, such as browsers, still differ."
            ShellSlider {
                id: scrollSlider
                focusOnTab: true
                Layout.fillWidth: true
                from: 0.2
                to: 2
                value: SettingsService.value("input.touchpadScrollFactor")
                onReleased: value => SettingsService.set("input.touchpadScrollFactor", Math.round(value * 20) / 20)
            }
            ShellText {
                text: Math.round((scrollSlider.pressed ? scrollSlider.liveValue : SettingsService.value("input.touchpadScrollFactor")) * 100) + "%"
                role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            // VS Code scrolls much further per step than other apps; its own
            // setting can be matched to the speed above.
            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Match VS Code"
                hint: "VS Code scrolls with its own sensitivity. This writes it into its settings (a backup is kept)."
                ShellButton {
                    focusOnTab: true
                    text: InputService.appScrollMatched ? "Undo" : "Match"
                    compact: true
                    enabledState: !InputService.appScrollBusy && InputService.appScrollError.length === 0
                    onClicked: InputService.appScrollRun(InputService.appScrollMatched ? "reset" : "apply")
                }
            }
            // What happened, not what the button is for: that is the hint.
            ShellText {
                Layout.fillWidth: true
                visible: InputService.appScrollError.length > 0 || InputService.appScrollMatched
                text: InputService.appScrollError.length > 0 ? InputService.appScrollError
                    : "VS Code uses the speed above. Restart it to pick the change up."
                role: "caption"
                color: InputService.appScrollError.length > 0 ? Colors.danger : Colors.mutedText
                wrapMode: Text.Wrap
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Tap to click"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("input.tapToClick"); onToggled: value => SettingsService.set("input.tapToClick", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Disable while typing"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("input.disableWhileTyping"); onToggled: value => SettingsService.set("input.disableWhileTyping", value) }
        }
    }

    SettingsSection {
        id: gestureSection
        Layout.fillWidth: true
        visible: GestureService.touchpadShown
        title: "Touchpad gestures"
        description: "Swipe with three or four fingers. Switching workspaces follows your fingers; panels open when the swipe ends."
        readonly property bool gesturesOn: SettingsService.value("gestures.enabled")

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use gestures"
            ShellToggle { focusOnTab: true; checked: gestureSection.gesturesOn; onToggled: value => SettingsService.set("gestures.enabled", value) }
        }

        Repeater {
            model: gestureSection.gesturesOn ? GestureService.slots : []
            SettingRow {
                id: slotRow
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    visible: slotRow.modelData.horizontal === true
                    current: SettingsService.value("gestures." + slotRow.modelData.key)
                    options: GestureService.horizontalActions
                    onSelected: value => SettingsService.set("gestures." + slotRow.modelData.key, value)
                }
                ShellSelect {
                    focusOnTab: true
                    Layout.fillWidth: true
                    visible: slotRow.modelData.horizontal !== true
                    current: SettingsService.value("gestures." + slotRow.modelData.key)
                    options: GestureService.actions
                    onSelected: value => SettingsService.set("gestures." + slotRow.modelData.key, value)
                }
            }
        }

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: gestureSection.gesturesOn
            label: "Natural swipe direction"
            hint: "Workspaces move with your fingers, like natural scrolling"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("gestures.naturalSwipe"); onToggled: value => SettingsService.set("gestures.naturalSwipe", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: gestureSection.gesturesOn
            label: "Create a new workspace at the end"
            hint: "Swiping past the last workspace opens an empty one"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("gestures.createNew"); onToggled: value => SettingsService.set("gestures.createNew", value) }
        }
    }
}
