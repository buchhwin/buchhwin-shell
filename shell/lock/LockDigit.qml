import QtQuick
import qs.theme

// One clock digit that rolls: the old value slides up and fades while the new
// one comes in from below.
Item {
    id: root
    property string value: "0"
    property font font
    property color color: Colors.lockClock
    implicitWidth: metrics.advanceWidth
    implicitHeight: metrics.height
    clip: true

    TextMetrics { id: metrics; font: root.font; text: "0" }

    property string previous: value
    // Only real changes roll; the first value just appears.
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => ready = true)
    onValueChanged: {
        if (!ready || !Animations.motionEnabled) { previous = value; return }
        roll.stop()
        incoming.y = root.height * 0.55
        incoming.opacity = 0
        outgoing.y = 0
        outgoing.opacity = 1
        roll.start()
    }

    Text {
        id: outgoing
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.previous
        font: root.font
        color: root.color
        renderType: Typography.renderType
        opacity: 0
    }
    Text {
        id: incoming
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.value
        font: root.font
        color: root.color
        renderType: Typography.renderType
    }

    ParallelAnimation {
        id: roll
        NumberAnimation { target: incoming; property: "y"; to: 0; duration: Animations.lockDigit; easing.type: Animations.easingControl; easing.overshoot: Animations.overshoot }
        NumberAnimation { target: incoming; property: "opacity"; to: 1; duration: Animations.lockDigitFade }
        NumberAnimation { target: outgoing; property: "y"; to: -root.height * 0.55; duration: Animations.lockDigit; easing.type: Animations.easing }
        NumberAnimation { target: outgoing; property: "opacity"; to: 0; duration: Animations.lockDigitFade }
        onFinished: root.previous = root.value
    }
}
