pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "power/DimLogic.js" as DimLogic
import "lock/LockLogic.js" as LockLogic
import "display/DisplayLogic.js" as DisplayLogic

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

    // The lock screen's process (lock.qml) is never the session: everything
    // below is the shell's, and a second copy there disabled the laptop panel
    // when the lock started with the lid shut (LockLogic.lockProcess).
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)
    readonly property bool realSession: !lockProcess && Quickshell.env("BUCHHWIN_NESTED") !== "1"
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
    //
    // Suspend waits for the lid to stay shut a moment. A lid shut and opened
    // again at once is a hand carrying the laptop off a dock, and a suspend
    // asked for at the first edge went through all the same: on 16.10. the
    // lid closed at 15:46:52.8, opened 0.3 s later, and the machine slept with
    // the lid open - where opening it cannot wake it, so it looked dead until
    // it was switched off. The lock and the screen still act at once.
    //
    // At a desk the action does not suspend and the panel always goes off
    // (DisplayLogic.lidClose has the why). The delay asks again before it
    // suspends: a dock plugged in within it keeps the laptop awake.
    property bool lidShut: false
    // Another screen on beside the laptop panel.
    readonly property bool docked: DisplayLogic.lidPlan(DisplayService.monitors, DisplayService.internalName) === "disable"
    function lidSteps() {
        return DisplayLogic.lidClose(lidAction, DisplayService.monitors, DisplayService.internalName)
    }
    function lidClosed() {
        lidShut = true
        const steps = lidSteps()
        if (steps.panel) DisplayService.setLidClosed(true)
        if (steps.lock) SessionService.run("lock")
        if (steps.suspend) {
            lidSuspendDelay.interval = 2000
            lidSuspendDelay.restart()
        }
    }
    function lidOpened() {
        lidShut = false
        lidSuspendDelay.stop()
        DisplayService.setLidClosed(false)
    }
    // Docked or undocked with the lid shut, which is what logind did while it
    // still had the lid: plugged in, the panel goes off; unplugged, the lid
    // action applies as if the lid had just closed - "Sleep" no longer stays
    // awake in a bag because it was shut at the desk. Not while the screens
    // are off for idleness: some docks drop their screens then, and that is
    // not an undock. The longer wait covers a dock that takes a moment to
    // find its screens again.
    onDockedChanged: {
        if (lockProcess || !lidShut) return
        if (docked) {
            lidSuspendDelay.stop()
            DisplayService.setLidClosed(true)
            return
        }
        if (screenOff) return
        const steps = lidSteps()
        if (steps.lock) SessionService.run("lock")
        if (steps.suspend) {
            lidSuspendDelay.interval = 5000
            lidSuspendDelay.restart()
        }
    }
    Timer {
        id: lidSuspendDelay
        interval: 2000
        onTriggered: {
            const steps = root.lidSteps()
            if (steps.suspend) SessionService.run("suspend")
            else if (steps.panel) DisplayService.setLidClosed(true)
        }
    }

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
        // The output may arrive before or after the exit; judge once both
        // are in. Judged at the exit alone, an exit first read "" and a lid
        // shut at login was never applied.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function finish() {
            if (!outputDone || exitCode < 0) return
            // Open, or no answer: DisplayService stops holding the laptop
            // panel off for the startup apply (DisplayService.lidKnown).
            if (LockLogic.parseLidClosed(output, exitCode)) {
                root.lidShut = true
                DisplayService.setLidClosed(true)
            } else {
                DisplayService.lidChecked()
            }
        }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        stdout: StdioCollector { onStreamFinished: { lidAtStart.output = text; lidAtStart.outputDone = true; lidAtStart.finish() } }
        onExited: code => { exitCode = code; finish() }
    }

    // Screen off and lock also run in nested test sessions, but never in the
    // lock process: the shell's own monitors keep working while it is locked.
    IdleMonitor {
        enabled: !root.lockProcess && !root.stayAwake && root.screenOffMinutes > 0
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
            // Re-read the backlight first: the udev monitor sees a change made
            // outside the shell only after its debounce, and the dim starts
            // from the value now.
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
        enabled: !root.lockProcess && !root.stayAwake && root.lockMinutes > 0
        timeout: Math.max(1, root.lockMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) SessionService.run("lock")
    }

    // The screen off soon after locking (Settings > Power, "Screen off when
    // locked"; 0 is never, the default): with the screen-off time at "Never"
    // on the charger, a locked laptop kept its panel lit for as long as it was
    // locked - three hours one afternoon. Counted from the lock, because an
    // idle monitor starts counting when it is enabled, and this one is
    // enabled while the lock screen's marker is there (LockScreen writes
    // `locked` into session-action.sh's directory once the session is locked,
    // and removes it on unlock).
    readonly property int lockedScreenOffMinutes: Math.max(0, Number(PowerService.current("lockedScreenOffMinutes")) || 0)
    readonly property string lockDir: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/buchhwin-shell/lock"
        + (Quickshell.env("BUCHHWIN_NESTED") === "1" ? "-nested" : "")
    property bool lockDirReady: false
    property bool locked: false
    property bool lockedOff: false
    // A FileView does not see a file appear in a directory that does not
    // exist yet (probed offscreen), and the lock makes its directory only
    // the first time it runs: made here first, the same way.
    Process {
        stderr: ErrorLog { label: "IdleService.lockDir" }
        running: !root.lockProcess && root.lockedScreenOffMinutes > 0 && !root.lockDirReady
            && (Quickshell.env("XDG_RUNTIME_DIR") || "").length > 0
        command: ["install", "-d", "-m", "700", "--", root.lockDir]
        onExited: code => { if (code === 0) root.lockDirReady = true }
    }
    FileView {
        path: root.lockDirReady && root.lockedScreenOffMinutes > 0 ? root.lockDir + "/locked" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.locked = true
        onLoadFailed: root.locked = false
    }
    IdleMonitor {
        enabled: !root.lockProcess && !root.stayAwake && root.locked && root.lockedScreenOffMinutes > 0
        timeout: Math.max(1, root.lockedScreenOffMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle && !root.screenOff) {
                root.lockedOff = true
                root.setScreen(false)
            } else if (!isIdle && root.lockedOff) {
                root.lockedOff = false
                root.setScreen(true)
            }
        }
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
    // A helper that has run for a minute counts as healthy again, so five
    // exits spread over a long session do not switch the lock off for good.
    // swayidle runs its command through sh, hence the quoted path.
    property bool beforeSleepPaused: false
    property int beforeSleepFailures: 0
    Process {
        id: beforeSleep
        stderr: ErrorLog { label: "IdleService.beforeSleep" }
        running: root.realSession && root.lockBeforeSleep && !root.beforeSleepPaused
        // After a resume every SystemClock is re-armed at once (WallClock.qml);
        // without this line WallClock's own minute check finds the jump
        // within a minute.
        command: Paths.bound(["swayidle", "-w", "before-sleep", "'" + Paths.script("session-action.sh").replace(/'/g, "'\\''") + "' lock",
                              "after-resume", "echo resumed"])
        stdout: SplitParser { onRead: data => { if (data.trim() === "resumed") WallClock.kick() } }
        onRunningChanged: {
            if (running) { beforeSleepHealthy.restart(); return }
            beforeSleepHealthy.stop()
            if (!root.realSession || !root.lockBeforeSleep || root.beforeSleepPaused) return
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
    Timer { id: beforeSleepHealthy; interval: 60000; onTriggered: root.beforeSleepFailures = 0 }

    // Keep logind's hands off the lid **always**, because the shell handles
    // every action itself now. It used to be conditional, which meant the
    // machine was unprotected for exactly as long as the setting said
    // "suspend" - and at session start, before UPower has said which power
    // source this is, that is whatever the defaults say.
    //
    // This cannot cover the moment before the shell runs; only
    // `/etc/systemd/logind.conf.d/50-buchhwin.conf` can, and
    // `install/system-install.sh --lid` writes it (see docs/system.md).
    //
    // Taken again after a pause if it ever ends (logind restarted, the
    // inhibitor killed), or logind would own the lid for the rest of the
    // session. The inner `sleep` is bound too, so it ends with the inhibitor.
    property bool lidInhibitPaused: false
    Process {
        stderr: ErrorLog { label: "IdleService.process" }
        running: root.realSession && !root.lidInhibitPaused
        command: Paths.bound(["systemd-inhibit", "--what=handle-lid-switch", "--who=buchhwin-shell",
                  "--why=Lid setting in buchhwin-shell", "--mode=block"].concat(Paths.bound(["sleep", "infinity"])))
        onRunningChanged: {
            if (running || !root.realSession || root.lidInhibitPaused) return
            root.lidInhibitPaused = true
            lidInhibitRestart.restart()
        }
    }
    Timer { id: lidInhibitRestart; interval: 5000; onTriggered: root.lidInhibitPaused = false }
}
