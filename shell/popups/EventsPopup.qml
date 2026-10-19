import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.dashboard
import "../../services/appearance/DateFormat.js" as DateFormat

// Events pill/widget: today's events that have not ended yet.
PopupPanel {
    id: root
    readonly property CalendarDemand calendarDemand: CalendarDemand { active: root.shown }
    panelId: "eventsPopup"
    heading: "Today"
    detail: DateFormat.date(clock.date, SettingsService.locale, "long")
    glyph: "󰸗"
    glyphActive: CalendarService.remainingToday(clock.date).length > 0
    footerText: "Open dashboard"
    footerGlyph: "󰃭"
    // The rest of the same day, in the shell's own dashboard.
    footerLeaves: false
    onFooterClicked: PanelService.open("dashboard")

    // Only while the popup is shown: built with the shell like every panel,
    // it woke once a minute all session to filter the day's events for a
    // header nobody saw. Enabled again, it reads the time at once.
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: root.shown && WallClock.ticking }

    body: ScrollList {
        maxHeight: Metrics.popupListHeight * 2
        EventList {
            width: parent.width
            remainingOnly: true
            isToday: true
        }
    }
}
