pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "power/BatteryLogic.js" as BatteryLogic
import "power/PowerSourceLogic.js" as PowerSourceLogic
import "power/ChargeLimitLogic.js" as ChargeLimit
import "power/EffectsLogic.js" as EffectsLogic
import "lock/LockLogic.js" as LockLogic

// Battery and power profile state from UPower and power-profiles (tuned-ppd),
// plus low battery warnings, the battery's charge limit and the lighter
// effects on battery.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: device !== null && device.isLaptopBattery
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    // UPower's OnBattery alone is not enough: it is false as soon as any power
    // supply reports itself online, and on laptops with UCSI a USB-C port can
    // stay "online, charging" with nothing plugged in - the panel said
    // "Plugged in" and the mains power settings applied while the battery ran
    // down at 13 W. A battery that is discharging is on battery, whatever else
    // is online.
    readonly property bool onBattery: UPower.onBattery || discharging
    // Charging means charging. PendingCharge is a battery held at its charge
    // threshold on the charger (a laptop with charge thresholds set stops at
    // the upper one): nothing flows, there is no time to full, and it used to
    // read "Charging" in green all day on a docked laptop. It gets the level
    // glyph and the plain ink, and says "Not charging".
    readonly property bool charging: device !== null && device.state === UPowerDeviceState.Charging
    readonly property bool pendingCharge: device !== null && device.state === UPowerDeviceState.PendingCharge
    readonly property bool full: device !== null && device.state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: device !== null && device.state === UPowerDeviceState.Discharging
    readonly property real secondsRemaining: device ? (charging ? device.timeToFull : device.timeToEmpty) : 0

    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property string profileLabel: profile === PowerProfile.PowerSaver ? "Power saver"
        : profile === PowerProfile.Performance ? "Performance" : "Balanced"

    readonly property string icon: {
        if (!hasBattery) return "󰚥"
        // While charging the glyph still shows the level (the bolt variants of
        // the same ten steps); one bolt for every level hid how full it was.
        const levels = charging
            ? ["󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
            : ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return levels[Math.max(0, Math.min(10, Math.round(percent / 10)))]
    }

    // "Charge limit 80% reached" rather than "Not charging" once the limit
    // has been read (below); until then, and without one, as before.
    readonly property string stateLabel: BatteryLogic.stateLabel(stateInput)
    // The same in the control center tile's header, short (BatteryLogic).
    readonly property string stateShort: BatteryLogic.stateLabel(stateInput, true)
    readonly property bool limitReached: BatteryLogic.limitHold(stateInput) === "reached"
    readonly property var stateInput: ({ hasBattery: hasBattery, full: full, charging: charging, onBattery: onBattery,
                                         pendingCharge: pendingCharge, percent: percent, limit: chargeLimit })

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
    // The one "low" every surface draws in the danger colour: the bar widget,
    // the battery popup, the control center's tile and Power page, the clock's
    // hint and the notch's status block. They used to keep thresholds of their
    // own (15 % in three places, 20 and 10 at the clock) while the warning came
    // at the level chosen here, so the battery could be red without a warning
    // or warned about while still drawn in the plain ink. The level counts
    // whether or not the warnings are switched on: it is the user's own idea
    // of "low". Only on battery and not charging - 12 % on the charger is not
    // a problem.
    readonly property bool low: hasBattery && onBattery && !charging && percent <= lowBatteryLevel
    property var batteryState: ({ fired: {} })
    readonly property string batteryInput: [device !== null && device.ready, hasBattery, charging, onBattery,
                                            percent, lowBatteryWarning, lowBatteryLevel].join(",")
    onBatteryInputChanged: batteryCheck.restart()
    Component.onCompleted: {
        batteryCheck.restart()
        sourceCheck.restart()
        pushEffects()
    }

    // The lock screen's process (lock.qml) only shows the battery. Warnings and
    // the power profile are the shell's, and asking IdleService from there
    // started a second one in the lock process, lid handling included
    // (LockLogic.lockProcess). `lockProcess` comes first so that IdleService
    // is never even created there.
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)

    function checkBattery() {
        if (lockProcess || !IdleService.realSession || device === null || !device.ready) return
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
        if (!result.profile.length || lockProcess || !IdleService.realSession) return
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

    // ---- Lighter effects on battery ----------------------------------------
    // Settings > Power, per source: "light" turns the blur off and Full motion
    // into Reduced while that source applies (EffectsLogic). Nothing stored
    // changes: SettingsService.lightEffects is a value of the running shell
    // that Animations and AppearanceService read beside the user's own
    // settings. `effectsPreview` ("keep", "light", "" for none) is IPC's, so
    // a nested session - which cannot unplug the host - can show it.
    readonly property string effectsChoice: EffectsLogic.normal(current("effects"))
    property string effectsPreview: ""
    readonly property bool lightEffects: EffectsLogic.light(effectsChoice, effectsPreview)
    onLightEffectsChanged: pushEffects()
    // Read before it is written: a SettingsService from before the value
    // existed has no such property, and the write would only warn.
    function pushEffects() {
        if (SettingsService.lightEffects === undefined || SettingsService.lightEffects === lightEffects) return
        SettingsService.lightEffects = lightEffects
    }

    // ---- The battery's charge limit ----------------------------------------
    // Read on demand only: when the battery popup, Settings > Power or the
    // control center's Power page opens, when the battery starts waiting on
    // the charger (PendingCharge - the state the limit explains) and after a
    // change. Nothing is read or watched at rest. Shown from sysfs, changed
    // through UPower (ChargeLimitLogic says why both).
    //
    // Not named `battery`: beside a property of that name, `onBattery` above
    // is taken for a handler and its binding never runs (probed offscreen on
    // Qt 6.12: it stays false whatever the charger does), and the shell keeps
    // the charger's settings on battery and warns of no low battery
    // (tests/python/on_property_test.py).
    readonly property var laptopBattery: {
        const list = UPower.devices.values
        for (let i = 0; i < list.length; ++i) {
            if (list[i] && list[i].isLaptopBattery && ChargeLimit.batteryName(list[i].nativePath).length) return list[i]
        }
        return null
    }
    readonly property string batteryNative: laptopBattery ? laptopBattery.nativePath : ""
    readonly property string batteryPath: ChargeLimit.upowerPath(batteryNative)
    property var chargeUpower: null
    property int chargeSysStart: -1
    property int chargeSysEnd: -1
    // The sysfs files are opened at the first read; a machine whose battery
    // has none just reads "unknown".
    property bool chargeSysfsWanted: false
    readonly property var chargeLimit: ChargeLimit.state(chargeUpower, chargeSysStart, chargeSysEnd)
    readonly property string chargeLimitLabel: ChargeLimit.label(chargeLimit)
    readonly property string chargeLimitHint: ChargeLimit.hint(chargeLimit)
    readonly property string chargeOnceHint: ChargeLimit.onceHint(chargeLimit)
    // UPower's answer to the last change that failed ("Access denied" from
    // polkit), "" after one that worked.
    property string chargeLimitError: ""
    // Only the real session changes the host's battery: a nested shell or a
    // sandboxed test sees the limit and leaves it alone.
    readonly property bool chargeWritable: !lockProcess && batteryPath.length > 0 && IdleService.realSession
    readonly property bool chargeBusy: chargeWrite.running

    function refreshChargeLimit() {
        if (lockProcess || !hasBattery || !batteryPath.length) return
        if (chargeRead.running) { chargeRead.again = true; return }
        chargeRead.command = ChargeLimit.readCommand(batteryPath)
        chargeRead.running = true
        if (!chargeSysfsWanted) { chargeSysfsWanted = true; return }
        chargeStartFile.reload()
        chargeEndFile.reload()
    }
    onPendingChargeChanged: if (pendingCharge) refreshChargeLimit()
    // UPower's device list fills in after the display device: a battery
    // already waiting at its limit when the shell starts is asked about once
    // the battery's object is known.
    onBatteryPathChanged: if (pendingCharge && batteryPath.length) refreshChargeLimit()

    Process {
        id: chargeRead
        property bool again: false
        property bool warned: false
        stdout: StdioCollector { id: chargeReadOut }
        stderr: StdioCollector { id: chargeReadErrors }
        onExited: code => {
            const parsed = code === 0 ? ChargeLimit.parseProperties(chargeReadOut.text) : null
            // An older UPower without the properties answers with an error
            // on every read: said once in the log, then shown as unsupported.
            if (!parsed && !warned) {
                warned = true
                console.warn("buchhwin-shell: PowerService.chargeRead:", ChargeLimit.errorText(chargeReadErrors.text))
            }
            root.chargeUpower = parsed
            if (again) { again = false; root.refreshChargeLimit() }
        }
    }
    FileView {
        id: chargeStartFile
        path: root.chargeSysfsWanted ? ChargeLimit.sysfsFile(root.batteryNative, "start") : ""
        printErrors: false
        onLoaded: root.chargeSysStart = ChargeLimit.parseThreshold(text())
        onLoadFailed: root.chargeSysStart = -1
    }
    FileView {
        id: chargeEndFile
        path: root.chargeSysfsWanted ? ChargeLimit.sysfsFile(root.batteryNative, "end") : ""
        printErrors: false
        onLoaded: root.chargeSysEnd = ChargeLimit.parseThreshold(text())
        onLoadFailed: root.chargeSysEnd = -1
    }

    // Settings > Power > "Limit charging". Returns false when nothing was
    // asked (no UPower support, a nested session, a change still running).
    function setChargeLimit(on) {
        if (!chargeWritable || !chargeLimit.supported || chargeWrite.running) return false
        setChargeOnce(false)
        return writeChargeLimit(on === true, "set")
    }

    // "Charge to 100% once": the limit is lifted now and set again when the
    // battery is full or the charger is unplugged (ChargeLimitLogic.onceStep).
    // Kept in settings.json (power.chargeOnce), so a shell restart on the
    // way to 100% still puts the limit back.
    function chargeOnce() {
        if (!chargeWritable || !chargeLimit.supported || !chargeLimit.active || chargeWrite.running) return false
        setChargeOnce(true)
        onceSawCharger = !onBattery
        return writeChargeLimit(false, "once")
    }
    // The limit back now, without waiting for the battery to fill.
    function cancelChargeOnce() {
        if (!chargeOnceActive || !chargeWritable || chargeWrite.running) return false
        return writeChargeLimit(true, "restore")
    }

    // In memory too: without the setting (an older SettingsService) a "once"
    // still ends within this session.
    property bool chargeOnceHeld: false
    readonly property bool chargeOnceActive: chargeOnceHeld || SettingsService.value("power.chargeOnce") === true
    // A "once" found at start counts as charged: a shell that starts on
    // battery with one still set missed the unplug, and the limit goes back
    // rather than lifting it for the next charge as well. One asked for on
    // battery waits for the charger (chargeOnce()).
    property bool onceSawCharger: true
    function setChargeOnce(active) {
        chargeOnceHeld = active
        if (SettingsService.defaultOf("power.chargeOnce") !== undefined) SettingsService.set("power.chargeOnce", active)
    }

    function writeChargeLimit(on, purpose) {
        chargeLimitError = ""
        chargeWrite.purpose = purpose
        chargeWrite.command = ChargeLimit.enableCommand(batteryPath, on)
        chargeWrite.running = true
        return true
    }
    Process {
        id: chargeWrite
        property string purpose: ""
        // The refusal last said in the log: a restore that polkit keeps
        // refusing is tried again at every change of the battery, and one
        // line for it is enough.
        property string warned: ""
        stderr: StdioCollector { id: chargeWriteErrors }
        onExited: code => {
            if (code === 0) {
                root.chargeLimitError = ""
                warned = ""
                // A "once" ends when its limit is back, not when it was asked
                // for: refused by polkit, it is tried again at the next change
                // rather than leaving the battery to charge to 100% for good.
                if (purpose === "restore") root.setChargeOnce(false)
            } else {
                root.chargeLimitError = ChargeLimit.errorText(chargeWriteErrors.text)
                if (warned !== root.chargeLimitError) {
                    warned = root.chargeLimitError
                    console.warn("buchhwin-shell: PowerService.chargeWrite:", root.chargeLimitError)
                }
                if (purpose === "once") root.setChargeOnce(false)
            }
            root.refreshChargeLimit()
        }
    }

    // Only while a "once" runs; read lazily, so nothing is joined at rest.
    readonly property string onceInput: chargeOnceActive
        ? [sourceReady, hasBattery, onBattery, full, charging, percent].join(",") : ""
    onOnceInputChanged: if (onceInput.length) onceCheck.restart()
    Timer {
        id: onceCheck
        interval: 500
        onTriggered: {
            if (!root.chargeOnceActive || !root.sourceReady || !root.chargeWritable || chargeWrite.running) return
            const result = ChargeLimit.onceStep({ active: true, sawCharger: root.onceSawCharger },
                                                { hasBattery: root.hasBattery, onBattery: root.onBattery, full: root.full,
                                                  charging: root.charging, percent: root.percent })
            root.onceSawCharger = result.state.sawCharger
            if (result.restore) root.writeChargeLimit(true, "restore")
        }
    }
}
