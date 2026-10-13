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
    // The other two buttons. Off unless chosen; the left click above is not
    // touched by them.
    readonly property var buttonOptions: [
        { value: "none", label: "Nothing" }, { value: "dashboard", label: "Dashboard" },
        { value: "controlCenter", label: "Quick settings" }, { value: "notifications", label: "Notifications" },
        { value: "launcher", label: "Launcher" }, { value: "clipboard", label: "Clipboard" },
        { value: "mediaPopup", label: "Media" }, { value: "playPause", label: "Play / pause" },
        { value: "overview", label: "Workspaces overview" }
    ]
    SettingRow {
        Layout.fillWidth: true
        label: "Middle click"
        hint: "On the collapsed notch"
        ShellSelect {
            focusOnTab: true
            Layout.fillWidth: true
            options: root.buttonOptions
            current: NotchService.middleAction
            onSelected: value => root.set("middleAction", value)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Right click"
        hint: "On the collapsed notch"
        ShellSelect {
            focusOnTab: true
            Layout.fillWidth: true
            options: root.buttonOptions
            current: NotchService.rightAction
            onSelected: value => root.set("rightAction", value)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        visible: NotchService.shape !== "pill"
        label: "Panels open"
        hint: NotchService.panelsFromNotch ? "Out of the notch, which makes way for them"
                                           : "Below the notch"
        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: SettingsService.value("notch.panelOrigin")
            options: [{ value: "below", label: "Below" }, { value: "notch", label: "Out of the notch" }]
            onSelected: value => root.set("panelOrigin", value)
        }
    }
    SettingRow {
        Layout.fillWidth: true
        labelFills: true
        label: "Swipe between pages"
        hint: "Scroll or swipe on the collapsed notch: the date on the left, what is playing on the right"
        ShellToggle { focusOnTab: true; checked: NotchService.swipe; onToggled: value => root.set("swipe", value) }
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
