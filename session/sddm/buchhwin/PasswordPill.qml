import QtQuick
import "Style.js" as S

// Password pill like the lock screen (shell/lock/PasswordField.qml): dots,
// an arrow button once something is typed, a shake after a failed login.
Item {
    id: root
    property string fontFamily: S.fontFamily
    property bool busy: false
    // Users without a password log in with Enter or the arrow alone.
    property bool needsPassword: true
    readonly property alias text: input.text
    signal submitted()
    signal edited()
    // Every key press in the field (for the Caps Lock guess).
    signal keyPressed(string text, bool shift, bool capsKey)
    implicitWidth: S.fieldWidth
    implicitHeight: S.fieldHeight

    function clear() { input.text = "" }
    function focusInput() { input.forceActiveFocus() }
    function shake() { shakeAnimation.restart() }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: S.field
        border.width: S.borderWidth
        border.color: input.activeFocus ? S.button : S.fieldBorder
        transform: Translate { id: offset }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: S.spaceLg
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: root.busy ? "Logging in …" : root.needsPassword ? "Enter Password" : "Press Enter to log in"
            color: S.muted
            font.family: root.fontFamily
            font.pixelSize: S.bodySize
            renderType: Text.QtRendering
        }

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.right: button.left
            anchors.leftMargin: S.spaceLg
            anchors.rightMargin: S.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            focus: true
            readOnly: root.busy
            echoMode: TextInput.Password
            passwordCharacter: "•"
            passwordMaskDelay: 0
            color: S.text
            selectionColor: S.button
            selectedTextColor: S.text
            cursorVisible: false
            cursorDelegate: Item {}
            font.family: root.fontFamily
            font.pixelSize: S.bodySize
            font.letterSpacing: S.dotTracking
            renderType: Text.QtRendering
            opacity: root.busy ? S.mutedOpacity : 1
            onTextEdited: root.edited()
            onAccepted: root.submitted()
            Keys.onEscapePressed: text = ""
            Keys.onPressed: event => {
                root.keyPressed(event.text, (event.modifiers & Qt.ShiftModifier) !== 0, event.key === Qt.Key_CapsLock)
                event.accepted = false
            }
        }

        Rectangle {
            id: button
            anchors.right: parent.right
            anchors.rightMargin: S.spaceXs
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - S.spaceXs * 2
            height: width
            radius: width / 2
            color: arrowArea.containsMouse ? S.fieldBorder : S.button
            opacity: (input.text.length > 0 || !root.needsPassword) && !root.busy ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: S.hoverMs } }
            Icon { anchors.centerIn: parent; name: "arrow"; size: S.iconSm }
            MouseArea {
                id: arrowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.submitted()
            }
        }
    }

    // Mirrors shell/lock/PasswordField.qml: three swings, then back.
    SequentialAnimation {
        id: shakeAnimation
        NumberAnimation { target: offset; property: "x"; to: S.shakeOffset; duration: S.shakeOutMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: offset; property: "x"; to: -S.shakeOffset; duration: S.shakeSwingMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: offset; property: "x"; to: S.shakeOffset; duration: S.shakeSwingMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: offset; property: "x"; to: 0; duration: S.shakeSwingMs; easing.type: Easing.OutQuad }
    }
}
