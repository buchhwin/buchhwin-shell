import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Options of the selected bar pill and its items inside the layout editor.
// Mirrors the list editor on Settings > Bar & Notch and uses the same
// LayoutService.bar* operations.
EditorPanel {
    id: panel
    required property var editor
    readonly property var place: editor.barPlace
    readonly property var pill: editor.barPillEntry
    readonly property var currentItem: pill !== null && editor.barItem >= 0 ? pill.items[editor.barItem] : null
    readonly property string unit: LayoutService.bar.style === "bar" ? "Group" : "Pill"
    visible: pill !== null && editor.barMode
    title: panel.unit + (panel.place ? " · " + (panel.place.zone === "left" ? "Left" : panel.place.zone === "center" ? "Center" : "Right") : "")


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
            Layout.fillWidth: true
            current: panel.currentItem ? panel.currentItem.display : "full"
            options: panel.currentItem ? WidgetRegistry.pillDisplays(panel.currentItem.type) : []
            onSelected: value => LayoutService.barSetDisplay(panel.pill.id, panel.editor.barItem, value)
        }
        // The size of this one item, on top of the bar's own size below: the
        // user asked to resize a tile, not only the whole strip.
        SectionLabel { text: "Item size" }
        SegmentedControl {
            Layout.fillWidth: true
            current: panel.currentItem ? (panel.currentItem.size || "small") : "small"
            options: [{ value: "small", label: "Small" }, { value: "medium", label: "Medium" }, { value: "large", label: "Large" }]
            onSelected: value => LayoutService.barSetItemSize(panel.pill.id, panel.editor.barItem, value)
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellButton {
                icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move item left"
                enabledState: panel.editor.barItem > 0
                onClicked: {
                    const index = panel.editor.barItem
                    LayoutService.barMoveItem(panel.pill.id, index, -1)
                    panel.editor.selectBar(panel.pill.id, index - 1)
                }
            }
            ShellButton {
                icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move item right"
                enabledState: panel.pill !== null && panel.editor.barItem < panel.pill.items.length - 1
                onClicked: {
                    const index = panel.editor.barItem
                    LayoutService.barMoveItem(panel.pill.id, index, 1)
                    panel.editor.selectBar(panel.pill.id, index + 1)
                }
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: panel.pill !== null && panel.pill.items.length > 1
                icon: "󰤼"; text: "Split off"; compact: true
                onClicked: {
                    LayoutService.barSplitItem(panel.pill.id, panel.editor.barItem)
                    panel.editor.selectBar(panel.pill.id, -1)
                }
            }
        }
        ShellButton {
            Layout.fillWidth: true
            icon: Icons.remove; text: "Remove item"; variant: "danger"
            onClicked: {
                const id = panel.pill.id
                LayoutService.barRemoveItem(id, panel.editor.barItem)
                panel.editor.selectBar(LayoutService.barPlace(id) ? id : "", -1)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        SectionLabel { text: "Zone" }
        SegmentedControl {
            Layout.fillWidth: true
            current: panel.place ? panel.place.zone : "center"
            options: [{ value: "left", label: "Left" }, { value: "center", label: "Center" }, { value: "right", label: "Right" }]
            onSelected: value => LayoutService.barMovePillTo(panel.pill.id, value, LayoutService.bar[value].length)
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellButton { icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Move left"
                onClicked: LayoutService.barMovePill(panel.pill.id, -1) }
            ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Move right"
                onClicked: LayoutService.barMovePill(panel.pill.id, 1) }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: panel.place !== null && panel.place.index < LayoutService.bar[panel.place.zone].length - 1
                icon: "󰘞"; text: "Merge"; compact: true; toolTip: "Merge with the next " + panel.unit.toLowerCase()
                onClicked: LayoutService.barMergeWithNext(panel.pill.id)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        // Size lived only in Settings while widgets could be resized four ways
        // in the editor. It is the bar's equivalent, so it belongs here too.
        SectionLabel { text: "Bar size" }
        SegmentedControl {
            Layout.fillWidth: true
            current: String(LayoutService.bar.scale)
            options: [{ value: "0.9", label: "Small" }, { value: "1", label: "Normal" }, { value: "1.15", label: "Large" }]
            onSelected: value => LayoutService.setBarOption("scale", Number(value))
        }
    }

    ShellButton {
        Layout.fillWidth: true
        icon: Icons.remove; text: "Remove " + panel.unit.toLowerCase(); variant: "danger"
        onClicked: {
            const id = panel.pill.id
            panel.editor.selectBar("", -1)
            LayoutService.barRemovePill(id)
        }
    }
}
