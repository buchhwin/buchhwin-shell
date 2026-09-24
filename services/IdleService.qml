pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "power/DimLogic.js" as DimLogic
import "lock/LockLogic.js" as LockLogic

// Idle and lid behaviour for the buchhwin-shell session: screen off, lock and
// suspend after inactivity (Wayland idle-notify, respecting apps that inhibit
// idle such as video players), "stay awake", locking before sleep and what
// closing the lid does. Nested test sessions never start the system-wide
// inhibitor or the before-sleep lock.
Singleton {
    id: root

    // Times, dimming and the lid action come from the active power source
    // (battery or charger) and change as soon as it is plugged or unplugged.
    readonly property int screenOffMinutes: PowerService.current("screenOffMinutes")
    readonly property int lockMinutes: PowerService.current("lockMinutes")
    readonly property int suspendMinutes: PowerService.current("suspendMinutes")
    readonly property bool lockBeforeSleep: SettingsService.value("power.lockBeforeSleep")
    readonly property string lidAction: PowerService.current("lidAction")
    property bool stayAwake: false
    property bool screenOff: false

    readonly property bool realSession: Quickshell.env("BUCHHWIN_NESTED") !== "1"
        && ((Quickshell.env("XDG_CONFIG_HOME") || "").length === 0
            || Quickshell.env("XDG_CONFIG_HOME") === Quickshell.env("HOME") + "/.config")

    function setScreen(on) {
        screenOff = !on
        // The saved backlight value returns right before the panel wakes;
        // the backlight is never written while the panel is off.
        if (on) dimEvent("screenOn")
        HyprCompat.dispatch(HyprCompat.commands.dpms(on))
        if (on) DisplayService.reassertLid()
    }

    // Dim stage: 30 s before screen off the backlight drops to 30 % of its
    // value; the exact raw value comes back on activity, when the screen turns
    // on again or when dimming is switched off. Real session only, so nested
    // tests never touch the host backlight.
    readonly property bool dimBeforeScreenOff: PowerService.current("dimBeforeScreenOff")
    readonly property bool dimAllowed: realSession && dimBeforeScreenOff && !stayAwake && screenOffMinutes > 0
        && BrightnessService.available
    property var dimState: ({ dimmed: false, saved: 0 })
    property string dimDevice: ""

    function dimEvent(event) {
        if (!dimState.dimmed && event !== "idle") return
        const result = DimLogic.next(dimState, event, {
            allowed: dimAllowed, current: BrightnessService.current,
            maximum: BrightnessService.maximum, screenOff: screenOff
        })
        dimState = result.state
        if (result.state.dimmed) dimDevice = BrightnessService.device
        if (result.write > 0) BrightnessService.setRaw(result.write, true)
    }

    onDimAllowedChanged: if (!dimAllowed) dimEvent("disabled")
    // A shell reload while dimmed must not leave the screen dark.
    Component.onDestruction: {
        if (dimState.dimmed && dimState.saved > 0 && dimDevice.length)
            Quickshell.execDetached(["brightnessctl", "-q", "-d", dimDevice, "set", String(dimState.saved)])
    }

    // Called by the Hyprland lid switch bindings (hypr/keybinds.conf).
    //
    // **All four actions are the shell's**, including suspend. It used to hand
    // that one back to logind - the inhibitor below was taken only while the
    // action was something else - and that left a hole nobody could close from
    // here: logind re-reads the lid when a session appears, so logging in with
    // the lid shut suspended the machine before this shell existed to inhibit
    // anything. The journal of 2026-09-22 has it plainly: the session starts at
    // 10:31:33 and `systemd-logind: Suspending...` at 10:31:47, with no lid
    // event in between. The user's answer was to open and close the lid once,
    // which is a real lid event and therefore reaches the shell.
    function lidClosed() {
        if (lidAction === "suspend") SessionService.run("suspend")
        else if (lidAction === "lock") SessionService.run("lock")
        else if (lidAction === "screenOff") DisplayService.setLidClosed(true)
    }
    function lidOpened() { DisplayService.setLidClosed(false) }

    // What a lid switch never says: that it was already shut when the session
    // started. Hyprland's `bindl` is an edge, so a session that begins with the
    // lid closed believes it is open until somebody moves it.
    //
    // Only the **display** half is applied from this, never the action: a
    // laptop that boots docked and shut would otherwise suspend or lock itself
    // the moment it finished starting, which is the very complaint this is
    // here to answer.
    Process {
        id: lidAtStart
        stderr: ErrorLog { label: "IdleService.lidAtStart" }
        running: root.realSession
        command: ["busctl", "--system", "--timeout=2", "get-property", "org.freedesktop.UPower",
                  "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsClosed"]
        property string output: ""
        onStarted: output = ""
        stdout: StdioCollector { onStreamFinished: lidAtStart.output = text }
        onExited: code => {
            if (LockLogic.parseLidClosed(lidAtStart.output, code)) DisplayService.setLidClosed(true)
        }
    }

    IdleMonitor {
        enabled: !root.stayAwake && root.screenOffMinutes > 0
        timeout: Math.max(1, root.screenOffMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: root.setScreen(!isIdle)
    }

    IdleMonitor {
        id: dimMonitor
        enabled: root.dimAllowed
        timeout: Math.max(1, DimLogic.dimTimeout(root.screenOffMinutes))
        respectInhibitors: true
        onIsIdleChanged: {
            if (!isIdle) {
                dimDelay.stop()
                root.dimEvent("active")
                return
            }
            // Re-read the backlight first: amdgpu does not report every change.
            BrightnessService.refresh()
            dimDelay.restart()
        }
    }
    Timer {
        id: dimDelay
        interval: 250
        onTriggered: if (dimMonitor.isIdle && !root.screenOff) root.dimEvent("idle")
    }

    IdleMonitor {
        enabled: !root.stayAwake && root.lockMinutes > 0
        timeout: Math.max(1, root.lockMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) SessionService.run("lock")
    }

    IdleMonitor {
        enabled: root.realSession && !root.stayAwake && root.suspendMinutes > 0
        timeout: Math.max(1, root.suspendMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) SessionService.run("suspend")
    }

    // Lock before any suspend (menu, idle, lid, power key). swayidle holds a
    // logind delay inhibitor so the lock screen is up before the system sleeps.
    // A crashed helper restarts after a growing pause; toggling `paused`
    // keeps the `running` binding intact so the setting can still stop it.
    property bool beforeSleepPaused: false
    property int beforeSleepFailures: 0
    Process {
        id: beforeSleep
        stderr: ErrorLog { label: "IdleService.beforeSleep" }
        running: root.realSession && root.lockBeforeSleep && !root.beforeSleepPaused
        command: ["swayidle", "-w", "before-sleep", Paths.script("session-action.sh") + " lock"]
        onRunningChanged: {
            if (running || !root.realSession || !root.lockBeforeSleep || root.beforeSleepPaused) return
            root.beforeSleepFailures += 1
            if (root.beforeSleepFailures > 5) return
            root.beforeSleepPaused = true
            restartBeforeSleep.interval = 5000 * Math.pow(2, root.beforeSleepFailures - 1)
            restartBeforeSleep.restart()
        }
    }
    Timer {
        id: restartBeforeSleep
        onTriggered: root.beforeSleepPaused = false
    }

    // Keep logind's hands off the lid **always**, because the shell handles
    // every action itself now. It used to be conditional, which meant the
    // machine was unprotected for exactly as long as the setting said
    // "suspend" - and at session start, before UPower has said which power
    // source this is, that is whatever the defaults say.
    //
    // This cannot cover the moment before the shell runs; only
    // `/etc/systemd/logind.conf.d/50-buchhwin.conf` can, and
    // `install/system-install.sh --lid` writes it (see docs/system.md).
    Process {
        stderr: ErrorLog { label: "IdleService.process" }
        running: root.realSession
        command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=buchhwin-shell",
                  "--why=Lid setting in buchhwin-shell", "--mode=block", "sleep", "infinity"]
    }
}
