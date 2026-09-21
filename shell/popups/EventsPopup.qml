import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.dashboard

// Events pill/widget: today's events that have not ended yet.
PopupPanel {
    id: root
    panelId: "eventsPopup"
    heading: "Today"
    detail: SettingsService.locale.toString(clock.date, "dddd, MMMM d")
    glyph: "󰸗"
    glyphActive: CalendarService.remainingToday(clock.date).length > 0
    footerText: "Open dashboard"
    footerGlyph: "󰃭"
    onFooterClicked: PanelService.open("dashboard")

    SystemClock { id: clock; precision: SystemClock.Minutes }

    body: ScrollList {
        maxHeight: Metrics.popupListHeight * 2
        EventList {
            width: parent.width
            remainingOnly: true
            isToday: true
        }
    }
}
