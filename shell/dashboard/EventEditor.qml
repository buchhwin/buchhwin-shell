import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/calendar/EventDraftLogic.js" as Draft
import "../../services/calendar/EventEditLogic.js" as Edit
import "../../services/calendar/RecurrenceLogic.js" as Rec

// New calendar event (PanelService args { mode: "new", day: "YYYY-MM-DD" })
// or the details of an existing one ({ mode: "details", event }). Opened over
// the dashboard or the events popup with PanelService.openOver, so closing
// returns there. Details offer Edit (the same form, prefilled) and Delete
// (second click confirms) once CalendarService matched the event to a single,
// non-recurring calendar entry; everything else points to Merkuro.
ShellPanel {
    id: root
    panelId: "eventEditor"
    placement: "center"
    cardWidth: Metrics.eventEditorWidth

    readonly property bool details: openArgs && openArgs.mode === "details"
    readonly property var event: details ? openArgs.event : null
    readonly property string saveState: CalendarService.saveState
    readonly property bool saving: saveState === "saving"
    readonly property bool canChange: CalendarService.identityState === "ok" && Edit.sameEvent(CalendarService.identityEvent, event)
    // Edit form of an existing event (details → Edit).
    property bool editing: false
    property var original: null
    readonly property bool locked: editing && Edit.timesLocked(event)
    readonly property bool form: !details || editing
    property bool confirmDelete: false
    property var draft: Draft.defaultDraft(new Date(), new Date(), "")
    // How often the event repeats, as the editor shows it. The rule itself is
    // built by the helper: the editor only ever sends these fields.
    property var rule: Rec.emptyDraft(new Date())
    property var originalRule: Rec.emptyDraft(new Date())
    // "single" or "series": which part of a recurring event a save or a delete
    // is meant for. One occurrence is the safer default.
    property string scope: "single"
    readonly property bool recurring: CalendarService.identityRecurs && root.canChange
    readonly property bool wholeSeries: !root.recurring || root.scope === "series"
    // The repetition is offered for a new event and when the whole series is
    // being edited, and only while the rule is one this editor can show again.
    readonly property bool repeatEditable: root.form && !root.locked
        && (!root.editing || (root.wholeSeries && root.rule.known))
    readonly property var check: editing ? Edit.validate(draft, original, locked, rule) : Draft.validate(draft)
    readonly property var changedFields: editing ? Edit.changes(original, draft, originalRule, rule) : []
    readonly property int currentDuration: Draft.duration(draft.start, draft.end)

    function update(changes) {
        draft = Object.assign({}, draft, changes)
        if (saveState === "error" || saveState === "preview") CalendarService.resetSave()
    }

    function setRule(changes) {
        rule = Object.assign({}, rule, changes)
        if (saveState === "error" || saveState === "preview") CalendarService.resetSave()
    }

    function submit() {
        if (saving) return
        if (editing) CalendarService.changeEvent(original, draft, locked, originalRule, rule, root.scope)
        else CalendarService.createEvent(draft, rule)
    }

    function fill(values) {
        draft = values
        titleField.text = values.title
        locationField.text = values.location
        notesField.text = values.notes
        startField.text = values.start
        endField.text = values.end
        dateField.text = values.date
        endDateField.text = values.endDate
        countField.text = String(rule.count)
        untilField.text = rule.until.length ? rule.until : values.date
        draft = values
    }

    function startEdit() {
        if (!canChange) return
        CalendarService.resetSave()
        confirmDelete = false
        original = Edit.draftFor(event, CalendarService.identityLocation)
        originalRule = Rec.ruleDraft(CalendarService.identity, event.start)
        rule = Object.assign({}, originalRule)
        editing = true
        fill(Object.assign({}, original))
        Qt.callLater(() => titleField.focusInput())
    }

    function stopEdit() {
        editing = false
        CalendarService.resetSave()
    }

    function pressDelete() {
        if (!canChange || saving) return
        if (!confirmDelete) {
            CalendarService.resetSave()
            confirmDelete = true
            confirmReset.restart()
            return
        }
        confirmDelete = false
        CalendarService.deleteEvent(root.scope)
    }

    Timer { id: confirmReset; interval: 4000; onTriggered: root.confirmDelete = false }

    onWantedChanged: {
        editing = false
        confirmDelete = false
        scope = "single"
        if (wanted) {
            if (PanelService.args.mode === "details") return
            const day = Draft.parseDate(PanelService.args.day || "") || new Date()
            const calendar = Draft.chooseCalendar(CalendarService.newEventCalendars, SettingsService.value("calendar.newEventCalendar"))
            originalRule = Rec.emptyDraft(day)
            rule = Object.assign({}, originalRule)
            fill(Draft.defaultDraft(day, new Date(), calendar))
            Qt.callLater(() => titleField.focusInput())
        } else {
            CalendarService.editorPreview = false
        }
    }

    // The calendar list may arrive after the dialog opened.
    Connections {
        target: CalendarService
        function onNewEventCalendarsChanged() {
            if (root.wanted && !root.details && !root.draft.calendarId.length)
                root.update({ calendarId: Draft.chooseCalendar(CalendarService.newEventCalendars, SettingsService.value("calendar.newEventCalendar")) })
        }
        function onSaveStateChanged() {
            if (CalendarService.saveState === "saved" && root.wanted) PanelService.close("eventEditor")
        }
    }

    component FieldLabel: ShellText {
        Layout.preferredWidth: Metrics.formLabelWidth
        role: "small"
        muted: true
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceMd

        // ---- header ----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd
            Rectangle {
                readonly property color base: CalendarService.colorFor(root.event)
                Layout.preferredWidth: Metrics.popupIconTile
                Layout.preferredHeight: Metrics.popupIconTile
                Layout.alignment: Qt.AlignTop
                radius: width / 2
                color: root.details ? Qt.rgba(base.r, base.g, base.b, Effects.eventSwatchFill) : Colors.accent // style: an event keeps its calendar's colour
                ShellIcon {
                    anchors.centerIn: parent
                    glyph: root.details ? "󰃭" : Icons.add
                    size: Metrics.iconMd
                    color: root.details ? Colors.foreground(parent.base) : Colors.accentText
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText {
                    Layout.fillWidth: true
                    text: root.editing ? "Edit event" : root.details ? root.event.title : "New event"
                    role: "title"
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                }
                ShellText {
                    Layout.fillWidth: true
                    role: "small"
                    muted: true
                    text: {
                        if (root.details && !root.editing) {
                            const event = root.event
                            const day = SettingsService.locale.toString(event.start, "dddd, MMMM d")
                            return day + " · " + CalendarService.formatRange(event)
                        }
                        const date = Draft.parseDate(root.draft.date)
                        return date ? SettingsService.locale.toString(date, "dddd, MMMM d, yyyy") : "Choose a date"
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: Metrics.borderWidth; color: Colors.border }

        // ---- details of an existing event -------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.details && !root.editing
            spacing: Metrics.spaceMd
            ShellText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.event ? root.event.description.trim() : ""
                wrapMode: Text.Wrap
                maximumLineCount: 8
            }
            ShellText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.canChange ? (CalendarService.identityLocation.length ? "Location: " + CalendarService.identityLocation : "")
                    : CalendarService.identityState === "checking" ? "Checking whether this event can be edited here …"
                    : CalendarService.identityMessage
                role: "small"
                muted: root.canChange || CalendarService.identityState === "checking"
                color: muted ? Colors.mutedText : Colors.warning
                wrapMode: Text.Wrap
            }
        }

        // ---- new event form ---------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.form
            spacing: Metrics.spaceMd

            ShellTextField {
                id: titleField
                Layout.fillWidth: true
                focusOnTab: true
                icon: "󰏫"
                placeholder: "Title"
                onTextChanged: root.update({ title: text })
                onAccepted: root.submit()
                onEscapePressed: if (!text.length && !root.editing) PanelService.close("eventEditor")
            }

            ShellText {
                Layout.fillWidth: true
                visible: root.locked
                text: "This event lasts a day or longer: change its times in Merkuro."
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.locked
                FieldLabel { text: "All day" }
                Item { Layout.fillWidth: true }
                ShellToggle {
                    checked: root.draft.allDay
                    onToggled: value => root.update({ allDay: value })
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: root.draft.allDay ? "From" : "Date" }
                ShellButton {
                    icon: Icons.back; variant: "ghost"; compact: true
                    onClicked: { dateField.text = Draft.shiftDate(dateField.text, -1); endDateField.text = Draft.shiftDate(endDateField.text, -1) }
                }
                ShellTextField {
                    id: dateField
                    Layout.fillWidth: true
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "YYYY-MM-DD"
                    border.color: Draft.parseDate(text) ? (inputActiveFocus ? Colors.accentBorder : Colors.border) : Colors.danger
                    onTextChanged: {
                        // Keep a one-day all-day event on one day while the date moves.
                        const endFollows = root.draft.endDate === root.draft.date
                        root.update({ date: text })
                        if (endFollows && Draft.parseDate(text)) endDateField.text = Draft.formatDate(Draft.parseDate(text))
                    }
                    onAccepted: root.submit()
                }
                ShellButton {
                    icon: Icons.forward; variant: "ghost"; compact: true
                    onClicked: { dateField.text = Draft.shiftDate(dateField.text, 1); endDateField.text = Draft.shiftDate(endDateField.text, 1) }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.draft.allDay && !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: "Until" }
                ShellButton { icon: Icons.back; variant: "ghost"; compact: true; onClicked: endDateField.text = Draft.shiftDate(endDateField.text, -1) }
                ShellTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "YYYY-MM-DD"
                    border.color: Draft.parseDate(text) ? (inputActiveFocus ? Colors.accentBorder : Colors.border) : Colors.danger
                    onTextChanged: root.update({ endDate: text })
                    onAccepted: root.submit()
                }
                ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; onClicked: endDateField.text = Draft.shiftDate(endDateField.text, 1) }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.draft.allDay && !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: "Time" }
                ShellTextField {
                    id: startField
                    Layout.preferredWidth: Metrics.timeFieldWidth
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "HH:MM"
                    border.color: Draft.parseTime(text) ? (inputActiveFocus ? Colors.accentBorder : Colors.border) : Colors.danger
                    onTextChanged: {
                        // Moving the start keeps the duration.
                        const keep = root.currentDuration
                        root.update({ start: text })
                        if (keep > 0 && Draft.parseTime(text)) endField.text = Draft.endAfter(text, keep)
                    }
                    onInputActiveFocusChanged: if (!inputActiveFocus && Draft.parseTime(text)) text = Draft.normalizeTime(text)
                    onAccepted: root.submit()
                }
                ShellText { text: "–"; muted: true }
                ShellTextField {
                    id: endField
                    Layout.preferredWidth: Metrics.timeFieldWidth
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "HH:MM"
                    border.color: Draft.parseTime(text) && root.currentDuration !== 0 ? (inputActiveFocus ? Colors.accentBorder : Colors.border) : Colors.danger
                    onTextChanged: root.update({ end: text })
                    onInputActiveFocusChanged: if (!inputActiveFocus && Draft.parseTime(text)) text = Draft.normalizeTime(text)
                    onAccepted: root.submit()
                }
                ShellText {
                    Layout.fillWidth: true
                    visible: root.check.overnight
                    text: "next day"
                    role: "small"
                    muted: true
                }
                Item { Layout.fillWidth: true; visible: !root.check.overnight }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.draft.allDay && !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: "Duration" }
                SegmentedControl {
                    Layout.fillWidth: true
                    options: Draft.durations.map(minutes => ({ value: String(minutes), label: Draft.durationLabel(minutes) }))
                    current: String(root.currentDuration)
                    onSelected: value => endField.text = Draft.endAfter(startField.text, Number(value))
                }
            }

            // ---- how often it repeats --------------------------------
            // One occurrence of a series keeps the series' rule: only the
            // series itself decides how often it happens.
            ShellText {
                Layout.fillWidth: true
                visible: root.editing && root.recurring && !root.wholeSeries
                text: "This occurrence keeps the repetition of its series: " + Rec.describe(root.rule) + "."
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }

            ShellText {
                Layout.fillWidth: true
                visible: root.editing && root.wholeSeries && !root.rule.known
                text: "This event repeats in a way this editor cannot show. Change the repetition in Merkuro."
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.repeatEditable
                spacing: Metrics.spaceSm
                FieldLabel { text: "Repeat" }
                ShellSelect {
                    Layout.fillWidth: true
                    // All six choices at once: the default list height cuts the
                    // last one off and a scrollbar for six words reads badly.
                    listHeight: Metrics.popupListHeight
                    options: Rec.repeatOptions()
                    current: root.rule.repeat
                    onSelected: value => root.setRule({ repeat: value })
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.repeatEditable && root.rule.repeat.length > 0
                spacing: Metrics.spaceSm
                FieldLabel { text: "Ends" }
                ShellSelect {
                    Layout.fillWidth: true
                    options: Rec.endingOptions()
                    current: root.rule.ending
                    // The field that just appeared starts filled, or the first
                    // save fails on a number nobody was asked for.
                    onSelected: value => {
                        root.setRule({ ending: value })
                        if (value === "count") countField.text = String(root.rule.count)
                        else if (value === "until" && !Draft.parseDate(untilField.text))
                            untilField.text = root.rule.until.length ? root.rule.until : root.draft.date
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.repeatEditable && root.rule.repeat.length > 0 && root.rule.ending === "until"
                spacing: Metrics.spaceSm
                FieldLabel { text: "Last day" }
                ShellTextField {
                    id: untilField
                    Layout.fillWidth: true
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "YYYY-MM-DD"
                    border.color: Draft.parseDate(text) ? (inputActiveFocus ? Colors.accentBorder : Colors.border) : Colors.danger
                    onTextChanged: root.setRule({ until: text })
                    onAccepted: root.submit()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.repeatEditable && root.rule.repeat.length > 0 && root.rule.ending === "count"
                spacing: Metrics.spaceSm
                FieldLabel { text: "Times" }
                ShellTextField {
                    id: countField
                    Layout.preferredWidth: Metrics.timeFieldWidth
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "10"
                    onTextChanged: root.setRule({ count: Number(text) })
                    onAccepted: root.submit()
                }
                ShellText {
                    Layout.fillWidth: true
                    text: Rec.describe(root.rule)
                    role: "small"
                    muted: true
                    wrapMode: Text.Wrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                FieldLabel { text: "Calendar"; Layout.alignment: Qt.AlignTop; Layout.topMargin: Metrics.spaceSm }
                // The control and its notes belong under each other, not next
                // to each other: side by side they overlapped with wide fonts.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXxs

                    ShellText {
                        Layout.fillWidth: true
                        Layout.topMargin: Metrics.spaceSm
                        visible: root.editing
                        text: "Stays in its calendar (move events in Merkuro)."
                        role: "small"
                        muted: true
                        wrapMode: Text.Wrap
                    }
                    ShellSelect {
                        Layout.fillWidth: true
                        visible: !root.editing && CalendarService.newEventCalendars.length > 0
                        options: CalendarService.newEventCalendars
                        current: root.draft.calendarId
                        listHeight: Metrics.popupListHeight / 2
                        onSelected: value => root.update({ calendarId: value })
                    }
                    ShellText {
                        Layout.fillWidth: true
                        // A local calendar never reaches the phone; say so before
                        // the event is created, not afterwards.
                        visible: !root.editing && CalendarService.newEventCalendars.length > 0
                            && Draft.calendarIsLocal(CalendarService.newEventCalendars, root.draft.calendarId)
                        text: "This calendar is only on this computer. Pick an account calendar to see the event on your phone."
                        role: "small"
                        color: Colors.warning
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        Layout.topMargin: Metrics.spaceSm
                        visible: !root.editing && CalendarService.newEventCalendars.length === 0
                        text: CalendarService.status === "ok" ? "No writable calendar found. Add one in Merkuro."
                            : CalendarService.status === "loading" ? "Loading calendars …"
                            : "KDE calendars are unavailable."
                        role: "small"
                        color: Colors.warning
                        wrapMode: Text.Wrap
                    }
                }
            }

            ShellTextField {
                id: locationField
                Layout.fillWidth: true
                focusOnTab: true
                icon: "󰍎"
                placeholder: "Location (optional)"
                onTextChanged: root.update({ location: text })
                onAccepted: root.submit()
            }

            ShellTextField {
                id: notesField
                Layout.fillWidth: true
                focusOnTab: true
                icon: "󰎞"
                placeholder: "Notes (optional)"
                onTextChanged: root.update({ notes: text })
                onAccepted: root.submit()
            }
        }

        // ---- messages (form and delete) -----------------------------------
        ShellText {
            Layout.fillWidth: true
            visible: !CalendarService.writeAllowed && root.saveState !== "preview" && (root.form || root.canChange)
            text: "Dry run: shows what would be written, nothing is saved."
            role: "small"
            color: Colors.warning
            wrapMode: Text.Wrap
        }

        ShellText {
            Layout.fillWidth: true
            visible: root.saveState === "error" || root.saveState === "preview" || (root.saving && text.length > 0)
            text: CalendarService.saveMessage
            role: "small"
            color: root.saveState === "error" ? Colors.danger : root.saving ? Colors.mutedText : Colors.warning
            wrapMode: Text.Wrap
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.saveState === "preview"
            implicitHeight: commandText.implicitHeight + Metrics.spaceSm * 2
            radius: Metrics.radiusInner
            color: Colors.surface
            border.width: Metrics.borderWidth
            border.color: Colors.border
            Text {
                id: commandText
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                text: CalendarService.previewText
                color: Colors.text
                font.family: Typography.monoFamily
                font.pixelSize: Typography.captionSize
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                textFormat: Text.PlainText
                renderType: Typography.renderType
            }
        }

        // ---- this occurrence or the whole series --------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.recurring && (!root.details || root.editing || !root.saving)
            spacing: Metrics.spaceXxs
            ShellText {
                Layout.fillWidth: true
                text: "This event repeats"
                role: "small"
                muted: true
            }
            SegmentedControl {
                Layout.fillWidth: true
                options: [{ value: "single", label: "This event" },
                          { value: "series", label: "All events in the series" }]
                current: root.scope
                onSelected: value => { root.scope = value; CalendarService.resetSave() }
            }
            ShellText {
                Layout.fillWidth: true
                text: Rec.describe(root.editing ? root.rule : Rec.ruleDraft(CalendarService.identity, root.event ? root.event.start : null))
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.details && !root.editing
            spacing: Metrics.spaceSm
            ShellButton {
                icon: Icons.remove
                text: root.saving ? "Deleting …" : root.confirmDelete ? "Click again to delete"
                    : root.recurring && root.wholeSeries ? "Delete series" : "Delete"
                variant: "danger"
                visible: root.canChange || root.saving
                enabledState: root.canChange && !root.saving
                onClicked: root.pressDelete()
            }
            Item { Layout.fillWidth: true }
            ShellButton { icon: Icons.leavesPanel; text: root.canChange ? "Merkuro" : "Open in Merkuro"; variant: root.canChange ? "ghost" : "accent"; onClicked: CalendarService.openManager() }
            ShellButton {
                icon: "󰏫"
                text: "Edit"
                variant: "accent"
                visible: root.canChange
                enabledState: !root.saving
                onClicked: root.startEdit()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.form
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                text: root.saving ? "Saving …"
                    : !root.check.ok && root.saveState !== "error" && (root.editing || root.draft.title.trim().length) ? root.check.error
                    : root.editing && !root.changedFields.length && root.saveState === "" ? "No changes yet." : ""
                role: "small"
                muted: true
                elide: Text.ElideRight
            }
            ShellButton {
                text: root.editing ? "Back" : "Cancel"
                variant: "ghost"
                enabledState: !root.saving
                onClicked: root.editing ? root.stopEdit() : PanelService.close("eventEditor")
            }
            ShellButton {
                text: CalendarService.writeAllowed ? "Save" : "Show request"
                variant: "accent"
                enabledState: root.check.ok && !root.saving && (!root.editing || root.changedFields.length > 0)
                onClicked: root.submit()
            }
        }
    }
}
