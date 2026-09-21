import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/quick/QuickLogic.js" as Quick
import "../../../services/arrange/ArrangeLogic.js" as Arrange
import "../../../services/arrange/FitLogic.js" as Fit

// The control center's front page. Which tiles it shows and in which order is
// the user's (LayoutService.quick, same zone -> pill -> item model as the
// bar); the tiles themselves are the components at the bottom of this file and
// keep their own conditions, so one with nothing to show still hides itself.
//
// "Arrange" turns the panel into its own editor: the tiles lean, a tile can be
// dropped on another one to take its place, a tile can be taken off, and the
// ones that are off can be put back. It is edited here rather than in the
// layout editor because both are full-screen surfaces with exclusive keyboard
// focus, and two of those at once is the trap that keeps Alt+Tab out of the
// panel system.
ColumnLayout {
    id: root
    signal openPage(string name)
    // The panel this page sits in, for its unclipped overlay: the drag ghost
    // has to be able to leave the card, which clips.
    property var panel: null
    spacing: Metrics.panelGap
    // The columns follow the panel's width, so a panel dragged wider gets
    // another column rather than wider tiles.
    readonly property int columns: Arrange.columnsFor(width, Metrics.quickGridCell, Metrics.quickGridColumns)
    readonly property bool editing: LayoutService.quickEditing
    readonly property var tiles: LayoutService.quick.quick
    // The panel's own tiles that are not on it, and then every desktop widget
    // that is not either - the notch has always offered both and there was no
    // reason this one should not.
    readonly property var missing: LayoutService.tileChoices(
        Quick.missing(LayoutService.quickTypes), LayoutService.quickTypes)

    // Fingerprint tile: reader state (cached) and the lid. KDE Connect is only
    // polled while this page exists (it unloads with the control center).
    Component.onCompleted: {
        FingerprintService.peek()
        KdeConnectService.track()
    }
    // Reported from the layout's resting cells, not from the items: an item
    // glides to its new place over Animations.reorder and a report would fire
    // long before it arrived, describing where it was halfway there.
    function reportCells() {
        const cells = {}
        for (const item of LayoutService.quickItems) {
            const cell = tileArea.cellOf(item.id)
            if (cell) cells[item.id] = { x: Math.round(cell.x), y: Math.round(cell.y),
                                         width: Math.round(cell.width), height: Math.round(cell.height),
                                         w: cell.w, h: cell.h }
        }
        LayoutService.reportQuickCells(cells)
    }

    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: root.reportCells()
    }

    Component.onDestruction: {
        LayoutService.reportQuickCells({})
        KdeConnectService.untrack()
        LayoutService.quickEditing = false
    }

    function componentFor(type) {
        switch (type) {
        case "wifi": return wifiTile
        case "bluetooth": return bluetoothTile
        case "dnd": return dndTile
        case "microphone": return microphoneTile
        case "fingerprint": return fingerprintTile
        case "brightness": return brightnessTile
        case "battery": return batteryTile
        case "media": return mediaTile
        case "audio": return audioTile
        case "drives": return drivesTile
        case "phone": return phoneTile
        case "shortcuts": return shortcutsTile
        }
        // Not one of the panel's own tiles: a desktop widget it accepts.
        return WidgetRegistry.isAvailable(type) ? widgetTile : null
    }

    // The tiles place themselves from ArrangeLogic rather than from a layout:
    // a layout owns its children's geometry and cannot let them glide aside.
    ArrangeArea {
        id: tileArea
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        columns: root.columns
        gap: Metrics.panelGap
        unit: Metrics.quickGridUnit
        editing: root.editing
        // The same ceiling the layout file clamps a stored size to, so a
        // corner cannot be pulled to a height the write then takes back.
        maxRows: LayoutService.gridMaxRows
        // While the panel's own corner is being pulled every cell changes in
        // every frame; gliding behind that reads as lag, not as motion.
        animated: !(root.panel && root.panel.sizing)
        dragLayer: root.panel ? root.panel.overlay : null
        model: LayoutService.quickItems.map(item => ({ id: item.id, w: item.w, h: item.h,
            minW: Quick.minSize(item.type).w, minH: Quick.minSize(item.type).h }))
        onCommitted: (id, index) => LayoutService.quickMoveTo(id, index)

        onPlacementChanged: reportTimer.restart()
        onWidthChanged: reportTimer.restart()

        Repeater {
            model: root.tiles
            QuickSlot {
                required property var modelData
                required property int index
                area: tileArea
                tileId: modelData.id
                type: modelData.items[0].type
                slotIndex: index
                content: root.componentFor(modelData.items[0].type)
            }
        }
    }

    // ---- arranging -------------------------------------------------------

    // One compact row: the tiles that are off, a reset and the way out. The
    // pencil in the header is the Done button, so there is not a second one,
    // and there is no sentence explaining the drag either - the wiggling tiles
    // and the handles on them say it, and the row is read on every visit.
    CardSection {
        Layout.fillWidth: true
        visible: root.editing
        padding: Metrics.spaceSm
        spacing: Metrics.spaceXs

        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            Repeater {
                model: root.missing
                ShellButton {
                    required property var modelData
                    icon: modelData.icon
                    variant: "surface"
                    compact: true
                    toolTip: modelData.label
                    onClicked: LayoutService.quickAdd(modelData.type)
                }
            }
            // Arranging pushes undo steps like every other editor does, so it
            // offers the way back like every other editor does.
            ShellButton {
                icon: Icons.undo
                variant: "ghost"
                compact: true
                enabledState: LayoutService.undoStack.length > 0
                toolTip: "Undo"
                onClicked: LayoutService.undo()
            }
            ShellButton {
                icon: Icons.reset
                variant: "ghost"
                compact: true
                // It discards an arrangement the user built by hand. One undo
                // step covers it, but only if they notice in time.
                confirm: true
                confirmText: "Reset"
                toolTip: "Back to the default tiles"
                onClicked: LayoutService.quickReset()
            }
        }
    }

    Component {
        id: wifiTile
        QuickTile {
            shape: fitClass
            readonly property bool shown: true
            icon: NetworkService.icon
            title: "Wi-Fi"
            subtitle: NetworkService.summary
            checked: NetworkService.wifiEnabled
            available: NetworkService.wifiAvailable
            showChevron: true
            onToggled: value => NetworkService.setWifiEnabled(value)
            onDetailsRequested: root.openPage("network")
        }
    }

    Component {
        id: bluetoothTile
        QuickTile {
            shape: fitClass
            readonly property bool shown: true
            icon: BluetoothService.icon
            title: "Bluetooth"
            subtitle: BluetoothService.summary
            checked: BluetoothService.enabled
            available: BluetoothService.available
            showChevron: true
            onToggled: value => BluetoothService.setEnabled(value)
            onDetailsRequested: root.openPage("bluetooth")
        }
    }

    Component {
        id: dndTile
        QuickTile {
            shape: fitClass
            readonly property bool shown: true
            icon: NotificationService.dndActive ? "󰂛" : "󰂚"
            title: "Do Not Disturb"
            subtitle: NotificationService.dndLabel
            checked: NotificationService.dndActive
            showChevron: true
            onToggled: value => NotificationService.setDnd(value ? "manual" : "off")
            onDetailsRequested: root.openPage("dnd")
        }
    }

    Component {
        id: microphoneTile
        QuickTile {
            shape: fitClass
            readonly property bool shown: true
            icon: AudioService.micMuted ? "󰍭" : "󰍬"
            title: "Microphone"
            subtitle: AudioService.micMuted ? "Muted" : (AudioService.micInUse ? "In use" : "On")
            checked: !AudioService.micMuted
            available: AudioService.source !== null
            showChevron: true
            onToggled: AudioService.toggleMute(AudioService.source)
            onDetailsRequested: root.openPage("audio")
        }
    }

    Component {
        id: fingerprintTile
        QuickTile {
            shape: fitClass
            readonly property bool shown: FingerprintService.ready
            icon: "󰈷"
            title: "Fingerprint"
            subtitle: FingerprintService.modeLabel
            checked: FingerprintService.mode !== "off"
            showChevron: true
            leavesPanel: true
            onToggled: value => FingerprintService.setMode(value ? "auto" : "off")
            onDetailsRequested: PanelService.open("settings", { page: "lockScreen" })
        }
    }

    Component {
        id: brightnessTile
        ShellCard {
            id: brightnessCard
            readonly property bool shown: BrightnessService.available
            implicitHeight: brightnessColumn.implicitHeight + Metrics.spaceLg * 2
            // Two rows is the least this tile may be pulled to, and a title
            // line over a slider does not fit in them. So at that size the
            // slider moves up beside the glyph and the title goes: the
            // control is what the tile is for, and it is the last thing that
            // may be cut.
            readonly property bool compact: fitClass === "small" || fitClass === "icon"
            ColumnLayout {
                id: brightnessColumn
                // Centred in the cell, not stretched across it: a layout that
                // fills its cell hands every spare pixel to whichever child is
                // itself a layout, which pinned the text to the top of a tall
                // tile and left a growing band under it. A cell too short
                // overflows instead, and QuickSlot clips it.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.spaceLg
                anchors.rightMargin: Metrics.spaceLg
                spacing: Metrics.spaceMd
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd
                    ShellIcon { glyph: "󰃟"; size: Metrics.iconLg; color: Colors.mutedText }
                    ShellText { Layout.fillWidth: true; text: "Brightness"; role: "bodyLarge"; visible: !compact }
                    // The slider comes up into this row when the tile is too
                    // short for a row of its own.
                    ShellSlider {
                        Layout.fillWidth: true
                        visible: compact
                        value: BrightnessService.value
                        onMoved: value => BrightnessService.set(value)
                    }
                    ShellText { text: Math.round(BrightnessService.value * 100) + "%"; role: "small"; muted: true }
                    ShellButton {
                        icon: "󰖔"
                        compact: true
                        visible: !brightnessCard.compact
                        variant: NightLightService.mode !== "off" ? "accent" : "ghost"
                        toolTip: "Night Light"
                        onClicked: NightLightService.toggle()
                    }
                }
                ShellSlider {
                    Layout.fillWidth: true
                    visible: !compact
                    value: BrightnessService.value
                    onMoved: value => BrightnessService.set(value)
                }
            }
        }
    }

    Component {
        id: batteryTile
        ShellCard {
            readonly property bool shown: true
            implicitHeight: batteryColumn.implicitHeight + Metrics.spaceLg * 2
            interactive: true
            hovered: batteryMouse.containsMouse
            pressed: batteryMouse.pressed && batteryMouse.containsMouse
            MouseArea { id: batteryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPage("power") }
            // The same rule as the brightness tile beside it, so the two keep
            // agreeing at every size: too short for a title over a bar, and
            // the bar comes up beside the glyph and the title goes.
            readonly property bool compact: fitClass === "small" || fitClass === "icon"
            ColumnLayout {
                id: batteryColumn
                // Centred in the cell, not stretched across it: a layout that
                // fills its cell hands every spare pixel to whichever child is
                // itself a layout, which pinned the text to the top of a tall
                // tile and left a growing band under it. A cell too short
                // overflows instead, and QuickSlot clips it.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.spaceLg
                anchors.rightMargin: Metrics.spaceLg
                spacing: Metrics.spaceMd
                // The same shape as the brightness tile beside it: one header
                // line of icon, title and value, then a bar in the slider's
                // footprint, so the two tiles line up instead of each finding
                // its own rhythm.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd
                    ShellIcon { glyph: PowerService.icon; size: Metrics.iconLg; color: PowerService.charging ? Colors.success : Colors.mutedText }
                    ShellText {
                        text: PowerService.hasBattery ? "Battery" : "Power supply"
                        role: "bodyLarge"
                        visible: !compact
                    }
                    // The state is the line that gives way, never the title:
                    // it takes the slack, so it is what elides on a narrow tile.
                    ShellText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: PowerService.stateLabel
                            + (PowerService.remainingLabel.length ? " · " + PowerService.remainingLabel : "")
                        role: "small"; muted: true; elide: Text.ElideRight
                        visible: !compact
                    }
                    Item {
                        Layout.fillWidth: true
                        visible: compact && PowerService.hasBattery
                        implicitHeight: Metrics.sliderTrack
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Colors.track
                            Rectangle {
                                width: parent.width * PowerService.percent / 100
                                height: parent.height
                                radius: parent.radius
                                color: PowerService.percent <= 15 && !PowerService.charging ? Colors.danger : Colors.accent
                            }
                        }
                    }
                    ShellText {
                        visible: PowerService.hasBattery
                        text: PowerService.percent + "%"
                        role: "small"; muted: true
                    }
                }
                Item {
                    Layout.fillWidth: true
                    visible: !compact && PowerService.hasBattery
                    implicitHeight: Metrics.sliderHandle + Metrics.spaceXs
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Metrics.sliderTrack
                        radius: height / 2
                        color: Colors.track
                        Rectangle {
                            width: parent.width * PowerService.percent / 100
                            height: parent.height
                            radius: parent.radius
                            color: PowerService.percent <= 15 && !PowerService.charging ? Colors.danger : Colors.accent
                        }
                    }
                }
            }
        }
    }

    Component {
        id: mediaTile
        MediaCard {
            shape: fitClass
            readonly property bool shown: true
        }
    }

    Component {
        id: audioTile
        AudioCard { onOpenDetails: root.openPage("audio")
            shape: fitClass
            readonly property bool shown: true
        }
    }

    Component {
        id: drivesTile
        ShellCard {
            readonly property bool shown: DrivesService.drives.length > 0 || DrivesService.phones.length > 0
            implicitHeight: drivesRow.implicitHeight + Metrics.spaceMd * 2
            interactive: true
            hovered: drivesMouse.containsMouse
            pressed: drivesMouse.pressed && drivesMouse.containsMouse
            MouseArea { id: drivesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPage("drives") }
            RowLayout {
                id: drivesRow
                // Centred in the cell, not stretched across it: a layout that
                // fills its cell hands every spare pixel to whichever child is
                // itself a layout, which pinned the text to the top of a tall
                // tile and left a growing band under it. A cell too short
                // overflows instead, and QuickSlot clips it.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.spaceLg
                anchors.rightMargin: Metrics.spaceMd
                spacing: Metrics.spaceMd
                // One grid row is 30 px: a title over a subtitle does not fit
                // in it, nor does a button beside them. What is left is what
                // the tile is - a glyph, a name and the way on.
                readonly property bool tight: gridH <= 1
                readonly property var single: DrivesService.drives.length === 1 && DrivesService.phones.length === 0
                    ? DrivesService.drives[0] : null
                readonly property bool onlyPhone: DrivesService.drives.length === 0 && DrivesService.phones.length === 1
                ShellIcon {
                    glyph: drivesRow.single ? DrivesService.icon(drivesRow.single)
                        : drivesRow.onlyPhone ? DrivesService.phoneIcon() : "󰋊"
                    size: Metrics.iconMd
                    color: Colors.accentForeground
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText { Layout.fillWidth: true; text: "Drives"; role: "bodyLarge" }
                    ShellText {
                        Layout.fillWidth: true
                        visible: !drivesRow.tight
                        text: drivesRow.single && DrivesService.isBusy(drivesRow.single) ? DrivesService.driveSubtitle(drivesRow.single) : DrivesService.summary
                        role: "small"; muted: true
                    }
                }
                ShellButton {
                    icon: "󰇪"; text: "Eject"; compact: true; variant: "ghost"
                    visible: !drivesRow.tight
                    enabledState: drivesRow.single !== null && !DrivesService.isBusy(drivesRow.single)
                    onClicked: { DrivesService.eject(drivesRow.single); root.openPage("drives") }
                }
                ShellIcon { glyph: Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
            }
        }
    }

    Component {
        id: phoneTile
        ShellCard {
            readonly property bool shown: KdeConnectService.phone !== null
            implicitHeight: phoneRow.implicitHeight + Metrics.spaceMd * 2
            interactive: true
            hovered: phoneMouse.containsMouse
            pressed: phoneMouse.pressed && phoneMouse.containsMouse
            MouseArea {
                id: phoneMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: PanelService.open("settings", { page: "kdeConnect" })
            }
            RowLayout {
                id: phoneRow
                // Centred in the cell, not stretched across it: a layout that
                // fills its cell hands every spare pixel to whichever child is
                // itself a layout, which pinned the text to the top of a tall
                // tile and left a growing band under it. A cell too short
                // overflows instead, and QuickSlot clips it.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.spaceLg
                anchors.rightMargin: Metrics.spaceMd
                spacing: Metrics.spaceMd
                // The same rule as the drives tile above it.
                readonly property bool tight: gridH <= 1
                readonly property var phone: KdeConnectService.phone
                ShellIcon {
                    glyph: phoneRow.phone ? KdeConnectService.deviceIcon(phoneRow.phone) : "󰄜"
                    size: Metrics.iconMd
                    color: Colors.accentForeground
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText { Layout.fillWidth: true; text: phoneRow.phone ? phoneRow.phone.name : "Phone"; role: "bodyLarge" }
                    ShellText {
                        Layout.fillWidth: true
                        visible: !phoneRow.tight
                        text: phoneRow.phone ? KdeConnectService.detailText(phoneRow.phone) : ""
                        role: "small"; muted: true
                    }
                }
                ShellButton {
                    icon: "󰂞"; text: "Ring"; compact: true; variant: "ghost"
                    visible: !phoneRow.tight
                    onClicked: KdeConnectService.run("ring", phoneRow.phone)
                }
                ShellIcon { glyph: Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
            }
        }
    }

    Component {
        id: shortcutsTile
        Item {
            readonly property bool shown: true

            // The only tile with no card of its own, so a cell taller than the
            // chips shows bare panel: they are centred in it rather than
            // pinned to its top. And they fill the width, because a chip has
            // no fillWidth of its own and four of them in a one-column panel
            // were squeezed below their own size.
            RowLayout {
                id: chipRow
                // One grid row is 30 px and a chip is 64: below two rows the
                // chips go compact rather than being cut off at the cell edge.
                readonly property bool tight: gridH <= 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.spaceSm

                ChipButton {
                    Layout.fillWidth: true
                    compact: chipRow.tight
                    icon: "󰓅"
                    title: "Power"
                    subtitle: PowerService.profileLabel
                    active: PowerService.profile !== 1
                    showChevron: true
                    onClicked: root.openPage("power")
                }
                ChipButton {
                    Layout.fillWidth: true
                    compact: chipRow.tight
                    icon: Colors.dark ? "󰖔" : "󰖙"
                    title: "Dark Mode"
                    subtitle: Colors.dark ? "On" : "Off"
                    active: Colors.dark
                    onClicked: SettingsService.set("appearance.theme", Colors.dark ? "light" : "dark")
                }
                ChipButton {
                    Layout.fillWidth: true
                    compact: chipRow.tight
                    icon: "󰍹"
                    title: "Displays"
                    subtitle: Quickshell.screens.length + " connected"
                    showChevron: true
                    leavesPanel: true
                    onClicked: PanelService.open("settings", { page: "displays" })
                }
                ChipButton {
                    Layout.fillWidth: true
                    compact: chipRow.tight
                    icon: "󰽥"
                    title: "Focus"
                    subtitle: AdaptiveService.focusActive ? "On" : "Off"
                    active: AdaptiveService.focusActive
                    onClicked: AdaptiveService.setFocus(!AdaptiveService.focusActive)
                }
            }
        }
    }

    // Anything not in the catalogue is a desktop widget - the same file the
    // desktop, the bar and the notch load. It is drawn on a card like every
    // other tile, in the theme's own ink (this is an ordinary panel surface,
    // unlike the notch), and it is clickable when the registry names a panel
    // for it: a widget that only looked like a control was the thing that went
    // wrong when the notch first allowed them.
    Component {
        id: widgetTile
        ShellCard {
            id: widgetCard
            // `tileType` comes from the Loader that created this component,
            // like `gridW` and `fitClass` beside it.
            readonly property string typeName: tileType
            readonly property var entry: WidgetRegistry.type(typeName)
            readonly property string action: entry ? entry.action : ""
            readonly property bool hasData: widget.item ? widget.item.hasData !== false : false
            readonly property bool shown: true

            interactive: action.length > 0
            hovered: widgetMouse.containsMouse
            pressed: widgetMouse.pressed && widgetMouse.containsMouse

            Loader {
                id: widget
                anchors.centerIn: parent
                visible: widgetCard.hasData
                source: WidgetRegistry.source(widgetCard.typeName)
                onLoaded: {
                    // Which readout this is: three registry types share one
                    // file and tell themselves apart by `options.metric`.
                    // `screen` as well as `type`: a workspace widget filters
                    // the compositor's workspaces by it, and without one it
                    // shows a single placeholder pip. The panel can move
                    // between monitors, so it is a binding.
                    item.instance = Qt.binding(() => ({
                        id: widgetCard.typeName, type: widgetCard.typeName,
                        screen: PanelService.screen ? PanelService.screen.name : "",
                        options: widgetCard.entry && widgetCard.entry.options
                            ? widgetCard.entry.options : {} }))
                }
            }
            // A binding, not a line in `onLoaded`: the cell keeps changing
            // after the widget is loaded, and an assignment never arrives
            // twice.
            Binding {
                target: widget.item
                property: "sizeClass"
                value: Fit.widgetSize(widgetCard.width, widgetCard.height)
                when: widget.item !== null
            }

            // A widget with nothing to say says its name, the way an empty
            // block does on the notch, rather than leaving a blank card.
            Row {
                anchors.centerIn: parent
                visible: !widgetCard.hasData
                spacing: Metrics.spaceSm
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: widgetCard.entry ? widgetCard.entry.icon : ""
                    size: Metrics.iconMd
                    color: Colors.mutedText
                }
                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: widgetCard.entry ? widgetCard.entry.label : widgetCard.typeName
                    muted: true
                }
            }

            MouseArea {
                id: widgetMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: widgetCard.action.length > 0
                cursorShape: Qt.PointingHandCursor
                // `actionArgs` says *where* in a panel the widget means, the
                // way `options` says which readout it is. Four surfaces load
                // widgets and the first pass taught only two of them - which
                // is the same mistake `options.metric` made, where every
                // system readout on the notch was the CPU.
                onClicked: PanelService.open(widgetCard.action,
                                             widgetCard.entry && widgetCard.entry.actionArgs
                                                 ? widgetCard.entry.actionArgs : {})
            }
        }
    }
}
