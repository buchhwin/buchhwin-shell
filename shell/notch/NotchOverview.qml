import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notch/NotchLogic.js" as Logic
import "../../services/arrange/FitLogic.js" as Fit
import "../../services/LayoutLogic.js" as LayoutLogic

// Content of the expanded notch. Two arrangements of the same blocks:
// "wide" puts the media beside the events so the notch grows sideways, and
// "stacked" keeps the older single column. Loaded only while the notch is
// expanded, so the weather is tracked only then.
Item {
    id: root
    required property var notch
    readonly property date now: clock.date
    readonly property var event: Logic.nextEvent(CalendarService.eventsFor(now), now)
    readonly property bool mediaPreview: NotchService.mediaPreview
    readonly property bool hasMedia: mediaPreview || (MprisService.hasPlayer && MprisService.title.length > 0)
    readonly property var current: WeatherService.current
    readonly property var events: Logic.upcomingEvents(CalendarService.eventsFor(now), now, NotchService.eventCount)
    readonly property bool wide: NotchService.wide
    readonly property var rows: Logic.rows({ event: event !== null, media: hasMedia })
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
    // `hasContent` then decides what each cell draws - the real block, or its
    // name quietly - which is what widgets have always done. Taking a block
    // off the notch for good is what the editor's remove button is for.
    readonly property var bodyItems: NotchService.expandedItems.filter(item =>
        item.type === "media" || item.type === "events" || item.type === "status"
            || WidgetRegistry.isAvailable(item.type))
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

    readonly property var status: Logic.statusItems({
        battery: { present: PowerService.hasBattery, percent: PowerService.percent, charging: PowerService.charging, icon: PowerService.icon },
        network: { icon: NetworkService.icon, connected: NetworkService.connected },
        bluetooth: { available: BluetoothService.available, icon: BluetoothService.icon, connected: BluetoothService.connected.length > 0 },
        dnd: NotificationService.dndActive,
        volume: { icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted), muted: AudioService.muted }
    })

    implicitWidth: Metrics.notchExpandedWidth
    // The same padding on all four sides. It used to be smaller at the top,
    // which nobody could see while the notch hung from the screen edge - and
    // which is the first thing you see on a pill, where both edges are there.
    implicitHeight: column.implicitHeight + Metrics.notchExpandedPadding * 2

    Component.onCompleted: WeatherService.track()
    Component.onDestruction: { WeatherService.untrack(); root.clearRects() }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    component NotchText: Text {
        property bool muted: false
        color: muted ? Colors.notchMutedText : Colors.notchText
        font.family: Typography.family
        font.pixelSize: Typography.bodySize
        elide: Text.ElideRight
        renderType: Typography.renderType
    }

    component NotchGlyph: Text {
        property int size: Metrics.iconSm
        color: Colors.notchText
        font.family: Typography.iconFamily
        font.pixelSize: size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
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
            Behavior on color { ColorAnimation { duration: Animations.hover } }
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
            Behavior on color { ColorAnimation { duration: Animations.hover } }
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
        Behavior on color { ColorAnimation { duration: Animations.hover } }
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
        clip: true
        radius: Metrics.notchFieldRadius
        color: Colors.notchField
        border.width: Metrics.borderWidth
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
        // is the time alone, at the size the collapsed strip uses - the same
        // clock, read the same way, in the room there is. And the long date
        // only fits across two columns; below that it is the short one.
        readonly property bool oneRow: clockBlock.rows <= 1
        ColumnLayout {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 0
            NotchText {
                Layout.fillWidth: true
                text: Logic.timeText(root.now)
                font.pixelSize: clockBlock.oneRow ? Typography.notchTimeSize : Typography.notchLargeTimeSize
                font.weight: Typography.light
                font.features: { "tnum": 1 }
            }
            NotchText {
                Layout.fillWidth: true
                visible: !clockBlock.oneRow
                text: SettingsService.locale.toString(root.now,
                    clockBlock.columns >= 2 ? "dddd, MMMM d" : "ddd, MMM d")
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
                    text: eventRow.event ? Logic.eventWhen(eventRow.event, root.now) : ""
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
                    NotchGlyph { text: stopMouse.containsMouse ? "󰓛" : "󰑊"; size: Metrics.iconXs; color: Colors.recordingText }
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
                    RowLayout {
                        required property var modelData
                        spacing: Metrics.spaceXxs
                        opacity: modelData.dim ? Effects.disabledOpacity : 1
                        NotchGlyph {
                            text: modelData.icon
                            size: Metrics.iconSm
                            color: modelData.charging ? Colors.successOnDark : Colors.notchMutedText
                        }
                        NotchText {
                            visible: statusBlock.showText && modelData.text.length > 0
                            text: modelData.text
                            muted: true
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

    // From the resting places, never from the items themselves: a cell glides
    // to its new place over `Animations.reorder` and the report fires long
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

    // A block with nothing to say, while the notch is arranged: its name and
    // its icon, so it can be seen, taken hold of and put somewhere else.
    Component {
        id: placeholderPart
        Field {
            id: box
            readonly property var entry: NotchService.entry(notchItem.type)
            Row {
                anchors.centerIn: parent
                spacing: Metrics.spaceSm
                NotchGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.entry.icon
                }
                NotchText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.entry.label
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
        Field { id: clockField; cellW: gridW; cellH: gridH
            ClockBlock { rows: clockField.cellH; columns: clockField.cellW } } }
    Component { id: weatherPart
        Field { id: weatherField; cellW: gridW; cellH: gridH
            WeatherBlock { rows: weatherField.cellH } } }
    Component { id: statusPart
        Field { id: statusField; cellW: gridW; cellH: gridH
            StatusBlock { columns: statusField.cellW } } }
    Component { id: mediaPart
        Field { id: mediaField; cellW: gridW; cellH: gridH
            MediaBlock { columns: mediaField.cellW } } }
    Component { id: eventsPart
        Field { id: eventsField; cellW: gridW; cellH: gridH
            EventsBlock {} } }

    // Any other type is a widget: the same file the desktop and the bar load,
    // told to draw on a black surface rather than on the theme's.
    Component {
        id: widgetPart
        Field {
            id: widgetBox
            readonly property var entry: WidgetRegistry.type(notchItem.type)
            // The same click a pill and a desktop widget give it: the panel
            // the registry names. Without it a widget on the notch was a
            // picture of a control - the volume readout did nothing at all.
            readonly property string action: entry ? entry.action : ""
            // A widget with nothing to say says its name instead, the way an
            // empty block does, rather than leaving an empty box.
            readonly property bool hasData: widget.item ? widget.item.hasData !== false : false

            Rectangle {
                anchors.fill: parent
                anchors.margins: Metrics.borderWidth
                radius: widgetBox.radius
                color: widgetMouse.containsMouse && widgetBox.action.length ? Colors.notchHover : "transparent"
                Behavior on color { ColorAnimation { duration: Animations.hover } }
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
                                      options: widgetBox.entry && widgetBox.entry.options
                                          ? widgetBox.entry.options : {} }
                    // **Not** `inGroup`. That flag means "you are one of
                    // several things crammed into one pill", and it makes a
                    // widget drop its label and everything above it. The
                    // overview's cells are a grid the user sizes, so a widget
                    // in one has exactly the room it was given - which the
                    // strip below the notch does not, and still says so.
                    item.textColor = Colors.notchText
                    item.mutedTextColor = Colors.notchMutedText
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
                anchors.centerIn: parent
                visible: !widgetBox.hasData
                spacing: Metrics.spaceSm
                NotchGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: widgetBox.entry ? widgetBox.entry.icon : ""
                }
                NotchText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: widgetBox.entry ? widgetBox.entry.label : notchItem.type
                    muted: true
                }
            }
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
        }
    }
}
