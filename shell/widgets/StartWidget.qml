import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.widgets

// The dock's start button: the fastfetch Saturn (shell/components/
// SaturnGlyph.qml) in the colours `ff` gives it. A click opens the start menu
// above it (shell/startmenu), or the launcher (Settings > Dock > Start
// button, WidgetRegistry.actionOf) - the registry's action, which the pill
// runs with the button's place, so the panel comes out of it like any panel
// out of its pill. `icon` stays the launcher's glyph: the editor's picker and
// inspector list the type by it.
WidgetBase {
    id: root
    icon: Icons.apps
    glyph: saturn
    label: "Start"
    name: "Start"

    // The dock can go all the way to see-through (its own transparency);
    // the mark then stands on the wallpaper and takes a rim to stay there.
    readonly property bool bare: PanelStyleService.opacity("dock") < PanelStyleService.minOpacity

    Component {
        id: saturn
        SaturnGlyph {
            implicitHeight: Metrics.startGlyphHeight * root.scaleFactor
            implicitWidth: Metrics.startGlyphWidth * root.scaleFactor
            halo: root.bare
        }
    }
}
