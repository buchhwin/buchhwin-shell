import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/calendar/EventDraftLogic.js" as Draft
import "../../services/calendar/EventEditLogic.js" as Edit
import "../../services/calendar/RecurrenceLogic.js" as Rec
import "../../services/dashboard/EventDateLogic.js" as Dates
import "../../services/appearance/DateFormat.js" as DateFormat

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
    // The form follows the interface text size, as the settings window does:
    // at fixed widths the labels and "HH:MM" clipped from a text size of 1.1.
    cardWidth: Math.round(Metrics.eventEditorWidth * Typography.scale)
    readonly property int timeFieldWidth: Math.round(Metrics.timeFieldWidth * Typography.scale)

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

    // The last day the From field could be read as: an Until on that day
    // follows a new From date (EventDateLogic.withDate).
    property string followDate: ""

    // Previous day / Next day. The From field's own handler takes an end that
    // follows it along at once; the end of a longer event is moved here by as
    // much, and an end the handler already moved is not moved a second time.
    function shiftDay(days) {
        const next = Dates.shiftDay(draft, days)
        dateField.text = next.date
        endDateField.text = next.endDate
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
        // Before the date goes in, so the end the form was filled with is
        // measured against this form's date and not the last one's.
        followDate = Dates.dayOf(values.date)
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
        deleteButton.disarmNow()
        original = Edit.draftFor(event, CalendarService.identityLocation)
        originalRule = Rec.ruleDraft(CalendarService.identity, event.start)
        rule = Object.assign({}, originalRule)
        opened = original
        openedRule = originalRule
        editing = true
        fill(Object.assign({}, original))
        Qt.callLater(() => titleField.focusInput())
    }

    function stopEdit() {
        editing = false
        CalendarService.resetSave()
    }

    // ---- a form that outlives a close ----------------------------------------
    // Since the editor closes on a click on any monitor, a typed event was
    // lost to the click that went to copy its meeting link. What the form held
    // is kept when the editor closes for any reason but Save, Cancel or
    // Escape, and handed back when it opens on the same day or the same event
    // again (EventEditLogic.keptDraft / resumes); any other open starts fresh.
    //
    // What the form was filled with, to tell a typed form from an untouched
    // one, and the arguments it was opened with.
    property var opened: null
    property var openedRule: null
    property var openedArgs: null
    property var kept: null
    // An edit to hand back once the event is known to be editable: the
    // details are matched to the calendar entry after the editor opens.
    property var pendingResume: null
    // Set by the three ways out that mean "throw it away".
    property bool discard: false

    function closeAndDiscard() {
        discard = true
        PanelService.close("eventEditor")
    }

    function resumeEdit() {
        if (!pendingResume || !wanted || !details || !canChange) return
        const state = pendingResume.state
        pendingResume = null
        CalendarService.resetSave()
        deleteButton.disarmNow()
        original = state.original
        originalRule = state.originalRule
        opened = state.opened
        openedRule = state.openedRule
        rule = Object.assign({}, state.rule)
        scope = state.scope
        editing = true
        fill(Object.assign({}, state.draft))
        Qt.callLater(() => titleField.focusInput())
    }
    onCanChangeChanged: resumeEdit()
    onEscapePressed: discard = true

    // The second click of the delete button: the first only arms it
    // (ShellButton's `confirm`, the "click again" this editor started).
    function deleteEvent() {
        if (!canChange || saving) return
        CalendarService.deleteEvent(root.scope)
    }

    onWantedChanged: {
        if (!wanted) {
            // Read before `editing` is reset below. An edit still waiting for
            // its event to be matched is kept as it was.
            kept = discard ? null
                : Edit.keptDraft(openedArgs, { editing: editing, opened: opened, openedRule: openedRule,
                                               draft: draft, rule: rule, original: original,
                                               originalRule: originalRule, scope: scope })
                  || pendingResume
            discard = false
            pendingResume = null
        }
        editing = false
        deleteButton.disarmNow()
        scope = "single"
        if (wanted) {
            // An Escape in an empty field closes the editor and then reaches
            // the panel as well, after the close: its mark must not carry
            // over to the next one.
            discard = false
            const args = PanelService.args
            openedArgs = args
            const resume = Edit.resumes(kept, args) ? kept : null
            kept = null
            if (args.mode === "details") {
                // Once `details` reads the new arguments (the panel takes
                // them in its own handler of this change) - and again when
                // the event is matched, if it is not yet.
                pendingResume = resume
                Qt.callLater(root.resumeEdit)
                return
            }
            if (resume) {
                const state = resume.state
                originalRule = state.openedRule
                opened = state.opened
                openedRule = state.openedRule
                rule = Object.assign({}, state.rule)
                fill(Object.assign({}, state.draft))
                Qt.callLater(() => titleField.focusInput())
                return
            }
            const day = Draft.parseDate(args.day || "") || new Date()
            const calendar = Draft.chooseCalendar(CalendarService.newEventCalendars, SettingsService.value("calendar.newEventCalendar"))
            originalRule = Rec.emptyDraft(day)
            rule = Object.assign({}, originalRule)
            opened = Draft.defaultDraft(day, new Date(), calendar)
            openedRule = originalRule
            fill(opened)
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
            if (CalendarService.saveState !== "saved") return
            // A save that lands after the editor closed (a click elsewhere
            // while the helper was still writing) is in the calendar now:
            // what was kept of it is no draft any more, and handed back it
            // would be saved a second time.
            if (root.wanted) root.closeAndDiscard()
            else root.kept = null
        }
    }

    component FieldLabel: ShellText {
        Layout.preferredWidth: Math.round(Metrics.formLabelWidth * Typography.scale)
        role: "small"
        muted: true
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceMd

        // ---- header ----------------------------------------------------
        // The one dialog header, like the Wi-Fi and pairing dialogs. The
        // event keeps its calendar's colour as the ink of the glyph.
        PanelHeader {
            Layout.fillWidth: true
            role: "title"
            icon: root.details ? "󰃭" : Icons.add
            iconColor: root.details ? Colors.foreground(CalendarService.colorFor(root.event)) : Colors.accentForeground
            title: root.editing ? "Edit event" : root.details ? root.event.title : "New event"
            subtitle: {
                if (root.details && !root.editing) {
                    const event = root.event
                    const day = DateFormat.date(event.start, SettingsService.locale, "long")
                    return day + " · " + CalendarService.formatRange(event)
                }
                const date = Draft.parseDate(root.draft.date)
                return date ? DateFormat.date(date, SettingsService.locale, "year") : "Choose a date"
            }
        }

        Divider {}

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
        // Every control is a Tab stop, in the order it is drawn: with only the
        // text fields in the walk, the switch, the choices and the buttons
        // were the mouse's alone.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.form
            spacing: Metrics.spaceMd

            ShellTextField {
                id: titleField
                Layout.fillWidth: true
                focusOnTab: true
                icon: Icons.modify
                placeholder: "Title"
                onTextChanged: root.update({ title: text })
                onAccepted: root.submit()
                onEscapePressed: if (!text.length && !root.editing) root.closeAndDiscard()
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
                    focusOnTab: true
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
                    icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Previous day"
                    focusOnTab: true
                    onClicked: root.shiftDay(-1)
                }
                ShellTextField {
                    id: dateField
                    Layout.fillWidth: true
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "YYYY-MM-DD"
                    error: !Draft.parseDate(text)
                    onTextChanged: {
                        // Keep a one-day all-day event on one day while the
                        // date moves, typed key by key as well as stepped.
                        const next = Dates.withDate(root.draft, text, root.followDate)
                        root.followDate = next.followed
                        root.update({ date: next.date })
                        if (endDateField.text !== next.endDate) endDateField.text = next.endDate
                    }
                    onAccepted: root.submit()
                }
                ShellButton {
                    icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Next day"
                    focusOnTab: true
                    onClicked: root.shiftDay(1)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.draft.allDay && !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: "Until" }
                ShellButton { icon: Icons.back; variant: "ghost"; compact: true; toolTip: "Ends a day earlier"; focusOnTab: true; onClicked: endDateField.text = Draft.shiftDate(endDateField.text, -1) }
                ShellTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "YYYY-MM-DD"
                    error: !Draft.parseDate(text)
                    onTextChanged: root.update({ endDate: text })
                    onAccepted: root.submit()
                }
                ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; toolTip: "Ends a day later"; focusOnTab: true; onClicked: endDateField.text = Draft.shiftDate(endDateField.text, 1) }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.draft.allDay && !root.locked
                spacing: Metrics.spaceSm
                FieldLabel { text: "Time" }
                ShellTextField {
                    id: startField
                    Layout.preferredWidth: root.timeFieldWidth
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "HH:MM"
                    error: !Draft.parseTime(text)
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
                    Layout.preferredWidth: root.timeFieldWidth
                    focusOnTab: true
                    selectAllOnFocus: true
                    placeholder: "HH:MM"
                    error: !Draft.parseTime(text) || root.currentDuration === 0
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
                    focusOnTab: true
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
                    focusOnTab: true
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
                    focusOnTab: true
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
                    error: !Draft.parseDate(text)
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
                    Layout.preferredWidth: root.timeFieldWidth
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
                        focusOnTab: true
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
                icon: Icons.location
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
            color: Colors.surface1
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
                focusOnTab: true
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
                id: deleteButton
                icon: Icons.remove
                text: root.saving ? "Deleting …" : root.recurring && root.wholeSeries ? "Delete series" : "Delete"
                variant: "danger"
                confirm: true
                confirmText: root.recurring && root.wholeSeries ? "Delete series?" : "Delete?"
                visible: root.canChange || root.saving
                enabledState: root.canChange && !root.saving
                focusOnTab: true
                // Arming clears an earlier error or preview, as the first
                // click always has.
                onArmedChanged: if (armed) CalendarService.resetSave()
                onClicked: root.deleteEvent()
            }
            Item { Layout.fillWidth: true }
            ShellButton { icon: Icons.leavesPanel; text: root.canChange ? "Merkuro" : "Open in Merkuro"; variant: root.canChange ? "ghost" : "accent"; focusOnTab: true; onClicked: CalendarService.openManager() }
            ShellButton {
                icon: Icons.modify
                text: "Edit"
                variant: "accent"
                visible: root.canChange
                enabledState: !root.saving
                focusOnTab: true
                onClicked: root.startEdit()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.form
            spacing: Metrics.spaceSm
            ShellText {
                // What stops the save is an error and reads as one, like the
                // save's own error above; "Saving …" and "No changes yet"
                // are news, not faults, and stay quiet.
                readonly property bool fault: !root.saving && !root.check.ok && root.saveState !== "error"
                    && (root.editing || root.draft.title.trim().length > 0)
                Layout.fillWidth: true
                text: root.saving ? "Saving …"
                    : fault ? root.check.error
                    : root.editing && !root.changedFields.length && root.saveState === "" ? "No changes yet" : ""
                role: "small"
                color: fault ? Colors.danger : Colors.mutedText
                elide: Text.ElideRight
            }
            ShellButton {
                text: root.editing ? "Back" : "Cancel"
                variant: "ghost"
                enabledState: !root.saving
                focusOnTab: true
                onClicked: root.editing ? root.stopEdit() : root.closeAndDiscard()
            }
            ShellButton {
                text: CalendarService.writeAllowed ? "Save" : "Show request"
                variant: "accent"
                // Not while the shell cannot write: a form opened before the one-shot
                // bindings check answered (createEvent and changeEvent refuse too).
                enabledState: root.check.ok && !root.saving && (!root.editing || root.changedFields.length > 0)
                    && !CalendarService.writesBlocked
                focusOnTab: true
                onClicked: root.submit()
            }
        }
    }
}
