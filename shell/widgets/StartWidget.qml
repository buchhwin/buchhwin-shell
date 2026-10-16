import QtQuick
import qs.shell.widgets
import qs.theme

// The dock's start button: the launcher's own glyph in the accent. A click
// opens the launcher above it - the registry's action, which the pill runs
// with the button's place, so the launcher comes out of it like any panel
// out of its pill.
WidgetBase {
    id: root
    icon: Icons.apps
    iconColor: root.accentInk
    label: "Apps"
    name: "Start"
}
