pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "shortcuts/ShortcutLogic.js" as Logic

// Settings > Shortcuts: every key binding of the running compositor
// (`hyprctl -j binds`) and the user's own shortcuts from
// ~/.config/buchhwin-shell/shortcuts.json. Custom shortcuts are runtime binds
// (HyprCompat bindExec/unbind, description "Custom: …"), applied at start,
// whenever the file changes and after Hyprland reloads its config (which drops
// them). The Hyprland config files stay untouched.
Singleton {
    id: root

    property var binds: []
    property var custom: []
    property bool storeLoaded: false
    property bool loading: false
    // Combinations of stored shortcuts that a config bind already uses.
    property var conflicts: []
    property string message: ""
    property bool messageError: false
    // Sync after the next binds snapshot.
    property bool syncPending: true
    // Changes were sent; binds are re-read before anything else is planned,
    // so a second sync cannot bind the same shortcut twice.
    property bool applying: false

    readonly property var rows: Logic.rows(binds, custom, entry => labelFor(entry))

    function labelFor(entry) {
        if (!entry.app) return entry.command
        const app = DesktopEntries.applications.values.find(item => item.id === entry.app)
        return app ? app.name : entry.app
    }
    function iconFor(entry) {
        const app = entry.app ? DesktopEntries.applications.values.find(item => item.id === entry.app) : null
        return app ? LauncherService.iconSource(app.icon) : ""
    }
    function comboOf(entry) { return Logic.comboOf(entry) }
    function keyParts(entry) { return Logic.keyParts(Logic.modmask(entry.mods), entry.key) }
    function grouped(query) { return Logic.grouped(rows, query) }
    function comboError(mods, key) { return Logic.comboError(mods, key) }
    function commandError(command) { return Logic.commandError(command) }
    function captureKey(key, modifiers, scanCode) { return Logic.captureKey(key, modifiers, scanCode) }

    // "" when the combination is free, otherwise what uses it.
    function usedBy(mods, key) {
        const entry = custom.find(item => Logic.modmask(item.mods) === Logic.modmask(mods) && item.key.toLowerCase() === String(key).toLowerCase())
        if (entry) return labelFor(entry)
        // Own binds without a stored entry are about to be removed.
        return Logic.conflictFor(binds.filter(bind => !Logic.ownBind(bind)), mods, key)
    }

    function refresh() {
        if (applying) return
        if (bindsProc.running) { refreshAgain.running = true; return }
        loading = true
        bindsProc.running = true
    }

    function sync() {
        syncPending = true
        refresh()
    }

    function say(text, isError) {
        message = text
        messageError = isError
    }

    // { mods, key, app } or { mods, key, command }; returns an error text or "".
    function add(entry) {
        const error = Logic.comboError(entry.mods, entry.key) || (entry.app ? "" : Logic.commandError(entry.command))
        if (error) return error
        const used = usedBy(entry.mods, entry.key)
        if (used) return "Already used by " + used
        const normalized = Logic.normalizeEntry(entry)
        if (!normalized) return "This shortcut cannot be saved"
        save(custom.concat([normalized]))
        say(Logic.comboOf(normalized) + " added", false)
        return ""
    }

    function remove(entry) {
        const mask = Logic.modmask(entry.mods)
        save(custom.filter(item => !(Logic.modmask(item.mods) === mask && item.key.toLowerCase() === entry.key.toLowerCase())))
        say(Logic.comboOf(entry) + " removed", false)
    }

    function save(list) {
        custom = list
        storeFile.setText(Logic.serializeStore(list))
        sync()
    }

    function apply() {
        const plan = Logic.syncPlan(binds, custom)
        conflicts = plan.conflicts
        const overrides = {}
        for (const id of Object.keys(LauncherService.appOverrides)) overrides[id] = Paths.script(LauncherService.appOverrides[id])
        const commands = []
        try {
            for (const item of plan.unbind) commands.push(HyprCompat.commands.unbind(item.mods, item.key))
            for (const entry of plan.bind)
                commands.push(HyprCompat.commands.bindExec(entry.mods, entry.key, Logic.commandFor(entry, overrides), Logic.descriptionFor(entry)))
        } catch (error) {
            console.warn("buchhwin-shell: shortcut rejected:", error)
            say("A shortcut could not be applied", true)
            return
        }
        if (!commands.length) return
        applying = true
        HyprCompat.configure(HyprCompat.commands.combine(commands))
        rereadDelay.restart()
    }

    Process {
        id: bindsProc
        stderr: ErrorLog { label: "ShortcutService.bindsProc" }
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.binds = Logic.parseBinds(text)
                root.loading = false
                if (root.syncPending && root.storeLoaded && HyprCompat.detected) {
                    root.syncPending = false
                    root.apply()
                }
            }
        }
    }
    Timer { id: refreshAgain; interval: 100; onTriggered: root.refresh() }
    // Read the binds back once Hyprland has processed the changes.
    Timer {
        id: rereadDelay
        interval: 500
        onTriggered: {
            root.applying = false
            root.refresh()
        }
    }
    // A reload applies the config files first; custom binds follow.
    Timer { id: reloadDelay; interval: 400; onTriggered: root.sync() }

    // Commands issued before HyprCompat knows the config format would be queued
    // without a way to read the result back; wait for the detection instead.
    Connections {
        target: HyprCompat
        function onDetectedChanged() { if (HyprCompat.detected && root.syncPending) root.refresh() }
    }
    Connections {
        target: HyprlandService
        function onConfigReloaded() { reloadDelay.restart() }
    }

    FileView {
        id: storeFile
        path: Paths.configDir + "/shortcuts.json"
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            if (root.storeLoaded && !text().trim().length) return
            root.custom = Logic.parseStore(text())
            root.storeLoaded = true
            root.sync()
        }
        onLoadFailed: {
            // Only a missing file at startup means "no shortcuts"; later it is a
            // replacement in progress.
            if (root.storeLoaded) return
            root.custom = []
            root.storeLoaded = true
            root.sync()
        }
        onFileChanged: reload()
    }
}
