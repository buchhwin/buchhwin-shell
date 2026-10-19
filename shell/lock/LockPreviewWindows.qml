import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme

// The lock face in ordinary layer windows on every screen, in place of the
// session lock, for nested screenshots (LockScreen.preview). lock.qml makes
// them only while previewing. They live in a file of their own because a file
// that names PanelWindow does not load offscreen at all ("No PanelWindow
// backend loaded"), and LockScreen is tested there.
Scope {
    id: root
    required property var lockState

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: previewWindow
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Colors.lockBase
            WlrLayershell.namespace: "buchhwin-lock-preview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            LockFace {
                anchors.fill: parent
                lockState: root.lockState
                screenName: previewWindow.modelData.name
            }
        }
    }
}
