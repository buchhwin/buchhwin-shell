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
