import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme
import qs.services
import qs.shell.components

// "Identify" on the Displays page: one surface per monitor, each showing that
// monitor's own number for a few seconds, so the numbered rectangles on the
// arrangement canvas can be matched to the monitors on the desk.
//
// The number comes from `DisplayService.displayNumber(name)` and not from this
// Variants' own index: the draft is sorted by position and `Quickshell.screens`
// is not, so numbering here would label the screens differently from the page
// that sent you looking.
//
// Unlike the colour picker, which this is modelled on, the surface takes no
// keyboard: it appears while Settings is open and in use, and stealing the
// focus would take the arrow keys away from the arrangement.
Variants {
    model: DisplayService.identifying ? Quickshell.screens : []

    PanelWindow {
        id: window
        required property var modelData
        readonly property int number: DisplayService.displayNumber(modelData.name)
        // The mode as the page states it, not as the compositor hands this
        // surface its logical size: the two disagree on a scaled output, and a
        // card that contradicts the page it was opened from is worse than no
        // card. Null until the draft is read.
        readonly property var entry: DisplayService.monitor(modelData.name)

        screen: modelData
        visible: DisplayService.identifying
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "buchhwin-identify"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Nothing here takes input: the pointer has to keep working while this
        // is up, because the thing it belongs to is a page the user is editing.
        mask: Region {}

        Rectangle {
            id: card
            anchors.centerIn: parent
            implicitWidth: Math.max(body.implicitWidth + Metrics.spaceXl * 2, Metrics.identifyCardSize)
            implicitHeight: Math.max(body.implicitHeight + Metrics.spaceXl * 2, Metrics.identifyCardSize)
            radius: Metrics.radiusCard
            color: Colors.pillFor("osd")
            border.width: Metrics.borderWidth
            border.color: Colors.pillBorder
            opacity: DisplayService.identifying ? 1 : 0
            scale: Animations.motionEnabled ? (DisplayService.identifying ? 1 : Effects.hoverScaleFrom) : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: DisplayService.identifying ? Animations.popupOpen : Animations.popupClose
                    easing.type: DisplayService.identifying ? Animations.easingEnter : Animations.easingExit
                }
            }
            Behavior on scale { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

            Column {
                id: body
                anchors.centerIn: parent
                spacing: Metrics.spaceXs

                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: window.number > 0 ? String(window.number) : "?"
                    role: "display"
                }
                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: window.modelData.name
                    role: "bodyLarge"
                }
                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // What the screen actually is, which is the other half of
                    // telling two identical monitors apart.
                    visible: window.entry !== null
                    text: window.entry ? window.entry.width + " × " + window.entry.height : ""
                    role: "caption"
                    muted: true
                }
            }
        }
    }
}
