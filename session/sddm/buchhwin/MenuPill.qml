import QtQuick
import QtQuick.Layouts
import "Style.js" as S

// Small translucent pill (icon, label, chevron) that opens a list above it:
// the session and user choosers. `entries` are { label, detail, face }.
Item {
    id: root
    property string icon: ""
    property string label: ""
    property var entries: []
    property int currentIndex: -1
    property bool open: false
    property bool showFaces: false
    property string fontFamily: S.fontFamily
    property color accent: S.accent
    signal toggled()
    signal chosen(int index)
    implicitWidth: row.implicitWidth + S.spaceMd * 2
    implicitHeight: S.pillHeight

    onOpenChanged: {
        if (!open) return
        list.currentIndex = Math.max(0, currentIndex)
        list.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: area.containsMouse || root.open ? S.button : S.field
        border.width: S.borderWidth
        border.color: S.fieldBorder
        Behavior on color { ColorAnimation { duration: S.hoverMs } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: S.spaceSm
            Icon { name: root.icon; size: S.iconSm }
            Text {
                text: root.label
                color: S.text
                font.family: root.fontFamily
                font.pixelSize: S.smallSize
                font.weight: Font.Medium
                renderType: Text.QtRendering
            }
            Icon {
                name: "chevron"
                size: S.iconSm - S.spaceXs
                opacity: S.mutedOpacity
                rotation: root.open ? 0 : 180
                Behavior on rotation { NumberAnimation { duration: S.popupOpen } }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    Rectangle {
        id: menu
        anchors.left: parent.left
        anchors.bottom: parent.top
        anchors.bottomMargin: S.spaceSm
        width: Math.max(S.menuMinWidth, root.width, list.contentWidthHint)
        height: Math.min(list.contentHeight, S.menuRowHeight * 8) + S.spaceXs * 2
        radius: S.radiusMd
        color: S.menu
        border.width: S.borderWidth
        border.color: S.menuBorder
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        transformOrigin: Item.BottomLeft
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: S.popupOpen; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: S.popupOpen; easing.type: Easing.OutCubic } }

        ListView {
            id: list
            // Widest label, so long session names are not cut.
            property real contentWidthHint: 0
            anchors.fill: parent
            anchors.margins: S.spaceXs
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries
            keyNavigationEnabled: true
            highlightMoveDuration: 0
            Keys.onReturnPressed: root.chosen(currentIndex)
            Keys.onEnterPressed: root.chosen(currentIndex)
            Keys.onEscapePressed: root.toggled()
            Keys.onSpacePressed: root.chosen(currentIndex)

            delegate: Rectangle {
                id: entry
                required property var modelData
                required property int index
                width: ListView.view.width
                height: S.menuRowHeight
                radius: S.radiusSm
                color: entryArea.containsMouse || (list.activeFocus && ListView.isCurrentItem) ? S.hover : "transparent"
                Component.onCompleted: list.contentWidthHint = Math.max(list.contentWidthHint, entryRow.implicitWidth + S.spaceMd * 2 + S.spaceXs * 2)

                RowLayout {
                    id: entryRow
                    anchors.fill: parent
                    anchors.leftMargin: S.spaceMd
                    anchors.rightMargin: S.spaceMd
                    spacing: S.spaceSm
                    Avatar {
                        visible: root.showFaces
                        size: S.menuAvatarSize
                        icon: entry.modelData.face || ""
                        name: entry.modelData.label
                        accent: root.accent
                        fontFamily: root.fontFamily
                    }
                    Text {
                        Layout.fillWidth: true
                        text: entry.modelData.label
                        color: S.text
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: S.bodySize
                        renderType: Text.QtRendering
                    }
                    Text {
                        visible: text.length > 0
                        text: entry.modelData.detail || ""
                        color: S.muted
                        font.family: root.fontFamily
                        font.pixelSize: S.captionSize
                        renderType: Text.QtRendering
                    }
                    Icon {
                        name: "check"
                        size: S.iconSm
                        opacity: entry.index === root.currentIndex ? 1 : 0
                    }
                }
                MouseArea {
                    id: entryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(entry.index)
                }
            }
        }
    }
}
