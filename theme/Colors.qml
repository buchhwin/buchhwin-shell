pragma Singleton
import Quickshell
import QtQuick
import qs.services
import "../services/appearance/ContrastLogic.js" as Contrast

// Dark and light palettes. Components only use these tokens.
Singleton {
    // The theme: what the apps follow (AppThemeService keeps its own copy),
    // what the desktop behind everything is and what the Dark mode switch
    // says. "auto" is dark from 19:00 to 07:00.
    readonly property bool dark: SettingsService.theme === "dark"
        || (SettingsService.theme === "auto" && (clock.hours >= 19 || clock.hours < 7))
    // What the panels really are, which decides every ink and surface step
    // drawn on them. The theme's own panels follow the theme; a panel colour
    // chosen in Settings > Appearance is what it is. With the theme alone
    // deciding, a black panel colour in the light theme - the buchhwin
    // profile after one tap on Dark mode - drew dark text and dark card
    // steps on black: titles at 1.25:1 and cards that were not there.
    readonly property bool surfaceDark: PanelStyleService.customColor ? !PanelStyleService.lightColor : dark

    SystemClock { id: clock; precision: SystemClock.Hours }

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(SettingsService.accent) ? SettingsService.accent : "#4f8ff7"
    // Text and icons on accent fills (buttons, badges, today). The labels are
    // body text (13-14 px), so they need 4.5:1: white where it has that, dark
    // ink otherwise. The calm blue and the purple used to keep white at 3:1,
    // which is the large-text minimum, and these are not large.
    readonly property color accentText: labelOn(accent)
    readonly property color onAccentDark: "#15171c"
    // The same choice for words on any other fill (the hex value on a picked
    // colour) ...
    function labelOn(background) { return Contrast.textOn(String(background), "#ffffff", onAccentDark, Contrast.TEXT_RATIO) }
    // ... and for marks on one (the check on an accent or a prompt colour
    // swatch): a glyph, so 3:1 is enough.
    function textOn(background) { return Contrast.textOn(String(background), "#ffffff", onAccentDark) }

    // ---- What the inks are measured on ---------------------------------
    // The panel colour as written, without its opacity.
    readonly property string panelHex: PanelStyleService.customColor ? PanelStyleService.color
        : surfaceDark ? "#13161d" : "#f8f9fb"
    // The panel the inks are measured on. A light one at its least opacity
    // (PanelStyleLogic.LIGHT_MIN_OPACITY) over black: the darkest a light
    // panel gets, so what reads there reads over any wallpaper. A dark one as
    // it is: over a bright wallpaper a translucent dark panel loses its
    // contrast the other way, and how much translucency is worth that is
    // the opacity slider's call.
    readonly property color panelBase: surfaceDark ? panelHex
        : Contrast.over(panelHex, PanelStyleService.lightMinOpacity, "#000000")
    // `fill` (a translucent token) as it shows on the opaque `base`.
    function flat(fill, base) { return Contrast.over(String(Qt.rgba(fill.r, fill.g, fill.b, 1)), fill.a, String(base)) }
    // A card on that panel, and a card inside the card.
    readonly property color cardBase: flat(surface1, panelBase)
    readonly property color innerBase: flat(surface2, panelBase)
    // What accent text, accent lines and event colours are made readable
    // against. Light: the card above. Dark: a card on a dark translucent
    // panel, the value the dark theme has always been tuned on.
    readonly property color contrastBase: surfaceDark ? "#1a1d25" : cardBase

    // Accent as text or icon on panels and cards: the accent with its
    // lightness moved until it reaches 4.5:1 on `contrastBase`. Dark keeps
    // every offered swatch as it is; light darkens it.
    readonly property color accentForeground: Contrast.readable(String(accent), String(contrastBase))
    // The same for other colours used as text or icons (event colours).
    function foreground(color) { return Contrast.readable(String(color), String(contrastBase)) }
    // Outline of selected segments, focused fields and highlighted cards.
    // Light accents are first darkened to 3:1 (non-text contrast), so a teal
    // outline does not vanish on light cards.
    readonly property color accentLine: Contrast.readable(String(accent), String(contrastBase), 3)
    readonly property color accentBorder: Qt.rgba(accentLine.r, accentLine.g, accentLine.b, surfaceDark ? 0.6 : 0.75)
    // The tint of a selected row, an active chip or a highlighted card. Light
    // tints with the 3:1 line rather than the accent: a light accent such as
    // the shipped teal has the luminance of a light card, so its wash changed
    // the colour and not the brightness - a selected row was 1.00:1 against
    // the rows beside it. The line at 0.26 is 1.28:1 to 1.42:1 for every
    // offered swatch (ColorsTest).
    readonly property color accentSoft: surfaceDark ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
        : Qt.rgba(accentLine.r, accentLine.g, accentLine.b, 0.26)
    // That tint on a card: what the ink of a highlighted row sits on.
    readonly property color softBase: flat(accentSoft, cardBase)
    // Accent text and the muted second line on that tint. accentForeground
    // and mutedText are measured on cards, and the tint takes contrast away
    // from both: the blue title of an active chip was 3.4:1, a selected row's
    // subtitle 2.8:1.
    readonly property color accentOnSoft: Contrast.readableOnAll(String(accent), [String(contrastBase), String(softBase)])
    readonly property color mutedOnSoft: Contrast.readableOnAll(String(mutedText), [String(softBase)])
    // The accent as a fill that says on or how much - a switch that is on, a
    // slider's level, a meter. It has to stand off the card around it, which
    // a light accent on a light card does not (1.08:1, the teal), so the
    // light side takes the 3:1 line. The white knob keeps about 4.5:1 on it.
    readonly property color accentFill: surfaceDark ? accent : accentLine
    readonly property color accentFillHover: surfaceDark ? accentHover : Qt.lighter(accentLine, 1.08)
    readonly property color accentFillPressed: surfaceDark ? accentPressed : Qt.darker(accentLine, 1.12)
    // Accent choices offered in Settings > Appearance. The teal is the one
    // the shipped profiles use, so a fresh install shows its accent chosen.
    readonly property var accentChoices: ["#4f8ff7", "#8b6cf6", "#d46ad8", "#ef5f67", "#f28b3c", "#e7b43c", "#4fbf73", "#50e2cb", "#8f97a6"]
    // The swatches to show: the choices, and the accent in use after them
    // when it is none of them (one from the wallpaper, a profile's own), so
    // the colour in use is always there to be seen as the chosen one.
    readonly property var accentSwatches: {
        const current = String(accent).toLowerCase()
        return accentChoices.indexOf(current) >= 0 ? accentChoices : accentChoices.concat([current])
    }

    readonly property color background: dark ? "#0d0f14" : "#eef0f4"
    // Panel backgrounds: the theme colour or the panel colour chosen in
    // Settings > Appearance, with the opacity of the window group
    // (PanelStyleService: ShellPanel ids or group keys such as "widgets"),
    // a light one never below its floor.
    readonly property color panel: panelWithOpacity(Effects.panelOpacity)
    function panelFor(id) { return panelWithOpacity(PanelStyleService.opacity(id), id) }
    function panelWithOpacity(alpha, id) {
        const rgb = PanelStyleService.rgb(panelHex)
        return Qt.rgba(rgb.r, rgb.g, rgb.b, PanelStyleService.surfaceOpacity(alpha, !surfaceDark, id))
    }
    // Check marks on colour swatches.
    readonly property color onLightSwatch: "#1b1e25"
    readonly property color onDarkSwatch: "#ffffff"
    // Panel colour choices in Settings > Appearance: dark tints, then light ones.
    readonly property var panelColorChoices: [
        { value: "#16181d", label: "Graphite" }, { value: "#000000", label: "Black" },
        { value: "#141c2e", label: "Midnight blue" }, { value: "#1f1830", label: "Deep purple" },
        { value: "#14221b", label: "Forest" }, { value: "#2a1f18", label: "Warm brown" },
        { value: "#ffffff", label: "White" }, { value: "#e6e8ec", label: "Light gray" },
        { value: "#e9eef8", label: "Ice blue" }, { value: "#f3ede4", label: "Sand" }
    ]
    // Depth ladder. Every surface sits on the one below it and is a clear step
    // lighter (dark) or darker (light): panel -> card -> inner card. The steps
    // stay apart at 40 % panel opacity over a busy wallpaper; the text on
    // them is another matter (see panelBase and the light floor).
    //   surface1  a card on a panel (Settings sections, control center tiles)
    //   surface2  a card inside a card (a media card, a forecast strip)
    //   sunken    a recessed trough or grid the content sits in
    readonly property color surface1: surfaceDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color surface2: surfaceDark ? Qt.rgba(1, 1, 1, 0.115) : Qt.rgba(0, 0, 0, 0.085)
    // Also the groove a segmented control, a slider or a switch sits in: it
    // is recessed, not raised - a lighter groove made the control read as
    // another card on the panel instead of a well the selection slides in.
    readonly property color sunken: surfaceDark ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(0, 0, 0, 0.045)
    // Hover and press for each step, so a card never borrows a control's state.
    readonly property color surface1Hover: surfaceDark ? Qt.rgba(1, 1, 1, 0.105) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color surface1Pressed: surfaceDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.11)
    readonly property color surface2Hover: surfaceDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.115)
    readonly property color surface2Pressed: surfaceDark ? Qt.rgba(1, 1, 1, 0.185) : Qt.rgba(0, 0, 0, 0.145)
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
    readonly property color solidSurface: surfaceDark ? "#1a1d25" : "#ffffff"
    readonly property color hover: surfaceDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color pressed: surfaceDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color track: surfaceDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.17)
    // A track under the pointer: one step up, as a button's fill steps.
    readonly property color trackHover: surfaceDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.23)
    // The bar that says a list has more below it. A slider's track is too
    // faint for a three-pixel hint at the edge of a translucent panel.
    readonly property color scrollHint: surfaceDark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.26)
    readonly property color knob: "#ffffff"
    // What an alpha mask shows through (a list's faded edges): only its
    // opacity counts, the colour is never seen.
    readonly property color maskShown: "#ffffff"
    // Keeps the white toggle knob visible on the light off track and on
    // light accents.
    readonly property color knobBorder: Qt.rgba(0, 0, 0, surfaceDark ? 0.16 : 0.14)

    // One UI control fills: calm, almost flat, one step per state. They read
    // as a filled capsule rather than an outlined box.
    readonly property color controlFill: surfaceDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color controlFillHover: surfaceDark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color controlFillPressed: surfaceDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.13)
    // Accent fills darken on press instead of lightening, like One UI.
    readonly property color accentPressed: Qt.darker(accent, surfaceDark ? 1.18 : 1.12)
    readonly property color accentHover: Qt.lighter(accent, surfaceDark ? 1.12 : 1.08)
    // Selected segment: a solid capsule that lifts off the trough.
    readonly property color segmentSelected: surfaceDark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff"
    // Its edge. White on the light trough is only 1.30:1 on an opaque card,
    // and the card's own 0.1 line drawn on white came to 1.04:1 against the
    // trough, so the light capsule takes a line that is there.
    readonly property color segmentBorder: surfaceDark ? border : Qt.rgba(0, 0, 0, 0.16)
    // Focus ring: the accent line plus a soft halo, visible in both themes.
    readonly property color focusRing: accentLine
    readonly property color focusHalo: Qt.rgba(accentLine.r, accentLine.g, accentLine.b, surfaceDark ? 0.32 : 0.28)

    readonly property color text: surfaceDark ? "#eceef2" : "#1b1e25"
    // The second line: these greys, moved until they reach 4.5:1 on a card
    // and on a card inside it. Dark keeps #9ba2ae; light comes to #505662 on
    // the theme's panel (the #5b6270 it was had 3.5:1 on a card at the
    // default opacity over a dark teal wallpaper, 2.8:1 over black).
    readonly property color mutedText: Contrast.readableOnAll(surfaceDark ? "#9ba2ae" : "#5b6270",
        [String(contrastBase), String(cardBase), String(innerBase)])
    // For marks, not words: 3:1 on the same surfaces - enough for a glyph or
    // a dot, short of the 4.5:1 text needs. Text and placeholders take
    // mutedText.
    readonly property color subtleText: Contrast.readableOnAll(surfaceDark ? "#6c7380" : "#717784",
        [String(contrastBase), String(cardBase), String(innerBase)], Contrast.LARGE_RATIO)

    // Dark lines on light surfaces read weaker than light lines on dark ones,
    // so the light values are a little stronger.
    readonly property color border: surfaceDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.1)
    // The line around a card inside a card: weaker, because the fill already
    // separates it from its parent.
    readonly property color borderInner: surfaceDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color panelBorder: surfaceDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color borderStrong: surfaceDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
    // Scrims stay at or below the layer rule's ignore_alpha 0.35
    // (hypr/windowrules.conf) so Hyprland does not blur the screen behind
    // them; the session menu's stronger scrim has its own 0.5 rule. Panel
    // backgrounds stay at 0.4 or more (PanelStyleLogic MIN_OPACITY), light
    // ones at 0.9 or more (LIGHT_MIN_OPACITY).
    // Cast shadows. A dark panel needs a deeper shadow to read at all; a
    // light one needs a softer one or the card looks dirty.
    readonly property color shadow: Qt.rgba(0, 0, 0, surfaceDark ? 0.55 : 0.22)
    // The light a large surface catches along its top edge. Only a dark
    // panel takes any of it (Effects.sheenTop): 3 % white over a light panel
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
    // The same in both themes: what is written on it is light in both, and
    // the light theme's thinner 0.62 let a bright wallpaper through - its
    // accent labels came to 2.5-3.2:1 there and the grey ones under 4:1 over
    // white (round 12, D10).
    readonly property color overviewScrim: Qt.rgba(0.02, 0.024, 0.03, 0.78)
    // The lightest that scrim gets: over a white wallpaper. What is written
    // on it is measured there, not against a dark guess.
    readonly property color overviewBackdrop: flat(overviewScrim, "#ffffff")
    // The accent as text and outline on that scrim: 4.5:1 at its lightest.
    readonly property color overviewAccent: Contrast.readable(String(accent), String(overviewBackdrop))
    // Text directly on the dark overview scrim, in both themes.
    readonly property color scrimText: "#f5f6f8"
    readonly property color scrimMutedText: Qt.rgba(1, 1, 1, 0.7)
    // Soft halo behind minimal widgets on the wallpaper: dark behind light
    // text, light behind the dark text of light panels (a dark shadow there
    // only smudged the glyphs). It follows the ink, so the panels' side.
    readonly property color textHalo: surfaceDark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.75)

    // Pill bar capsules: near-black on dark panels like the mockup, light glass otherwise.
    // The panel colour replaces them when one is chosen. `pill` itself serves
    // small badges and stays nearly opaque; the bar and OSD use pillFor(group).
    readonly property color pill: pillWithOpacity(Math.max(0.92, Effects.panelOpacity))
    function pillFor(id) { return pillWithOpacity(PanelStyleService.opacity(id)) }
    function pillWithOpacity(chosen) {
        const alpha = PanelStyleService.surfaceOpacity(chosen, !surfaceDark)
        const custom = PanelStyleService.customColor ? PanelStyleService.rgb(PanelStyleService.color) : null
        if (custom) return Qt.rgba(custom.r, custom.g, custom.b, alpha)
        return surfaceDark ? Qt.rgba(0.02, 0.022, 0.028, alpha) : Qt.rgba(0.98, 0.98, 0.99, alpha)
    }
    function pillHoverFor(id) {
        const alpha = PanelStyleService.surfaceOpacity(PanelStyleService.opacity(id), !surfaceDark)
        const custom = PanelStyleService.customColor ? PanelStyleService.hoverRgb(PanelStyleService.color) : null
        if (custom) return Qt.rgba(custom.r, custom.g, custom.b, alpha)
        return surfaceDark ? Qt.rgba(0.09, 0.1, 0.12, alpha) : Qt.rgba(1, 1, 1, alpha)
    }
    readonly property color pillBorder: surfaceDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.12)
    // The dock's outline: fainter than a panel's - the dock stays on screen,
    // and a full panel border read as a frame around the apps.
    // The fastfetch Saturn (the start button, the start menu's header), in
    // the colours `ff` gives it in the session: the planet in the accent, the
    // ring in the accent mixed half with white - which is exactly the pale
    // blue of the shipped logo's second colour (#5fafff → #afd7ff). On a light
    // panel the planet is the accent as text and the ring that pale mix
    // darkened until it is a mark that reads (3:1).
    //
    // The two keep `saturnSeparation` apart, or at the menu's small letters
    // they run into one mass: the teal's half-white ring was 1.25:1 from its
    // planet (round 12, D13 d). On a dark panel the ring takes more white
    // until it stands that far off (the logo's own blue already does, and
    // stays #afd7ff); on a light one the planet is darkened past its 4.5:1
    // until it stands that far below the ring.
    readonly property real saturnSeparation: 1.5
    readonly property color saturnRingMix: Qt.tint(accent, Qt.rgba(1, 1, 1, 0.5)) // style: ff's own mix, half white
    readonly property color saturnRingLight: Contrast.readable(String(saturnRingMix), String(contrastBase), Contrast.LARGE_RATIO)
    readonly property color saturnPlanet: surfaceDark ? accentLine
        : Contrast.readable(String(accent), String(contrastBase),
            Math.max(Contrast.TEXT_RATIO, Contrast.contrast(String(saturnRingLight), String(contrastBase)) * saturnSeparation))
    readonly property color saturnRing: surfaceDark ? ringApart(String(accent), String(saturnPlanet)) : saturnRingLight
    // The accent mixed with white from ff's half upwards, in steps of a
    // twentieth, until it stands `saturnSeparation` off `planet`; white when
    // nothing short of it does.
    function ringApart(accentHex, planet) {
        for (let step = 10; step <= 20; ++step) {
            const ring = Contrast.over("#ffffff", step / 20, accentHex)
            if (Contrast.contrast(ring, planet) >= saturnSeparation) return ring
        }
        return "#ffffff"
    }
    readonly property color dockBorder: surfaceDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.08)
    // Bar style "bar": item hover highlight and the line between item groups.
    readonly property color barItemHover: surfaceDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color barSeparator: surfaceDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)

    // Status colours as picked. What is drawn is measured: as text they
    // reach 4.5:1 on a card (the editor's dry-run note is text, not only an
    // icon), which keeps the dark ones as they are and darkens the light
    // ones a little on the theme's light panel.
    readonly property color successHue: surfaceDark ? "#62d394" : "#178048"
    readonly property color warningHue: surfaceDark ? "#f2b84b" : "#95600e"
    readonly property color dangerHue: surfaceDark ? "#f07171" : "#c53030"
    readonly property color success: Contrast.readable(String(successHue), String(contrastBase))
    readonly property color warning: Contrast.readable(String(warningHue), String(contrastBase))
    // Success on surfaces that stay dark in both themes (notch, lock screen).
    // Both greens are the "status" choice; a good state asks `positive` and
    // `positiveOnDark` below, which may be the accent instead.
    readonly property color successOnDark: "#62d394"
    // Danger on the same surfaces: a low battery in the notch's status block.
    // The dark theme's danger, 7.3:1 on black; the light theme's would be
    // 3.8:1 there and change with the theme on a surface that does not.
    readonly property color dangerOnDark: "#f07171"
    // Warning on the same surfaces: the microphone in use, a busy CPU, Do
    // Not Disturb on the strip. The dark theme's warning, 11:1 on black; the
    // light theme's is made for light panels and is 4:1 there.
    readonly property color warningOnDark: "#f2b84b"
    // What a good state wears - a battery charging, a tunnel up, the clock's
    // charging hint (appearance.statusColors, Settings > Power). "status"
    // keeps the green above; "accent" draws the state in the accent, so the
    // shell's own colour says "on and fine" instead of a second colour
    // beside it. Only the good states follow it: a low battery, a warning
    // and a failure keep red and amber either way, because what needs
    // attention has to stand out from the accent, not turn into it. Every
    // surface that colours a good state asks these three rather than
    // `success`, so the choice is made here and nowhere else. With the
    // notch's glyphs in the accent (notch.accentGlyphs) a charging battery
    // and a neutral glyph are then one colour: the accent says "on", and
    // charging is on. With the red or the orange swatch, charging comes
    // close to the low red or a warning's amber; the glyph still tells them
    // apart (a bolt against an empty battery), and that pairing is the
    // user's to choose.
    readonly property bool statusInAccent: SettingsService.value("appearance.statusColors") === "accent"
    // As a glyph or a word on panels and cards: both choices reach 4.5:1
    // there (`success`, `accentForeground`).
    readonly property color positive: statusInAccent ? accentForeground : success
    // On the surfaces that stay dark in both themes (notch, lock screen):
    // both keep at least 3:1 on black (`successOnDark`, `notchAccent`).
    readonly property color positiveOnDark: statusInAccent ? notchAccent : successOnDark
    // As a level on a panel (the battery's bar): the accent as the fill a
    // level is drawn in when nothing is charging (`accentFill`), so plugging
    // in does not switch the bar to a second shade of the same accent.
    readonly property color positiveFill: statusInAccent ? accentFill : success
    // Background of warning badges (security updates).
    readonly property color warningSoft: Qt.rgba(warningHue.r, warningHue.g, warningHue.b, surfaceDark ? 0.18 : 0.14)
    readonly property color danger: Contrast.readable(String(dangerHue), String(contrastBase))
    // Fill of a button that destroys something. It used to fall through to the
    // neutral control fill, so a delete was a grey capsule with a red glyph and
    // read as any other button. A wash of its own colour rather than a solid
    // block: these sit in lists and on tiles, not on their own.
    readonly property color dangerSoft: Qt.rgba(dangerHue.r, dangerHue.g, dangerHue.b, surfaceDark ? 0.18 : 0.14)
    readonly property color dangerSoftHover: Qt.rgba(dangerHue.r, dangerHue.g, dangerHue.b, surfaceDark ? 0.28 : 0.22)
    readonly property color dangerSoftPressed: Qt.rgba(dangerHue.r, dangerHue.g, dangerHue.b, surfaceDark ? 0.36 : 0.3)
    // The label on that wash, hovered (its stronger step): the red measured
    // on cards came to 4.0:1 dark and 3.8:1 light on its own tint.
    readonly property color dangerOnSoft: Contrast.readableOnAll(String(dangerHue),
        [String(contrastBase), String(flat(dangerSoftHover, cardBase))])
    // Screen recording indicator next to the clock: solid on any wallpaper.
    readonly property color recording: "#e5484d"
    readonly property color recordingText: "#ffffff"
    // Notch (desktop mode "notch"): pure black like a MacBook notch in both
    // themes, so its text is always light.
    readonly property color notch: "#000000"
    readonly property color notchText: "#f5f5f7"
    readonly property color notchMutedText: Qt.rgba(1, 1, 1, 0.58)
    // A glyph that is there but off - no connection, a muted speaker - about
    // 3.6:1 on black, the most a mark can lose and still be one. The muted ink
    // at the disabled opacity came to 1.9:1, which read as nothing at all.
    readonly property color notchSubtleText: Qt.rgba(1, 1, 1, 0.4)
    // The accent as a status glyph on the notch (notch.accentGlyphs): lifted
    // until it keeps 3:1 on black, the minimum for a mark that is not text,
    // so a dark accent does not sink into the notch. Every offered swatch
    // already clears it and stays as it is.
    readonly property color notchAccent: Contrast.readable(String(accent), String(notch), 3)
    // The groove behind a level the notch itself is showing. Not `track`: that
    // one is made to sit on a panel, and on black it disappears.
    readonly property color notchTrack: Qt.rgba(1, 1, 1, 0.22)
    readonly property color notchHover: Qt.rgba(1, 1, 1, 0.1)
    // The media and event fields inside the wide notch: each sits on its own
    // slightly raised surface so they read as two boxes, not two columns.
    readonly property color notchField: Qt.rgba(1, 1, 1, 0.06)
    readonly property color notchFieldBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property color notchButton: Qt.rgba(1, 1, 1, 0.14)
    readonly property color notchCoverFallback: Qt.rgba(1, 1, 1, 0.1)
    // The frame around a pill or a dock group in the layout editor
    // (shell/editor/BarEditOverlay.qml). On a flat bar or the taskbar it is
    // the only sign of what can be dragged, so it is a mark at 3:1 on the
    // panel under the editor's scrim - not a divider: `border` there was
    // 1.1-1.2:1, and subtleText alone 2.8:1 on a light panel under the scrim.
    readonly property color editorFrame: Contrast.readableOnAll(String(subtleText),
        [String(flat(scrim, panelBase)), String(flat(scrim, cardBase))], Contrast.LARGE_RATIO)
}
