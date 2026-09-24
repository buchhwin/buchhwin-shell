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

    // One monitor's settings at a time. Three screens meant three stacked
    // copies of resolution, refresh rate, scale and rotation, and the page was
    // mostly a wall of the same four rows.
    //
    // `chosen` rather than `selected` alone: a name can point at a monitor that
    // has just been unplugged, so the page falls back to the focused screen and
    // then to the first rather than showing nothing.
    property string selected: ""
    readonly property string chosen: {
        const names = monitors.map(monitor => monitor.name)
        if (names.indexOf(selected) >= 0) return selected
        const focused = monitors.find(monitor => monitor.focused)
        return focused ? focused.name : (names.length ? names[0] : "")
    }
    property string dragging: ""
    property var frozen: null          // layout box frozen while dragging

    // Monitors may have come or gone since the page was last on screen.
    PageActivity { onOpened: DisplayService.refresh() }

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
                // **A count, not the array.** `enabledMonitors` is a fresh JS
                // array on every draft change, so a Repeater bound to it threw
                // its delegates away and built new ones after every nudge -
                // and the rectangle holding the keyboard went with them. Only
                // the first arrow key after a click ever did anything, which
                // nobody noticed because the test asked whether the draft
                // turned dirty and one press is enough for that.
                //
                // Bound to the length, the delegates are only rebuilt when a
                // monitor really appears or disappears; everything else is a
                // binding that updates in place, and the focus stays put.
                model: root.enabledMonitors.length
                Rectangle {
                    id: monitorRect
                    required property int index
                    readonly property var modelData: root.enabledMonitors[index] || null
                    // Guarded: when a monitor is unplugged the count drops a
                    // frame before the delegate goes, and a binding error here
                    // lands in the log the smoke test reads.
                    readonly property var size: modelData ? DisplayService.logicalSize(modelData)
                                                          : ({ width: 0, height: 0 })
                    readonly property real homeX: modelData
                        ? canvas.offsetX + (modelData.x - canvas.layoutBox.minX) * canvas.factor : 0
                    readonly property real homeY: modelData
                        ? canvas.offsetY + (modelData.y - canvas.layoutBox.minY) * canvas.factor : 0
                    x: dragArea.drag.active ? x : homeX
                    y: dragArea.drag.active ? y : homeY
                    width: size.width * canvas.factor
                    height: size.height * canvas.factor
                    radius: Metrics.radiusInner
                    // The accent belongs to the **selection** now. It used to
                    // mark the screen Hyprland had focused, and two markings
                    // competing for one colour means neither can be read.
                    readonly property bool chosen: modelData !== null && modelData.name === root.chosen
                    color: chosen ? Colors.accentSoft : Colors.elevatedSurface
                    border.width: dragArea.drag.active || chosen ? Metrics.focusBorderWidth : Metrics.borderWidth
                    border.color: dragArea.drag.active || chosen ? Colors.accent : Colors.border
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
                    // Tab selects too, so the keyboard and the pointer mean
                    // the same thing: whatever you land on is what the
                    // settings below are about.
                    onActiveFocusChanged: if (activeFocus && modelData) root.selected = modelData.name
                    Keys.onLeftPressed: event => monitorRect.nudge(-1, 0, event)
                    Keys.onRightPressed: event => monitorRect.nudge(1, 0, event)
                    Keys.onUpPressed: event => monitorRect.nudge(0, -1, event)
                    Keys.onDownPressed: event => monitorRect.nudge(0, 1, event)

                    function nudge(dx, dy, event) {
                        if (!modelData) return
                        const fine = (event.modifiers & Qt.ShiftModifier) !== 0
                        DisplayService.nudge(modelData.name, dx, dy,
                                            fine ? Metrics.nudgeFineStep : Metrics.nudgeStep)
                    }

                    FocusRing { active: monitorRect.activeFocus; controlRadius: monitorRect.radius }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        ShellText { Layout.alignment: Qt.AlignHCenter; text: String(monitorRect.index + 1); role: "headline" }
                        ShellText { Layout.alignment: Qt.AlignHCenter; text: monitorRect.modelData ? monitorRect.modelData.name : ""; role: "caption" }
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
                            if (!monitorRect.modelData) return
                            monitorRect.forceActiveFocus()
                            root.selected = monitorRect.modelData.name
                            root.frozen = canvas.layoutBox
                        }
                        onReleased: {
                            if (monitorRect.modelData && (drag.active || root.frozen)) {
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

    // A disabled monitor has no rectangle on the canvas - it is not in
    // `enabledMonitors` and has no position to draw. With the canvas as the
    // only way to choose, it could never be switched back on, so this row
    // carries **every** monitor.
    SettingsSection {
        Layout.fillWidth: true
        visible: root.monitors.length > 1
        title: "Display"
        description: "Settings below apply to the display you choose here"

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            compact: true
            current: root.chosen
            options: root.monitors.map((monitor, index) => ({
                value: monitor.name,
                label: (index + 1) + " · " + monitor.name + (monitor.disabled ? " (off)" : "")
            }))
            onSelected: value => root.selected = value
        }
    }

    Repeater {
        model: root.monitors
        SettingsSection {
            id: monitorSection
            required property var modelData
            required property int index
            readonly property var monitor: modelData
            // One at a time. An invisible item is left out of the layout, so
            // the others cost nothing but their own bindings.
            visible: monitor.name === root.chosen
            Layout.fillWidth: true
            title: "Display " + (index + 1) + " · " + monitor.name
            description: [monitor.make, monitor.model].filter(value => value && value.length).join(" ")

            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Enabled"
                ShellToggle {
                    focusOnTab: true
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
                    label: "Adaptive sync"
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

    // Off by default, and it changes nothing at all while every screen is at
    // scale 1 - logical and physical are the same size there, so XWayland
    // reports the same either way. It only means something with fractional
    // scaling. There, X11 windows stop being stretched, and X11 is told the
    // real scale through `Xft.dpi` (AppearanceService.applyX11Scale), which
    // only X11 clients read - a toolkit that honours it comes up the right
    // size, one that does not is a third smaller and needs its own scale in
    // whatever launches it. Shown wherever there is a scaled screen, so the
    // question is only asked of the people it can answer.
    SettingsSection {
        Layout.fillWidth: true
        visible: root.monitors.some(monitor => Number(monitor.scale) !== 1)
        title: "X11 applications"
        description: "Applications that do not speak Wayland are drawn by XWayland, which is told the scaled size of a display rather than its real one - so on a screen at 1.5 they render 2560x1440 pixels and the compositor stretches them over 3840x2160. Citrix showed it as an almost unreadable font on a 4K screen and a sharp one on a Full HD screen beside it."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Sharp X11 applications"
            hint: "They draw in real pixels instead of being stretched, and X11 is told the real scale of the largest screen (Xft.dpi, which only X11 applications read). A toolkit that honours it comes up the right size; one that does not is a third smaller and needs its own scale (GDK_SCALE, QT_SCALE_FACTOR) in its launcher. Only applications started afterwards are affected."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("display.xwaylandSharp")
                onToggled: value => SettingsService.set("display.xwaylandSharp", value)
            }
        }
        // X11 has one DPI for all its screens, so this is one number. "Auto"
        // is the largest screen's scale; the others are for a session that is
        // mostly one remote desktop and reads better a step larger than the
        // screen itself. An X11 window on a screen at 1 is that much too
        // large either way - the trade the switch above makes.
        SettingRow {
            Layout.fillWidth: true
            visible: SettingsService.xwaylandSharp
            label: "X11 scale"
            hint: "What X11 is told its screen runs at. Auto follows the largest screen; a step larger makes a remote desktop easier to read. Applications started afterwards pick it up, a Citrix session on its next connection."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.x11ScaleSetting)
                options: [{ value: "0", label: "Auto" }, { value: "1.25", label: "125 %" }, { value: "1.5", label: "150 %" },
                          { value: "1.75", label: "175 %" }, { value: "2", label: "200 %" }]
                onSelected: value => SettingsService.set("display.x11Scale", Number(value))
            }
        }
    }

}
