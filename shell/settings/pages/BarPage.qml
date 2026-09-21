import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Desktop mode and pill bar editor: pills per zone, items per pill. Select an
// item chip to move, restyle, split or remove it. Changes apply live and can
// be undone like layout edits.
ColumnLayout {
    id: page
    spacing: Metrics.spaceLg

    property string selectedPill: ""
    // The notch stores items by id, the chips speak in types.
    function notchIdOf(type) {
        for (const zone of ["expanded", "collapsed"])
            for (const pill of (LayoutService.notchLayout[zone] || []))
                if (pill.items[0].type === type) return pill.id
        return ""
    }
    property int selectedItem: -1
    readonly property var bar: LayoutService.bar
    readonly property var typeOptions: WidgetRegistry.availableTypes()
        .map(entry => ({ value: entry.name, label: entry.label }))
        .sort((a, b) => a.label.localeCompare(b.label))
    readonly property var zoneLabels: ({ left: "Left", center: "Center", right: "Right" })
    // The bar style draws pills as item groups inside one bar.
    readonly property string unit: bar.style === "bar" ? "group" : "pill"

    function select(pillId, index) {
        selectedPill = pillId
        selectedItem = index
    }

    function typeLabel(type) {
        const entry = WidgetRegistry.type(type)
        return entry ? entry.label : type
    }

    function typeIcon(type) {
        const entry = WidgetRegistry.type(type)
        return entry ? entry.icon : "󰘔"
    }

    DesktopModeSection { Layout.fillWidth: true }

    SettingsSection {
        Layout.fillWidth: true
        visible: LayoutService.widgetsShown
        title: "The bar is hidden"
        description: "Widgets mode shows the widgets on the wallpaper instead of the bar. The pills below are kept and come back with the Bar mode."
        ShellButton {
            icon: Icons.edit; text: "Open Widgets"
            onClicked: PanelService.open("settings", { page: "widgets" })
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Notch"
        description: "Hover the notch for the time, weather, events, media and status. Hotkey panels open below it. Applies to all profiles."
        visible: LayoutService.notchShown

        SettingRow {
            label: "Size"
            hint: "Drag the notch itself in the layout editor (Super+Alt+E): the strip sideways, the hover overview in both directions"
            ShellButton {
                text: "Open the editor"
                icon: Icons.edit
                onClicked: { PanelService.close("settings"); LayoutService.editMode = true }
            }
        }
        SettingRow {
            label: "Show"
            hint: "What the expanded notch carries"
            // The same list the notch itself is arranged from, so a chip here
            // and a drag on the notch are two ways to the one place.
            Flow {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                Repeater {
                    model: [{ type: "weather", label: "Weather" }, { type: "media", label: "Media" },
                            { type: "events", label: "Events" }, { type: "status", label: "Status" }]
                    ChipButton {
                        required property var modelData
                        title: modelData.label
                        active: NotchService.shows(modelData.type)
                        onClicked: active ? LayoutService.notchRemove(page.notchIdOf(modelData.type))
                                          : LayoutService.notchAdd(modelData.type, "expanded")
                    }
                }
            }
        }
        SettingRow {
            label: "Events"
            hint: "Listed when the overview is wide enough for a list"
            visible: NotchService.wide && NotchService.shows("events")
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("notch.eventCount"))
                options: [{ value: "1", label: "1" }, { value: "2", label: "2" }, { value: "3", label: "3" }, { value: "4", label: "4" }]
                onSelected: value => SettingsService.set("notch.eventCount", Number(value))
            }
        }

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Expand on hover"
            hint: "Otherwise a click opens the overview"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.expandOnHover"); onToggled: value => SettingsService.set("notch.expandOnHover", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Reserve space for windows"
            hint: "Windows start below the notch instead of behind it"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.reserve"); onToggled: value => SettingsService.set("notch.reserve", value) }
        }
        SettingRow {
            label: "In fullscreen"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("notch.fullscreen")
                options: [{ value: "hide", label: "Hide" }, { value: "show", label: "Always show" }]
                onSelected: value => SettingsService.set("notch.fullscreen", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Bar"
        description: "Pills float as separate capsules; the bar joins all items into one continuous bar. Color and transparency follow Appearance > Panels."
        visible: LayoutService.barShown

        SettingRow {
            label: "Style"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.style
                options: [{ value: "pills", label: "Pills" }, { value: "bar", label: "Bar" }]
                onSelected: value => LayoutService.setBarOption("style", value)
            }
        }
        SettingRow {
            visible: page.bar.style === "bar"
            label: "Position"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.position
                options: [{ value: "floating", label: "Floating" }, { value: "attached", label: "Attached" }]
                onSelected: value => LayoutService.setBarOption("position", value)
            }
        }
        SettingRow {
            // Not gated on the bar style: a floating row of pills may sit at
            // the bottom of the screen just as well as a continuous bar can.
            label: "Edge"
            hint: "Left and right turn the bar on its side: the three zones run from top to bottom, a pill stacks its items instead of placing them in a row, and a panel opens beside the bar rather than under it. Widgets there have room for an icon and little else."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.edge
                options: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" },
                          { value: "left", label: "Left" }, { value: "right", label: "Right" }]
                onSelected: value => LayoutService.setBarOption("edge", value)
            }
        }
        SettingRow {
            label: "Panels open"
            hint: "Where a panel appears along the bar. By the widget is what the shell has always done - the control center under the tile you clicked. The other three pin every panel to one place whatever opened it, including the ones opened by a keyboard shortcut. On a vertical bar these run from top to bottom."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.panelSpot
                options: [{ value: "widget", label: "By the widget" }, { value: "start", label: "Start" },
                          { value: "centre", label: "Center" }, { value: "end", label: "End" }]
                onSelected: value => LayoutService.setBarOption("panelSpot", value)
            }
        }
        SettingRow {
            label: "Notifications open"
            hint: "The same question for notification popups, asked separately: wanting the control center under your hand and the notifications out of the way is one wish, not two conflicting ones. By the widget means out of the notifications pill when the bar has one, and out of the bar's end when it does not."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.notificationSpot
                options: [{ value: "widget", label: "By the widget" }, { value: "start", label: "Start" },
                          { value: "centre", label: "Center" }, { value: "end", label: "End" }]
                onSelected: value => LayoutService.setBarOption("notificationSpot", value)
            }
        }
        BarPreview {
            Layout.fillWidth: true
            barStyle: page.bar.style
            position: page.bar.position
            edge: page.bar.edge
            reserve: page.bar.reserve
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Reserve space for windows"
            hint: "Windows start below the bar instead of behind it"
            ShellToggle { focusOnTab: true; checked: page.bar.reserve; onToggled: value => LayoutService.setBarOption("reserve", value) }
        }
        SettingRow {
            label: "In fullscreen"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.fullscreen
                options: [{ value: "hide", label: "Hide" }, { value: "show", label: "Always show" }]
                onSelected: value => LayoutService.setBarOption("fullscreen", value)
            }
        }
        SettingRow {
            label: "Size"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(page.bar.scale)
                options: [{ value: "0.9", label: "Small" }, { value: "1", label: "Normal" }, { value: "1.15", label: "Large" }]
                onSelected: value => LayoutService.setBarOption("scale", Number(value))
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton {
                icon: Icons.edit; text: "Edit layout"; variant: "accent"
                onClicked: { PanelService.close(); LayoutService.editMode = true }
            }
            ShellButton { icon: Icons.undo; text: "Undo"; enabledState: LayoutService.undoStack.length > 0; onClicked: LayoutService.undo() }
            ShellButton { icon: Icons.reset; text: "Restore default"; onClicked: { page.select("", -1); LayoutService.resetBar() } }
        }
        ShellText {
            Layout.fillWidth: true
            text: "Super + Alt + E drags pills between the zones on the desktop itself; the list below does the same by hand."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Workspaces"
        description: "Which workspaces the workspace pill, the widget and the window overview show. Applies to all profiles."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Each monitor its own"
            hint: "Hyprland keeps one set of workspaces and gives each of them a monitor, so Super+3 means \u201Cgo to whichever screen is holding 3\u201D \u2014 with several monitors a workspace becomes a monitor. With this on, every monitor has its own 1 to 9: Super+3 switches the screen your pointer is on and the focus never jumps to another one. Behind the scenes the monitors get blocks of ten ids, and the first monitor keeps 1 to 10, so with a single screen nothing changes at all."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("workspaces.perMonitor") === true
                onToggled: value => SettingsService.set("workspaces.perMonitor", value)
            }
        }
        SettingRow {
            label: "Show"
            hint: "Open shows only the workspaces that exist, which is what Hyprland keeps - a workspace disappears the moment its last window closes. No gaps fills the empty ones between them back in, so closing everything on 2 while 1 and 3 are in use does not renumber the row under your hand. A fixed number always shows 1 to N and dims the empty ones; occupied workspaces above N still appear."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("workspaces.mode")
                options: [{ value: "open", label: "Open" }, { value: "gapless", label: "No gaps" },
                          { value: "fixed", label: "Fixed number" }]
                onSelected: value => SettingsService.set("workspaces.mode", value)
            }
        }
        SettingRow {
            label: "Style"
            hint: "Numbers writes each workspace's number in its pip. Dots writes none of them, so the row becomes a row of pips and the one you are on is the filled one. A dot for the active one keeps the numbers of everywhere you could go and takes away only the number of where you already are. A workspace you have named keeps its name whichever of the three is chosen."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("workspaces.style")
                options: [{ value: "numbers", label: "Numbers" }, { value: "dots", label: "Dots" },
                          { value: "activeDot", label: "Dot for the active one" }]
                onSelected: value => SettingsService.set("workspaces.style", value)
            }
        }
        SettingRow {
            visible: SettingsService.value("workspaces.mode") === "fixed"
            label: "Number"
            ShellSlider {
                focusOnTab: true
                id: countSlider
                Layout.fillWidth: true
                from: 1; to: 10
                value: SettingsService.value("workspaces.count")
                // A wheel step is smaller than one slot, so it moves at least one.
                onReleased: value => {
                    const delta = value - SettingsService.value("workspaces.count")
                    const step = Math.abs(delta) < 1 && Math.abs(delta) > 0.01 ? Math.sign(delta) : Math.round(delta)
                    SettingsService.set("workspaces.count", Math.max(1, Math.min(10, SettingsService.value("workspaces.count") + step)))
                }
            }
            ShellText {
                text: String(Math.round(countSlider.pressed ? countSlider.liveValue : countSlider.value))
                role: "small"; muted: true
                Layout.minimumWidth: Metrics.iconXl
            }
        }
    }

    Repeater {
        model: LayoutService.barShown ? LayoutService.zones : []

        SettingsSection {
            id: zoneSection
            required property string modelData
            readonly property string zone: modelData
            readonly property var pills: page.bar[zone] || []
            property string addType: "clock"
            Layout.fillWidth: true
            title: page.zoneLabels[zone]
            description: pills.length ? "" : page.unit === "group" ? "No groups yet" : "No pills yet"

            Repeater {
                model: zoneSection.pills

                ShellCard {
                    id: pillCard
                    // A card inside a settings section.
                    level: 2
                    required property var modelData
                    required property int index
                    readonly property var pill: modelData
                    readonly property bool selected: page.selectedPill === pill.id
                    Layout.fillWidth: true
                    highlighted: selected
                    implicitHeight: pillColumn.implicitHeight + Metrics.spaceMd * 2

                    MouseArea { anchors.fill: parent; onClicked: page.select(pillCard.pill.id, -1) }

                    ColumnLayout {
                        id: pillColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Metrics.spaceMd
                        spacing: Metrics.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXs

                            Flow {
                                Layout.fillWidth: true
                                spacing: Metrics.spaceXs
                                Repeater {
                                    model: pillCard.pill.items
                                    ShellButton {
                                        required property var modelData
                                        required property int index
                                        compact: true
                                        icon: page.typeIcon(modelData.type)
                                        text: page.typeLabel(modelData.type) + (modelData.display === "full" ? ""
                                            : " · " + (WidgetRegistry.pillDisplays(modelData.type).find(option => option.value === modelData.display) || { label: "" }).label)
                                        variant: pillCard.selected && page.selectedItem === index ? "accent" : "surface"
                                        onClicked: page.select(pillCard.pill.id, index)
                                    }
                                }
                            }

                            ShellButton { icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move left"; onClicked: LayoutService.barMovePill(pillCard.pill.id, -1) }
                            ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move right"; onClicked: LayoutService.barMovePill(pillCard.pill.id, 1) }
                            ShellButton {
                                visible: pillCard.index < zoneSection.pills.length - 1
                                icon: "󰘞"; variant: "ghost"; compact: true; toolTip: "Merge with next " + page.unit
                                onClicked: LayoutService.barMergeWithNext(pillCard.pill.id)
                            }
                            ShellButton {
                                icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove " + page.unit
                                onClicked: { page.select("", -1); LayoutService.barRemovePill(pillCard.pill.id) }
                            }
                        }

                        // Actions for the selected item of this pill.
                        RowLayout {
                            readonly property var item: pillCard.selected && page.selectedItem >= 0 ? pillCard.pill.items[page.selectedItem] : null
                            id: itemActions
                            visible: item !== undefined && item !== null
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXs

                            SegmentedControl {
                                Layout.preferredWidth: Metrics.editorSidebarWidth * (options.length > 2 ? 1.4 : 1)
                                current: itemActions.item ? itemActions.item.display : "full"
                                options: itemActions.item ? WidgetRegistry.pillDisplays(itemActions.item.type) : []
                                onSelected: value => LayoutService.barSetDisplay(pillCard.pill.id, page.selectedItem, value)
                            }
                            Item { Layout.fillWidth: true }
                            ShellButton {
                                icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move item left"
                                enabledState: page.selectedItem > 0
                                onClicked: { LayoutService.barMoveItem(pillCard.pill.id, page.selectedItem, -1); page.selectedItem -= 1 }
                            }
                            ShellButton {
                                icon: "󰁔"; variant: "ghost"; compact: true; toolTip: "Move item right"
                                enabledState: page.selectedItem < pillCard.pill.items.length - 1
                                onClicked: { LayoutService.barMoveItem(pillCard.pill.id, page.selectedItem, 1); page.selectedItem += 1 }
                            }
                            ShellButton {
                                visible: pillCard.pill.items.length > 1
                                icon: "󰤼"; text: "Split off"; compact: true
                                onClicked: { LayoutService.barSplitItem(pillCard.pill.id, page.selectedItem); page.select("", -1) }
                            }
                            ShellButton {
                                icon: Icons.remove; text: "Remove"; variant: "danger"; compact: true
                                onClicked: { LayoutService.barRemoveItem(pillCard.pill.id, page.selectedItem); page.select(pillCard.pill.id, -1) }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellSelect {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    options: page.typeOptions
                    current: zoneSection.addType
                    onSelected: value => zoneSection.addType = value
                }
                ShellButton {
                    Layout.alignment: Qt.AlignTop
                    icon: Icons.add; text: "New " + page.unit
                    onClicked: LayoutService.barAddPill(zoneSection.zone, zoneSection.addType, "")
                }
                ShellButton {
                    Layout.alignment: Qt.AlignTop
                    readonly property var place: page.selectedPill.length ? LayoutService.barPlace(page.selectedPill) : null
                    visible: place !== null && place.zone === zoneSection.zone
                    icon: "󰐖"; text: "Add to " + page.unit
                    onClicked: LayoutService.barAddItem(page.selectedPill, zoneSection.addType, "")
                }
            }
        }
    }
}
