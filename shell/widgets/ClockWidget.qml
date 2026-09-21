import Quickshell
import QtQuick
import qs.theme
import qs.services

// 24-hour clock. small: time (date on hover), medium: time and short date,
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

    readonly property int textAlign: alignment === "left" ? Text.AlignLeft : alignment === "center" ? Text.AlignHCenter : Text.AlignRight
    readonly property bool showHoverDate: sizeClass === "small" && hovered && !inGroup
    // In groups and pills the clock is compact: "23:45", semibold.
    readonly property real timeSize: (inGroup ? Typography.bodyLargeSize + Metrics.spaceXxs
        : sizeClass === "large" ? Typography.clockLarge
        : sizeClass === "medium" ? Typography.clockMedium : Typography.clockSmall) * scaleFactor

    // Context hints next to the time, only when something needs attention.
    readonly property bool showIndicators: !inGroup && SettingsService.value("desktop.clockIndicators")
    readonly property var indicators: {
        if (!showIndicators) return []
        const result = []
        if (CalendarService.hintActive && CalendarService.upcoming(clock.date) !== null)
            result.push({ icon: "󰃰", color: Colors.accentForeground })
        if (HyprlandService.screencastActive) result.push({ icon: "󰹑", color: Colors.danger })
        if (AudioService.micInUse) result.push({ icon: "󰍬", color: Colors.warning })
        if (NotificationService.dndActive) result.push({ icon: "󰂛", color: root.mutedTextColor })
        else if (NotificationService.unread > 0) result.push({ icon: "󰂞", color: Colors.accentForeground })
        if (PowerService.hasBattery && PowerService.charging && !PowerService.full) result.push({ icon: "󰂄", color: Colors.success })
        else if (PowerService.hasBattery && PowerService.onBattery && PowerService.percent <= 20)
            result.push({ icon: PowerService.icon, color: PowerService.percent <= 10 ? Colors.danger : Colors.warning })
        return result
    }
    // Screen recording: red dot with the elapsed time, a click stops it. Shown
    // even with the hints switched off.
    readonly property bool showRecording: !inGroup && RecordingService.active
    readonly property real indicatorWidth: indicatorRow.visible ? indicatorRow.implicitWidth + Metrics.spaceSm * scaleFactor : 0

    implicitWidth: Math.max(time.implicitWidth + indicatorWidth, detail.visible ? detail.implicitWidth : 0,
                            secondary.visible ? secondary.implicitWidth : 0)
    implicitHeight: time.implicitHeight
        + (detail.visible ? detail.implicitHeight + Metrics.spaceXxs * scaleFactor : 0)
        + (secondary.visible ? secondary.implicitHeight : 0)

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Row {
        id: indicatorRow
        visible: root.indicators.length > 0 || root.showRecording
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
                    renderType: Typography.renderType
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: RecordingService.elapsedText
                    color: Colors.recordingText
                    font.family: Typography.family
                    font.pixelSize: Typography.bodySize * root.scaleFactor
                    font.weight: Typography.semibold
                    font.features: { "tnum": 1 }
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
        text: root.stacked ? Qt.formatTime(clock.date, "HH") + "\n" + Qt.formatTime(clock.date, "mm")
            : root.inGroup ? Qt.formatTime(clock.date, "HH:mm")
            : Qt.formatTime(clock.date, "HH") + " : " + Qt.formatTime(clock.date, "mm")
        color: root.textColor
        font.family: Typography.family
        font.pixelSize: root.timeSize
        font.weight: root.inGroup ? Typography.semibold : Typography.clockWeight
        font.letterSpacing: root.inGroup ? Typography.pillClockTracking : 0
        font.features: { "tnum": 1 }
        renderType: Typography.renderType
    }

    Text {
        id: detail
        anchors.top: time.bottom
        anchors.topMargin: Metrics.spaceXxs * root.scaleFactor
        width: root.width
        horizontalAlignment: root.textAlign
        visible: root.sizeClass !== "small" || opacity > 0
        opacity: root.sizeClass !== "small" || root.showHoverDate ? 1 : 0
        text: root.sizeClass === "medium"
            ? SettingsService.locale.toString(clock.date, "ddd, MMM d")
            : root.sizeClass === "large" ? SettingsService.locale.toString(clock.date, "dddd")
            : SettingsService.locale.toString(clock.date, "dddd, MMMM d")
        color: root.sizeClass === "large" ? root.textColor : root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: (root.sizeClass === "large" ? Typography.headlineSize : Typography.bodySize) * root.scaleFactor
        font.weight: Typography.light
        renderType: Typography.renderType
        Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    }

    Text {
        id: secondary
        anchors.top: detail.bottom
        width: root.width
        horizontalAlignment: root.textAlign
        visible: root.sizeClass === "large"
        text: SettingsService.locale.toString(clock.date, "MMMM d")
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.titleSize * root.scaleFactor
        font.weight: Typography.light
        renderType: Typography.renderType
    }
}
