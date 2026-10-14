import QtQuick
import QtQuick.Layouts
import qs.theme

// A card with an optional title, an optional description and padded content.
// The one way to put a group of controls on a card: settings sections, control
// center pages, dashboard blocks and popups all use it, so a card looks the
// same wherever it appears. A Rectangle does not clip its children to its
// radius, so the content is inset rather than filling the card.
ShellCard {
    id: root
    property string title: ""
    property string description: ""
    property real padding: Metrics.spaceLg
    property real spacing: Metrics.spaceMd
    // Where the title sits from the card's edges: one inset for every titled
    // card, whatever its content padding. A card of rows pads by spaceSm or
    // less because ListRow brings its own inset, and its title sat at 8/8
    // beside the 16/16 of every other card (the privacy popup). A card padded
    // for plain content keeps the title on that content's edge.
    property real titleInset: padding < Metrics.spaceMd ? Metrics.spaceLg : padding
    default property alias content: body.data
    implicitHeight: column.implicitHeight + root.padding * 2

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: root.spacing

        ColumnLayout {
            spacing: Metrics.spaceXxs
            visible: root.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Math.max(0, root.titleInset - root.padding)
            Layout.rightMargin: Math.max(0, root.titleInset - root.padding)
            Layout.topMargin: Math.max(0, root.titleInset - root.padding)
            ShellText { text: root.title; role: "title"; Layout.fillWidth: true }
            ShellText { text: root.description; muted: true; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: root.spacing
        }
    }
}
