import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services

// Rounds the corners of the screen itself, like a laptop display with a
// rounded bezel. One click-through overlay per screen draws the four wedges
// that lie outside the rounded corner; everything else keeps its own shape.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData
        readonly property int radius: AppearanceService.screenCornerRadius

        screen: modelData
        visible: radius > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "buchhwin-screencorners"
        // Above everything, including a fullscreen window, or the corners
        // would disappear exactly where they are most visible.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // An empty input region: the corners are decoration, never a target.
        mask: Region {}

        // One corner: the wedge between the screen's square corner and the
        // arc. `corner` is the square point, `from`/`to` the two points on the
        // edges where the arc starts and ends; the arc's centre is the point
        // diagonally opposite the square corner.
        component Corner: Shape {
            id: corner
            property point square: Qt.point(0, 0)
            property point from: Qt.point(0, 0)
            property point to: Qt.point(0, 0)
            readonly property int size: window.radius
            width: size
            height: size
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
                    radiusX: corner.size
                    radiusY: corner.size
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: corner.square.x; y: corner.square.y }
            }
        }

        readonly property int r: radius
        Corner {
            anchors.left: parent.left; anchors.top: parent.top
            square: Qt.point(0, 0); from: Qt.point(window.r, 0); to: Qt.point(0, window.r)
        }
        Corner {
            anchors.right: parent.right; anchors.top: parent.top
            square: Qt.point(window.r, 0); from: Qt.point(window.r, window.r); to: Qt.point(0, 0)
        }
        Corner {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            square: Qt.point(window.r, window.r); from: Qt.point(0, window.r); to: Qt.point(window.r, 0)
        }
        Corner {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            square: Qt.point(0, window.r); from: Qt.point(0, 0); to: Qt.point(window.r, window.r)
        }
    }
}
