import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme
import qs.services
import "../../services/LayoutLogic.js" as Logic

// One small layer surface per widget or group. It sits below windows, so it
// is visible on the desktop and never blocks clicks elsewhere.
PanelWindow {
    id: window
    required property var screenModel
    required property string placementId
    readonly property var item: LayoutService.item(placementId)
    readonly property int hoverRoom: Effects.hoverTranslate + Metrics.spaceXxs

    screen: screenModel
    // Focus mode keeps only the clock on the desktop.
    readonly property bool hasClock: item !== null && (item.type === "clock"
        || (item.members !== undefined && LayoutService.members(item.id).some(entry => entry.type === "clock")))
    visible: item !== null && item.visible && LayoutService.widgetsShown && !LayoutService.editMode && frame.hasContent
        && (!AdaptiveService.focusActive || hasClock)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.ceil(frame.implicitWidth)
    implicitHeight: Math.ceil(frame.implicitHeight) + hoverRoom
    anchors { top: true; left: true }
    // screenModel is briefly null while its monitor goes away (lid, unplug).
    readonly property var placementPosition: item && screenModel ? Logic.pixelPosition(item, implicitWidth, implicitHeight,
                                                                screenModel.width, screenModel.height)
                                         : ({ x: 0, y: 0 })
    margins { left: placementPosition ? placementPosition.x : 0; top: placementPosition ? placementPosition.y : 0 }
    WlrLayershell.namespace: "buchhwin-widget"
    WlrLayershell.layer: WlrLayer.Bottom

    onPlacementPositionChanged: report()
    onImplicitWidthChanged: report()
    onImplicitHeightChanged: report()
    function report() {
        if (!placementPosition || !screenModel) return
        LayoutService.reportRect(screenModel.name, placementId,
            { x: placementPosition.x, y: placementPosition.y, width: implicitWidth, height: implicitHeight })
    }

    WidgetFrame {
        id: frame
        y: window.hoverRoom
        item: window.item
        screenOrigin: Qt.point(window.placementPosition ? window.placementPosition.x : 0,
                               window.placementPosition ? window.placementPosition.y : 0)
    }
}
