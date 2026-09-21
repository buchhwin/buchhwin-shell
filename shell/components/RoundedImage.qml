import QtQuick
import QtQuick.Effects

// Image clipped to a rounded rectangle or circle (radius >= size / 2).
// Plain `clip` only cuts rectangles, so the image is masked instead.
Item {
    id: root
    property alias source: image.source
    property alias fillMode: image.fillMode
    property real radius
    property int sourceWidth: 128
    readonly property int status: image.status

    Image {
        id: image
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.sourceWidth
        layer.enabled: true
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: Math.min(root.radius, Math.min(width, height) / 2)
        visible: false
        layer.enabled: true
        layer.smooth: true
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
