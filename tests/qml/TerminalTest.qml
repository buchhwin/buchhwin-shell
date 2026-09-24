import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/terminal/TerminalLogic.js" as L

ShellRoot {
    Component.onCompleted: {
        const base = {
            fontFamily: "JetBrains Mono", fontSize: 11, opacity: 0.86, padding: 12, cursorShape: "beam", cursorBlink: true,
            promptColor: "shell", errorColor: "#f07178", symbol: "❯", errorSymbol: "❯", gitSymbol: "󰊢",
            username: true, hostname: true, directory: true, git: true, gitStatus: true, python: false, nodejs: false,
            docker: false, commandDuration: true, jobs: true, time: false, twoLine: true, newline: true,
            directoryDepth: 3, durationMin: 1500, timeFormat: "%H:%M", fastfetchOnStart: true, previewGit: true
        }
        const toml = L.starshipToml(base, "#4F8FF7")
        T.ok(toml.indexOf("format = \"$username$hostname$directory$git_branch$git_status$cmd_duration$jobs$line_break$character\"") >= 0, "default module order")
        T.ok(toml.indexOf("success_symbol = \"[❯](bold #4f8ff7)\"") >= 0, "shell accent used for the prompt symbol")
        T.ok(toml.indexOf("symbol = \"󰊢 \"") >= 0, "git symbol keeps the Nerd Font glyph")
        T.ok(toml.indexOf("[time]\ndisabled = true") >= 0, "clock off by default")

        const custom = L.starshipToml(Object.assign({}, base, { promptColor: "#62D394", hostname: false, twoLine: false, time: true,
            symbol: "λ\"\\\nx", timeFormat: "", directoryDepth: 40 }), "#4f8ff7")
        T.ok(custom.indexOf("format = \"$username$directory$git_branch$git_status$cmd_duration$jobs$time$character\"") >= 0, "modules and one-line prompt")
        T.ok(custom.indexOf("format = \"[$user]($style) \"") >= 0, "username adds the space without hostname")
        T.ok(custom.indexOf("success_symbol = \"[λ\\\"\\\\ x](bold #62d394)\"") >= 0, "symbol escaped, single line, custom colour")
        T.ok(custom.indexOf("time_format = \"%H:%M\"") >= 0 && custom.indexOf("truncation_length = 10") >= 0, "empty time format and depth clamped")
        T.ok(L.starshipToml(Object.assign({}, base, { promptColor: "red\"]" }), "#4f8ff7").indexOf("red") < 0, "invalid colours rejected")
        T.eq(Array.from(L.symbol("󰊢".repeat(40), "x")).length, 32, "symbols limited to 32 characters")

        T.eq(L.fastfetchColorText(base, "#62D394"), "#62d394\n", "fastfetch labels follow the shell accent")
        T.eq(L.fastfetchColorText(Object.assign({}, base, { promptColor: "#A28BFE" }), "#62d394"), "#a28bfe\n", "fastfetch labels follow a custom prompt colour")
        T.eq(L.fastfetchColorText(base, "blue; rm -rf ~"), "#4f8ff7\n", "invalid accent falls back to blue")

        const kitty = L.kittyConf(Object.assign({}, base, { fontSize: 99, opacity: 0.2, cursorShape: "evil\nshape", cursorBlink: false, fontFamily: "Fira\ninclude /etc/passwd" }))
        T.ok(kitty.indexOf("font_size 20.0") >= 0 && kitty.indexOf("background_opacity 0.50") >= 0, "kitty values clamped")
        T.ok(kitty.indexOf("cursor_shape beam") >= 0 && kitty.indexOf("cursor_blink_interval 0\n") >= 0, "cursor shape validated, blink off")
        const soft = L.kittyConf(Object.assign({}, base, { cursorBlink: true, cursorBlinkStyle: "soft", cursorTrail: "short" }), "#62d394")
        T.ok(soft.indexOf("cursor_blink_interval 0.6 ease-in-out") >= 0, "a soft blink carries an easing function")
        T.ok(soft.indexOf("cursor_trail 3") >= 0 && soft.indexOf("cursor_trail_color #62d394") >= 0, "the trail follows the accent")
        const hard = L.kittyConf(Object.assign({}, base, { cursorBlink: true, cursorBlinkStyle: "hard", cursorTrail: "off" }), "#62d394")
        T.ok(hard.indexOf("cursor_blink_interval 0.6\n") >= 0, "a hard blink has no easing")
        T.ok(hard.indexOf("cursor_trail 0") >= 0 && hard.indexOf("cursor_trail_decay") < 0, "no trail, no decay line")
        T.ok(L.kittyConf(Object.assign({}, base, { cursorTrail: "evil; rm -rf ~" }), "#62d394").indexOf("cursor_trail 3") >= 0, "an unknown trail falls back")
        T.eq(kitty.split("\n").filter(line => line.startsWith("include")).length, 0, "font family cannot inject directives")

        T.eq(L.ansiToRich("\x1b[1;38;2;79;143;247mme\x1b[0m <a>"), "<font color=\"#4f8ff7\"><b>me</b></font>&nbsp;&lt;a&gt;", "ANSI colour and bold to rich text")
        T.eq(L.ansiToRich("%{\x1b[31m%}x%{\x1b[0m%}\ny"), "<font color=\"#f07178\">x</font><br>y", "zsh wrappers removed, basic colours, line break")
        // A background is not painted, and its arguments are not foreground
        // codes: `48;2;30;30;30` used to paint the text with colour 30.
        T.eq(L.ansiToRich("\x1b[48;2;30;30;30mx\x1b[0m"), "x", "a true-colour background leaves the text alone")
        T.eq(L.ansiToRich("\x1b[48;5;31mx\x1b[0m"), "x", "so does a palette background")
        T.eq(L.ansiToRich("\x1b[48;2;1;2;3;31mx\x1b[0m"), "<font color=\"#f07178\">x</font>",
             "and a foreground after it is still read")
        // cmatrix colour name and cava gradient follow the prompt accent.
        const accentOpts = { promptColor: "shell" }
        T.eq([L.cmatrixColor(accentOpts, "#50e2cb"), L.cmatrixColor(accentOpts, "#ff2200"),
              L.cmatrixColor({ promptColor: "#22cc22" }, "#50e2cb")],
             ["cyan", "red", "green"], "cmatrix uses the nearest colour name")
        const cava = L.cavaConfig(accentOpts, "#50e2cb")
        T.ok(cava.indexOf("gradient = 1") >= 0 && cava.indexOf("gradient_color_1") >= 0
             && cava.indexOf("gradient_color_8") >= 0, "cava config has the full gradient")
        T.eq(cava.split("\n").filter(line => line.indexOf("gradient_color_") === 0).length, 8, "eight gradient stops")
        T.ok(/gradient_color_4 = '#[0-9a-f]{6}'/.test(cava), "stops are hex colours")
        T.finish("TerminalTest")
    }
}
