import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.spaceLg

    SettingsSection {
        Layout.fillWidth: true
        title: "Source"
        description: "buchhwin-shell only reads the KDE calendars, like the Plasma clock. Google accounts and other calendars are set up in Merkuro (KDE)."

        ListRow {
            Layout.fillWidth: true
            icon: "󰸗"
            active: CalendarService.status === "ok"
            title: "KDE calendars (Akonadi)"
            subtitle: CalendarService.status === "ok"
                ? CalendarService.visibleCalendarCount + " of " + CalendarService.calendarRows.filter(row => row.selectable).length + " calendars visible"
                : CalendarService.status === "unavailable" ? "Not reachable. Is Akonadi running?"
                : CalendarService.status === "sandbox" ? "Not available in the test session"
                : CalendarService.status === "disabled" ? "Turned off" : "Loading …"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("calendar.enabled")
                onToggled: value => SettingsService.set("calendar.enabled", value)
            }
        }

        RowLayout {
            spacing: Metrics.spaceSm
            ShellButton { focusOnTab: true; icon: "󰃭"; text: "Manage in Merkuro"; onClicked: CalendarService.openManager() }
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: "Refresh"
                enabledState: CalendarService.status === "ok"
                onClicked: CalendarService.refresh()
            }
        }
    }

    Repeater {
        model: CalendarService.status === "ok" ? CalendarService.calendarGroups : []
        SettingsSection {
            id: groupSection
            required property var modelData
            Layout.fillWidth: true
            title: modelData.name
            description: modelData.id === -1 ? "Calendars on this computer" : "Account"

            Repeater {
                model: groupSection.modelData.calendars
                ListRow {
                    focusOnTab: true
                    id: calendarRow
                    required property var modelData
                    readonly property bool shown: CalendarService.hiddenIds.indexOf(modelData.id) < 0
                    Layout.fillWidth: true
                    compact: true
                    level: 1
                    icon: modelData.icon === "view-pim-tasks" ? "󰄲" : modelData.icon === "view-calendar-birthday" ? "󰃩" : "󰃭"
                    title: modelData.name
                    active: shown
                    onClicked: CalendarService.setCalendarVisible(modelData.id, !shown)
                    ShellToggle {
                        focusOnTab: true
                        checked: calendarRow.shown
                        onToggled: value => CalendarService.setCalendarVisible(calendarRow.modelData.id, value)
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Event colors"
        description: "The bar next to an event in the dashboard, the notch and the widgets."

        SettingRow {
            label: "Color"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("calendar.eventColor")
                options: [{ value: "accent", label: "Accent" }, { value: "calendar", label: "Calendar" }]
                onSelected: value => SettingsService.set("calendar.eventColor", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Hint next to the clock"
        description: "Shows a calendar icon next to the clock shortly before an event (when hints next to the clock are on)."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show upcoming events"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("calendar.eventHint")
                onToggled: value => SettingsService.set("calendar.eventHint", value)
            }
        }
        SettingRow {
            label: "Lead time"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("calendar.hintMinutes"))
                options: [{ value: "5", label: "5 min" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }, { value: "60", label: "1 h" }]
                onSelected: value => SettingsService.set("calendar.hintMinutes", parseInt(value))
            }
        }
    }
}
