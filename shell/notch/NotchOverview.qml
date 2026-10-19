import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notch/NotchLogic.js" as Logic
import "../../services/arrange/FitLogic.js" as Fit
import "../../services/LayoutLogic.js" as LayoutLogic
import "../../services/appearance/DateFormat.js" as DateFormat

// Content of the expanded notch. Two arrangements of the same blocks:
// "wide" puts the media beside the events so the notch grows sideways, and
// "stacked" keeps the older single column. Loaded only while the notch is
// expanded, so the weather is tracked only then - and only with a weather
// item in it.
Item {
    id: root
    required property var notch
    readonly property CalendarDemand calendarDemand: CalendarDemand { active: NotchService.shows("events") }
    readonly property date now: clock.date
    // "6:52 PM" or "18:52", as the bar's clock says it.
    readonly property bool twelve: SettingsService.twelveHourClock
    readonly property bool mediaPreview: NotchService.mediaPreview
    readonly property bool hasMedia: mediaPreview || (MprisService.hasPlayer && MprisService.title.length > 0)
    readonly property var current: WeatherService.current
    readonly property var events: Logic.upcomingEvents(CalendarService.eventsFor(now), now, NotchService.eventCount)
    readonly property bool wide: NotchService.wide
    // The overview's body, in the order the list has it. The weather is not
    // here: it sits beside the time in the header, which is where a notch puts
    // it. Anything that is not one of the notch's own blocks is a widget - the
    // same file the desktop and the bar use, handed the notch's colours.
    //
    // **Everything the user put in the list keeps its place**, whether or not
    // it has anything to say right now. The notch's own blocks used to be
    // dropped from the grid the moment they went quiet - the media block when
    // nothing was playing, the events block on an empty day - while a *widget*
    // with no data kept its cell and drew its name. Two rules for the same
    // situation, and the packer made the difference visible: dropping one cell
    // pulls every cell after it forward, so a song ending moved the status
    // block from the bottom right of the notch to the bottom left. The user
    // arranged that grid; a grid that rearranges itself is not an arrangement.
    //
    // `hasContent` then decides what each cell draws - the real block, or
    // quietly what it is missing ("No events") - which is what widgets do too.
    // Taking a block off the notch for good is what the editor's remove
    // button is for.
    //
    // The one exception is the item's own: `options.hideEmpty` on a block
    // (NotchLogic.hidesEmpty - the built-in presets' music) leaves its cell
    // out while it has nothing to draw, and the grid closes up around it.
    readonly property var listedItems: NotchService.expandedItems.filter(item =>
        item.type === "media" || item.type === "events" || item.type === "status"
            || WidgetRegistry.isAvailable(item.type))
    readonly property var bodyItems: listedItems.filter(item =>
        !Logic.hidesEmpty(item, root.hasContent(item.type), NotchService.arranging))
    readonly property var bodyTypes: bodyItems.map(item => item.type)
    // Whether a block has anything to draw right now. While the notch is
    // arranged one that has not is still in the body, as a named placeholder:
    // an empty block would be a cell of zero height and nothing to take hold
    // of.
    function hasContent(type) {
        if (type === "clock") return true
        if (type === "weather") return root.current !== null
        if (type === "media") return root.hasMedia
        if (type === "events") return root.events.length > 0
        if (type === "status") return true
        return WidgetRegistry.isAvailable(type)
    }
    // What a cell with nothing to show says instead (NotchLogic.emptyText):
    // "No location", "No events", "Empty workspace" rather than the block's
    // bare name.
    readonly property bool workspaceEmpty: {
        const workspace = HyprlandService.focusedWorkspace
        return workspace !== null && workspace.toplevels.values.length === 0
    }
    readonly property var emptyFacts: ({ weather: WeatherService.status, workspaceEmpty: root.workspaceEmpty })

    readonly property var status: Logic.statusItems({
        battery: { present: PowerService.hasBattery, percent: PowerService.percent, charging: PowerService.charging,
                   low: PowerService.low, icon: PowerService.icon },
        network: { icon: NetworkService.icon, connected: NetworkService.connected },
        bluetooth: { available: BluetoothService.available, icon: BluetoothService.icon, connected: BluetoothService.connected.length > 0 },
        dnd: NotificationService.dndActive,
        stayAwake: { on: IdleService.stayAwake, icon: IdleService.stayAwakeIcon },
        volume: { icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted), muted: AudioService.muted }
    })

    implicitWidth: Metrics.notchExpandedWidth
    // The same padding on all four sides. It used to be smaller at the top,
    // which nobody could see while the notch hung from the screen edge - and
    // which is the first thing you see on a pill, where both edges are there.
    implicitHeight: column.implicitHeight + Metrics.notchExpandedPadding * 2

    // The forecast is fetched only while this overview has a weather item to
    // draw it in. It used to be tracked on every opening, so a hover over a
    // notch without the weather could still send a request when the data was
    // more than ten minutes old. Followed rather than read once: the editor
    // can add or remove the item while the overview is open. From the list
    // and not from what is drawn: a weather cell that hides while it has no
    // forecast would otherwise never ask for one.
    readonly property bool showsWeather: root.listedItems.some(item => item.type === "weather")
    property bool weatherTracked: false
    onShowsWeatherChanged: syncWeather()
    function syncWeather() {
        if (showsWeather === weatherTracked) return
        weatherTracked = showsWeather
        if (weatherTracked) WeatherService.track()
        else WeatherService.untrack()
    }

    Component.onCompleted: syncWeather()
    Component.onDestruction: { if (weatherTracked) WeatherService.untrack(); root.clearRects() }

    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: WallClock.ticking }

    // Plain text, always: a track title, an artist or an event title is
    // somebody else's string, and Qt's default format renders one that looks
    // like markup - an <img src=...> in a YouTube title made the shell fetch
    // the address it named.
    component NotchText: Text {
        property bool muted: false
        color: muted ? Colors.notchMutedText : Colors.notchText
        font.family: Typography.family
        font.pixelSize: Typography.bodySize
        elide: Text.ElideRight
        textFormat: Text.PlainText
        renderType: Typography.renderType
    }

    component NotchGlyph: Text {
        property int size: Metrics.iconSm
        color: Colors.notchText
        font.family: Typography.iconFamily
        font.pixelSize: size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        renderType: Typography.renderType
    }

    // A block that fills its cell, highlights on hover and runs `clicked`.
    // Not RowButton: that one measures itself against its children, and a
    // block that also fills its parent makes that a binding loop.
    component FillButton: Item {
        id: fillButton
        default property alias content: fillBody.data
        property bool interactive: true
        readonly property bool hovered: fillMouse.containsMouse
        signal clicked()
        anchors.fill: parent

        // The highlight is the whole cell, not the row inside it. A block that
        // measured its own content left the hover mark shorter than the tile
        // it belonged to as soon as the tile could be made bigger.
        Rectangle {
            anchors.fill: parent
            radius: Metrics.notchFieldRadius
            color: fillButton.hovered && fillButton.interactive ? Colors.notchHover : "transparent"
            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        }
        // Under the content, not over it: a control inside the block - the
        // player's own buttons - must get the click it was aimed at, and this
        // one only takes what the content ignored.
        MouseArea {
            id: fillMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: fillButton.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: fillButton.clicked()
        }
        Item { id: fillBody; anchors.fill: parent }
    }

    // A row that highlights on hover and runs `clicked`.
    component RowButton: Item {
        id: rowButton
        default property alias content: holder.data
        readonly property bool hovered: rowMouse.containsMouse
        property bool interactive: true
        signal clicked()
        implicitHeight: holder.childrenRect.height
        // Exactly on the row. It used to reach a step beyond it, which read
        // as a stray band once every block sat in a field that clips.
        Rectangle {
            anchors.fill: parent
            radius: Metrics.notchFieldRadius
            color: rowButton.hovered && rowButton.interactive ? Colors.notchHover : "transparent"
            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            anchors.margins: -Metrics.spaceSm
            hoverEnabled: true
            enabled: rowButton.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: rowButton.clicked()
        }
        Item { id: holder; anchors.fill: parent }
    }

    component ControlButton: Rectangle {
        id: control
        property string glyph: ""
        property bool primary: false
        property bool available: true
        signal clicked()
        implicitWidth: primary ? Metrics.notchPlayControl : Metrics.notchControl
        implicitHeight: implicitWidth
        radius: width / 2
        color: primary ? (controlMouse.containsMouse && available ? Colors.notchHover : Colors.notchButton)
            : controlMouse.containsMouse && available ? Colors.notchHover : "transparent"
        opacity: available ? 1 : Effects.disabledOpacity
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        NotchGlyph { anchors.centerIn: parent; text: control.glyph; size: control.primary ? Metrics.iconMd : Metrics.iconSm + Metrics.spaceXxs }
        MouseArea {
            id: controlMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: control.available
            cursorShape: Qt.PointingHandCursor
            onClicked: control.clicked()
        }
    }

    // A boxed area inside the notch. The wide layout puts the media in one and
    // the events in the other, so they read as two fields rather than two
    // columns of the same block.
    component Field: Rectangle {
        default property alias content: fieldBody.data
        // The cell's granted size in grid steps, from the Loader that created
        // this field. The blocks inside read it rather than measuring pixels
        // they would have to know the notch's grid to interpret. Steps, not a
        // shape name: the notch's row is 36 px, so a row count says directly
        // what a block can hold.
        property int cellW: 1
        property int cellH: 1
        // No anchors: it is the root of a Loader that already has the cell's
        // size, and a second one would fight it.
        // An item can ask to stand free, without the field's own surface -
        // the island preset keeps a card only for what is a card (the media).
        property bool plain: false
        clip: true
        radius: Metrics.notchFieldRadius
        color: plain ? "transparent" : Colors.notchField
        border.width: plain ? 0 : Metrics.borderWidth
        border.color: Colors.notchFieldBorder
        Item {
            id: fieldBody
            x: Metrics.notchFieldPadding
            y: Metrics.notchFieldPadding
            width: parent.width - Metrics.notchFieldPadding * 2
            height: parent.height - Metrics.notchFieldPadding * 2
        }
    }

    // The big time and the long date. It used to be half of a fixed header;
    // it is an item like any other now, so it can be moved, sized and taken
    // off like any other.
    component ClockBlock: FillButton {
        id: clockBlock
        property int rows: 1
        property int columns: 1
        onClicked: root.notch.openPanel("dashboard")
        // 36 px of time over a date needs two of the notch's rows. In one it
        // is the time alone, at the size the collapsed strip uses - unless the
        // row spans three columns or more, which makes it a header (below).
        // The long date only fits across two columns; below that it is the
        // short one.
        readonly property bool oneRow: clockBlock.rows <= 1
        // One row across most of the notch is a header: the time and the
        // short date side by side, centred, the way an island reads.
        readonly property bool header: oneRow && clockBlock.columns >= 3
        GridLayout {
            anchors.left: clockBlock.header ? undefined : parent.left
            anchors.horizontalCenter: clockBlock.header ? parent.horizontalCenter : undefined
            anchors.verticalCenter: parent.verticalCenter
            width: clockBlock.header ? implicitWidth : parent.width
            columns: clockBlock.header ? 2 : 1
            columnSpacing: Metrics.spaceSm
            rowSpacing: 0
            NotchText {
                Layout.fillWidth: !clockBlock.header
                text: Logic.timeText(root.now, root.twelve)
                font.pixelSize: clockBlock.oneRow ? Typography.notchTimeSize : Typography.notchLargeTimeSize
                font.weight: Typography.light
                font.features: { "tnum": 1 }
            }
            NotchText {
                Layout.fillWidth: !clockBlock.header
                Layout.alignment: Qt.AlignVCenter
                visible: !clockBlock.oneRow || clockBlock.header
                text: DateFormat.date(root.now, SettingsService.locale,
                    clockBlock.columns >= 2 && !clockBlock.header ? "long" : "short", SettingsService.dateOrder, SettingsService.shortDateNumbers)
                muted: true
                font.pixelSize: Typography.smallSize
            }
        }
    }

    // The weather, the way a notch draws it: the glyph, the temperature and
    // the condition under them. Also an item now, not the other half of a
    // header.
    component WeatherBlock: FillButton {
        id: weatherBlock
        property int rows: 1
        onClicked: root.notch.openPanel("weatherPopup")
        // The condition is the line that goes: a glyph and a temperature is
        // still the weather, and a condition cut off at its waist is not.
        readonly property bool showLabel: weatherBlock.rows >= 2
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Metrics.spaceXs
                NotchGlyph {
                    text: root.current ? root.current.icon : ""
                    size: Metrics.iconLg
                }
                NotchText {
                    text: root.current ? WeatherService.formatTemperature(root.current.temperature) : ""
                    font.pixelSize: Typography.notchTemperatureSize
                    font.weight: Typography.light
                }
            }
            NotchText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                visible: weatherBlock.showLabel
                text: root.current ? root.current.label : ""
                muted: true
                font.pixelSize: Typography.captionSize
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // One event: a coloured bar, when it is and what it is.
    component EventRow: RowButton {
        id: eventRow
        property var event: null
        Layout.fillWidth: true
        implicitHeight: eventContent.implicitHeight
        onClicked: root.notch.openPanel("dashboard")
        RowLayout {
            id: eventContent
            width: parent.width
            spacing: Metrics.spaceMd
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Metrics.notchEventBar
                radius: width / 2
                color: CalendarService.colorFor(eventRow.event)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                NotchText {
                    text: eventRow.event ? Logic.eventWhen(eventRow.event, root.now, root.twelve) : ""
                    muted: true
                    font.pixelSize: Typography.captionSize
                    font.features: { "tnum": 1 }
                }
                NotchText {
                    Layout.fillWidth: true
                    text: eventRow.event ? eventRow.event.title : ""
                    font.weight: Typography.medium
                }
            }
        }
    }

    // The events column of the wide layout, or the single next event of the
    // stacked one.
    component EventsBlock: FillButton {
        id: eventsBlock
        // Each row is its own button, so the block itself is not one.
        interactive: false
        // As many as fit, never more than the setting asks for: a tile made
        // taller shows more of the day rather than more empty field.
        readonly property int fits: Fit.rowsFor(height, Metrics.notchEventRow, Metrics.spaceSm)
        readonly property int count: Math.min(NotchService.eventCount, fits)

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.spaceSm
            Repeater {
                model: root.events.slice(0, eventsBlock.count)
                EventRow {
                    required property var modelData
                    width: parent.width
                    event: modelData
                }
            }
        }
    }

    // Cover and titles open the media popup, the buttons control the player.
    component MediaBlock: FillButton {
        id: mediaBlock
        property int columns: 2
        interactive: !root.mediaPreview
        onClicked: root.notch.openPanel("mediaPopup")
        // A cover, two lines of text and three buttons need three columns of
        // the notch's grid. In two, the block keeps play and pause - the one
        // control worth reaching for - and drops the two beside it.
        readonly property bool fullTransport: mediaBlock.columns >= 3
        RowLayout {
            id: mediaInfo
            anchors.left: parent.left
            anchors.right: parent.right
            // The transport is the last thing in this row, so without an inset
            // the play button sits hard against the edge of the block - which
            // is where the block's own rounding is, and it reads as falling
            // off. The title column fills what is left, so pulling the edge in
            // moves the buttons left and shortens the title together; the
            // title elides rather than running under them.
            anchors.rightMargin: Metrics.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.spaceMd
                Rectangle {
                    Layout.preferredWidth: Metrics.notchCover
                    Layout.preferredHeight: Metrics.notchCover
                    radius: width / 2
                    color: Colors.notchCoverFallback
                    NotchGlyph {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: "󰎆"
                        size: Metrics.iconMd
                        color: Colors.notchMutedText
                    }
                    RoundedImage {
                        id: cover
                        anchors.fill: parent
                        radius: width / 2
                        visible: status === Image.Ready
                        source: root.mediaPreview ? "" : MprisService.artUrl
                        sourceWidth: Metrics.notchCover * 2
                        opacity: MprisService.playing ? 1 : Effects.mutedOpacity
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    NotchText {
                        Layout.fillWidth: true
                        text: root.mediaPreview ? NotchService.previewTrack.title : MprisService.title
                        font.weight: Typography.medium
                    }
                    NotchText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.mediaPreview ? NotchService.previewTrack.artist : MprisService.artist
                        muted: true
                        font.pixelSize: Typography.smallSize
                    }
                }
                RowLayout {
                    spacing: Metrics.spaceXxs
                    readonly property var player: MprisService.active
                    ControlButton {
                        glyph: Icons.previous
                        visible: mediaBlock.fullTransport
                        available: !root.mediaPreview && parent.player !== null && parent.player.canGoPrevious
                        onClicked: MprisService.previous()
                    }
                    ControlButton {
                        primary: true
                        glyph: (root.mediaPreview ? NotchService.previewTrack.playing : MprisService.playing) ? Icons.pause : Icons.play
                        available: !root.mediaPreview && parent.player !== null && parent.player.canTogglePlaying
                        onClicked: MprisService.togglePlaying()
                    }
                    ControlButton {
                        glyph: Icons.next
                        visible: mediaBlock.fullTransport
                        available: !root.mediaPreview && parent.player !== null && parent.player.canGoNext
                        onClicked: MprisService.next()
                    }
            }
        }
    }

    // Status (control center), centred; while recording a stop chip sits
    // on the left and the icons move to the right.
    component StatusBlock: FillButton {
        id: statusBlock
        property int columns: 1
        onClicked: root.notch.openPanel("controlCenter")
        // Five readouts with their figures need the width of the grid. In one
        // column the figures go and the glyphs close up: which of them is on
        // is still readable, which is what the row is for.
        readonly property bool showText: statusBlock.columns >= 2
        Item {
            anchors.fill: parent

            Rectangle {
                id: recordingChip
                visible: RecordingService.active
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: recordingRow.implicitWidth + Metrics.spaceSm * 2
                implicitHeight: recordingRow.implicitHeight + Metrics.spaceXxs * 2
                radius: height / 2
                color: Colors.recording
                RowLayout {
                    id: recordingRow
                    anchors.centerIn: parent
                    spacing: Metrics.spaceXs
                    NotchGlyph { text: stopMouse.containsMouse ? Icons.stop : "󰑊"; size: Metrics.iconXs; color: Colors.recordingText }
                    NotchText {
                        text: RecordingService.busy === "stopping" ? "Saving …" : RecordingService.elapsedText
                        color: Colors.recordingText
                        font.pixelSize: Typography.captionSize
                        font.weight: Typography.semibold
                        font.features: { "tnum": 1 }
                    }
                }
                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: RecordingService.stop()
                }
            }

            RowLayout {
                id: statusIcons
                anchors.verticalCenter: parent.verticalCenter
                x: recordingChip.visible ? parent.width - implicitWidth : (parent.width - implicitWidth) / 2
                spacing: statusBlock.showText ? Metrics.spaceLg : Metrics.spaceMd
                Repeater {
                    model: root.status
                    // Something off (no connection, a muted speaker) is drawn
                    // in the subtle ink rather than the muted one at the
                    // disabled opacity: the two together came to 1.9:1 on
                    // black, which is not dimmed but gone. And it stays
                    // subtle with the accent on, because the accent says "on".
                    // A low battery is red here as it is on every other
                    // surface - the notch's own red, since it is black in
                    // both themes. Charging is the green or, with Settings >
                    // Power > Status colors on the accent, the accent made
                    // for black - the colour the accent glyphs wear too.
                    // The glyph 4 px off its figure, as the bar's battery
                    // (WidgetBase's columnSpacing): at 2 "63%" read glued on.
                    RowLayout {
                        required property var modelData
                        spacing: Metrics.spaceXs
                        NotchGlyph {
                            text: modelData.icon
                            size: Metrics.iconSm
                            color: modelData.charging ? Colors.positiveOnDark
                                : modelData.low ? Colors.dangerOnDark
                                : modelData.dim ? Colors.notchSubtleText
                                : NotchService.overviewGlyphsInAccent ? Colors.notchAccent : Colors.notchMutedText
                        }
                        NotchText {
                            visible: statusBlock.showText && modelData.text.length > 0
                            text: modelData.text
                            color: modelData.dim ? Colors.notchSubtleText : Colors.notchMutedText
                            font.pixelSize: Typography.captionSize
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: column
        x: Metrics.notchExpandedPadding
        y: Metrics.notchExpandedPadding
        width: parent.width - Metrics.notchExpandedPadding * 2
        spacing: Metrics.notchRowGap

        // The body is a grid, and each item says how much of it it takes: half
        // a row or the whole one, plus how big it draws. The places come from
        // ArrangeLogic rather than from a layout, so a neighbour can glide
        // aside when the order changes and the rectangles the editor works on
        // are the *resting* ones - an animated position that fed a report back
        // would never settle.
        ArrangeArea {
            id: body
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: root.bodyItems.length > 0
            columns: NotchService.columns
            gap: Metrics.notchColumnGap
            unit: Metrics.notchGridUnit
            // The dragging is the layout editor's, on its own surface above
            // the notch; this only places what it is given.
            editing: false
            model: root.bodyItems.map(item => ({ id: item.id, w: item.w, h: item.h,
                minW: LayoutLogic.notchMinSize(item.type).w, minH: LayoutLogic.notchMinSize(item.type).h }))
            onXChanged: reportTimer.restart()
            onYChanged: reportTimer.restart()
            onWidthChanged: reportTimer.restart()
            onPlacementChanged: reportTimer.restart()

            Repeater {
                id: bodyParts
                model: root.bodyItems
                ArrangeItem {
                    id: cell
                    required property var modelData
                    area: body
                    itemId: modelData.id
                    draggable: false
                    // The area leaves out anything that reports no height at
                    // all, the way a layout skips an invisible child. Which is
                    // every item here unless it says otherwise: what the notch
                    // shows is decided in `bodyItems`, not by a measurement.
                    contentHeight: 1

                    // The cell decides the size now, so the block fills it and
                    // what does not fit is cut off rather than pushing its
                    // neighbours around. Drag its corner if it needs more.
                    Loader {
                        id: part
                        anchors.fill: parent
                        // The blocks read this, not the delegate's `modelData`:
                        // a component's scope reaches the Loader that created
                        // it, not the item the Loader happens to sit in. The
                        // cell's granted shape rides along for the same reason.
                        readonly property var notchItem: cell.modelData
                        readonly property int gridW: cell.gridW
                        readonly property int gridH: cell.gridH
                        readonly property string fitClass: cell.fitClass
                        sourceComponent: !root.hasContent(notchItem.type) ? placeholderPart
                            : notchItem.type === "clock" ? clockPart
                            : notchItem.type === "weather" ? weatherPart
                            : notchItem.type === "status" ? statusPart
                            : notchItem.type === "media" ? mediaPart
                            : notchItem.type === "events" ? eventsPart
                            : widgetPart
                    }
                }
            }
        }
    }

    // ---- where the body's parts are --------------------------------------
    // The editor covers the notch, so it works on the real one and the notch
    // says where its parts sit. Reported after the morph has settled: a
    // rectangle that is still moving makes the drop index chase itself.
    readonly property bool reporting: NotchService.arrangingExpanded && root.notch !== null

    function screenRect(item) {
        const origin = root.notch ? root.notch.reportOrigin : Qt.point(0, 0)
        const topLeft = item.mapToItem(null, 0, 0)
        return { x: Math.round(topLeft.x + origin.x), y: Math.round(topLeft.y + origin.y),
                 width: Math.round(item.width), height: Math.round(item.height) }
    }

    // From the resting places, never from the items themselves: a cell springs
    // to its new place (ArrangeItem, SpringMotion) and the report fires long
    // before that, so reporting an item's own x and y described where it was
    // halfway there. The frames then sat beside the things they belong to.
    function reportRects() {
        const screenName = root.notch ? root.notch.screenName : ""
        if (!screenName.length) return
        LayoutService.reportSurfaceRect(screenName, "notchzone:expanded",
                                        reporting ? screenRect(body) : null)
        const origin = reporting ? screenRect(body) : null
        for (const item of root.bodyItems) {
            const cell = body.cellOf(item.id)
            LayoutService.reportSurfaceRect(screenName, "notch:" + item.id,
                origin && cell ? { x: Math.round(origin.x + cell.x), y: Math.round(origin.y + cell.y),
                                   width: Math.round(cell.width), height: Math.round(cell.height) }
                               : null)
        }
    }

    function clearRects() {
        const screenName = root.notch ? root.notch.screenName : ""
        if (!screenName.length) return
        LayoutService.reportSurfaceRect(screenName, "notchzone:expanded", null)
        for (const item of NotchService.expandedItems)
            LayoutService.reportSurfaceRect(screenName, "notch:" + item.id, null)
    }

    onReportingChanged: reportTimer.restart()

    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: root.reportRects()
    }

    // A block with nothing to say: its icon and what is missing, quietly, so
    // it can be seen (and, while the notch is arranged, taken hold of and put
    // somewhere else) without reading like a name left unfilled.
    Component {
        id: placeholderPart
        Field {
            id: box
            readonly property var entry: NotchService.entry(notchItem.type)
            Row {
                id: placeholderRow
                anchors.centerIn: parent
                spacing: Metrics.spaceSm
                NotchGlyph {
                    id: placeholderGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.entry.icon
                }
                NotchText {
                    anchors.verticalCenter: parent.verticalCenter
                    // Ends in "…" inside the cell rather than at its clip.
                    width: Math.min(implicitWidth, Math.max(0, placeholderRow.parent.width
                        - placeholderGlyph.implicitWidth - placeholderRow.spacing))
                    text: Logic.emptyText(notchItem.type, root.emptyFacts, box.entry.label)
                    muted: true
                }
            }
        }
    }

    // Every block in the overview sits in a field of its own now, so the
    // grid reads as a grid; before, only the media and the events were boxed
    // and the rest floated between them.
    // Every block fills its cell, so its hover mark is the cell.
    // Each field takes the cell's granted shape from the Loader that made it
    // and hands the blocks inside whichever half of it they care about. Named
    // fields rather than a walk up `parent`: the block sits in the field's
    // body, not in the field, so a parent chain would be one step longer than
    // it looks and would break the first time the field grows a wrapper.
    Component { id: clockPart
        Field { id: clockField; cellW: gridW; cellH: gridH; plain: notchItem.options.plain === true
            ClockBlock { rows: clockField.cellH; columns: clockField.cellW } } }
    Component { id: weatherPart
        Field { id: weatherField; cellW: gridW; cellH: gridH; plain: notchItem.options.plain === true
            WeatherBlock { rows: weatherField.cellH } } }
    Component { id: statusPart
        Field { id: statusField; cellW: gridW; cellH: gridH; plain: notchItem.options.plain === true
            StatusBlock { columns: statusField.cellW } } }
    Component { id: mediaPart
        Field { id: mediaField; cellW: gridW; cellH: gridH; plain: notchItem.options.plain === true
            MediaBlock { columns: mediaField.cellW } } }
    Component { id: eventsPart
        Field { id: eventsField; cellW: gridW; cellH: gridH; plain: notchItem.options.plain === true
            EventsBlock {} } }

    // Any other type is a widget: the same file the desktop and the bar load,
    // told to draw on a black surface rather than on the theme's.
    Component {
        id: widgetPart
        Field {
            plain: notchItem.options.plain === true
            id: widgetBox
            readonly property var entry: WidgetRegistry.type(notchItem.type)
            // The same click a pill and a desktop widget give it: the panel
            // the registry names. Without it a widget on the notch was a
            // picture of a control - the volume readout did nothing at all.
            readonly property string action: entry ? entry.action : ""
            // A widget with nothing to say says what is missing instead, the
            // way an empty block does, rather than leaving an empty box.
            readonly property bool hasData: widget.item ? widget.item.hasData !== false : false

            Rectangle {
                anchors.fill: parent
                anchors.margins: Metrics.borderWidth
                radius: widgetBox.radius
                color: widgetMouse.containsMouse && widgetBox.action.length ? Colors.notchHover : "transparent"
                Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
            }
            // The cell's click, under the widget rather than over it, as on
            // the pill bar and the desktop: a widget's own controls - the
            // Playback widget's play/pause - take the press they were aimed
            // at, and this one only gets what they leave. Declared last, it
            // covered them, and play/pause opened the media popup.
            MouseArea {
                id: widgetMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: widgetBox.action.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notch.openPanel(widgetBox.action,
                                                widgetBox.entry && widgetBox.entry.actionArgs
                                                    ? widgetBox.entry.actionArgs : {})
            }
            Loader {
                id: widget
                anchors.centerIn: parent
                visible: widgetBox.hasData
                source: WidgetRegistry.source(notchItem.type)
                onLoaded: {
                    // Which readout this is. Three registry types share one
                    // file and tell it apart by `options.metric`, and the
                    // notch never handed that over - so a RAM or a disk
                    // widget put on the notch drew the CPU, under its own
                    // glyph. The bar and the desktop both pass an instance;
                    // this was the one place that did not.
                    // `screen` as well as `type`: a workspace widget filters
                    // the compositor's workspaces by it. The notch has one
                    // surface per screen, so it never changes.
                    item.instance = { id: notchItem.id, type: notchItem.type,
                                      screen: root.notch ? root.notch.screenName : "",
                                      options: Object.assign({}, widgetBox.entry && widgetBox.entry.options
                                          ? widgetBox.entry.options : {}, notchItem.options || {}) }
                    // **Not** `inGroup`. That flag means "you are one of
                    // several things crammed into one pill", and it makes a
                    // widget drop its label and everything above it. The
                    // overview's cells are a grid the user sizes, so a widget
                    // in one has exactly the room it was given - which the
                    // strip below the notch does not, and still says so.
                    item.textColor = Colors.notchText
                    item.mutedTextColor = Colors.notchMutedText
                    // The neutral glyph ink, the accent when the overview is
                    // asked for it (notch.accentGlyphs); a binding, so a new
                    // accent or setting reaches it without a reload. And the
                    // groove behind a meter: the theme's vanishes on black.
                    // Only widgets built on WidgetBase have either.
                    if (item.glyphInk !== undefined)
                        item.glyphInk = Qt.binding(() => NotchService.overviewGlyphsInAccent ? Colors.notchAccent : Colors.notchText)
                    if (item.trackColor !== undefined) item.trackColor = Colors.notchTrack
                    // Black in both themes: the state colours (charging, low,
                    // a tunnel up, unread) take their on-dark variants.
                    if (item.onDark !== undefined) item.onDark = true
                    // The cell's room, inside the field's padding: the cell is
                    // the size the user dragged, and a label that did not know
                    // it ran past the edge and was cut mid-letter instead of
                    // ending in "…". A widget that does not take it is centred
                    // and clipped by the field as before.
                    if (item.availableWidth !== undefined)
                        item.availableWidth = Qt.binding(() => Math.max(0, widgetBox.width - Metrics.notchFieldPadding * 2))
                }
            }
            // The size the cell was pulled to, not a fixed "small". Eleven
            // widgets already draw a different thing per size name - a short
            // date against a long one, one event against three - and the notch
            // used to ask every one of them for the smallest whatever room it
            // had been given. A binding rather than a line in `onLoaded`,
            // because the cell keeps changing after the widget is loaded.
            Binding {
                target: widget.item
                property: "sizeClass"
                value: Fit.widgetSize(widgetBox.width, widgetBox.height)
                when: widget.item !== null
            }
            Row {
                id: emptyRow
                anchors.centerIn: parent
                visible: !widgetBox.hasData
                spacing: Metrics.spaceSm
                NotchGlyph {
                    id: emptyGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: widgetBox.entry ? widgetBox.entry.icon : ""
                }
                NotchText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, emptyRow.parent.width
                        - emptyGlyph.implicitWidth - emptyRow.spacing))
                    text: Logic.emptyText(notchItem.type, root.emptyFacts,
                                          widgetBox.entry ? widgetBox.entry.label : notchItem.type)
                    muted: true
                }
            }
        }
    }
}
