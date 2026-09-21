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

    implicitHeight: column.implicitHeight + Metrics.spaceLg * 2
    radius: Metrics.radiusPanel
    color: Colors.panelFor("editor")
    border.width: Metrics.borderWidth
    border.color: Colors.panelBorder
    // Clicks stay in the panel instead of reaching the scrim behind it.
    MouseArea { anchors.fill: parent }

    Flickable {
        anchors.fill: parent
        anchors.margins: Metrics.spaceLg
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

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
}
