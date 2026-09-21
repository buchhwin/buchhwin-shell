import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "../../services/workspaces/WorkspaceLogic.js" as Logic
import "../../services/hypr/HiddenWindows.js" as Hidden

// Workspaces of this widget's monitor; the focused one is highlighted. Settings
// > Bar & Notch chooses which workspaces are shown (the open ones, the open
// ones with the gaps filled, or a fixed number of slots - empty slots are
// dimmed and clicking one creates it) and how they are drawn (numbers, dots,
// or a dot for the one you are on).
// A row of pips across the bar, a column of them down it. `Grid` rather than a
// Row and a Column side by side: one element that can be either, so the pips,
// the styles and the click handling exist once.
Grid {
    id: root
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
    readonly property var list: Logic.entries(SettingsService.value("workspaces.mode"), SettingsService.value("workspaces.count"),
        HyprlandService.workspaces.map(workspace => ({
            id: workspace.id,
            name: workspace.name,
            windows: Hidden.visibleCount(workspace.toplevels.values.map(toplevel => ({
                appId: toplevel.wayland ? toplevel.wayland.appId : "",
                ipcClass: toplevel.lastIpcObject ? toplevel.lastIpcObject.class : ""
            }))),
            screen: workspace.monitor ? workspace.monitor.name : ""
        })),
        instance ? instance.screen : "",
        // This screen's own active workspace, not the globally focused one:
        // with three bars, comparing against the global focus left two of them
        // showing no active pip at all.
        HyprlandService.activeWorkspaceOn(instance ? instance.screen : ""),
        HyprlandService.offsetFor(instance ? instance.screen : ""),
        HyprlandService.focusedWorkspace !== null ? HyprlandService.focusedWorkspace.id : -1)
    readonly property string style: SettingsService.value("workspaces.style")
    property bool vertical: false
    columns: vertical ? 1 : 1000
    spacing: Metrics.spaceXs * scaleFactor

    Repeater {
        model: root.list
        // A slot rather than the pip itself: a dot is smaller than the row is
        // tall, and a pointer should not have to find a 14 px target. The slot
        // keeps the full height and a hand's width whatever is drawn in it.
        Item {
            id: slot
            required property var modelData
            readonly property bool current: modelData.active
            readonly property bool labelled: Logic.showsLabel(root.style, modelData)
            readonly property real unit: Metrics.iconMd + Metrics.spaceXs
            implicitHeight: slot.unit * root.scaleFactor
            implicitWidth: Math.max(pip.width, Metrics.iconMd * root.scaleFactor)

            Rectangle {
                id: pip
                anchors.centerIn: parent
                // With a number in it the pip is a capsule and the active one
                // stretches. With nothing in it a capsule reads as a number
                // that failed to draw, so it becomes a circle - and the active
                // one says so by being larger rather than longer.
                width: slot.labelled
                    ? (slot.current ? Metrics.iconXl : slot.unit) * root.scaleFactor
                    : (slot.current ? Metrics.iconSm : Metrics.iconXs) * root.scaleFactor
                height: slot.labelled ? slot.height : width
                radius: height / 2
                color: slot.current ? Colors.accent : pipMouse.containsMouse ? Colors.surface2Hover : Colors.elevatedSurface
                opacity: slot.current || slot.modelData.occupied ? 1 : Effects.mutedOpacity
                // The pip width is the widget's width, so every frame resizes
                // the widget's layer surface and re-reports its rectangle.
                // Reduced and Off skip it like the other movements.
                Behavior on width {
                    enabled: Animations.motionEnabled
                    NumberAnimation { duration: Animations.navigation; easing.type: Animations.easing }
                }
                Text {
                    anchors.centerIn: parent
                    visible: slot.labelled
                    // The number of *this monitor's* set, or a name the user
                    // chose. `id` is the compositor's and can be 23.
                    text: slot.modelData.label
                    color: slot.current ? Colors.accentText : slot.modelData.occupied ? root.textColor : Colors.subtleText
                    font.family: Typography.family
                    font.pixelSize: Typography.smallSize * root.scaleFactor
                    renderType: Typography.renderType
                }
            }
            MouseArea {
                id: pipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HyprlandService.focusWorkspace(slot.modelData.id)
            }
        }
    }
}
