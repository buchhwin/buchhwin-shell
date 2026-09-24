pragma Singleton
import Quickshell
import QtQuick
import qs.services

Singleton {
    readonly property int spaceXxs: 2
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int spaceXl: 20
    readonly property int spaceXxl: 28

    // How far a rejected password field swings sideways. A distance, not a
    // spacing: the space tokens must stay free to change without touching it.
    readonly property int shakeOffset: 10

    // Corner radii scale with Settings > Appearance > Shell corners (20 = default).
    readonly property real cornerScale: Math.max(0, Math.min(32, SettingsService.value("appearance.shellRadius"))) / 20
    readonly property int radiusXs: Math.round(6 * cornerScale)
    readonly property int radiusSm: Math.round(10 * cornerScale)
    readonly property int radiusMd: Math.round(12 * cornerScale)
    readonly property int radiusLg: Math.round(16 * cornerScale)
    readonly property int radiusXl: Math.round(20 * cornerScale)
    readonly property int radiusPill: 999
    // Semantic radii. Every surface picks one of these, so a hover highlight
    // can never end up rounder or squarer than the thing it sits in, and a
    // change to the shell corner setting moves all of them together.
    // A floating panel card. **Derived, not picked off the ladder**: a card
    // inside a panel sits `panelPadding` in from its edge, and the two corners
    // only run parallel when the outer radius is the inset plus the inner one.
    // At the old 20 with a 20 px inset and a 16 px card the gap between the
    // two edges was 20 px down the straight sides and **26.6** into the
    // corner - `20 + 0.414 * cardRadius` - which is the swell the user saw at
    // the bottom right of the launcher's result list. 36 makes it 20 all the
    // way round.
    //
    // The inset is scaled on the way *down* although the real `panelPadding` is
    // not: a corner slider that changed how much content fits would be a
    // different control, but a panel that stayed round while the slider asked
    // for square would be a broken one. Above the designed setting the scaling
    // stops, because there the inset is all the room there is and a rounder
    // panel would only pull its corner away from the card again. So: exact at
    // the designed setting and above it, approximate below, and square is
    // square.
    readonly property int radiusPanel:
        radiusCard + Math.min(panelPadding, Math.round(panelPadding * cornerScale))
    // The same derivation for a panel that insets its cards by something
    // other than `panelPadding` (the switcher strip, which is a dense row of
    // cards): the outer corner is the inner one plus the inset, scaled the
    // same way, so `radiusPanel` is `panelRadius(panelPadding)`. Picking
    // `radiusPanel` for a tighter inset put the corner 8 px off the card's.
    function panelRadius(inset) {
        return radiusCard + Math.min(inset, Math.round(inset * cornerScale))
    }
    readonly property int radiusCard: radiusLg      // a card, tile, row, field or highlight on a panel
    readonly property int radiusInner: radiusSm     // a thumbnail, bar or swatch inside a card
    readonly property int radiusTiny: radiusXs      // the smallest marks
    // One UI controls are capsules. The shell-corner setting only flattens
    // them: at the default 20 (cornerScale 1) they stay fully round, at 4 they
    // become the same gentle rounding as the panels.
    readonly property real controlRoundness: Math.min(1, cornerScale)
    function pillRadius(size) { return size / 2 * controlRoundness }

    readonly property int borderWidth: 1
    readonly property int focusBorderWidth: 2
    // Focus ring drawn outside a control, plus the gap to the control itself.
    readonly property int focusRingWidth: 2
    readonly property int focusRingGap: 2
    readonly property int controlHeight: 40
    readonly property int controlHeightSm: 30
    readonly property int rowHeight: 48
    readonly property int tileHeight: 72
    // The colour picker's loupe: a circle of magnified screen with the pixel
    // under the crosshair in its middle. The zoom is also the size one pixel
    // is drawn at, which is what the outline in the middle measures.
    readonly property int colorLoupeSize: 132
    readonly property int colorLoupeZoom: 12
    readonly property int colorSwatch: 40
    // The little usage bar a widget draws once it has been made big enough to
    // show one (WidgetBase.meter).
    readonly property int widgetMeterWidth: 56
    // One row of the control center's grid. A standard tile is two of them
    // (2 x 30 + one 12 gap = the 72 it always was), so the panel looks exactly
    // as it did until a corner is dragged.
    readonly property int quickGridUnit: 30
    // The width one column of the control center's grid is worth. The column
    // count follows the panel's width through this, so dragging it wider adds
    // a column instead of stretching the tiles - the notch does the same.
    //
    // It is measured against the panel's *content* width, which is the card
    // minus panelPadding twice. At 320 the count was rounded rather than
    // floored, so two columns came out 254 wide - narrower than the metric
    // claimed a column was worth - and the fourth column could never be
    // reached at all, because the widest panel divided by 320 rounds to three.
    readonly property int quickGridCell: 210
    readonly property int quickGridColumns: 4
    // The hint that a list has more below it, how close to the edge a drag has
    // to come before the list scrolls under it, and how far it travels in one
    // tick at the very edge. The step is small on purpose: the tick is a frame,
    // so the band's own width as a step would cross a whole panel in a sixth of
    // a second.
    readonly property int scrollHintWidth: 3
    readonly property int scrollEdge: 48
    readonly property int scrollStep: 6
    // One UI buttons carry a lot of air around their label.
    readonly property int controlPadding: 20
    readonly property int controlPaddingSm: 14

    readonly property int iconXs: 14
    readonly property int iconSm: 16
    readonly property int iconMd: 20
    readonly property int iconLg: 26
    readonly property int iconXl: 36
    readonly property int thumbnailSize: 64
    // The lock screen's grid: a row and a column step for the items above the
    // login block. A taller row than the control center's, because what sits
    // there is read from across a room.
    readonly property int lockGridUnit: 44
    // Two columns, not four: the grid is centred on the screen and its items
    // start two wide, so a four-column grid left everything hugging its left
    // edge instead of sitting under the middle of the screen - which is where
    // a lock screen puts its clock. Half a row is still reachable by pulling a
    // corner in.
    readonly property int lockGridCell: 340
    readonly property int lockGridColumns: 2
    readonly property int lockGridWidth: 720
    readonly property int lockAvatarSize: 76
    readonly property int lockFieldWidth: 260
    readonly property int lockFieldHeight: 36
    readonly property int lockClockTop: 72
    readonly property int lockBottomMargin: 110
    readonly property int lockMediaWidth: 360
    // Fingerprint glyph: enrollment in Settings, the hint on the lock screen.
    readonly property int fingerprintGlyph: 64
    readonly property int fingerprintLockGlyph: 24
    readonly property int coverSize: 72

    // One UI switch: a large soft capsule with a big round knob.
    readonly property int toggleWidth: 46
    readonly property int toggleHeight: 26
    readonly property int toggleKnob: 20
    // One UI slider: thick track, large round handle that overlaps it.
    readonly property int sliderTrack: 8
    readonly property int sliderHandle: 20
    // What a slider is worth when nothing tells it to fill its row.
    readonly property int sliderWidth: 160
    // Progress bars that are not sliders (battery, rain, OSD level).
    readonly property int progressTrack: 5
    // Microphone level bar in Settings > Audio.
    readonly property int meterHeight: 6
    readonly property int meterPeakWidth: 2

    // What the compositor leaves between a window and whatever is reserved
    // above it: Hyprland's `general:gaps_out`. A surface that wants a gap
    // under itself reserves that much less, because this one is already
    // there. `checks.py hypr` holds the two to the same number.
    readonly property int windowGap: 12
    readonly property int screenMargin: 16
    readonly property int panelTopOffset: 92
    readonly property int panelPadding: 20
    // The gap between the blocks of a panel. Same step as spaceMd; the name
    // says where it belongs, so a panel root column uses this one.
    readonly property int panelGap: spaceMd
    readonly property int controlCenterWidth: 640
    // How narrow and how wide the control center may be dragged.
    readonly property int controlCenterMinWidth: 360
    readonly property int controlCenterMaxWidth: 900
    // Emoji picker: wide enough for ten cells, tall enough that the grid is
    // worth scrolling rather than a strip.
    readonly property int emojiWidth: 560
    readonly property int emojiHeight: 520
    readonly property int emojiCell: 52
    // The first-start tour: one column of text, and the dots that count it.
    readonly property int welcomeWidth: 520
    readonly property int dotSize: 6
    readonly property int toneSelectWidth: 150
    readonly property int launcherWidth: 880
    // What the launcher may be pulled to. It is a search surface, so it is wide
    // rather than tall by default and there is a floor below which the result
    // list stops being a list.
    readonly property int launcherMinWidth: 520
    readonly property int launcherMaxWidth: 1400
    readonly property int launcherMinHeight: 320
    readonly property int launcherSidebarWidth: 190
    readonly property int launcherHeight: 600
    // The wallpaper picker (Super+Shift+W): a grid of 16:9 thumbnails, with
    // room around it so the wall it is choosing stays visible at the edges.
    readonly property int wallpaperPickerWidth: 920
    readonly property int wallpaperPickerHeight: 660
    readonly property int wallpaperPickerTile: 260
    // One cell of the image grid on Settings > Wallpaper; the column count
    // follows the card's width through this.
    readonly property int wallpaperGridCell: 170
    readonly property int notificationWidth: 380
    readonly property int notificationCenterWidth: 430
    // The session menu (Super+M). Wider and its tiles taller than a panel's,
    // because it is read at a glance and clicked once, and getting it wrong
    // costs a session.
    readonly property int powerMenuWidth: 780
    readonly property int powerMenuTileHeight: 128
    readonly property int powerMenuIcon: 40
    readonly property int editorSidebarWidth: 280
    // The settings window and its sidebar follow the interface font: at a
    // larger size the window grows rather than the content being squeezed.
    readonly property int settingsWidth: Math.round(980 * Typography.scale)
    readonly property int settingsHeight: Math.round(680 * Typography.scale)
    readonly property int settingsSidebarWidth: Math.round(230 * Typography.scale)
    // The Super+F1 sheet. Wider and taller than the settings window because it
    // is a wall of 69 short rows and nothing else: the width buys a third
    // column and the height buys eleven more rows before anybody scrolls.
    // `ShellPanel` clamps both to the screen, so a small display simply gets
    // fewer columns.
    readonly property int shortcutSheetWidth: Math.round(1320 * Typography.scale)
    readonly property int shortcutSheetHeight: Math.round(760 * Typography.scale)
    // What one column of the sheet needs before a third one is worth having:
    // a title, its longest row and its keys without wrapping.
    readonly property int shortcutColumnWidth: Math.round(380 * Typography.scale)
    // What the dashboard is worth before anybody drags it, and what it may be
    // dragged to. The grid is the same idea as the control center's, several
    // steps coarser, because a layout file clamps every cell to six rows
    // (LayoutLogic.GRID_MAX_H) and a dashboard card is a whole block rather
    // than a tile: at 64 a row, the clock card is two rows, the month grid
    // five and the day's events three, which is where they sat when the two
    // columns were hard-coded.
    readonly property int dashboardWidth: 900
    readonly property int dashboardMinWidth: 420
    readonly property int dashboardMaxWidth: 1600
    readonly property int dashboardGridUnit: 64
    readonly property int dashboardGridCell: 420
    readonly property int dashboardGridColumns: 3
    readonly property int weekHourHeight: 32
    readonly property int weekGridHeight: 272
    readonly property int weekGutter: 48
    readonly property int weekAllDayHeight: 20
    readonly property int weekBlockGap: 2
    readonly property int weekNowLine: 2
    // New-event dialog.
    readonly property int eventEditorWidth: 460
    readonly property int formLabelWidth: 64
    readonly property int timeFieldWidth: 84
    // Small popups opened from a pill or widget (Wi-Fi, Bluetooth, media …).
    readonly property int popupWidth: 380
    readonly property int popupWideWidth: 420
    // A popup that puts two columns side by side (weather).
    readonly property int popupSplitWidth: 660
    readonly property int popupListHeight: 270
    readonly property int popupIconTile: 36
    readonly property int popupPlayButton: 52
    readonly property int popupMediaWidth: 580
    readonly property int popupMediaCover: 168
    readonly property int popupMediaVolume: 90

    // Content-width breakpoints for responsive panel layouts.
    readonly property int compactWidth: 520
    readonly property int wideWidth: 900

    // Desktop widgets and layout editor.
    readonly property real widgetScaleMin: 0.7
    readonly property real widgetScaleMax: 2.0
    readonly property int snapThreshold: 12
    readonly property int gridSize: 24
    readonly property int dragThreshold: 3
    readonly property int resizeHandle: 18
    readonly property int guideWidth: 1

    // Pill bar (desktop mode "pills"): small floating capsules at the top edge.
    readonly property int pillHeight: 32
    readonly property int pillGap: 6
    readonly property int pillPadding: 12
    readonly property int pillItemGap: 10
    // Gap between a round cover and the pill edge, equal on all sides.
    readonly property int pillCoverInset: 4
    readonly property int barMargin: 6
    // Bar style "bar": one continuous bar with flat item segments. Corners
    // follow the shell radius; the hover highlight is inset from the bar edge.
    readonly property int barRadius: radiusMd
    readonly property int barHighlightInset: 3
    readonly property int barSidePadding: 8
    readonly property int barSegmentPadding: 10
    readonly property int barSegmentGap: 2
    readonly property int barGroupGap: 9
    readonly property int barSeparatorWidth: 1
    readonly property int barSeparatorHeight: 14
    // Bar sketch in Settings > Bar & Notch.
    readonly property int barPreviewHeight: 96
    // One arrow-key press on the display arrangement, in logical pixels, and
    // the same number as the snap threshold for it: an edge closer than one
    // press catches the monitor instead of letting it stop short.
    readonly property int nudgeStep: 10
    readonly property int nudgeFineStep: 1
    // The square the "Identify" card fills on each monitor. Big enough to read
    // across a desk and small enough not to cover what is behind it.
    readonly property int identifyCardSize: 220
    // Padding on each side *across* a vertical bar, beyond the pill on it. A
    // horizontal bar needs none: its widgets run along it, so their width
    // costs the bar nothing. A vertical one reads a widget's stacked value
    // across its thickness, and "50%" measures 32 px at the body size - which
    // is a pill exactly, edge to edge. Measured on a nested right-hand bar.
    readonly property int verticalBarPadding: 3
    // How wide the overview decodes a wallpaper for one workspace card. There
    // is one card per workspace and a wallpaper can be 5120 px across.
    readonly property int overviewCardSourceWidth: 480
    readonly property int barPreviewBar: 18
    readonly property int barPreviewText: 5

    // Notch (desktop mode "notch"): collapsed like a MacBook notch, expanded
    // on hover into a small overview. The surface is sized for the expanded
    // shape; input only reaches the shape.
    readonly property int notchHeight: 32
    readonly property int notchMinWidth: 164
    readonly property int notchPadding: 16
    // The notch while it *is* the display: how wide a level track is, and how
    // much room a title gets before it elides. Both are what keeps the shape a
    // strip rather than letting a long notification stretch it across the
    // screen.
    readonly property int notchLevelWidth: 96
    readonly property int notchDisplayTextWidth: 260
    // How long a track change stays in the notch. Longer than an OSD, which is
    // a value you already know you changed, and shorter than a notification,
    // which you may have to read.
    readonly property int notchTrackTimeout: 3200
    readonly property int notchEar: 7
    readonly property int notchRadius: 11
    // The two widths the notch used to be able to be. They are the default and
    // the ceiling now: the size itself is dragged, not picked.
    readonly property int notchExpandedWidth: 384
    readonly property int notchWideWidth: 700
    readonly property int notchColumnGap: 12
    // One row of the overview's grid, measured so the blocks fit their cells
    // rather than the other way round: one row holds a chip row (20) with the
    // field's padding around it, two rows hold the media block (68), which is
    // what its cover and its controls need. Get this wrong and a block is cut
    // off at the cell edge - the fields clip.
    readonly property int notchGridUnit: 36
    readonly property int notchGridColumns: 4
    // The width one grid column is worth. The overview's column count follows
    // its width through this, so dragging it wider adds a column instead of
    // stretching the cells.
    readonly property int notchGridCell: 175
    // How narrow and how wide the overview may be dragged.
    readonly property int notchMinExpandedWidth: 260
    readonly property int notchFieldPadding: 8
    // The notch fields are cards, so they take the card radius and follow the
    // shell corner setting with everything else (this used to be a fixed 16,
    // which could not match anything once the setting moved).
    readonly property int notchFieldRadius: radiusCard
    // The widest the overview may be dragged, and therefore the width the
    // surface must be able to hold.
    readonly property int notchMaxExpandedWidth: notchWideWidth
    readonly property int notchExpandedEar: 14
    readonly property int notchExpandedRadius: 34
    // How far below the top edge a pill sits, and how far above the windows.
    // Kept small on purpose: the space over it and the space under it are the
    // same, so every pixel counts twice.
    readonly property int notchPillMargin: 6
    readonly property int notchExpandedPadding: 20
    readonly property int notchRowGap: 14
    // The room the expanded notch may use. It was 300, which the wide layout
    // with three or four events already outgrew: the body was clamped to
    // 300 - spaceXl and everything past that was cut off with no scroll and no
    // hint. The surface is transparent and its input mask follows the notch
    // shape, so a taller one costs nothing.
    // Sized for the tallest the overview may be dragged to, not for a preset:
    // the surface is transparent and its input mask follows the notch shape,
    // so holding room costs nothing.
    readonly property int notchSurfaceHeight: 600
    readonly property int notchCover: 44
    readonly property int notchControl: 30
    readonly property int notchPlayControl: 34
    readonly property int notchEventBar: 3
    // One event row in the notch: the time line above the title. The events
    // tile shows as many of these as its height holds.
    readonly property int notchEventRow: 34
    readonly property int notchRecordingDot: 8

    readonly property int overviewCardWidth: 420
    // The narrowest a workspace card may be squeezed to so a monitor's whole
    // row - its workspaces and its "New workspace" card - fits on one line.
    // Below this a preview stops showing anything and wrapping is the lesser
    // evil.
    readonly property int overviewCardMinWidth: 210

    // Alt+Tab window switcher cards.
    readonly property int switcherCardWidth: 208
    readonly property int switcherPreviewHeight: 128
    readonly property int switcherIconSize: 48

    // On-screen display for volume and brightness.
    readonly property int osdWidth: 300
    readonly property int osdBottomMargin: 96
    readonly property int osdTimeout: 1400
    // Widget content inside a pill is drawn slightly smaller than on the desktop.
    readonly property real pillContentScale: 0.88

}
