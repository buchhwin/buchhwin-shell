import QtQuick
import qs.theme

// One UI focus ring: an accent outline just outside the control with a soft
// halo around it, so keyboard focus stays visible on dark and light surfaces
// and on top of a translucent panel. `controlRadius` is the radius of the
// control it surrounds.
Item {
    id: root
    property bool active: false
    property real controlRadius: 0

    readonly property int inset: Metrics.focusRingGap + Metrics.focusRingWidth
    anchors.fill: parent
    anchors.margins: -inset
    visible: active
    z: 1

    Rectangle {
        anchors.fill: parent
        radius: root.controlRadius + root.inset
        color: "transparent"
        border.width: Metrics.focusRingWidth
        border.color: Colors.focusHalo
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Metrics.focusRingWidth
        radius: root.controlRadius + Metrics.focusRingGap
        color: "transparent"
        border.width: Metrics.borderWidth
        border.color: Colors.focusRing
    }
}
