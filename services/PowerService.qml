pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "power/BatteryLogic.js" as BatteryLogic
import "power/PowerSourceLogic.js" as PowerSourceLogic

// Battery and power profile state from UPower and power-profiles (tuned-ppd),
// plus low battery warnings.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: device !== null && device.isLaptopBattery
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool onBattery: UPower.onBattery
    readonly property bool charging: device !== null && (device.state === UPowerDeviceState.Charging
        || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: device !== null && device.state === UPowerDeviceState.FullyCharged
    readonly property real secondsRemaining: device ? (charging ? device.timeToFull : device.timeToEmpty) : 0

    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property string profileLabel: profile === PowerProfile.PowerSaver ? "Power saver"
        : profile === PowerProfile.Performance ? "Performance" : "Balanced"

    readonly property string icon: {
        if (!hasBattery) return "󰚥"
        if (charging) return "󰂄"
        const levels = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return levels[Math.max(0, Math.min(10, Math.round(percent / 10)))]
    }

    readonly property string stateLabel: !hasBattery ? "AC power"
        : full ? "Fully charged"
        : charging ? "Charging" : onBattery ? "On battery" : "Plugged in"

    function formatDuration(seconds) {
        if (!seconds || seconds <= 0) return ""
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.round((seconds % 3600) / 60)
        return hours > 0 ? hours + " h " + minutes + " min" : minutes + " min"
    }

    readonly property string remainingLabel: {
        const text = formatDuration(secondsRemaining)
        if (!text.length || full || (!charging && !onBattery)) return ""
        return charging ? "full in " + text : text + " left"
    }

    function setProfile(value) {
        if (value === PowerProfile.Performance && !hasPerformance) return
        PowerProfiles.profile = value
    }

    // Low battery warnings (Settings > Power), sent through notify-send to the
    // shell's own notification server. Only in the real session: nested tests
    // would otherwise notify Plasma about the host battery.
    readonly property bool lowBatteryWarning: SettingsService.value("power.lowBatteryWarning")
    readonly property int lowBatteryLevel: BatteryLogic.lowLevel(SettingsService.value("power.lowBatteryLevel"))
    property var batteryState: ({ fired: {} })
    readonly property string batteryInput: [device !== null && device.ready, hasBattery, charging, onBattery,
                                            percent, lowBatteryWarning, lowBatteryLevel].join(",")
    onBatteryInputChanged: batteryCheck.restart()
    Component.onCompleted: {
        batteryCheck.restart()
        sourceCheck.restart()
    }

    function checkBattery() {
        if (!IdleService.realSession || device === null || !device.ready) return
        const discharging = hasBattery && onBattery && !charging && !full
        if (!discharging) dismissBatteryWarnings()
        const result = BatteryLogic.update(batteryState, {
            hasBattery: hasBattery, discharging: discharging, percent: percent,
            enabled: lowBatteryWarning, level: lowBatteryLevel
        })
        batteryState = result.state
        if (!result.warning) return
        dismissBatteryWarnings()
        const text = BatteryLogic.message(result.warning.kind, percent, remainingLabel)
        Quickshell.execDetached(["notify-send", "--app-name=Power", "--icon=" + text.icon,
                                 "--urgency=" + text.urgency, "--", text.title, text.body])
    }

    // An older battery warning is replaced by the next one and closes once
    // the charger is connected.
    function dismissBatteryWarnings() {
        const list = NotificationService.history
        for (let i = list.length - 1; i >= 0; --i) {
            const item = list[i]
            if (item && item.appName === "Power" && BatteryLogic.TITLES.indexOf(item.summary) >= 0) item.dismiss()
        }
    }

    // UPower updates several properties at once; evaluate them together.
    Timer {
        id: batteryCheck
        interval: 500
        onTriggered: root.checkBattery()
    }

    // Separate settings for battery and charger (Settings > Power). `source`
    // is "battery" or "ac"; the idle times, dimming and the lid action in
    // IdleService follow it immediately.
    readonly property string source: PowerSourceLogic.source(hasBattery, onBattery)
    // Source shown in Settings > Power ("" = the active one); IPC can set it.
    property string pageSource: ""

    function sourceValue(name, key) { return SettingsService.value("power." + name + "." + key) }
    function setSourceValue(name, key, value) { return SettingsService.set("power." + name + "." + key, value) }
    function current(key) { return sourceValue(source, key) }

    // The chosen profile of a source is applied when the source changes and
    // when the choice itself changes (real session only). The second half is
    // why `profileChoice` is in `sourceInput`: without it the timer never ran
    // for a setting the user had just changed, so choosing "Performance" for
    // the charger while on the charger did nothing until the next unplug.
    readonly property string profileChoice: current("profile")
    readonly property bool sourceReady: device !== null && device.ready
    property var sourceState: ({ source: "", choice: "" })
    readonly property string sourceInput: [sourceReady, source, profileChoice].join(",")
    onSourceInputChanged: sourceCheck.restart()

    function checkSource() {
        const result = PowerSourceLogic.profileChange(sourceState, { ready: sourceReady, source: source, choice: profileChoice })
        sourceState = result.state
        if (!result.profile.length || !IdleService.realSession) return
        const profiles = { powerSaver: PowerProfile.PowerSaver, balanced: PowerProfile.Balanced, performance: PowerProfile.Performance }
        setProfile(profiles[result.profile])
    }

    Timer {
        id: sourceCheck
        interval: 500
        onTriggered: root.checkSource()
    }

    function cycleProfile() {
        const order = hasPerformance
            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            : [PowerProfile.PowerSaver, PowerProfile.Balanced]
        const index = order.indexOf(profile)
        setProfile(order[(index + 1) % order.length])
    }
}
