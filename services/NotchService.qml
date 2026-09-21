pragma Singleton
import Quickshell
import QtQuick
import qs.theme
import "LayoutLogic.js" as Logic
import "notch/NotchLogic.js" as NotchLogic

// Shared state of the notch (desktop mode "notch", shell/notch/Notch.qml):
// its settings, the expansion requested over IPC (tests cannot hover) and a
// synthetic track for screenshots. Each notch reports what it shows, as ids
// and sizes only (no titles).
Singleton {
    id: root

    readonly property bool reserve: SettingsService.value("notch.reserve")
    readonly property string fullscreen: SettingsService.value("notch.fullscreen")
    readonly property bool expandOnHover: SettingsService.value("notch.expandOnHover")
    // ---- the size of the two shapes ---------------------------------------
    // Both are dragged in the layout editor: the strip only horizontally - its
    // height is the notch's own - and the overview freely. Neither is a
    // preset any more; "wide" and "stacked" were the two sizes on offer and
    // are read once, here, to fill the width in for a session that had them.
    readonly property string shape: SettingsService.value("notch.shape") === "pill" ? "pill" : "notch"
    readonly property bool pill: shape === "pill"
    readonly property real storedCollapsedWidth: SettingsService.value("notch.collapsedWidth")
    readonly property real storedExpandedWidth: SettingsService.value("notch.expandedWidth")
    readonly property real storedExpandedHeight: SettingsService.value("notch.expandedHeight")
    // Zero means "never dragged", and the clamp in NotchLogic.expandedSize
    // fills the default in. The two presets this used to fall back to are
    // gone: nothing had written them since the notch grew a corner to pull.
    readonly property real expandedWidth: storedExpandedWidth
    // How many columns that width is worth. A wider notch gets more columns
    // rather than wider cells, so a cell stays the size of what it holds.
    readonly property int columns: NotchLogic.gridColumns(expandedWidth, Metrics.notchGridCell, Metrics.notchGridColumns)
    readonly property bool wide: columns > 2
    // What the notch shows, in the order the user put it in.
    readonly property var collapsedItems: Logic.notchItems(LayoutService.notchLayout, "collapsed")
    readonly property var expandedItems: Logic.notchItems(LayoutService.notchLayout, "expanded")
    readonly property var collapsedTypes: collapsedItems.map(item => item.type)
    readonly property var expandedTypes: expandedItems.map(item => item.type)
    function shows(type) { return expandedTypes.indexOf(type) >= 0 }
    // While the notch is arranged it shows both of its lists at once and every
    // item in them, whether or not it has anything to say: an item left out
    // would make the indices the drop maths produces count a shorter list.
    readonly property bool arranging: LayoutService.notchEditing
    // Which of the notch's two shapes the editor is working on: the strip that
    // is always there, or the overview it opens into. The strip is only as
    // tall as the notch, so it is dragged sideways; the overview freely.
    readonly property string arrangeZone: LayoutService.notchEditZone
    readonly property bool arrangingExpanded: arranging && arrangeZone === "expanded"

    // The notch's own blocks: the four things it draws better than a widget
    // can, and which therefore have no entry in WidgetRegistry. Everything
    // else in the catalogue is a widget and is named by the registry.
    readonly property var blocks: [
        { type: "weather", label: "Weather", icon: "\u{f0590}" },
        { type: "media", label: "Media", icon: "\u{f075a}" },
        { type: "events", label: "Events", icon: "\u{f00ed}" },
        { type: "status", label: "Status", icon: "\u{f05a9}" }
    ]

    // What a type is called and which glyph names it, wherever it comes from.
    function entry(type) {
        for (const block of blocks) if (block.type === type) return block
        const widget = WidgetRegistry.type(type)
        if (widget) return { type: type, label: widget.label, icon: widget.icon }
        return { type: type, label: type, icon: "" }
    }

    // The whole catalogue the notch offers, its own blocks first.
    function catalogue() {
        return blocks.concat(WidgetRegistry.availableTypes()
            .map(widget => ({ type: widget.name, label: widget.label, icon: widget.icon })))
    }
    readonly property int eventCount: Math.max(1, Math.min(4, SettingsService.value("notch.eventCount") || 2))

    // Screen name expanded over IPC or by a click ("" = none).
    property string forcedScreen: ""
    // Synthetic now-playing data (IPC `notch previewMedia`); controls stay disabled.
    property bool mediaPreview: false
    readonly property var previewTrack: ({ title: "Sample track", artist: "Sample artist", playing: true })

    // screen name -> { shown, expanded, rows, width, height }
    property var states: ({})

    function expand(screenName) { forcedScreen = screenName }
    function collapse() { forcedScreen = "" }

    function report(screenName, state) {
        if (JSON.stringify(states[screenName]) === JSON.stringify(state)) return
        const next = Object.assign({}, states)
        next[screenName] = state
        states = next
    }

    function forget(screenName) {
        if (states[screenName] === undefined) return
        const next = Object.assign({}, states)
        delete next[screenName]
        states = next
    }

    function describe() {
        const covered = {}
        for (const screen of Quickshell.screens) covered[screen.name] = HyprlandService.fullscreenReport(screen)
        return JSON.stringify({ mode: LayoutService.mode, reserve: reserve, fullscreen: fullscreen, expandOnHover: expandOnHover,
                                forced: forcedScreen, mediaPreview: mediaPreview, weatherTrackers: WeatherService.trackers,
                                screens: states, coveredBy: covered })
    }
}
