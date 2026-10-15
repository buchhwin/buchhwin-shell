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
    // The glyph's neutral ink: what `iconColor` is when there is no state to
    // show. The text's colour unless the surface says otherwise - the notch
    // hands its accent here when asked to (notch.accentGlyphs). A widget whose
    // glyph shows a state (charging, low, unread) colours that state itself and
    // falls back to this, so a surface sets the ink and never `iconColor`:
    // setting that from outside would paint over a warning.
    property color glyphInk: textColor
    // The groove behind the meter. The theme's track is made to sit on a
    // panel; on the black notch it disappears, so the notch hands its own.
    property color trackColor: Colors.track
    property string icon: ""
    property color iconColor: glyphInk
    // A widget may draw its glyph instead of naming one - a signal strength
    // as rising bars, a battery lying down - when the item it is placed as
    // asks for it (`options.glyph`, read by the widget itself). It takes the
    // icon's place; the icon's colour is the widget's to use inside it.
    property Component glyph: null
    property string label: ""
    property int maxLabelWidth: 220
    // The room the surface grants the whole row, in pixels. Below zero it
    // grants none and the caps decide alone, which is every surface that sizes
    // itself to its widget. The notch's overview does not: its cells are the
    // size the user dragged, and a label longer than its cell was cut off
    // mid-letter at the field's edge instead of ending in "…".
    property real availableWidth: -1
    // What the widget is called, shown from `medium` up. Not the value.
    property string name: ""
    // A second line of value, shown at `large`: what is left, how long, where.
    property string detail: ""
    // A ratio between 0 and 1 drawn as a small bar from `medium` up. Below
    // zero there is none, which is most widgets.
    property real meter: -1
    property color meterColor: Colors.accent

    // Across a vertical bar there is room for a short value - "79%", "21°",
    // a count, an elapsed "12:34" - and nothing longer: a window title,
    // "Microphone active" or a hex code kept their 220-640 px cap on a strip
    // 38 px thick. A longer label gives way to the glyph alone. Counted in
    // characters rather than measured, so a battery does not lose its number
    // at 100 % and get it back at 99.
    readonly property int verticalLabelChars: 5
    readonly property bool showsLabel: label.length > 0 && !iconOnly
        && (!vertical || label.length <= verticalLabelChars)
    readonly property bool showsName: !iconOnly && !inGroup
        && (sizeClass === "medium" || sizeClass === "large") && name.length > 0
    readonly property bool showsMeter: !iconOnly && !inGroup
        && (sizeClass === "medium" || sizeClass === "large") && meter >= 0
    readonly property bool showsDetail: !iconOnly && !inGroup
        && sizeClass === "large" && detail.length > 0

    // How that room is shared. The glyph, the name and the meter keep their
    // widths; the label and the detail line split what is left. Both at full
    // length when they fit; otherwise the detail keeps up to a third and the
    // label - the value, which is what the widget is for - takes the rest.
    // Natural widths and the caps only, never the laid-out ones, so no bound
    // feeds back into the width it bounds. Stacked, each line has it all.
    readonly property real fixedWidth: (glyph !== null ? glyphSlot.implicitWidth + columnSpacing : 0)
        + (icon.length > 0 && glyph === null ? iconText.implicitWidth + columnSpacing : 0)
        + (showsName ? nameText.implicitWidth + columnSpacing : 0)
        + (showsMeter ? meterBar.implicitWidth + columnSpacing : 0)
    readonly property real labelCap: maxLabelWidth * scaleFactor
    readonly property real labelNeeds: showsLabel ? Math.min(labelText.implicitWidth, labelCap) : 0
    readonly property real detailNeeds: showsDetail ? Math.min(detailText.implicitWidth, labelCap) : 0
    readonly property real spareWidth: availableWidth - fixedWidth
        - (showsLabel && showsDetail ? columnSpacing : 0)
    readonly property real detailRoom: availableWidth < 0 ? Infinity : vertical ? availableWidth
        : Math.max(0, spareWidth - labelNeeds, Math.min(detailNeeds, spareWidth / 3))
    readonly property real labelRoom: availableWidth < 0 ? Infinity : vertical ? availableWidth
        : Math.max(0, spareWidth - Math.min(detailNeeds, detailRoom))

    // One column stacks, a count nothing will reach lays them in a line.
    columns: vertical ? 1 : 1000
    columnSpacing: Metrics.spaceXs * scaleFactor
    // Tighter than the gap across a row: two lines of a readout are one thing,
    // and the row's own spacing between them reads as two.
    rowSpacing: Metrics.spaceXxs * scaleFactor

    Loader {
        id: glyphSlot
        visible: root.glyph !== null
        active: root.glyph !== null
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        sourceComponent: root.glyph
    }
    Text {
        id: iconText
        visible: root.icon.length > 0 && root.glyph === null
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
        id: nameText
        visible: root.showsName
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        text: root.name
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
        renderType: Typography.renderType
    }
    Text {
        id: labelText
        visible: root.showsLabel
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.maximumWidth: Math.min(root.labelCap, root.labelRoom)
        text: root.label
        elide: Text.ElideRight
        color: root.textColor
        font.family: Typography.family
        font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
        font.features: { "tnum": 1 }
        renderType: Typography.renderType
    }
    Rectangle {
        id: meterBar
        visible: root.showsMeter
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        implicitWidth: Metrics.widgetMeterWidth * root.scaleFactor
        implicitHeight: Metrics.sliderTrack * root.scaleFactor
        radius: height / 2
        color: root.trackColor
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.meter))
            height: parent.height
            radius: parent.radius
            color: root.meterColor
        }
    }
    Text {
        id: detailText
        visible: root.showsDetail
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.maximumWidth: Math.min(root.labelCap, root.detailRoom)
        text: root.detail
        elide: Text.ElideRight
        color: root.mutedTextColor
        font.family: Typography.family
        font.pixelSize: Typography.smallSize * root.scaleFactor
        renderType: Typography.renderType
    }
}
