import Quickshell
import QtQuick
import qs.theme

// A command to run in a terminal, shown as one: monospace on a sunken block,
// selectable, with a button that copies it whole. For steps the user runs
// themselves (sudo, a package, a model to pull), where prose that says "run
// this, then that" could not be copied from - the assistant's steps without
// Ollama; Settings > Screen sharing draws its configuration lines the same
// way.
Rectangle {
    id: block
    property string command: ""

    implicitHeight: Math.max(lines.implicitHeight, copy.implicitHeight) + Metrics.spaceSm * 2
    radius: Metrics.radiusInner
    color: Colors.sunken
    border.width: Metrics.borderWidth
    border.color: Colors.borderInner

    TextEdit {
        id: lines
        anchors.left: parent.left
        anchors.right: copy.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Metrics.spaceSm
        text: block.command
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        color: Colors.text
        selectionColor: Colors.accentSoft
        selectedTextColor: Colors.text
        font.family: Typography.monoFamily
        font.pixelSize: Typography.smallSize
        renderType: Typography.renderType
    }
    ShellButton {
        id: copy
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Metrics.spaceXs
        focusOnTab: true
        icon: Icons.copy
        compact: true
        variant: "ghost"
        toolTip: "Copy"
        onClicked: Quickshell.clipboardText = block.command
    }
}
