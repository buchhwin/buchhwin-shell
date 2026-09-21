pragma Singleton
import Quickshell
import QtQuick
import qs.services
import "../services/appearance/ContrastLogic.js" as Contrast

// Dark and light palettes. Components only use these tokens.
Singleton {
    // "auto" is dark from 19:00 to 07:00.
    readonly property bool dark: SettingsService.theme === "dark"
        || (SettingsService.theme === "auto" && (clock.hours >= 19 || clock.hours < 7))

    SystemClock { id: clock; precision: SystemClock.Hours }

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(SettingsService.accent) ? SettingsService.accent : "#4f8ff7"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.22 : 0.16)
    // Text and icons on accent fills (buttons, badges, today): white while it
    // keeps 3:1 (the calm blue), dark on light accents such as teal or yellow.
    readonly property color accentText: Contrast.textOn(String(accent), "#ffffff", onAccentDark)
    readonly property color onAccentDark: "#15171c"
    // The same choice for other fills (accent and prompt colour swatches).
    function textOn(background) { return Contrast.textOn(String(background), "#ffffff", onAccentDark) }
    // Accent as text or icon on panels and cards: the accent with its
    // lightness moved until it reaches 4.5:1 on `contrastBase` (a card on a
    // translucent panel). Dark keeps the accent as it is for all swatches;
    // light darkens it (the blue #4f8ff7 has only 3:1 on light surfaces).
    readonly property color contrastBase: dark ? "#1a1d25" : "#e9ebef"
    readonly property color accentForeground: Contrast.readable(String(accent), String(contrastBase))
    // The same for other colours used as text or icons (event colours).
    function foreground(color) { return Contrast.readable(String(color), String(contrastBase)) }
    // Outline of selected segments, focused fields and highlighted cards.
    // Light accents are first darkened to 3:1 (non-text contrast), so a teal
    // outline does not vanish on light cards.
    readonly property color accentLine: Contrast.readable(String(accent), String(contrastBase), 3)
    readonly property color accentBorder: Qt.rgba(accentLine.r, accentLine.g, accentLine.b, dark ? 0.6 : 0.75)
    // Accent choices offered in Settings > Appearance.
    readonly property var accentChoices: ["#4f8ff7", "#8b6cf6", "#d46ad8", "#ef5f67", "#f28b3c", "#e7b43c", "#4fbf73", "#2eb8a8", "#8f97a6"]

    readonly property color background: dark ? "#0d0f14" : "#eef0f4"
    // Panel backgrounds: the theme colour or the panel colour chosen in
    // Settings > Appearance, with the opacity of the window group
    // (PanelStyleService: ShellPanel ids or group keys such as "widgets").
    readonly property color panel: panelWithOpacity(Effects.panelOpacity)
    function panelFor(id) { return panelWithOpacity(PanelStyleService.opacity(id)) }
    function panelWithOpacity(alpha) {
        const custom = PanelStyleService.customColor ? PanelStyleService.rgb(PanelStyleService.color) : null
        if (custom) return Qt.rgba(custom.r, custom.g, custom.b, alpha)
        return dark ? Qt.rgba(0.075, 0.086, 0.114, alpha) : Qt.rgba(0.972, 0.976, 0.984, alpha)
    }
    // Check marks on colour swatches.
    readonly property color onLightSwatch: "#1b1e25"
    readonly property color onDarkSwatch: "#ffffff"
    // Panel colour choices in Settings > Appearance: dark tints, then light ones.
    readonly property var panelColorChoices: [
        { value: "#16181d", label: "Graphite" }, { value: "#000000", label: "Black" },
        { value: "#141c2e", label: "Midnight blue" }, { value: "#1f1830", label: "Deep purple" },
        { value: "#14221b", label: "Forest" }, { value: "#2a1f18", label: "Warm brown" },
        { value: "#ffffff", label: "White" }, { value: "#e6e8ec", label: "Light grey" },
        { value: "#e9eef8", label: "Ice blue" }, { value: "#f3ede4", label: "Sand" }
    ]
    // Depth ladder. Every surface sits on the one below it and is a clear step
    // lighter (dark) or darker (light): panel -> card -> inner card. The steps
    // are wide enough to read at 40 % panel opacity over a busy wallpaper,
    // which is how the session actually runs.
    //   surface1  a card on a panel (Settings sections, control center tiles)
    //   surface2  a card inside a card (a media card, a forecast strip)
    //   sunken    a recessed trough or grid the content sits in
    readonly property color surface1: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color surface2: dark ? Qt.rgba(1, 1, 1, 0.115) : Qt.rgba(0, 0, 0, 0.085)
    readonly property color sunken: dark ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(0, 0, 0, 0.045)
    // Hover and press for each step, so a card never borrows a control's state.
    readonly property color surface1Hover: dark ? Qt.rgba(1, 1, 1, 0.105) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color surface1Pressed: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.11)
    readonly property color surface2Hover: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.115)
    readonly property color surface2Pressed: dark ? Qt.rgba(1, 1, 1, 0.185) : Qt.rgba(0, 0, 0, 0.145)
    // Kept so the existing call sites read the first step by its old name.
    readonly property color surface: surface1
    // Terminal preview box (Settings > Terminal), close to the Kitty background.
    readonly property color terminalBackground: "#0d0f14"
    readonly property color terminalForeground: "#eceef2"
    readonly property color vinyl: "#0c0d10"
    // Rounded screen corners: the bezel is black in both themes, like a
    // laptop display.
    readonly property color screenCorner: "#000000"
    // Lock screen: always light text on the darkened, blurred screen capture.
    readonly property color lockBase: "#15161c"
    readonly property color lockShade: Qt.rgba(0, 0, 0, 0.12)
    readonly property color lockText: "#f5f6f8"
    readonly property color lockClock: Qt.rgba(1, 1, 1, 0.94)
    readonly property color lockMuted: Qt.rgba(1, 1, 1, 0.72)
    readonly property color lockField: Qt.rgba(1, 1, 1, 0.16)
    readonly property color lockFieldBorder: Qt.rgba(1, 1, 1, 0.22)
    readonly property color lockButton: Qt.rgba(1, 1, 1, 0.24)
    readonly property color lockButtonHover: Qt.rgba(1, 1, 1, 0.32)
    // A bare glyph on the lock screen (media controls, the retry target).
    readonly property color lockGlyphHover: Qt.rgba(1, 1, 1, 0.12)
    readonly property color lockError: "#ffb4ab"
    readonly property color elevatedSurface: surface2
    readonly property color solidSurface: dark ? "#1a1d25" : "#ffffff"
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.17)
    // The bar that says a list has more below it. A slider's track is too
    // faint for a three-pixel hint at the edge of a translucent panel.
    readonly property color scrollHint: dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.26)
    readonly property color knob: "#ffffff"
    // Keeps the white toggle knob visible on the light off track and on
    // light accents.
    readonly property color knobBorder: Qt.rgba(0, 0, 0, dark ? 0.16 : 0.14)

    // One UI control fills: calm, almost flat, one step per state. They read
    // as a filled capsule rather than an outlined box.
    readonly property color controlFill: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color controlFillHover: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color controlFillPressed: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.13)
    // Ghost buttons only gain a fill on hover and press.
    readonly property color ghostHover: hover
    readonly property color ghostPressed: pressed
    // Accent fills darken on press instead of lightening, like One UI.
    readonly property color accentPressed: Qt.darker(accent, dark ? 1.18 : 1.12)
    readonly property color accentHover: Qt.lighter(accent, dark ? 1.12 : 1.08)
    // The groove a segmented control, a slider or a switch sits in. It is
    // recessed, not raised: a lighter groove made the control read as another
    // card on the panel instead of a well the selection slides in.
    readonly property color controlTrough: sunken
    // Selected segment: a solid capsule that lifts off the trough.
    readonly property color segmentSelected: dark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff"
    // Focus ring: the accent line plus a soft halo, visible in both themes.
    readonly property color focusRing: accentLine
    readonly property color focusHalo: Qt.rgba(accentLine.r, accentLine.g, accentLine.b, dark ? 0.32 : 0.28)

    readonly property color text: dark ? "#eceef2" : "#1b1e25"
    readonly property color mutedText: dark ? "#9ba2ae" : "#5b6270"
    // Light: about 4:1 on panels (the former #8a909c had 3:1 and faded on
    // translucent panels).
    readonly property color subtleText: dark ? "#6c7380" : "#717784"

    // Dark lines on light surfaces read weaker than light lines on dark ones,
    // so the light values are a little stronger.
    readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.1)
    // The line around a card inside a card: weaker, because the fill already
    // separates it from its parent.
    readonly property color borderInner: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color panelBorder: dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color borderStrong: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
    // Scrims stay at or below the layer rule's ignore_alpha 0.35
    // (hypr/windowrules.conf) so Hyprland does not blur the screen behind
    // them; the session menu's stronger scrim has its own 0.5 rule. Panel
    // backgrounds stay at 0.4 or more (PanelStyleLogic MIN_OPACITY).
    // Cast shadows. Dark themes need a deeper shadow to read at all; light
    // themes need a softer one or the card looks dirty.
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.55 : 0.22)
    // The light that a surface catches along its top edge.
    // The light a large surface catches along its top edge. Only the dark
    // theme takes any of it (Effects.sheenTop): 3 % white over a light panel
    // is invisible, so a light panel stays flat on purpose.
    readonly property color sheen: "#ffffff"
    readonly property color scrim: Qt.rgba(0, 0, 0, dark ? 0.22 : 0.12)
    readonly property color scrimStrong: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.3)
    // For a panel whose whole job is to let you look past it: the wallpaper
    // strip is choosing the wallpaper, so dimming it would defeat the point.
    // Enough to lift the card off a bright image and no more.
    readonly property color scrimFaint: Qt.rgba(0, 0, 0, dark ? 0.08 : 0.05)
    // Overview backdrop: dark enough (and above the blur threshold) to hide
    // window content behind the previews.
    readonly property color overviewScrim: Qt.rgba(0.02, 0.024, 0.03, dark ? 0.78 : 0.62)
    // Text directly on the dark overview scrim, in both themes.
    readonly property color scrimText: "#f5f6f8"
    readonly property color scrimMutedText: Qt.rgba(1, 1, 1, 0.7)
    readonly property color scrimAccent: Contrast.readable(String(accent), String(contrastBase))
    // Soft halo behind minimal widgets on the wallpaper: dark behind light
    // text, light behind the dark text of the light theme (a dark shadow
    // there only smudged the glyphs).
    readonly property color textHalo: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.75)

    // Pill bar capsules: near-black in dark mode like the mockup, light glass otherwise.
    // The panel colour replaces them when one is chosen. `pill` itself serves
    // small badges and stays nearly opaque; the bar and OSD use pillFor(group).
    readonly property color pill: pillWithOpacity(Math.max(0.92, Effects.panelOpacity))
    function pillFor(id) { return pillWithOpacity(PanelStyleService.opacity(id)) }
    function pillWithOpacity(alpha) {
        const custom = PanelStyleService.customColor ? PanelStyleService.rgb(PanelStyleService.color) : null
        if (custom) return Qt.rgba(custom.r, custom.g, custom.b, alpha)
        return dark ? Qt.rgba(0.02, 0.022, 0.028, alpha) : Qt.rgba(0.98, 0.98, 0.99, alpha)
    }
    function pillHoverFor(id) {
        const alpha = PanelStyleService.opacity(id)
        const custom = PanelStyleService.customColor ? PanelStyleService.hoverRgb(PanelStyleService.color) : null
        if (custom) return Qt.rgba(custom.r, custom.g, custom.b, alpha)
        return dark ? Qt.rgba(0.09, 0.1, 0.12, alpha) : Qt.rgba(1, 1, 1, alpha)
    }
    readonly property color pillBorder: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.12)
    // Bar style "bar": item hover highlight and the line between item groups.
    readonly property color barItemHover: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color barSeparator: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)

    // Light values reach about 4.5:1 on light panels (text such as the
    // editor's dry-run note, not only icons).
    readonly property color success: dark ? "#62d394" : "#178048"
    readonly property color warning: dark ? "#f2b84b" : "#95600e"
    // Success on surfaces that stay dark in both themes (notch, lock screen).
    readonly property color successOnDark: "#62d394"
    // Background of warning badges (security updates).
    readonly property color warningSoft: Qt.rgba(warning.r, warning.g, warning.b, dark ? 0.18 : 0.14)
    readonly property color danger: dark ? "#f07171" : "#c53030"
    // Fill of a button that destroys something. It used to fall through to the
    // neutral control fill, so a delete was a grey capsule with a red glyph and
    // read as any other button. A wash of its own colour rather than a solid
    // block: these sit in lists and on tiles, not on their own.
    readonly property color dangerSoft: Qt.rgba(danger.r, danger.g, danger.b, dark ? 0.18 : 0.14)
    readonly property color dangerSoftHover: Qt.rgba(danger.r, danger.g, danger.b, dark ? 0.28 : 0.22)
    readonly property color dangerSoftPressed: Qt.rgba(danger.r, danger.g, danger.b, dark ? 0.36 : 0.3)
    // Screen recording indicator next to the clock: solid on any wallpaper.
    readonly property color recording: "#e5484d"
    readonly property color recordingText: "#ffffff"
    // Notch (desktop mode "notch"): pure black like a MacBook notch in both
    // themes, so its text is always light.
    readonly property color notch: "#000000"
    readonly property color notchText: "#f5f5f7"
    readonly property color notchMutedText: Qt.rgba(1, 1, 1, 0.58)
    readonly property color notchHover: Qt.rgba(1, 1, 1, 0.1)
    // The media and event fields inside the wide notch: each sits on its own
    // slightly raised surface so they read as two boxes, not two columns.
    readonly property color notchField: Qt.rgba(1, 1, 1, 0.06)
    readonly property color notchFieldBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property color notchButton: Qt.rgba(1, 1, 1, 0.14)
    readonly property color notchCoverFallback: Qt.rgba(1, 1, 1, 0.1)
    readonly property color guide: accent
    readonly property color selection: accentSoft
}
