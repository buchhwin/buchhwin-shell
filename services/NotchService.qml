pragma Singleton
import Quickshell
import QtQuick
import qs.theme
import "LayoutLogic.js" as Logic
import "notch/NotchLogic.js" as NotchLogic
import "notch/NotchDisplay.js" as NotchDisplay
import "dock/DockLogic.js" as DockLogic

// Shared state of the notch (desktop mode "notch", shell/notch/Notch.qml):
// its settings, the expansion requested over IPC (tests cannot hover) and a
// synthetic track for screenshots. Each notch reports what it shows, as ids
// and sizes only (no titles).
Singleton {
    id: root

    readonly property bool reserve: SettingsService.value("notch.reserve")
    readonly property string fullscreen: SettingsService.value("notch.fullscreen")
    // How it opens (services/notch/NotchLogic.js): on hover, on a click, never.
    readonly property string hoverMode: NotchLogic.hoverMode(SettingsService.value("notch.hoverMode"))
    readonly property bool expandOnHover: NotchLogic.hoverOpens(hoverMode)
    readonly property int openDelay: NotchLogic.delay(SettingsService.value("notch.openDelay"), NotchLogic.OPEN_DELAY)
    readonly property int closeDelay: NotchLogic.delay(SettingsService.value("notch.closeDelay"), NotchLogic.CLOSE_DELAY)
    readonly property string clickAction: SettingsService.value("notch.clickAction")
    // What a click on the collapsed notch does: "expand" or "dashboard".
    readonly property string clickResult: NotchLogic.clickResult(hoverMode, clickAction)
    // The middle and the right button (NotchLogic.buttonAction): "none" or
    // what they open.
    readonly property string middleAction: NotchLogic.buttonAction(SettingsService.value("notch.middleAction"))
    readonly property string rightAction: NotchLogic.buttonAction(SettingsService.value("notch.rightAction"))
    readonly property bool swipe: SettingsService.value("notch.swipe") !== false
    // The neutral status glyphs in the accent instead of white: "off",
    // "overview" or "all" (the strip too). The two flags are what the surfaces
    // read; a glyph that shows a state keeps its colour either way.
    readonly property string accentGlyphs: NotchLogic.accentGlyphs(SettingsService.value("notch.accentGlyphs"))
    readonly property bool overviewGlyphsInAccent: NotchLogic.glyphsInAccent(accentGlyphs, "overview")
    readonly property bool stripGlyphsInAccent: NotchLogic.glyphsInAccent(accentGlyphs, "strip")
    // Panels open out of the notch rather than below it (ShellPanel).
    readonly property bool panelsFromNotch: SettingsService.value("notch.panelOrigin") === "notch" && !pill
    // ---- the collapsed body -----------------------------------------------
    // How tall it is, how round its bottom corners are and how much air the
    // strip keeps at both ends. The theme's tokens are the defaults and the
    // fallback; a preset carries all three, which is how Classic gets the
    // 32 / 11 / 16 body the notch had before Island. The expanded shape keeps
    // the theme's own sizes.
    readonly property int bodyHeight: NotchLogic.bodySize(SettingsService.value("notch.bodyHeight"), NotchLogic.BODY_HEIGHT, Metrics.notchHeight)
    readonly property int bodyRadius: NotchLogic.bodySize(SettingsService.value("notch.bodyRadius"), NotchLogic.BODY_RADIUS, Metrics.notchRadius)
    // The radius the body is drawn with: the setting under the shell corner
    // scale, as every other corner is (Metrics.cornerScale, 1 at the designed
    // 20). `bodyRadius` stays the stored number, which is what a preset saves.
    readonly property int drawnBodyRadius: Math.round(bodyRadius * Metrics.cornerScale)
    readonly property int bodyPadding: NotchLogic.bodySize(SettingsService.value("notch.bodyPadding"), NotchLogic.BODY_PADDING, Metrics.notchPadding)
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
    // ---- beside a taskbar ---------------------------------------------------
    // notch.dockDuplicates "hide": on a screen with a dock along the whole
    // edge and always there, the strip leaves out the readouts that dock holds
    // as well - the time, Wi-Fi, the battery twice on one screen otherwise
    // (NotchLogic.dockDuplicateTypes). Read from the settings and the layout,
    // never from DockService, and only with "hide": the default "keep" asks
    // nothing of the dock, and a dock that is off builds nothing of its own.
    readonly property string dockDuplicates: NotchLogic.dockDuplicates(SettingsService.value("notch.dockDuplicates"))
    readonly property bool dockDuplicatesHidden: dockDuplicates === "hide"
    readonly property var dockScreenNames: dockDuplicatesHidden
        ? DockLogic.screensFor(SettingsService.value("dock.screens"), Quickshell.screens.map(screen => screen.name)) : []
    readonly property var dockReadouts: dockDuplicatesHidden
        ? NotchLogic.DOCK_READOUTS.filter(type => Logic.dockHasType(LayoutService.dockLayout, type)) : []
    // The types the strip on this screen leaves out; [] with "keep".
    function dockDuplicatesOn(screenName) {
        if (!dockDuplicatesHidden) return []
        return NotchLogic.dockDuplicateTypes(dockDuplicates, {
            enabled: SettingsService.value("dock.enabled") === true,
            span: SettingsService.value("dock.span"),
            visibility: SettingsService.value("dock.visibility"),
            screens: dockScreenNames
        }, dockReadouts, screenName, arranging)
    }
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

    // ---- the notch as the display -----------------------------------------
    // Volume, a notification, a track change: shown *in* the notch instead of
    // in a surface below it. Who may, and who wins when two ask at once, is
    // NotchDisplay; this is only the three slots and their order in time.
    //
    // There is no timer here. Each display already has one - the OSD hides
    // after 1400 ms, a popup after the notification duration - so the notch
    // mirrors what is on rather than keeping a second clock that can disagree
    // with the first.
    readonly property bool displayOsd: SettingsService.value("notch.displayOsd")
    readonly property bool displayNotifications: SettingsService.value("notch.displayNotifications")
    readonly property bool displayMedia: SettingsService.value("notch.displayMedia")
    readonly property bool osdRing: SettingsService.value("notch.osdStyle") !== "bar"
    function displayEnabled(kind) {
        return kind === "osd" ? displayOsd : kind === "notification" ? displayNotifications
            : kind === "media" ? displayMedia : false
    }

    // kind -> { stamp, content } | null. `stamp` only goes up, so "the most
    // recent wins" is a comparison rather than a history.
    property var displaySlots: ({})
    property int displayStamp: 0
    // The screen the display belongs to: the focused one at the moment it was
    // set. Only that notch takes it; the others stay as they are.
    property string displayScreen: ""

    function setDisplay(kind, screenName, content) {
        const slots = Object.assign({}, displaySlots)
        if (content) {
            displayStamp += 1
            slots[kind] = { stamp: displayStamp, content: content }
            displayScreen = screenName
        } else {
            slots[kind] = null
        }
        displaySlots = slots
    }

    readonly property var display: NotchDisplay.current(displaySlots)
    readonly property string displayKind: display ? display.kind : ""

    // Whether the notch on this screen may take this kind right now. The
    // caller knows whether it is the focused screen; everything else is here.
    function takesDisplay(kind, screenName) {
        const state = states[screenName] || null
        return NotchDisplay.takes(kind, {
            enabled: displayEnabled(kind),
            notchShown: LayoutService.notchShown,
            hasNotch: !!(state && state.shown) && LayoutService.notchRect(screenName) !== null,
            overviewOpen: !!(state && state.expanded),
            arranging: arranging
        })
    }

    // Screens held expanded over IPC, by a click or by the layout editor.
    // A list, not one name: the editor sits on every monitor at once, and
    // each of its notches has to be the expanded one it arranges - with a
    // single name the last editor to ask won, and the others arranged a
    // collapsed notch under an expanded outline (seen with three monitors).
    property var forcedScreens: []
    // Synthetic now-playing data (IPC `notch previewMedia`); controls stay disabled.
    property bool mediaPreview: false
    readonly property var previewTrack: ({ title: "Sample track", artist: "Sample artist", playing: true })

    // screen name -> { shown, expanded, rows, width, height }
    property var states: ({})

    function expand(screenName) {
        if (forcedScreens.indexOf(screenName) < 0) forcedScreens = forcedScreens.concat([screenName])
    }
    // One screen, or every one when none is named (the IPC `collapse`).
    function collapse(screenName) {
        forcedScreens = screenName ? forcedScreens.filter(name => name !== screenName) : []
    }

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
        return JSON.stringify({ mode: LayoutService.desktopMode, reserve: reserve, fullscreen: fullscreen, hoverMode: hoverMode,
                                clickAction: clickAction, openDelay: openDelay, closeDelay: closeDelay, accentGlyphs: accentGlyphs,
                                dockDuplicates: dockDuplicates,
                                bodyHeight: bodyHeight, bodyRadius: bodyRadius, bodyPadding: bodyPadding,
                                presets: LayoutService.notchPresets.length,
                                forced: forcedScreens.join(","), mediaPreview: mediaPreview, weatherTrackers: WeatherService.trackers,
                                display: displayKind, displayScreen: displayScreen,
                                screens: states, coveredBy: covered })
    }
}
