pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "shortcuts/ShortcutLogic.js" as Logic

// Settings > Shortcuts: every key binding of the running compositor
// (`hyprctl -j binds`) and the user's own shortcuts from
// ~/.config/buchhwin-shell/shortcuts.json. Custom shortcuts are runtime binds
// (HyprCompat bindExec/unbind, a shell action's global shortcut through
// Logic.globalBind; description "Custom: …"), applied at start,
// whenever the file changes and after Hyprland reloads its config (which drops
// them). The Hyprland config files stay untouched.
Singleton {
    id: root

    property var binds: []
    property var custom: []
    // Where each built-in shortcut sits by default, read out of
    // hypr/hyprland.lua, and where the user has moved any of them.
    //
    // It has to be read from the file. With a Lua configuration every bind is
    // a closure, so `hyprctl -j binds` answers `dispatcher: "__lua"` and an
    // internal index - the *name* of a shortcut is readable from outside, the
    // *action* is not, and neither is the combination it started on once it
    // has moved. So the configuration keeps the only copy of what a shortcut
    // does, and this file only ever says where it sits.
    property var defaults: []
    property var keyOverrides: ({})
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

    // Names from the desktop entries, which arrive one at a time after the
    // shell is up: the rows follow LauncherService's count of finished scans
    // rather than every single entry (`byId` alone would not be followed).
    readonly property var rows: {
        LauncherService.entriesRevision
        return Logic.rows(binds, custom, entry => labelFor(entry))
    }

    function labelFor(entry) {
        if (!entry.app) return Logic.entryLabel(entry)
        const app = DesktopEntries.byId(entry.app)
        return app ? app.name : entry.app
    }
    function iconFor(entry) {
        const app = entry.app ? DesktopEntries.byId(entry.app) : null
        return app ? LauncherService.iconSource(app.icon) : ""
    }
    // The shell actions a shortcut can be put on, as { value, label }
    // (ShellShortcuts.BINDABLE: the start menu).
    readonly property var shellActions: Logic.shellActions()
    function comboOf(entry) { return Logic.comboOf(entry) }

    // The combination a shortcut started on. For one that has not been moved
    // that is where it is now; for one that has, the store is the only record.
    // Which built-in a live binding is, found by comparing canonical
    // combinations: the configuration writes "SUPER + D", Hyprland answers a
    // modmask and "D", and neither case nor modifier order agrees.
    function entryFor(modmask, key) {
        const live = Logic.canonicalBind(modmask, key)
        for (const item of defaults) {
            const wanted = keyOverrides[item.combo]
            const now = wanted ? Logic.canonicalCombo(wanted) : item.canon
            if (now === live) return item
        }
        return null
    }
    function defaultCombo(modmask, key) {
        const item = entryFor(modmask, key)
        return item ? item.combo : ""
    }
    // Where a built-in shortcut sits now, by the combination hyprland.lua
    // starts it on ("SUPER + K"), and that as a hint names it ("Super + K",
    // or "Super+K" compact). Hints that name a key ask here rather than
    // spelling it out, so a move in Settings > Shortcuts reaches them too;
    // with nothing moved they read as they always did.
    function keyFor(defaultCombo) { return Logic.currentCombo(keyOverrides, defaultCombo) }
    function keyHint(defaultCombo, compact) { return Logic.comboLabel(keyFor(defaultCombo), compact === true) }
    function keyHintParts(defaultCombo) { return Logic.comboParts(keyFor(defaultCombo)) }
    function movable(modmask, key) { return entryFor(modmask, key) !== null }
    function movedFrom(modmask, key) {
        const item = entryFor(modmask, key)
        return item && keyOverrides[item.combo] ? item.combo : ""
    }

    // Move a built-in shortcut, or put it back. Both write the file the
    // configuration reads and then ask Hyprland to read it again - the
    // overrides are real configuration, so they hold even when this shell is
    // not running, which a runtime bind never could.
    function setKey(fromCombo, toCombo) {
        if (!fromCombo || !toCombo || fromCombo === toCombo) return "Nothing to change"
        if (!defaults.some(item => item.combo === fromCombo)) return "That shortcut is not one of the built-in ones"
        const wanted = Logic.canonicalCombo(toCombo)
        const taken = defaults.find(item => item.combo !== fromCombo
            && Logic.canonicalCombo(keyOverrides[item.combo] || item.combo) === wanted)
        if (taken) return "Already used by " + taken.description
        const next = Object.assign({}, keyOverrides)
        next[fromCombo] = toCombo
        writeKeys(next)
        return ""
    }
    function resetKey(fromCombo) {
        if (!keyOverrides[fromCombo]) return
        const next = Object.assign({}, keyOverrides)
        delete next[fromCombo]
        writeKeys(next)
    }

    function writeKeys(map) {
        keyOverrides = map
        keysFile.setText(Logic.serializeKeyOverrides(map))
        // A reload re-reads the whole configuration, which is the price of the
        // overrides being configuration rather than runtime binds. It is a
        // deliberate, occasional action; nothing here loops. It runs once the
        // file is on disk (`onSaved`), or Hyprland reads the previous keys;
        // a change made while a reload runs gets one more.
    }
    property bool reloadQueued: false
    function requestReload() {
        if (reloadProc.running) reloadQueued = true
        else reloadProc.running = true
    }
    function keyParts(entry) { return Logic.keyParts(Logic.modmask(entry.mods), entry.key) }
    function grouped(query) { return Logic.grouped(rows, query) }
    function rowKeys(list) { return Logic.rowKeys(list) }
    // The sheet's columns, packed by weight rather than laid out in a grid -
    // see `columnise` for why a grid leaves gaps.
    function columnise(list, count) { return Logic.columnise(list, count) }
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

    // { mods, key, app }, { mods, key, shell } or { mods, key, command };
    // returns an error text or "".
    function add(entry) {
        const error = Logic.comboError(entry.mods, entry.key) || (entry.app || entry.shell ? "" : Logic.commandError(entry.command))
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

    // The store as last read or written, so the watch reading this shell's
    // own write back is not taken for a change (storeFile's onLoaded).
    property string storeText: ""

    function save(list) {
        custom = list
        storeText = Logic.serializeStore(list)
        storeFile.setText(storeText)
        sync()
    }

    // What each custom shortcut's bind was made to run, by combination and
    // description: the bind cannot say (a Lua bind reports `__lua`), and a
    // bind with the right name may still run an older command line - one an
    // older shell made with gtk-launch, or one made before the app's desktop
    // entry was read. Those are bound again (Logic.syncPlan).
    property var boundCommands: ({})
    function bindKey(entry) { return Logic.comboOf(entry) + "|" + Logic.descriptionFor(entry) }
    // The command line of a custom shortcut: an app the way the launcher
    // starts it (Logic.commandFor); a shell action's bind sends its global
    // shortcut instead (Logic.globalBind).
    function commandOf(entry) {
        return Logic.commandFor(entry, { app: entry.app ? DesktopEntries.byId(entry.app) : null,
                                         overrides: LauncherService.appOverrides, script: name => Paths.script(name) })
    }

    function apply() {
        // Each entry on its own: a command line a bind cannot hold (a `;`
        // or a control character in a desktop entry's Exec) costs that
        // shortcut, not all of them.
        const built = {}
        let failed = ""
        for (const entry of custom) {
            const text = commandOf(entry)
            try {
                built[bindKey(entry)] = { text: text, bind: entry.shell ? Logic.globalBind(entry)
                                                         : HyprCompat.commands.bindExec(entry.mods, entry.key, text, Logic.descriptionFor(entry)) }
            } catch (error) {
                console.warn("buchhwin-shell: shortcut rejected:", Logic.comboOf(entry), error)
                if (!failed.length) failed = Logic.comboOf(entry)
            }
        }
        // One that cannot be built keeps whatever bind it has.
        const plan = Logic.syncPlan(binds, custom, entry => !built[bindKey(entry)] || boundCommands[bindKey(entry)] === built[bindKey(entry)].text)
        conflicts = plan.conflicts
        if (failed.length) say(failed + " could not be applied", true)
        const commands = []
        const bound = {}
        for (const entry of custom) {
            const key = bindKey(entry)
            if (boundCommands[key] !== undefined) bound[key] = boundCommands[key]
        }
        try {
            for (const item of plan.unbind) commands.push(HyprCompat.commands.unbind(item.mods, item.key))
        } catch (error) {
            console.warn("buchhwin-shell: shortcut rejected:", error)
            say("A shortcut could not be applied", true)
            return
        }
        for (const entry of plan.bind) {
            const ready = built[bindKey(entry)]
            if (!ready) continue
            commands.push(ready.bind)
            bound[bindKey(entry)] = ready.text
        }
        boundCommands = bound
        if (!commands.length) return
        applying = true
        HyprCompat.configure(HyprCompat.commands.combine(commands))
        rereadDelay.restart()
    }

    Process {
        id: reloadProc
        stderr: ErrorLog { label: "ShortcutService.reloadProc" }
        command: ["hyprctl", "reload"]
        onExited: {
            if (root.reloadQueued) {
                root.reloadQueued = false
                Qt.callLater(root.requestReload)
                return
            }
            root.refresh()
        }
    }

    // The configuration is the only record of what a shortcut does and where
    // it started, so it is read rather than asked for.
    FileView {
        path: Paths.shellFile("hypr/hyprland.lua")
        printErrors: false
        onLoaded: root.defaults = Logic.parseDefaults(text())
    }

    FileView {
        id: keysFile
        path: Paths.configDir + "/shortcut-keys.txt"
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root.keyOverrides = Logic.parseKeyOverrides(text())
        onSaved: root.requestReload()
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
    // An app's command line comes from its desktop entry: once a scan has
    // finished (at the start, or an app installed or changed), the binds of
    // app shortcuts are checked again. Nothing is rebound unless a command
    // changed.
    Connections {
        target: LauncherService
        function onEntriesRevisionChanged() { if (root.custom.some(entry => entry.app)) root.sync() }
    }

    FileView {
        id: storeFile
        path: Paths.configDir + "/shortcuts.json"
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            const read = storeFile.text()
            if (!Logic.storeReadIsNews(root.storeLoaded, read, root.storeText)) return
            root.storeText = read
            root.custom = Logic.parseStore(read)
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
