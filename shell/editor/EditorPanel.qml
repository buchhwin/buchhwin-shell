import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// The chrome of an editor side panel: the picker and the two inspectors were
// the same twenty-five lines written three times. It follows the panel theme
// like every other surface, so the editor does not look like a different
// application when a panel colour is set.
Rectangle {
    id: root
    property string title: ""
    default property alias content: column.data
    property alias contentSpacing: column.spacing

    // `radiusPanel` is `radiusCard` plus `panelPadding`, so the content sits
    // `panelPadding` in: with a smaller inset the corner of a card inside
    // did not run parallel to the panel's.
    implicitHeight: column.implicitHeight + Metrics.panelPadding * 2
    radius: Metrics.radiusPanel
    color: Colors.panelFor("editor")
    border.width: Metrics.borderWidth
    border.color: Colors.panelBorder
    // Clicks stay in the panel instead of reaching the scrim behind it.
    MouseArea { anchors.fill: parent }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Metrics.panelPadding
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollFeel { id: feel; view: flick }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Metrics.spaceMd

            ShellText {
                Layout.fillWidth: true
                visible: root.title.length > 0
                text: root.title
                role: "title"
            }
        }
    }

    // A hint that there is more below, the one every ScrollList has: a card
    // capped at the room above the editor's controls (the notch's "What it
    // carries", with a named row per item) can end right after a group's
    // last row, and then looked complete with more groups under its edge.
    Rectangle {
        visible: flick.contentHeight > flick.height + 1
        x: flick.x + flick.width - width
        y: flick.y + flick.visibleArea.yPosition * flick.height
        width: Metrics.scrollHintWidth
        height: Math.max(Metrics.spaceLg, flick.visibleArea.heightRatio * flick.height)
        radius: width / 2
        color: Colors.scrollHint
        opacity: flick.moving || feel.scrolling ? 1 : Effects.mutedOpacity
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
    }
}
