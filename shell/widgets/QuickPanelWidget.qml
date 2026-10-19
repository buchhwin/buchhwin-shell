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
    // The ones that change what the machine does rather than how it looks,
    // and whose being on is worth knowing from across the room. Stay awake
    // among them: it is said while it holds the lock and sleep off, so it is
    // not left on by accident - and in a pill the clock beside it shows no
    // hints (ClockWidget's inGroup), so this is where the pill bar says it.
    readonly property bool dnd: NotificationService.dndActive
    readonly property bool stayAwake: IdleService.stayAwake
    readonly property bool nightLight: NightLightService.active
    readonly property bool wifiOff: !NetworkService.wifiEnabled
    readonly property int active: (dnd ? 1 : 0) + (stayAwake ? 1 : 0) + (nightLight ? 1 : 0) + (wifiOff ? 1 : 0)

    // Do Not Disturb wins the glyph when it is on: it is the one that changes
    // whether the machine may interrupt you, which is the thing you would want
    // to be reminded of. Stay awake next: it keeps the screen unlocked.
    icon: root.dnd ? "󰂛" : root.stayAwake ? IdleService.stayAwakeIcon : root.nightLight ? Icons.nightLight : root.wifiOff ? "󰤮" : "󰕮"
    iconColor: root.dnd || root.wifiOff ? root.warningInk : root.glyphInk
    label: ""

    name: "Control center"
    detail: root.dnd ? "Do Not Disturb"
        : root.stayAwake ? "Staying awake"
        : root.wifiOff ? "Wi-Fi off"
        : root.nightLight ? "Night Light"
        : "Nothing on"
}
