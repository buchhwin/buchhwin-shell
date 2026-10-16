import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// The start menu's own small menu - an app's (open, its actions, pin it) or
// the power button's. Inside the menu's card rather than a panel of its own:
// one panel is open at a time, and a second one would close the start menu.
// It has the keys while it is open; anything typed closes it and goes to the
// search instead.
FocusScope {
    id: root
    // [{ kind, label, icon, iconSource, hint, enabled }]
    property var rows: []
    property int index: firstEnabled()
    signal picked(var row)
    signal dismissed()
    signal typed(string text)

    implicitWidth: Metrics.startMenuMenuWidth
    implicitHeight: card.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function enabledAt(at) { return at >= 0 && at < rows.length && rows[at].enabled !== false }
    function firstEnabled() {
        for (let at = 0; at < rows.length; ++at) if (enabledAt(at)) return at
        return -1
    }
    function step(delta) {
        for (let at = index + delta; at >= 0 && at < rows.length; at += delta)
            if (enabledAt(at)) { index = at; return }
    }
    onRowsChanged: index = firstEnabled()

    Keys.onPressed: event => {
        event.accepted = true
        if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) step(1)
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) step(-1)
        else if (event.key === Qt.Key_Home) index = firstEnabled()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (enabledAt(index)) root.picked(rows[index])
        }
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left || event.key === Qt.Key_Menu) root.dismissed()
        else if (event.text.length && !(event.modifiers & Qt.ControlModifier) && event.text.charCodeAt(0) >= 32) root.typed(event.text)
        else event.accepted = false
    }

    // Solid under the card's own tint, and lifted off the menu with a
    // panel's shadow: the rows under it must not show through.
    Rectangle {
        anchors.fill: card
        radius: card.radius
        color: Colors.solidSurface
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colors.shadow
            blurMax: Effects.elevation2Max
            shadowBlur: Effects.elevation2Blur
            shadowOpacity: Effects.elevation2Opacity
            shadowVerticalOffset: Effects.elevation2Offset
        }
    }
    ShellCard {
        id: card
        level: 2
        width: parent.width
        implicitHeight: column.implicitHeight + Metrics.spaceXs * 2

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Metrics.spaceXs
            spacing: 0

            Repeater {
                model: root.rows
                ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    level: 2
                    compact: true
                    icon: modelData.icon || ""
                    iconSource: modelData.iconSource || ""
                    title: modelData.label
                    subtitle: modelData.enabled === false ? modelData.hint || "" : ""
                    interactive: modelData.enabled !== false
                    selected: index === root.index
                    onClicked: root.picked(modelData)
                }
            }
        }
    }
}
