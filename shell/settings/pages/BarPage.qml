import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/dock/DockLogic.js" as DockLogic

// Desktop mode and pill bar editor: pills per zone, items per pill. Select an
// item chip to move, restyle, split or remove it. Changes apply live and can
// be undone like layout edits.
ColumnLayout {
    id: page
    spacing: Metrics.pageGap

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

    // A pill moved by the keyboard keeps the keyboard. Inside its zone the
    // card moves along with the pill (the cards are keyed by pill id); into
    // the next zone it is a new card there, and the focus goes to the same
    // button on it, or to the other one at the end of the bar.
    function movePill(pillId, delta, keepFocus) {
        if (!LayoutService.barMovePill(pillId, delta) || !keepFocus) return
        Qt.callLater(() => {
            for (let zone = 0; zone < zoneRepeater.count; ++zone) {
                const section = zoneRepeater.itemAt(zone)
                const card = section ? section.cardFor(pillId) : null
                if (card) { card.focusMove(delta); return }
            }
        })
    }

    DesktopModeSection { Layout.fillWidth: true }

    SettingsSection {
        Layout.fillWidth: true
        visible: LayoutService.widgetsShown
        title: "The bar is hidden"
        description: "Widgets mode shows the widgets on the wallpaper instead of the bar. The pills below are kept and come back with the Bar mode."
        ShellButton {
            focusOnTab: true
            icon: Icons.arrange; text: "Open widgets"
            onClicked: PanelService.open("settings", { page: "widgets" })
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Notch"
        description: "Hover the notch for the time, weather, events, media and status. Hotkey panels open below it. Applies to every mode of this profile."
        visible: LayoutService.notchShown

        SettingRow {
            Layout.fillWidth: true
            label: "Preset"
            hint: "A whole notch at once - what it shows and how it opens. Save your own from the notch as it is now."
            NotchPresetPicker { Layout.fillWidth: true }
        }
        SettingRow {
            label: "Size"
            hint: "Drag the notch itself in the layout editor (" + ShortcutService.keyHint("SUPER + ALT + E", true) + "): the strip sideways, the hover overview in both directions"
            ShellButton {
                focusOnTab: true
                text: "Open the editor"
                icon: Icons.arrange
                onClicked: { PanelService.close("settings"); LayoutService.editMode = true }
            }
        }
        // notch.screens: every screen by default, as the bar's own list.
        SettingRow {
            id: notchScreens
            visible: Quickshell.screens.length > 1
            readonly property string stored: SettingsService.value("notch.screens")
            readonly property var names: Quickshell.screens.map(screen => screen.name)
            readonly property var shownOn: DockLogic.screensFor(stored, names)
            label: "Show on"
            hint: "Which displays have a notch. With all of them ticked a new display gets one too. The last one cannot be unticked."
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                Repeater {
                    model: Quickshell.screens
                    ChipButton {
                        required property var modelData
                        compact: true
                        focusOnTab: true
                        title: modelData.name
                        active: notchScreens.shownOn.indexOf(modelData.name) >= 0
                        onClicked: {
                            const next = DockLogic.toggleScreen(notchScreens.stored, modelData.name, notchScreens.names)
                            if (next !== null) SettingsService.set("notch.screens", next)
                        }
                    }
                }
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
                        focusOnTab: true
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
                onSelected: value => LayoutService.changeNotch("notch.eventCount", Number(value))
            }
        }

        // The notch *is* the display, instead of opening a surface below it.
        // One switch per kind on purpose: a volume bar in the notch with
        // notifications still under it is an ordinary thing to want.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Volume and brightness in the notch"
            hint: "The notch itself shows the level instead of a box below it. On a screen without a notch - widgets or bar mode, or a second monitor - it appears where it always did."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.displayOsd"); onToggled: value => SettingsService.set("notch.displayOsd", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            visible: SettingsService.value("notch.displayOsd")
            label: "Level as"
            hint: "A ring beside the figure, or a flat track"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("notch.osdStyle")
                options: [{ value: "ring", label: "Ring" }, { value: "bar", label: "Track" }]
                onSelected: value => SettingsService.set("notch.osdStyle", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Notifications in the notch"
            hint: "The newest one, in the notch instead of below it. The others wait; all of them are in the notification center either way."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.displayNotifications"); onToggled: value => SettingsService.set("notch.displayNotifications", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Track changes in the notch"
            hint: "A new song names itself for a few seconds. It has no other place to appear, so with this off nothing happens at all."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.displayMedia"); onToggled: value => SettingsService.set("notch.displayMedia", value) }
        }
        ShellText {
            Layout.fillWidth: true
            text: "While the overview is open the notch stays the overview, and whatever wanted it appears below instead. When two ask at once the newer one wins - a key you just pressed must show what it did."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }

        NotchHoverRows { Layout.fillWidth: true }
        // Notch options take an undo step (LayoutService.changeNotch), the
        // same as the editor's rows for them and the hover rows above: an
        // undo in the editor must reach a change made on this page too.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Reserve space for windows"
            hint: "Windows start below the notch instead of behind it"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notch.reserve"); onToggled: value => LayoutService.changeNotch("notch.reserve", value) }
        }
        SettingRow {
            label: "In fullscreen"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("notch.fullscreen")
                options: [{ value: "hide", label: "Hide" }, { value: "show", label: "Always show" }]
                onSelected: value => LayoutService.changeNotch("notch.fullscreen", value)
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
            hint: "Left and right stand the bar on its side: its zones run from top to bottom, a pill stacks its items, and panels open beside it. Widgets there have room for an icon and little else."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.bar.edge
                options: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" },
                          { value: "left", label: "Left" }, { value: "right", label: "Right" }]
                onSelected: value => LayoutService.setBarOption("edge", value)
            }
        }
        // Only worth asking when there is more than one screen to ask about.
        SettingRow {
            visible: Quickshell.screens.length > 1
            label: "Show on"
            // With every display ticked "all" is stored as "all", not as a
            // list of the screens that happen to be here today, so a display
            // plugged in later gets a bar as well.
            hint: "Which displays carry the bar. With every display ticked, a new one gets a bar too."
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                Repeater {
                    model: Quickshell.screens
                    ChipButton {
                        required property var modelData
                        readonly property var wanted: page.bar.screens || []
                        compact: true
                        title: modelData.name
                        // An empty list means every screen, so nothing ticked
                        // in the file is everything ticked on screen.
                        active: !wanted.length || wanted.indexOf(modelData.name) >= 0
                        focusOnTab: true
                        onClicked: {
                            const all = Quickshell.screens.map(screen => screen.name)
                            const current = wanted.length ? wanted.slice() : all.slice()
                            const at = current.indexOf(modelData.name)
                            if (at >= 0) current.splice(at, 1)
                            else current.push(modelData.name)
                            // Taking the last one away would leave no bar and
                            // no control to bring it back, so it is refused.
                            if (!current.length) return
                            LayoutService.setBarScreens(current, all)
                        }
                    }
                }
            }
        }
        SettingRow {
            label: "Panels open"
            hint: "Where a panel appears along the bar: under the widget that opened it, or always at the start, center or end - from a shortcut too. On a vertical bar these run from top to bottom."
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
            // Asked apart from the panels: the control center under your hand
            // and the notifications out of the way is one wish, not two.
            hint: "The same for notification popups. By the widget means out of the notifications pill, or out of the bar's end without one."
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
        // Edit layout and Undo are the Desktop mode section's, at the top of
        // this page: here they were the same two buttons a second time.
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton { focusOnTab: true; icon: Icons.reset; text: "Restore default"; onClicked: { page.select("", -1); LayoutService.resetBar() } }
            ShellText {
                Layout.fillWidth: true
                text: ShortcutService.keyHint("SUPER + ALT + E", true) + " drags pills between the zones on the desktop itself; the list below does the same by hand."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Workspaces"
        description: "Which workspaces the workspace pill, the widget and the window overview show. Applies to every mode of this profile."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Each monitor its own"
            // Hyprland keeps one set of workspaces and gives each a monitor,
            // so Super+3 means "go to whichever screen holds 3". With this on
            // the monitors get blocks of ten ids, and the first keeps 1 to
            // 10, which is why a single screen sees no change at all.
            hint: "Every monitor has its own 1 to 9: " + ShortcutService.keyHint("SUPER + 3", true)
                + " switches the screen your pointer is on, and the focus never jumps to another one. With one screen nothing changes."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("workspaces.perMonitor") === true
                onToggled: value => SettingsService.set("workspaces.perMonitor", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Keep empty workspaces open"
            hint: "Hyprland closes a workspace the moment it is empty and you switch away. With this on, every workspace you open stays until you close it with \u00D7 on its card in the overview (" + ShortcutService.keyHint("SUPER + W", true) + "); a workspace with windows hands them to its neighbour first, nothing is closed."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("workspaces.keepEmpty") === true
                onToggled: value => SettingsService.set("workspaces.keepEmpty", value)
            }
        }
        SettingRow {
            label: "Show"
            // "Open" is what Hyprland keeps: a workspace goes once it is empty
            // and left, unless "Keep empty workspaces open" above holds it.
            hint: "Open: the workspaces that exist. No gaps: the empty ones between them too, so emptying 2 between 1 and 3 does not renumber the row. Fixed number: always 1 to N, the empty ones dimmed and busy ones above N as well."
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
            hint: "Numbers: each pip shows its number. Dots: plain pips, yours filled. Pills: narrow capsules, yours wider. Dot for the active one: a dot where you are, numbers everywhere else. A workspace you have named keeps its name in every style."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("workspaces.style")
                options: [{ value: "numbers", label: "Numbers" }, { value: "dots", label: "Dots" }, { value: "pills", label: "Pills" },
                          { value: "activeDot", label: "Dot for the active one" }]
                onSelected: value => SettingsService.set("workspaces.style", value)
            }
        }
        SettingRow {
            visible: SettingsService.value("workspaces.mode") === "fixed"
            label: "Number"
            // A key or wheel step is smaller than one slot, so it moves at
            // least one (IntegerSlider).
            IntegerSlider {
                focusOnTab: true
                id: countSlider
                Layout.fillWidth: true
                from: 1; to: 10
                value: SettingsService.value("workspaces.count")
                onPicked: value => SettingsService.set("workspaces.count", value)
            }
            ShellText {
                text: String(Math.round(countSlider.pressed ? countSlider.liveValue : countSlider.value))
                role: "small"; muted: true
                Layout.minimumWidth: Metrics.iconXl
            }
        }
    }

    Repeater {
        id: zoneRepeater
        model: LayoutService.barShown ? LayoutService.zones : []

        SettingsSection {
            id: zoneSection
            required property string modelData
            readonly property string zone: modelData
            readonly property var pills: page.bar[zone] || []
            property string addType: "clock"
            Layout.fillWidth: true
            title: page.zoneLabels[zone]

            // This zone's card for a pill, or null.
            function cardFor(pillId) {
                for (let at = 0; at < pillRepeater.count; ++at) {
                    const card = pillRepeater.itemAt(at)
                    if (card && card.modelData === pillId) return card
                }
                return null
            }

            EmptyState {
                Layout.fillWidth: true
                visible: zoneSection.pills.length === 0
                row: true
                icon: "󰘔"
                title: page.unit === "group" ? "No groups yet" : "No pills yet"
            }
            // Keyed by pill id: every change to the bar is a new list of new
            // pills, and a Repeater over it built every card of the zone
            // again, so after Move right, Merge or a display segment the
            // keyboard's place was gone. A card stays with its pill now,
            // through a move inside the zone too.
            Repeater {
                id: pillRepeater
                model: ScriptModel { values: zoneSection.pills.map(pill => pill.id) }

                ShellCard {
                    id: pillCard
                    // A card inside a settings section.
                    level: 2
                    required property string modelData
                    required property int index
                    readonly property var pill: zoneSection.pills.find(entry => entry.id === modelData) || ({ id: modelData, items: [] })
                    readonly property bool selected: page.selectedPill === pill.id
                    // After a move into another zone: the button that moved
                    // it, or the other one where the bar ends.
                    function focusMove(delta) {
                        const wanted = delta < 0 ? moveLeftButton : moveRightButton
                        const other = delta < 0 ? moveRightButton : moveLeftButton
                        const zoneAt = LayoutService.zones.indexOf(zoneSection.zone)
                        const atEnd = delta < 0 ? zoneAt === 0 && pillCard.index === 0
                            : zoneAt === LayoutService.zones.length - 1 && pillCard.index === zoneSection.pills.length - 1
                        const button = atEnd ? other : wanted
                        button.forceActiveFocus()
                    }
                    Layout.fillWidth: true
                    highlighted: selected
                    interactive: true
                    hovered: pillMouse.containsMouse
                    pressed: pillMouse.pressed && pillMouse.containsMouse
                    implicitHeight: pillColumn.implicitHeight + Metrics.spaceMd * 2

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.select(pillCard.pill.id, -1)
                    }

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
                                        focusOnTab: true
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

                            // A click takes no focus, so the focus says the keyboard pressed it.
                            ShellButton { id: moveLeftButton; focusOnTab: true; icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move left"; onClicked: page.movePill(pillCard.pill.id, -1, activeFocus) }
                            ShellButton { id: moveRightButton; focusOnTab: true; icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move right"; onClicked: page.movePill(pillCard.pill.id, 1, activeFocus) }
                            ShellButton {
                                focusOnTab: true
                                visible: pillCard.index < zoneSection.pills.length - 1
                                icon: "󰘞"; variant: "ghost"; compact: true; toolTip: "Merge with next " + page.unit
                                onClicked: LayoutService.barMergeWithNext(pillCard.pill.id)
                            }
                            // A whole pill with everything in it: it asks first.
                            ShellButton {
                                focusOnTab: true
                                icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove " + page.unit
                                confirm: true; confirmText: "Remove?"
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
                                focusOnTab: true
                                Layout.fillWidth: true
                                current: itemActions.item ? itemActions.item.display : "full"
                                options: itemActions.item ? WidgetRegistry.pillDisplays(itemActions.item.type) : []
                                onSelected: value => LayoutService.barSetDisplay(pillCard.pill.id, page.selectedItem, value)
                            }
                            // At an end, the keyboard goes on to the button
                            // that still moves the item.
                            function stepItem(delta, keepFocus) {
                                LayoutService.barMoveItem(pillCard.pill.id, page.selectedItem, delta)
                                page.selectedItem += delta
                                if (!keepFocus) return
                                const wanted = delta < 0 ? itemLeftButton : itemRightButton
                                const button = wanted.enabledState ? wanted : delta < 0 ? itemRightButton : itemLeftButton
                                button.forceActiveFocus()
                            }
                            ShellButton {
                                id: itemLeftButton
                                focusOnTab: true
                                icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move item left"
                                enabledState: page.selectedItem > 0
                                onClicked: itemActions.stepItem(-1, activeFocus)
                            }
                            ShellButton {
                                id: itemRightButton
                                focusOnTab: true
                                icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move item right"
                                enabledState: page.selectedItem < pillCard.pill.items.length - 1
                                onClicked: itemActions.stepItem(1, activeFocus)
                            }
                            ShellButton {
                                focusOnTab: true
                                visible: pillCard.pill.items.length > 1
                                icon: "󰤼"; text: "Split off"; compact: true
                                onClicked: { LayoutService.barSplitItem(pillCard.pill.id, page.selectedItem); page.select("", -1) }
                            }
                            ShellButton {
                                focusOnTab: true
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
                    focusOnTab: true
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    options: page.typeOptions
                    current: zoneSection.addType
                    onSelected: value => zoneSection.addType = value
                }
                ShellButton {
                    focusOnTab: true
                    Layout.alignment: Qt.AlignTop
                    icon: Icons.add; text: "New " + page.unit
                    onClicked: LayoutService.barAddPill(zoneSection.zone, zoneSection.addType, "")
                }
                ShellButton {
                    focusOnTab: true
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
