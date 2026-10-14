import QtQuick
import QtQuick.Layouts
import qs.theme

// A hairline between the parts of a card or popup, full width in a layout.
Rectangle {
    Layout.fillWidth: true
    implicitHeight: Metrics.borderWidth
    color: Colors.border
}
