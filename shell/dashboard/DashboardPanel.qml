import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/dashboard/DashboardLogic.js" as Dash
import "../../services/arrange/FitLogic.js" as Fit
import "../../services/appearance/TimeFormat.js" as TimeFormat
import "../../services/appearance/DateFormat.js" as DateFormat

// Time / weather / calendar dashboard (Super+K or click on the clock).
// Weather comes from Open-Meteo, events from the KDE calendars (Akonadi).
ShellPanel {
    id: root
    keyNavigation: true
    readonly property CalendarDemand calendarDemand: CalendarDemand { active: root.shown }
    panelId: "dashboard"
    placement: "top-right"
    // The dashboard is a grid the user sizes, the way the control center and
    // the notch are. Its own size is dragged from the grip on its bottom left
    // corner while the cards are being arranged; until it is, the default is
    // the width the month needs.
    readonly property real minPanelHeight: header.height + Metrics.dashboardGridUnit
        + Metrics.panelPadding * 2 + Metrics.panelGap
    sizeBounds: ({ minWidth: Metrics.dashboardMinWidth,
                                         maxWidth: Metrics.dashboardMaxWidth,
                                         width: Metrics.dashboardWidth,
                                         minHeight: minPanelHeight,
                                         room: roomBelowTop })
    readonly property var box: Arrange.panelBox(SettingsService.value("desktop.dashboardWidth"),
                                                SettingsService.value("desktop.dashboardHeight"),
                                                sizeBounds)
    // The grip and the drag live in ShellPanel; this says what it may be
    // resized to, when the grip is reachable and where the result goes.
    resizable: true
    gripShown: root.editing
    onResized: (width, height) => LayoutService.dashboardResize(width, height)
    cardWidth: sizing ? dragWidth : box.width
    cardHeight: sizing ? dragHeight : box.height
    readonly property bool editing: LayoutService.dashboardEditing
    // The dashboard's own cards that are not on it, and then every desktop
    // widget that is not either.
    readonly property var missing: LayoutService.tileChoices(
        Dash.missing(LayoutService.dashboardTypes), LayoutService.dashboardTypes)
    // Set on every open (`onWantedChanged`). Not bound to the clock: until
    // the first open that binding moved the day every minute, and the hidden
    // events card built its list again each time.
    property date selectedDay: new Date()
    readonly property bool selectedIsToday: selectedDay.toDateString() === today.toDateString()
    // The day, not the minute: the month grid reads it, and bound to the
    // minute clock its 42 cells were worked out again every minute, behind a
    // closed panel too (1-3 ms each time, 1440 times a day). Moved on when
    // the day changes and on every open.
    property date today: new Date()
    function takeToday(now) {
        const date = now || clock.date
        if (date.toDateString() !== today.toDateString()) today = date
    }
    // Dialogs opened from here (new event, event details) return to this day.
    readonly property var returnArgs: ({ day: SettingsService.locale.toString(selectedDay, "yyyy-MM-dd") })

    // Only while the dashboard is shown: built with the shell like every
    // panel, it woke once a minute all session behind a closed panel.
    // Enabled again it reads the time at once (probed offscreen), but it may
    // still be paused in the turn the panel opens in, so the open below asks
    // the time itself.
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: root.shown && WallClock.ticking; onDateChanged: root.takeToday() }

    // The month grid is one of the cards: it can be taken off the dashboard
    // altogether, so it is held by reference rather than by an id, and every
    // path that used to reach for it copes without.
    property Item monthGrid: null

    // The calendar service reads the six-week grid of one month.
    function syncMonth() {
        if (monthGrid) {
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

    onShownChanged: if (!shown) {
        LayoutService.dashboardEditing = false
        sizing = false
    }

    onWantedChanged: {
        if (wanted) {
            // The cards are built now, on the first open, and kept from then
            // on (see `cardsWanted`); a month built here is there to reset.
            cardsWanted = true
            const now = new Date()
            takeToday(now)
            if (monthGrid) monthGrid.reset()
            selectedDay = now
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
    ColumnLayout {
        width: parent.width
        spacing: Metrics.panelGap

        // The header every panel has, so the title sits where the control
        // center's does; the arrange button arranges the cards the way it
        // arranges the tiles there.
        PanelHeader {
            id: header
            Layout.fillWidth: true
            title: "Dashboard"
            shortcut: "SUPER + K"

            ShellButton {
                icon: Icons.arrange
                variant: root.editing ? "accent" : "ghost"
                iconSize: Metrics.iconMd
                toolTip: root.editing ? "Done arranging" : "Arrange cards"
                onClicked: LayoutService.dashboardEditing = !LayoutService.dashboardEditing
            }
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
                - header.height - Metrics.panelPadding * 2 - Metrics.panelGap - Metrics.spaceLg)

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
                    // The control center's gap between cards, not one of its
                    // own: the same kind of card sat 16 px apart here, 12
                    // there and 8 in the session menu.
                    gap: Metrics.cardGridGap
                    unit: Metrics.dashboardGridUnit
                    editing: root.editing
                    maxRows: LayoutService.gridMaxRows
                    animated: !root.sizing && !root.landing
                    dragLayer: root.overlay
                    model: root.cardCells
                    onCommitted: (id, index) => LayoutService.dashboardMoveTo(id, index)
                    onPlacementChanged: reportTimer.restart()
                    onWidthChanged: reportTimer.restart()

                    // Matched by id, not rebuilt: the card list is new on every
                    // write of the layout file - any surface, a mode or profile
                    // switch, an undo - and on a plain array every card (the
                    // month's 42 cells, the media card, the weather) was thrown
                    // away and built again, hidden or not.
                    //
                    // The model is the ids themselves, not the cards with
                    // `objectProp: "id"`: Quickshell 0.3.2's ScriptModel stops
                    // comparing keys once it has updated one entry in place and
                    // hands every later row the next entry by position, so after
                    // a card taken out of the middle each slot below it showed
                    // its neighbour, and the last one forgot the height of a card
                    // still on the panel. Strings are equal by value, so the ids
                    // diff as they should, and a slot reads its card by its id.
                    Repeater {
                        model: ScriptModel { values: root.cardsWanted ? LayoutService.dashboardItems.map(item => item.id) : [] }
                        DashboardSlot {
                            required property string modelData
                            required property int index
                            // Gone from the table in the same turn as the slot
                            // itself when its card is taken off; empty, it
                            // unloads rather than build a card on its way out.
                            readonly property var card: root.cardById[modelData] || null
                            area: cardArea
                            cardId: modelData
                            type: card ? card.type : ""
                            slotIndex: index
                            content: card ? root.cardFor(card.type) : null
                        }
                    }
                }

                // One compact row while arranging: the cards that are off, undo
                // and the way back. The arrange button in the header is the
                // Done button, so there is not a second one.
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
                            confirmText: "Reset?"
                            toolTip: "Back to the default cards"
                            onClicked: LayoutService.dashboardReset()
                        }
                    }
                }
            }
        }
    }

    // The cards wait for the first open: a session that never opens the
    // dashboard held its clock, the hourly and daily forecast, the month's 42
    // cells and the event list from the login on, some 6 MB. Built in the
    // turn the panel is asked for, they are on its first frame, and they stay
    // for the rest of the session, so every later open is as fast as before.
    property bool cardsWanted: false

    // The slots' cards by id (the Repeater runs on the ids alone).
    readonly property var cardById: {
        const table = {}
        for (const item of LayoutService.dashboardItems) table[item.id] = item
        return table
    }

    // The cells the area places, handed over by hand rather than bound. The
    // cards used to be built again on every write, already in their new
    // places; kept (the ScriptModel above), one whose cell moved would glide
    // there instead - a removed card's neighbours, an undo, a profile switch
    // with the panel open - and start springs that never ran on a write
    // (pitfall 40). So a write lands as it always did: the glide is off
    // before the new cells reach the area and back on once that turn is
    // over. A drag or a pulled corner moves the cells without a write and
    // glides as before. Bound, the order between the area's binding and a
    // handler switching the glide off would be the engine's to pick.
    property bool landing: false
    property var cardCells: []
    // Each at its stored size, but never below its card's minimum
    // (DashboardLogic.shownSize). Default ships the month at four rows, 292 px
    // for a grid that needs 346, and its sixth week was cut off; it is drawn
    // at five, and the file keeps what it says until a corner is pulled.
    function takeCells() {
        landing = true
        cardCells = LayoutService.dashboardItems.map(item => {
            const shown = Dash.shownSize(item.type, item.w, item.h)
            return { id: item.id, w: shown.w, h: shown.h,
                     minW: Dash.minSize(item.type).w, minH: Dash.minSize(item.type).h }
        })
        Qt.callLater(root.landed)
    }
    function landed() { landing = false }
    Connections {
        target: LayoutService
        function onDashboardItemsChanged() { root.takeCells() }
    }
    Component.onCompleted: takeCells()

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
        case "events": return eventsCard
        case "media": return mediaCard
        case "system": return systemCard
        }
        // Not one of the dashboard's own cards: a desktop widget it accepts.
        return WidgetRegistry.isAvailable(type) ? widgetCardItem : null
    }

    // Every card is an Item with its real content anchored to the top. The
    // card itself fills its cell - `Math.max` of the two heights, so a cell
    // taller than the content is card to its bottom edge instead of a gap of
    // panel under a short card, and the column of cards ends level instead
    // of ragged - and a shorter cell cuts it off at its own edge
    // (DashboardSlot clips). `shown` is the contract DashboardSlot reads: a
    // card the chosen view has no use for holds no place, the way a quick
    // tile with nothing to show holds none.
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
            readonly property bool compact: fitClass === "small" || fitClass === "wide"
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.max(implicitHeight, parent.height)
                spacing: 0
                // Raw Text, not ShellText: the clock needs tabular figures so
                // the digits do not shift every minute.
                Text {
                    text: TimeFormat.time(clock.date, SettingsService.twelveHourClock, " : ")
                    color: Colors.text
                    textFormat: Text.PlainText
                    font.family: Typography.family
                    font.pixelSize: clockBody.tiny ? Typography.headlineSize
                        : clockBody.compact ? Typography.displaySize : Typography.dashboardClockSize
                    font.weight: Typography.light
                    font.features: { "tnum": 1 }
                    renderType: Typography.renderType
                }
                ShellText {
                    Layout.fillWidth: true
                    visible: !clockBody.tiny
                    text: DateFormat.date(clock.date, SettingsService.locale,
                        clockBody.compact ? "short" : "long")
                    role: clockBody.compact ? "small" : "headline"
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
                height: Math.max(implicitHeight, parent.height)
                fillsCell: true
                rows: gridH
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
            readonly property bool shown: true
            CardSection {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.max(implicitHeight, parent.height)
                padding: Metrics.spaceMd

                CalendarMonth {
                    id: grid
                    Layout.fillWidth: true
                    today: root.today
                    selectable: true
                    eventDays: CalendarService.eventDays
                    onYearChanged: CalendarService.showMonth(year, month)
                    onMonthChanged: CalendarService.showMonth(year, month)
                    onDaySelected: day => root.selectedDay = day
                    // The panel reaches for the grid rather than the other way
                    // round, because this card can be hidden or removed.
                    Component.onCompleted: root.monthGrid = grid
                    Component.onDestruction: if (root.monthGrid === grid) root.monthGrid = null
                }
            }
        }
    }

    // The control center already wraps this exact card the same way; the two
    // surfaces differ in the size they start it at, not in the card.
    Component {
        id: mediaCard
        Item {
            id: mediaBody
            readonly property bool shown: true
            // The player's position is read again only while someone counts
            // as watching it (MprisService.trackers, a tick a second): the
            // control center and the media popup count themselves, and the
            // card's seek bar stood still here. While the dashboard is open,
            // as the system card samples, and only with this card on it.
            readonly property bool watching: root.shown
            property bool tracked: false
            onWatchingChanged: syncTracking()
            Component.onCompleted: syncTracking()
            Component.onDestruction: if (tracked) MprisService.trackers = Math.max(0, MprisService.trackers - 1)
            function syncTracking() {
                if (watching === tracked) return
                tracked = watching
                if (tracked) MprisService.trackers += 1
                else MprisService.trackers = Math.max(0, MprisService.trackers - 1)
            }
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
            // While the dashboard is open, not while the card exists: the
            // card is built with the panel at start, and a track on creation
            // kept /proc read every 2 s and `df` run every 30 s for the whole
            // session behind a closed panel. Opening samples at once, like
            // the system popup.
            readonly property bool sampling: root.shown
            property bool tracked: false
            onSamplingChanged: syncTracking()
            Component.onCompleted: syncTracking()
            Component.onDestruction: if (tracked) SystemStatsService.untrack()
            function syncTracking() {
                if (sampling === tracked) return
                tracked = sampling
                if (tracked) SystemStatsService.track()
                else SystemStatsService.untrack()
            }

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
                height: Math.max(implicitHeight, parent.height)
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
                height: Math.max(implicitHeight, parent.height)

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
                        text: DateFormat.date(root.selectedDay, SettingsService.locale, "short")
                        role: "small"
                        muted: true
                    }
                    ShellButton {
                        icon: Icons.add
                        variant: "ghost"
                        compact: true
                        // Merkuro takes it while the shell cannot write (CalendarService.openEditor).
                        toolTip: CalendarService.writesBlocked ? "New event in Merkuro" : "New event"
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

            // A plain card with the widget inset by the card padding, not a
            // CardSection: that one stacks its content from the top at its
            // implicit height, so a `fillHeight` item in it was 0 px tall and
            // the widget sat centred on the top padding line, clipped, with a
            // click area of nothing.
            ShellCard {
                anchors.fill: parent
                interactive: widgetBody.action.length > 0
                hovered: widgetMouse.containsMouse
                pressed: widgetMouse.pressed && widgetMouse.containsMouse
                Item {
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceLg

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
                            // A readout samples while the dashboard is open,
                            // not for as long as the card exists.
                            if (item.sampling !== undefined) item.sampling = Qt.binding(() => root.shown)
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
                        id: widgetMouse
                        anchors.fill: parent
                        anchors.margins: -Metrics.spaceLg
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
