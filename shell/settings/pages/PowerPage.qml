import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/power/StayAwakeLogic.js" as StayAwakeLogic

ColumnLayout {
    id: page
    spacing: Metrics.pageGap

    // Idle, lid and automatic profile settings exist once for battery and
    // once for the charger; the switch below picks the set these rows edit.
    // Machines without a battery only have the "ac" set.
    readonly property string source: !PowerService.hasBattery ? "ac"
        : PowerService.pageSource.length ? PowerService.pageSource : PowerService.source
    readonly property string sourceLabel: source === "battery" ? "On battery" : "Plugged in"
    function sourceValue(key) { return PowerService.sourceValue(source, key) }
    function setSourceValue(key, value) { PowerService.setSourceValue(source, key, value) }
    // The page opens on the active source again next time. The charge limit
    // is read each time the page is shown, and only then.
    PageActivity {
        onOpened: PowerService.refreshChargeLimit()
        onClosed: PowerService.pageSource = ""
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Battery"
        description: PowerService.remainingLabel.length ? PowerService.remainingLabel : ""

        // Charging, low or the page's ink, as in the control center's Power
        // page: a state colour only when there is a state to show.
        RowLayout {
            spacing: Metrics.spaceMd
            ShellIcon {
                glyph: PowerService.icon; size: Metrics.iconXl
                color: PowerService.charging ? Colors.positive : PowerService.low ? Colors.danger : Colors.text
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: PowerService.hasBattery ? PowerService.percent + "%" : "AC power"; role: "headline" }
                ShellText { text: PowerService.stateLabel; role: "small"; muted: true }
            }
            ShellText {
                visible: PowerService.device !== null && PowerService.device.healthPercentage > 0
                text: PowerService.device ? "Health " + Math.round(PowerService.device.healthPercentage) + "%" : ""
                role: "small"; muted: true
            }
        }

        // The charge limit, shown from the kernel and changed through UPower
        // (PowerService, ChargeLimitLogic). A limit UPower cannot change -
        // set in the firmware or by another tool on an older UPower - is
        // still named, so "Not charging" at 80% has its reason.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: PowerService.hasBattery && PowerService.chargeLimit.supported
            label: "Limit charging"
            // A test session never writes the limit (chargeWritable).
            hint: PowerService.chargeLimitHint
                + (PowerService.chargeLimit.supported && !PowerService.chargeWritable ? ". A test session leaves the battery's limit alone" : "")
            ShellToggle {
                focusOnTab: true
                checked: PowerService.chargeLimit.active && !PowerService.chargeOnceActive
                enabledState: PowerService.chargeWritable && !PowerService.chargeBusy
                onToggled: value => PowerService.setChargeLimit(value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: PowerService.hasBattery && PowerService.chargeLimit.supported
                && (PowerService.chargeLimit.active || PowerService.chargeOnceActive)
            label: "Charge to 100% once"
            hint: PowerService.chargeOnceHint
            ShellButton {
                focusOnTab: true
                compact: true
                // The verb, not the label beside it again.
                text: PowerService.chargeOnceActive ? "Keep the limit" : "Charge once"
                enabledState: PowerService.chargeWritable && !PowerService.chargeBusy
                onClicked: PowerService.chargeOnceActive ? PowerService.cancelChargeOnce() : PowerService.chargeOnce()
            }
        }
        // What the limit is doing that the switches do not show: a refusal,
        // a charge to full under way, a limit set outside the shell. What
        // "once" means is in its row's hint.
        ShellText {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.Wrap
            role: "small"
            color: PowerService.chargeLimitError.length ? Colors.warning : Colors.mutedText
            text: !PowerService.hasBattery ? ""
                : PowerService.chargeLimitError.length ? "UPower refused the change: " + PowerService.chargeLimitError
                : PowerService.chargeOnceActive ? "Charging to 100% once"
                : PowerService.chargeLimit.active && !PowerService.chargeLimit.supported
                    ? PowerService.chargeLimitLabel + ", set outside the shell (UPower cannot change it here)"
                : ""
        }

        // What every good state in the shell wears (Colors.positive): the
        // battery on the bar, the notch, the popup, the control center and
        // the lock screen, the clock's charging hint and a VPN that is up.
        // Here because the battery is where the green shows most. Shown
        // without a battery too: the tunnel follows it as well. The bad
        // states are not part of the choice - they keep red and amber.
        SettingRow {
            label: "Status colors"
            hint: "Charging and a connected VPN in green or in the accent; a low battery stays red"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("appearance.statusColors")
                options: [{ value: "status", label: "Green" }, { value: "accent", label: "Accent" }]
                onSelected: value => SettingsService.set("appearance.statusColors", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: PowerService.hasBattery
        title: "Low battery"
        scope: "power"
        hint: "Warnings while running on battery; below 10% and 5% they stay until you close them"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Low battery warnings"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("power.lowBatteryWarning")
                onToggled: value => SettingsService.set("power.lowBatteryWarning", value)
            }
        }
        SettingRow {
            label: "Warn at"
            enabled: SettingsService.value("power.lowBatteryWarning")
            opacity: enabled ? 1 : Effects.disabledOpacity
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("power.lowBatteryLevel"))
                options: [{ value: "10", label: "10%" }, { value: "15", label: "15%" }, { value: "20", label: "20%" }, { value: "25", label: "25%" }]
                onSelected: value => SettingsService.set("power.lowBatteryLevel", parseInt(value))
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Power profile"
        hint: "Balance performance against battery life and fan noise"

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: String(PowerService.profile)
            options: [
                { value: String(PowerProfile.PowerSaver), label: "Power saver", icon: "󰌪" },
                { value: String(PowerProfile.Balanced), label: "Balanced", icon: "󰾅" }
            ].concat(PowerService.hasPerformance ? [{ value: String(PowerProfile.Performance), label: "Performance", icon: "󰓅" }] : [])
            onSelected: value => PowerService.setProfile(parseInt(value))
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Sleep"
        scope: "power"
        hint: PowerService.hasBattery ? "These apply on battery and when plugged in" : ""

        // How long, as on the control center's Power page; the battery
        // popup's switch and the control center's tile start the last choice
        // made here or there again.
        SettingRow {
            label: "Stay awake"
            hint: "Pauses screen off, lock and sleep. The switch in the battery popup starts the last choice again; a restart of the shell ends it"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: IdleService.stayAwakeMode
                // The control center's words (StayAwakeLogic.title).
                options: StayAwakeLogic.MODES.filter(mode => mode === "off" || mode === "1h" || mode === "manual"
                                                     || IdleService.stayAwakeMode === mode || IdleService.stayAwakeOffered(mode))
                    .map(mode => ({ value: mode, label: StayAwakeLogic.title(mode) }))
                onSelected: value => IdleService.chooseStayAwake(value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: IdleService.stayAwakeMode === "1h"
            text: IdleService.stayAwakeSubtitle
            role: "small"; muted: true
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Lock before sleep"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("power.lockBeforeSleep")
                onToggled: value => SettingsService.set("power.lockBeforeSleep", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: PowerService.hasBattery
        title: "Battery and charger"
        hint: "The settings below are kept separately for each; plugging in or unplugging switches between them right away."

        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: page.source
            options: [
                { value: "battery", label: "On battery", icon: "󰁹", badge: PowerService.source === "battery" ? "Current" : "" },
                { value: "ac", label: "Plugged in", icon: "󰚥", badge: PowerService.source === "ac" ? "Current" : "" }
            ]
            onSelected: value => PowerService.pageSource = value
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "When idle"
        scope: "power"
        // Which set the rows edit stays in sight, as on the lid's section.
        description: PowerService.hasBattery ? page.sourceLabel : ""
        hint: "Apps that are playing video prevent this automatically."

        SettingRow {
            label: "Screen off"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(page.sourceValue("screenOffMinutes"))
                options: [{ value: "0", label: "Never" }, { value: "5", label: "5 min" }, { value: "10", label: "10 min" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }]
                onSelected: value => page.setSourceValue("screenOffMinutes", parseInt(value))
            }
        }
        SettingRow {
            label: "Lock"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(page.sourceValue("lockMinutes"))
                options: [{ value: "0", label: "Never" }, { value: "5", label: "5 min" }, { value: "10", label: "10 min" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }]
                onSelected: value => page.setSourceValue("lockMinutes", parseInt(value))
            }
        }
        SettingRow {
            label: "Screen off when locked"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(page.sourceValue("lockedScreenOffMinutes"))
                options: [{ value: "0", label: "Never" }, { value: "1", label: "1 min" }, { value: "2", label: "2 min" }, { value: "5", label: "5 min" }]
                onSelected: value => page.setSourceValue("lockedScreenOffMinutes", parseInt(value))
            }
        }
        SettingRow {
            label: "Sleep"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(page.sourceValue("suspendMinutes"))
                options: [{ value: "0", label: "Never" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }, { value: "60", label: "1 h" }]
                onSelected: value => page.setSourceValue("suspendMinutes", parseInt(value))
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: BrightnessService.available
            label: "Dim before screen off"
            hint: "Lowers the laptop brightness 30 seconds before the screen turns off"
            ShellToggle {
                focusOnTab: true
                checked: page.sourceValue("dimBeforeScreenOff")
                onToggled: value => page.setSourceValue("dimBeforeScreenOff", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: PowerService.hasBattery ? "Lid and power profile" : "Lid"
        scope: "power"
        description: PowerService.hasBattery ? page.sourceLabel : ""

        SettingRow {
            label: "When the lid closes"
            hint: page.sourceValue("lidAction") === "screenOff"
                ? "Everything keeps running and only the laptop screen turns off; on a docking station the windows move to the external display"
                : "With an external display connected the laptop stays awake and its screen turns off"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.sourceValue("lidAction")
                options: [{ value: "suspend", label: "Sleep" }, { value: "lock", label: "Lock only" }, { value: "screenOff", label: "Screen off" }, { value: "nothing", label: "Nothing" }]
                onSelected: value => page.setSourceValue("lidAction", value)
            }
        }
        SettingRow {
            visible: PowerService.hasBattery
            label: "Power profile"
            hint: page.source === "battery" ? "Set when you unplug" : "Set when you plug in"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: page.sourceValue("profile")
                options: [{ value: "keep", label: "Don't change" }, { value: "powerSaver", label: "Power saver" },
                          { value: "balanced", label: "Balanced" }]
                    .concat(PowerService.hasPerformance || page.sourceValue("profile") === "performance" ? [{ value: "performance", label: "Performance" }] : [])
                onSelected: value => page.setSourceValue("profile", value)
            }
        }
        // Off by default, and meant to be measured before it is kept: the
        // blur and the animations cost the GPU something on battery, how
        // much on this laptop is BAT0's power_now with and without.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: PowerService.hasBattery && SettingsService.defaultOf("power.battery.effects") !== undefined
            label: "Lighter effects"
            hint: (page.source === "battery" ? "On battery" : "Plugged in")
                + ", the blur is off and Full motion runs as Reduced. Settings > Appearance keeps your own choice for the rest of the time"
            ShellToggle {
                focusOnTab: true
                checked: page.sourceValue("effects") === "light"
                onToggled: value => page.setSourceValue("effects", value ? "light" : "keep")
            }
        }
    }
}
