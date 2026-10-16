import QtQuick
import QtQuick.Shapes
import qs.theme
import "../../services/startmenu/StartMenuLogic.js" as Logic

// The fastfetch Saturn as a mark: the planet, and its ring tilted up to the
// right, behind the planet at the top and across its lower half in front -
// traced from config/builtin-profiles/buchhwin/saturn.txt, in the colours
// `ff` gives the logo (Colors.saturnPlanet, saturnRing). Drawn as shapes, not
// letters: at a dock icon's size the logo's 15 rows would be a pixel each. The
// start button wears it (shell/widgets/StartWidget.qml).
//
// Shapes with the curve renderer: the paths stay on the GPU and stay sharp at
// any size and scale, and only a new size or colour builds them again.
Item {
    id: root
    property color planetColor: Colors.saturnPlanet
    property color ringColor: Colors.saturnRing
    // A dark or light rim around it all, for a surface that has gone
    // see-through (the dock down to nothing: the mark on the wallpaper).
    property bool halo: false
    property color haloColor: Colors.textHalo

    implicitHeight: Metrics.startGlyphHeight
    implicitWidth: Metrics.startGlyphWidth

    readonly property var geometry: Logic.saturnGeometry(width, height)

    component Drawing: Shape {
        id: drawing
        // Extra width around every line and the planet: the halo's rim.
        property real rim: 0
        property color planet
        property color ring
        property var g: ({ cx: 0, cy: 0, planet: 0, ringA: 0, ringB: 0, stroke: 0, tilt: 0, overlap: 0 })
        anchors.fill: parent
        rotation: g.tilt
        preferredRendererType: Shape.CurveRenderer

        // The ring's far half, behind the planet: the top of the ellipse.
        ShapePath {
            fillColor: "transparent"
            strokeColor: drawing.ring
            strokeWidth: drawing.g.stroke + drawing.rim * 2
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: drawing.g.cx; centerY: drawing.g.cy
                radiusX: drawing.g.ringA; radiusY: drawing.g.ringB
                startAngle: 180; sweepAngle: 180
            }
        }
        // The planet over it.
        ShapePath {
            fillColor: drawing.planet
            strokeColor: drawing.rim > 0 ? drawing.planet : "transparent"
            strokeWidth: drawing.rim > 0 ? drawing.rim * 2 : -1
            PathAngleArc {
                centerX: drawing.g.cx; centerY: drawing.g.cy
                radiusX: drawing.g.planet; radiusY: drawing.g.planet
                startAngle: 0; sweepAngle: 360
            }
        }
        // The near half across the planet's lower half, reaching a little
        // over the far half at both tips so the two meet without a seam.
        ShapePath {
            fillColor: "transparent"
            strokeColor: drawing.ring
            strokeWidth: drawing.g.stroke + drawing.rim * 2
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: drawing.g.cx; centerY: drawing.g.cy
                radiusX: drawing.g.ringA; radiusY: drawing.g.ringB
                startAngle: -drawing.g.overlap; sweepAngle: 180 + drawing.g.overlap * 2
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.halo
        sourceComponent: Drawing { g: root.geometry; rim: Metrics.startGlyphHalo; planet: root.haloColor; ring: root.haloColor }
    }
    Drawing { g: root.geometry; planet: root.planetColor; ring: root.ringColor }
}
