import QtQuick
import qs.theme

// Vertical list area that grows with its content up to maxHeight. It sits on
// the panel as a card, like every other group of rows, and insets its content
// because a Rectangle does not clip its children to its radius. `card: false`
// is for a list whose own children are already cards.
//
// A `title` belongs to the card rather than floating above it: a label outside
// and a card below it read as two things, and the whole point of the card is
// that the label and the rows are one.
Item {
    id: root
    default property alias content: column.data
    // The list itself, for an arrange surface inside it: a drag near the edge
    // has to be able to scroll what it is sitting in.
    readonly property alias view: flick
    property string title: ""
    property real maxHeight: 360
    property bool card: true
    property real padding: card ? Metrics.spaceXs : 0
    readonly property real headHeight: title.length > 0 ? head.implicitHeight + Metrics.spaceSm : 0
    readonly property real contentMax: Math.max(0, maxHeight - padding * 2 - headHeight)

    implicitHeight: Math.min(column.implicitHeight, contentMax) + padding * 2 + headHeight

    ShellCard {
        anchors.fill: parent
        visible: root.card
    }

    ShellText {
        id: head
        visible: root.title.length > 0
        text: root.title
        role: "title"
        elide: Text.ElideRight
        x: root.padding + Metrics.spaceSm
        y: root.padding + Metrics.spaceXs
        width: Math.max(0, root.width - x * 2)
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: root.padding
        anchors.topMargin: root.padding + root.headHeight
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: flick.width
            spacing: Metrics.spaceXxs
        }
    }

    // A hint that there is more below. While the height followed its content
    // there was never anything hidden; with a height the user chose there is,
    // and a bare Flickable says nothing about it.
    Rectangle {
        id: hint
        visible: flick.contentHeight > flick.height + 1
        x: flick.x + flick.width - width
        y: flick.y + flick.visibleArea.yPosition * flick.height
        width: Metrics.scrollHintWidth
        height: Math.max(Metrics.spaceLg, flick.visibleArea.heightRatio * flick.height)
        radius: width / 2
        color: Colors.scrollHint
        opacity: flick.moving ? 1 : Effects.mutedOpacity
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
    }
}
