import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// How many updates are waiting. Until now this lived only on a settings page,
// which is the one place you do not look when you are wondering whether to
// look - so it is a widget, which means it can sit on the desktop, the bar,
// the notch, the quick panel and the dashboard.
//
// A click opens Settings on its own page, where the lists and the buttons are.
WidgetBase {
    id: root
    readonly property int count: UpdatesService.total
    readonly property int security: UpdatesService.securityCount

    icon: root.security > 0 ? Icons.warning : "󰚰"
    // The number alone. "Up to date" is a sentence and this is a glyph with a
    // figure beside it; nothing waiting is nothing to say, so the widget goes
    // quiet instead of insisting.
    label: root.count > 0 ? String(root.count) : ""
    // A security update is the one case worth colouring for: everything else
    // can wait for a convenient moment and this cannot.
    iconColor: root.security > 0 ? Colors.danger : root.textColor

    // Nothing waiting is still worth a place - an empty slot where a readout
    // used to be reads as broken - so the name and the state fill a larger
    // cell rather than the widget disappearing from it.
    name: "Updates"
    detail: UpdatesService.summary
    hasData: true
}
