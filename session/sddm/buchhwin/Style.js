.pragma library

// Design tokens copied from theme/ (Colors lock*, Metrics, Typography,
// Effects, Animations at the default "fast" speed). SDDM runs the theme as
// its own user without the shell's modules, so keep these in sync by hand.

// Colors (lock screen: light text on a darkened, blurred backdrop).
var base = "#15161c"
var shade = "#1f000000"          // rgba(0, 0, 0, 0.12)
var text = "#f5f6f8"
var clock = "#f0ffffff"          // 0.94
var muted = "#b8ffffff"          // 0.72
var field = "#29ffffff"          // 0.16
var fieldBorder = "#38ffffff"    // 0.22
var button = "#3dffffff"         // 0.24
var hover = "#1fffffff"          // 0.12
var menu = "#d91b1c23"           // base-like panel, 0.85
var menuBorder = "#24ffffff"     // 0.14
var error = "#ffb4ab"
var accent = "#4f8ff7"
var accentText = "#ffffff"

// Metrics.
var spaceXxs = 2
var spaceXs = 4
var spaceSm = 8
var spaceMd = 12
var spaceLg = 16
var spaceXl = 20
var spaceXxl = 28
var radiusSm = 10
var radiusMd = 12
var radiusLg = 16
var borderWidth = 1
var controlHeight = 40
var controlHeightSm = 30
var pillHeight = 32
var menuRowHeight = 34
var menuMinWidth = 220
var iconSm = 16
var iconMd = 20
var avatarSize = 76
var menuAvatarSize = 22
var fieldWidth = 260
var fieldHeight = 36
var clockTop = 72
var bottomMargin = 110
var statusWidth = 360

// Typography.
var fontFamily = "Inter Variable"
var captionSize = 12
var smallSize = 13
var bodySize = 14
var dateSize = 22
var clockSize = 118
var nameSize = 17
var initialSize = 34
var clockTracking = 1.0
var dotTracking = 1.4

// Effects.
var blurMax = 64
var backdropWidth = 128          // decoded width of the wallpaper before the blur
var saturation = 0.25
var brightness = -0.04
var zoom = 0.07
var engagedScale = 1.08
var clockShadow = 0.45
var clockGlow = 0.28
var shadowBlur = 24
var shadowOffset = 6
var mutedOpacity = 0.65

// Animations (ms).
var hoverMs = 100
// A rejected password: three fast swings at full amplitude, then rest (~0.4 s).
var shakeOffset = 10
var shakeOutMs = 70
var shakeSwingMs = 110
var popupOpen = 220
var enter = 720
var staggerMs = 120
var digit = 460
var exit = 380
var pulse = 1100
var idleReturn = 12000
var confirmReset = 4000
