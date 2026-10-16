import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
// Registers the widget module so pill items can share WidgetBase.
import qs.shell.widgets
import qs.shell.editor
import "../../services/bar/BarLogic.js" as BarLogic
import "../../services/dock/DockLogic.js" as DockLogic
import "../../services/LayoutLogic.js" as LayoutLogic
import "../../services/model/KeyedLogic.js" as Keyed

// One pill of the top bar with one or more widget items. Items reuse the
// desktop widget files in their compact form (inGroup, sizeClass "small" or
// "icon"). A click runs the item's registry action and opens the panel below.
// The pill hides while none of its items has data.
// Style "pills": a capsule; a click opens the panel below the pill's centre.
// Style "bar" (`flat`): no own background; every item is a segment with its
// own hover highlight, a click opens the panel centred below that item, and a
// separator line precedes the group when `separator` is set.
Rectangle {
    id: root
    required property var pill
    required property string screenName
    property real scaleFactor: 1
    property bool flat: false
    property bool separator: false
    // Whether the bar this pill sits in runs down the screen. Everything that
    // has a direction below turns on it.
    property bool vertical: false
    // Radius of the surrounding bar, so the hover highlight stays concentric.
    property real barRadius: 0
    // How thick the bar is, for a highlight that has to span it.
    property real barThickness: 0
    readonly property bool hovered: hover.hovered
    // A pill made only of items that do nothing when clicked (workspaces, the
    // active window, the recording chip) used to light up like a button. The
    // flat bar style already gated its highlight on this.
    readonly property bool clickable: pill.items.some(item => {
        const entry = WidgetRegistry.type(item.type)
        return entry !== null && entry.action.length > 0
    })
    readonly property bool iconsOnly: pill.items.every(item => item.display === "icon")
    property int showingCount: 0
    readonly property bool hasContent: showingCount > 0
    // While the layout editor is open the pill is the thing being edited: it
    // leans like a desktop tile, it reports where it is so the editor can draw
    // its frame and its drop marker on the real bar, and its items stop
    // opening panels.
    readonly property bool editing: surface === "dock"
        ? LayoutService.editMode && LayoutService.editTarget === "dock"
        : LayoutService.editMode && LayoutService.barShown && LayoutService.editTarget !== "dock"
    readonly property bool selected: editing && LayoutService.editorSelection === pill.id
    // Which surface holds this pill: the bar, or the dock (shell/dock/Dock.qml,
    // the same pills on another layer). A dock's pill edits with the dock,
    // tells nothing to the table of where the bar's widgets are (a popup of
    // the bar's clock must not come out of the dock's), and opens its panels
    // beside the dock on `dockEdge`.
    property string surface: "bar"
    property string dockEdge: "bottom"
    property int wiggleIndex: 0

    // The pill reports for itself and for its items: one place, so a delayed
    // call can never run against a delegate that is already gone.
    function reportRects() {
        const on = editing && visible
        LayoutService.reportSurfaceRect(screenName, pill.id, on ? screenRect(root) : null)
        for (let index = 0; index < itemRepeater.count; ++index) {
            const segment = itemRepeater.itemAt(index)
            LayoutService.reportSurfaceRect(screenName, pill.id + "#" + index,
                on && segment && segment.visible ? screenRect(segment) : null)
            // And, whether or not the editor is open, where this type of
            // widget is: a notification and an OSD come out of the thing they
            // belong to, and they cannot wait for an editor to be opened.
            if (index < pill.items.length && surface === "bar")
                LayoutService.reportBarItemRect(screenName, pill.items[index].type,
                    visible && segment && segment.visible ? screenRect(segment) : null)
            // Every item on the dock the same way (the start menu opened by a
            // key or IPC comes out of the start button, a panel opened by its
            // hotkey can come out of its item) - by the pill's own condition,
            // not `visible`: a hidden dock hides its content (pitfall 89), and
            // the place where an item shows is what is asked for then.
            if (index < pill.items.length && surface === "dock")
                reportDockItem(pill.items[index].type, hasContent && segment && segment.showing ? screenRect(segment) : null)
        }
    }
    // A type is reported under the screen and the type alone: a pill takes
    // back only what it reported itself, and leaves a second item of the
    // type (another pill's) where it is. Kept out of every binding.
    property var dockReports: ({ types: {} })
    function reportDockItem(type, rect) {
        const mine = dockReports.types[type]
        if (rect) {
            dockReports.types[type] = JSON.stringify(rect)
            LayoutService.reportDockItemRect(screenName, type, rect)
        } else if (mine !== undefined) {
            delete dockReports.types[type]
            if (JSON.stringify(LayoutService.dockItemRect(screenName, type)) === mine)
                LayoutService.reportDockItemRect(screenName, type, null)
        }
    }
    function reportSoon() { reportTimer.restart() }

    // Where the bar's surface sits on the screen. Mapping to `null` maps to
    // the *window*, and the bar's window is only as thick as the bar and hangs
    // from its own edge - so on a bottom or a right bar every rectangle this
    // pill reports would be a screen's width out. See PillBar.reportOrigin.
    property var reportOrigin: ({ x: 0, y: 0 })
    // What the places are measured in: the window (null), or on the dock its
    // drawn content, which slides out over the edge as the dock hides - the
    // place an item has while shown is the one that is wanted.
    property Item reportFrame: null

    function screenRect(item) {
        const topLeft = item.mapToItem(reportFrame, 0, 0)
        return { x: topLeft.x + reportOrigin.x, y: topLeft.y + reportOrigin.y,
                 width: item.width, height: item.height }
    }

    function clearRects() {
        LayoutService.reportSurfaceRect(screenName, pill.id, null)
        for (let index = 0; index < pill.items.length; ++index) {
            LayoutService.reportSurfaceRect(screenName, pill.id + "#" + index, null)
            if (surface === "bar") LayoutService.reportBarItemRect(screenName, pill.items[index].type, null)
        }
        for (const type of Object.keys(dockReports.types)) reportDockItem(type, null)
    }

    // Every way a pill can end up somewhere else. On a horizontal bar it moves
    // in x and changes width; on a vertical one it moves in y and changes
    // height, and with only the first pair a pill that shifted because the one
    // above it grew went on reporting where it used to be - which puts the
    // editor's frame and its drop marker on the wrong pill.
    //
    // The same shape as the notch's own report, which had triggers for
    // everything except the input that changes late.
    onEditingChanged: reportTimer.restart()
    // The surface itself moved (a bar switched on beside the dock, a bar's
    // size): every place the pill reported moved with it.
    onReportOriginChanged: reportTimer.restart()
    onHasContentChanged: reportTimer.restart()
    onXChanged: reportTimer.restart()
    onYChanged: reportTimer.restart()
    onWidthChanged: reportTimer.restart()
    onHeightChanged: reportTimer.restart()
    onVisibleChanged: reportTimer.restart()
    Component.onCompleted: reportTimer.restart()
    Component.onDestruction: clearRects()

    // The pill animates its width, so the rectangles are reported once it has
    // settled rather than on every frame of the animation.
    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: root.reportRects()
    }

    Wiggle {
        id: wiggle
        index: root.wiggleIndex
        running: root.editing && !root.selected
    }
    transform: Rotation {
        origin.x: root.width / 2
        origin.y: root.height / 2
        angle: wiggle.angle
    }

    function recount() {
        let count = 0
        for (let i = 0; i < itemRepeater.count; ++i) {
            const segment = itemRepeater.itemAt(i)
            if (segment && segment.showing) count += 1
        }
        showingCount = count
        reportTimer.restart()
    }

    // Each item with a key that is all of it; the count after `#` keeps two
    // equal items (two clocks) apart.
    // What the model below was handed last, kept outside any binding's
    // dependencies: each change hands back the very same objects for the
    // entries that stayed, which is the only way Quickshell's ScriptModel
    // matches them right (services/model/KeyedLogic.js).
    property var lastItems: ({ list: [] })
    function keptItems(next) {
        const list = Keyed.keep(lastItems.list, next, "itemKey")
        lastItems.list = list
        return list
    }
    function itemKeys(list) {
        const seen = {}
        return (list || []).map(item => {
            const text = JSON.stringify(item)
            seen[text] = (seen[text] || 0) + 1
            return Object.assign({ itemKey: text + "#" + seen[text] }, item)
        })
    }

    // A round cover at either end sits concentric in that end of the pill.
    readonly property bool coverFirst: edgeCover(0, false)
    readonly property bool coverLast: edgeCover(itemRepeater.count - 1, true)
    readonly property real inset: Metrics.pillCoverInset * scaleFactor
    // Leading and trailing along the pill: left and right when it runs across
    // the bar, above and below when it runs down it.
    readonly property real leadPad: flat ? 0 : coverFirst ? inset : iconsOnly && showingCount === 1 ? Metrics.spaceSm * scaleFactor : Metrics.pillPadding * scaleFactor
    readonly property real trailPad: flat ? 0 : coverLast ? inset : iconsOnly && showingCount === 1 ? Metrics.spaceSm * scaleFactor : Metrics.pillPadding * scaleFactor
    readonly property real highlightInset: Metrics.barHighlightInset * scaleFactor

    // The cover sits at the left of its item, so it only forms the right end
    // while no title or controls follow it.
    function edgeCover(index, rightEnd) {
        const unused = showingCount
        const segment = itemRepeater.itemAt(index)
        return segment !== null && segment.coverAt(rightEnd)
    }

    // The thickness is the bar's; the length is what the items need. Which of
    // width and height is which turns with the bar.
    // A pill is a pill thick whichever way the bar runs, and its length is
    // what its items need.
    //
    // On a vertical bar the items do not turn and the bar does not grow: the
    // icons stay the right way up and a readout that is short enough sits
    // straight on the bar, like a horizontal one. What changes is the ones
    // that are too wide for a strip - the clock stacks its hours over its
    // minutes rather than being rotated on its side or making the bar a fat
    // column. `vertical` is how a widget is told which it is.
    //
    // Both of the other two were tried first and both were worse: growing the
    // bar to its widest item took a tenth of the screen, and a quarter turn
    // put the Wi-Fi arc on its side and asked the reader to tilt their head.
    readonly property real thickness: Metrics.pillHeight * scaleFactor
    readonly property real contentLength: vertical ? content.implicitHeight : content.implicitWidth
    // On the dock: whether the apps are among the items, and the pill's
    // length without them - the room the apps are fitted into is measured
    // from the rest (DockZone.lengthBesideApps), never from the apps.
    readonly property bool holdsApps: pill.items.some(item => item.type === "apps")
    readonly property real lengthBesideApps: {
        if (!holdsApps) return 0
        const unused = showingCount
        let length = 0
        let shown = 0
        for (let index = 0; index < itemRepeater.count; ++index) {
            const segment = itemRepeater.itemAt(index)
            if (!segment || !segment.showing) continue
            shown += 1
            length += segment.lengthBesideApps
        }
        return length + Math.max(0, shown - 1) * content.columnSpacing + (flat ? 0 : leadPad + trailPad)
    }
    readonly property real length: flat ? contentLength
        : Math.max(thickness, contentLength + leadPad + trailPad)
    implicitHeight: vertical ? length : thickness
    implicitWidth: vertical ? thickness : length
    radius: flat ? 0 : height / 2
    color: flat ? "transparent" : hovered && clickable ? Colors.pillHoverFor("pillBar") : Colors.pillFor("pillBar")
    border.width: flat ? 0 : Metrics.borderWidth
    border.color: Colors.pillBorder
    visible: hasContent
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    // A spring rather than a duration: a pill whose text changes again
    // half-way (a clock, a title) is redirected from where it is instead of
    // restarting a fixed-length glide from there.
    Behavior on implicitWidth {
        enabled: Animations.motionEnabled && !root.vertical
        SpringMotion {}
    }
    Behavior on implicitHeight {
        enabled: Animations.motionEnabled && root.vertical
        SpringMotion {}
    }

    HoverHandler { id: hover }

    // The capsule lights up as a whole, so all of it answers a click: the
    // padding at its round ends and across it lies outside every item's own
    // area, and a click there - inside the highlight - did nothing. It goes to
    // the nearest item that opens something. Below the items, which take
    // their own clicks first.
    MouseArea {
        anchors.fill: parent
        enabled: !root.flat && root.clickable && !root.editing
        acceptedButtons: Qt.LeftButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            let best = null, bestDistance = Infinity
            for (let i = 0; i < itemRepeater.count; ++i) {
                const item = itemRepeater.itemAt(i)
                if (!item || !item.visible || !item.clickable) continue
                const centre = item.mapToItem(root, item.width / 2, item.height / 2)
                const distance = root.vertical ? Math.abs(centre.y - mouse.y) : Math.abs(centre.x - mouse.x)
                if (distance < bestDistance) { best = item; bestDistance = distance }
            }
            if (best) best.open()
        }
    }

    // Line between groups in the bar, centred in the gap before this group. It
    // crosses the bar, so it turns with it: a hairline down a horizontal bar,
    // across a vertical one.
    Rectangle {
        visible: root.flat && root.separator
        width: root.vertical ? Metrics.barSeparatorHeight * root.scaleFactor : Metrics.barSeparatorWidth
        height: root.vertical ? Metrics.barSeparatorWidth : Metrics.barSeparatorHeight * root.scaleFactor
        x: root.vertical ? Math.round((parent.width - width) / 2)
            : -Math.round((Metrics.barGroupGap * root.scaleFactor + width) / 2)
        y: root.vertical ? -Math.round((Metrics.barGroupGap * root.scaleFactor + height) / 2)
            : Math.round((parent.height - height) / 2)
        color: Colors.barSeparator
    }

    // A ColumnLayout when the bar is vertical and a RowLayout when it is not.
    // Two Loaders would mean the items are built twice and the widget states
    // thrown away on every change of edge, so it is one GridLayout instead -
    // one column stacks, one row does not.
    GridLayout {
        id: content
        readonly property real along: root.flat ? 0
            : root.coverFirst || root.coverLast ? root.leadPad
            : (root.length - (root.vertical ? implicitHeight : implicitWidth)) / 2
        columns: root.vertical ? 1 : 1000
        rows: root.vertical ? 1000 : 1
        x: root.vertical ? Math.round((root.width - implicitWidth) / 2) : along
        y: root.vertical ? along : Math.round((root.height - implicitHeight) / 2)
        columnSpacing: (root.flat ? Metrics.barSegmentGap : Metrics.pillItemGap) * root.scaleFactor
        rowSpacing: columnSpacing

        Repeater {
            id: itemRepeater
            // Matched, not rebuilt: a pill PillBar keeps is handed a new but
            // equal `pill` on every write of the layout, and a plain array
            // would load all of its widgets again. Kept only while equal.
            model: ScriptModel { values: root.keptItems(root.itemKeys(root.pill.items)); objectProp: "itemKey" }
            onItemAdded: root.recount()
            onItemRemoved: Qt.callLater(root.recount)

            // One item: in the bar a padded segment with a hover highlight,
            // in a capsule just the widget.
            delegate: Item {
                id: segment
                required property var modelData
                required property int index
                readonly property var entry: WidgetRegistry.type(modelData.type)
                readonly property bool showing: loader.item !== null && loader.item.hasData !== false
                readonly property bool clickable: entry !== null && entry.action.length > 0
                readonly property bool hovered: segmentHover.hovered
                // A widget can say its panel is open (the start button with
                // its menu open out of it) and that the keys are on it (the
                // dock's keyboard): the segment then keeps its backing, and
                // the keys their ring.
                readonly property bool held: loader.item !== null && loader.item.panelOpen === true
                readonly property bool keyFocus: loader.item !== null && loader.item.keyFocus === true
                // Its length without the apps widget in it, for the dock's
                // room (Pill.lengthBesideApps): the apps' padding only.
                readonly property real lengthBesideApps: modelData.type !== "apps" ? (root.vertical ? implicitHeight : implicitWidth)
                    : root.flat ? pads.start + pads.end : 0
                readonly property var pads: BarLogic.segmentPadding(coverAt(false), coverAt(true), modelData.display === "icon", {
                    cover: Metrics.pillCoverInset * root.scaleFactor, highlight: root.highlightInset,
                    icon: Metrics.spaceSm * root.scaleFactor, text: Metrics.barSegmentPadding * root.scaleFactor
                })

                function coverAt(rightEnd) {
                    const widget = loader.item
                    if (widget === null || widget.compactCover !== true || !showing) return false
                    return !rightEnd || (widget.showTitle === false && widget.expanded !== true)
                }

                visible: showing
                // The padding is at the two ends *along* the bar; across it
                // the segment is as thick as the bar.
                // Across the bar a segment is its widget; along it, the
                // widget plus the padding at the two ends. Which of width and
                // height is which turns with the bar, and nothing else does.
                implicitWidth: root.vertical
                    ? (root.flat ? root.width : loader.implicitWidth)
                    : loader.implicitWidth + (root.flat ? pads.start + pads.end : 0)
                implicitHeight: root.vertical
                    ? loader.implicitHeight + (root.flat ? pads.start + pads.end : 0)
                    : (root.flat ? root.height : loader.implicitHeight)
                Layout.alignment: Qt.AlignCenter
                onShowingChanged: root.recount()

                HoverHandler { id: segmentHover; enabled: root.flat }

                Rectangle {
                    visible: root.flat && segment.clickable
                    // Across the bar the highlight spans the bar, not the
                    // segment - the segment is only as wide as its widget, and
                    // a highlight that hugged a glyph would read as a chip
                    // rather than as the row being pointed at.
                    // Inset across the bar, full length along it.
                    x: root.vertical ? Math.round((segment.width - width) / 2) : 0
                    y: root.vertical ? 0 : root.highlightInset
                    width: root.vertical ? Math.max(0, root.barThickness - root.highlightInset * 2) : segment.width
                    height: root.vertical ? segment.height : Math.max(0, segment.height - root.highlightInset * 2)
                    radius: BarLogic.highlightRadius(root.barRadius, root.highlightInset,
                                                     root.vertical ? width : height,
                                                     segment.coverAt(false) || segment.coverAt(true))
                    color: Colors.barItemHover
                    opacity: segment.hovered || segment.held || segment.keyFocus ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }

                    FocusRing {
                        active: segment.keyFocus
                        controlRadius: parent.radius
                    }
                }

                // Below the widget so its own buttons (media controls, volume
                // wheel) receive input first.
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: root.flat ? 0 : -Metrics.spaceXs
                    acceptedButtons: Qt.LeftButton
                    enabled: segment.clickable && !root.editing
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: segment.open()
                }
                function open() {
                    const box = root.flat ? segment : root
                    const mapped = box.mapToItem(root.reportFrame, 0, 0)
                    // On the screen, not in the bar's own surface.
                    const topLeft = { x: mapped.x + root.reportOrigin.x,
                                      y: mapped.y + root.reportOrigin.y }
                    // The place along the bar the panel centres on: x when
                    // the bar runs across the screen, y when it runs down
                    // it. A vertical bar sends `anchorY` instead, which
                    // ShellPanel reads as "beside me, centred here".
                    const along = root.vertical
                        ? (root.flat ? BarLogic.anchorAlong(topLeft.y, segment.height)
                                     : root.mapToItem(null, 0, root.height / 2).y + root.reportOrigin.y)
                        : (root.flat ? BarLogic.anchorAlong(topLeft.x, segment.width)
                                     : root.mapToItem(null, root.width / 2, 0).x + root.reportOrigin.x)
                    // Out of the dock: above it at the bottom, beside it on a
                    // side, a gap off the dock's body rather than the item
                    // inside it - and on the dock's own screen, which need not
                    // be the focused one (the dock stays shown for a panel it
                    // opened only on its screen, Dock.qml `panelFromHere`).
                    const anchor = root.surface !== "dock" ? (root.vertical ? { anchorY: along } : { anchorX: along })
                        : Object.assign(DockLogic.panelAnchor(root.dockEdge, { x: topLeft.x, y: topLeft.y, width: box.width, height: box.height },
                                                              Metrics.dockPanelGap, DockService.placeOf(root.screenName)),
                                        { onScreen: root.screenName })
                    PanelService.toggle(WidgetRegistry.actionOf(segment.modelData.type), Object.assign(anchor, {
                        originX: topLeft.x, originY: topLeft.y,
                        originWidth: box.width, originHeight: box.height
                    }, segment.entry.actionArgs || {}))
                }

                // Each item carries its own size on top of the bar's scale, so
                // one tile can be bigger than the ones beside it. It scales the
                // item, not the capsule: the bar is a layer surface of a fixed
                // height, so a taller pill would be clipped - and one tile must
                // not change the space reserved for every window.
                readonly property real itemScale: root.scaleFactor * LayoutLogic.sizeScale(segment.modelData.size)

                Loader {
                    id: loader
                    x: root.vertical ? Math.round((segment.width - implicitWidth) / 2)
                        : root.flat ? segment.pads.start : 0
                    y: root.vertical ? (root.flat ? segment.pads.start : 0)
                        : Math.round((segment.height - implicitHeight) / 2)
                    source: WidgetRegistry.isAvailable(segment.modelData.type) ? WidgetRegistry.source(segment.modelData.type) : ""

                    onLoaded: {
                        item.instance = Qt.binding(() => ({
                            id: root.pill.id + "-" + segment.index,
                            type: segment.modelData.type,
                            screen: root.screenName,
                            options: Object.assign({}, segment.entry && segment.entry.options ? segment.entry.options : {}, segment.modelData.options)
                        }))
                        item.scaleFactor = Qt.binding(() => segment.itemScale * Metrics.pillContentScale)
                        item.sizeClass = Qt.binding(() => segment.modelData.display === "icon" ? "icon"
                            : segment.modelData.display === "expanded" ? "expanded" : "small")
                        item.hovered = Qt.binding(() => root.flat ? segment.hovered : root.hovered)
                        item.alignment = "center"
                        item.inGroup = true
                        // Which way the bar runs, for the readouts that have
                        // a second shape for a strip - the clock stacks its
                        // hours over its minutes. A widget that has nothing
                        // to change simply ignores it.
                        if (item.vertical !== undefined) item.vertical = Qt.binding(() => root.vertical)
                    }
                }
            }
        }
    }
}
