import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Options of the selected bar pill and its items inside the layout editor.
// Mirrors the list editor on Settings > Bar & notch and uses the same
// LayoutService.bar* operations.
EditorPanel {
    id: panel
    required property var editor
    readonly property var place: editor.barPlace
    readonly property var pill: editor.barPillEntry
    readonly property var currentItem: pill !== null && editor.barItem >= 0 ? pill.items[editor.barItem] : null
    readonly property bool itemSized: currentItem === null || currentItem === undefined || WidgetRegistry.pillSized(currentItem.type)
    // The bar's or the dock's: the editor says which (LayoutService.pill*).
    readonly property string target: editor.zoneTarget
    readonly property var zones: editor.zones
    readonly property string unit: target === "dock" || LayoutService.bar.style === "bar" ? "Group" : "Pill"
    visible: pill !== null && editor.zonesMode
    title: panel.unit + (panel.place ? " · " + (panel.place.zone === "left" ? "Left" : panel.place.zone === "center" ? "Center" : "Right") : "")

    // Every control is a Tab stop, top to bottom as drawn, like the panels'
    // forms. From the editor itself Tab still walks the pills
    // (EditLayer.barKey) and Ctrl+Tab enters the controls
    // (EditLayer.walkControls); Tab then walks on among them, and these are
    // also the names a screen reader gives them.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        SectionLabel { text: "Items" }
        Repeater {
            model: panel.pill ? panel.pill.items : []
            ListRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                focusOnTab: true
                compact: true
                icon: (WidgetRegistry.type(modelData.type) || { icon: "󰘔" }).icon
                title: (WidgetRegistry.type(modelData.type) || { label: modelData.type }).label
                selected: panel.editor.barItem === index
                onClicked: panel.editor.selectBar(panel.pill.id, index)
            }
        }
    }

    ColumnLayout {
        visible: panel.currentItem !== null
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        SectionLabel { text: "Display" }
        SegmentedControl {
            focusOnTab: true
            accessibleName: "Display"
            Layout.fillWidth: true
            current: panel.currentItem ? panel.currentItem.display : "full"
            options: panel.currentItem ? WidgetRegistry.pillDisplays(panel.currentItem.type) : []
            onSelected: value => LayoutService.pillSetDisplay(panel.target, panel.pill.id, panel.editor.barItem, value)
        }
        // The size of this one item, on top of the bar's own size below: the
        // user asked to resize a tile, not only the whole strip. Not for an
        // item that sizes itself (WidgetRegistry `pillSized: false`, the
        // dock's apps): a pick there wrote an undo step and changed nothing.
        SectionLabel { visible: panel.itemSized; text: "Item size" }
        SegmentedControl {
            visible: panel.itemSized
            focusOnTab: true
            accessibleName: "Item size"
            Layout.fillWidth: true
            current: panel.currentItem ? (panel.currentItem.size || "small") : "small"
            options: [{ value: "small", label: "Small" }, { value: "medium", label: "Medium" }, { value: "large", label: "Large" }]
            onSelected: value => LayoutService.pillSetItemSize(panel.target, panel.pill.id, panel.editor.barItem, value)
        }
        ShellText {
            visible: !panel.itemSized
            Layout.fillWidth: true
            text: "Its icons follow the dock's icon size (Settings > Dock)."
            role: "small"
            color: Colors.mutedText
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellButton {
                focusOnTab: true
                icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move item left"
                enabledState: panel.editor.barItem > 0
                onClicked: {
                    const index = panel.editor.barItem
                    LayoutService.pillMoveItem(panel.target, panel.pill.id, index, -1)
                    panel.editor.selectBar(panel.pill.id, index - 1)
                }
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move item right"
                enabledState: panel.pill !== null && panel.editor.barItem < panel.pill.items.length - 1
                onClicked: {
                    const index = panel.editor.barItem
                    LayoutService.pillMoveItem(panel.target, panel.pill.id, index, 1)
                    panel.editor.selectBar(panel.pill.id, index + 1)
                }
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: panel.pill !== null && panel.pill.items.length > 1
                focusOnTab: true
                icon: "󰤼"; text: "Split off"; compact: true
                onClicked: {
                    LayoutService.pillSplit(panel.target, panel.pill.id, panel.editor.barItem)
                    panel.editor.selectBar(panel.pill.id, -1)
                }
            }
        }
        ShellButton {
            Layout.fillWidth: true
            focusOnTab: true
            icon: Icons.remove; text: "Remove item"; variant: "danger"
            onClicked: {
                const id = panel.pill.id
                LayoutService.pillRemoveItem(panel.target, id, panel.editor.barItem)
                panel.editor.selectBar(LayoutService.pillPlace(panel.target, id) ? id : "", -1)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        SectionLabel { text: "Zone" }
        SegmentedControl {
            focusOnTab: true
            accessibleName: "Zone"
            Layout.fillWidth: true
            current: panel.place ? panel.place.zone : "center"
            options: [{ value: "left", label: "Left" }, { value: "center", label: "Center" }, { value: "right", label: "Right" }]
            // To the end of another zone. A click on the zone the pill is in
            // already (the control answers that too) moved it to that zone's
            // end and took an undo step.
            onSelected: value => {
                if (panel.place && value !== panel.place.zone)
                    LayoutService.pillMoveTo(panel.target, panel.pill.id, value, panel.zones[value].length)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellButton { focusOnTab: true; icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move left"
                onClicked: LayoutService.pillMove(panel.target, panel.pill.id, -1) }
            ShellButton { focusOnTab: true; icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move right"
                onClicked: LayoutService.pillMove(panel.target, panel.pill.id, 1) }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: panel.place !== null && panel.place.index < panel.zones[panel.place.zone].length - 1
                focusOnTab: true
                icon: "󰘞"; text: "Merge"; compact: true; toolTip: "Merge with the next " + panel.unit.toLowerCase()
                onClicked: LayoutService.pillMerge(panel.target, panel.pill.id)
            }
        }
    }

    ColumnLayout {
        // The bar's own size; the dock's is its icon size (Settings > Dock).
        visible: panel.target === "bar"
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        // Size lived only in Settings while widgets could be resized four ways
        // in the editor. It is the bar's equivalent, so it belongs here too.
        SectionLabel { text: "Bar size" }
        SegmentedControl {
            focusOnTab: true
            accessibleName: "Bar size"
            Layout.fillWidth: true
            current: String(LayoutService.bar.scale)
            options: [{ value: "0.9", label: "Small" }, { value: "1", label: "Normal" }, { value: "1.15", label: "Large" }]
            onSelected: value => LayoutService.setBarOption("scale", Number(value))
        }
    }

    ShellButton {
        Layout.fillWidth: true
        focusOnTab: true
        icon: Icons.remove; text: "Remove " + panel.unit.toLowerCase(); variant: "danger"
        onClicked: {
            const id = panel.pill.id
            panel.editor.selectBar("", -1)
            LayoutService.pillRemove(panel.target, id)
        }
    }
}
