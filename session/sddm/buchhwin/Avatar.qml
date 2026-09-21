import QtQuick
import QtQuick.Effects
import "Logic.js" as Logic
import "Style.js" as S

// Round user picture: the face SDDM reports, or the initial on the accent
// colour when the user has none (or it fails to load).
Item {
    id: root
    property string icon: ""
    property string name: ""
    property color accent: S.accent
    property string fontFamily: S.fontFamily
    property int size: S.avatarSize
    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.accent
        visible: picture.status !== Image.Ready
        Text {
            anchors.centerIn: parent
            text: Logic.initial(root.name)
            color: S.accentText
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.size * 0.45)
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        source: Logic.hasOwnFace(root.icon) ? Logic.imageUrl(root.icon) : ""
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
    MultiEffect {
        anchors.fill: parent
        source: picture
        visible: picture.status === Image.Ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
