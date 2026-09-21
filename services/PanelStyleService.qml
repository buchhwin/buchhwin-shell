pragma Singleton
import Quickshell
import QtQuick
import "appearance/PanelStyleLogic.js" as Logic

// Panel background colour and transparency per window group
// (Settings > Appearance > Panels). Sliders preview values here while they
// are dragged, so open panels follow at once; settings.json is written on release.
Singleton {
    id: root

    readonly property var groups: Logic.GROUPS
    readonly property real minOpacity: Logic.MIN_OPACITY
    // "auto" (theme colours) or "#rrggbb".
    readonly property string color: Logic.colorSetting(SettingsService.value("appearance.panelColor"))
    readonly property bool customColor: color !== "auto"
    readonly property bool lightColor: customColor && Logic.isLight(color)
    // Group key (or "default" for the global slider) → opacity while dragging.
    property var preview: ({})
    readonly property real defaultOpacity: typeof preview["default"] === "number"
        ? Logic.clampOpacity(preview["default"]) : SettingsService.panelOpacity

    function groupFor(id) { return Logic.groupFor(id) }
    function stored(group) { return SettingsService.value("panelOpacity." + Logic.groupFor(group)) }
    function hasOwnOpacity(group) {
        const key = Logic.groupFor(group)
        return typeof preview[key] === "number" || Logic.isOverride(stored(key))
    }
    // Effective opacity for a ShellPanel id or group key.
    function opacity(id) {
        const key = Logic.groupFor(id)
        const own = typeof preview[key] === "number" ? preview[key] : stored(key)
        return Logic.effectiveOpacity(key, own, defaultOpacity)
    }
    function rgb(hex) { return Logic.parseHex(hex) }
    function hoverRgb(hex) { return Logic.hoverRgb(hex) }
    function normalizeHex(text) { return Logic.normalizeHex(text) }
    function isLight(hex) { return Logic.isLight(hex) }
    function matchesTheme(dark) { return Logic.matchesTheme(color, dark) }

    function setPreview(group, value) {
        const next = Object.assign({}, preview)
        next[group] = Logic.clampOpacity(value)
        preview = next
    }
    function clearPreview(group) {
        if (!(group in preview)) return
        const next = Object.assign({}, preview)
        delete next[group]
        preview = next
    }
    function rounded(value) { return Math.round(Logic.clampOpacity(value) * 100) / 100 }

    function setDefaultOpacity(value) {
        SettingsService.set("appearance.panelOpacity", rounded(value))
        clearPreview("default")
    }
    // Starting an own value copies the current effective opacity.
    function setOwnOpacity(group, value) {
        const key = Logic.groupFor(group)
        SettingsService.set("panelOpacity." + key, rounded(value === undefined ? opacity(key) : value))
        clearPreview(key)
    }
    function useDefaultOpacity(group) {
        const key = Logic.groupFor(group)
        SettingsService.set("panelOpacity." + key, -1)
        clearPreview(key)
    }
    function resetAllOpacities() {
        for (const group of Logic.GROUPS)
            if (Logic.isOverride(stored(group.key))) SettingsService.set("panelOpacity." + group.key, -1)
        preview = {}
    }
    // "auto" or any colour Logic.normalizeHex accepts; returns false when invalid.
    // Text colours come from the theme (every component reads Colors.text), so
    // a colour of the other brightness also switches the theme (`dark` is the
    // current theme brightness). The Appearance page hints when they disagree later.
    function setColor(value, dark) {
        const next = value === "auto" ? "auto" : Logic.normalizeHex(value)
        if (!next.length || !SettingsService.set("appearance.panelColor", next)) return false
        const theme = Logic.themeForColor(next, dark)
        if (theme.length) SettingsService.set("appearance.theme", theme)
        return true
    }
}
