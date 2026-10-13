import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "../../services/notch/NotchLogic.js" as NotchLogic

// How the notch opens, shown the same in the layout editor and on the Bar &
// Notch page: the mode, what a click does and the two delays. Each change is
// an undo step (LayoutService.changeNotch), wherever it was made.
ColumnLayout {
    id: root
    spacing: Metrics.spaceSm

    readonly property string mode: NotchService.hoverMode
    function set(key, value) { LayoutService.changeNotch("notch." + key, value) }

    SettingRow {
        Layout.fillWidth: true
        label: "Opens"
        hint: root.mode === "hover" ? "When the pointer rests on it"
            : root.mode === "click" ? "Only when it is clicked"
            : "Never; a click opens the dashboard"
        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: root.mode
            options: [{ value: "hover", label: "Hover" }, { value: "click", label: "Click" }, { value: "off", label: "Never" }]
            onSelected: value => root.set("hoverMode", value)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        visible: root.mode === "hover"
        label: "Click"
        hint: "What a click on the collapsed notch opens"
        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: NotchService.clickAction
            options: [{ value: "dashboard", label: "Dashboard" }, { value: "expand", label: "Overview" }]
            onSelected: value => root.set("clickAction", value)
        }
    }
    SettingRow {
        id: openRow
        Layout.fillWidth: true
        visible: root.mode === "hover"
        label: "Open after"
        hint: Math.round(openSlider.pressed ? openSlider.liveValue : NotchService.openDelay) + " ms"
        ShellSlider {
            id: openSlider
            focusOnTab: true
            Layout.fillWidth: true
            from: NotchLogic.OPEN_DELAY.min; to: NotchLogic.OPEN_DELAY.max
            value: NotchService.openDelay
            onReleased: value => root.set("openDelay", Math.round(value / 10) * 10)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        visible: root.mode !== "off"
        label: "Close after"
        hint: Math.round(closeSlider.pressed ? closeSlider.liveValue : NotchService.closeDelay) + " ms once the pointer leaves"
        ShellSlider {
            id: closeSlider
            focusOnTab: true
            Layout.fillWidth: true
            from: NotchLogic.CLOSE_DELAY.min; to: NotchLogic.CLOSE_DELAY.max
            value: NotchService.closeDelay
            onReleased: value => root.set("closeDelay", Math.round(value / 10) * 10)
        }
    }
}
