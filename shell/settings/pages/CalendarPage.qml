import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/calendar/LinkLogic.js" as Links

ColumnLayout {
    id: page
    readonly property CalendarDemand calendarDemand: CalendarDemand {}
    spacing: Metrics.pageGap

    // The calendars from a link are read each time the page is shown - the
    // panel keeps a page between opens, so "created" would be once a session -
    // and nothing asks while it is closed (CalendarService.refreshLinks).
    PageActivity {
        id: activity
        onOpened: {
            page.followUp(0)
            CalendarService.resetLinkMessage()
            CalendarService.refreshLinks()
        }
    }
    // A calendar Akonadi is still fetching (just added, or "Fetch now") is
    // asked about again while the page is open, so its row ends on what came
    // of it - read, or why not - rather than on "Updating …". An add and a
    // fetch are asked about twice even when the first answer is idle (the
    // fetch may not have begun yet), and nothing more than ten times.
    property int rechecks: 0
    property int rechecksAtLeast: 0
    readonly property bool rechecking: recheckTimer.running
    function followUp(atLeast) {
        page.rechecks = 0
        page.rechecksAtLeast = atLeast
    }
    Timer {
        id: recheckTimer
        interval: 3000
        // Repeating, so the binding on `running` survives each tick
        // (testing.md pitfall 7).
        repeat: true
        running: activity.open && !CalendarService.linkBusy && !CalendarService.linkListing && page.rechecks < 10
            && (page.rechecks < page.rechecksAtLeast
                || CalendarService.linkCalendars.some(row => row.status === "running"))
        onTriggered: {
            page.rechecks += 1
            CalendarService.refreshLinks()
        }
    }
    // The form for a new link, and whether an add from it is on its way.
    property bool adding: false
    property bool addSent: false
    function closeForm() {
        // The pasted link goes with the form: it is not kept anywhere here.
        linkField.text = ""
        nameField.text = ""
        page.adding = false
        page.addSent = false
    }
    function sendLink() {
        if (CalendarService.linkBusy) return
        if (!CalendarService.addLink(linkField.text, nameField.text)) return
        // A test session answers at once with a preview; the real one when
        // the helper is done (below).
        if (CalendarService.linkBusy) page.addSent = true
        else if (!CalendarService.realSession) linkField.text = ""
    }
    Connections {
        target: CalendarService
        function onLinkStateChanged() {
            if (!page.addSent || CalendarService.linkBusy) return
            page.addSent = false
            if (CalendarService.linkError) return
            page.closeForm()
            page.followUp(2)
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Source"
        // Whether the dashboard's new events can go into them depends on the
        // distribution: they are written through KDE's Akonadi Python
        // bindings, which Fedora packages and Arch and openSUSE Leap do not
        // (CalendarService.writerState, asked once when the calendar starts).
        description: CalendarService.writerReady
            ? "Reads the KDE calendars, like the Plasma clock, and new events from the dashboard go into them. Google accounts and other calendars are set up in Merkuro (KDE)."
            : CalendarService.writerState === "missing"
            ? "Reads the KDE calendars, like the Plasma clock. New events are made in Merkuro (KDE): this system does not have KDE's Akonadi Python bindings. Google accounts and other calendars are set up there too."
            : "Reads the KDE calendars, like the Plasma clock. Google accounts and other calendars are set up in Merkuro (KDE)."

        ListRow {
            interactive: false
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
            // Which calendars are shown is the machine's.
            scope: "calendar.hiddenCalendars"
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
                    // The row is the one tab stop (Space and Return toggle it
                    // through onClicked); the toggle keeps its click and takes
                    // its name from the row's title (ListRow.nameTrailing).
                    ShellToggle {
                        checked: calendarRow.shown
                        onToggled: value => CalendarService.setCalendarVisible(calendarRow.modelData.id, value)
                    }
                }
            }
        }
    }

    // A published calendar as one more KDE calendar: Outlook's meetings here,
    // where Exchange is no longer reachable any other way (scripts/
    // calendar-link.py makes an Akonadi iCal resource on the link).
    SettingsSection {
        Layout.fillWidth: true
        title: "Calendars from a link"
        description: "A published calendar, such as Outlook's \"Publish a calendar\" ICS link or a Google calendar's secret address. Read-only and fetched again every " + Links.REFRESH_MINUTES + " minutes. Anyone who has such a link can read the calendar: keep it like a password."

        // Keyed by the resource id: a list read anew keeps its rows, and an
        // armed Remove stays armed (kept_rows_test.py).
        Repeater {
            model: ScriptModel { values: CalendarService.linkCalendars.map(row => row.id) }
            ListRow {
                id: linkRow
                required property string modelData
                readonly property var calendar: CalendarService.linkCalendars.find(row => row.id === modelData) || null
                Layout.fillWidth: true
                interactive: false
                compact: true
                level: 1
                icon: "\u{f0339}"
                title: calendar ? calendar.name : ""
                subtitle: calendar ? calendar.subtitle : ""
                ShellButton {
                    focusOnTab: true
                    icon: Icons.refresh
                    compact: true
                    variant: "ghost"
                    toolTip: "Fetch now"
                    enabledState: !CalendarService.linkBusy
                    onClicked: if (CalendarService.syncLink(linkRow.modelData)) page.followUp(2)
                }
                ShellButton {
                    focusOnTab: true
                    icon: Icons.remove
                    text: "Remove"
                    compact: true
                    confirm: true
                    confirmText: "Remove?"
                    enabledState: !CalendarService.linkBusy
                    toolTip: "Takes the calendar out of KDE; the published calendar itself stays as it is"
                    onClicked: CalendarService.removeLink(linkRow.modelData)
                }
            }
        }

        ShellButton {
            visible: !page.adding
            focusOnTab: true
            icon: Icons.add
            text: "Add calendar from a link …"
            onClicked: { page.adding = true; Qt.callLater(() => linkField.focusInput(Qt.TabFocusReason)) }
        }

        SettingRow {
            visible: page.adding
            Layout.fillWidth: true
            label: "Link"
            ShellTextField {
                id: linkField
                Layout.fillWidth: true
                focusOnTab: true
                placeholder: "https://… or webcal://…"
                accessibleName: "Calendar link"
                enabledState: !CalendarService.linkBusy
                onAccepted: page.sendLink()
                onEscapePressed: page.closeForm()
            }
        }
        SettingRow {
            visible: page.adding
            Layout.fillWidth: true
            label: "Name"
            ShellTextField {
                id: nameField
                Layout.fillWidth: true
                focusOnTab: true
                placeholder: "Outlook"
                accessibleName: "Calendar name"
                enabledState: !CalendarService.linkBusy
                onAccepted: page.sendLink()
                onEscapePressed: page.closeForm()
            }
        }
        RowLayout {
            visible: page.adding
            spacing: Metrics.spaceSm
            ShellButton {
                focusOnTab: true
                variant: "accent"
                icon: Icons.add
                text: CalendarService.linkState === "adding" ? "Adding …" : "Add"
                enabledState: linkField.text.trim().length > 0 && !CalendarService.linkBusy
                onClicked: page.sendLink()
            }
            ShellButton {
                focusOnTab: true
                variant: "ghost"
                text: "Cancel"
                enabledState: !CalendarService.linkBusy
                onClicked: page.closeForm()
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: CalendarService.linkMessage
            role: "small"
            wrapMode: Text.WordWrap
            color: CalendarService.linkError ? Colors.danger : Colors.mutedText
        }
        ShellText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: CalendarService.linkPreview
            role: "small"
            muted: true
            font.family: Typography.monoFamily
            wrapMode: Text.WrapAnywhere
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
