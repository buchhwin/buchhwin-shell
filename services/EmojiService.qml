pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "emoji/EmojiLogic.js" as Logic

// The emoji list, the search over it, and the ones that were picked before.
//
// The list is config/emoji.json, built once from the Unicode and CLDR data by
// scripts/build-emoji-data.py and checked in, so nothing has to be installed
// or parsed at runtime beyond reading one file. It is loaded the first time
// the picker or the launcher asks for it and stays loaded afterwards.
Singleton {
    id: root

    property var entries: []
    property var groups: []
    property var recent: []
    readonly property bool loaded: entries.length > 0
    // 0 = as the emoji comes, 1-5 = the Unicode skin tones.
    readonly property int tone: Math.max(0, Math.min(5, SettingsService.value("emoji.tone")))
    readonly property var toneLabels: Logic.TONE_LABELS

    // One read, on the first ask. Before `preload: false` the FileView read
    // the file when the service was created, which is at start - the picker's
    // panel exists from the first frame - so every session parsed 172 KB into
    // a few MB of objects whether or not the picker was ever opened. Turning
    // `preload` on is what reads it: `reload()` reads a file *again* and does
    // nothing for one that was never read (Quickshell 0.3.2, tried). A read
    // that failed is not tried again, which is what one read at start did.
    //
    // The ask comes from a binding (the picker's `results` calls `search`),
    // so nothing here may write a property that it has just read: a
    // `requested` flag set in the same evaluation was a binding loop. The
    // FileView's own `preload` is the flag, and it is switched a turn later.
    function load() {
        if (loaded || listFile.preload) return
        Qt.callLater(() => { listFile.preload = true })
    }

    function search(query, group) {
        load()
        if (group === "recent" && !String(query || "").trim().length)
            return Logic.recentEntries(recent, entries)
        return Logic.search(entries, query, group, 500)
    }

    // The emoji as it would be inserted, with the chosen skin tone.
    function text(entry) { return Logic.withTone(entry, tone) }

    function setTone(value) { SettingsService.set("emoji.tone", value) }

    // Picking one: it goes to the clipboard, the way the calculator and the
    // clipboard history hand things over. The shell never types into another
    // window - the panel holds the keyboard until it closes, and a keystroke
    // sent afterwards would land wherever the focus happened to go.
    function pick(entry) {
        const value = text(entry)
        if (!value.length) return ""
        Quickshell.clipboardText = value
        recent = Logic.remember(recent, value)
        recentFile.setText(Logic.serializeRecent(recent))
        return value
    }

    FileView {
        id: listFile
        path: Paths.shellFile("config/emoji.json")
        preload: false
        onLoaded: {
            let data = null
            try {
                data = JSON.parse(text())
            } catch (error) {
                console.warn("buchhwin-shell: emoji list unreadable")
                return
            }
            if (!data || !Array.isArray(data.emoji)) return
            root.entries = data.emoji
            root.groups = Array.isArray(data.groups) ? data.groups : []
        }
        onLoadFailed: console.warn("buchhwin-shell: emoji list missing")
    }

    FileView {
        id: recentFile
        path: Paths.stateDir + "/emoji.json"
        atomicWrites: true
        printErrors: false
        watchChanges: false
        Component.onCompleted: reload()
        onLoaded: root.recent = Logic.parseRecent(text())
    }
}
