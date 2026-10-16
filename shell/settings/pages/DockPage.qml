import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/dock/DockLogic.js" as Logic

// Settings > Dock (shell/dock/Dock.qml). Everything here is a setting; the
// page never asks DockService anything, so an open page does not start the
// dock's service while the dock is off.
ColumnLayout {
    id: page
    spacing: Metrics.pageGap

    readonly property bool enabled: SettingsService.value("dock.enabled") === true
    readonly property string visibility: SettingsService.value("dock.visibility")
    readonly property string position: SettingsService.value("dock.position")
    readonly property string screensStored: SettingsService.value("dock.screens")
    readonly property var screenNames: Quickshell.screens.map(screen => screen.name)
    readonly property var shownOn: Logic.screensFor(screensStored, screenNames)
    readonly property bool barHere: LayoutService.barShown && LayoutService.barEdge(PanelService.screen ? PanelService.screen.name : "") === position

    SettingsSection {
        Layout.fillWidth: true
        title: "Dock"
        description: "Your pinned apps and the apps that have windows, at the edge of the screen. It works next to the notch, the bar or the widgets."

        SettingRow {
            labelFills: true
            label: "Show the dock"
            hint: "Super+Shift+D turns it on as well, and after that shows it and gives it the keyboard."
            ShellToggle {
                focusOnTab: true
                checked: page.enabled
                onToggled: value => SettingsService.set("dock.enabled", value)
            }
        }
        SettingRow {
            label: "Visibility"
            hint: "Hide for windows: the dock goes away as soon as a window touches it and comes back at the screen edge or with the key. Always: windows keep clear of it. Edge or key: it only comes when you ask."
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Visibility"
                current: page.visibility
                options: [{ value: "intellihide", label: "Hide for windows" },
                          { value: "always", label: "Always" },
                          { value: "hidden", label: "Edge or key" }]
                onSelected: value => SettingsService.set("dock.visibility", value)
            }
        }
        SettingRow {
            label: "Position"
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Position"
                current: page.position
                options: [{ value: "bottom", label: "Bottom" }, { value: "left", label: "Left" }, { value: "right", label: "Right" }]
                onSelected: value => SettingsService.set("dock.position", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: page.barHere
            text: "The bar is on this edge too. The dock stands beyond it."
            role: "small"
            muted: true
            wrapMode: Text.Wrap
        }
        SettingRow {
            label: "Icon size"
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Icon size"
                // A segmented control speaks strings: the sizes go in and
                // come out as text.
                current: String(SettingsService.value("dock.iconSize"))
                options: Logic.ICON_SIZES.map(size => ({ value: String(size), label: size + " px" }))
                onSelected: value => SettingsService.set("dock.iconSize", Number(value))
            }
        }
        SettingRow {
            label: "Distance from the edge"
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Distance from the edge"
                current: String(SettingsService.value("dock.margin"))
                options: Logic.MARGINS.map(margin => ({ value: String(margin), label: margin === 0 ? "None" : margin + " px" }))
                onSelected: value => SettingsService.set("dock.margin", Number(value))
            }
        }
        SettingRow {
            visible: Quickshell.screens.length > 1
            label: "Show on"
            hint: "Which displays have a dock. With all of them ticked a new display gets one too. The last one cannot be unticked: switch the dock off instead."
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                Repeater {
                    model: Quickshell.screens
                    ChipButton {
                        required property var modelData
                        compact: true
                        focusOnTab: true
                        enabledState: page.enabled
                        title: modelData.name
                        active: page.shownOn.indexOf(modelData.name) >= 0
                        onClicked: {
                            const next = Logic.toggleScreen(page.screensStored, modelData.name, page.screenNames)
                            if (next !== null) SettingsService.set("dock.screens", next)
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Apps"
        description: "The pinned apps are the launcher's: pin and unpin them here on the dock (right click), in the launcher, or in Settings > Launcher. Drag a pinned app along the dock to move it, or a running one among the pins to pin it."

        SettingRow {
            labelFills: true
            label: "Running apps"
            hint: "Apps with a window that are not pinned, after a line. Without them the dock shows only the pins, with dots for the ones running."
            ShellToggle {
                focusOnTab: true
                enabledState: page.enabled
                checked: SettingsService.value("dock.showRunning") !== false
                onToggled: value => SettingsService.set("dock.showRunning", value)
            }
        }
        SettingRow {
            labelFills: true
            label: "Magnify under the pointer"
            hint: Animations.motionEnabled ? "The icon under the pointer and its neighbours grow."
                : "Needs full animations (Settings > Appearance > Animations)."
            ShellToggle {
                focusOnTab: true
                enabledState: page.enabled && Animations.motionEnabled
                checked: SettingsService.value("dock.magnification") === true
                onToggled: value => SettingsService.set("dock.magnification", value)
            }
        }
        SettingRow {
            label: "Pinned apps"
            hint: "At most 10, the same ones as in the launcher."
            ShellText {
                Layout.fillWidth: true
                text: LauncherService.pinnedApps.length + " of 10 pinned"
                role: "small"
                muted: true
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.leavesPanel; text: "Launcher settings"; variant: "ghost"; compact: true
                onClicked: PanelService.open("settings", { page: "launcher" })
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Look"
        description: "The dock wears the panels' colour (Settings > Appearance > Panels) at a transparency of its own."

        SettingRow {
            id: transparencyRow
            readonly property bool own: PanelStyleService.hasOwnOpacity("dock")
            label: "Transparency"
            hint: own ? "Its own value. The reset button goes back to the panels' default." : "The panels' default."
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                from: PanelStyleService.minOpacity; to: 1
                value: PanelStyleService.opacity("dock")
                onMoved: value => PanelStyleService.setPreview("dock", value)
                onReleased: value => PanelStyleService.setOwnOpacity("dock", value)
            }
            ShellText {
                Layout.minimumWidth: Metrics.iconXl
                text: Math.round((1 - PanelStyleService.opacity("dock")) * 100) + "%"
                role: "small"
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.reset; variant: "ghost"; compact: true
                toolTip: "Use default"
                enabledState: transparencyRow.own
                onClicked: PanelStyleService.useDefaultOpacity("dock")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Keyboard"
        description: ShortcutService.keyHint("SUPER + SHIFT + D") + " shows the dock and gives it the keys: the arrow keys move along it, Enter starts or raises an app, Shift+Enter opens a new window, the menu key opens the app's menu, Esc gives the keys back."
    }
}
