import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Monitor arrangement and per-monitor modes. Changes form a draft; "Apply"
// applies it and asks to keep it, otherwise it reverts after 15 seconds.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var monitors: DisplayService.draft
    readonly property var enabledMonitors: monitors.filter(monitor => !monitor.disabled)
    property string dragging: ""
    property var frozen: null          // layout box frozen while dragging

    Component.onCompleted: DisplayService.refresh()

    function box() {
        if (frozen) return frozen
        const list = enabledMonitors
        if (!list.length) return { minX: 0, minY: 0, spanX: 1, spanY: 1 }
        const sizes = list.map(monitor => DisplayService.logicalSize(monitor))
        const minX = Math.min.apply(null, list.map(monitor => monitor.x))
        const minY = Math.min.apply(null, list.map(monitor => monitor.y))
        const maxX = Math.max.apply(null, list.map((monitor, index) => monitor.x + sizes[index].width))
        const maxY = Math.max.apply(null, list.map((monitor, index) => monitor.y + sizes[index].height))
        // Leave room around the layout so monitors can be dragged to any side.
        const padX = (maxX - minX) * 0.35, padY = (maxY - minY) * 0.35
        return { minX: minX - padX, minY: minY - padY, spanX: maxX - minX + padX * 2, spanY: maxY - minY + padY * 2 }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Arrangement"
        description: "Drag displays to arrange them. Edges snap together."

        Rectangle {
            id: canvas
            Layout.fillWidth: true
            implicitHeight: Metrics.tileHeight * 3
            radius: Metrics.radiusCard
            color: Colors.surface
            clip: true
            readonly property var layoutBox: root.box()
            readonly property real factor: Math.min(width / Math.max(1, layoutBox.spanX), height / Math.max(1, layoutBox.spanY))
            readonly property real offsetX: (width - layoutBox.spanX * factor) / 2
            readonly property real offsetY: (height - layoutBox.spanY * factor) / 2

            Repeater {
                model: root.enabledMonitors
                Rectangle {
                    id: monitorRect
                    required property var modelData
                    required property int index
                    readonly property var size: DisplayService.logicalSize(modelData)
                    readonly property real homeX: canvas.offsetX + (modelData.x - canvas.layoutBox.minX) * canvas.factor
                    readonly property real homeY: canvas.offsetY + (modelData.y - canvas.layoutBox.minY) * canvas.factor
                    x: dragArea.drag.active ? x : homeX
                    y: dragArea.drag.active ? y : homeY
                    width: size.width * canvas.factor
                    height: size.height * canvas.factor
                    radius: Metrics.radiusInner
                    color: modelData.focused ? Colors.accentSoft : Colors.elevatedSurface
                    border.width: dragArea.drag.active || modelData.focused ? Metrics.focusBorderWidth : Metrics.borderWidth
                    border.color: dragArea.drag.active || modelData.focused ? Colors.accent : Colors.border
                    z: dragArea.drag.active ? 2 : 1

                    // One tab stop per monitor, and the arrows move it. The
                    // handler sits here and not on the panel: the settings
                    // search field owns Up and Down for walking the page list,
                    // and a nudge forwarded from there would fight it.
                    //
                    // Shift is the fine step. Dragging is fine for a rough
                    // arrangement and useless for "this one is twelve pixels
                    // low", which is the whole reason the keys are here.
                    activeFocusOnTab: !DisplayService.confirming
                    Keys.onLeftPressed: event => monitorRect.nudge(-1, 0, event)
                    Keys.onRightPressed: event => monitorRect.nudge(1, 0, event)
                    Keys.onUpPressed: event => monitorRect.nudge(0, -1, event)
                    Keys.onDownPressed: event => monitorRect.nudge(0, 1, event)

                    function nudge(dx, dy, event) {
                        const fine = (event.modifiers & Qt.ShiftModifier) !== 0
                        DisplayService.nudge(modelData.name, dx, dy,
                                            fine ? Metrics.nudgeFineStep : Metrics.nudgeStep)
                    }

                    FocusRing { active: monitorRect.activeFocus; controlRadius: monitorRect.radius }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        ShellText { Layout.alignment: Qt.AlignHCenter; text: String(monitorRect.index + 1); role: "headline" }
                        ShellText { Layout.alignment: Qt.AlignHCenter; text: monitorRect.modelData.name; role: "caption" }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: !DisplayService.confirming && root.enabledMonitors.length > 1
                        cursorShape: enabled ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                        drag.target: monitorRect
                        drag.threshold: Metrics.dragThreshold
                        // Clicking a monitor hands it the keyboard, so the
                        // arrows act on the one you just pointed at.
                        onPressed: {
                            monitorRect.forceActiveFocus()
                            root.frozen = canvas.layoutBox
                        }
                        onReleased: {
                            if (drag.active || root.frozen) {
                                const logicalX = (monitorRect.x - canvas.offsetX) / canvas.factor + canvas.layoutBox.minX
                                const logicalY = (monitorRect.y - canvas.offsetY) / canvas.factor + canvas.layoutBox.minY
                                const snapped = DisplayService.snap(monitorRect.modelData.name, logicalX, logicalY,
                                                                    Metrics.snapThreshold / canvas.factor)
                                DisplayService.setPosition(monitorRect.modelData.name, snapped.x, snapped.y)
                            }
                            root.frozen = null
                        }
                    }
                }
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: DisplayService.overlapping
            text: "Displays overlap. Hyprland moves them itself when you apply."
            role: "small"; color: Colors.warning; wrapMode: Text.Wrap
        }
    }

    Repeater {
        model: root.monitors
        SettingsSection {
            id: monitorSection
            required property var modelData
            required property int index
            readonly property var monitor: modelData
            Layout.fillWidth: true
            title: "Display " + (index + 1) + " · " + monitor.name
            description: [monitor.make, monitor.model].filter(value => value && value.length).join(" ")

            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Enabled"
                ShellToggle {
                    checked: !monitorSection.monitor.disabled
                    enabledState: !DisplayService.confirming && (monitorSection.monitor.disabled || root.enabledMonitors.length > 1)
                    onToggled: value => DisplayService.setEnabled(monitorSection.monitor.name, value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !monitorSection.monitor.disabled
                spacing: Metrics.spaceMd

                SettingRow {
                    label: "Resolution"
                    ShellSelect {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: DisplayService.resolutions(monitorSection.monitor.name)
                        current: monitorSection.monitor.width + "x" + monitorSection.monitor.height
                        onSelected: value => DisplayService.setResolution(monitorSection.monitor.name, value)
                    }
                }
                SettingRow {
                    label: "Refresh rate"
                    SegmentedControl {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: DisplayService.refreshRates(monitorSection.monitor.name)
                        current: monitorSection.monitor.refresh.toFixed(2)
                        onSelected: value => DisplayService.setRefresh(monitorSection.monitor.name, value)
                    }
                }
                SettingRow {
                    label: "Scale"
                    SegmentedControl {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: DisplayService.scaleChoices(monitorSection.monitor.name)
                            .map(scale => ({ value: String(scale), label: Math.round(scale * 100) + "%" }))
                        current: String(monitorSection.monitor.scale)
                        onSelected: value => DisplayService.setScale(monitorSection.monitor.name, value)
                    }
                }
                SettingRow {
                    label: "Orientation"
                    SegmentedControl {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: DisplayService.transforms.map(item => ({ value: String(item.value), label: item.label }))
                        current: String(monitorSection.monitor.transform)
                        onSelected: value => DisplayService.setTransform(monitorSection.monitor.name, value)
                    }
                }
                SettingRow {
                    label: "Adaptive Sync"
                    hint: "VRR / FreeSync"
                    SegmentedControl {
                        focusOnTab: true
                        Layout.fillWidth: true
                        options: DisplayService.vrrModes.map(item => ({ value: String(item.value), label: item.label }))
                        current: String(monitorSection.monitor.vrr)
                        onSelected: value => DisplayService.setVrr(monitorSection.monitor.name, value)
                    }
                }
                SettingRow {
                    label: "Position"
                    ShellText { text: monitorSection.monitor.x + ", " + monitorSection.monitor.y; muted: true }
                }
            }
        }
    }

    // Kept in view by SettingsPanel instead of scrolling with the page: a
    // resolution changed at the top of a long page used to need a scroll to
    // the very end before it could be applied.
    //
    // It names nothing inside this page on purpose. A Component is created by
    // whatever Loader takes it, and the safest thing to hand over is one that
    // only reaches singletons and shared components.
    property Component footer: Component {
        ShellCard {
            highlighted: DisplayService.confirming
            implicitHeight: actionRow.implicitHeight + Metrics.spaceMd * 2

            RowLayout {
                id: actionRow
                anchors.fill: parent
                anchors.margins: Metrics.spaceMd
                spacing: Metrics.spaceSm

                ShellIcon {
                    glyph: DisplayService.confirming ? Icons.busy : "󰍹"
                    size: Metrics.iconMd
                    color: DisplayService.confirming ? Colors.accentForeground : Colors.mutedText
                }
                ShellText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: DisplayService.confirming ? "Keep these display settings? Reverting in " + DisplayService.countdown + " s"
                        : DisplayService.dirty ? "Unsaved changes" : "No changes"
                    muted: !DisplayService.confirming && !DisplayService.dirty
                }
                ShellButton {
                    text: "Identify"
                    focusOnTab: true
                    variant: "ghost"
                    enabledState: !DisplayService.confirming
                    onClicked: DisplayService.identify()
                }
                ShellButton {
                    text: DisplayService.confirming ? "Revert" : "Discard"
                    focusOnTab: true
                    variant: "ghost"
                    enabledState: DisplayService.confirming || DisplayService.dirty
                    onClicked: DisplayService.confirming ? DisplayService.revert() : DisplayService.discard()
                }
                ShellButton {
                    text: DisplayService.confirming ? "Keep" : "Apply"
                    focusOnTab: true
                    variant: "accent"
                    enabledState: DisplayService.confirming || (DisplayService.dirty && DisplayService.valid)
                    onClicked: DisplayService.confirming ? DisplayService.keep() : DisplayService.apply()
                }
            }
        }
    }
}
