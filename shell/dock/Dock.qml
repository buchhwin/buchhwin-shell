import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.bar
import "../../services/dock/DockLogic.js" as Logic
import "../../services/bar/BarLogic.js" as BarLogic
import "../../services/model/KeyedLogic.js" as Keyed

// The dock: a second bar of its own, next to the notch, the bar and the
// widgets, in any desktop mode, and off until Settings > Dock or
// Super+Shift+D switch it on. Its zones hold pills like the bar's
// (LayoutService.dockLayout): the apps (shell/widgets/AppsWidget.qml), a
// start button, and any widget the bar can carry; the layout editor edits
// them (Super+Alt+E, "Dock"). Presets: a taskbar along the whole edge, and
// the dock as it began (config/dock-presets/).
//
// One surface per screen, anchored along its whole edge and as thick as the
// settings make it - never as long or as thick as its content, so it never
// changes size while mapped (testing.md pitfall 57). The body is drawn in it
// - as long as its content ("fit") or along the whole edge ("full") - and the
// input mask is the body: the rest is transparent and takes no input.
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
        readonly property bool full: DockService.span === "full"
        readonly property bool editing: LayoutService.editMode && LayoutService.editTarget === "dock"

        readonly property bool fullscreenOn: HyprlandService.fullscreenOn(modelData)
        readonly property bool mapped: DockService.enabled
        readonly property bool active: mapped && !fullscreenOn
        // A fullscreen window ends the keyboard on it: a grab armed under it
        // took the keys the moment the fullscreen ended.
        onFullscreenOnChanged: if (fullscreenOn) DockService.endKeyboard(screenName)
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
        // A side dock runs down from below whatever reserves the top - a bar,
        // the notch's own zone (notch.reserve), anything else - so its top is
        // read off the surface the compositor gave it: the screen less the
        // surface's length less what is under it. Worked out from the bar
        // alone it was the notch's zone too high in notch mode.
        readonly property real surfaceTop: vertical && window.height > 0 && modelData
            ? Math.max(0, modelData.height - window.height - barOn("bottom")) : barOn("top")
        readonly property var offsets: ({ left: barOn("left"), right: barOn("right"), top: surfaceTop, bottom: barOn("bottom") })

        // ---- thickness ------------------------------------------------------------
        // The body: the icon size and a padding on each side. The surface: the
        // margin to the edge, the body, and the room beyond it for the apps'
        // names and their magnification - fixed by the settings alone. A name
        // stands above an icon on a bottom dock and beside it on a side one,
        // where the room is a whole label wide (the rest of the surface is
        // transparent and the input mask keeps the pointer to the body).
        readonly property real across: DockService.iconSize + Metrics.dockPadding * 2
        readonly property real headroom: (vertical ? Metrics.dockLabelMaxWidth : Metrics.dockLabelHeight) + Metrics.dockLabelGap
            + (DockService.magnifies ? Math.ceil(DockService.iconSize * (Metrics.dockMagnifyScale - 1)) : 0)
        readonly property real thickness: DockService.margin + across + headroom
        // Widgets on the dock are drawn a little larger than on the bar, in
        // proportion to the dock's thickness, within a ceiling.
        readonly property real widgetScale: Math.max(1, Math.min(Metrics.dockWidgetScaleMax,
                                                                 across / Metrics.pillHeight * Metrics.dockWidgetFill))
        // The room the windows leave: the body and a margin on each side of
        // it, less the gap Hyprland puts back (NotchLogic.reserveHeight).
        readonly property real zone: DockService.reserves ? Math.max(0, DockService.margin * 2 + across - Metrics.windowGap) : 0
        // The surface's length along its edge (the window is anchored along it).
        readonly property real length: vertical ? height : width

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
        implicitHeight: vertical ? 0 : thickness
        implicitWidth: vertical ? thickness : 0
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: zone
        WlrLayershell.namespace: "buchhwin-dock"
        WlrLayershell.layer: WlrLayer.Top
        // The keyboard only while the key gave it to this dock: OnDemand, with
        // a grab that a click anywhere else ends (pitfall 83, never Exclusive).
        readonly property bool keyboard: active && DockService.keyboardScreen === screenName
        WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // While the dock's own menu is open it holds the keys for the dock
        // (DockService.keysWithMenu): only one grab holds the seat, and the
        // compositor ended this one when the menu's began - which ended the
        // dock's keyboard mode with it. It steps aside, and comes back when
        // an Escape closes the menu.
        HyprlandFocusGrab {
            windows: [window]
            active: window.keyboard && !DockService.keysWithMenu
            onCleared: if (!DockService.keysWithMenu) DockService.endKeyboard(window.screenName)
        }

        onExclusiveZoneChanged: remap()
        onEdgeChanged: remap()
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
        // A bar on the dock's edge stands between it and the screen edge: the
        // bar says when the pointer rests at its outer edge (DockService.
        // edgePointer), and that counts as the dock's own strip. Leaving it on
        // the way up to the dock keeps the dock a moment, so it is still there
        // when the pointer has crossed the bar.
        readonly property bool edgeHeld: DockService.edgePointerScreen === screenName
        readonly property bool pointerHolds: (hover.hovered || edgeHeld || edgeLeave.running) && armed
        onEdgeHeldChanged: {
            if (edgeHeld) {
                edgeLeave.stop()
                if (shown) armed = true
                else revealTimer.restart()
            } else if (!hover.hovered) {
                revealTimer.stop()
                if (armed) edgeLeave.restart()
            }
        }
        Timer {
            id: edgeLeave
            interval: Animations.dockHideDelay
            onTriggered: if (!hover.hovered && !window.edgeHeld) window.armed = false
        }
        readonly property bool dragging: DockService.dragKey.length > 0 && DockService.dragScreen === screenName
        readonly property bool covered: DockService.covered(screenName)
        readonly property bool want: editing || Logic.wantRevealed({
            enabled: DockService.enabled, fullscreen: fullscreenOn, dragging: dragging,
            menuOpen: DockService.menuOpenOn(screenName) || panelFromHere, keyboard: keyboard, mode: DockService.visibility,
            pointer: pointerHolds, hotkey: DockService.hotkeyScreen === screenName, covered: covered
        })
        // A panel a widget on this dock opened (its clock's calendar, the
        // launcher from the start button) keeps the dock while it is open.
        readonly property bool panelFromHere: PanelService.active.length > 0 && PanelService.args && PanelService.args.fromDock === true
            && PanelService.screenName === screenName
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
            onTriggered: if (hover.hovered || window.edgeHeld) window.armed = true
        }
        onShownChanged: report()
        onActiveChanged: report()

        readonly property string maskKind: Logic.maskKind({ active: active, revealed: shown, reserves: DockService.reserves,
                                                             dragging: dragging })
        mask: Region { item: window.maskKind === "window" ? wholeArea : window.maskKind === "body" ? hitArea
                             : window.maskKind === "strip" ? stripArea : null }
        // The whole surface, for the input mask while an app is dragged on it.
        Item { id: wholeArea; anchors.fill: parent }

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

        // ---- the body ---------------------------------------------------------------
        // Along the edge: as long as the zones in fit, the whole edge less the
        // margins in full. Across: the margin from the edge, then the body.
        // The zones' lengths and where each starts along the body: one after
        // the other in fit, start/centre/end in full (the bar's rule: the
        // centre never under a neighbour).
        function zoneLength(zone) { return zone.visibleCount > 0 ? (vertical ? zone.implicitHeight : zone.implicitWidth) : 0 }
        readonly property var lengths: [zoneLength(leftZone), zoneLength(centerZone), zoneLength(rightZone)]
        readonly property real contentLength: Logic.zonesLength(lengths, Metrics.dockZoneGap)
        readonly property var starts: Logic.zoneStarts(lengths, full, bodyLength, Metrics.dockPadding, Metrics.dockZoneGap)
        readonly property real bodyLength: full ? Math.max(0, length - DockService.margin * 2)
            : Math.min(length - DockService.margin * 2, contentLength + Metrics.dockPadding * 2)
        readonly property real bodyStart: full ? DockService.margin : Math.round((length - bodyLength) / 2)
        readonly property real bodyAcross: edge === "bottom" ? thickness - DockService.margin - across
            : edge === "left" ? DockService.margin : thickness - DockService.margin - across
        readonly property var body: vertical
            ? { x: bodyAcross, y: bodyStart, width: across, height: bodyLength }
            : { x: bodyStart, y: bodyAcross, width: bodyLength, height: across }
        // The body at rest: magnified icons make it longer under the pointer
        // (fit), and only the input mask follows that - intellihide and the
        // panels out of the dock go by the body at rest, which does not move
        // with every move of the pointer. Its length: the zones with the apps
        // at their resting length (AppsWidget reports it).
        readonly property bool restMeasured: DockService.magnifies && !full
            && (leftZone.holdsApps || centerZone.holdsApps || rightZone.holdsApps)
        function restZoneLength(zone) { return zone.holdsApps ? zone.lengthBesideApps + (DockService.appsRestOn[screenName] || 0) : zoneLength(zone) }
        readonly property real restLength: !restMeasured ? bodyLength
            : Math.min(length - DockService.margin * 2, Logic.zonesLength([restZoneLength(leftZone), restZoneLength(centerZone),
                                                                          restZoneLength(rightZone)], Metrics.dockZoneGap) + Metrics.dockPadding * 2)
        readonly property real restStart: restMeasured ? Math.round((length - restLength) / 2) : bodyStart
        readonly property var restBody: vertical
            ? { x: bodyAcross, y: restStart, width: across, height: restLength }
            : { x: restStart, y: bodyAcross, width: restLength, height: across }

        // The room the apps have along the body, measured without them
        // (DockLogic.appsRoom): the apps widget fits its icons into it, so a
        // long row of apps gets smaller icons rather than running off the
        // body, or under the zone beside it.
        function zoneRoom(zone) {
            return zone.holdsApps ? { apps: true, beside: zone.lengthBesideApps } : { apps: false, length: zoneLength(zone) }
        }
        readonly property real appsRoom: Logic.appsRoom(Math.max(0, length - DockService.margin * 2), Metrics.dockPadding,
                                                        Metrics.dockZoneGap, [zoneRoom(leftZone), zoneRoom(centerZone), zoneRoom(rightZone)])
        onAppsRoomChanged: DockService.reportAppsRoom(screenName, appsRoom)

        // ---- what the service hears -----------------------------------------------
        // Where this surface's top-left corner is on its screen.
        readonly property point origin: edge === "bottom"
            ? Qt.point(offsets.left, (modelData ? modelData.height : 0) - offsets.bottom - thickness)
            : edge === "right" ? Qt.point((modelData ? modelData.width : 0) - offsets.right - thickness, offsets.top)
            : Qt.point(offsets.left, offsets.top)
        function screenRect() {
            return modelData ? { x: modelData.x, y: modelData.y, width: modelData.width, height: modelData.height } : null
        }
        // Where the screen is among the others: a screen that moves without
        // changing size (monitors.json applied after the start, a layout
        // changed in Settings > Displays) moves the dock's global body with
        // it, and nothing else here would hear of it.
        readonly property rect screenPlace: modelData ? Qt.rect(modelData.x, modelData.y, modelData.width, modelData.height) : Qt.rect(0, 0, 0, 0)
        function report() {
            reportPlace()
            DockService.reportShown(screenName, active && shown)
            DockService.reportReach(screenName, DockService.margin + across)
            DockService.reportOrigin(screenName, origin)
            DockService.reportAppsRoom(screenName, appsRoom)
            reportZones()
        }
        // The body at rest: global for intellihide, on the screen for the
        // panels that come out of the dock.
        function reportPlace() {
            DockService.reportBody(screenName, active ? Logic.globalRect(restBody, screenRect(), offsets, thickness, edge) : null)
            DockService.reportPlace(screenName, !active ? null
                : { x: origin.x + restBody.x, y: origin.y + restBody.y, width: restBody.width, height: restBody.height })
        }
        onRestBodyChanged: report()
        // The zones' frames only matter to the editor; magnifying moves them
        // with every move of the pointer.
        onBodyChanged: if (editing) Qt.callLater(reportZones)
        onOriginChanged: report()
        onScreenPlaceChanged: report()
        onEditingChanged: Qt.callLater(reportZones)
        Component.onDestruction: {
            DockService.forget(screenName)
            for (const key of ["left", "center", "right"]) {
                LayoutService.reportSurfaceRect(screenName, "dock-zone:" + key, null)
                LayoutService.reportSurfaceRect(screenName, "dock-row:" + key, null)
            }
        }
        // The editor draws its drop marker and zone hints on the real dock:
        // the dock's zones say where they are while it is edited (the bar's
        // `zone:`/`row:` reports, under the dock's own names).
        // Not edited, they are taken back once and then left alone: the
        // zones move with every move of the pointer while magnifying.
        property bool zonesReported: true
        function reportZones() {
            const on = editing && active
            if (!on && !zonesReported) return
            zonesReported = on
            const zones = [["left", leftZone], ["center", centerZone], ["right", rightZone]]
            const third = (vertical ? body.height : body.width) / 3
            let index = 0
            for (const [key, zone] of zones) {
                LayoutService.reportSurfaceRect(screenName, "dock-zone:" + key, !on ? null : vertical
                    ? { x: origin.x + body.x, y: origin.y + body.y + third * index, width: across, height: third }
                    : { x: origin.x + body.x + third * index, y: origin.y + body.y, width: third, height: across })
                const at = zone.mapToItem(content, 0, 0)
                LayoutService.reportSurfaceRect(screenName, "dock-row:" + key, !on ? null
                    : { x: origin.x + at.x, y: origin.y + at.y,
                        width: Math.max(zone.width, 1), height: Math.max(zone.height, 1) })
                index += 1
            }
        }

        // ---- input areas ------------------------------------------------------------
        // The body, the band down to the edge, and - magnifying - the room the
        // icons grow into.
        Item {
            id: hitArea
            readonly property real grow: DockService.magnifies ? Math.ceil(DockService.iconSize * (Metrics.dockMagnifyScale - 1)) : 0
            x: window.edge === "left" ? 0 : window.edge === "right" ? window.body.x - grow : window.body.x
            y: window.vertical ? window.body.y : window.body.y - grow
            width: window.edge === "left" ? window.body.x + window.across + grow
                : window.edge === "right" ? window.thickness - window.body.x + grow : window.body.width
            height: window.vertical ? window.body.height : window.thickness - window.body.y + grow
        }
        Item {
            id: stripArea
            x: window.vertical ? (window.edge === "left" ? 0 : window.thickness - Metrics.dockEdgeStrip) : window.body.x
            y: window.vertical ? window.body.y : window.thickness - Metrics.dockEdgeStrip
            width: window.vertical ? Metrics.dockEdgeStrip : window.body.width
            height: window.vertical ? window.body.height : Metrics.dockEdgeStrip
        }
        // On the whole surface, not on an area beside the icons: the input
        // mask keeps the pointer to the dock (or its strip), and only an
        // ancestor of the icons keeps its hover while the pointer is on one -
        // an icon's own MouseArea took it from a handler beside it, and the
        // dock went away under the hand that was on it (pitfall 100).
        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered && window.shown) window.armed = true
                else if (hovered) revealTimer.restart()
                if (!hovered) {
                    revealTimer.stop()
                    window.armed = false
                }
            }
        }

        // ---- what is drawn ------------------------------------------------------------
        // What the pills map their places to: the drawn content, in the
        // window's coordinates while the dock is shown and without the slide
        // that takes it out over the edge, so a place reported while hidden
        // is where it shows.
        readonly property Item frame: content
        Item {
            id: content
            visible: window.contentShown
            opacity: window.progress
            width: window.width
            height: window.height
            // Out over the edge as it goes.
            readonly property real away: Animations.motionEnabled ? (1 - window.progress) * (DockService.margin + window.across + Metrics.dockEdgeStrip) : 0
            transform: Translate {
                x: window.edge === "left" ? -content.away : window.edge === "right" ? content.away : 0
                y: window.edge === "bottom" ? content.away : 0
            }

            // Along a whole edge without a margin a taskbar is part of the
            // edge, not something on it: square, and its line only on the
            // inner edge - a border all round ran along the screen's edges
            // too, a hairline around the bar (a Rectangle draws its border
            // over its own fill only inside, the outer pixels on what is
            // behind).
            readonly property bool flush: window.full && DockService.margin === 0
            Rectangle {
                id: bodyRect
                x: window.body.x
                y: window.body.y
                width: window.body.width
                height: window.body.height
                radius: content.flush ? 0 : Math.min(Metrics.radiusPanel, window.across / 2)
                color: Colors.panelFor("dock")
                border.width: content.flush ? 0 : Metrics.borderWidth
                border.color: Colors.dockBorder
            }
            Rectangle {
                visible: content.flush
                x: window.edge === "left" ? window.body.x + window.body.width - width : window.body.x
                y: window.body.y
                width: window.vertical ? Metrics.borderWidth : window.body.width
                height: window.vertical ? window.body.height : Metrics.borderWidth
                color: Colors.dockBorder
            }

            // The three zones, placed along the body (`starts`), centred across it.
            DockZone {
                id: leftZone
                zone: "left"; dock: window
                x: window.vertical ? window.body.x + (window.across - width) / 2 : window.body.x + window.starts[0]
                y: window.vertical ? window.body.y + window.starts[0] : window.body.y + (window.across - height) / 2
            }
            DockZone {
                id: centerZone
                zone: "center"; dock: window
                x: window.vertical ? window.body.x + (window.across - width) / 2 : window.body.x + window.starts[1]
                y: window.vertical ? window.body.y + window.starts[1] : window.body.y + (window.across - height) / 2
            }
            DockZone {
                id: rightZone
                zone: "right"; dock: window
                x: window.vertical ? window.body.x + (window.across - width) / 2 : window.body.x + window.starts[2]
                y: window.vertical ? window.body.y + window.starts[2] : window.body.y + (window.across - height) / 2
            }

            // The keys, while the key gave them to this dock.
            FocusScope {
                id: keys
                focus: window.keyboard
                Keys.onPressed: event => window.key(event)
            }
        }

        onKeyboardChanged: if (keyboard) keys.forceActiveFocus()
        // The keys walk the apps and the start button beside them
        // (DockService.keyOnStart); Enter on the button opens what its click
        // opens.
        function key(event) {
            const back = vertical ? Qt.Key_Up : Qt.Key_Left
            const on = vertical ? Qt.Key_Down : Qt.Key_Right
            const app = DockService.keyOnStart ? null : DockService.items[DockService.keyIndex]
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            event.accepted = true
            if (event.key === back) DockService.moveKey(-1)
            else if (event.key === on) DockService.moveKey(1)
            else if (event.key === Qt.Key_Home) DockService.keyHome()
            else if (event.key === Qt.Key_End) DockService.keyEnd()
            else if (enter && DockService.keyOnStart) DockService.openStart(screenName)
            else if (enter && app)
                (event.modifiers & Qt.ShiftModifier) ? DockService.newWindow(app.key) : DockService.activate(app.key)
            else if ((event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) && app)
                DockService.menuWanted()
            else if (event.key === Qt.Key_Escape) DockService.endKeyboard(screenName)
            else event.accepted = false
        }
    }
}
