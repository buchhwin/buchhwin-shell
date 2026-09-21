import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
import "../../services/color/ColorLogic.js" as Logic

// The last colour picked, as a widget: a dot in that colour beside the
// dropper. A click opens the list; picking a new one is a keystroke away from
// there, or Super+Shift+C from anywhere.
//
// It goes wherever a widget goes - the desktop, the bar, the notch, the quick
// panel, the dashboard - because it is an ordinary WidgetBase and the surfaces
// take whatever the registry offers.
WidgetBase {
    id: root
    readonly property string latest: ColorPickerService.history.length
        ? ColorPickerService.history[0] : ""

    icon: "󰈊"
    // The dropper carries the colour itself when there is one, so the widget
    // says what it knows even with no room for a label at all.
    iconColor: root.latest.length ? root.latest : root.mutedTextColor
    label: root.latest.length ? root.latest.slice(1).toUpperCase() : "Pick"
    name: "Color"
    detail: ColorPickerService.history.length > 1
        ? ColorPickerService.history.length + " picked" : ""
    maxLabelWidth: 120
}
