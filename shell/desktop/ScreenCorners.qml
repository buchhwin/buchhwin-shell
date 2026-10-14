import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services

// Rounds the corners of the screen itself, like a laptop display with a
// rounded bezel. Two click-through strips per screen, one along the top edge
// and one along the bottom, each as tall as the radius, draw the wedges that
// lie outside the rounded corners at their two ends; everything else keeps
// its own shape.
//
// Two thin strips, not one surface the size of the screen: a transparent
// overlay over a whole 4K display is two or three RGBA buffers of some 30 MB
// each, per screen, and the compositor blends the whole of it into every
// damaged frame - under a fullscreen window that is every frame - for four
// corners of sixteen pixels. And two strips, not a surface per corner: every
// mapped window costs the shell a render thread, its GL context with Mesa's
// threads and a malloc arena (testing.md pitfall 50), and four corners were
// four of the seven windows of a single screen. A strip of 3840 x 27 pixels is
// some 400 KB. The namespace stays `buchhwin-screencorners`: the blur-off
// layer rule in hypr/ is keyed on it.
Variants {
    model: Quickshell.screens

    Scope {
        id: screenScope
        required property var modelData
        readonly property int radius: AppearanceService.screenCornerRadius

        // One wedge, drawn inside a strip: `square` is the square corner of
        // the screen, `from`/`to` the two points on the edges where the arc
        // starts and ends; the arc's centre is the point diagonally opposite
        // the square corner.
        component Wedge: Shape {
            id: wedge
            property point square: Qt.point(0, 0)
            property point from: Qt.point(0, 0)
            property point to: Qt.point(0, 0)
            readonly property int radius: screenScope.radius
            width: radius
            height: radius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Colors.screenCorner
                strokeWidth: -1
                startX: wedge.square.x
                startY: wedge.square.y
                PathLine { x: wedge.from.x; y: wedge.from.y }
                PathArc {
                    x: wedge.to.x
                    y: wedge.to.y
                    radiusX: wedge.radius
                    radiusY: wedge.radius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: wedge.square.x; y: wedge.square.y }
            }
        }

        // One strip: the screen's width, the radius tall, along one edge.
        component CornerStrip: PanelWindow {
            screen: screenScope.modelData
            visible: screenScope.radius > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            implicitHeight: screenScope.radius
            WlrLayershell.namespace: "buchhwin-screencorners"
            // Above everything, including a fullscreen window, or the corners
            // would disappear exactly where they are most visible.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // An empty input region: the corners are decoration, never a target.
            mask: Region {}
        }

        // The anchors never change for the life of a surface: a mapped layer
        // surface does not reliably take a new anchor.
        CornerStrip {
            anchors { top: true; left: true; right: true }
            Wedge {
                anchors.left: parent.left
                square: Qt.point(0, 0); from: Qt.point(radius, 0); to: Qt.point(0, radius)
            }
            Wedge {
                anchors.right: parent.right
                square: Qt.point(radius, 0); from: Qt.point(radius, radius); to: Qt.point(0, 0)
            }
        }
        CornerStrip {
            anchors { bottom: true; left: true; right: true }
            Wedge {
                anchors.right: parent.right
                square: Qt.point(radius, radius); from: Qt.point(0, radius); to: Qt.point(radius, 0)
            }
            Wedge {
                anchors.left: parent.left
                square: Qt.point(0, radius); from: Qt.point(0, 0); to: Qt.point(radius, radius)
            }
        }
    }
}
