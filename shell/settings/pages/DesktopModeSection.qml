import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// The one desktop mode selector, shown on the Widgets and the Bar page.
// Exactly one surface is active; every mode of the profile keeps its own, so
// switching back restores the widgets or pills that were set up before.
SettingsSection {
    id: section
    title: "Desktop mode"
    description: "One at a time: widgets on the wallpaper, a bar along one edge, or a notch at the top center. Applies to the active mode."

    SegmentedControl {
        focusOnTab: true
        Layout.fillWidth: true
        current: LayoutService.desktopMode
        options: [{ value: "widgets", label: "Widgets", icon: Icons.edit },
                  { value: "pills", label: "Bar", icon: "󰘔" },
                  { value: "notch", label: "Notch", icon: "󱂩" }]
        onSelected: value => LayoutService.setDesktopMode(value)
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        ShellButton {
            focusOnTab: true
            icon: Icons.edit; text: "Edit layout"; variant: "accent"
            onClicked: { PanelService.close(); LayoutService.editMode = true }
        }
        ShellButton { focusOnTab: true; icon: Icons.undo; text: "Undo"; enabledState: LayoutService.undoStack.length > 0; onClicked: LayoutService.undo() }
        ShellText {
            Layout.fillWidth: true
            text: "Super + Alt + E edits widgets, the bar and the notch by hand"
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
    }
    ShellText {
        visible: LayoutService.readOnly
        Layout.fillWidth: true
        text: "Layout is read-only: " + LayoutService.readOnlyReason
        color: Colors.warning
        wrapMode: Text.Wrap
    }
}
