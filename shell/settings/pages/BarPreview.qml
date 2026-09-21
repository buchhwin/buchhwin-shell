import QtQuick
import qs.theme
import qs.services
import "../../../services/bar/BarLogic.js" as BarLogic

// Small live sketch of the bar in Settings > Bar & Notch: the screen edge the
// bar is on, with pills or the continuous bar (floating or attached), and a
// window that keeps clear of it while space is reserved. Colours follow the
// panel colour.
Rectangle {
    id: root
    property string barStyle: "pills"
    property string position: "floating"
    property string edge: "top"
    property bool reserve: true
    readonly property bool flat: barStyle === "bar"
    readonly property bool atBottom: BarLogic.edge(edge) === "bottom"
    // The sketch turns with the bar, or it would say a left-hand bar is a strip
    // across the top - which is the one thing a preview must not do.
    readonly property bool vertical: BarLogic.vertical(edge)
    readonly property bool atFar: BarLogic.farEdge(edge)
    readonly property real ratio: Metrics.barPreviewBar / Metrics.pillHeight
    readonly property real span: vertical ? screen.height : screen.width
    readonly property var geometry: BarLogic.geometry(barStyle, position, edge, span, {
        height: Metrics.barPreviewBar, margin: Metrics.barMargin * ratio,
        radius: Metrics.barRadius * ratio, border: Metrics.borderWidth
    }, reserve)
    // Relative widths of the left, centre and right item sketches.
    readonly property var zoneItems: ({ left: [0.07, 0.05], center: [0.1], right: [0.04, 0.04, 0.06] })

    implicitHeight: Metrics.barPreviewHeight
    radius: Metrics.radiusCard
    color: Colors.surface
    border.width: Metrics.borderWidth
    border.color: Colors.border

    // The sketched screen: square corners, so an attached bar sits flush.
    Item {
        id: screen
        anchors.fill: parent
        anchors.margins: Metrics.spaceSm
        clip: true

        // A window beside the bar (or behind it without reserved space). Both
        // its edge and its height move, so switching the bar to the bottom is
        // one animation rather than a jump.
        Rectangle {
            readonly property real reserved: root.geometry.exclusiveZone
            x: root.vertical ? (root.atFar ? Metrics.spaceXs : reserved + Metrics.spaceXs) : Metrics.spaceLg
            y: root.vertical ? Metrics.spaceLg
                : root.atBottom ? Metrics.spaceXs : reserved + Metrics.spaceXs
            width: root.vertical ? screen.width - reserved - Metrics.spaceXs : screen.width - Metrics.spaceLg * 2
            height: root.vertical ? screen.height - Metrics.spaceLg * 2 : screen.height - reserved - Metrics.spaceXs
            Behavior on x { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }
            Behavior on width { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }
            radius: Metrics.radiusInner
            color: Colors.elevatedSurface
            border.width: Metrics.borderWidth
            border.color: Colors.border
            Behavior on y { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }
            Behavior on height { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }
        }

        // The bar's own surface, on whichever edge it is. Everything inside is
        // placed by the geometry in the surface's own coordinates, so the
        // sketch and the real bar agree without a second set of rules.
        Item {
            id: barSketch
            width: root.vertical ? root.geometry.thickness : screen.width
            height: root.vertical ? screen.height : root.geometry.thickness
            x: root.vertical && root.atFar ? screen.width - width : 0
            y: !root.vertical && root.atBottom ? screen.height - height : 0
            Behavior on x { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }
            Behavior on y { NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing } }

        Rectangle {
            visible: root.flat
            x: root.geometry.background ? root.geometry.background.x : 0
            y: root.geometry.background ? root.geometry.background.y : 0
            width: root.geometry.background ? root.geometry.background.width : 0
            height: root.geometry.background ? root.geometry.background.height : 0
            topLeftRadius: root.geometry.radii.topLeft
            topRightRadius: root.geometry.radii.topRight
            bottomLeftRadius: root.geometry.radii.bottomLeft
            bottomRightRadius: root.geometry.radii.bottomRight
            color: Colors.pillFor("pillBar")
            border.width: Metrics.borderWidth
            border.color: Colors.pillBorder
        }

        Repeater {
            model: ["left", "center", "right"]

            Grid {
                id: zone
                required property string modelData
                readonly property real inset: BarLogic.zoneInset(root.barStyle, root.position,
                    Metrics.barHighlightInset * root.ratio, Metrics.barSidePadding * root.ratio) + (root.flat ? Metrics.spaceXs : 0)
                readonly property var content: root.geometry.content
                // Along the bar, the same three places whichever way it runs.
                readonly property real size: root.vertical ? height : width
                readonly property real start: root.vertical ? content.y : content.x
                readonly property real extent: root.vertical ? content.height : content.width
                readonly property real along: modelData === "left" ? start + inset
                    : modelData === "right" ? start + extent - size - inset
                    : (root.span - size) / 2
                columns: root.vertical ? 1 : 1000
                x: root.vertical ? content.x : along
                y: root.vertical ? along : content.y
                spacing: root.flat ? Metrics.spaceSm : Metrics.spaceXs

                Repeater {
                    model: root.zoneItems[zone.modelData]

                    // A capsule (pills) or a bare item (bar) with a text sketch.
                    Rectangle {
                        id: sketch
                        required property real modelData
                        // The item's length is a fraction of the bar; across
                        // it, it is the bar's own thickness.
                        readonly property real run: root.span * modelData + (root.flat ? 0 : Metrics.spaceMd)
                        width: root.vertical ? Metrics.barPreviewBar : run
                        height: root.vertical ? run : Metrics.barPreviewBar
                        radius: Math.min(width, height) / 2
                        color: root.flat ? "transparent" : Colors.pillFor("pillBar")
                        border.width: root.flat ? 0 : Metrics.borderWidth
                        border.color: Colors.pillBorder

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.vertical ? Metrics.barPreviewText : root.span * sketch.modelData
                            height: root.vertical ? root.span * sketch.modelData : Metrics.barPreviewText
                            radius: Math.min(width, height) / 2
                            color: Colors.mutedText
                            opacity: Effects.mutedOpacity
                        }
                    }
                }
            }
        }
        }
    }
}
