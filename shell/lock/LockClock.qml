import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services
import "../../services/appearance/TimeFormat.js" as TimeFormat

// Large lock screen clock: rolling digits with a soft glow behind and a deep
// shadow, so it stands out from any backdrop.
Item {
    id: root
    required property date time
    implicitWidth: digits.implicitWidth
    implicitHeight: digits.implicitHeight

    readonly property string text: TimeFormat.time(time, SettingsService.twelveHourClock, ":")
    readonly property font clockFont: Qt.font({
        family: Typography.family, pixelSize: Typography.lockClockSize, weight: Typography.bold,
        letterSpacing: -Typography.clockTracking * 2, features: { "tnum": 1 }
    })

    component Digits: Row {
        LockDigit { value: root.text.charAt(0); font: root.clockFont }
        LockDigit { value: root.text.charAt(1); font: root.clockFont }
        Text {
            text: ":"
            font: root.clockFont
            color: Colors.lockClock
            renderType: Typography.renderType
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Metrics.spaceSm
        }
        LockDigit { value: root.text.charAt(3); font: root.clockFont }
        LockDigit { value: root.text.charAt(4); font: root.clockFont }
    }

    // Glow: a blurred copy of the digits right behind them. The layer renders
    // at half resolution — a 24 px blur cannot show the difference, and the
    // whole layer is redrawn for every frame of a rolling digit.
    Digits {
        id: glow
        anchors.centerIn: digits
        opacity: Effects.lockClockGlow
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, glow.width * Effects.glowResolution),
                                   Math.max(1, glow.height * Effects.glowResolution))
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blur: 1
            blurMax: Effects.shadowBlur
            brightness: 0.4
        }
    }

    Digits {
        id: digits
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: Colors.lockBase
            shadowOpacity: Effects.lockClockShadow
            shadowBlur: Effects.shadowBlurSm
            shadowVerticalOffset: Effects.shadowOffset
        }
    }
}
