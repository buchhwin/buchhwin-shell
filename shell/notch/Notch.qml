import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.theme
import qs.services
import "../../services/notch/NotchLogic.js" as Logic

// Desktop mode "notch": a black notch at the top centre of every screen, like
// a MacBook notch, showing only the time (and a recording indicator). Hovering
// it morphs the shape into a small overview (NotchOverview). The surface is
// sized for the expanded shape; input only reaches the shape, so clicks next
// to it go to the windows below. Panels opened by hotkeys appear centred
// below the collapsed notch (LayoutService.clockRect).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData
        readonly property string screenName: modelData.name
        readonly property bool fullscreenOn: HyprlandService.fullscreenOn(modelData)
        readonly property bool hiddenForFullscreen: NotchService.fullscreen === "hide" && fullscreenOn
        readonly property bool fullscreenShown: NotchService.fullscreen === "show" && fullscreenOn
        readonly property bool active: LayoutService.loaded && SettingsService.loaded && LayoutService.notchShown && !hiddenForFullscreen
        // A mapped layer surface keeps its exclusive zone, so a change of
        // "Reserve space" maps the surface again.
        property bool remapping: false

        // Expansion: hover (after a short delay) or IPC; a panel opening closes it.
        property bool hoverExpanded: false
        readonly property bool wantExpanded: active && (hoverExpanded || NotchService.forcedScreen === screenName)
        // Shape target and content visibility, staged so the content fades in
        // after the shape grows and out before it shrinks.
        property bool expanded: false
        property bool contentShown: false

        // Measured from the strip the user arranged, never below the minimum
        // and never wider than the expanded shape.
        readonly property real collapsedWidth: Logic.collapsedWidth(strip.implicitWidth,
            NotchService.storedCollapsedWidth, Metrics.notchMinWidth, expandedWidth, Metrics.notchPadding)
        readonly property real contentHeight: overviewLoader.item ? overviewLoader.item.implicitHeight : Metrics.notchHeight
        // The size the overview was dragged to, bounded by the surface. The
        // height is a floor: what the grid needs always wins, or an item would
        // be cut off with no way to reach it.
        readonly property var expandedSize: Logic.expandedSize(
            NotchService.expandedWidth, NotchService.storedExpandedHeight, contentHeight,
            { minWidth: Metrics.notchMinExpandedWidth, maxWidth: Metrics.notchMaxExpandedWidth,
              maxHeight: maxBodyHeight, width: Metrics.notchExpandedWidth })
        readonly property int expandedWidth: expandedSize.width
        readonly property real overviewHeight: expandedSize.height

        NotchValue { id: bodyWidth; minimum: Math.min(window.collapsedWidth, to); to: window.expanded ? window.expandedWidth : window.collapsedWidth }
        // The body may use the whole surface but its bottom margin, so the
        // clamp and the surface can never drift apart.
        readonly property real maxBodyHeight: Metrics.notchSurfaceHeight - Metrics.spaceXl
        NotchValue { id: bodyHeight; minimum: Metrics.notchHeight; to: window.expanded ? window.overviewHeight : Metrics.notchHeight }
        NotchValue { id: bodyEar; minimum: Metrics.notchEar; to: window.expanded ? Metrics.notchExpandedEar : Metrics.notchEar }
        NotchValue { id: bodyRadius; minimum: Metrics.notchRadius; to: window.expanded ? Metrics.notchExpandedRadius : Metrics.notchRadius }

        screen: modelData
        visible: active && !remapping
        color: "transparent"
        anchors.top: true
        implicitWidth: Metrics.notchMaxExpandedWidth + Metrics.notchExpandedEar * 2 + Metrics.spaceXxl * 2
        implicitHeight: Metrics.notchSurfaceHeight
        // Setting exclusiveZone switches Quickshell to ExclusionMode.Normal, so
        // "no reserve" is a zone of 0 rather than ExclusionMode.Ignore.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: NotchService.reserve
            ? Logic.reserveHeight(NotchService.shape, Metrics.notchHeight,
                                  Metrics.notchPillMargin, Metrics.windowGap) : 0
        WlrLayershell.namespace: "buchhwin-notch"
        // Hyprland hides the Top layer under fullscreen windows; "Always show"
        // moves the notch to the Overlay layer while one is fullscreen.
        WlrLayershell.layer: fullscreenShown ? WlrLayer.Overlay : WlrLayer.Top

        mask: Region { item: maskArea }

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
        Component.onCompleted: reportPlace()
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
                    width: Math.round(collapsedWidth), height: Metrics.notchHeight }
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
        onReportStateChanged: NotchService.report(screenName, reportState)

        // Collapse at once, then open a panel centred below the notch.
        // `args` is what the thing that was clicked wants to say beyond which
        // panel to open - a widget's `actionArgs`, which names the page. The
        // anchor is the notch's own and always wins.
        function openPanel(panelId, args) {
            hoverExpanded = false
            openTimer.stop()
            if (NotchService.forcedScreen === screenName) NotchService.collapse()
            PanelService.open(panelId, Object.assign({}, args || {}, { anchorX: modelData.width / 2 }))
        }

        Connections {
            target: NotchService
            function onReserveChanged() {
                if (!window.visible) return
                window.remapping = true
                remapTimer.restart()
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
                if (!NotchService.arranging && NotchService.forcedScreen === window.screenName)
                    NotchService.collapse()
            }
        }

        Timer {
            id: openTimer
            interval: Animations.notchHoverDelay
            onTriggered: if (hover.hovered && PanelService.active.length === 0) window.hoverExpanded = true
        }
        Timer {
            id: closeTimer
            interval: Animations.notchLeaveDelay
            // Leaving undoes what the hover did, not what somebody else did.
            // The layout editor holds the notch open through `forcedScreen`,
            // and it covers the notch with its own surface - so opening the
            // editor while the notch was hovered sends a leave, and clearing
            // `forcedScreen` here closed the very thing being arranged.
            onTriggered: if (!hover.hovered) {
                window.hoverExpanded = false
                if (!NotchService.arranging && NotchService.forcedScreen === window.screenName)
                    NotchService.collapse()
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
        Rectangle {
            id: shadowCaster
            visible: false
            x: outline.shape.left
            y: window.shapeTop - (NotchService.pill ? 0 : Metrics.notchRadius)
            width: Math.max(0, outline.shape.right - outline.shape.left)
            height: Math.max(0, outline.shape.bottom + (NotchService.pill ? 0 : Metrics.notchRadius))
            topLeftRadius: NotchService.pill ? outline.shape.radius : 0
            topRightRadius: NotchService.pill ? outline.shape.radius : 0
            bottomLeftRadius: outline.shape.radius
            bottomRightRadius: outline.shape.radius
            color: Colors.shadow
            layer.enabled: true
        }
        MultiEffect {
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
        }

        // The outline as path elements instead of a PathSvg: the springs move
        // every frame and an SVG string would be built and parsed again for
        // each one. NotchLogic.geometry stays the pure, unit-tested part.
        // A pill is the same thing detached from the top edge: a rounded
        // rectangle instead of an outline with concave ears. Everything else -
        // what it carries, how it expands, where panels open - is unchanged.
        readonly property int shapeTop: Logic.pillTop(NotchService.shape, Metrics.notchPillMargin)

        Rectangle {
            visible: NotchService.pill
            x: outline.shape.left
            y: window.shapeTop
            width: Math.max(0, outline.shape.right - outline.shape.left)
            height: Math.max(0, outline.shape.bottom)
            radius: Logic.pillRadius(height, Metrics.notchRadius, Metrics.notchExpandedRadius, window.expanded)
            color: Colors.notch
        }

        Shape {
            visible: !NotchService.pill
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: outline
                readonly property var shape: Logic.geometry(window.width / 2,
                    bodyWidth.value, bodyHeight.value, bodyEar.value, bodyRadius.value)

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
                        openTimer.stop()
                        closeTimer.restart()
                    }
                }
            }

            // Collapsed: a click expands (hover off) or opens the dashboard.
            MouseArea {
                anchors.fill: parent
                enabled: !window.expanded
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotchService.expandOnHover) window.openPanel("dashboard")
                    else NotchService.expand(window.screenName)
                }
            }

            // Collapsed content: the strip the user arranged - the time by
            // default, and while recording a red dot with the elapsed time
            // leading it (a click stops the recording).
            Item {
                id: collapsedContent
                x: (hitArea.width - width) / 2
                width: window.collapsedWidth
                height: Metrics.notchHeight
                opacity: window.expanded ? 0 : 1
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
