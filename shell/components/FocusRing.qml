import QtQuick
import qs.theme

// One UI focus ring: an accent outline just outside the control with a soft
// halo around it, so keyboard focus stays visible on dark and light surfaces
// and on top of a translucent panel. `controlRadius` is the radius of the
// control it surrounds.
//
// Drawn only while the control has the keyboard focus, and built only then:
// every button, row, toggle, field and slider carries one, nearly all of
// them in panels that are built at start and in controls that never see a
// key, and the rings were a tenth of the shell's objects at start (a profile
// counted 268 of them, 804 objects) for an outline that is almost never on
// screen. The Loader is synchronous, so the ring is there in the frame the
// focus arrives in.
Item {
    id: root
    property bool active: false
    property real controlRadius: 0

    readonly property int inset: Metrics.focusRingGap + Metrics.focusRingWidth
    anchors.fill: parent
    anchors.margins: -inset
    visible: active
    z: 1

    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: Rectangle {
            radius: root.controlRadius + root.inset
            color: "transparent"
            border.width: Metrics.focusRingWidth
            border.color: Colors.focusHalo

            Rectangle {
                anchors.fill: parent
                anchors.margins: Metrics.focusRingWidth
                radius: root.controlRadius + Metrics.focusRingGap
                color: "transparent"
                border.width: Metrics.borderWidth
                border.color: Colors.focusRing
            }
        }
    }
}
