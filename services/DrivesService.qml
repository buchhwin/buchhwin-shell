pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "drives/DrivesLogic.js" as Logic

// Removable drives (USB sticks, SD cards, external disks, LUKS volumes) and
// MTP phones. scripts/drives.py watches UDisks2 and the gvfs volume monitor
// read-only and prints the list plus added/removed events; mounting,
// unmounting, unlocking, locking and powering off run through udisksctl
// (udisks' polkit rules allow them for the active session, no sudo), phones
// through `gio mount`. A LUKS passphrase only reaches udisksctl over stdin
// (`--key-file /dev/stdin`), never as an argument and never in a message.
// Notifications and every action only run in the real session: nested
// sessions share the host's disks and would notify Plasma. `preview` shows
// synthetic drives and a synthetic phone.
Singleton {
    id: root

    readonly property bool realSession: AppearanceService.realSession
    readonly property bool notifyEnabled: SettingsService.value("drives.notify")
    readonly property bool autoOpen: SettingsService.value("drives.autoOpen")

    property var liveDrives: []
    property var previewDrives: []
    property var livePhones: []
    property var previewPhones: []
    property bool preview: false
    readonly property var drives: preview ? previewDrives : liveDrives
    readonly property var phones: preview ? previewPhones : livePhones
    readonly property string summary: Logic.summary(drives, phones)
    property bool available: true
    // False when gvfs-mtp is missing: phones cannot be listed or opened then.
    property bool mtpAvailable: true
    property string message: ""
    property bool messageError: false
    // drive or phone id → "Ejecting …", "Mounting …" while jobs for it are queued.
    property var busy: ({})
    property var pending: []
    // Unlock dialog state; the passphrase itself is never stored.
    property string unlockError: ""
    property string unlockingId: ""

    readonly property bool actionsAllowed: realSession && !preview
    readonly property string blockedReason: preview ? "Preview data: drive actions are disabled"
        : !realSession ? "Drive actions only run in the buchhwin-shell session" : ""

    function icon(drive) { return Logic.icon(drive) }
    function driveTitle(drive) { return Logic.driveTitle(drive) }
    function driveSubtitle(drive) { return busy[drive.id] || Logic.driveSubtitle(drive) }
    function volumeTitle(volume) { return Logic.volumeTitle(volume) }
    function volumeSubtitle(volume) { return Logic.volumeSubtitle(volume) }
    function mounted(volume) { return Logic.mounted(volume) }
    function locked(volume) { return Logic.locked(volume) }
    function anyMounted(drive) { return Logic.mountedVolumes(drive).length > 0 }
    function isBusy(drive) { return !!busy[drive.id] }
    function find(id) { return drives.find(item => item.id === id) || null }
    function findVolume(id) {
        for (const drive of drives) {
            const volume = drive.volumes.find(item => item.id === id)
            if (volume) return { drive: drive, volume: volume }
        }
        return null
    }

    function phoneIcon() { return Logic.phoneIcon() }
    function phoneTitle(phone) { return Logic.phoneTitle(phone) }
    function phoneSubtitle(phone) { return busy[phone.id] || Logic.phoneSubtitle(phone) }
    function findPhone(id) { return phones.find(item => item.id === id) || null }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    function setBusy(id, text) {
        const next = Object.assign({}, busy)
        if (text.length) next[id] = text
        else delete next[id]
        busy = next
    }

    function handleLine(line) {
        const event = Logic.parseLine(line)
        if (!event) return
        if (event.kind === "drives") {
            available = true
            monitorFailures = 0
            liveDrives = event.drives
            livePhones = event.phones
            mtpAvailable = event.mtp
            const known = liveDrives.concat(livePhones)
            for (const id in busy) if (!known.some(item => item.id === id) && !pending.some(job => job.driveId === id)) setBusy(id, "")
            openWaitingPhone()
        } else if (event.kind === "added") {
            const drive = liveDrives.find(item => item.id === event.id)
            if (drive) driveAdded(drive)
        } else if (event.kind === "removed") {
            dismissNotifications(event.id)
        } else if (event.kind === "phoneAdded") {
            const phone = livePhones.find(item => item.id === event.id)
            if (phone) phoneAdded(phone)
        } else if (event.kind === "phoneRemoved") {
            dismissNotifications(event.id)
            if (waitingPhone === event.id) waitingPhone = ""
        } else if (event.kind === "error") {
            available = false
        }
    }

    function driveAdded(drive) {
        if (!realSession) return
        // A locked volume needs the passphrase, so nothing is opened by itself.
        if (autoOpen && !drive.volumes.every(Logic.locked)) openDrive(drive)
        if (notifyEnabled) notifyConnected(drive)
    }

    function phoneAdded(phone) {
        if (!realSession) return
        if (autoOpen) openPhone(phone)
        if (notifyEnabled) notifyPhone(phone)
    }

    // ---- notifications (notify-send to the shell's own server) -------------
    function notifyConnected(drive) {
        const body = Logic.connectedBody(drive)
        notifyComponent.createObject(root, {
            driveId: drive.id, body: body,
            command: ["notify-send", "--app-name=Drives", "--icon=" + Logic.notifyIcon(drive),
                      "--action=open=Open", "--action=ignore=Ignore", "--", Logic.connectedTitle(drive), body]
        })
    }

    function notifyPhone(phone) {
        const body = Logic.phoneConnectedBody(phone)
        notifyComponent.createObject(root, {
            driveId: phone.id, body: body,
            command: ["notify-send", "--app-name=Drives", "--icon=" + Logic.phoneNotifyIcon(),
                      "--action=open=Open", "--action=ignore=Ignore", "--", "Phone connected", body]
        })
    }

    function notifyRemovable(name) {
        if (!notifyEnabled) return
        Quickshell.execDetached(["notify-send", "--app-name=Drives", "--icon=media-eject", "--urgency=low", "--",
                                 "Safe to remove", "“" + name + "” can be unplugged now."])
    }

    function notificationAction(driveId, action) {
        if (action !== "open") return
        const drive = find(driveId)
        if (drive) { openDrive(drive); return }
        const phone = findPhone(driveId)
        if (phone) openPhone(phone)
    }

    // A connection notice is pointless once the drive is gone.
    function dismissNotifications(driveId) {
        for (let i = 0; i < notifiers.length; ++i) {
            const notifier = notifiers[i]
            if (notifier.driveId !== driveId) continue
            const list = NotificationService.history
            for (let j = list.length - 1; j >= 0; --j) {
                const item = list[j]
                if (item && item.appName === "Drives" && item.body === notifier.body) item.dismiss()
            }
        }
    }
    property var notifiers: []

    Component {
        id: notifyComponent
        Process {
            id: notifier
            stderr: ErrorLog { label: "DrivesService.notifier" }
            property string driveId: ""
            property string body: ""
            running: true
            // notify-send prints the chosen action key and exits when the
            // notification closes.
            stdout: StdioCollector {
                onStreamFinished: {
                    root.notifiers = root.notifiers.filter(item => item !== notifier)
                    root.notificationAction(notifier.driveId, text.trim())
                    notifier.destroy()
                }
            }
            Component.onCompleted: root.notifiers = root.notifiers.concat([notifier])
        }
    }

    // ---- actions --------------------------------------------------------------
    function blocked() {
        if (actionsAllowed) return false
        say(blockedReason, true)
        return true
    }

    function openPath(path) {
        if (!path.startsWith("/")) return
        Quickshell.execDetached(["xdg-open", path])
        PanelService.close("controlCenter")
    }

    // Opens the first mounted volume, mounting the drive first when needed.
    // Locked volumes are skipped: they need the passphrase dialog.
    function openDrive(drive) {
        if (blocked() || !drive) return
        const open = drive.volumes.find(Logic.mounted)
        if (open) openPath(open.mountPoints[0])
        let opening = !!open
        for (const volume of drive.volumes) {
            if (Logic.mounted(volume) || Logic.locked(volume)) continue
            enqueue("mount", Logic.fsDevice(volume), drive, !opening)
            opening = true
        }
    }

    function openVolume(drive, volume) {
        if (Logic.locked(volume)) { askPassphrase(drive, volume); return }
        if (blocked()) return
        if (Logic.mounted(volume)) openPath(volume.mountPoints[0])
        else enqueue("mount", Logic.fsDevice(volume), drive, true)
    }

    function mountVolume(drive, volume) {
        if (Logic.locked(volume)) { askPassphrase(drive, volume); return }
        if (!blocked()) enqueue("mount", Logic.fsDevice(volume), drive, false)
    }

    function unmountVolume(drive, volume) {
        if (!blocked()) enqueue("unmount", Logic.fsDevice(volume), drive, false)
    }

    // ---- encrypted volumes -----------------------------------------------------
    // The dialog collects the passphrase; it is handed to the unlock job and
    // dropped as soon as it has been written to the process' stdin.
    function askPassphrase(drive, volume) {
        if (!drive || !volume) return
        unlockError = ""
        PanelService.openOver("driveUnlock", { drive: drive.id, volume: volume.id })
    }

    function unlockVolume(drive, volume, secret, openAfter) {
        if (!drive || !volume || !Logic.locked(volume) || !secret.length) return
        if (blocked()) { unlockError = blockedReason; return }
        unlockError = ""
        unlockingId = volume.id
        enqueue("unlock", volume.device, drive, openAfter === true, false, secret)
    }

    function lockVolume(drive, volume) {
        if (blocked() || !volume || !volume.encrypted || !volume.unlocked) return
        if (Logic.mounted(volume)) enqueue("unmount", Logic.fsDevice(volume), drive, false)
        enqueue("lock", volume.device, drive, false)
    }

    // ---- MTP phones -------------------------------------------------------------
    function openPhone(phone) {
        if (blocked() || !phone) return
        if (!mtpAvailable) { say("Phones need the gvfs-mtp package.", true); return }
        if (phone.mounted && phone.mountPoint.length) { openPath(phone.mountPoint); return }
        enqueuePhone("mount", phone, true)
    }

    function unmountPhone(phone) {
        if (blocked() || !phone) return
        enqueuePhone("unmount", phone, false)
    }

    // `gio mount` prints no path, so the mount point is taken from the next
    // helper snapshot (and forgotten again when it does not arrive).
    property string waitingPhone: ""

    function openWaitingPhone() {
        if (!waitingPhone.length) return
        const phone = livePhones.find(item => item.id === waitingPhone)
        if (!phone || !phone.mounted || !phone.mountPoint.length) return
        waitingPhone = ""
        phoneWait.stop()
        openPath(phone.mountPoint)
    }

    Timer {
        id: phoneWait
        interval: 8000
        onTriggered: root.waitingPhone = ""
    }

    // Safely remove: unmount every volume, lock what was unlocked, then power
    // the drive off (card readers that cannot power off are safe once unmounted).
    function eject(drive) {
        if (blocked() || !drive || isBusy(drive)) return
        setBusy(drive.id, "Ejecting …")
        for (const volume of Logic.mountedVolumes(drive)) enqueue("unmount", Logic.fsDevice(volume), drive, false, true)
        for (const volume of Logic.unlockedVolumes(drive)) enqueue("lock", volume.device, drive, false, true)
        if (drive.canPowerOff) enqueue("powerOff", drive.volumes[0].device, drive, false, true)
        else enqueue("done", "", drive, false, true)
    }

    function enqueue(action, device, drive, openAfter, ejecting, secret) {
        const argv = action === "done" ? [] : Logic.command(action, device)
        if (argv === null) return
        if (!ejecting && !busy[drive.id]) setBusy(drive.id, busyLabel(action))
        pending = pending.concat([{ action: action, argv: argv, driveId: drive.id, name: Logic.driveTitle(drive),
                                    openAfter: openAfter, ejecting: !!ejecting, secret: secret || "", phone: false }])
        next()
    }

    function enqueuePhone(action, phone, openAfter) {
        const argv = Logic.phoneCommand(action, phone.uri)
        if (argv === null) return
        setBusy(phone.id, action === "mount" ? "Opening …" : "Closing …")
        pending = pending.concat([{ action: action, argv: argv, driveId: phone.id, name: Logic.phoneTitle(phone),
                                    openAfter: openAfter === true, ejecting: false, secret: "", phone: true }])
        next()
    }

    function busyLabel(action) {
        return action === "mount" ? "Mounting …" : action === "unlock" ? "Unlocking …"
            : action === "lock" ? "Locking …" : "Unmounting …"
    }

    function next() {
        if (actionProc.running) return
        while (pending.length) {
            const job = pending[0]
            pending = pending.slice(1)
            if (job.action === "done") { finishEject(job); continue }
            actionProc.job = job
            actionProc.command = Logic.wrap(job.argv)
            actionProc.running = true
            return
        }
    }

    function finishEject(job) {
        setBusy(job.driveId, "")
        say("“" + job.name + "” can be unplugged now.", false)
        notifyRemovable(job.name)
    }

    function finish(job, output) {
        const result = Logic.parseResult(output)
        const ok = result.code === 0
            || (job.phone ? Logic.phoneHarmless(job.action, result.output) : Logic.harmless(job.action, result.output))
        const more = pending.some(item => item.driveId === job.driveId)
        if (job.action === "unlock") unlockingId = ""
        if (!ok) {
            const problem = job.phone ? Logic.phoneErrorText(job.action, job.name, result.output)
                : Logic.errorText(job.action, job.name, result.output)
            // The dialog stays open and shows the reason next to the field.
            if (job.action === "unlock") unlockError = problem
            else say(problem, true)
            // A failed step stops the rest of an ejection.
            if (job.ejecting) pending = pending.filter(item => !(item.ejecting && item.driveId === job.driveId))
            if (!pending.some(item => item.driveId === job.driveId)) setBusy(job.driveId, "")
        } else if (job.action === "powerOff") {
            finishEject(job)
        } else if (job.action === "unlock") {
            PanelService.close("driveUnlock")
            say("“" + job.name + "” is unlocked", false)
            const clear = Logic.parseCleartext(result.output)
            const drive = clear.length ? find(job.driveId) : null
            if (!more) setBusy(job.driveId, "")
            if (drive) enqueue("mount", clear, drive, job.openAfter)
        } else {
            if (!more) setBusy(job.driveId, "")
            if (job.phone) {
                if (!job.ejecting) say(job.action === "mount" ? "“" + job.name + "” is open" : "“" + job.name + "” is closed", false)
                if (job.action === "mount" && job.openAfter) { waitingPhone = job.driveId; phoneWait.restart(); openWaitingPhone() }
            } else if (!job.ejecting) {
                say(job.action === "mount" ? "“" + job.name + "” is mounted"
                    : job.action === "lock" ? "“" + job.name + "” is locked"
                    : "“" + job.name + "” is unmounted", false)
            }
            if (!job.phone && job.action === "mount" && job.openAfter) {
                const path = Logic.parseMountPoint(result.output)
                if (path.length) openPath(path)
            }
        }
    }

    Process {
        id: actionProc
        stderr: ErrorLog { label: "DrivesService.actionProc" }
        property var job: null
        // Only the unlock job writes: the passphrase goes to
        // `udisksctl unlock --key-file /dev/stdin` and stdin is closed at once,
        // so it never appears in argv, in the log or in a property.
        stdinEnabled: true
        onStarted: {
            const secret = actionProc.job ? actionProc.job.secret : ""
            if (!secret.length) return
            write(secret)
            actionProc.job.secret = ""
            stdinEnabled = false
        }
        onExited: stdinEnabled = true
        stdout: StdioCollector {
            onStreamFinished: {
                const job = actionProc.job
                if (!job) return
                actionProc.job = null
                root.finish(job, text)
                Qt.callLater(root.next)
            }
        }
    }

    // ---- preview --------------------------------------------------------------
    function showPreview() {
        message = ""
        if (sampleFile.loaded) applySample(sampleFile.text())
        preview = true
    }

    function stopPreview() {
        preview = false
        message = ""
    }

    function applySample(text) {
        const event = Logic.parseLine(text.trim())
        previewDrives = event && event.kind === "drives" ? event.drives : []
        previewPhones = event && event.kind === "drives" ? event.phones : []
    }

    FileView {
        id: sampleFile
        path: Paths.shellFile("tests/fixtures/drives-sample.json")
        printErrors: false
        onLoaded: if (root.preview) root.applySample(text())
    }

    // ---- monitor ----------------------------------------------------------------
    // Crash restarts pause through a flag so the `running` binding survives.
    property bool monitorPaused: false
    property int monitorFailures: 0

    Process {
        id: monitorProc
        stderr: ErrorLog { label: "DrivesService.monitorProc" }
        running: !root.monitorPaused
        command: [Paths.script("drives.py"), "monitor"]
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        onRunningChanged: {
            if (running || root.monitorPaused) return
            root.available = false
            root.monitorFailures += 1
            if (root.monitorFailures > 5) return
            root.monitorPaused = true
            monitorRestart.interval = 5000 * Math.pow(2, root.monitorFailures - 1)
            monitorRestart.restart()
        }
    }
    Timer {
        id: monitorRestart
        onTriggered: root.monitorPaused = false
    }
}
