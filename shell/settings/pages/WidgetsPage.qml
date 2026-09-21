import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Desktop mode and the widgets on the wallpaper: one list per display with
// style, visibility and removal. Positions, scale and groups are dragged in
// the editor (Super + Alt + E); every change is undoable like a layout edit.
ColumnLayout {
    id: page
    spacing: Metrics.spaceLg

    readonly property int revision: LayoutService.revision
    readonly property var typeOptions: WidgetRegistry.availableTypes()
        .map(entry => ({ value: entry.name, label: entry.label }))
        .sort((a, b) => a.label.localeCompare(b.label))

    function label(entry) {
        if (entry.members !== undefined)
            return LayoutService.members(entry.id)
                .map(member => (WidgetRegistry.type(member.type) || { label: member.type }).label).join(" · ")
        return (WidgetRegistry.type(entry.type) || { label: entry.type }).label
    }

    function icon(entry) {
        if (entry.members !== undefined) return "󰕸"
        return (WidgetRegistry.type(entry.type) || { icon: Icons.edit }).icon
    }

    DesktopModeSection { Layout.fillWidth: true }

    Repeater {
        model: LayoutService.widgetsShown ? Quickshell.screens : []

        SettingsSection {
            id: screenSection
            required property var modelData
            readonly property string screenName: modelData.name
            readonly property var ids: page.revision >= 0 ? LayoutService.placementIds(screenName, true) : []
            property string addType: "clock"
            Layout.fillWidth: true
            title: Quickshell.screens.length > 1 ? "Widgets on " + screenName : "Widgets"
            description: ids.length ? "" : "No widgets on this display yet"

            Repeater {
                model: screenSection.ids

                ColumnLayout {
                    id: row
                    required property string modelData
                    readonly property var entry: LayoutService.item(modelData)
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXs
                    visible: entry !== null

                    ListRow {
                        Layout.fillWidth: true
                        icon: row.entry ? page.icon(row.entry) : ""
                        title: row.entry ? page.label(row.entry) : ""
                        subtitle: row.entry && row.entry.members !== undefined ? "Group" : ""
                        RowLayout {
                            spacing: Metrics.spaceSm
                            ShellToggle {
                                checked: row.entry ? row.entry.visible : true
                                onToggled: value => LayoutService.updateItem(row.modelData, { visible: value })
                            }
                            ShellButton {
                                icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove"
                                onClicked: LayoutService.removeItem(row.modelData)
                            }
                        }
                    }
                    SegmentedControl {
                        Layout.fillWidth: true
                        current: row.entry ? row.entry.style : "minimal"
                        options: [{ value: "minimal", label: "Minimal" }, { value: "capsule", label: "Capsule" }, { value: "card", label: "Card" }]
                        onSelected: value => LayoutService.updateItem(row.modelData, { style: value })
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
                    current: screenSection.addType
                    onSelected: value => screenSection.addType = value
                }
                ShellButton {
                    Layout.alignment: Qt.AlignTop
                    icon: Icons.add; text: "Add widget"
                    onClicked: {
                        LayoutService.beginChange()
                        LayoutService.addWidget(screenSection.screenName, screenSection.addType)
                        LayoutService.save()
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: !LayoutService.widgetsShown
        title: "Widgets are hidden"
        description: LayoutService.notchShown
            ? "The notch shows the time at the top center. Switch to Widgets to place widgets on the wallpaper again; the current widget layout is kept."
            : "The bar along the top edge replaces the desktop widgets. Switch to Widgets to place them on the wallpaper again; the current widget layout is kept."
        ShellButton {
            icon: "󰘔"; text: "Open Bar & Notch"
            onClicked: PanelService.open("settings", { page: "bar" })
        }
    }
}
