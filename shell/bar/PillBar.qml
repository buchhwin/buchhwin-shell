import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services
import "../../services/bar/BarLogic.js" as BarLogic

// Desktop mode "pills": a bar on one edge of every screen with start, centre
// and end zones (layout.json, per profile). Style "pills" draws floating
// capsules and only accepts input on them; style "bar" draws one continuous
// bar (floating or attached to its edge) that accepts input on its whole
// area, so clicks on empty parts do not reach the windows below. It can
// reserve space for windows and hides on fullscreen unless configured to stay.
//
// Top and bottom make it horizontal, left and right vertical. Everything that
// differs between the two is a `vertical` test here; the arithmetic itself is
// in BarLogic, written in the bar's own directions rather than in x and y.
Variants {
    // Which screens the bar appears on. It used to be every one, with no way
    // to say otherwise - widgets could be placed per monitor from the layout
    // editor, the bar could not, so a portrait screen beside two landscape
    // ones got the same strip whether it was wanted there or not.
    //
    // An empty list means every screen, which is what a bar always did, so
    // nothing changes for a configuration written before this and a monitor
    // plugged in later is included rather than left bare.
    model: {
        const wanted = LayoutService.bar.screens || []
        if (!wanted.length) return Quickshell.screens
        const shown = Quickshell.screens.filter(screen => wanted.indexOf(screen.name) >= 0)
        // Never all of them off: a list that matches nothing on this machine
        // (an old name, a monitor left behind) would leave no bar and no way
        // back to one except the settings file.
        return shown.length ? shown : Quickshell.screens
    }

    PanelWindow {
        id: window
        required property var modelData
        readonly property var bar: LayoutService.bar
        readonly property real scaleFactor: bar.scale
        readonly property real pillHeight: Metrics.pillHeight * scaleFactor
        readonly property bool flat: bar.style === "bar"
        readonly property bool fullscreenOn: HyprlandService.fullscreenOn(modelData)
        readonly property bool hiddenForFullscreen: bar.fullscreen === "hide" && fullscreenOn
        readonly property bool fullscreenShown: bar.fullscreen === "show" && fullscreenOn
        readonly property bool active: LayoutService.loaded && LayoutService.barShown && !hiddenForFullscreen
        readonly property real barRadius: Metrics.barRadius * scaleFactor
        readonly property bool attached: flat && bar.position === "attached"
        readonly property string edge: BarLogic.edge(bar.edge)
        readonly property bool vertical: BarLogic.vertical(edge)
        // The edge away from the origin: the bottom or the right. It is the
        // one thing that mirrors rather than simply turning.
        readonly property bool atFar: BarLogic.farEdge(edge)
        // How long the bar is, and how thick. The surface is the whole edge,
        // so one of these is the screen's dimension and the other is what the
        // geometry asked for.
        //
        // The length is read from the *screen* and not from this window. They
        // are the same number - the bar is anchored along its whole edge - but
        // taking it from the window put `geometry` in a circle with the
        // implicit size that `geometry` decides, and Qt says so on every
        // start: "Binding loop detected for property barLength".
        readonly property real barLength: modelData ? (vertical ? modelData.height : modelData.width) : 0
        readonly property real barThickness: vertical ? width : height
        // How thick the bar is: a pill, plus - on a vertical bar only - a
        // small padding on each side. A horizontal bar needs none, because its
        // widgets run along it. A vertical one reads a stacked value across
        // its thickness, and "50%" is a pill wide to the pixel.
        //
        // The padding is a number of its own because it is an *across* one.
        // This used to borrow `zoneInset`, which is the inset *along* the bar
        // and is already spent by the zones below - so an attached bar came
        // out 48 px for no reason - and nothing centred the pills in the room
        // that made, so every pixel of it piled up against the screen edge.
        // That is what a right-hand bar looked wrong for: the same 6 px read
        // either as a bar too wide or as icons off centre, and it was both.
        //
        // What it does not do is grow to fit. That was tried and taken back:
        // it cost a tenth of the screen. The widgets stack instead.
        readonly property real barSpan: BarLogic.barThickness(edge, pillHeight,
            Metrics.verticalBarPadding * scaleFactor)
        readonly property var geometry: BarLogic.geometry(bar.style, bar.position, edge, barLength, {
            height: barSpan, margin: Metrics.barMargin, radius: barRadius, border: Metrics.borderWidth
        }, bar.reserve)
        readonly property real zoneInset: BarLogic.zoneInset(bar.style, bar.position,
            Metrics.barHighlightInset * scaleFactor, Metrics.barSidePadding * scaleFactor)
        readonly property real zoneGap: (flat ? Metrics.barGroupGap : Metrics.pillGap) * scaleFactor
        // A mapped layer surface keeps its exclusive zone, so a change of the
        // zone (reserve, style, position, size) maps the surface again.
        property bool remapping: false
        // While recording the screen a stop pill appears at the right unless
        // the user placed the recording item in a pill already.
        readonly property bool hasRecordingPill: ["left", "center", "right"].some(zone =>
            bar[zone].some(pill => pill.items.some(item => item.type === "recording")))
        readonly property var recordingPill: ({ id: "recording-auto", items: [{ type: "recording", display: "full", options: {} }] })

        screen: modelData
        visible: active && !remapping
        color: "transparent"
        // Anchored to its own edge for the whole life of the surface. A
        // mapped layer surface does not reliably take a new anchor, which is
        // why a change of `edge` maps it again below rather than just moving.
        //
        // A vertical bar spans the height and hangs from one side; a
        // horizontal one spans the width and hangs from the top or bottom.
        // Either way it is anchored along its whole edge, and only the
        // thickness is an implicit size.
        anchors {
            top: vertical || !atFar
            bottom: vertical || atFar
            left: !vertical || !atFar
            right: !vertical || atFar
        }
        implicitHeight: vertical ? 0 : geometry.thickness
        implicitWidth: vertical ? geometry.thickness : 0
        // Setting exclusiveZone switches Quickshell to ExclusionMode.Normal, so
        // "no reserve" is a zone of 0 rather than ExclusionMode.Ignore.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: geometry.exclusiveZone
        WlrLayershell.namespace: "buchhwin-bar"
        // Hyprland hides the Top layer under fullscreen windows; "Always show"
        // moves the bar to the Overlay layer while one is fullscreen.
        WlrLayershell.layer: fullscreenShown ? WlrLayer.Overlay : WlrLayer.Top

        // The bar takes input on the bar itself, never on the corners hanging
        // under it: those are decoration over the windows.
        Item {
            id: barArea
            // The bar itself, wherever its edge is. That is the content rect,
            // on every edge and in both positions: an attached bar's content
            // already runs the whole length of the screen, and the concave
            // corners hanging past it are decoration over the windows, not
            // part of the bar. This used to be built from the *background*
            // rect, which reaches two border widths further out so the borders
            // draw - so the input mask sat two pixels off the bar it masks.
            readonly property var box: window.geometry.content
            x: box ? box.x : 0
            y: box ? box.y : 0
            width: box ? box.width : 0
            height: box ? box.height : 0
        }

        mask: Region {
            Region { item: window.flat ? barArea : null }
            Region { item: window.flat ? null : leftZone }
            Region { item: window.flat ? null : centerZone }
            Region { item: window.flat ? null : rightZone }
        }

        // How far into the screen the bar reaches, and from which edge. The
        // pair travels together: a panel that only knew the number used to
        // assume it came from the top, which was true for as long as that was
        // the only edge there was.
        function reportInset() {
            LayoutService.reportBarInset(modelData.name, active ? geometry.inset : -1, edge)
        }
        onActiveChanged: reportInset()
        onGeometryChanged: reportInset()
        Component.onCompleted: reportInset()
        Component.onDestruction: LayoutService.reportBarInset(modelData.name, -1, edge)

        // Everything this bar reports is mapped to its own window, and the
        // window is only as thick as the bar - so on a bottom or a right bar
        // it is not where the editor, which covers the whole screen, would
        // draw it, nor where an OSD or a panel growing out of a widget
        // belongs. `BarLogic.surfaceOrigin` is that correction; the notch has
        // carried its own since the day it was built.
        readonly property var reportOrigin: BarLogic.surfaceOrigin(edge, geometry.thickness,
            modelData ? modelData.width : 0, modelData ? modelData.height : 0)

        // Where a zone sits *across* the bar: centred in the content rect.
        // With the bar exactly a pill thick there is nothing to centre, and
        // that is the point - the three zones used to be pinned to the start
        // of the content rect, so every pixel the bar was thicker than its
        // pills piled up on one side. Any slack that ever comes back lands on
        // both sides instead of against the screen edge.
        function zoneAcross(size) {
            const content = geometry.content
            const start = vertical ? content.x : content.y
            const room = vertical ? content.width : content.height
            return start + Math.round(Math.max(0, room - size) / 2)
        }

        // The editor draws its drop marker and its zone hints on the real bar,
        // so the zones say where they are while it is open.
        readonly property bool editing: LayoutService.editMode && LayoutService.barShown
        // Two rectangles per zone: `zone:` is the third of the bar a pill has
        // to be dropped in, `row:` is where that zone's pills actually sit, so
        // the marker of an empty zone lands where the first pill would.
        function reportZones() {
            const zones = [["left", leftZone], ["center", centerZone], ["right", rightZone]]
            const content = geometry.content
            // Thirds along the bar, whichever way it runs.
            const third = (vertical ? content.height : content.width) / 3
            let index = 0
            for (const [key, zone] of zones) {
                if (!editing) {
                    LayoutService.reportSurfaceRect(modelData.name, "zone:" + key, null)
                    LayoutService.reportSurfaceRect(modelData.name, "row:" + key, null)
                    index += 1
                    continue
                }
                LayoutService.reportSurfaceRect(modelData.name, "zone:" + key, vertical
                    ? { x: content.x + reportOrigin.x, y: content.y + third * index + reportOrigin.y,
                        width: barSpan, height: third }
                    : { x: content.x + third * index + reportOrigin.x, y: content.y + reportOrigin.y,
                        width: third, height: barSpan })
                LayoutService.reportSurfaceRect(modelData.name, "row:" + key, vertical
                    ? { x: zone.x + reportOrigin.x, y: zone.y + reportOrigin.y,
                        width: pillHeight, height: Math.max(zone.height, 1) }
                    : { x: zone.x + reportOrigin.x, y: zone.y + reportOrigin.y,
                        width: Math.max(zone.width, 1), height: pillHeight })
                index += 1
            }
        }
        onEditingChanged: Qt.callLater(reportZones)
        onWidthChanged: Qt.callLater(reportZones)
        onHeightChanged: Qt.callLater(reportZones)

        onExclusiveZoneChanged: window.remap()
        // The anchor is the other thing a mapped surface will not take.
        onEdgeChanged: window.remap()
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

        // Separator flags for the groups of a zone (bar style only); `pills`
        // are the zone's Pill items in order (hidden ones have no content).
        function separatorsFor(pills) {
            return BarLogic.separators(pills.map(pill => pill !== null && pill.visible))
        }

        // An attached bar and the area beside it are one shape: the bar fills
        // through to its own inner edge and two concave corners hang past it
        // at the screen's sides, so what looks rounded is the space the
        // windows live in. Rounding the bar's own inner corners instead left
        // two notches with the wallpaper showing through them, which read as
        // two shapes rather than as a bar the windows sit inside.
        //
        // One path rather than a rectangle with two wedges laid on it: the
        // border has to run along the inner edge *and* around both arcs, and a
        // rectangle's own border would cut straight through them.
        //
        // The path is written **once**, for a bar at the top, and placed by a
        // transform: mirrored across its thickness for the far edges (bottom,
        // right) and transposed for the vertical ones. Eight segments and two
        // arcs that have to agree with a border is exactly the kind of thing
        // that drifts when it is copied, and there would be four copies.
        //
        // The transposition is a reflection rather than a rotation, which is
        // only allowed because this shape is symmetric along the bar - one
        // corner at each end. A reflection of it is the shape the other
        // orientation wants.
        //
        // Order matters: the mirror is in the path's own coordinates, so it
        // has to happen before the transpose moves them.
        Shape {
            id: attachedBackground
            visible: window.attached
            anchors.fill: parent
            transform: [
                Scale {
                    yScale: window.atFar ? -1 : 1
                    origin.y: window.barThickness / 2
                },
                Matrix4x4 {
                    matrix: window.vertical
                        ? Qt.matrix4x4(0, 1, 0, 0,
                                       1, 0, 0, 0,
                                       0, 0, 1, 0,
                                       0, 0, 0, 1)
                        : Qt.matrix4x4(1, 0, 0, 0,
                                       0, 1, 0, 0,
                                       0, 0, 1, 0,
                                       0, 0, 0, 1)
                }
            ]
            preferredRendererType: Shape.CurveRenderer
            // The outer and side borders sit this far outside the surface, so
            // no fractional scale rounds any part of them back into view.
            readonly property real outset: window.geometry.background
                ? Math.abs(window.vertical ? window.geometry.background.y : window.geometry.background.x) : 0
            readonly property real corner: window.geometry.corners
            readonly property real edge: window.barSpan
            // The path runs along the bar, which is the screen's height when
            // the bar is vertical.
            readonly property real length: window.barLength
            ShapePath {
                fillColor: Colors.pillFor("pillBar")
                strokeColor: Colors.pillBorder
                strokeWidth: Metrics.borderWidth
                startX: -attachedBackground.outset
                startY: -attachedBackground.outset
                PathLine {
                    x: attachedBackground.length + attachedBackground.outset
                    y: -attachedBackground.outset
                }
                PathLine {
                    x: attachedBackground.length + attachedBackground.outset
                    y: attachedBackground.edge + attachedBackground.corner
                }
                PathArc {
                    x: attachedBackground.length + attachedBackground.outset - attachedBackground.corner
                    y: attachedBackground.edge
                    radiusX: attachedBackground.corner
                    radiusY: attachedBackground.corner
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: -attachedBackground.outset + attachedBackground.corner
                    y: attachedBackground.edge
                }
                PathArc {
                    x: -attachedBackground.outset
                    y: attachedBackground.edge + attachedBackground.corner
                    radiusX: attachedBackground.corner
                    radiusY: attachedBackground.corner
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: -attachedBackground.outset
                    y: -attachedBackground.outset
                }
            }
        }

        // The floating bar: one rounded capsule inset by the margin.
        Rectangle {
            id: background
            visible: window.flat && !window.attached
            x: window.geometry.background ? window.geometry.background.x : 0
            y: window.geometry.background ? window.geometry.background.y : 0
            width: window.geometry.background ? window.geometry.background.width : 0
            height: window.geometry.background ? window.geometry.background.height : 0
            topLeftRadius: window.geometry.radii.topLeft
            topRightRadius: window.geometry.radii.topRight
            bottomLeftRadius: window.geometry.radii.bottomLeft
            bottomRightRadius: window.geometry.radii.bottomRight
            color: Colors.pillFor("pillBar")
            border.width: Metrics.borderWidth
            border.color: Colors.pillBorder
        }

        // The three zones are `Grid`s rather than `Row`s so one element can be
        // either: `columns: 1` stacks them, a column count nothing will reach
        // lays them in a line. A Row and a Column side by side would mean two
        // of everything below, including the separator flags and the wiggle
        // indices.
        //
        // `start`, `centre` and `end` is what they mean; the ids and the
        // stored keys stay left/center/right because a layout.json written
        // before there were vertical bars has those words in it, and renaming
        // a stored key to make a label read better is how a file stops loading.
        Grid {
            id: leftZone
            onXChanged: Qt.callLater(window.reportZones)
            onYChanged: Qt.callLater(window.reportZones)
            onWidthChanged: Qt.callLater(window.reportZones)
            onHeightChanged: Qt.callLater(window.reportZones)
            readonly property var flags: window.separatorsFor(Array.from({ length: leftRepeater.count }, (_, i) => leftRepeater.itemAt(i)))
            columns: window.vertical ? 1 : 1000
            x: window.vertical ? window.zoneAcross(width)
                : window.geometry.content.x + window.zoneInset
            y: window.vertical ? window.geometry.content.y + window.zoneInset
                : window.zoneAcross(height)
            spacing: window.zoneGap
            Repeater {
                id: leftRepeater
                model: window.bar.left
                Pill {
                    required property var modelData
                    required property int index
                    pill: modelData; screenName: window.modelData.name; scaleFactor: window.scaleFactor
                    flat: window.flat; barRadius: window.barRadius; vertical: window.vertical; barThickness: window.barSpan
                    reportOrigin: window.reportOrigin
                    separator: leftZone.flags[index] === true
                    wiggleIndex: index
                }
            }
        }

        Grid {
            id: centerZone
            onXChanged: Qt.callLater(window.reportZones)
            onYChanged: Qt.callLater(window.reportZones)
            onWidthChanged: Qt.callLater(window.reportZones)
            onHeightChanged: Qt.callLater(window.reportZones)
            readonly property var flags: window.separatorsFor(Array.from({ length: centerRepeater.count }, (_, i) => centerRepeater.itemAt(i)))
            columns: window.vertical ? 1 : 1000
            // Centred, but never under a neighbour: a wide centre pill (an
            // expanded player, a long window title) used to be clamped against
            // the start zone only and then slid under the end one, and the
            // zones have no clip, so the pills drew on top of each other. The
            // same clamp, along whichever axis the bar runs.
            readonly property real lowLimit: window.vertical
                ? leftZone.y + leftZone.height + window.zoneGap
                : leftZone.x + leftZone.width + window.zoneGap
            readonly property real highLimit: window.vertical
                ? rightZone.y - window.zoneGap - height
                : rightZone.x - window.zoneGap - width
            readonly property real along: Math.min(
                Math.max(lowLimit, (window.barLength - (window.vertical ? height : width)) / 2),
                Math.max(lowLimit, highLimit))
            x: window.vertical ? window.zoneAcross(width) : along
            y: window.vertical ? along : window.zoneAcross(height)
            spacing: window.zoneGap
            Repeater {
                id: centerRepeater
                model: window.bar.center
                Pill {
                    required property var modelData
                    required property int index
                    pill: modelData; screenName: window.modelData.name; scaleFactor: window.scaleFactor
                    flat: window.flat; barRadius: window.barRadius; vertical: window.vertical; barThickness: window.barSpan
                    reportOrigin: window.reportOrigin
                    separator: centerZone.flags[index] === true
                    wiggleIndex: index + 2
                }
            }
        }

        Grid {
            id: rightZone
            onXChanged: Qt.callLater(window.reportZones)
            onYChanged: Qt.callLater(window.reportZones)
            onWidthChanged: Qt.callLater(window.reportZones)
            onHeightChanged: Qt.callLater(window.reportZones)
            // The automatic recording pill leads the end zone.
            readonly property var flags: window.separatorsFor([recordingAuto].concat(Array.from({ length: rightRepeater.count }, (_, i) => rightRepeater.itemAt(i))))
            columns: window.vertical ? 1 : 1000
            x: window.vertical ? window.zoneAcross(width)
                : window.geometry.content.x + window.geometry.content.width - width - window.zoneInset
            y: window.vertical ? window.geometry.content.y + window.geometry.content.height - height - window.zoneInset
                : window.zoneAcross(height)
            spacing: window.zoneGap
            Pill {
                id: recordingAuto
                pill: window.recordingPill
                screenName: window.modelData.name
                scaleFactor: window.scaleFactor
                flat: window.flat; barRadius: window.barRadius; vertical: window.vertical; barThickness: window.barSpan
                reportOrigin: window.reportOrigin
                visible: hasContent && !window.hasRecordingPill
            }
            Repeater {
                id: rightRepeater
                model: window.bar.right
                Pill {
                    required property var modelData
                    required property int index
                    pill: modelData; screenName: window.modelData.name; scaleFactor: window.scaleFactor
                    flat: window.flat; barRadius: window.barRadius; vertical: window.vertical; barThickness: window.barSpan
                    reportOrigin: window.reportOrigin
                    separator: rightZone.flags[index + 1] === true
                    wiggleIndex: index + 4
                }
            }
        }
    }
}
