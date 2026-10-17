.pragma library

// Wi-Fi as a phone's status bar shows it: how strong, in steps, and whether
// the connection reaches the internet. One place for every glyph and bar
// count, so the bar, the notch, the popup and the control center agree with
// each other - and with nmcli and Plasma, whose steps these are.

// NetworkManager's own steps (nm_utils_wifi_strength_bars, which nmcli's bars
// and Plasma's icons follow): over 80 % four bars, over 55 three, over 30
// two, over 5 one. Quickshell hands the strength as 0-1. The shell's own
// steps were 75/50/25 and the island's bars a third rule (ceil), so the same
// network could read three bars in one place and four in another.
var STEPS = [0.05, 0.30, 0.55, 0.80]

// Material's wifi-strength glyphs: the whole fan as an outline, the bars
// filled - and the same with "!" for a connection without the internet.
// Index = bars (0-4).
var GLYPHS = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
var ALERT_GLYPHS = ["󰤫", "󰤠", "󰤣", "󰤦", "󰤩"]

// 0-4 bars for a strength of 0-1. A network you are connected to shows at
// least one: no bars reads as no connection.
function level(strength, connected) {
    const value = Number(strength)
    let bars = 0
    if (isFinite(value)) for (const step of STEPS) if (value > step) bars += 1
    return connected === true ? Math.max(1, bars) : bars
}

// Of `total` bars, how many are lit (the island's drawn bars): the four
// steps spread over them.
function lit(strength, total, connected) {
    const count = Math.max(0, Math.round(Number(total)) || 0)
    const bars = level(strength, connected)
    return Math.min(count, Math.round(bars * count / STEPS.length))
}

// The glyph for a network at `strength`; `limited` adds the "!". An unknown
// strength (none reported yet) draws full rather than empty.
function glyph(strength, limited, connected) {
    const bars = strength === undefined || strength === null ? 4 : level(strength, connected)
    return (limited === true ? ALERT_GLYPHS : GLYPHS)[bars]
}

// NetworkManager's connectivity, as Quickshell names it, in words this file
// takes: "full", "limited", "portal", "none", "unknown".
// Connected without the internet: a captive portal, limited, or none at all.
// Unknown (no check configured, or not run yet) is not a reason to alarm.
function limited(connectivity) {
    return connectivity === "limited" || connectivity === "portal" || connectivity === "none"
}

// What the connection's line says after its name, or "".
function note(connectivity) {
    if (connectivity === "portal") return "Sign-in required"
    if (connectivity === "limited" || connectivity === "none") return "No internet"
    return ""
}
