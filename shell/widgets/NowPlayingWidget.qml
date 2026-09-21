import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Desktop: small shows play state and "title – artist"; medium shows cover,
// title, artist and a play button.
// Groups and pills use a round cover that fills the pill height:
//   icon (Compact)     cover only, the title slides in on hover
//   small (Title)      cover and "title – artist"
//   expanded (Expanded) cover, title and artist on two lines, previous,
//                     play/pause and next
// On a bar that runs down the screen this stacks: the cover above the title.
GridLayout {
    id: root
    property bool vertical: false
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    property bool hasData: MprisService.hasPlayer && MprisService.title.length > 0
    readonly property bool expanded: sizeClass === "expanded"
    readonly property bool compactCover: (inGroup || sizeClass === "icon" || expanded) && MprisService.artUrl.length > 0
    readonly property bool showTitle: sizeClass !== "icon" || (inGroup && hovered)
    columns: vertical ? 1 : 1000
    columnSpacing: Metrics.spaceSm * scaleFactor
    rowSpacing: Metrics.spaceSm * scaleFactor

    RoundedImage {
        visible: root.sizeClass === "medium" && !root.inGroup
        Layout.preferredWidth: Metrics.coverSize * 0.75 * root.scaleFactor
        Layout.preferredHeight: Layout.preferredWidth
        radius: Metrics.radiusInner
        source: visible ? MprisService.artUrl : ""
        sourceWidth: 160
    }

    // Round cover sized to the pill: pill height minus the same inset on
    // every side, so it sits concentric in the pill's round end.
    RoundedImage {
        visible: root.compactCover
        Layout.preferredWidth: (Metrics.pillHeight - Metrics.pillCoverInset * 2) * root.scaleFactor / Metrics.pillContentScale
        Layout.preferredHeight: Layout.preferredWidth
        radius: width / 2
        opacity: MprisService.playing ? 1 : Effects.mutedOpacity
        source: root.compactCover ? MprisService.artUrl : ""
        sourceWidth: 96
        Behavior on opacity { NumberAnimation { duration: Animations.hover } }
    }

    Text {
        visible: !root.compactCover && root.sizeClass !== "medium"
        text: MprisService.playing ? "󰎈" : Icons.pause
        color: Colors.accentForeground
        font.family: Typography.iconFamily
        font.pixelSize: Typography.titleSize * root.scaleFactor
    }

    ColumnLayout {
        id: titles
        visible: root.showTitle
        spacing: 0
        Text {
            Layout.maximumWidth: (root.inGroup ? (root.expanded ? 180 : 200) : 260) * root.scaleFactor
            text: root.sizeClass === "medium" && !root.inGroup || root.expanded ? MprisService.title
                : MprisService.title + (MprisService.artist.length ? " – " + MprisService.artist : "")
            elide: Text.ElideRight
            color: root.textColor
            font.family: Typography.family
            font.pixelSize: (root.expanded ? Typography.smallSize : root.inGroup ? Typography.bodySize : Typography.bodyLargeSize) * root.scaleFactor
            font.weight: root.expanded ? Typography.medium : Typography.regular
            renderType: Typography.renderType
        }
        Text {
            visible: (root.sizeClass === "medium" && !root.inGroup || root.expanded) && MprisService.artist.length > 0
            Layout.maximumWidth: (root.expanded ? 180 : 260) * root.scaleFactor
            text: MprisService.artist
            elide: Text.ElideRight
            color: root.mutedTextColor
            font.family: Typography.family
            font.pixelSize: (root.expanded ? Typography.captionSize : Typography.smallSize) * root.scaleFactor
            renderType: Typography.renderType
        }
    }

    Text {
        visible: root.sizeClass === "medium" && !root.inGroup
        text: MprisService.playing ? Icons.pause : Icons.play
        color: root.textColor
        font.family: Typography.iconFamily
        font.pixelSize: Typography.headlineSize * root.scaleFactor
        MouseArea { anchors.fill: parent; anchors.margins: -Metrics.spaceXs; cursorShape: Qt.PointingHandCursor; onClicked: MprisService.togglePlaying() }
    }

    // Controls of the expanded pill.
    Repeater {
        model: root.expanded ? [
            { icon: Icons.previous, action: "previous" },
            { icon: MprisService.playing ? Icons.pause : Icons.play, action: "toggle" },
            { icon: Icons.next, action: "next" }
        ] : []
        Text {
            required property var modelData
            text: modelData.icon
            color: controlMouse.containsMouse ? Colors.accentForeground : root.textColor
            font.family: Typography.iconFamily
            font.pixelSize: (modelData.action === "toggle" ? Typography.titleSize : Typography.bodyLargeSize) * root.scaleFactor
            renderType: Typography.renderType
            MouseArea {
                id: controlMouse
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXs
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.action === "previous" ? MprisService.previous()
                    : modelData.action === "next" ? MprisService.next() : MprisService.togglePlaying()
            }
        }
    }
}
