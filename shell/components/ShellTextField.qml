import QtQuick
import QtQuick.Layouts
import qs.theme

// One UI input: a filled capsule with an icon, placeholder and optional busy
// indicator. Focus shows the accent outline (the same marker the focus ring
// draws around the other controls).
Rectangle {
    id: root
    property alias text: input.text
    property alias echoMode: input.echoMode
    readonly property alias inputActiveFocus: input.activeFocus
    property string icon: ""
    property string placeholder: ""
    property bool busy: false
    // Tab / Shift+Tab move between fields that opt in (forms).
    property bool focusOnTab: false
    property bool selectAllOnFocus: false
    // The hero field of a panel (the launcher): taller, card-shaped and set in
    // the title size, but the same material as every other field.
    property bool large: false
    signal accepted()
    signal escapePressed()
    // Delete with an empty field (TextInput would swallow the key otherwise).
    signal deleteOnEmpty()
    // First refusal on every key, before the field itself handles it. A panel
    // that drives a list from its search field (the launcher) needs Return and
    // the arrows before TextInput takes them.
    signal keyPressed(var event)

    function focusInput() { input.forceActiveFocus() }

    implicitHeight: large ? Metrics.controlHeight + Metrics.spaceLg : Metrics.controlHeight
    radius: large ? Metrics.radiusCard : Metrics.pillRadius(height)
    color: input.activeFocus ? Colors.controlFillHover : Colors.controlFill
    border.width: Metrics.borderWidth
    border.color: input.activeFocus ? Colors.accentBorder : large ? Colors.border : "transparent"
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    Behavior on border.color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceLg
        spacing: Metrics.spaceSm
        ShellIcon {
            visible: root.icon.length > 0
            glyph: root.icon
            size: root.large ? Metrics.iconMd : Metrics.iconSm
            color: root.large ? Colors.accentForeground : Colors.mutedText
        }
        TextInput {
            id: input
            Layout.fillWidth: true
            color: Colors.text
            selectionColor: Colors.accentSoft
            font.family: Typography.family
            font.pixelSize: root.large ? Typography.titleSize : Typography.bodySize
            selectedTextColor: Colors.text
            clip: true
            activeFocusOnTab: root.focusOnTab
            onActiveFocusChanged: if (activeFocus && root.selectAllOnFocus) selectAll()
            onAccepted: root.accepted()
            Keys.onPressed: event => root.keyPressed(event)
            Keys.onDeletePressed: event => {
                if (text.length) { event.accepted = false; return }
                root.deleteOnEmpty()
            }
            Keys.onEscapePressed: event => {
                if (text.length) text = ""
                else event.accepted = false
                root.escapePressed()
            }
            ShellText {
                visible: parent.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                role: root.large ? "bodyLarge" : "body"
                color: Colors.subtleText
            }
        }
        ShellIcon {
            visible: root.busy
            glyph: Icons.refresh
            size: Metrics.iconSm
            color: Colors.mutedText
            RotationAnimation on rotation {
                running: root.busy && root.visible && Animations.motionEnabled
                from: 0
                to: 360
                loops: Animation.Infinite
                duration: Animations.spinner
            }
        }
    }
}
