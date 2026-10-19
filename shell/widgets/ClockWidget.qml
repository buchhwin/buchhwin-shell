import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/appearance/TimeFormat.js" as TimeFormat
import "../../services/appearance/DateFormat.js" as DateFormat

// The clock, in 24 or 12 hours (SettingsService.twelveHourClock). small: time
// (date on hover), medium: time and short date,
// large: time, weekday and date.
Item {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // The surface runs down the screen (a bar on the left or right edge).
    // "18:52" is wider than such a strip, so the hours go above the minutes -
    // which is what a clock on a vertical taskbar has always done, and it
    // needs neither a rotation nor a wider bar.
    property bool vertical: false
    readonly property bool stacked: vertical && inGroup
    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    // A surface that stays dark in both themes (the notch): the hints take
    // their on-dark colours, as WidgetBase's states do. The charging hint is
    // the green or the accent (Settings > Power > Status colors), a low
    // battery red in both.
    property bool onDark: false
    readonly property color successInk: onDark ? Colors.positiveOnDark : Colors.positive
    readonly property color dangerInk: onDark ? Colors.dangerOnDark : Colors.danger
    readonly property color warningInk: onDark ? Colors.warningOnDark : Colors.warning
    readonly property color accentInk: onDark ? Colors.notchAccent : Colors.accentForeground

    readonly property int textAlign: alignment === "left" ? Text.AlignLeft : alignment === "center" ? Text.AlignHCenter : Text.AlignRight
    readonly property bool showHoverDate: sizeClass === "small" && hovered && !inGroup
    // In groups and pills the clock is compact: "23:45", semibold.
    readonly property real timeSize: (inGroup ? Typography.bodyLargeSize + Metrics.spaceXxs
        : sizeClass === "large" ? Typography.clockLarge
        : sizeClass === "medium" ? Typography.clockMedium : Typography.clockSmall) * scaleFactor

    // Context hints next to the time, only when something needs attention.
    readonly property bool showIndicators: !inGroup && SettingsService.value("desktop.clockIndicators")
    // The event hint needs the calendar while this clock can draw it; the
    // backend no longer starts for the setting alone (CalendarService.wanted).
    readonly property CalendarDemand calendarDemand: CalendarDemand { active: root.showIndicators && CalendarService.hintActive }
    readonly property var indicators: {
        if (!showIndicators) return []
        const result = []
        if (CalendarService.hintActive && CalendarService.upcoming(clock.date) !== null)
            result.push({ icon: "󰃰", color: root.accentInk })
        if (HyprlandService.screencastActive) result.push({ icon: "󰹑", color: root.dangerInk })
        if (AudioService.micInUse) result.push({ icon: "󰍬", color: root.warningInk })
        if (NotificationService.dndActive) result.push({ icon: "󰂛", color: root.mutedTextColor })
        else if (NotificationService.unread > 0) result.push({ icon: "󰂞", color: root.accentInk })
        // A low battery is PowerService's low, in the danger colour every
        // other battery uses. It had its own two steps here (amber from 20 %,
        // red from 10 %) that no other surface drew; the escalation lives in
        // the warnings, which grow more urgent at 10 % and 5 %.
        if (PowerService.hasBattery && PowerService.charging && !PowerService.full) result.push({ icon: "󰂄", color: root.successInk })
        else if (PowerService.low) result.push({ icon: PowerService.icon, color: root.dangerInk })
        return result
    }
    // Screen recording: red dot with the elapsed time, a click stops it. Shown
    // even with the hints switched off.
    readonly property bool showRecording: !inGroup && RecordingService.active
    // Which lines are there, as their own conditions rather than read back
    // from `visible`: that is false under any hidden parent too, and the bar
    // hides its content while a fullscreen window covers it (PillBar) - the
    // clock's size then shrank behind the hidden bar and its pill sprang
    // back to width on the way out of fullscreen.
    readonly property bool indicatorsShown: indicators.length > 0 || showRecording
    readonly property bool detailShown: sizeClass !== "small" || detail.opacity > 0
    readonly property bool secondaryShown: sizeClass === "large"
    readonly property real indicatorWidth: indicatorsShown ? indicatorRow.implicitWidth + Metrics.spaceSm * scaleFactor : 0

    implicitWidth: Math.max(time.implicitWidth + indicatorWidth, detailShown ? detail.implicitWidth : 0,
                            secondaryShown ? secondary.implicitWidth : 0)
    implicitHeight: time.implicitHeight
        + (detailShown ? detail.implicitHeight + Metrics.spaceXxs * scaleFactor : 0)
        + (secondaryShown ? secondary.implicitHeight : 0)

    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: WallClock.ticking }

    Row {
        id: indicatorRow
        visible: root.indicatorsShown
        spacing: Metrics.spaceXs * root.scaleFactor
        anchors.verticalCenter: time.verticalCenter
        x: root.alignment === "left" ? time.x + time.contentWidth + Metrics.spaceSm * root.scaleFactor
            : root.alignment === "center" ? (root.width - time.contentWidth - root.indicatorWidth) / 2
            : root.width - time.contentWidth - root.indicatorWidth
        // Outside the repeater so the per-second time update does not rebuild
        // the hints (and a click is not lost).
        Rectangle {
            visible: root.showRecording
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: recordingRow.implicitWidth + Metrics.spaceSm * 2 * root.scaleFactor
            implicitHeight: recordingRow.implicitHeight + Metrics.spaceXxs * 2 * root.scaleFactor
            radius: height / 2
            color: Colors.recording
            Row {
                id: recordingRow
                anchors.centerIn: parent
                spacing: Metrics.spaceXs * root.scaleFactor
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: recordingMouse.containsMouse ? "󰓛" : "󰑊"
                    color: Colors.recordingText
                    font.family: Typography.iconFamily
                    font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
                    textFormat: Text.PlainText
                    renderType: Typography.renderType
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Only asked while the chip shows: a clock in a pill or a
                    // test never starts the recorder's service for it.
                    text: root.showRecording ? RecordingService.elapsedText : ""
                    color: Colors.recordingText
                    font.family: Typography.family
                    font.pixelSize: Typography.bodySize * root.scaleFactor
                    font.weight: Typography.semibold
                    font.features: { "tnum": 1 }
                    textFormat: Text.PlainText
                    renderType: Typography.renderType
                }
            }
            MouseArea {
                id: recordingMouse
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXxs
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: RecordingService.stop()
            }
        }
        Repeater {
            model: root.indicators
            Text {
                required property var modelData
                text: modelData.icon
                color: modelData.color
                font.family: Typography.iconFamily
                font.pixelSize: Typography.titleSize * root.scaleFactor
                textFormat: Text.PlainText
                renderType: Typography.renderType
            }
        }
    }

    Text {
        id: time
        // Centred clocks shift right by half the indicator width so time and
        // hints are centred together.
        x: root.alignment === "center" ? root.indicatorWidth / 2 : 0
        width: root.alignment === "left" ? root.width - root.indicatorWidth : root.width
        horizontalAlignment: root.stacked ? Text.AlignHCenter : root.textAlign
        // No colon when it is two lines: the break is the separator, and a
        // colon hanging at the end of the hours reads as a missing number.
        // `lineHeight` pulls the pair together so it reads as one time.
        lineHeight: root.stacked ? 0.92 : 1
        text: root.stacked
            ? TimeFormat.hour(clock.date, SettingsService.twelveHourClock) + "\n" + TimeFormat.minute(clock.date)
            : root.inGroup ? TimeFormat.time(clock.date, SettingsService.twelveHourClock, ":")
            : TimeFormat.time(clock.date, SettingsService.twelveHourClock, " : ")
        color: root.textColor
        font.family: Typography.family
        font.pixelSize: root.timeSize
        font.weight: root.inGroup ? Typography.semibold : Typography.clockWeight
        font.letterSpacing: root.inGroup ? Typography.pillClockTracking : 0
        font.features: { "tnum": 1 }
        textFormat: Text.PlainText
        renderType: Typography.renderType
    }

    Text {
        id: detail
        anchors.top: time.bottom
        anchors.topMargin: Metrics.spaceXxs * root.scaleFactor
        width: root.width
        horizontalAlignment: root.textAlign
        visible: root.detailShown
        opacity: root.sizeClass !== "small" || root.showHoverDate ? 1 : 0
        text: root.sizeClass === "medium"
            ? DateFormat.date(clock.date, SettingsService.locale, "short")
            : root.sizeClass === "large" ? SettingsService.locale.toString(clock.date, "dddd")
            : DateFormat.date(clock.date, SettingsService.locale, "long")
        color: root.sizeClass === "large" ? root.textColor : root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: (root.sizeClass === "large" ? Typography.headlineSize : Typography.bodySize) * root.scaleFactor
        font.weight: Typography.light
        textFormat: Text.PlainText
        renderType: Typography.renderType
        Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    }

    Text {
        id: secondary
        anchors.top: detail.bottom
        width: root.width
        horizontalAlignment: root.textAlign
        visible: root.secondaryShown
        text: DateFormat.date(clock.date, SettingsService.locale, "day")
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.titleSize * root.scaleFactor
        font.weight: Typography.light
        textFormat: Text.PlainText
        renderType: Typography.renderType
    }
}
