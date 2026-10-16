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

    // Hour and minute apart, not cut out of the whole time by position: a
    // 12-hour clock writes "9:05 PM", whose third character is the colon, and
    // the lock read "9::5" for nine hours a day and dropped the PM. The hour
    // has one or two digits there, the suffix is its own smaller label.
    readonly property bool twelve: SettingsService.twelveHourClock
    readonly property string hour: TimeFormat.hour(time, twelve)
    readonly property string minute: TimeFormat.minute(time)
    readonly property string suffix: TimeFormat.suffix(time, twelve)
    readonly property font clockFont: Qt.font({
        family: Typography.family, pixelSize: Typography.lockClockSize, weight: Typography.bold,
        letterSpacing: -Typography.clockTracking * 2, features: { "tnum": 1 }
    })
    readonly property font suffixFont: Qt.font({
        family: Typography.family, pixelSize: Typography.lockDateSize, weight: Typography.semibold
    })
    FontMetrics { id: clockMetrics; font: root.clockFont }
    FontMetrics { id: suffixMetrics; font: root.suffixFont }

    component Digits: Row {
        // The tens slot only exists for a two-digit hour: always on a 24-hour
        // clock, so that one looks exactly as it did.
        LockDigit { visible: root.hour.length > 1; value: root.hour.length > 1 ? root.hour.charAt(0) : ""; font: root.clockFont }
        LockDigit { value: root.hour.charAt(root.hour.length - 1); font: root.clockFont }
        Text {
            text: ":"
            font: root.clockFont
            color: Colors.lockClock
            textFormat: Text.PlainText
            renderType: Typography.renderType
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Metrics.spaceSm
        }
        LockDigit { value: root.minute.charAt(0); font: root.clockFont }
        LockDigit { value: root.minute.charAt(1); font: root.clockFont }
        // AM/PM on the digits' baseline: both sit on the row's bottom, lifted
        // by the difference of their descents.
        Text {
            visible: root.suffix.length > 0
            leftPadding: Metrics.spaceSm
            anchors.bottom: parent.bottom
            anchors.bottomMargin: clockMetrics.descent - suffixMetrics.descent
            text: root.suffix
            font: root.suffixFont
            color: Colors.lockClock
            textFormat: Text.PlainText
            renderType: Typography.renderType
        }
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
