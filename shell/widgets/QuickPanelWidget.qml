import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// A way into the control center that is not a keyboard shortcut. `Super+O`
// has always opened it and a widget is the other half of that: something to
// aim at, on the desktop in widgets mode or on the bar.
//
// It shows what the panel would tell you if it were open - how many of the
// quick settings are actually on - so it is a readout rather than a button
// pretending to be one. Nothing on is a quiet glyph, not an empty widget.
WidgetBase {
    id: root
    // The three that change what the machine does rather than how it looks,
    // and the ones whose being on is worth knowing from across the room.
    readonly property bool dnd: NotificationService.dndActive
    readonly property bool nightLight: NightLightService.active
    readonly property bool wifiOff: !NetworkService.wifiEnabled
    readonly property int active: (dnd ? 1 : 0) + (nightLight ? 1 : 0) + (wifiOff ? 1 : 0)

    // Do Not Disturb wins the glyph when it is on: it is the one that changes
    // whether the machine may interrupt you, which is the thing you would want
    // to be reminded of.
    icon: root.dnd ? "󰂛" : root.nightLight ? "󰖔" : root.wifiOff ? "󰤮" : "󰕮"
    iconColor: root.dnd || root.wifiOff ? Colors.warning : root.textColor
    label: ""

    name: "Quick settings"
    detail: root.dnd ? "Do Not Disturb"
        : root.wifiOff ? "Wi-Fi off"
        : root.nightLight ? "Night Light"
        : "Nothing on"
}
