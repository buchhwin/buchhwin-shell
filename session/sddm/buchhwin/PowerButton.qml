import QtQuick
import QtQuick.Layouts
import "Style.js" as S

// Round power button with a label, as on the lock screen: the first click
// asks for confirmation, the second one runs the action.
ColumnLayout {
    id: root
    property string icon: ""
    property string label: ""
    property bool confirming: false
    property string fontFamily: S.fontFamily
    property color accent: S.accent
    signal clicked()
    spacing: S.spaceXs

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: S.controlHeight + S.spaceSm
        implicitHeight: implicitWidth
        radius: width / 2
        color: root.confirming ? root.accent : area.containsMouse ? S.button : S.field
        border.width: root.confirming ? 0 : S.borderWidth
        border.color: S.fieldBorder
        Behavior on color { ColorAnimation { duration: S.hoverMs } }
        Icon { anchors.centerIn: parent; name: root.icon; size: S.iconMd }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.confirming ? "Click again" : root.label
        color: S.muted
        font.family: root.fontFamily
        font.pixelSize: S.captionSize
        renderType: Text.QtRendering
    }
}
