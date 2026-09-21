import QtQuick
import QtQuick.Effects
import "Style.js" as S

// Large clock like the lock screen (shell/lock/LockClock.qml): rolling digits
// with a soft glow behind and a deep shadow, so it stands out from any
// wallpaper.
Item {
    id: root
    required property date time
    required property string fontFamily
    implicitWidth: digits.implicitWidth
    implicitHeight: digits.implicitHeight

    readonly property string text: Qt.formatTime(time, "HH:mm")
    readonly property font clockFont: Qt.font({
        family: fontFamily, pixelSize: S.clockSize, weight: Font.Bold,
        letterSpacing: S.clockTracking, features: { "tnum": 1 }
    })

    component Digits: Row {
        Digit { value: root.text.charAt(0); font: root.clockFont }
        Digit { value: root.text.charAt(1); font: root.clockFont }
        Text {
            text: ":"
            font: root.clockFont
            color: S.clock
            renderType: Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -S.spaceSm
        }
        Digit { value: root.text.charAt(3); font: root.clockFont }
        Digit { value: root.text.charAt(4); font: root.clockFont }
    }

    // Glow: a blurred copy of the digits right behind them.
    Digits {
        anchors.centerIn: digits
        opacity: S.clockGlow
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blur: 1
            blurMax: S.shadowBlur
            brightness: 0.4
        }
    }

    Digits {
        id: digits
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: S.base
            shadowOpacity: S.clockShadow
            shadowBlur: 1
            shadowVerticalOffset: S.shadowOffset
        }
    }
}
