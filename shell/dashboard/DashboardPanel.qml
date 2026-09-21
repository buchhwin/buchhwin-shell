import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/calendar/WeekLogic.js" as Week
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/dashboard/DashboardLogic.js" as Dash
import "../../services/arrange/FitLogic.js" as Fit
import "../../services/appearance/TimeFormat.js" as TimeFormat

// Time / weather / calendar dashboard (Super+K or click on the clock).
// Weather comes from Open-Meteo, events from the KDE calendars (Akonadi).
ShellPanel {
    id: root
    panelId: "dashboard"
    placement: "top-right"
    // Month, week or day. Only the week view widens the card; the
    // clock/weather column keeps its width.
    readonly property string calendarView: SettingsService.value("calendar.dashboardView")
    readonly property bool weekView: calendarView === "week"
    readonly property bool dayView: calendarView === "day"
    // Both time-grid views replace the month calendar.
    readonly property bool gridView: weekView || dayView
    // The dashboard is a grid the user sizes, the way the control center and
    // the notch are. Its own size is dragged from the grip on its bottom left
    // corner while the cards are being arranged; until it is, the width the
    // chosen view asks for is the default - the week view needs more room than
    // the month, and nobody should have to drag for that.
    readonly property real minPanelHeight: header.height + Metrics.dashboardGridUnit
        + Metrics.panelPadding * 2 + Metrics.spaceLg
    readonly property var sizeBounds: ({ minWidth: Metrics.dashboardMinWidth,
                                         maxWidth: Metrics.dashboardMaxWidth,
                                         width: weekView ? Metrics.dashboardWeekWidth : Metrics.dashboardWidth,
                                         minHeight: minPanelHeight,
                                         room: roomBelowTop })
    readonly property var box: Arrange.panelBox(SettingsService.value("desktop.dashboardWidth"),
                                                SettingsService.value("desktop.dashboardHeight"),
                                                sizeBounds)
    property bool sizing: false
    property real dragWidth: 0
    property real dragHeight: 0
    cardWidth: sizing ? dragWidth : box.width
    cardHeight: sizing ? dragHeight : box.height
    readonly property bool editing: LayoutService.dashboardEditing
    // The dashboard's own cards that are not on it, and then every desktop
    // widget that is not either.
    readonly property var missing: LayoutService.tileChoices(
        Dash.missing(LayoutService.dashboardTypes), LayoutService.dashboardTypes)
    property date selectedDay: clock.date
    readonly property bool selectedIsToday: selectedDay.toDateString() === clock.date.toDateString()
    // Dialogs opened from here (new event, event details) return to this day.
    readonly property var returnArgs: ({ day: SettingsService.locale.toString(selectedDay, "yyyy-MM-dd") })

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // The month grid is one of the cards now: it can be hidden by the view, or
    // taken off the dashboard altogether, so it is held by reference rather
    // than by an id, and every path that used to reach for it copes without.
    property Item monthGrid: null

    // The calendar service reads the six-week grid of one month: the shown
    // month, in the week view the month of the week's Monday (its grid always
    // contains the whole week), in the day view the month of the shown day.
    function syncMonth() {
        if (gridView) {
            const first = Week.rangeStart(selectedDay, dayView ? 1 : 7, 1)
            CalendarService.showMonth(first.getFullYear(), first.getMonth())
        } else if (monthGrid) {
            CalendarService.showMonth(monthGrid.year, monthGrid.month)
        } else {
            // No month grid on the dashboard: the day's events still need the
            // month around the day that is selected.
            CalendarService.showMonth(selectedDay.getFullYear(), selectedDay.getMonth())
        }
    }

    // Puts the month grid, whenever there is one, on a given day.
    function showDay(day) {
        selectedDay = day
        if (!monthGrid) return
        monthGrid.year = day.getFullYear()
        monthGrid.month = day.getMonth()
        monthGrid.selectedDate = day
    }

    onSelectedDayChanged: if (gridView) syncMonth()
    onCalendarViewChanged: {
        if (!gridView) showDay(selectedDay)
        syncMonth()
    }

    onShownChanged: if (!shown) {
        LayoutService.dashboardEditing = false
        sizing = false
    }

    onWantedChanged: {
        if (wanted) {
            if (monthGrid) monthGrid.reset()
            selectedDay = clock.date
            const parts = String(PanelService.args.day || "").split("-").map(Number)
            if (parts.length === 3 && parts.every(part => part > 0))
                showDay(new Date(parts[0], parts[1] - 1, parts[2]))
            syncMonth()
            WeatherService.track()
        } else {
            WeatherService.untrack()
        }
    }

    // The grip that sizes the panel, on the corner that grows. On the overlay
    // rather than in the card, which clips. Only while the cards are being
    // arranged, the way the control center's is.
    Rectangle {
        parent: root.overlay
        visible: root.editing
        x: root.cardRect.x + Metrics.spaceXxs
        y: root.cardRect.y + root.cardRect.height - height - Metrics.spaceXxs
        width: Metrics.iconSm
        height: width
        radius: width / 2
        color: grip.pulling || grip.containsMouse ? Colors.accentHover : Colors.accent
        border.width: Metrics.borderWidth
        border.color: Colors.accent

        MouseArea {
            id: grip
            anchors.fill: parent
            anchors.margins: -Metrics.spaceXs
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeBDiagCursor
            readonly property bool pulling: root.sizing
            // The corner the card is anchored by, taken once at the press: the
            // live edge moves with the width wherever the panel is anchored to
            // something, and the drag would chase its own result.
            property real fromRight: 0
            property real fromTop: 0
            property real pressX: 0
            property real pressY: 0
            property bool moved: false
            onPressed: mouse => {
                const point = mapToItem(root.overlay, mouse.x, mouse.y)
                fromRight = root.cardRect.x + root.cardRect.width
                fromTop = root.cardRect.y
                pressX = point.x
                pressY = point.y
                moved = false
                root.dragWidth = root.cardRect.width
                root.dragHeight = root.cardRect.height
                root.sizing = true
            }
            onPositionChanged: mouse => {
                if (!root.sizing) return
                const point = mapToItem(root.overlay, mouse.x, mouse.y)
                if (!moved) {
                    if (Math.abs(point.x - pressX) + Math.abs(point.y - pressY) < Metrics.dragThreshold) return
                    moved = true
                }
                const wanted = Arrange.panelDragTo(point.x, point.y,
                                                   { right: fromRight, top: fromTop }, root.sizeBounds)
                root.dragWidth = wanted.width
                root.dragHeight = wanted.height
            }
            onReleased: {
                if (!root.sizing) return
                root.sizing = false
                // A press that never moved is not a resize.
                if (moved) LayoutService.dashboardResize(root.dragWidth, root.dragHeight)
                moved = false
            }
            onCanceled: {
                root.sizing = false
                moved = false
            }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceLg

        RowLayout {
            id: header
            Layout.fillWidth: true
            ShellText { text: "buchhwin-shell"; role: "label"; color: Colors.text; font.capitalization: Font.MixedCase }
            Rectangle { Layout.preferredWidth: Metrics.spaceLg; height: Metrics.borderWidth; color: Colors.mutedText }
            Item { Layout.fillWidth: true }
            // Taller than the header text: it overlaps the spacing instead of
            // growing the header (the dashboard already fills 800 px screens).
            Item {
                Layout.preferredWidth: viewSwitch.implicitWidth
                Layout.preferredHeight: shortcutLabel.implicitHeight
                SegmentedControl {
                    id: viewSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    width: implicitWidth
                    height: Metrics.controlHeightSm
                    options: [{ value: "month", label: "Month" }, { value: "week", label: "Week" }, { value: "day", label: "Day" }]
                    current: root.calendarView
                    onSelected: value => SettingsService.set("calendar.dashboardView", value)
                }
            }
            ShellButton {
                Layout.leftMargin: Metrics.spaceMd
                icon: Icons.edit
                variant: root.editing ? "accent" : "ghost"
                iconSize: Metrics.iconMd
                toolTip: root.editing ? "Done arranging" : "Arrange cards"
                onClicked: LayoutService.dashboardEditing = !LayoutService.dashboardEditing
            }
            SectionLabel { id: shortcutLabel; Layout.leftMargin: Metrics.spaceMd; text: "Super + K" }
        }

        // What does not fit the height the user chose scrolls, rather than
        // being cut off below the card's edge. The granted height may only be
        // read when one is stored: without one the card measures its own
        // content, and reading it back here would be a binding loop.
        ScrollList {
            Layout.fillWidth: true
            card: false
            maxHeight: Math.max(Metrics.dashboardGridUnit,
                (root.cardHeight > 0 ? root.cardTargetHeight : root.roomBelowTop)
                - header.height - Metrics.panelPadding * 2 - Metrics.spaceLg * 2)

            ColumnLayout {
                width: parent.width
                spacing: Metrics.spaceLg

                // The cards place themselves from ArrangeLogic rather than from
                // a layout: a layout owns its children's geometry and cannot
                // let them glide aside.
                ArrangeArea {
                    id: cardArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    columns: Arrange.columnsFor(width, Metrics.dashboardGridCell, Metrics.dashboardGridColumns)
                    gap: Metrics.spaceLg
                    unit: Metrics.dashboardGridUnit
                    editing: root.editing
                    maxRows: LayoutService.gridMaxRows
                    animated: !root.sizing
                    dragLayer: root.overlay
                    model: LayoutService.dashboardItems.map(item => ({ id: item.id, w: item.w, h: item.h,
                        minW: Dash.minSize(item.type).w, minH: Dash.minSize(item.type).h }))
                    onCommitted: (id, index) => LayoutService.dashboardMoveTo(id, index)
                    onPlacementChanged: reportTimer.restart()
                    onWidthChanged: reportTimer.restart()

                    Repeater {
                        model: LayoutService.dashboard.dashboard
                        DashboardSlot {
                            required property var modelData
                            required property int index
                            area: cardArea
                            cardId: modelData.id
                            type: modelData.items[0].type
                            slotIndex: index
                            content: root.cardFor(modelData.items[0].type)
                        }
                    }
                }

                // One compact row while arranging: the cards that are off, undo
                // and the way back. The pencil in the header is the Done
                // button, so there is not a second one.
                CardSection {
                    Layout.fillWidth: true
                    visible: root.editing
                    padding: Metrics.spaceSm
                    spacing: Metrics.spaceXs

                    Flow {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceXs
                        Repeater {
                            model: root.missing
                            ShellButton {
                                required property var modelData
                                icon: modelData.icon
                                variant: "surface"
                                compact: true
                                toolTip: modelData.label
                                onClicked: LayoutService.dashboardAdd(modelData.type)
                            }
                        }
                        ShellButton {
                            icon: Icons.undo
                            variant: "ghost"
                            compact: true
                            enabledState: LayoutService.undoStack.length > 0
                            toolTip: "Undo"
                            onClicked: LayoutService.undo()
                        }
                        ShellButton {
                            icon: Icons.reset
                            variant: "ghost"
                            compact: true
                            confirm: true
                            confirmText: "Reset"
                            toolTip: "Back to the default cards"
                            onClicked: LayoutService.dashboardReset()
                        }
                    }
                }
            }
        }
    }

    // Reported from the layout's resting cells, not from the items: a card
    // glides to its new place and a report would fire long before it arrived.
    function reportCells() {
        const cells = {}
        for (const item of LayoutService.dashboardItems) {
            const cell = cardArea.cellOf(item.id)
            if (cell) cells[item.id] = { x: Math.round(cell.x), y: Math.round(cell.y),
                                         width: Math.round(cell.width), height: Math.round(cell.height),
                                         w: cell.w, h: cell.h }
        }
        LayoutService.reportDashboardCells(cells)
    }

    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: root.reportCells()
    }

    Component.onDestruction: LayoutService.reportDashboardCells({})

    function cardFor(type) {
        switch (type) {
        case "clock": return clockCard
        case "weather": return weatherCard
        case "calendar": return calendarCard
        case "agenda": return agendaCard
        case "events": return eventsCard
        case "media": return mediaCard
        case "system": return systemCard
        }
        // Not one of the dashboard's own cards: a desktop widget it accepts.
        return WidgetRegistry.isAvailable(type) ? widgetCardItem : null
    }

    // Every card is an Item with its real content anchored to the top, so a
    // cell taller than the card leaves room under it and a shorter one is cut
    // off at its own edge (DashboardSlot clips). `shown` is the contract
    // DashboardSlot reads: a card the chosen view has no use for holds no
    // place, the way a quick tile with nothing to show holds none.
    Component {
        id: clockCard
        Item {
            id: clockBody
            readonly property bool shown: true
            // 84 px of time needs two grid rows to itself and four to sit
            // over a long date. Below that the clock steps down rather than
            // being cut off at its own baseline, and the date shortens with
            // it - the same ladder the date widget has always had.
            readonly property bool tiny: fitClass === "icon"
            readonly property bool short: fitClass === "small" || fitClass === "wide"
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 0
                // Raw Text, not ShellText: the clock needs tabular figures so
                // the digits do not shift every minute.
                Text {
                    text: TimeFormat.time(clock.date, SettingsService.twelveHourClock, " : ")
                    color: Colors.text
                    font.family: Typography.family
                    font.pixelSize: clockBody.tiny ? Typography.headlineSize
                        : clockBody.short ? Typography.displaySize : Typography.dashboardClockSize
                    font.weight: Typography.light
                    font.features: { "tnum": 1 }
                    renderType: Typography.renderType
                }
                ShellText {
                    Layout.fillWidth: true
                    visible: !clockBody.tiny
                    text: SettingsService.locale.toString(clock.date,
                        clockBody.short ? "ddd, MMM d" : "dddd, MMMM d")
                    role: clockBody.short ? "small" : "headline"
                    font.weight: Typography.light
                }
            }
        }
    }

    Component {
        id: weatherCard
        Item {
            readonly property bool shown: true
            WeatherCard {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                // The card has always been able to put the seven days beside
                // the hourly strip instead of under it; nothing ever asked it
                // to, so a card pulled two columns wide stayed a narrow stack
                // with empty space next to it.
                wide: fitClass === "wide" || fitClass === "large"
                // Side by side, both halves fit in half the height.
                showHourly: gridH >= (wide ? 2 : 3)
                showDaily: gridH >= (wide ? 3 : 4)
                showLocation: gridH >= (wide ? 3 : 5)
            }
        }
    }

    Component {
        id: calendarCard
        Item {
            // The month grid and the week grid are two cards, and the view
            // switch decides which of them has anything to show.
            readonly property bool shown: !root.gridView
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                padding: Metrics.spaceMd

                CalendarMonth {
                    id: grid
                    Layout.fillWidth: true
                    today: clock.date
                    selectable: true
                    eventDays: CalendarService.eventDays
                    onYearChanged: if (!root.gridView) CalendarService.showMonth(year, month)
                    onMonthChanged: if (!root.gridView) CalendarService.showMonth(year, month)
                    onDaySelected: day => root.selectedDay = day
                    // The panel reaches for the grid rather than the other way
                    // round, because this card can be hidden or removed.
                    Component.onCompleted: root.monthGrid = grid
                    Component.onDestruction: if (root.monthGrid === grid) root.monthGrid = null
                }
            }
        }
    }

    Component {
        id: agendaCard
        Item {
            readonly property bool shown: root.gridView
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                padding: Metrics.spaceMd

                WeekView {
                    Layout.fillWidth: true
                    dayCount: root.dayView ? 1 : 7
                    today: clock.date
                    selectedDate: root.selectedDay
                    onDaySelected: day => root.selectedDay = day
                    onEventClicked: event => CalendarService.openEvent(event, root.returnArgs)
                    onCreateRequested: day => {
                        root.selectedDay = day
                        CalendarService.openEditor(day, root.returnArgs)
                    }
                }
            }
        }
    }

    // The control center already wraps this exact card the same way; the two
    // surfaces differ in the size they start it at, not in the card.
    Component {
        id: mediaCard
        Item {
            readonly property bool shown: true
            MediaCard {
                anchors.fill: parent
                // The card centres its content in whatever height it is given
                // and steps its own form down from the cell's shape, which is
                // the whole reason it could be lifted here unchanged.
                shape: fitClass
            }
        }
    }

    // CPU, memory and disk together. All three are reachable one at a time as
    // widgets already; what was missing is the card that shows them at once,
    // which is what the system popup has always done.
    Component {
        id: systemCard
        Item {
            id: systemBody
            readonly property bool shown: true
            // Sampling runs only while something is watching. Without this
            // pair the meters sit at zero and look broken rather than idle.
            Component.onCompleted: SystemStatsService.track()
            Component.onDestruction: SystemStatsService.untrack()

            // A meter is a glyph, a name, a figure and a bar. How many fit is
            // a question about pixels, not about grid steps - the same
            // arithmetic the notch's event list uses.
            readonly property real rowHeight: Typography.bodySize + Metrics.meterHeight + Metrics.spaceXs
            readonly property int rows: Math.min(3, Fit.rowsFor(
                systemBody.height - Metrics.spaceLg * 2 - Typography.titleSize - Metrics.spaceMd,
                rowHeight, Metrics.spaceMd))
            // One column has no room for the figures beside the names; what
            // that costs is written down where the meters are drawn.
            readonly property bool roomForDetail: gridW > 1

            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                title: fitClass === "icon" ? "" : "System"

                SystemMeters {
                    Layout.fillWidth: true
                    maxRows: systemBody.rows
                    showDetail: systemBody.roomForDetail
                }
            }
        }
    }

    Component {
        id: eventsCard
        Item {
            id: eventsBody
            readonly property bool shown: true
            // One column has no room for two buttons beside a date.
            readonly property bool narrow: gridW <= 1
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                RowLayout {
                    id: eventsHeader
                    Layout.fillWidth: true
                    ShellText {
                        text: root.selectedIsToday ? "Today"
                            : SettingsService.locale.toString(root.selectedDay, "dddd")
                        role: "title"
                    }
                    Item { Layout.fillWidth: true }
                    ShellText {
                        text: SettingsService.locale.toString(root.selectedDay, "ddd, MMM d")
                        role: "small"
                        muted: true
                    }
                    ShellButton {
                        icon: Icons.add
                        variant: "ghost"
                        compact: true
                        toolTip: "New event"
                        onClicked: CalendarService.openEditor(root.selectedDay, root.returnArgs)
                    }
                    ShellButton {
                        icon: "󰃭"
                        variant: "ghost"
                        compact: true
                        visible: !eventsBody.narrow
                        toolTip: "Open in Merkuro"
                        onClicked: CalendarService.openManager()
                    }
                }
                EventList {
                    Layout.fillWidth: true
                    day: root.selectedDay
                    isToday: root.selectedIsToday
                    returnArgs: root.returnArgs
                    // What the cell has room for under the header, counted the
                    // way the notch's events block counts: a shorter card
                    // shows fewer events and says how many it left out, rather
                    // than the top half of all of them.
                    maxRows: Fit.rowsFor(eventsBody.height - eventsHeader.height - Metrics.spaceMd * 3,
                                         Metrics.rowHeight, Metrics.spaceSm)
                }
            }
        }
    }

    // Anything not in the catalogue is a desktop widget - the same file the
    // desktop, the bar and the notch load, on a card like every other. The
    // control center has the twin of this; the two differ only in what their
    // surface calls a card.
    Component {
        id: widgetCardItem
        Item {
            id: widgetBody
            readonly property string typeName: tileType
            readonly property var entry: WidgetRegistry.type(typeName)
            readonly property string action: entry ? entry.action : ""
            readonly property bool hasData: widget.item ? widget.item.hasData !== false : false
            readonly property bool shown: true

            CardSection {
                anchors.fill: parent
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Loader {
                        id: widget
                        anchors.centerIn: parent
                        visible: widgetBody.hasData
                        source: WidgetRegistry.source(widgetBody.typeName)
                        onLoaded: {
                            // Which readout this is: three registry types
                            // share one file and are told apart by
                            // `options.metric`.
                            // `screen` as well as `type`; see OverviewPage.
                            item.instance = Qt.binding(() => ({
                                id: widgetBody.typeName, type: widgetBody.typeName,
                                screen: PanelService.screen ? PanelService.screen.name : "",
                                options: widgetBody.entry && widgetBody.entry.options
                                    ? widgetBody.entry.options : {} }))
                        }
                    }
                    // A binding, not a line in `onLoaded`: the cell keeps
                    // changing after the widget is loaded.
                    Binding {
                        target: widget.item
                        property: "sizeClass"
                        value: Fit.widgetSize(widgetBody.width, widgetBody.height)
                        when: widget.item !== null
                    }

                    Row {
                        anchors.centerIn: parent
                        visible: !widgetBody.hasData
                        spacing: Metrics.spaceSm
                        ShellIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: widgetBody.entry ? widgetBody.entry.icon : ""
                            size: Metrics.iconMd
                            color: Colors.mutedText
                        }
                        ShellText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: widgetBody.entry ? widgetBody.entry.label : widgetBody.typeName
                            muted: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: widgetBody.action.length > 0
                        cursorShape: Qt.PointingHandCursor
                        // See the control center's twin: `actionArgs` says
                        // where in a panel the widget means.
                        onClicked: PanelService.open(widgetBody.action,
                                                     widgetBody.entry && widgetBody.entry.actionArgs
                                                         ? widgetBody.entry.actionArgs : {})
                    }
                }
            }
        }
    }
}
