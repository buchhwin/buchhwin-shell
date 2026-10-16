import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/workspaces/WorkspaceLogic.js" as Logic
import "../../services/hypr/HiddenWindows.js" as Hidden
import "../../services/model/KeyedLogic.js" as Keyed

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
    // And the fills of a numbered capsule. The theme's surface tints are
    // made for panels: on the notch's black the light theme's `surface2` (a
    // dark tint) left the capsules invisible. The notch hands its own ink, so
    // the fills follow it there - its own button pair, as its controls use.
    readonly property bool onNotch: Qt.colorEqual(root.textColor, Colors.notchText)
    property color fillColor: onNotch ? Colors.notchButton : Colors.surface2
    property color fillHoverColor: onNotch ? Colors.notchHover : Colors.surface2Hover
    // The session's mode, unless this instance names its own: the island
    // preset shows a fixed row of dots whatever the bar does.
    readonly property string mode: root.instance && root.instance.options && root.instance.options.mode
        ? root.instance.options.mode : SettingsService.value("workspaces.mode")
    readonly property var list: Logic.entries(root.mode, SettingsService.value("workspaces.count"),
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
    // The session's style, unless this instance names its own (a notch preset
    // drawing dots while the bar keeps numbers).
    readonly property string style: root.instance && root.instance.options && root.instance.options.style
        ? root.instance.options.style : SettingsService.value("workspaces.style")
    property bool vertical: false
    // One row rather than a column count nothing reaches, which adds a
    // gap to the width (PillBar's zones, round 12 D6).
    rows: vertical ? -1 : 1
    columns: vertical ? 1 : -1
    spacing: Metrics.spaceXs * scaleFactor

    property var lastList: ({ list: [] })
    function keptList(next) {
        const list = Keyed.keep(lastList.list, next, "id")
        lastList.list = list
        return list
    }

    Repeater {
        // Matched by id, not rebuilt: a plain array threw every pip away on
        // each switch, in every screen's notch at once. Kept delegates get
        // their new modelData; the ones that stayed are handed over as the
        // same objects (`keptList`, services/model/KeyedLogic.js), or a
        // workspace that went took its neighbours' pips along.
        model: ScriptModel { values: root.keptList(root.list); objectProp: "id" }
        // A slot rather than the pip itself: a dot is smaller than the row is
        // tall, and a pointer should not have to find a 14 px target. The slot
        // keeps the full height and a hand's width whatever is drawn in it.
        Item {
            id: slot
            required property var modelData
            readonly property bool current: modelData.active
            readonly property bool labelled: Logic.showsLabel(root.style, modelData)
            // "pills": a standing capsule instead of a dot, in a narrower slot.
            readonly property bool pill: !labelled && root.style === "pills"
            readonly property real unit: Metrics.iconMd + Metrics.spaceXs
            implicitHeight: slot.unit * root.scaleFactor
            implicitWidth: Math.max(pip.width, (slot.pill ? Metrics.workspacePillSlot : Metrics.iconMd) * root.scaleFactor)

            Rectangle {
                id: pip
                anchors.centerIn: parent
                // With a number in it the pip is a capsule and the active one
                // stretches. With nothing in it a capsule reads as a number
                // that failed to draw, so it becomes a circle - and the active
                // one says so by being larger rather than longer.
                // A pill stands: narrow, and the active one wider rather than
                // taller, so the row keeps one height.
                // A name is as wide as it needs, up to a cap, and elides past
                // it: "web" spilled out of a 24 px capsule over its
                // neighbours. Down a vertical bar the capsule keeps the
                // strip's width and the name elides inside it.
                readonly property real labelBase: (slot.current ? Metrics.iconXl : slot.unit) * root.scaleFactor
                width: slot.labelled
                    ? (root.vertical ? labelBase
                       : Math.max(labelBase, Math.min(label.implicitWidth + Metrics.spaceSm * root.scaleFactor,
                                                      Metrics.workspaceLabelMax * root.scaleFactor)))
                    : slot.pill
                    ? (slot.current ? Metrics.workspacePillActiveWidth : Metrics.workspacePillWidth) * root.scaleFactor
                    : (slot.current ? Metrics.iconSm : Metrics.iconXs) * root.scaleFactor
                height: slot.labelled ? slot.height : slot.pill ? Metrics.workspacePillHeight * root.scaleFactor : width
                radius: Math.min(width, height) / 2
                // A bare dot takes the muted ink the surface hands over: the
                // theme's surface tint vanished on the notch's black. Under
                // the pointer it takes the full ink - the capsule's hover
                // tint (15 % white) made a dot vanish exactly where it was
                // pointed at.
                color: slot.current ? Colors.accent
                    : slot.labelled ? (pipMouse.containsMouse ? root.fillHoverColor : root.fillColor)
                    : pipMouse.containsMouse ? root.textColor : root.mutedTextColor
                opacity: slot.current || slot.modelData.occupied ? 1 : Effects.mutedOpacity
                // No spring on the width. It never ran while the pips were
                // rebuilt on every switch, and once they were kept it did -
                // and redrawing the notch for every frame of a workspace
                // slide cost 8-9 dropped frames in eight switches against
                // 0-5 without it (measured on a 4K monitor). The pip
                // changes with the slide, which is the motion already on
                // screen.
                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, Math.max(0, parent.width - Metrics.spaceSm * root.scaleFactor))
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: slot.labelled
                    // The number of *this monitor's* set, or a name the user
                    // chose. `id` is the compositor's and can be 23.
                    text: slot.modelData.label
                    color: slot.current ? Colors.accentText : slot.modelData.occupied ? root.textColor : root.mutedTextColor
                    font.family: Typography.family
                    font.pixelSize: Typography.smallSize * root.scaleFactor
                    textFormat: Text.PlainText
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
