import QtQuick
import "Style.js" as S

// White line icon from assets/ (Nerd Fonts live in the user's home and are
// not readable by the sddm user).
Item {
    id: root
    property string name: ""
    property int size: S.iconMd
    implicitWidth: size
    implicitHeight: size

    Image {
        anchors.fill: parent
        source: root.name.length ? "assets/" + root.name + ".svg" : ""
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
