import QtQuick
import QtQuick.Layouts
import qs.theme

// Common widget contract (set by WidgetFrame) plus an icon + label row.
//
// Four steps, and each one shows something the one below it did not, rather
// than the same thing larger. `scaleFactor` still grows the type - that is the
// desktop's own size control - but it is not what makes a bigger widget worth
// more:
//
//   icon    the glyph alone (a pill bar set to icon, a one-step grid cell)
//   small   the glyph and the value: "42%", an SSID, a track
//   medium  the name in front of it, so a row of readouts can be read without
//           knowing the glyphs
//   large   and the meter or the detail line, for a widget that has one
//
// A widget that has nothing more to say simply leaves `name`, `meter` and
// `detail` unset and stops growing, which is honest: it is why the registry
// says per type which sizes it offers.
// On a bar that runs down the screen the row becomes a column: the glyph above
// the value instead of beside it. "79%" beside a battery is wider than a strip
// and above it is not, and a widget stacked this way needs no rotation, no
// head tilt and no bar three times as thick. `vertical` is how the surface
// says which it is; a widget that has nothing to change ignores it.
GridLayout {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    property bool vertical: false
    // "icon" (pill bar, icon only) hides the label.
    readonly property bool iconOnly: sizeClass === "icon"
    // Set to false when there is nothing to show; the frame then hides itself.
    property bool hasData: true
    // The surface a widget is drawn on decides its ink. The desktop and the
    // bar are the theme's own surfaces; the notch is black in both themes, so
    // a widget placed there is handed the notch's colours instead of inheriting
    // text that disappears into it in the light theme.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    property string icon: ""
    property color iconColor: textColor
    property string label: ""
    property int maxLabelWidth: 220
    // What the widget is called, shown from `medium` up. Not the value.
    property string name: ""
    // A second line of value, shown at `large`: what is left, how long, where.
    property string detail: ""
    // A ratio between 0 and 1 drawn as a small bar from `medium` up. Below
    // zero there is none, which is most widgets.
    property real meter: -1
    property color meterColor: Colors.accent

    readonly property bool showsName: !iconOnly && !inGroup
        && (sizeClass === "medium" || sizeClass === "large") && name.length > 0
    readonly property bool showsMeter: !iconOnly && !inGroup
        && (sizeClass === "medium" || sizeClass === "large") && meter >= 0
    readonly property bool showsDetail: !iconOnly && !inGroup
        && sizeClass === "large" && detail.length > 0

    // One column stacks, a count nothing will reach lays them in a line.
    columns: vertical ? 1 : 1000
    columnSpacing: Metrics.spaceXs * scaleFactor
    // Tighter than the gap across a row: two lines of a readout are one thing,
    // and the row's own spacing between them reads as two.
    rowSpacing: Metrics.spaceXxs * scaleFactor

    Text {
        visible: root.icon.length > 0
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        text: root.icon
        color: root.iconColor
        font.family: Typography.iconFamily
        font.pixelSize: Typography.titleSize * root.scaleFactor
        renderType: Typography.renderType
    }
    // The name goes in front of the value, muted, so the value is still what
    // the eye lands on.
    Text {
        visible: root.showsName
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        text: root.name
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
        renderType: Typography.renderType
    }
    Text {
        visible: root.label.length > 0 && !root.iconOnly
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.maximumWidth: root.maxLabelWidth * root.scaleFactor
        text: root.label
        elide: Text.ElideRight
        color: root.textColor
        font.family: Typography.family
        font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
        font.features: { "tnum": 1 }
        renderType: Typography.renderType
    }
    Rectangle {
        visible: root.showsMeter
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        implicitWidth: Metrics.widgetMeterWidth * root.scaleFactor
        implicitHeight: Metrics.sliderTrack * root.scaleFactor
        radius: height / 2
        color: Colors.track
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.meter))
            height: parent.height
            radius: parent.radius
            color: root.meterColor
        }
    }
    Text {
        visible: root.showsDetail
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.maximumWidth: root.maxLabelWidth * root.scaleFactor
        text: root.detail
        elide: Text.ElideRight
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.smallSize * root.scaleFactor
        renderType: Typography.renderType
    }
}
