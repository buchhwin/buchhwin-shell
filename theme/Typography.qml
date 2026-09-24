pragma Singleton
import Quickshell
import QtQuick
import qs.services

Singleton {
    // Font families are user settings (Settings > Appearance).
    readonly property string family: SettingsService.fontFamily.length ? SettingsService.fontFamily : "Inter Variable"
    readonly property string monoFamily: SettingsService.monoFontFamily.length ? SettingsService.monoFontFamily : "JetBrains Mono"
    readonly property string iconFamily: "FiraCode Nerd Font Propo"
    // Native glyph rendering snaps to whole pixels and looks uneven at
    // fractional scales (1.25, 1.5) and during scale animations; Qt's own
    // renderer stays evenly spaced.
    readonly property int renderType: Text.QtRendering

    // Interface text size (Settings > Appearance). Every size below is derived
    // from it, and Metrics.settingsWidth and its sidebar follow, so a larger
    // font widens the window instead of squeezing what is in it - that was the
    // cause behind the overflow that used to be patched page by page.
    readonly property real scale: Math.max(0.9, Math.min(1.25, SettingsService.value("appearance.fontScale")))
    function size(base) { return Math.round(base * scale) }

    readonly property int captionSize: size(12)
    readonly property int smallSize: size(13)
    readonly property int bodySize: size(14)
    readonly property int bodyLargeSize: size(15)
    readonly property int titleSize: size(17)
    readonly property int headlineSize: size(22)
    // The title of a page inside a panel (Settings), one step above the panel
    // titles themselves.
    readonly property int pageTitleSize: size(26)
    // The initial in the lock screen avatar: a glyph, not a text role.
    readonly property int avatarInitialSize: size(34)
    readonly property int displaySize: size(56)
    // The charge in the battery popup: bigger than a headline, smaller than
    // the display size a clock takes.
    readonly property int batteryPercentSize: size(33)
    // The pairing code in the Bluetooth dialog, read across the room and
    // compared digit by digit with the other device.
    readonly property int pairingCodeSize: size(39)
    // One emoji in the picker's grid.
    readonly property int emojiSize: size(28)
    // Lock screen (macOS style: date above a very large, heavy clock).
    readonly property int lockDateSize: size(22)
    readonly property int lockClockSize: size(118)
    readonly property int lockNameSize: size(17)

    // Clock sizes per widget size class; the clock is thin like the mockups.
    readonly property int clockSmall: size(54)
    readonly property int clockMedium: size(64)
    readonly property int clockLarge: size(88)
    // The dashboard's own clock, between the desktop widget's sizes.
    readonly property int dashboardClockSize: size(84)

    readonly property int light: Font.Light
    readonly property int regular: Font.Normal
    readonly property int medium: Font.Medium
    readonly property int semibold: Font.DemiBold
    readonly property int bold: Font.Bold
    readonly property int clockWeight: Font.Light

    // Letter spacing for small upper-case section labels.
    readonly property real captionTracking: 1.4
    readonly property real clockTracking: 1.0
    readonly property real pillClockTracking: 0.3
    // Notch: small semibold time when collapsed, large light time expanded.
    readonly property int notchTimeSize: size(14)
    readonly property int notchLargeTimeSize: size(36)
    readonly property int notchTemperatureSize: size(26)
}
