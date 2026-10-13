import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services

// Rounds the corners of the screen itself, like a laptop display with a
// rounded bezel. Four click-through overlays per screen, each the size of the
// radius and sitting in its corner, draw the wedges that lie outside the
// rounded corner; everything else keeps its own shape.
//
// Four small surfaces, not one the size of the screen: a transparent overlay
// over a whole 4K display is two or three RGBA buffers of some 30 MB each,
// per screen, and the compositor blends the whole of it into every damaged
// frame - under a fullscreen window that is every frame - for four corners of
// sixteen pixels. The namespace stays `buchhwin-screencorners`: the blur-off
// layer rule in hypr/ is keyed on it.
Variants {
    model: Quickshell.screens

    Scope {
        id: screenScope
        required property var modelData
        readonly property int radius: AppearanceService.screenCornerRadius

        // One corner: a surface the size of the radius, anchored into one
        // corner of the screen, drawing the wedge between the screen's square
        // corner and the arc. `square` is the square point, `from`/`to` the
        // two points on the edges where the arc starts and ends; the arc's
        // centre is the point diagonally opposite the square corner.
        component CornerWindow: PanelWindow {
            id: corner
            property point square: Qt.point(0, 0)
            property point from: Qt.point(0, 0)
            property point to: Qt.point(0, 0)
            readonly property int radius: screenScope.radius

            screen: screenScope.modelData
            visible: screenScope.radius > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: radius
            implicitHeight: radius
            WlrLayershell.namespace: "buchhwin-screencorners"
            // Above everything, including a fullscreen window, or the corners
            // would disappear exactly where they are most visible.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // An empty input region: the corners are decoration, never a target.
            mask: Region {}

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Colors.screenCorner
                    strokeWidth: -1
                    startX: corner.square.x
                    startY: corner.square.y
                    PathLine { x: corner.from.x; y: corner.from.y }
                    PathArc {
                        x: corner.to.x
                        y: corner.to.y
                        radiusX: corner.radius
                        radiusY: corner.radius
                        direction: PathArc.Counterclockwise
                    }
                    PathLine { x: corner.square.x; y: corner.square.y }
                }
            }
        }

        // The anchors never change for the life of a surface: a mapped layer
        // surface does not reliably take a new anchor.
        CornerWindow {
            anchors { top: true; left: true }
            square: Qt.point(0, 0); from: Qt.point(radius, 0); to: Qt.point(0, radius)
        }
        CornerWindow {
            anchors { top: true; right: true }
            square: Qt.point(radius, 0); from: Qt.point(radius, radius); to: Qt.point(0, 0)
        }
        CornerWindow {
            anchors { bottom: true; right: true }
            square: Qt.point(radius, radius); from: Qt.point(0, radius); to: Qt.point(radius, 0)
        }
        CornerWindow {
            anchors { bottom: true; left: true }
            square: Qt.point(0, radius); from: Qt.point(0, 0); to: Qt.point(radius, radius)
        }
    }
}
