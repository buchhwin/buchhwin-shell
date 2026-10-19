pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "drives/DrivesLogic.js" as Logic

// Removable drives (USB sticks, SD cards, external disks, LUKS volumes) and
// MTP phones. `scripts/drives.py list` reads UDisks2 and the gvfs volume
// monitor read-only and prints the list; it runs whenever `udisksctl monitor`
// or `gio mount -o` says something changed (see "watching" below), and what
// came and went is worked out here (DrivesLogic.settle). Mounting,
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

    // One message of a read: the list, then what came and went since the read
    // before (DrivesLogic.settle), or an error.
    function handleMessage(event) {
        if (!event) return
        if (event.kind === "drives") {
            available = true
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
            forgetAutoOpen(event.id)
        } else if (event.kind === "phoneAdded") {
            const phone = livePhones.find(item => item.id === event.id)
            if (phone) phoneAdded(phone)
        } else if (event.kind === "phoneRemoved") {
            dismissNotifications(event.id)
            forgetAutoOpen(event.id)
            if (waitingPhone === event.id) waitingPhone = ""
        } else if (event.kind === "error") {
            available = false
        }
    }

    function driveAdded(drive) {
        if (!realSession) return
        // A locked volume needs the passphrase, so nothing is opened by itself.
        if (autoOpen && !drive.volumes.every(Logic.locked)) queueAutoOpen(drive.id)
        if (notifyEnabled) notifyConnected(drive)
    }

    function phoneAdded(phone) {
        if (!realSession) return
        if (autoOpen) queueAutoOpen(phone.id)
        if (notifyEnabled) notifyPhone(phone)
    }

    // ---- opening by itself, not behind the lock screen ---------------------------
    // "Open automatically" waits while the screen is locked
    // (DrivesLogic.autoOpenAction): the lock screen's marker file says so,
    // and the drives waiting are opened once it is gone - looked at every
    // 3 s, and only while something waits.
    readonly property string lockMarker: Paths.runtimeDir + "/lock/locked"
    property var autoOpenIds: []

    function queueAutoOpen(id) {
        if (autoOpenIds.indexOf(id) < 0) autoOpenIds = autoOpenIds.concat([id])
        if (!lockCheck.running) lockCheck.running = true
    }

    function forgetAutoOpen(id) {
        autoOpenIds = autoOpenIds.filter(item => item !== id)
    }

    function settleAutoOpen(screenLocked) {
        const waiting = []
        for (const id of autoOpenIds) {
            const drive = find(id)
            const phone = drive ? null : findPhone(id)
            if (!drive && !phone) continue
            const openable = phone !== null || !drive.volumes.every(Logic.locked)
            const action = Logic.autoOpenAction(autoOpen, openable, screenLocked)
            if (action === "wait") waiting.push(id)
            else if (action === "open" && drive) openDrive(drive)
            else if (action === "open") openPhone(phone)
        }
        autoOpenIds = waiting
        if (waiting.length) lockPoll.restart()
    }

    Process {
        id: lockCheck
        command: ["test", "-e", root.lockMarker]
        onExited: code => root.settleAutoOpen(code === 0)
    }
    Timer {
        id: lockPoll
        interval: 3000
        onTriggered: if (root.autoOpenIds.length && !lockCheck.running) lockCheck.running = true
    }

    // ---- notifications (notify-send to the shell's own server) -------------
    // notify-send waits for an answer until its notice closes, and the shell
    // keeps notices in its history: every plug event left a notify-send and
    // its Process behind for good. Ten minutes is time enough to click; after
    // that the notice stays in the history and its buttons do nothing. Bound
    // to the shell as well, so a crash leaves none of them behind (Paths.bound).
    function noticeCommand(argv) { return Paths.bound(["timeout", "10m"].concat(argv)) }

    function notifyConnected(drive) {
        const body = Logic.connectedBody(drive)
        rememberNotice(drive.id, body)
        notifyComponent.createObject(root, {
            driveId: drive.id,
            command: noticeCommand(["notify-send", "--app-name=Drives", "--icon=" + Logic.notifyIcon(drive),
                      "--action=open=Open", "--action=ignore=Ignore", "--", Logic.connectedTitle(drive), body])
        })
    }

    function notifyPhone(phone) {
        const body = Logic.phoneConnectedBody(phone)
        rememberNotice(phone.id, body)
        notifyComponent.createObject(root, {
            driveId: phone.id,
            command: noticeCommand(["notify-send", "--app-name=Drives", "--icon=" + Logic.phoneNotifyIcon(),
                      "--action=open=Open", "--action=ignore=Ignore", "--", "Phone connected", body])
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

    // A connection notice is pointless once the drive is gone. Its body is
    // kept by drive rather than on the notifier: the notifier is gone after
    // ten minutes, the notice in the history is not.
    property var noticeBodies: ({})
    function rememberNotice(driveId, body) {
        const next = Object.assign({}, noticeBodies)
        next[driveId] = body
        noticeBodies = next
    }
    function dismissNotifications(driveId) {
        const body = noticeBodies[driveId]
        if (body === undefined) return
        const next = Object.assign({}, noticeBodies)
        delete next[driveId]
        noticeBodies = next
        const list = NotificationService.history
        for (let j = list.length - 1; j >= 0; --j) {
            const item = list[j]
            if (item && item.appName === "Drives" && item.body === body) item.dismiss()
        }
    }

    Component {
        id: notifyComponent
        Process {
            id: notifier
            stderr: ErrorLog { label: "DrivesService.notifier" }
            property string driveId: ""
            running: true
            // notify-send prints the chosen action key and exits when the
            // notification closes, or timeout ends it (noticeCommand); the
            // Process goes with it either way.
            stdout: StdioCollector {
                onStreamFinished: {
                    root.notificationAction(notifier.driveId, text.trim())
                    notifier.destroy()
                }
            }
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

    // Called once the output is in and once the process is gone, which come
    // in either order: from the output alone, a process not yet reaped made
    // this return, and the rest of an ejection never ran.
    function next() {
        if (actionProc.running || actionProc.job) return
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
            // Closed for every other job too: a `gio mount` that wants a
            // password would otherwise wait on stdin for good.
            if (!secret.length) { stdinEnabled = false; return }
            write(secret)
            actionProc.job.secret = ""
            stdinEnabled = false
        }
        onExited: {
            stdinEnabled = true
            Qt.callLater(root.next)
        }
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

    // Read only for the preview: every start used to read the sample and keep
    // its text, preview or not.
    FileView {
        id: sampleFile
        path: root.preview ? Paths.shellFile("tests/fixtures/drives-sample.json") : ""
        printErrors: false
        onLoaded: if (root.preview) root.applySample(text())
    }

    // ---- watching ---------------------------------------------------------------
    // Two small C watchers say when to read: `udisksctl monitor` for every
    // UDisks2 object that comes, goes or changes (and udisksd going away and
    // coming back), and `gio mount -o` for gvfs - phones, which UDisks2 never
    // sees, and their mounts - only while gvfs-mtp is installed. Each line
    // restarts a 400 ms wait, then `drives.py list` reads everything once.
    // Before, a python process (drives.py monitor with PyGObject and
    // dbus-python) stayed for the whole session to hear the same signals:
    // ~20 MB for events that come a few times a week; the watchers hold
    // about 1 MB each, and a plug or a mount costs one read of ~0.1-0.3 s.
    // Bound to the shell (Paths.bound) like every long-running helper.
    property var readState: Logic.emptyReadState()
    property bool listed: false
    property bool readQueued: false

    function readSoon() { readDebounce.restart() }

    function readNow() {
        readRetry.stop()
        if (listProc.running) { readQueued = true; return }
        listProc.running = true
    }

    function applyRead(text) {
        const step = Logic.settle(readState, Logic.readResult(text))
        readState = step.state
        if (step.say === "error") {
            handleMessage({ kind: "error" })
            // A watcher's line reads sooner (readSoon replaces this).
            readRetry.interval = Logic.retryDelay(step.state.retries)
            readRetry.restart()
            return
        }
        if (step.say !== "drives") return
        listed = true
        handleMessage({ kind: "drives", drives: step.state.drives, phones: step.state.phones, mtp: step.state.mtp })
        for (const event of step.events) handleMessage(event)
    }

    // The first read comes from here, merged with the watchers' first lines.
    Component.onCompleted: readSoon()
    Timer { id: readDebounce; interval: Logic.DEBOUNCE_MS; onTriggered: root.readNow() }
    Timer { id: readRetry; onTriggered: root.readNow() }

    Process {
        id: listProc
        stderr: ErrorLog { label: "DrivesService.listProc" }
        command: [Paths.script("drives.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyRead(text)
                // Something changed while this read ran: read once more.
                if (root.readQueued) {
                    root.readQueued = false
                    Qt.callLater(root.readNow)
                }
            }
        }
    }

    // A watcher that ends starts again after a growing pause, five times in a
    // row at most; one that ran for a minute counts anew. Crash restarts pause
    // through a flag so the `running` binding survives. A watcher started
    // again may have missed something meanwhile, so a read follows.
    property bool udisksPaused: false
    property int udisksFailures: 0
    Process {
        id: udisksWatch
        stderr: ErrorLog { label: "DrivesService.udisksWatch" }
        running: !root.udisksPaused
        command: Paths.bound(["udisksctl", "monitor"])
        stdout: SplitParser { onRead: data => { if (Logic.watcherNews(data)) root.readSoon() } }
        onRunningChanged: {
            if (running) {
                udisksHealthy.restart()
                if (root.udisksFailures > 0) root.readSoon()
                return
            }
            udisksHealthy.stop()
            if (root.udisksPaused) return
            root.udisksFailures += 1
            const delay = Logic.watcherRestartDelay(root.udisksFailures)
            // Given up: no drive would show up any more, so the page says the
            // drives are unavailable rather than "appear here when you
            // connect them" (the resident monitor's end said so too).
            if (delay < 0) { root.available = false; return }
            root.udisksPaused = true
            udisksRestart.interval = delay
            udisksRestart.restart()
        }
    }
    Timer { id: udisksRestart; onTriggered: root.udisksPaused = false }
    Timer { id: udisksHealthy; interval: 60000; onTriggered: root.udisksFailures = 0 }

    // Only once a read has said gvfs-mtp is there: without it phones cannot
    // be listed at all, and nothing else needs gvfs' events.
    property bool gioPaused: false
    property int gioFailures: 0
    Process {
        id: gioWatch
        stderr: ErrorLog { label: "DrivesService.gioWatch" }
        running: root.listed && root.mtpAvailable && !root.gioPaused
        command: Paths.bound(["gio", "mount", "-o"])
        stdout: SplitParser { onRead: data => { if (Logic.watcherNews(data)) root.readSoon() } }
        onRunningChanged: {
            if (running) {
                gioHealthy.restart()
                if (root.gioFailures > 0) root.readSoon()
                return
            }
            gioHealthy.stop()
            if (root.gioPaused || !root.listed || !root.mtpAvailable) return
            root.gioFailures += 1
            const delay = Logic.watcherRestartDelay(root.gioFailures)
            if (delay < 0) return
            root.gioPaused = true
            gioRestart.interval = delay
            gioRestart.restart()
        }
    }
    Timer { id: gioRestart; onTriggered: root.gioPaused = false }
    Timer { id: gioHealthy; interval: 60000; onTriggered: root.gioFailures = 0 }
}
