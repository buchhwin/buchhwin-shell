import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/DockLogic.js" as Logic

// The dock: the launcher's pinned apps and the apps that have windows, along
// the bottom (or a side) of a screen. Its own block next to the notch, the
// bar and the widgets, in any desktop mode, and off until Settings > Dock or
// Super+Shift+D switch it on. DockService has the apps and what they do;
// DockLogic the arithmetic.
//
// One surface per screen, anchored along its whole edge and as thick as the
// settings make it - never as long or as thick as the apps make it, so it
// never changes size while mapped (testing.md pitfall 57). The body is drawn
// centred in it, and the input mask is the body: the rest is transparent and
// takes no input.
//
// Shown, it stays unless a window comes over it (intellihide), its edge is
// all there is of it (hidden) or it reserves its room (always). Hidden, a
// strip at the screen edge takes the pointer and brings it back. Under a
// fullscreen window the surface stays mapped with nothing drawn and no input
// (the notch's pattern, pitfalls 88 and 89).
Variants {
    // Off: no surfaces, and DockService is never asked.
    model: SettingsService.loaded && SettingsService.value("dock.enabled") === true ? DockService.screens : []

    PanelWindow {
        id: window
        required property var modelData
        readonly property string screenName: modelData ? modelData.name : ""
        readonly property string edge: DockService.position
        readonly property bool vertical: Logic.vertical(edge)

        readonly property bool fullscreenOn: HyprlandService.fullscreenOn(modelData)
        readonly property bool mapped: DockService.enabled
        readonly property bool active: mapped && !fullscreenOn
        // A mapped layer surface keeps its zone and its anchors: a change of
        // either maps it again.
        property bool remapping: false

        // ---- what lies beside it --------------------------------------------------
        // The bar, when there is one: on this edge the dock stands beyond it -
        // a reserving bar's zone puts it there, a bar that reserves nothing
        // gets the same room as this surface's margin. On a side it spans,
        // a reserving bar shortens the surface.
        readonly property real barInset: LayoutService.barShown ? LayoutService.barBottom(screenName) : -1
        readonly property string barEdge: LayoutService.barEdge(screenName)
        readonly property bool barReserves: LayoutService.barShown && LayoutService.bar && LayoutService.bar.reserve === true
        readonly property real layerMargin: barInset > 0 && barEdge === edge && !barReserves ? barInset : 0
        function barOn(side) {
            return barInset > 0 && barEdge === side && (barReserves || side === edge) ? barInset : 0
        }
        readonly property var offsets: ({ left: barOn("left"), right: barOn("right"), top: barOn("top"), bottom: barOn("bottom") })

        // ---- geometry -------------------------------------------------------------
        readonly property var apps: DockService.items
        readonly property int firstRunning: apps.findIndex(app => !app.pinned)
        readonly property real labelRoom: Metrics.dockLabelHeight + Metrics.dockLabelGap
        readonly property real magnifyRoom: DockService.magnifies ? Math.ceil(DockService.iconSize * (Metrics.dockMagnifyScale - 1)) : 0
        // The surface's length along its edge, from the screen and what lies
        // on the sides it spans - never from this window, whose size the
        // geometry decides.
        readonly property real room: modelData
            ? (vertical ? modelData.height - offsets.top - offsets.bottom : modelData.width - offsets.left - offsets.right) : 0
        readonly property var geo: Logic.geometry(edge, {
            icon: DockService.iconSize, pad: Metrics.dockPadding, gap: Metrics.dockGap,
            margin: DockService.margin, headroom: labelRoom + magnifyRoom, windowGap: Metrics.windowGap,
            strip: Metrics.dockEdgeStrip, count: apps.length, room: room,
            sep: firstRunning, sepRoom: Metrics.dockSeparatorRoom
        }, DockService.reserves)

        screen: modelData
        visible: mapped && !remapping
        color: "transparent"
        anchors {
            bottom: edge === "bottom" || vertical
            top: vertical
            left: edge !== "right"
            right: edge !== "left"
        }
        margins {
            bottom: edge === "bottom" ? layerMargin : 0
            left: edge === "left" ? layerMargin : 0
            right: edge === "right" ? layerMargin : 0
        }
        implicitHeight: vertical ? 0 : geo.thickness
        implicitWidth: vertical ? geo.thickness : 0
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: geo.zone
        WlrLayershell.namespace: "buchhwin-dock"
        WlrLayershell.layer: WlrLayer.Top
        // The keyboard only while the key gave it to this dock: OnDemand, with
        // a grab that a click anywhere else ends (pitfall 83, never Exclusive).
        readonly property bool keyboard: active && DockService.keyboardScreen === screenName
        WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        HyprlandFocusGrab {
            windows: [window]
            active: window.keyboard
            onCleared: DockService.endKeyboard(window.screenName)
        }

        onExclusiveZoneChanged: remap()
        onEdgeChanged: remap()
        readonly property real thickness: geo.thickness
        onThicknessChanged: remap()
        function remap() {
            if (!window.visible) return
            window.remapping = true
            remapTimer.restart()
        }
        Timer {
            id: remapTimer
            interval: Animations.notchHoverDelay
            onTriggered: window.remapping = false
        }

        // ---- shown or hidden --------------------------------------------------------
        // The pointer holds the dock: it came onto a shown dock, or rested on
        // the edge of a hidden one long enough. Set by the pointer's own
        // events, never from `shown` - that is decided from this.
        property bool armed: false
        readonly property bool pointerHolds: hover.hovered && armed
        readonly property bool dragging: DockService.dragKey.length > 0 && DockService.dragScreen === screenName
        readonly property bool covered: DockService.covered(screenName)
        readonly property bool want: Logic.wantRevealed({
            enabled: DockService.enabled, fullscreen: fullscreenOn, dragging: dragging,
            menuOpen: DockService.menuOpenOn(screenName), keyboard: keyboard, mode: DockService.visibility,
            pointer: pointerHolds, hotkey: DockService.hotkeyScreen === screenName, covered: covered
        })
        property bool shown: false
        Component.onCompleted: { shown = want; report() }
        onWantChanged: {
            if (want) {
                hideTimer.stop()
                shown = true
            } else if (shown) {
                // A window that came over it: soon, so it is gone before the
                // window settles. The pointer that left: a little later.
                hideTimer.interval = covered && !hover.hovered ? Animations.dockCoverDelay : Animations.dockHideDelay
                hideTimer.restart()
            }
        }
        Timer {
            id: hideTimer
            onTriggered: if (!window.want) { window.shown = false; window.armed = false }
        }
        Timer {
            id: revealTimer
            interval: Animations.dockRevealDelay
            onTriggered: if (hover.hovered) window.armed = true
        }
        // The key showed it and the pointer never came: it goes with the key
        // again, with Escape, or with a click elsewhere (the grab).
        onShownChanged: report()
        onActiveChanged: report()

        readonly property string maskKind: Logic.maskKind({ active: active, revealed: shown, reserves: DockService.reserves })
        mask: Region { item: window.maskKind === "body" ? hitArea : window.maskKind === "strip" ? stripArea : null }

        // 0 hidden, 1 shown: a slide out over the edge in Full, a fade in
        // Reduced, nothing in Off.
        property real progress: shown && active ? 1 : 0
        Behavior on progress {
            NumberAnimation {
                duration: Animations.motionEnabled ? Animations.dockSlide : Animations.hover
                easing.type: window.shown ? Animations.easingEnter : Animations.easingExit
            }
        }
        readonly property bool contentShown: active && (shown || progress > 0)

        // ---- what the service hears -----------------------------------------------
        function screenRect() {
            return modelData ? { x: modelData.x, y: modelData.y, width: modelData.width, height: modelData.height } : null
        }
        // Where this surface's top-left corner is on its screen.
        readonly property point origin: edge === "bottom"
            ? Qt.point(offsets.left, (modelData ? modelData.height : 0) - offsets.bottom - geo.thickness)
            : edge === "right" ? Qt.point((modelData ? modelData.width : 0) - offsets.right - geo.thickness, offsets.top)
            : Qt.point(offsets.left, offsets.top)
        function report() {
            DockService.reportBody(screenName, active ? Logic.globalRect(geo.body, screenRect(), offsets, geo.thickness, edge) : null)
            DockService.reportShown(screenName, active && shown)
            DockService.reportReach(screenName, geo.reach)
            const rects = slots.map((slot, index) => ({
                x: Math.round(origin.x + geo.body.x + (vertical ? 0 : slot.offset)),
                y: Math.round(origin.y + geo.body.y + (vertical ? slot.offset : 0)),
                width: Math.round(vertical ? geo.across : slot.size), height: Math.round(vertical ? slot.size : geo.across),
                pinned: apps[index] ? apps[index].pinned : false, running: apps[index] ? apps[index].running : false
            }))
            DockService.reportRects(screenName, active ? rects : null)
        }
        onGeoChanged: report()
        onOriginChanged: report()
        onSlotsChanged: report()
        Component.onDestruction: DockService.forget(screenName)

        // ---- the apps' places ------------------------------------------------------
        // Along the body: resting places, then the magnified ones while the
        // pointer is on the dock.
        readonly property var rest: Logic.layout(apps.length, geo.icon, Metrics.dockGap, null, Metrics.dockPadding,
                                                 firstRunning, Metrics.dockSeparatorRoom)
        readonly property var centres: rest.offsets.map((offset, index) => offset + rest.sizes[index] / 2)
        property real pointerAlong: -1
        property real magnifyAmount: DockService.magnifies && hover.hovered && !dragging ? 1 : 0
        Behavior on magnifyAmount { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        readonly property var scales: Logic.magnify(pointerAlong, centres, Metrics.dockMagnifyScale,
                                                    geo.icon * Metrics.dockMagnifyReach)
            .map(scale => 1 + (scale - 1) * magnifyAmount)
        readonly property var placed: Logic.layout(apps.length, geo.icon, Metrics.dockGap, scales, Metrics.dockPadding,
                                                   firstRunning, Metrics.dockSeparatorRoom)
        // The body grows with the magnified icons, around the same centre.
        readonly property real grow: placed.length - rest.length
        readonly property var slots: placed.offsets.map((offset, index) => ({ offset: offset - grow / 2, size: placed.sizes[index] }))

        // ---- input areas ------------------------------------------------------------
        // The body, the band down to the edge, and - magnifying - the room the
        // icons grow into.
        Item {
            id: hitArea
            readonly property var box: window.geo.hit
            readonly property real extra: window.magnifyRoom
            x: window.edge === "right" ? box.x - extra : box.x
            y: window.edge === "bottom" ? box.y - extra : box.y
            width: box.width + (window.vertical ? extra : 0)
            height: box.height + (window.vertical ? 0 : extra)
        }
        // On the whole surface, not on the area: the input mask already keeps
        // the pointer to the area (or the strip), and only an ancestor of the
        // icons keeps its hover while the pointer is on one - an icon's own
        // MouseArea took it from a handler beside it, and the dock went away
        // under the hand that was on it.
        HoverHandler {
            id: hover
            onPointChanged: window.pointerAlong = hovered
                ? (window.vertical ? point.position.y - window.geo.body.y : point.position.x - window.geo.body.x) : -1
            onHoveredChanged: {
                if (hovered && window.shown) window.armed = true
                else if (hovered) revealTimer.restart()
                if (!hovered) {
                    revealTimer.stop()
                    window.armed = false
                    window.pointerAlong = -1
                }
            }
        }
        Item {
            id: stripArea
            x: window.geo.strip.x
            y: window.geo.strip.y
            width: window.geo.strip.width
            height: window.geo.strip.height
        }

        // ---- the body ------------------------------------------------------------
        Item {
            id: content
            visible: window.contentShown
            opacity: window.progress
            width: window.width
            height: window.height
            // Out over the edge as it goes.
            readonly property real away: Animations.motionEnabled ? (1 - window.progress) * (DockService.margin + window.geo.across + Metrics.dockEdgeStrip) : 0
            transform: Translate {
                x: window.edge === "left" ? -content.away : window.edge === "right" ? content.away : 0
                y: window.edge === "bottom" ? content.away : 0
            }

            Rectangle {
                id: body
                x: window.vertical ? window.geo.body.x : window.geo.body.x - window.grow / 2
                y: window.vertical ? window.geo.body.y - window.grow / 2 : window.geo.body.y
                width: window.vertical ? window.geo.body.width : window.geo.body.width + window.grow
                height: window.vertical ? window.geo.body.height + window.grow : window.geo.body.height
                radius: Metrics.radiusPanel
                color: Colors.panelFor("dock")
                border.width: Metrics.borderWidth
                border.color: Colors.panelBorder
                visible: window.apps.length > 0
            }

            // Between the pins and the apps that are only running.
            Rectangle {
                visible: window.firstRunning > 0
                readonly property real at: window.firstRunning > 0 && window.slots.length > window.firstRunning
                    ? window.slots[window.firstRunning].offset - Metrics.dockSeparatorRoom / 2 - Metrics.dockGap / 2 : 0
                x: window.vertical ? window.geo.body.x + (window.geo.across - width) / 2 : window.geo.body.x + at
                y: window.vertical ? window.geo.body.y + at : window.geo.body.y + (window.geo.across - height) / 2
                width: window.vertical ? Metrics.dockSeparatorLength : Metrics.borderWidth
                height: window.vertical ? Metrics.borderWidth : Metrics.dockSeparatorLength
                color: Colors.border
            }

            // The drop place while a pin is dragged.
            Rectangle {
                visible: window.dragging && window.dropSlot >= 0
                readonly property real at: window.dropAt
                x: window.vertical ? window.geo.body.x : window.geo.body.x + at - width / 2
                y: window.vertical ? window.geo.body.y + at - height / 2 : window.geo.body.y
                width: window.vertical ? window.geo.across : Metrics.focusBorderWidth
                height: window.vertical ? Metrics.focusBorderWidth : window.geo.across
                color: Colors.accentLine
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: window.keyboard
                Keys.onPressed: event => window.key(event)

                Repeater {
                    model: ScriptModel { values: window.apps; objectProp: "key" }
                    DockItem {
                        id: dockItem
                        required property var modelData
                        required property int index
                        app: modelData
                        edge: window.edge
                        readonly property var slot: window.slots[index] || { offset: 0, size: window.geo.icon }
                        iconSize: slot.size
                        across: window.geo.across
                        keyFocus: window.keyboard && window.keyIndex === index
                        dragging: DockService.dragKey === modelData.key && window.dragging
                        x: window.vertical ? window.geo.body.x + (window.edge === "left" ? Metrics.dockPadding : window.geo.across - Metrics.dockPadding - slot.size)
                                           : window.geo.body.x + slot.offset
                        y: window.vertical ? window.geo.body.y + slot.offset
                                           : window.geo.body.y + window.geo.across - Metrics.dockPadding - slot.size
                        width: slot.size
                        height: slot.size
                        z: dragging ? 1 : 0
                        onActivated: DockService.activate(modelData.key)
                        onNewWindow: DockService.newWindow(modelData.key)
                        onMenuWanted: window.openMenu(index)
                        onDragStarted: {
                            DockService.dragKey = modelData.key
                            DockService.dragScreen = window.screenName
                        }
                        onDragMoved: along => window.dragTo(index, along)
                        onDragEnded: (along, acrossOut) => window.dragEnd(index, along, acrossOut)
                        onHoveredChanged: if (hovered) window.labelFor(index); else window.labelFor(-1)
                    }
                }
            }

            DockLabel {
                id: label
                edge: window.edge
                anchorRect: window.labelIndex >= 0 && window.slots[window.labelIndex] ? window.itemRect(window.labelIndex) : null
                text: window.notice.length ? window.notice
                    : window.labelIndex >= 0 && window.apps[window.labelIndex] ? window.apps[window.labelIndex].name : ""
                shown: (window.labelShown || window.notice.length > 0) && window.contentShown && !window.dragging
            }
        }

        // ---- the name over an icon ------------------------------------------------
        property int labelIndex: -1
        property bool labelShown: false
        function labelFor(index) {
            if (index < 0) {
                labelTimer.stop()
                labelShown = false
                return
            }
            labelIndex = index
            // Once one is up, the next shows at once as the pointer moves on.
            if (labelShown) return
            labelTimer.restart()
        }
        Timer { id: labelTimer; interval: Animations.dockLabelDelay; onTriggered: window.labelShown = true }
        // A word of the dock's own in the label's place (a drop it refused).
        property string notice: ""
        Timer { id: noticeTimer; interval: Metrics.osdTimeout; onTriggered: window.notice = "" }
        function itemRect(index) {
            const slot = slots[index]
            return vertical
                ? { x: geo.body.x, y: geo.body.y + slot.offset, width: geo.across, height: slot.size }
                : { x: geo.body.x + slot.offset, y: geo.body.y + geo.across - Metrics.dockPadding - slot.size, width: slot.size, height: slot.size }
        }

        // ---- menu, keys, drag ------------------------------------------------------
        function openMenu(index) {
            const app = apps[index]
            if (!app) return
            const rect = itemRect(index)
            DockService.openMenu(app.key, screenName, { x: origin.x + rect.x, y: origin.y + rect.y, width: rect.width, height: rect.height })
        }

        property int keyIndex: 0
        onKeyboardChanged: if (keyboard) {
            const active = apps.findIndex(app => app.active)
            keyIndex = Math.max(0, active)
            keys.forceActiveFocus()
        }
        function key(event) {
            const back = vertical ? Qt.Key_Up : Qt.Key_Left
            const on = vertical ? Qt.Key_Down : Qt.Key_Right
            const app = apps[keyIndex]
            event.accepted = true
            if (event.key === back) keyIndex = Math.max(0, keyIndex - 1)
            else if (event.key === on) keyIndex = Math.min(apps.length - 1, keyIndex + 1)
            else if (event.key === Qt.Key_Home) keyIndex = 0
            else if (event.key === Qt.Key_End) keyIndex = Math.max(0, apps.length - 1)
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && app)
                (event.modifiers & Qt.ShiftModifier) ? DockService.newWindow(app.key) : DockService.activate(app.key)
            else if ((event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) && app)
                openMenu(keyIndex)
            else if (event.key === Qt.Key_Escape) DockService.endKeyboard(screenName)
            else event.accepted = false
        }

        // Where a dragged pin would land: a slot among the pins without it.
        property int dropSlot: -1
        property real dropAt: 0
        function pinSlots(skip) {
            const result = []
            for (let index = 0; index < apps.length; ++index)
                if (apps[index].pinned && index !== skip) result.push([slots[index].offset, slots[index].size])
            return result
        }
        function dragTo(index, along) {
            const at = (vertical ? itemRect(index).y : itemRect(index).x) + along - (vertical ? geo.body.y : geo.body.x)
            const pins = pinSlots(index)
            dropSlot = Logic.slotAt(at, pins)
            dropAt = dropSlot < pins.length ? pins[dropSlot][0] - Metrics.dockGap / 2
                : pins.length ? pins[pins.length - 1][0] + pins[pins.length - 1][1] + Metrics.dockGap / 2 : Metrics.dockPadding
        }
        function dragEnd(index, along, acrossOut) {
            const app = apps[index]
            // Dropped off the dock: nothing happens.
            if (app && dropSlot >= 0 && acrossOut < geo.across) {
                const result = DockService.drop(app.key, dropSlot)
                if (result === "full") {
                    labelIndex = index
                    notice = "At most 10 pinned apps"
                    noticeTimer.restart()
                }
            }
            dropSlot = -1
            DockService.dragKey = ""
            DockService.dragScreen = ""
        }
    }
}
