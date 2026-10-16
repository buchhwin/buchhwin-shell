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
//
// While its panel is open out of it on this screen the pill keeps the
// button's backing (`panelOpen`), as a pressed start button does; with the
// dock's keyboard on it, the keys' ring (`keyFocus`, DockService.keyOnStart).
WidgetBase {
    id: root
    icon: Icons.apps
    glyph: saturn
    label: "Start"
    name: "Start"

    // The dock can go all the way to see-through (its own transparency);
    // the mark then stands on the wallpaper and takes a rim to stay there.
    readonly property bool bare: PanelStyleService.opacity("dock") < PanelStyleService.minOpacity

    readonly property string screenName: instance ? String(instance.screen || "") : ""
    readonly property bool panelOpen: screenName.length > 0 && PanelService.active === WidgetRegistry.actionOf("start")
        && PanelService.screenName === screenName && PanelService.args && PanelService.args.fromDock === true
    // The dock's service only while the dock is on (testing.md pitfall 101).
    readonly property bool keyFocus: screenName.length > 0 && SettingsService.value("dock.enabled") === true
        && DockService.keyOnStart && DockService.keyboardScreen === screenName

    Component {
        id: saturn
        SaturnGlyph {
            implicitHeight: Metrics.startGlyphHeight * root.scaleFactor
            implicitWidth: Metrics.startGlyphWidth * root.scaleFactor
            halo: root.bare
        }
    }
}
