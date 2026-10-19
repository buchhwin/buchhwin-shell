import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/tray/TrayLogic.js" as Logic

// The tray: an icon for every background app that has something to show,
// with a dot on the ones asking for attention. A left click is the app's own
// (most open their window), a middle click its second action, a right click
// opens its menu in the shell's own popup, growing out of the icon, and the
// wheel goes to the app (a volume, a page). Passive items stay off it; the
// control center's "Background apps" page lists everything.
//
// Costs one small item per icon on each screen it is placed on: the items
// come from TrayService, which runs anyway for that page.
Grid {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    property bool vertical: false
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    // The dot's ink: the theme's warning on a panel, its on-dark one on the
    // notch's black (WidgetBase.warningInk).
    property bool onDark: false
    readonly property color attentionInk: onDark ? Colors.warningOnDark : Colors.warning
    readonly property bool hasData: TrayService.shownItems.length > 0

    readonly property real iconSize: Metrics.iconSm * scaleFactor
    rows: vertical ? -1 : 1
    columns: vertical ? 1 : -1
    spacing: Metrics.spaceXs * scaleFactor

    // Where this widget's window sits on its screen (TrayLogic.surfaceOrigin):
    // read at the click, from the window the widget is in.
    function screenRect(item) {
        const window = root.QsWindow.window
        const inWindow = item.mapToItem(null, 0, 0)
        const screen = window && window.screen ? window.screen : null
        const origin = window && window.anchors !== undefined && screen
            ? Logic.surfaceOrigin(window.anchors, window.margins, { width: window.width, height: window.height },
                                  { width: screen.width, height: screen.height })
            : { x: 0, y: 0 }
        return { x: origin.x + inWindow.x, y: origin.y + inWindow.y, width: item.width, height: item.height,
                 screenHeight: screen ? screen.height : 0, screenName: screen ? screen.name : "",
                 edge: window && window.anchors !== undefined ? Logic.surfaceEdge(window.anchors) : "" }
    }

    Repeater {
        // The items themselves, kept by identity: a status change in one
        // does not rebuild the others.
        model: ScriptModel { values: TrayService.shownItems }
        Item {
            id: icon
            required property var modelData
            readonly property bool attention: modelData.status === Status.NeedsAttention
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            Image {
                anchors.fill: parent
                source: icon.modelData.icon
                sourceSize.width: Math.ceil(root.iconSize * 2)
                sourceSize.height: Math.ceil(root.iconSize * 2)
                asynchronous: true
                smooth: true
            }
            // A dot in the corner, the way the bell marks unread ones.
            Rectangle {
                visible: icon.attention
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -Metrics.spaceXxs
                anchors.topMargin: -Metrics.spaceXxs
                width: Metrics.dotSize * root.scaleFactor
                height: width
                radius: width / 2
                color: root.attentionInk
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXxs
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // The app's name, where the surface has a layer for bubbles;
                // every way out takes it down (ToolTipHost).
                onEntered: tip.arm()
                onExited: tip.release()
                onClicked: mouse => {
                    tip.release()
                    const button = mouse.button === Qt.RightButton ? "right" : mouse.button === Qt.MiddleButton ? "middle" : "left"
                    let args = {}
                    if (Logic.clickAction(button, icon.modelData.onlyMenu, icon.modelData.hasMenu) === "menu") {
                        const rect = root.screenRect(icon)
                        // Whether the bar (or the notch) is on the edge this
                        // surface hangs from: then it is the bar itself.
                        const barAtEdge = (LayoutService.notchShown && rect.edge === "top")
                            || (LayoutService.barShown && LayoutService.barEdge(rect.screenName) === rect.edge)
                        args = Logic.menuArgs(rect, rect.screenHeight, Metrics.spaceSm, rect.screenName, rect.edge, barAtEdge)
                    }
                    TrayService.click(icon.modelData, button, args)
                }
                onWheel: wheel => icon.modelData.scroll(wheel.angleDelta.y, false)
            }
            ToolTipHost {
                id: tip
                anchorItem: icon
                text: Logic.label(icon.modelData)
            }
        }
    }
}
