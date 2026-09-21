import Quickshell
import QtQuick
import qs.theme
import qs.services

Item {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // A bar that runs down the screen. "Sat, Sep 20" is three times wider
    // than a strip a pill wide, and there is no way to set it in one line
    // that is not a lie - so it becomes two, and the month is what goes.
    // On any day you are reading a bar you already know the month; the
    // weekday and the date are what you look at. The weekday sits above,
    // small and muted, with the day's number under it, which is what a date
    // on a vertical taskbar has always been.
    property bool vertical: false

    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText

    implicitWidth: vertical ? stack.implicitWidth : label.implicitWidth
    implicitHeight: vertical ? stack.implicitHeight : label.implicitHeight

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Text {
        id: label
        visible: !root.vertical
        text: SettingsService.locale.toString(clock.date, (root.sizeClass === "small" || root.sizeClass === "icon") ? "ddd, MMM d" : "dddd, MMMM d")
        color: root.textColor
        font.family: Typography.family
        font.pixelSize: (root.sizeClass === "large" ? Typography.headlineSize
            : root.sizeClass === "medium" ? Typography.titleSize : Typography.bodyLargeSize) * root.scaleFactor
        font.weight: Typography.light
        renderType: Typography.renderType
    }

    Column {
        id: stack
        visible: root.vertical
        // No gap: the two lines are one date, and a row's worth of air
        // between them reads as two separate readouts.
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SettingsService.locale.toString(clock.date, "ddd")
            color: root.mutedTextColor
            font.family: Typography.family
            font.pixelSize: Typography.smallSize * root.scaleFactor
            renderType: Typography.renderType
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SettingsService.locale.toString(clock.date, "d")
            color: root.textColor
            font.family: Typography.family
            font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
            font.weight: Typography.semibold
            font.features: { "tnum": 1 }
            renderType: Typography.renderType
        }
    }
}
