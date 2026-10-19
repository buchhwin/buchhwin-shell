import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/hypr/PassthroughLogic.js" as Logic

// While the keys go to a window (the keyboard passthrough, Super+Esc): a chip
// in the top right corner of the screen in front, saying where they go and
// which key brings them back. Every key the session would take is the
// window's now, so this is the only thing on screen that says why Super+D
// does nothing. A few seconds in full, then only the key, so it does not sit
// over the remote desktop's own corner; a click gives the keys back too.
//
// Built by shell.qml's LazyLoader only while the passthrough lasts, so it is
// no surface at all the rest of the time. Over a full-screen window (the
// Citrix session) it needs the Overlay layer. It never takes the keyboard:
// that is the window's.
PanelWindow {
    id: chip

    readonly property string key: ShortcutService.keyHint("SUPER + Escape", true)
    readonly property string fullText: Logic.chipText(HyprlandService.passOwnerInfo, key)
    readonly property string shortText: Logic.chipShort(key)
    property bool expanded: true

    screen: PanelService.focusedScreen()
    // Under a bar along the top of that screen, rather than over its
    // right-hand pills (the status, Wi-Fi) - for four seconds in full and
    // then for as long as the keys are away. The notch sits in the middle
    // and leaves the corner free.
    readonly property string screenName: screen ? screen.name : ""
    readonly property real barReach: LayoutService.barShown && !LayoutService.notchShown
        && LayoutService.barEdge(screenName) === "top" ? LayoutService.barBottom(screenName) : -1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true }
    margins {
        top: barReach >= 0 ? barReach + Metrics.spaceSm : Metrics.screenMargin
        right: Metrics.screenMargin
    }
    // Room for the whole text; the pill inside shrinks, the surface does not
    // (a surface resized while shown flashes a frame at its old size).
    implicitWidth: measure.implicitWidth + Metrics.spaceLg * 2 + Metrics.iconMd + Metrics.spaceMd
    implicitHeight: Metrics.pillHeight
    WlrLayershell.namespace: "buchhwin-passthrough"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the pill takes the pointer; the rest of the surface lets every
    // click through to the window under it.
    mask: Region { item: pill }

    Timer { interval: 4000; running: true; onTriggered: chip.expanded = false }

    ShellText {
        id: measure
        visible: false
        text: chip.fullText
        role: "small"
    }

    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        width: (chip.expanded || hover.hovered ? measure.implicitWidth : shortLabel.implicitWidth)
            + Metrics.spaceLg * 2 + Metrics.iconMd + Metrics.spaceMd
        radius: height / 2
        color: Colors.pillFor("osd")
        border.width: Metrics.borderWidth
        border.color: area.containsMouse ? Colors.accentLine : Colors.pillBorder
        Behavior on width { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

        HoverHandler { id: hover }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: HyprlandService.setPassthrough(false)
        }
        Accessible.role: Accessible.Button
        Accessible.name: chip.fullText

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceLg
            anchors.rightMargin: Metrics.spaceLg
            spacing: Metrics.spaceMd
            clip: true
            ShellIcon { glyph: "󰌌"; size: Metrics.iconMd; color: Colors.accentForeground }
            ShellText {
                id: shortLabel
                Layout.fillWidth: true
                text: chip.expanded || hover.hovered ? chip.fullText : chip.shortText
                role: "small"
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }
}
