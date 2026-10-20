import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/dock/DockLogic.js" as Logic
import "../../../services/settings/DockPageLogic.js" as PageLogic

// Settings > Dock (shell/dock/Dock.qml). Everything here is a setting or the
// dock's layout; the page never asks DockService anything, so an open page
// does not start the dock's service while the dock is off.
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

    // The preset the dock is built from (its widgets; the pins and the
    // options tuned since are the user's, DockPageLogic): its card says "In
    // use". The two cards looked the same whichever one was applied.
    readonly property string presetInUse: PageLogic.presetInUse(LayoutService.builtinDockPresets, LayoutService.dockLayout,
                                                                key => SettingsService.value("dock." + key))
    // A preset is one click, and it replaces the dock's layout and options:
    // the step it took is kept here, and "Undo" stays offered while that
    // step is still the last one (LayoutService.undo takes it back, the
    // dock switched on with it included).
    property var appliedStep: null
    property string appliedLabel: ""
    readonly property bool presetUndoable: appliedStep !== null && LayoutService.undoStack.length > 0
        && LayoutService.undoStack[LayoutService.undoStack.length - 1] === appliedStep
    function applyPreset(preset) {
        if (LayoutService.readOnly || !preset) return
        // Switched on with it: choosing a dock is asking for one.
        if (!LayoutService.applyDockPreset(preset.id, true)) return
        if (!page.enabled) SettingsService.set("dock.enabled", true)
        page.appliedStep = LayoutService.undoStack.length ? LayoutService.undoStack[LayoutService.undoStack.length - 1] : null
        page.appliedLabel = preset.label
    }
    function undoPreset() {
        if (!page.presetUndoable) return
        page.appliedStep = null
        LayoutService.undo()
    }

    // The dock's pins as they are stored, each with the entry it stands for
    // now. Read here rather than from DockService, which this page never
    // starts (see above): the same resolution, desktop ids and the defaults
    // of Settings > Default apps.
    readonly property var pins: LayoutService.dockLayout.pins || []
    readonly property bool pinsNeedDefaults: pins.some(pin => Logic.pinCategory(pin).length > 0)
    function entryFor(pin) {
        if (pin === "@settings") return null
        const id = Logic.pinCategory(pin).length ? Logic.defaultFor(pin, DefaultAppsService.categories) : pin
        const entry = id.length ? DesktopEntries.byId(id) : null
        return entry && !entry.noDisplay ? { name: entry.name, icon: entry.icon } : null
    }
    // DesktopEntries.byId() notifies no binding when the entries are read
    // (the scan after the start, an app installed or removed): the
    // launcher's count of settled scans runs the rows again, or a pin read
    // before the scan said "Not installed" until the layout changed.
    readonly property var pinRows: {
        LauncherService.entriesRevision
        return pins.map(pin => PageLogic.pinRow(pin, page.entryFor(pin), DefaultAppsService.categories.length > 0))
    }
    // A step builds the rows anew (a new array: every row is made again) and
    // the button pressed goes with its row, so a keyboard lost its place
    // after every step. The focus comes back to the same button on the pin's
    // new row, and Space walks the pin on.
    function stepPin(pin, index, delta, keepFocus) {
        const target = PageLogic.stepTarget(index, delta, page.pins.length)
        if (target < 0 || !LayoutService.dockPin(pin, target)) return
        if (keepFocus) Qt.callLater(() => {
            const row = pinRepeater.itemAt(target)
            if (row) row.focusStep(delta)
        })
    }
    PageActivity {
        onOpened: if (page.pinsNeedDefaults && !DefaultAppsService.categories.length && !DefaultAppsService.loading)
            DefaultAppsService.refresh()
    }

    // A whole dock at once (config/dock-presets/): the taskbar first.
    SettingsSection {
        Layout.fillWidth: true
        title: "Presets"
        hint: "A whole dock at once: its layout and how it shows. Your pinned apps stay; change anything afterwards here or in the layout editor. Dock gets out of the way as soon as a window touches it; Taskbar is always there, with the status, notifications and the clock on the right."

        Repeater {
            model: LayoutService.builtinDockPresets
            ShellCard {
                id: card
                required property var modelData
                readonly property bool inUse: page.presetInUse === modelData.id
                // A start button on it: the taskbar, whose mark is the Saturn
                // the button wears, not the apps grid "Edit in the editor"
                // and the Default apps page have too.
                readonly property bool withStart: PageLogic.holds(modelData.layout, "start")
                Layout.fillWidth: true
                interactive: !LayoutService.readOnly
                hovered: cardMouse.containsMouse
                pressed: cardMouse.pressed && cardMouse.containsMouse
                implicitHeight: cardBody.implicitHeight + Metrics.spaceSm * 2
                // The one in use is framed in the accent, beside its chip.
                border.color: inUse ? Colors.accentBorder : Colors.border
                activeFocusOnTab: !LayoutService.readOnly
                Keys.onReturnPressed: apply()
                Keys.onSpacePressed: apply()
                Accessible.name: modelData.label + (inUse ? ", in use" : "")
                function apply() { page.applyPreset(card.modelData) }
                FocusRing { active: card.activeFocus; controlRadius: card.radius }
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !LayoutService.readOnly
                    onClicked: card.apply()
                }
                RowLayout {
                    id: cardBody
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceSm
                    spacing: Metrics.spaceSm
                    // One box for both marks, so the two titles start at the
                    // same x: the glyphs differ in width.
                    Item {
                        Layout.preferredWidth: Metrics.iconXl
                        Layout.preferredHeight: Metrics.iconLg
                        SaturnGlyph {
                            visible: card.withStart
                            anchors.centerIn: parent
                            width: Metrics.startGlyphWidth
                            height: Metrics.startGlyphHeight
                        }
                        ShellIcon {
                            visible: !card.withStart
                            anchors.centerIn: parent
                            glyph: Icons.dock
                            size: Metrics.iconLg
                            color: Colors.accentForeground
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm
                            ShellText { text: card.modelData.label; role: "title" }
                            Rectangle {
                                visible: card.inUse
                                implicitWidth: inUseText.implicitWidth + Metrics.spaceSm * 2
                                implicitHeight: inUseText.implicitHeight + Metrics.spaceXxs * 2
                                radius: Metrics.pillRadius(height)
                                color: Colors.accentSoft
                                ShellText {
                                    id: inUseText
                                    anchors.centerIn: parent
                                    text: "In use"
                                    role: "caption"
                                    color: Colors.accentOnSoft
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        ShellText {
                            Layout.fillWidth: true
                            text: card.modelData.description
                            role: "small"
                            muted: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: page.presetUndoable
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                text: page.appliedLabel + " applied"
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.undo; text: "Undo"; compact: true
                onClicked: page.undoPreset()
            }
        }
        SettingRow {
            labelFills: true
            label: "Layout"
            // The keys as they are bound now: a shortcut moved in Settings >
            // Shortcuts is named here under its new keys. A dock without a
            // start button is told here where one comes from.
            hint: "What the dock holds and where - its apps, a start button, the clock or any other bar widget - in the layout editor ("
                + ShortcutService.keyHint("SUPER + ALT + E", true) + ", \"Dock\"). The Taskbar preset brings a start button too."
            ShellButton {
                focusOnTab: true
                icon: Icons.arrange; text: "Edit in the editor"; compact: true
                onClicked: {
                    if (!page.enabled) SettingsService.set("dock.enabled", true)
                    PanelService.close("settings")
                    LayoutService.editTarget = "dock"
                    LayoutService.editMode = true
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        // Not "Dock" a third time: the page and a preset are called that.
        title: "Behavior"
        hint: "Your pinned and running apps at the screen edge, as a dock in the middle or a taskbar along the whole edge. It works beside the notch, the bar or the widgets."

        SettingRow {
            labelFills: true
            label: "Show the dock"
            hint: ShortcutService.keyHint("SUPER + SHIFT + D", true) + " turns it on as well, and after that shows it and gives it the keyboard."
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
        SettingRow {
            label: "Width"
            hint: "Fit: as long as what is on it, in the middle. Whole edge: along the full edge of the screen, like a taskbar."
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Width"
                current: SettingsService.value("dock.span")
                options: [{ value: "fit", label: "Fit" }, { value: "full", label: "Whole edge" }]
                onSelected: value => SettingsService.set("dock.span", value)
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
            scope: "dock.screens"
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
        hint: "Right-click an app on the dock to pin or unpin it; drag a pin to move it, a running app among the pins to pin it. The start menu's pins are under Settings > Launcher."

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
        // With docks on more than one screen: every screen's running apps on
        // each, or each dock its own screen's - a taskbar per screen.
        SettingRow {
            visible: Quickshell.screens.length > 1 && SettingsService.value("dock.showRunning") !== false
            label: "Running apps of"
            hint: "Every dock lists the running apps of all screens, or each lists only those with a window on its own screen. Pinned apps are on every dock either way."
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Running apps of"
                current: SettingsService.value("dock.runningOn") === "screen" ? "screen" : "all"
                options: [{ value: "all", label: "Every screen" }, { value: "screen", label: "Its own screen" }]
                onSelected: value => SettingsService.set("dock.runningOn", value)
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
        // A click on the app in front: its next window, as the dock always
        // did, or minimize it (the Taskbar preset's; DockLogic.clickPlan).
        SettingRow {
            label: "Click on the app in front"
            hint: "Minimize: as on a Windows or KDE taskbar - the next click brings the window back. Next window: its other windows in turn."
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Click on the app in front"
                current: SettingsService.value("dock.activeClick") === "minimize" ? "minimize" : "cycle"
                options: [{ value: "cycle", label: "Next window" }, { value: "minimize", label: "Minimize" }]
                onSelected: value => SettingsService.set("dock.activeClick", value)
            }
        }
        SettingRow {
            labelFills: true
            label: "Unread counts"
            hint: "On an app's icon: a web app's own count from its window title - Teams writes (3) -, else its notifications that came while the notification center was closed."
            ShellToggle {
                focusOnTab: true
                enabledState: page.enabled
                checked: SettingsService.value("dock.badges") === true
                onToggled: value => SettingsService.set("dock.badges", value)
            }
        }
        SettingRow {
            labelFills: true
            label: "Window previews"
            hint: "The pointer resting on a running app shows its windows instead of its name. A click brings one to the front, a middle-click closes it."
            ShellToggle {
                focusOnTab: true
                enabledState: page.enabled
                checked: SettingsService.value("dock.previews") === true
                onToggled: value => SettingsService.set("dock.previews", value)
            }
        }
        SettingRow {
            labelFills: true
            label: "Volume under the wheel"
            hint: "The wheel over a running app turns its sound up or down. A web app plays through its browser, so over it the wheel turns the browser's sound."
            ShellToggle {
                focusOnTab: true
                enabledState: page.enabled
                checked: SettingsService.value("dock.wheelVolume") === true
                onToggled: value => SettingsService.set("dock.wheelVolume", value)
            }
        }
        // Only for a dock that has the button; on one without it the choice
        // did nothing, and nothing said so. Layout's hint says how to get one.
        SettingRow {
            visible: LayoutService.dockHasStart
            label: "Start button"
            hint: "What the Saturn on the dock opens: the start menu (pinned and frequent apps, all apps, your folders, lock and power) or the launcher."
            SegmentedControl {
                focusOnTab: true
                enabledState: page.enabled
                Layout.fillWidth: true
                accessibleName: "Start button"
                current: SettingsService.value("dock.startOpens") === "launcher" ? "launcher" : "startMenu"
                options: [{ value: "startMenu", label: "Start menu" }, { value: "launcher", label: "Launcher" }]
                onSelected: value => SettingsService.set("dock.startOpens", value)
            }
        }
        SettingRow {
            label: "Pinned apps"
            hint: "At most " + LayoutService.dockPinLimit + ". Files, terminal and browser follow Default apps; an app no longer installed keeps its place until it is unpinned here."
            ShellText {
                Layout.fillWidth: true
                text: page.pins.length + " of " + LayoutService.dockPinLimit + " pinned"
                role: "small"
                muted: true
            }
            // A page of this panel, so the forward glyph, as for the other
            // jumps inside Settings, after the words where it reads as going
            // on; leavesPanel is for what opens Settings from somewhere else.
            ShellButton {
                focusOnTab: true
                trailingIcon: Icons.forward; text: "Default apps"; variant: "ghost"; compact: true
                onClicked: PanelService.open("settings", { page: "defaultApps" })
            }
        }

        // The pins in their order on the dock, as the launcher's are listed
        // on its page: moved by keyboard, and taken off - a pin whose app
        // was uninstalled draws nothing on the dock, so this is the only
        // place it can be seen and removed.
        Repeater {
            id: pinRepeater
            model: page.pinRows
            ListRow {
                id: pinRow
                required property var modelData
                required property int index
                // At an end now, the button that still moves it.
                function focusStep(delta) {
                    const wanted = delta < 0 ? earlierButton : laterButton
                    const other = delta < 0 ? laterButton : earlierButton
                    const button = wanted.enabledState ? wanted : other
                    button.forceActiveFocus()
                }
                interactive: false
                Layout.fillWidth: true
                compact: true
                level: 1
                iconSource: modelData.icon.length ? LauncherService.iconSource(modelData.icon) : ""
                icon: modelData.settings ? Icons.settingsApp : modelData.missing ? Icons.warning : Icons.apps
                title: modelData.name
                subtitle: modelData.subtitle
                RowLayout {
                    spacing: Metrics.spaceXxs
                    ShellButton {
                        id: earlierButton
                        focusOnTab: true
                        icon: Icons.raise
                        variant: "ghost"
                        compact: true
                        toolTip: "Earlier on the dock"
                        enabledState: !LayoutService.readOnly && PageLogic.stepTarget(pinRow.index, -1, page.pins.length) >= 0
                        // A click takes no focus, so the focus says the keyboard pressed it.
                        onClicked: page.stepPin(pinRow.modelData.pin, pinRow.index, -1, activeFocus)
                    }
                    ShellButton {
                        id: laterButton
                        focusOnTab: true
                        icon: Icons.collapse
                        variant: "ghost"
                        compact: true
                        toolTip: "Later on the dock"
                        enabledState: !LayoutService.readOnly && PageLogic.stepTarget(pinRow.index, 1, page.pins.length) >= 0
                        onClicked: page.stepPin(pinRow.modelData.pin, pinRow.index, 1, activeFocus)
                    }
                    // Asks first, like the launcher's pins on its page.
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.remove
                        variant: "ghost"
                        compact: true
                        toolTip: "Unpin from the dock"
                        enabledState: !LayoutService.readOnly
                        confirm: true
                        confirmText: "Unpin?"
                        onClicked: LayoutService.dockUnpin(pinRow.modelData.pin)
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: page.pins.length === 0
            row: true
            icon: Icons.pin
            title: "Nothing pinned to the dock"
        }
    }

    // Minimized windows (services/MinimizeService.qml) are not the dock's
    // alone: the overview and Alt+Tab list them too, so this works with the
    // dock off.
    SettingsSection {
        Layout.fillWidth: true
        title: "Minimize"
        hint: ShortcutService.keyHint("SUPER + H", true) + " minimizes the window in front, " + ShortcutService.keyHint("SUPER + SHIFT + H", true) + " brings back the last one. Minimized windows stay on the dock (a hollow dot), in the overview and in Alt+Tab, and go back to their workspaces at every start."

        SettingRow {
            labelFills: true
            label: "Minimize buttons in apps"
            // Honest about the compositor: the shell acts on Hyprland's
            // `minimized` event, and Hyprland 0.56.2 posted none for GTK3 and
            // GTK4 apps on Wayland or XWayland (testing.md pitfall 149).
            hint: "Minimizes a window when its app's own minimize button asks, for the apps whose request Hyprland reports. Hyprland 0.56 reports none from GTK apps, on Wayland or X11, so their buttons still do nothing; "
                + ShortcutService.keyHint("SUPER + H", true) + " and the dock's menu minimize every window. Only for the app in front: a game that minimizes itself when it loses the focus stays where it is."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("windows.minimizeRequests") !== false
                onToggled: value => SettingsService.set("windows.minimizeRequests", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Look"
        hint: "The panels' color (Settings > Appearance > Panels), at a transparency of its own."

        SettingRow {
            id: transparencyRow
            readonly property bool own: PanelStyleService.hasOwnOpacity("dock")
            label: "Transparency"
            hint: own ? "Its own value. The reset button goes back to the panels' default." : "The panels' default."
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                // To nothing at all: the apps on the wallpaper.
                from: PanelStyleService.minOpacityFor("dock"); to: 1
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
        hint: ShortcutService.keyHint("SUPER + SHIFT + D", true) + " shows the dock and gives it the keys: the arrow keys move along it, Enter starts or raises an app or opens an item, Shift+Enter opens a new window, the menu key the app's menu. Esc gives the keys back."
    }
}
