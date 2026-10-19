import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "Harness.js" as T

// A waiting state turns its glyph - in Full motion, in a window on screen -
// and keeps the still hourglass otherwise; an empty state never turns.
ShellRoot {
    id: root

    // Outside any window: a page kept in a closed panel.
    EmptyState { id: offscreen; icon: Icons.busy; title: "Searching …" }

    FloatingWindow {
        visible: true
        implicitWidth: 300
        implicitHeight: 300
        Column {
            EmptyState { id: waiting; width: 300; icon: Icons.busy; title: "Searching …" }
            EmptyState { id: empty; width: 300; icon: Icons.search; title: "No results" }
            EmptyState { id: told; width: 300; icon: Icons.search; title: "Loading"; busy: true }
        }
    }

    function glyphOf(state) {
        for (const child of state.children[0].children)
            if (child.glyph !== undefined) return child
        return null
    }

    Timer {
        id: shown
        interval: 200
        onTriggered: {
            T.eq([waiting.busy, empty.busy], [true, false], "the hourglass is a waiting state, any other glyph is not")
            T.eq(waiting.spinning, true, "in Full motion, on screen, it turns")
            T.eq(glyphOf(waiting).glyph, Icons.refresh, "as the spinner a busy field shows")
            T.eq(empty.spinning, false, "an empty state stays still")
            T.eq(told.spinning, true, "a caller can say it waits whatever the glyph")
            T.eq(offscreen.spinning, false, "and nothing turns outside a window on screen")
            SettingsService.set("appearance.animationMode", "reduced")
            T.eq(waiting.spinning, false, "Reduced keeps it still")
            T.eq([glyphOf(waiting).glyph, glyphOf(waiting).rotation], [Icons.busy, 0], "as the upright hourglass")
            SettingsService.set("appearance.animationMode", "full")
            T.finish("EmptyStateTest")
        }
    }
    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        property int waits: 0
        onTriggered: {
            if (!SettingsService.loaded && ++waits < 250) return
            stop()
            shown.start()
        }
    }
}
