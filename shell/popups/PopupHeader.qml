import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// Popup title row: round icon tile (accent while active), heading, status
// line and an optional switch, with a divider below. A PanelHeader inside.
ColumnLayout {
    id: root
    property string heading: ""
    property string detail: ""
    property string glyph: ""
    property bool active: false
    property bool hasToggle: false
    property bool checked: false
    property bool toggleEnabled: true
    signal toggled(bool checked)
    spacing: Metrics.panelGap

    // The panels' header, instead of a second header that had drifted to
    // its own. At the size of a panel that is one page (the control center,
    // the notification centre), one step above the titles of the cards in
    // the popup: at the dialog size, "Audio" was "Output" and "Applications"
    // again, same size and weight.
    PanelHeader {
        Layout.fillWidth: true
        role: "headline"
        icon: root.glyph
        iconTile: true
        iconActive: root.active
        title: root.heading
        subtitle: root.detail
        wrap: false

        ShellToggle {
            focusOnTab: true
            // The popup's own name is what the switch turns on and off.
            accessibleName: root.heading
            visible: root.hasToggle
            checked: root.checked
            enabledState: root.toggleEnabled
            onToggled: value => root.toggled(value)
        }
    }

    Divider {}
}
