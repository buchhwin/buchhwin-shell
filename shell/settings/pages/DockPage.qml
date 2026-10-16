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
        description: "A whole dock at once: its layout and how it shows; your pinned apps stay. Change anything afterwards here or in the layout editor."

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
                text: page.appliedLabel + " applied. Undo puts the dock back as it was."
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
            hint: "What the dock holds - its apps, a start button, the clock, status and any other widget the bar can carry - and where: in the layout editor (Super+Alt+E, \"Dock\")."
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
        description: "Your pinned apps and the apps that have windows, at the edge of the screen - a dock in the middle or a taskbar along the whole edge. It works next to the notch, the bar or the widgets."

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
        description: "The dock keeps its own pinned apps: pin and unpin them on the dock (right click) or in the list below. Drag a pinned app along the dock to move it, or a running one among the pins to pin it. Files, terminal and browser follow Settings > Default apps. The start menu's pinned apps are its own, under Settings > Launcher."

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
        // Only for a dock that has the button; on one without it the choice
        // did nothing, and nothing said so.
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
        ShellText {
            Layout.fillWidth: true
            visible: !LayoutService.dockHasStart
            text: "There is no start button on the dock. Add one in the layout editor (Layout, above), or apply the Taskbar preset."
            role: "small"
            muted: true
            wrapMode: Text.Wrap
        }
        SettingRow {
            label: "Pinned apps"
            hint: "At most " + LayoutService.dockPinLimit + ". An app that is no longer installed still takes a place until it is unpinned here."
            ShellText {
                Layout.fillWidth: true
                text: page.pins.length + " of " + LayoutService.dockPinLimit + " pinned"
                role: "small"
                muted: true
            }
            // A page of this panel, so the forward glyph, as for the other
            // jumps inside Settings; leavesPanel is for what opens Settings
            // from somewhere else.
            ShellButton {
                focusOnTab: true
                icon: Icons.forward; text: "Default apps"; variant: "ghost"; compact: true
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

    SettingsSection {
        Layout.fillWidth: true
        title: "Look"
        description: "The dock wears the panels' color (Settings > Appearance > Panels) at a transparency of its own."

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
        description: ShortcutService.keyHint("SUPER + SHIFT + D") + " shows the dock and gives it the keys: the arrow keys move along it, Enter starts or raises an app, Shift+Enter opens a new window, the menu key opens the app's menu, Esc gives the keys back."
    }
}
