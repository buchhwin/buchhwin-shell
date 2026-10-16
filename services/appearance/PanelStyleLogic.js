.pragma library

// Panel background colour and per-window opacity (Settings > Appearance).
// Opacity values are stored per group in settings.json `panelOpacity.<group>`;
// a negative value means "use the default transparency". Unit tested.

// Hyprland blurs buchhwin-* layers only above ignore_alpha 0.35
// (hypr/windowrules.conf), so the minimum keeps a margin above it.
var MIN_OPACITY = 0.4
var MAX_OPACITY = 1
// A light panel is dark ink on a light glass, and what shows through a dark
// wallpaper pulls the glass towards the ink: at the default 0.74 over black a
// light card is #aeafb0, and the muted text tuned for an opaque one fell to
// 2.8:1 (3.5:1 over a dark teal wallpaper). A dark panel over a
// bright wallpaper has the same problem the other way round, but the light
// side is the one the ink cannot win back: no grey reads at 4.5:1 on a light
// glass at 0.4 over black. So a light surface never goes below this, and the
// light inks (theme/Colors.qml) are measured on a card at exactly this over
// black - the darkest a light card can get. 0.9 keeps muted text at a grey
// (#505662, 5:1 on that card) rather than near black, and the glass still
// shows the wallpaper's colour.
var LIGHT_MIN_OPACITY = 0.9
// WCAG relative luminance where black and white text have equal contrast.
var LIGHT_LUMINANCE = 0.179

// Order and labels of Settings > Appearance > Individual windows.
var GROUPS = [
    { key: "settings", label: "Settings" },
    { key: "controlCenter", label: "Control center" },
    { key: "dashboard", label: "Dashboard" },
    { key: "launcher", label: "Launcher" },
    { key: "notificationCenter", label: "Notification center" },
    { key: "notificationPopups", label: "Notification popups" },
    { key: "sessionMenu", label: "Session menu" },
    { key: "clipboard", label: "Clipboard" },
    { key: "overview", label: "Overview" },
    { key: "switcher", label: "Window switcher" },
    { key: "popups", label: "Pill popups & dialogs" },
    { key: "pillBar", label: "Pill bar" },
    { key: "widgets", label: "Desktop widgets" },
    { key: "osd", label: "Volume & brightness OSD" }
]

// ShellPanel ids whose group has another name. Unknown ids (pill popups,
// Wi-Fi and pairing dialogs, future panels) fall back to FALLBACK_GROUP.
var PANEL_GROUPS = {
    notifications: "notificationCenter",
    powerMenu: "sessionMenu",
    // The emoji picker is a launcher with one kind of result in it.
    emoji: "launcher"
}
var FALLBACK_GROUP = "popups"

function isGroup(key) {
    return GROUPS.some(function (group) { return group.key === key })
}

function groupFor(id) {
    const name = String(id || "")
    if (isGroup(name)) return name
    return PANEL_GROUPS[name] || FALLBACK_GROUP
}

function clampOpacity(value) {
    const number = Number(value)
    if (!isFinite(number)) return MAX_OPACITY
    return Math.max(MIN_OPACITY, Math.min(MAX_OPACITY, number))
}

function isOverride(stored) {
    return typeof stored === "number" && isFinite(stored) && stored >= 0
}

// Opacity of a panel or group: its own value, or the default transparency.
// Small indicators (pill bar, OSD, notification popups) follow it as well.
function effectiveOpacity(id, stored, defaultOpacity) {
    return clampOpacity(isOverride(stored) ? stored : defaultOpacity)
}

// The opacity a surface is drawn with: the chosen one, but a light surface
// not below LIGHT_MIN_OPACITY. The setting keeps what was chosen, so a
// dark panel colour later gets it back.
function surfaceOpacity(alpha, light) {
    const value = clampOpacity(alpha)
    return light ? Math.max(LIGHT_MIN_OPACITY, value) : value
}

// "#rgb", "rgb", "#rrggbb" or "rrggbb" (surrounding spaces allowed) →
// lower-case "#rrggbb"; anything else → "".
function normalizeHex(text) {
    const value = String(text === undefined || text === null ? "" : text).trim().replace(/^#/, "")
    if (/^[0-9a-fA-F]{3}$/.test(value))
        return ("#" + value[0] + value[0] + value[1] + value[1] + value[2] + value[2]).toLowerCase()
    if (/^[0-9a-fA-F]{6}$/.test(value)) return ("#" + value).toLowerCase()
    return ""
}

// Stored setting → "auto" or a normalized hex colour.
function colorSetting(stored) {
    if (stored === "auto") return "auto"
    const hex = normalizeHex(stored)
    return hex.length ? hex : "auto"
}

// "#rrggbb" → { r, g, b } in 0..1, or null.
function parseHex(text) {
    const hex = normalizeHex(text)
    if (!hex.length) return null
    return {
        r: parseInt(hex.slice(1, 3), 16) / 255,
        g: parseInt(hex.slice(3, 5), 16) / 255,
        b: parseInt(hex.slice(5, 7), 16) / 255
    }
}

function rgba(text, alpha) {
    const rgb = parseHex(text)
    if (!rgb) return null
    return { r: rgb.r, g: rgb.g, b: rgb.b, a: Math.max(0, Math.min(1, Number(alpha))) }
}

// WCAG 2 relative luminance (0 black … 1 white), -1 for invalid colours.
function luminance(text) {
    const rgb = parseHex(text)
    if (!rgb) return -1
    function channel(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
}

// Dark text reads better than light text on this colour.
function isLight(text) {
    return luminance(text) > LIGHT_LUMINANCE
}

// Whether a panel colour is of the theme's brightness: a light colour with
// the light theme, a dark one with the dark theme. The panels' own ink
// follows the colour (Colors.surfaceDark); the theme is what the desktop and
// the apps follow.
function matchesTheme(text, dark) {
    const hex = colorSetting(text)
    return hex === "auto" || isLight(hex) !== !!dark
}

// Theme to switch to after choosing a colour, so the desktop and the apps go
// along with the panels: "light" or "dark" when the colour does not fit the
// current brightness, else "".
function themeForColor(text, dark) {
    if (matchesTheme(text, dark)) return ""
    return isLight(colorSetting(text)) ? "light" : "dark"
}

// Hover tint for capsules: a little lighter on dark colours, darker on light ones.
function hoverRgb(text) {
    const rgb = parseHex(text)
    if (!rgb) return null
    const target = isLight(text) ? 0 : 1
    const amount = isLight(text) ? 0.05 : 0.08
    return {
        r: rgb.r + (target - rgb.r) * amount,
        g: rgb.g + (target - rgb.g) * amount,
        b: rgb.b + (target - rgb.b) * amount
    }
}
