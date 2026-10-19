import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.dock
import "../../services/dock/DockLogic.js" as Logic
import "../../services/dock/PreviewLogic.js" as Preview
import "../../services/dock/BadgeLogic.js" as Badges

// The dock's apps (DockService.items): the pinned ones, then - after a line -
// the ones that only have windows. A pill on the dock holds it like any other
// widget (shell/dock/Dock.qml); it is offered only there (WidgetRegistry
// `dockOnly`), because it needs the dock's service and the dock's room for
// its labels and its magnification.
//
// The pill sets the properties every widget has; the icon size is the
// dock's own setting - smaller only when the dock's edge has no room for all
// of them (Dock.qml measures the room the other pills leave, DockLogic.fit).
//
// With Settings > Dock's previews on, the pointer resting on a running app
// shows its windows (shell/dock/DockPreview.qml) where its name would show;
// with the wheel for the volume on, the wheel over an app turns its sound
// and the name's place says how loud.
Item {
    id: root

    // What a pill hands every widget (WidgetBase's names).
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "center"
    property bool inGroup: false
    property bool vertical: false
    property bool hasData: true

    readonly property string screenName: instance ? String(instance.screen || "") : ""
    readonly property string edge: DockService.position
    // This dock's apps: every dock's, or its own screen's running apps
    // (DockService.itemsOn).
    readonly property var apps: DockService.itemsOn(screenName)
    readonly property int firstRunning: apps.findIndex(app => !app.pinned)
    readonly property real room: screenName.length && DockService.appsRoomOn[screenName] !== undefined
        ? DockService.appsRoomOn[screenName] : -1
    readonly property real slot: room < 0 ? DockService.iconSize
        : Logic.fit(apps.length, DockService.iconSize, Metrics.dockGap,
                    room - (firstRunning > 0 ? Metrics.dockSeparatorRoom : 0), 0)
    readonly property bool keyboard: DockService.keyboardScreen === screenName && screenName.length > 0

    // ---- places along the row -------------------------------------------------
    readonly property var rest: Logic.layout(apps.length, slot, Metrics.dockGap, null, 0,
                                             firstRunning, Metrics.dockSeparatorRoom)
    readonly property var centres: rest.offsets.map((offset, index) => offset + rest.sizes[index] / 2)
    // Magnification: the pointer's place along the row, -1 away.
    property real pointerAlong: -1
    property real magnifyAmount: DockService.magnifies && hover.hovered && !dragging ? 1 : 0
    Behavior on magnifyAmount { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    readonly property var scales: Logic.magnify(pointerAlong, centres, Metrics.dockMagnifyScale, slot * Metrics.dockMagnifyReach)
        .map(scale => 1 + (scale - 1) * magnifyAmount)
    readonly property var placed: Logic.layout(apps.length, slot, Metrics.dockGap, scales, 0,
                                               firstRunning, Metrics.dockSeparatorRoom)

    implicitWidth: vertical ? slot : Math.max(slot, placed.length)
    implicitHeight: vertical ? Math.max(slot, placed.length) : slot
    // Its length at rest, unmagnified: the dock's body at rest is measured
    // with it (Dock.qml restBody).
    readonly property real restAlong: Math.max(slot, rest.length)
    onRestAlongChanged: if (screenName.length) DockService.reportAppsRest(screenName, restAlong)
    onScreenNameChanged: if (screenName.length) DockService.reportAppsRest(screenName, restAlong)

    // The pointer's place matters only to the magnification: without it a
    // move along the row laid every icon out again for nothing.
    HoverHandler {
        id: hover
        onPointChanged: if (DockService.magnifies) root.pointerAlong = hovered ? (root.vertical ? point.position.y : point.position.x) : -1
        onHoveredChanged: {
            if (!hovered) root.pointerAlong = -1
            // The streams are bound while the pointer is here, so the wheel
            // finds their volume (DockService.holdStreams).
            if (root.screenName.length) DockService.holdStreams(root.screenName, hovered && DockService.wheelVolumeOn)
        }
    }

    // Between the pins and the apps that are only running.
    Rectangle {
        visible: root.firstRunning > 0 && root.placed.offsets.length > root.firstRunning
        readonly property real at: visible ? root.placed.offsets[root.firstRunning] - Metrics.dockSeparatorRoom / 2 - Metrics.dockGap / 2 : 0
        x: root.vertical ? (root.width - width) / 2 : at
        y: root.vertical ? at : (root.height - height) / 2
        width: root.vertical ? Metrics.dockSeparatorLength : Metrics.borderWidth
        height: root.vertical ? Metrics.borderWidth : Metrics.dockSeparatorLength
        color: Colors.border
    }

    // Where a dragged app would land.
    Rectangle {
        visible: root.dragging && root.dropSlot >= 0 && !root.dragAway
        x: root.vertical ? 0 : root.dropAt - width / 2
        y: root.vertical ? root.dropAt - height / 2 : 0
        width: root.vertical ? root.slot : Metrics.focusBorderWidth
        height: root.vertical ? Metrics.focusBorderWidth : root.slot
        color: Colors.accentLine
    }

    Repeater {
        model: ScriptModel { values: root.apps; objectProp: "key" }
        DockItem {
            id: dockItem
            required property var modelData
            required property int index
            app: modelData
            edge: root.edge
            readonly property real size: root.placed.sizes[index] !== undefined ? root.placed.sizes[index] : root.slot
            readonly property real offset: root.placed.offsets[index] !== undefined ? root.placed.offsets[index] : 0
            iconSize: size
            x: root.vertical ? (root.edge === "left" ? 0 : root.width - size) : offset
            y: root.vertical ? offset : root.height - size
            width: size
            height: size
            keyFocus: root.keyboard && DockService.keyIndex === index
            running: DockService.runningOf(modelData)
            active: DockService.activeOf(modelData)
            wheelTurns: DockService.wheelVolumeOn && running
            dragging: DockService.dragKey === modelData.key && root.dragging
            removing: dragging && root.dragAway
            z: dragging ? 1 : 0
            onActivated: { DockService.hidePreview(); DockService.activate(modelData.key, root.screenName) }
            onNewWindow: { DockService.hidePreview(); DockService.newWindow(modelData.key) }
            onMenuWanted: { DockService.hidePreview(); root.openMenu(index) }
            onWheeled: steps => root.turnVolume(index, steps)
            onDragStarted: {
                DockService.dragKey = modelData.key
                DockService.dragScreen = root.screenName
                root.dragIndex = index
            }
            onDragMoved: (along, acrossOut) => root.dragTo(index, along, acrossOut)
            onDragEnded: (along, acrossOut) => root.dragEnd(index, along, acrossOut)
            onDragCanceled: (along, acrossOut, rising) => root.dragCancel(modelData.key, acrossOut, rising)
            onHoveredChanged: root.labelFor(index, hovered)
            // An app before it that went or came moves it along the row
            // under the pointer: the name goes with it, or its leave would
            // read as another icon's and leave the name up.
            onIndexChanged: if (hovered) root.labelIndex = index
        }
    }

    // ---- the name over an icon ------------------------------------------------
    property int labelIndex: -1
    property bool labelShown: false
    property string notice: ""
    // The pointer entered or left an icon (DockLogic.labelAfter): the name
    // shows after a delay, and once it is up the next icon's shows at once -
    // the gap between two icons, where no icon has the pointer, is crossed
    // within a grace instead of taking the name down. The grace is the
    // dock's own wait after the pointer left (a wait, not motion: the same
    // with animations off), so a name stays as long as the dock does.
    function labelFor(index, entered) {
        const next = Logic.labelAfter({ index: labelIndex, shown: labelShown }, index, entered)
        labelIndex = next.index
        labelShown = next.shown
        if (next.timer === "show") { labelGrace.stop(); labelTimer.restart() }
        else if (next.timer === "hide") { labelTimer.stop(); labelGrace.restart() }
        else if (next.timer === "stop") { labelTimer.stop(); labelGrace.stop() }
    }
    Timer { id: labelTimer; interval: Animations.dockLabelDelay; onTriggered: root.labelShown = true }
    Timer { id: labelGrace; interval: Animations.dockHideDelay; onTriggered: root.labelShown = false }
    // The row lost the icon the name was over (DockLogic.labelInRow).
    onAppsChanged: {
        const next = Logic.labelInRow({ index: labelIndex, shown: labelShown }, apps.length)
        if (!next) return
        labelTimer.stop()
        labelGrace.stop()
        labelIndex = next.index
        labelShown = next.shown
    }
    Timer { id: noticeTimer; interval: Metrics.osdTimeout; onTriggered: root.notice = "" }

    // ---- the windows instead of the name ---------------------------------------
    // Where the name would show, an app with windows shows them (with the
    // dock's previews on, PreviewLogic.wanted): asked when the name would come
    // up, let go when it would go - the strip keeps itself while the pointer
    // is on it - and taken down at once for an app that has no windows to show.
    readonly property var labelApp: labelIndex >= 0 && labelIndex < apps.length ? apps[labelIndex] : null
    readonly property bool previewing: DockService.previewsOn && Preview.wanted(true, labelApp)
    function syncPreview() {
        if (!DockService.previewsOn || !screenName.length) return
        if (labelShown && previewing && !dragging) DockService.showPreview(screenName, labelApp.key, screenRect(labelIndex))
        else if (!labelShown) DockService.releasePreview(screenName)
        else DockService.hidePreview()
    }
    onLabelShownChanged: syncPreview()
    onLabelIndexChanged: if (labelShown) syncPreview()

    // ---- the wheel: an app's volume --------------------------------------------
    // Said where its name shows (DockService.stepVolume, BadgeLogic.volumeNotice).
    function turnVolume(index, steps) {
        const app = apps[index]
        if (!app) return
        DockService.hidePreview()
        const level = DockService.stepVolume(app.key, steps, screenName)
        labelIndex = index
        notice = Badges.volumeNotice(level)
        noticeTimer.restart()
    }
    function itemRect(index) {
        const size = placed.sizes[index] !== undefined ? placed.sizes[index] : slot
        const offset = placed.offsets[index] !== undefined ? placed.offsets[index] : 0
        return vertical ? { x: edge === "left" ? 0 : width - size, y: offset, width: size, height: size }
                        : { x: offset, y: height - size, width: size, height: size }
    }
    // Outside the widget, in the room the dock's surface keeps for it, and
    // kept on that surface (a taskbar's first app is at the screen's edge).
    // While a pinned app is pulled off the dock it says what letting go does.
    DockLabel {
        z: 2
        edge: root.edge
        readonly property int index: root.dragAway ? root.dragIndex : root.labelIndex
        anchorRect: index >= 0 && index < root.apps.length ? root.itemRect(index) : null
        // The menu's word for it.
        text: root.dragAway ? "Unpin"
            : root.notice.length ? root.notice
            : root.labelIndex >= 0 && root.apps[root.labelIndex] ? root.apps[root.labelIndex].name : ""
        // An app whose windows show above it does not show its name too.
        shown: root.dragging ? root.dragAway : (root.labelShown && !root.previewing) || root.notice.length > 0
        clampToWindow: true
    }

    // ---- where the apps are, for `dock rects` (tests aim with it) -------------
    // Mapped to the dock's drawn content without the slide that takes it out
    // over the edge (Dock.qml `frame`, the pills' reportFrame), so a place
    // reported while the dock is hidden is where it shows - mapped to the
    // window, `dock rects` put a hidden dock's icons below the screen, and
    // the dock menu's morph came from there. Asked for when it is reported,
    // long after the window was made; the window itself without one.
    function frameItem() {
        const dock = QsWindow.window
        return dock && dock.frame ? dock.frame : null
    }
    function reportRects() {
        if (!screenName.length) return
        const origin = DockService.originOn[screenName] || { x: 0, y: 0 }
        const frame = frameItem()
        DockService.reportRects(screenName, apps.map((app, index) => {
            const rect = itemRect(index)
            const topLeft = mapToItem(frame, rect.x, rect.y)
            return { x: Math.round(topLeft.x + origin.x), y: Math.round(topLeft.y + origin.y),
                     width: Math.round(rect.width), height: Math.round(rect.height),
                     pinned: app.pinned, running: DockService.runningOf(app) }
        }))
    }
    Timer { id: rectsTimer; interval: Animations.hover; onTriggered: root.reportRects() }
    onPlacedChanged: rectsTimer.restart()
    onXChanged: rectsTimer.restart()
    onYChanged: rectsTimer.restart()
    // The widget does not move inside its pill when the dock's body does:
    // the dock's own reports say when.
    Connections {
        target: DockService
        function onOriginOnChanged() { rectsTimer.restart() }
        function onBodiesChanged() { rectsTimer.restart() }
    }
    Component.onCompleted: rectsTimer.restart()
    Component.onDestruction: {
        if (!screenName.length) return
        DockService.reportRects(screenName, null)
        // Gone in the middle of a drag (the pill taken off the dock): the drag
        // goes with it, and so do the streams it held and its windows' strip.
        if (dragging) DockService.endDrag(screenName)
        DockService.holdStreams(screenName, false)
        if (DockService.previewScreen === screenName) DockService.hidePreview()
    }

    // ---- menu ------------------------------------------------------------------
    // An icon's place on the screen: mapped to the dock's content as `dock
    // rects` is, moved by where the dock's surface sits (Dock.qml reports it).
    // The menu and the previews come out of it.
    function screenRect(index) {
        const rect = itemRect(index)
        const topLeft = mapToItem(frameItem(), rect.x, rect.y)
        const origin = DockService.originOn[screenName] || { x: 0, y: 0 }
        return { x: topLeft.x + origin.x, y: topLeft.y + origin.y, width: rect.width, height: rect.height }
    }
    function openMenu(index) {
        const app = apps[index]
        if (!app) return
        DockService.openMenu(app.key, screenName, screenRect(index))
    }
    Connections {
        target: DockService
        enabled: root.keyboard
        function onMenuWanted() { root.openMenu(DockService.keyIndex) }
    }

    // ---- drag ---------------------------------------------------------------
    // Along the dock: among the pins (DockService.drop). Pulled away from the
    // dock, a pinned app is unpinned when it is let go (DockLogic.dragOutcome)
    // - it fades and its label says so first.
    readonly property bool dragging: DockService.dragKey.length > 0 && DockService.dragScreen === screenName
    property int dropSlot: -1
    property real dropAt: 0
    property int dragIndex: -1
    property bool dragAway: false
    // How far a pull off the dock can go and still be on its surface: the
    // room above a bottom dock for the names (Dock.qml `headroom`, less a
    // little), the whole label width beside a side one.
    readonly property real unpinRoom: vertical ? Infinity : Metrics.dockLabelHeight + Metrics.dockLabelGap - Metrics.spaceSm
    function pinSlots(skip) {
        const result = []
        for (let index = 0; index < apps.length; ++index)
            if (apps[index].pinned && index !== skip) result.push([placed.offsets[index], placed.sizes[index]])
        return result
    }
    function dragTo(index, along, acrossOut) {
        dragAway = Logic.dragAway(apps[index], acrossOut, slot, Metrics.dockUnpinReach, unpinRoom)
        const at = (vertical ? itemRect(index).y : itemRect(index).x) + along
        const pins = pinSlots(index)
        dropSlot = Logic.slotAt(at, pins)
        dropAt = dropSlot < pins.length ? pins[dropSlot][0] - Metrics.dockGap / 2
            : pins.length ? pins[pins.length - 1][0] + pins[pins.length - 1][1] + Metrics.dockGap / 2 : 0
    }
    function dragEnd(index, along, acrossOut) {
        const app = apps[index]
        const outcome = Logic.dragOutcome(app, acrossOut, slot, dropSlot, Metrics.dockUnpinReach, unpinRoom)
        if (outcome === "unpin") {
            DockService.unpinByDrag(app.key)
        } else if (outcome === "drop" && DockService.drop(app.key, dropSlot) === "full") {
            labelIndex = index
            notice = "At most " + LayoutService.dockPinLimit + " pinned apps"
            noticeTimer.restart()
        }
        resetDrag()
        DockService.endDrag()
    }
    // Taken away by the system: a pull past the surface's edge is one, and
    // unpins as letting go there would have (DockLogic.cancelOutcome). By
    // the app's key, and only the app being dragged: a cancel can come from
    // an icon on its way out, whose place may already be another app's.
    function dragCancel(key, acrossOut, rising) {
        if (key !== DockService.dragKey) return
        const app = apps.find(item => item.key === key) || null
        if (Logic.cancelOutcome(app, acrossOut, rising, slot, Metrics.dockUnpinReach, unpinRoom) === "unpin")
            DockService.unpinByDrag(key)
        resetDrag()
        DockService.endDrag()
    }
    function resetDrag() {
        dropSlot = -1
        dragIndex = -1
        dragAway = false
    }
    // A drag that ended without its icon - the app went, the dock's service
    // let it go (DockService.endDrag) - leaves no drop marker or "Unpin"
    // behind.
    onDraggingChanged: if (!dragging) resetDrag()
}
