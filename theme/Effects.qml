pragma Singleton
import Quickshell
import QtQuick
import qs.services

Singleton {
    // Default panel opacity (live while the Settings slider is dragged).
    readonly property real panelOpacity: PanelStyleService.defaultOpacity
    readonly property real disabledOpacity: 0.4
    readonly property real mutedOpacity: 0.65
    // The wallpaper behind a workspace card in the overview. Held back so the
    // window previews on top of it stay the thing being read.
    readonly property real overviewWallpaperOpacity: 0.55
    readonly property real hoverScaleFrom: 0.98
    readonly property int hoverTranslate: 2
    // One UI press feedback: the control dips a little under the finger.
    readonly property real pressScale: 0.96
    // Wide surfaces (list rows, tiles, chips) dip much less than a button.
    readonly property real pressScaleWide: 0.985
    // An item lifted off the surface to be dragged: a little smaller than its
    // place, so the gap it will drop into stays readable underneath it.
    readonly property real dragScale: 0.95
    // The switch knob stretches slightly while pressed.
    readonly property real knobPressScale: 1.12
    readonly property int shadowBlur: 24
    readonly property int shadowOffset: 6

    // Elevation. MultiEffect takes `shadowBlur` as 0..1 of `blurMax`, so each
    // step carries its own max, opacity and vertical offset. Only panels cast
    // one:
    //   2  a panel over the desktop
    //   3  a panel over a strong scrim (session menu, dialogs)
    // Cards get no shadow at all: their depth comes from the surface ladder and
    // the border, and a MultiEffect per card would render every one of them
    // into its own texture.
    readonly property int elevation2Max: 48
    readonly property real elevation2Blur: 0.8
    readonly property real elevation2Opacity: 0.34
    readonly property int elevation2Offset: 8
    readonly property int elevation3Max: 72
    readonly property real elevation3Blur: 0.9
    readonly property real elevation3Opacity: 0.46
    readonly property int elevation3Offset: 14
    // A large surface is not one flat fill: a barely visible top-to-bottom
    // gradient gives it a direction without reading as a gradient.
    readonly property real sheenTop: Colors.dark ? 0.032 : 0
    readonly property real sheenBottom: 0.0
    // The lock backdrop is a tiny capture; this smooths it when scaled up.
    readonly property int lockBlurMax: 64
    readonly property real lockSaturation: 0.25
    readonly property real lockBrightness: -0.04
    readonly property real lockZoom: 0.07             // backdrop zoom while entering/leaving
    readonly property real lockEngagedScale: 1.08     // login block while typing
    // How far the wallpaper tiles that are not chosen sit back, so the one
    // being judged is the one that reads as chosen.
    readonly property real pickerRestScale: 0.96
    readonly property real lockClockShadow: 0.45
    // How far the lock screen's arranged grid fades back while the login block
    // sits in the middle of the screen. Not to nothing: the clock is what a
    // glance at a locked screen is usually for, and it should still be there
    // behind the field.
    readonly property real lockYieldOpacity: 0.25
    readonly property real lockClockGlow: 0.28
    // Blurred glow layers render at this share of their size: the blur hides
    // the missing detail and the layer is redrawn on every animated frame.
    readonly property real glowResolution: 0.5
    // Media popup: the cover, blurred and faint, tints the card behind it.
    readonly property int mediaBackdropBlur: 64
    readonly property real mediaBackdropOpacity: 0.32
    // Media popup vinyl: hole size (share of the radius), groove and sheen strength.
    readonly property real vinylHole: 0.075        // share of the disc radius
    readonly property real vinylLabel: 0.62       // label diameter / disc diameter
    // How far an editable tile leans while it wiggles.
    readonly property real wiggleAngle: 0.8
    readonly property real vinylGrooves: 0.07
    readonly property real vinylSheen: 0.14
    // The grooves fade in and out around the disc, and the lower highlight is
    // weaker than the upper one.
    readonly property real vinylGrooveBase: 0.6
    readonly property real vinylGrooveSwing: 0.4
    readonly property real vinylSheenLower: 0.6
    // An event is drawn in its calendar's colour, tinted down so the text on it
    // stays readable: a block in the grid, a full-day bar, and the editor's
    // preview swatch.
    readonly property real eventFill: 0.32
    readonly property real eventFillHover: 0.5
    readonly property real eventAllDayFill: 0.55
    readonly property real eventSwatchFill: 0.25
    // A shadow under a small surface (a desktop widget, the lock clock's text).
    readonly property int shadowOffsetSm: 1
    readonly property real shadowBlurSm: 1
}
