import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.dock
import "../../services/dock/DockLogic.js" as Logic

// The dock's apps (DockService.items): the pinned ones, then - after a line -
// the ones that only have windows. A pill on the dock holds it like any other
// widget (shell/dock/Dock.qml); it is offered only there (WidgetRegistry
// `dockOnly`), because it needs the dock's service and the dock's room for
// its labels and its magnification.
//
// The pill sets the properties every widget has; the icon size is the
// dock's own setting.
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
    readonly property var apps: DockService.items
    readonly property int firstRunning: apps.findIndex(app => !app.pinned)
    readonly property real slot: DockService.iconSize
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

    HoverHandler {
        id: hover
        onPointChanged: root.pointerAlong = hovered ? (root.vertical ? point.position.y : point.position.x) : -1
        onHoveredChanged: if (!hovered) root.pointerAlong = -1
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
        visible: root.dragging && root.dropSlot >= 0
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
            dragging: DockService.dragKey === modelData.key && root.dragging
            z: dragging ? 1 : 0
            onActivated: DockService.activate(modelData.key)
            onNewWindow: DockService.newWindow(modelData.key)
            onMenuWanted: root.openMenu(index)
            onDragStarted: {
                DockService.dragKey = modelData.key
                DockService.dragScreen = root.screenName
            }
            onDragMoved: along => root.dragTo(index, along)
            onDragEnded: (along, acrossOut) => root.dragEnd(index, along, acrossOut)
            onHoveredChanged: root.labelFor(hovered ? index : -1)
        }
    }

    // ---- the name over an icon ------------------------------------------------
    property int labelIndex: -1
    property bool labelShown: false
    property string notice: ""
    function labelFor(index) {
        if (index < 0) {
            labelTimer.stop()
            labelShown = false
            return
        }
        labelIndex = index
        // Once one is up, the next shows at once as the pointer moves on.
        if (!labelShown) labelTimer.restart()
    }
    Timer { id: labelTimer; interval: Animations.dockLabelDelay; onTriggered: root.labelShown = true }
    Timer { id: noticeTimer; interval: Metrics.osdTimeout; onTriggered: root.notice = "" }
    function itemRect(index) {
        const size = placed.sizes[index] !== undefined ? placed.sizes[index] : slot
        const offset = placed.offsets[index] !== undefined ? placed.offsets[index] : 0
        return vertical ? { x: edge === "left" ? 0 : width - size, y: offset, width: size, height: size }
                        : { x: offset, y: height - size, width: size, height: size }
    }
    DockLabel {
        z: 2
        edge: root.edge
        anchorRect: root.labelIndex >= 0 && root.labelIndex < root.apps.length ? root.itemRect(root.labelIndex) : null
        text: root.notice.length ? root.notice
            : root.labelIndex >= 0 && root.apps[root.labelIndex] ? root.apps[root.labelIndex].name : ""
        shown: (root.labelShown || root.notice.length > 0) && !root.dragging
        clampToArea: false
    }

    // ---- where the apps are, for `dock rects` (tests aim with it) -------------
    function reportRects() {
        if (!screenName.length) return
        const origin = DockService.originOn[screenName] || { x: 0, y: 0 }
        DockService.reportRects(screenName, apps.map((app, index) => {
            const rect = itemRect(index)
            const topLeft = mapToItem(null, rect.x, rect.y)
            return { x: Math.round(topLeft.x + origin.x), y: Math.round(topLeft.y + origin.y),
                     width: Math.round(rect.width), height: Math.round(rect.height),
                     pinned: app.pinned, running: app.running }
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
    Component.onDestruction: if (screenName.length) DockService.reportRects(screenName, null)

    // ---- menu ------------------------------------------------------------------
    // Its place on the screen: mapped to the dock's window, moved by where the
    // dock's surface sits (Dock.qml reports it).
    function openMenu(index) {
        const app = apps[index]
        if (!app) return
        const rect = itemRect(index)
        const topLeft = mapToItem(null, rect.x, rect.y)
        const origin = DockService.originOn[screenName] || { x: 0, y: 0 }
        DockService.openMenu(app.key, screenName, { x: topLeft.x + origin.x, y: topLeft.y + origin.y,
                                                    width: rect.width, height: rect.height })
    }
    Connections {
        target: DockService
        enabled: root.keyboard
        function onMenuWanted() { root.openMenu(DockService.keyIndex) }
    }

    // ---- drag ---------------------------------------------------------------
    readonly property bool dragging: DockService.dragKey.length > 0 && DockService.dragScreen === screenName
    property int dropSlot: -1
    property real dropAt: 0
    function pinSlots(skip) {
        const result = []
        for (let index = 0; index < apps.length; ++index)
            if (apps[index].pinned && index !== skip) result.push([placed.offsets[index], placed.sizes[index]])
        return result
    }
    function dragTo(index, along) {
        const at = (vertical ? itemRect(index).y : itemRect(index).x) + along
        const pins = pinSlots(index)
        dropSlot = Logic.slotAt(at, pins)
        dropAt = dropSlot < pins.length ? pins[dropSlot][0] - Metrics.dockGap / 2
            : pins.length ? pins[pins.length - 1][0] + pins[pins.length - 1][1] + Metrics.dockGap / 2 : 0
    }
    function dragEnd(index, along, acrossOut) {
        const app = apps[index]
        // Dropped off the dock: nothing happens.
        if (app && dropSlot >= 0 && acrossOut < slot) {
            if (DockService.drop(app.key, dropSlot) === "full") {
                labelIndex = index
                notice = "At most " + LayoutService.dockPinLimit + " pinned apps"
                noticeTimer.restart()
            }
        }
        dropSlot = -1
        DockService.dragKey = ""
        DockService.dragScreen = ""
    }
}
