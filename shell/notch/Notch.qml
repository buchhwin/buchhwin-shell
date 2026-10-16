import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notch/NotchLogic.js" as Logic

// Desktop mode "notch": a black notch at the top centre of every screen, like
// a MacBook notch, showing what its strip is given (the time, by default, and
// a recording indicator). Hovering or clicking it - as notch.hoverMode says -
// morphs the shape into a small overview (NotchOverview). The surface is
// sized for the expanded shape; input only reaches the shape, so clicks next
// to it go to the windows below. Panels opened by hotkeys appear centred
// below the collapsed notch (LayoutService.clockRect).
//
// Built only while the desktop mode shows a notch, as the pill bar is: in the
// widgets and bar modes every screen used to carry a hidden notch anyway - the
// strip and its widget loaders, the springs, the shadow and its effect, the
// timers - following workspaces, the minute and the network behind a surface
// that never mapped. Leaving notch mode destroys them (each reports its
// rectangle away on the way out) and coming back builds them again.
Variants {
    model: LayoutService.loaded && LayoutService.notchShown ? Quickshell.screens : []

    PanelWindow {
        id: window
        required property var modelData
        readonly property string screenName: modelData.name
        readonly property bool fullscreenOn: HyprlandService.fullscreenOn(modelData)
        readonly property bool hiddenForFullscreen: NotchService.fullscreen === "hide" && fullscreenOn
        readonly property bool fullscreenShown: NotchService.fullscreen === "show" && fullscreenOn
        // Mapped for as long as the mode shows a notch; drawn and taking input
        // only while no fullscreen window hides it.
        //
        // A fullscreen window used to unmap it, and Quickshell destroys a
        // hidden layer window: every fullscreen toggle, and every switch to or
        // from a workspace with a fullscreen window (a remote desktop), built
        // a new window, render thread and GL context on the way back, and the
        // reserved zone went to 0 and came back, so the app was laid out twice
        // on its way out of fullscreen. Now the surface stays and only its
        // content goes: nothing is drawn (`active` hides every visual part
        // below), the input mask is empty, and the zone stays what it is -
        // a real fullscreen window covers the whole monitor whatever is
        // reserved, and Hyprland does not draw the Top layer over one either.
        readonly property bool mapped: LayoutService.loaded && SettingsService.loaded && LayoutService.notchShown
        readonly property bool active: mapped && !hiddenForFullscreen
        // A mapped layer surface keeps its exclusive zone, so a change of
        // "Reserve space" maps the surface again.
        property bool remapping: false

        // ---- the third shape: the notch *is* the display -------------------
        // Volume, a notification or a track change, shown in the notch instead
        // of in a surface below it. It is a strip the height of the notch, only
        // wider - not a second overview, which is the thing it replaces.
        //
        // Only the screen the display was raised on takes it, and only while
        // the overview is not open: the arbitration itself is NotchDisplay.
        readonly property bool displaying: NotchService.displayKind.length > 0
            && NotchService.displayScreen === screenName && !expanded
            && NotchService.takesDisplay(NotchService.displayKind, screenName)
        readonly property var displayContent: NotchService.display ? NotchService.display.content : null
        // A notification in the notch opens up on a click (Tide-island's
        // idea): the body wraps, the notch grows to fit it and the popup's
        // timer waits until a second click closes it again.
        property bool displayOpen: false
        readonly property bool showingNotification: displaying && NotchService.displayKind === "notification"
        onShowingNotificationChanged: if (!showingNotification) closeDisplay()
        onDisplayContentChanged: if (displayOpen) closeDisplay()
        function closeDisplay() {
            displayOpen = false
            NotificationService.heldPopup = null
        }
        function toggleDisplay() {
            if (displayOpen) { closeDisplay(); return }
            displayOpen = true
            NotificationService.heldPopup = NotificationService.popups.length ? NotificationService.popups[0] : null
        }
        // ---- pages: scrolled or swiped to on the collapsed notch -----------
        // -1 the date and the next event, 0 the strip, +1 what is playing
        // (only while something is). NotchLogic.swipeSettle decides.
        property int page: 0
        property bool swiped: false
        property real swipePosition: 0
        readonly property var pages: MprisService.hasPlayer ? [-1, 0, 1] : [-1, 0]
        onPagesChanged: if (pages.indexOf(page) < 0) page = 0
        readonly property bool paging: page !== 0 && !expanded && !displaying
        readonly property var pageContent: page > 0
            ? { kind: "page", icon: MprisService.artUrl.length ? "" : (MprisService.playing ? Icons.play : Icons.pause),
                iconSource: MprisService.artUrl, title: MprisService.title, subtitle: MprisService.artist }
            : page < 0 ? Object.assign({ kind: "page", icon: "\u{f00ed}" }, window.dayPage(pageClock.date))
            : null
        function dayPage(now) {
            const next = CalendarService.remainingToday(now).find(event => !event.allDay)
            return { title: Qt.formatDate(now, "dddd, d MMMM"),
                     subtitle: next ? next.title + " \u00b7 " + CalendarService.formatRange(next) : "Nothing else today" }
        }
        SystemClock { id: pageClock; precision: SystemClock.Minutes; enabled: window.page < 0 }
        readonly property CalendarDemand calendarDemand: CalendarDemand { active: window.page < 0 }
        readonly property real pageWidth: Math.max(collapsedWidth,
            Math.min(Metrics.notchMaxExpandedWidth, pageLoader.item ? pageLoader.item.implicitWidth : collapsedWidth))
        Timer {
            id: swipeSettle
            interval: Logic.SWIPE.idleMs
            onTriggered: {
                window.page = Logic.swipeSettle(window.page, window.swipePosition, window.pages)
                window.swipePosition = 0
            }
        }

        readonly property real displayHeight: displayOpen && displayLoader.item
            ? Math.min(maxBodyHeight, displayLoader.item.implicitHeight) : NotchService.bodyHeight
        readonly property real displayWidth: Math.max(collapsedWidth,
            Math.min(Metrics.notchMaxExpandedWidth,
                     displayLoader.item ? displayLoader.item.implicitWidth : collapsedWidth))

        // A panel that came out of the notch stands in for it (Settings:
        // "Panels open: Out of the notch"), so the notch on that screen makes
        // way while it is open and comes back as the panel shrinks into it.
        readonly property bool madeWay: PanelService.overNotch && PanelService.active.length > 0
            && PanelService.screen === modelData
        property real bodyOpacity: madeWay ? 0 : 1
        Behavior on bodyOpacity {
            enabled: Animations.enabled
            NumberAnimation {
                duration: window.madeWay ? Animations.hover : Animations.popupClose
                easing.type: Animations.easing
            }
        }

        // Expansion: hover (after a short delay) or IPC; a panel opening closes it.
        property bool hoverExpanded: false
        readonly property bool wantExpanded: active && (hoverExpanded || NotchService.forcedScreens.indexOf(screenName) >= 0)
        // Shape target and content visibility, staged so the content fades in
        // after the shape grows and out before it shrinks.
        property bool expanded: false
        property bool contentShown: false

        // Measured from the strip the user arranged, never below the minimum
        // and never wider than the expanded shape.
        readonly property real collapsedWidth: Logic.collapsedWidth(strip.implicitWidth,
            NotchService.storedCollapsedWidth, Metrics.notchMinWidth, expandedWidth, NotchService.bodyPadding)
        readonly property real contentHeight: overviewLoader.item ? overviewLoader.item.implicitHeight : NotchService.bodyHeight
        // The size the overview was dragged to, bounded by the surface. The
        // height is a floor: what the grid needs always wins, or an item would
        // be cut off with no way to reach it.
        readonly property var expandedSize: Logic.expandedSize(
            NotchService.expandedWidth, NotchService.storedExpandedHeight, contentHeight,
            { minWidth: Metrics.notchMinExpandedWidth, maxWidth: Metrics.notchMaxExpandedWidth,
              maxHeight: maxBodyHeight, width: Metrics.notchExpandedWidth })
        readonly property int expandedWidth: expandedSize.width
        readonly property real overviewHeight: expandedSize.height

        // The floor is the collapsed width the body last came to rest at, not
        // the one it is heading for: with the new one a strip that grew - a
        // workspace opened, one more dot - snapped wider in a single frame
        // and only its shrinking was animated, which read as the notch
        // jumping about (measured live on 15.10.: 254 -> 302 px in one frame,
        // back over twelve). Collapsing still never springs below the strip.
        property real restingCollapsedWidth: 0
        // Later, not inside the change: the floor is part of `value`'s own
        // binding, and moving it from its change handler was a binding loop.
        function settleCollapsedWidth() {
            if (!expanded && !displaying && !paging && Math.abs(bodyWidth.value - collapsedWidth) < 0.5)
                restingCollapsedWidth = collapsedWidth
        }
        Connections {
            target: bodyWidth
            function onValueChanged() { Qt.callLater(window.settleCollapsedWidth) }
        }
        NotchValue { id: bodyWidth
                     minimum: Math.min(window.collapsedWidth, window.restingCollapsedWidth || window.collapsedWidth, to)
                     to: window.expanded ? window.expandedWidth
                         : window.displaying ? window.displayWidth
                         : window.paging ? window.pageWidth : window.collapsedWidth }
        // The body may use the whole surface but its bottom margin, so the
        // clamp and the surface can never drift apart.
        readonly property real maxBodyHeight: Metrics.notchSurfaceHeight - Metrics.spaceXl
        // The collapsed height and radius are the user's (NotchService.body*:
        // the theme's tokens unless a preset - Classic - says otherwise); the
        // expanded shape keeps the theme's own.
        NotchValue { id: bodyHeight; minimum: NotchService.bodyHeight
                     to: window.expanded ? window.overviewHeight
                         : window.displaying ? window.displayHeight : NotchService.bodyHeight }
        NotchValue { id: bodyEar; minimum: Metrics.notchEar; to: window.expanded ? Metrics.notchExpandedEar : Metrics.notchEar }
        // The collapsed corners at no more than half the body's height (the
        // height is a slider, the radius its own number; Logic.collapsedRadius
        // says why clamped and not scaled). The outline and the shadow both
        // take it from here; the pill is round at its ends anyway.
        readonly property real collapsedRadius: Logic.collapsedRadius(NotchService.drawnBodyRadius, NotchService.bodyHeight)
        NotchValue { id: bodyRadius; minimum: window.collapsedRadius; to: window.expanded ? Metrics.notchExpandedRadius : window.collapsedRadius }
        // The body's geometry, shared by the outline, the pill and the shadow.
        readonly property var bodyShape: Logic.geometry(window.width / 2,
            bodyWidth.value, bodyHeight.value, bodyEar.value, bodyRadius.value)

        screen: modelData
        visible: mapped && !remapping
        color: "transparent"
        anchors.top: true
        implicitWidth: Metrics.notchMaxExpandedWidth + Metrics.notchExpandedEar * 2 + Metrics.spaceXxl * 2
        implicitHeight: Metrics.notchSurfaceHeight
        // Setting exclusiveZone switches Quickshell to ExclusionMode.Normal, so
        // "no reserve" is a zone of 0 rather than ExclusionMode.Ignore.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: NotchService.reserve
            ? Logic.reserveHeight(NotchService.shape, NotchService.bodyHeight,
                                  Metrics.notchPillMargin, Metrics.windowGap) : 0
        WlrLayershell.namespace: "buchhwin-notch"
        // Hyprland hides the Top layer under fullscreen windows; "Always show"
        // moves the notch to the Overlay layer while one is fullscreen.
        WlrLayershell.layer: fullscreenShown ? WlrLayer.Overlay : WlrLayer.Top

        // Nothing at all while hidden for a fullscreen window: an empty region
        // passes every click through to the window, whatever the compositor
        // does with the layer under it.
        mask: Region { item: window.active ? maskArea : null }

        onWantExpandedChanged: {
            if (wantExpanded) {
                collapseTimer.stop()
                expanded = true
                contentTimer.restart()
            } else {
                contentTimer.stop()
                contentShown = false
                collapseTimer.restart()
            }
        }

        onActiveChanged: {
            if (!active) {
                hoverExpanded = false
                openTimer.stop()
                closeTimer.stop()
            }
            reportPlace()
        }
        onCollapsedWidthChanged: reportPlace()
        onShapeTopChanged: reportPlace()
        Component.onCompleted: {
            restingCollapsedWidth = collapsedWidth
            reportPlace()
        }
        // The screen's width is the other half of the sum, and it is the half
        // that arrives late. The notch is ready as soon as three FileViews
        // have loaded - a frame or two - while the saved display scaling takes
        // a file read, a `hyprctl monitors` process and a round trip to the
        // compositor (DisplayService). Until then Hyprland's `auto` scaling is
        // in force and the logical width is a different number, so a report
        // made at startup and never revisited describes a screen that no
        // longer exists. `collapsedWidth` will not save it either: it only
        // changes when the clock text changes width, and 14:32 to 14:33 does
        // not, so the stale value survives for hours.
        //
        // That is the whole of "after a reboot the notch outline sits too far
        // left": the editor draws the outline from this report while the notch
        // itself is centred by the compositor and stays right. A reload finds
        // the scaling already applied, which is why only a cold boot shows it.
        Connections {
            target: window.modelData
            function onWidthChanged() { window.reportPlace() }
        }
        Component.onDestruction: {
            LayoutService.reportNotchRect(screenName, null)
            NotchService.forget(screenName)
        }

        // The notch surface is only as wide as the notch, and it is centred by
        // the compositor, so a rectangle mapped to the window is not where the
        // editor - which covers the whole screen - would draw it. Everything
        // the notch reports is offset by this.
        readonly property point reportOrigin: Qt.point(Math.round((modelData.width - width) / 2), 0)

        // The collapsed shape is what panels and notification popups align to,
        // so they do not move while the notch expands.
        //
        // A screen whose width is not known yet gets no rectangle at all. The
        // same lesson as OriginLogic.under, applied to the producer instead of
        // its consumers: a width of zero centres on the left-hand edge, and an
        // answer that is merely wrong is worse than no answer, because every
        // consumer already knows what to do with null and none of them can
        // tell a wrong rectangle from a right one.
        function reportPlace() {
            const screenWidth = modelData ? modelData.width : 0
            LayoutService.reportNotchRect(screenName, active && screenWidth > 0
                ? { x: Math.round((screenWidth - collapsedWidth) / 2), y: shapeTop,
                    width: Math.round(collapsedWidth), height: NotchService.bodyHeight }
                : null)
        }

        readonly property var reportState: ({
            shown: active, expanded: expanded, content: contentShown,
            rows: overviewLoader.item ? overviewLoader.item.rows : [],
            width: Math.round(bodyWidth.to), height: Math.round(bodyHeight.to),
            // The surface's own width and where it starts on the screen. A
            // rectangle the notch reports is in *its* coordinates, so these
            // two are what turn one into a place on the desktop - and a frame
            // in the wrong place is a wrong one of these, not a wrong
            // rectangle.
            surfaceWidth: Math.round(window.width),
            reportX: Math.round(reportOrigin.x)
        })
        // A turn later, not inside the change: the report rewrites
        // `NotchService.states`, `displaying` reads it back and the body's
        // `to` reads `displaying`, so a synchronous report closed the loop
        // that logged "Binding loop detected for property reportState"
        // (and "displaying", "display", "to"; one per start). A Timer and
        // not Qt.callLater: callLater folds calls of the same function, and
        // every screen's notch would share one report.
        onReportStateChanged: reportTimer.restart()
        Timer {
            id: reportTimer
            interval: 0
            onTriggered: NotchService.report(window.screenName, window.reportState)
        }

        // Collapse at once, then open a panel centred below the notch.
        // `args` is what the thing that was clicked wants to say beyond which
        // panel to open - a widget's `actionArgs`, which names the page. The
        // anchor is the notch's own and wins over the widget's; `fromNotch`
        // lets a panel that belongs in the corner (`followClock: false`, the
        // notification list) keep its corner and only grow out of the notch.
        function openPanel(panelId, args) {
            hoverExpanded = false
            openTimer.stop()
            NotchService.collapse(screenName)
            PanelService.open(panelId, Object.assign({}, args || {}, { anchorX: modelData.width / 2, fromNotch: true }))
        }

        function buttonAction(action) {
            if (action === "none") return
            if (action === "playPause") { MprisService.togglePlaying(); return }
            window.openPanel(action)
        }

        function remap() {
            if (!visible) return
            remapping = true
            remapTimer.restart()
        }
        Connections {
            target: NotchService
            function onReserveChanged() { window.remap() }
            // The body height is part of the zone, so a preset that changes
            // it (Classic's 32 for Island's 34) or the Height row maps the
            // surface again too while space is reserved - and the rectangle
            // the panels align to is reported again either way.
            function onBodyHeightChanged() {
                if (NotchService.reserve) window.remap()
                window.reportPlace()
            }
        }
        Timer {
            id: remapTimer
            interval: Animations.notchHoverDelay
            onTriggered: window.remapping = false
        }

        Connections {
            target: PanelService
            function onActiveChanged() {
                if (PanelService.active.length === 0) return
                window.hoverExpanded = false
                openTimer.stop()
                if (!NotchService.arranging) NotchService.collapse(window.screenName)
            }
        }

        Timer {
            id: openTimer
            interval: NotchService.openDelay
            onTriggered: if (hover.hovered && !window.swiped && PanelService.active.length === 0) window.hoverExpanded = true
        }
        Timer {
            id: closeTimer
            interval: NotchService.closeDelay
            // Leaving undoes what the hover did, not what somebody else did.
            // The layout editor holds the notch open through `forcedScreens`,
            // and it covers the notch with its own surface - so opening the
            // editor while the notch was hovered sends a leave, and clearing
            // the forced screen here closed the very thing being arranged.
            onTriggered: if (!hover.hovered) {
                window.hoverExpanded = false
                if (!NotchService.arranging) NotchService.collapse(window.screenName)
            }
        }
        Timer {
            id: contentTimer
            interval: Animations.notchContentDelay
            onTriggered: window.contentShown = window.wantExpanded
        }
        Timer {
            id: collapseTimer
            interval: Math.round(Animations.notchContentFade * 0.6)
            onTriggered: if (!window.wantExpanded) window.expanded = false
        }

        // A shadow under the notch, so it sits on the screen instead of being
        // painted onto it. Cast from a plain rounded rectangle rather than
        // from the outline itself: the springs move every frame, and putting
        // a Shape through a layer and a blur on each of them is the cost
        // ShellPanel avoids the same way. The ears are left out - they are
        // concave cuts into the top edge, where there is nothing to fall on.
        //
        // A plain rectangle that follows the springs is still a layer and a
        // blur per frame of the morph. So, as in ShellPanel, the caster takes
        // the shape the springs are *heading for* - the same target geometry
        // the input mask is cut from, which changes twice per morph rather
        // than once per frame - and the effect is scaled and moved onto the
        // body as it springs. The scale works from the caster's top-left
        // corner, and the top edge is the one edge the two shapes share, so
        // only x needs an offset: how far the body's left edge is from the
        // target's. At rest the two shapes are the same and the picture is
        // the one drawn before. `staticShadow: false` is the way back to the
        // per-frame shadow.
        property bool staticShadow: true
        readonly property var targetShape: Logic.geometry(window.width / 2,
            bodyWidth.to, bodyHeight.to, bodyEar.to, bodyRadius.to)
        readonly property var shadowShape: staticShadow ? targetShape : bodyShape
        // The caster reaches above the top edge by the corner radius, so the
        // notch's square top corners cast nothing onto the screen; the pill
        // is detached and rounded all the way round.
        readonly property real shadowReach: NotchService.pill ? 0 : NotchService.drawnBodyRadius
        Rectangle {
            id: shadowCaster
            visible: false
            x: window.shadowShape.left
            y: window.shapeTop - window.shadowReach
            width: Math.max(0, window.shadowShape.right - window.shadowShape.left)
            height: Math.max(0, window.shadowShape.bottom + window.shadowReach)
            topLeftRadius: NotchService.pill ? window.shadowShape.radius : 0
            topRightRadius: NotchService.pill ? window.shadowShape.radius : 0
            bottomLeftRadius: window.shadowShape.radius
            bottomRightRadius: window.shadowShape.radius
            color: Colors.shadow
            layer.enabled: true
        }
        MultiEffect {
            visible: window.active
            opacity: window.bodyOpacity
            source: shadowCaster
            anchors.fill: shadowCaster
            shadowEnabled: true
            shadowColor: Colors.shadow
            blurMax: Effects.elevation2Max
            shadowBlur: Effects.elevation2Blur
            shadowOpacity: Effects.elevation2Opacity
            shadowVerticalOffset: Effects.elevation2Offset
            // Masked by the caster, inverted: only what falls outside the
            // notch is drawn, so the shape is not darkened from underneath.
            maskEnabled: true
            maskSource: shadowCaster
            maskInverted: true
            // Scale about the corner, then translate - not `scale`, which
            // works from the centre and so from the padding too (ShellPanel
            // has the whole of it): the body's rect over the caster's.
            transform: [
                Scale {
                    origin.x: 0
                    origin.y: 0
                    xScale: window.staticShadow
                        ? (window.bodyShape.right - window.bodyShape.left) / Math.max(1, shadowCaster.width) : 1
                    yScale: window.staticShadow
                        ? (window.bodyShape.bottom + window.shadowReach) / Math.max(1, shadowCaster.height) : 1
                },
                Translate { x: window.staticShadow ? window.bodyShape.left - shadowCaster.x : 0 }
            ]
        }

        // The outline as path elements instead of a PathSvg: the springs move
        // every frame and an SVG string would be built and parsed again for
        // each one. NotchLogic.geometry stays the pure, unit-tested part.
        // A pill is the same thing detached from the top edge: a rounded
        // rectangle instead of an outline with concave ears. Everything else -
        // what it carries, how it expands, where panels open - is unchanged.
        readonly property int shapeTop: Logic.pillTop(NotchService.shape, Metrics.notchPillMargin)

        Rectangle {
            opacity: window.bodyOpacity
            visible: NotchService.pill && window.active
            x: window.bodyShape.left
            y: window.shapeTop
            width: Math.max(0, window.bodyShape.right - window.bodyShape.left)
            height: Math.max(0, window.bodyShape.bottom)
            radius: Logic.pillRadius(height, NotchService.drawnBodyRadius, Metrics.notchExpandedRadius, window.expanded)
            color: Colors.notch
        }

        // The outline is built again each time the window is shown. A Shape
        // drawn by the CurveRenderer keeps its last geometry across an unmap
        // and map of the layer surface - remapped for a reserve change, and
        // until 16.10. unmapped for every fullscreen window - and paints the
        // body where it was when the window went away, until the next morph
        // changes the path. Seen as the notch coming back with its body half
        // off the left edge while the clock and the shadow, which read the
        // geometry directly, were in the right place; a hover (a morph) put
        // it right. A fullscreen window now hides the content and keeps the
        // surface, and the outline is still let go and built again with the
        // content: a Shape is cheap, a stale outline is not.
        Loader {
            opacity: window.bodyOpacity
            active: !NotchService.pill && window.visible && window.active
            anchors.fill: parent
            sourceComponent: Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    id: outline
                    readonly property var shape: window.bodyShape

                    fillColor: Colors.notch
                    strokeWidth: -1
                    strokeColor: "transparent"
                    startX: outline.shape.left - outline.shape.ear
                    startY: 0
                    // Concave ear into the top edge, down to the bottom corners.
                    PathArc {
                        x: outline.shape.left; y: outline.shape.ear
                        radiusX: outline.shape.ear; radiusY: outline.shape.ear
                        direction: PathArc.Clockwise
                    }
                    PathLine { x: outline.shape.left; y: outline.shape.bottom - outline.shape.radius }
                    PathArc {
                        x: outline.shape.left + outline.shape.radius; y: outline.shape.bottom
                        radiusX: outline.shape.radius; radiusY: outline.shape.radius
                        direction: PathArc.Counterclockwise
                    }
                    PathLine { x: outline.shape.right - outline.shape.radius; y: outline.shape.bottom }
                    PathArc {
                        x: outline.shape.right; y: outline.shape.bottom - outline.shape.radius
                        radiusX: outline.shape.radius; radiusY: outline.shape.radius
                        direction: PathArc.Counterclockwise
                    }
                    PathLine { x: outline.shape.right; y: outline.shape.ear }
                    PathArc {
                        x: outline.shape.right + outline.shape.ear; y: 0
                        radiusX: outline.shape.ear; radiusY: outline.shape.ear
                        direction: PathArc.Clockwise
                    }
                }
            }
        }

        // The input region is handed to the compositor on every change, so it
        // follows the morph target instead of the springing value: it is
        // committed twice per morph rather than once per frame, and the
        // pointer is already inside the expanded shape while it grows.
        Item {
            id: maskArea
            x: (window.width - width) / 2
            y: window.shapeTop
            width: Math.round(bodyWidth.to + bodyEar.to * 2)
            height: Math.max(1, Math.round(bodyHeight.to))
        }

        // The shape including its ears: hover and clicks. The content items
        // are children so hovering them keeps the notch open.
        Item {
            id: hitArea
            visible: window.active
            opacity: window.bodyOpacity
            x: (window.width - width) / 2
            y: window.shapeTop
            width: Math.max(bodyWidth.value + bodyEar.value * 2, maskArea.width)
            height: Math.max(1, bodyHeight.value, maskArea.height)

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (hovered) {
                        closeTimer.stop()
                        if (NotchService.expandOnHover && !window.hoverExpanded) openTimer.restart()
                    } else {
                        window.swiped = false
                        openTimer.stop()
                        closeTimer.restart()
                    }
                }
            }

            // Collapsed: a click opens the overview or the dashboard, as the
            // hover mode and the click action say (NotchLogic.clickResult).
            // The middle and the right button do what their own settings say,
            // nothing unless they are set.
            MouseArea {
                anchors.fill: parent
                enabled: !window.expanded
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton && window.showingNotification) window.toggleDisplay()
                    else if (mouse.button === Qt.LeftButton && window.paging)
                        window.openPanel(window.page > 0 ? "mediaPopup" : "dashboard")
                    else if (mouse.button === Qt.MiddleButton) window.buttonAction(NotchService.middleAction)
                    else if (mouse.button === Qt.RightButton) window.buttonAction(NotchService.rightAction)
                    else if (NotchService.clickResult === "expand") NotchService.expand(window.screenName)
                    else window.openPanel("dashboard")
                }
            }

            WheelHandler {
                enabled: NotchService.swipe && !window.expanded && !window.displaying
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    // A hand that scrolls is paging, not resting: the hover
                    // does not open the overview under it until it leaves.
                    window.swiped = true
                    openTimer.stop()
                    window.swipePosition = Math.max(-1, Math.min(1, window.swipePosition
                        + Logic.swipeStep(event.pixelDelta.x, event.pixelDelta.y, event.angleDelta.x, event.angleDelta.y)))
                    swipeSettle.restart()
                }
            }

            // A page, in the strip's place: the same row the display uses.
            Loader {
                id: pageLoader
                x: (hitArea.width - width) / 2
                width: Math.max(0, bodyWidth.value)
                height: NotchService.bodyHeight
                clip: true
                active: window.paging || opacity > 0
                opacity: window.paging ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Animations.notchContentFade; easing.type: Animations.easing } }
                sourceComponent: NotchDisplayContent {
                    anchors.horizontalCenter: parent.horizontalCenter
                    content: window.pageContent || ({})
                }
            }

            // The display, in the notch's own place. It fades over the strip
            // rather than replacing it, so the clock is still there underneath
            // and comes back without a second morph.
            Loader {
                id: displayLoader
                x: (hitArea.width - width) / 2
                width: Math.max(0, bodyWidth.value)
                height: Math.max(NotchService.bodyHeight, bodyHeight.value)
                clip: true
                active: window.displaying || opacity > 0
                opacity: window.displaying ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Animations.notchContentFade; easing.type: Animations.easing } }
                sourceComponent: NotchDisplayContent {
                    anchors.horizontalCenter: parent.horizontalCenter
                    content: window.displayContent || ({})
                    open: window.displayOpen
                }
            }

            // Collapsed content: the strip the user arranged - the time by
            // default, and while recording a red dot with the elapsed time
            // leading it (a click stops the recording).
            Item {
                id: collapsedContent
                x: (hitArea.width - width) / 2
                width: window.collapsedWidth
                height: NotchService.bodyHeight
                opacity: window.expanded || window.displaying || window.paging ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }

                NotchStrip {
                    id: strip
                    anchors.centerIn: parent
                    // While the notch is expanded the overview carries the
                    // strip and this one is not on screen. Both would report
                    // under the same keys, and this one - restarted by every
                    // frame of the morph - would win and report nothing.
                    screenName: window.expanded ? "" : window.screenName
                    // No screen under a fullscreen window: the dock draws
                    // nothing there (Dock.qml), so a notch that stays over it
                    // (notch.fullscreen "show") keeps the time it would
                    // otherwise leave to the taskbar.
                    ownerScreen: window.fullscreenOn ? "" : window.screenName
                    reportOrigin: window.reportOrigin
                }
            }

            // Expanded content, clipped to the body while it grows.
            Item {
                x: (hitArea.width - width) / 2
                width: Math.max(0, bodyWidth.value)
                height: Math.max(0, bodyHeight.value)
                clip: true

                Loader {
                    id: overviewLoader
                    x: (parent.width - window.expandedWidth) / 2
                    width: window.expandedWidth
                    active: window.expanded || opacity > 0
                    opacity: window.contentShown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Animations.notchContentFade; easing.type: Animations.easing } }
                    sourceComponent: NotchOverview { notch: window }
                }
            }
        }
    }
}
