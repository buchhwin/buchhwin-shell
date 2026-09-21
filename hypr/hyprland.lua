-- buchhwin-shell — Hyprland Lua configuration (Hyprland 0.56+, required from 0.57).
-- Same session as hyprland.conf + keybinds.conf + windowrules.conf; keep both in
-- sync. Started by session/buchhwin-shell-session; it never replaces the user's
-- own ~/.config/hypr/hyprland.lua.

local home = os.getenv("HOME") or ""
local projectPath = os.getenv("BUCHHWIN_SHELL_PATH") or (home .. "/.local/share/buchhwin-shell")
-- Nested test sessions (scripts/nested-session.sh) set these.
local nested = os.getenv("BUCHHWIN_NESTED") == "1"
local nestedMode = os.getenv("BUCHHWIN_NESTED_MODE") or "1920x1200"
local nestedScale = os.getenv("BUCHHWIN_NESTED_SCALE") or "1"

-- Default apps from Settings > Default Apps (Kitty, Brave and Dolphin otherwise).
local terminal = projectPath .. "/scripts/launch-default.sh terminal"
local browser = projectPath .. "/scripts/launch-default.sh browser"
local fileManager = projectPath .. "/scripts/launch-default.sh files"
local ipc = "quickshell --path " .. projectPath .. " ipc call "

-- Monitors ----------------------------------------------------------------
if nested then
    hl.monitor({ output = "", mode = nestedMode, position = "0x0", scale = nestedScale })
else
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end

-- Session start -----------------------------------------------------------
hl.on("hyprland.start", function()
    if nested then
        -- start-shell.sh keeps the log in ~/.local/state/buchhwin-shell/.
        hl.exec_cmd(projectPath .. "/scripts/start-shell.sh " .. projectPath)
    else
        -- session-init.sh imports the environment and restarts the portal, then
        -- starts the shell through start-shell.sh.
        hl.exec_cmd(projectPath .. "/scripts/session-init.sh " .. projectPath)
    end
end)

hl.env("XCURSOR_THEME", "breeze_cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- The session name comes first so xdg-desktop-portal loads
-- buchhwin-shell-portals.conf (KWallet secrets, KDE dialogs and settings).
hl.env("XDG_CURRENT_DESKTOP", "buchhwin-shell:Hyprland")
-- KDE applications keep the Plasma look (Breeze, colors, icons) in this session.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_SESSION_DESKTOP", "buchhwin-shell")
hl.env("DESKTOP_SESSION", "buchhwin-shell")

-- Look and feel -------------------------------------------------------------
hl.config({
    -- Frame scheduling: the newer path decides when to start a frame from when
    -- the last one finished rather than from the vblank alone. It was turned on
    -- for an animation on an idle *laptop* - six panel animations left the GPU
    -- at 16 % busy on its lowest clock while the motion still stepped.
    --
    -- Off again: it was never measured against more than one screen, and on a
    -- three-monitor dock it decides when a frame starts for *which output*. The
    -- reported symptom is that shape exactly - a video on the left monitor
    -- nearly freezes when focus moves to the second one while its audio keeps
    -- playing. See hyprland.conf for the long version.
    render = {
        new_render_scheduling = false,
    },
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 1,
        col = {
            active_border = "rgba(4f8ff7cc)",
            inactive_border = "rgba(ffffff22)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 16,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 0.96,
        shadow = {
            enabled = true,
            range = 18,
            render_power = 3,
            color = "rgba(00000059)",
        },
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            ignore_opacity = true,
            new_optimizations = true,
            -- Blur samples the wallpaper instead of the whole stack behind a
            -- surface. The lock screen pointed here: it is smooth because
            -- nothing is composited behind it, while the desktop steps on the
            -- same machine at the same 16 % GPU.
            xray = true,
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        -- A restarted lock screen may take over a session whose locker crashed.
        allow_session_lock_restore = true,
        -- XDG_CURRENT_DESKTOP is set on purpose (hl.env above) so portals and
        -- default apps recognise this session; skip the "managed externally" notice.
        disable_xdg_env_checks = true,
        -- Shown until the shell paints the wallpaper.
        background_color = "rgb(0d0f14)",
        -- A tiled window dragged with SUPER + left button swaps into the slot
        -- under the pointer. Without this it changes place between one frame
        -- and the next, which reads as teleporting; with it, it travels there,
        -- at the cost of trailing the pointer slightly.
        animate_mouse_windowdragging = true,
        -- The same for a window resized by dragging its border or SUPER+right.
        animate_manual_resizes = true,
    },
    input = {
        kb_layout = "de",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
        },
    },
})

-- The compositor moves in the same One UI rhythm as the shell (theme/
-- Animations.qml): fast off the mark, long soft landing (buchhwinFast, the
-- curve behind Easing.OutQuint), a hint of push for windows appearing
-- (buchhwinSpring) and no looping border animation.
hl.curve("buchhwinFast", { type = "bezier", points = { {0.22, 1.0}, {0.36, 1.0} } })
hl.curve("buchhwinSpring", { type = "bezier", points = { {0.2, 1.12}, {0.32, 1.0} } })
hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "buchhwinSpring", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.7, bezier = "buchhwinFast", style = "popin 87%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.0, bezier = "buchhwinFast" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.7, bezier = "buchhwinFast" })
hl.animation({ leaf = "layers", enabled = true, speed = 1.7, bezier = "buchhwinFast", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.2, bezier = "buchhwinFast", style = "slidefade 10%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.0, bezier = "buchhwinFast", style = "slidefadevert 15%" })
hl.animation({ leaf = "border", enabled = true, speed = 2.0, bezier = "buchhwinFast" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "buchhwinFast" })

-- Keybindings ---------------------------------------------------------------
-- Lua binds show up as `__lua` in `hyprctl binds`; the descriptions are the
-- titles Settings > Shortcuts shows (services/shortcuts/ShortcutLogic.js).
local function exec(command) return hl.dsp.exec_cmd(command) end
-- Where a shortcut sits, as opposed to what it does.
--
-- What each binding *does* stays in this file and nowhere else. A user who
-- moves one writes only the new combination into
-- `~/.config/buchhwin-shell/shortcut-keys.txt`, one `default = replacement`
-- per line, and `keyFor` looks it up. Settings > Shortcuts writes that file.
--
-- Why not read the binding back from the compositor and rebind it there: with
-- a Lua configuration every bind is a closure, so `hyprctl -j binds` reports
-- `dispatcher = "__lua"` and an internal index. The *name* of a shortcut can
-- be read from outside; the *action* cannot. So the move has to happen where
-- the action is, which is here.
--
-- Plain text rather than a Lua table, and parsed by hand: this file is the
-- session's configuration and must not execute something another program
-- wrote. The default combination is the key because descriptions are not
-- unique - four bindings are called "Resize window".
local shortcutKeys = {}
do
    local configHome = os.getenv("XDG_CONFIG_HOME")
    if not configHome or configHome == "" then
        configHome = (os.getenv("HOME") or "") .. "/.config"
    end
    local file = io.open(configHome .. "/buchhwin-shell/shortcut-keys.txt", "r")
    if file then
        for line in file:lines() do
            if not line:match("^%s*#") then
                local from, to = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
                if from and to and #from > 0 and #to > 0 then shortcutKeys[from] = to end
            end
        end
        file:close()
    end
end

local function keyFor(default)
    local wanted = shortcutKeys[default]
    if type(wanted) == "string" and #wanted > 0 then return wanted end
    return default
end


-- Applications and safe shell recovery.
hl.bind(keyFor("SUPER + RETURN"), exec(terminal), { description = "Terminal" })
hl.bind(keyFor("SUPER + B"), exec(browser), { description = "Web browser" })
hl.bind(keyFor("SUPER + E"), exec(fileManager), { description = "File manager" })
hl.bind(keyFor("SUPER + CTRL + R"), exec(projectPath .. "/scripts/reload-shell.sh"), { description = "Restart buchhwin-shell" })
hl.bind(keyFor("SUPER + ALT + E"), exec(ipc .. "editor toggle"), { description = "Layout editor" })
hl.bind(keyFor("SUPER + ALT + D"), exec(ipc .. "desktop cycleMode"), { description = "Desktop mode: widgets, bar, notch" })
hl.bind(keyFor("SUPER + ALT + P"), exec(ipc .. "profile cycle"), { description = "Profile: minimal, work, gaming, laptop, docked" })
-- F1, not ?: on a German layout ? is Shift+ss and unreliable as a binding.
hl.bind(keyFor("SUPER + F1"), exec(ipc .. "shortcuts toggleSheet"), { description = "All keyboard shortcuts" })
hl.bind(keyFor("SUPER + D"), exec(ipc .. "launcher toggle"), { description = "Launcher" })
hl.bind(keyFor("SUPER + O"), exec(ipc .. "controlCenter toggle"), { description = "Control center" })
hl.bind(keyFor("SUPER + I"), exec(ipc .. "settings toggle"), { description = "Settings" })
hl.bind(keyFor("SUPER + N"), exec(ipc .. "notifications toggle"), { description = "Notification center" })
hl.bind(keyFor("SUPER + K"), exec(ipc .. "dashboard toggle"), { description = "Dashboard" })
hl.bind(keyFor("SUPER + M"), exec(ipc .. "powerMenu toggle"), { description = "Session menu" })
hl.bind(keyFor("SUPER + W"), exec(ipc .. "overview toggle"), { description = "Overview" })
hl.bind(keyFor("SUPER + SHIFT + W"), exec(ipc .. "wallpaperPicker toggle"), { description = "Wallpaper picker" })
hl.bind(keyFor("SUPER + SHIFT + C"), exec(ipc .. "colorPicker pick"), { description = "Pick a colour off the screen" })
-- Alt+Tab switcher: releasing Alt focuses the selection (transparent, so apps
-- still see the release; a confirm without an open switcher does nothing).
hl.bind(keyFor("ALT + TAB"), exec(ipc .. "switcher next"), { description = "Next window" })
hl.bind(keyFor("ALT + SHIFT + TAB"), exec(ipc .. "switcher previous"), { description = "Previous window" })
hl.bind(keyFor("ALT + ALT_L"), exec(ipc .. "switcher confirm"), { release = true, transparent = true, description = "Switch to selected window" })
hl.bind(keyFor("SUPER + V"), exec(ipc .. "clipboard toggle"), { description = "Clipboard history" })
hl.bind(keyFor("SUPER + PERIOD"), exec(ipc .. "emoji toggle"), { description = "Emoji picker" })
hl.bind(keyFor("SUPER + L"), exec(projectPath .. "/scripts/session-action.sh lock"), { description = "Lock screen" })

-- Screenshots.
hl.bind(keyFor("SUPER + S"), exec(projectPath .. "/scripts/screenshot.sh region"), { description = "Screenshot of a region" })
hl.bind(keyFor("SUPER + SHIFT + S"), exec(projectPath .. "/scripts/screenshot.sh screen"), { description = "Screenshot of the screen" })
hl.bind(keyFor("SUPER + ALT + S"), exec(projectPath .. "/scripts/screenshot.sh window"), { description = "Screenshot of a window" })
hl.bind(keyFor("Print"), exec(projectPath .. "/scripts/screenshot.sh region"), { description = "Screenshot of a region" })
-- Screen recording (pressing it again stops).
hl.bind(keyFor("SUPER + SHIFT + R"), exec(ipc .. "recording toggle region"), { description = "Record a region" })
hl.bind(keyFor("SUPER + CTRL + SHIFT + R"), exec(ipc .. "recording toggle screen"), { description = "Record the screen" })

-- Window actions.
hl.bind(keyFor("SUPER + Q"), hl.dsp.window.close(), { description = "Close window" })
hl.bind(keyFor("SUPER + F"), hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Fullscreen" })

-- SUPER + arrows resize repeatedly; in tiled dwindle layouts this moves the split.
hl.bind(keyFor("SUPER + RIGHT"), hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true, description = "Resize window" })
hl.bind(keyFor("SUPER + LEFT"), hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true, description = "Resize window" })
hl.bind(keyFor("SUPER + DOWN"), hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true, description = "Resize window" })
hl.bind(keyFor("SUPER + UP"), hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true, description = "Resize window" })

-- Conflict-free focus navigation.
hl.bind(keyFor("SUPER + ALT + LEFT"), hl.dsp.focus({ direction = "left" }), { description = "Move focus left" })
hl.bind(keyFor("SUPER + ALT + RIGHT"), hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind(keyFor("SUPER + ALT + UP"), hl.dsp.focus({ direction = "up" }), { description = "Move focus up" })
hl.bind(keyFor("SUPER + ALT + DOWN"), hl.dsp.focus({ direction = "down" }), { description = "Move focus down" })

-- Workspaces 1-9, through the shell: with workspaces per monitor, `Super+3`
-- means "the third workspace of the monitor under the focus", and only the
-- shell knows which monitor that is. The `||` tail is the old, global
-- behaviour, for a session whose shell is not running.
-- Moving a window keeps the user on the current workspace.
for i = 1, 9 do
    hl.bind("SUPER + " .. i, exec(ipc .. "workspaces switchTo " .. i .. " || hyprctl dispatch workspace " .. i),
            { description = "Go to workspace " .. i })
    hl.bind("SUPER + SHIFT + " .. i, exec(ipc .. "workspaces move " .. i .. " || hyprctl dispatch movetoworkspacesilent " .. i),
            { description = "Move window to workspace " .. i })
end

-- Pointer moving and resizing.
hl.bind(keyFor("SUPER + mouse:272"), hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind(keyFor("SUPER + mouse:273"), hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Hardware keys talk to the system backends directly; the shell follows the
-- resulting PipeWire, backlight and MPRIS events.
hl.bind(keyFor("XF86AudioRaiseVolume"), exec("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Volume up" })
hl.bind(keyFor("XF86AudioLowerVolume"), exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true, description = "Volume down" })
hl.bind(keyFor("XF86AudioMute"), exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, description = "Mute audio" })
hl.bind(keyFor("XF86AudioMicMute"), exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, description = "Mute microphone" })
hl.bind(keyFor("XF86MonBrightnessUp"), exec("brightnessctl -e4 -n2 set 5%+ && " .. ipc .. "brightness refresh"), { locked = true, repeating = true, description = "Brightness up" })
hl.bind(keyFor("XF86MonBrightnessDown"), exec("brightnessctl -e4 -n2 set 5%- && " .. ipc .. "brightness refresh"), { locked = true, repeating = true, description = "Brightness down" })
-- The keyboard light goes through the shell rather than running brightnessctl
-- here: the LED's name carries its driver's prefix (tpacpi on this ThinkPad,
-- asus or dell elsewhere) and a key binding cannot know it.
hl.bind(keyFor("XF86KbdBrightnessUp"), exec(ipc .. "kbdBacklight up"), { locked = true, repeating = true, description = "Keyboard light up" })
hl.bind(keyFor("XF86KbdBrightnessDown"), exec(ipc .. "kbdBacklight down"), { locked = true, repeating = true, description = "Keyboard light down" })
hl.bind(keyFor("XF86KbdLightOnOff"), exec(ipc .. "kbdBacklight toggle"), { locked = true, description = "Keyboard light on or off" })
hl.bind(keyFor("XF86AudioPlay"), exec("playerctl play-pause"), { locked = true, description = "Play or pause" })
hl.bind(keyFor("XF86AudioPause"), exec("playerctl play-pause"), { locked = true, description = "Play or pause" })
hl.bind(keyFor("XF86AudioNext"), exec("playerctl next"), { locked = true, description = "Next track" })
hl.bind(keyFor("XF86AudioPrev"), exec("playerctl previous"), { locked = true, description = "Previous track" })
hl.bind(keyFor("switch:on:Lid Switch"), exec(ipc .. "power lidClosed"), { locked = true, description = "Lid closed" })
hl.bind(keyFor("switch:off:Lid Switch"), exec(ipc .. "power lidOpened"), { locked = true, description = "Lid opened" })

-- Rules ---------------------------------------------------------------------
-- Quickshell surfaces use their own transparent layer windows. Blur only goes
-- behind pixels more opaque than ignore_alpha: panels (at least 40 % opaque,
-- Settings > Appearance > Panels) keep their blur, scrims and shadows (theme/
-- Colors.qml, at most 35 %) stay sharp. The session menu's stronger scrim needs
-- the higher threshold; its card over that scrim stays above it.
hl.layer_rule({ name = "buchhwin-layers", match = { namespace = "^(buchhwin-.*)$" }, blur = true, ignore_alpha = 0.35 })
hl.layer_rule({ name = "buchhwin-session-menu", match = { namespace = "^(buchhwin-powerMenu)$" }, ignore_alpha = 0.5 })
-- Surfaces that can never show what is behind them, or that are mostly empty:
-- the wallpaper covers the screen, the notch is opaque black, and the screen
-- corners are four small shapes on a surface the size of the whole display.
-- Blurring behind them buys nothing and costs a two-pass blur of their area on
-- every frame.
--
-- **The rule above is a catch-all, so every full-screen layer this shell adds
-- lands in it by default and has to be taken out again by hand.** That is how
-- `buchhwin-screencorners` came to blur the entire screen on every monitor,
-- every frame, behind four rounded corners: it was added after the other two
-- and nobody thought of this line. The user felt it as the notch and the
-- panels being sluggish at the dock, and turning blur off entirely was the
-- first thing that made it better. If a new layer covers a lot of screen and
-- shows little, put it here.
hl.layer_rule({ name = "buchhwin-wallpaper", match = { namespace = "^(buchhwin-wallpaper)$" }, blur = false })
hl.layer_rule({ name = "buchhwin-notch-noblur", match = { namespace = "^(buchhwin-notch)$" }, blur = false })
hl.layer_rule({ name = "buchhwin-corners-noblur", match = { namespace = "^(buchhwin-screencorners)$" }, blur = false })
-- Helper windows that must keep running but never show (list shared with the
-- shell in services/hypr/HiddenWindows.js). xwaylandvideobridge (KDE autostart)
-- otherwise opens a black, uncloseable window on workspace 1.
hl.window_rule({
    name = "buchhwin-hidden-windows",
    match = { class = "^(xwaylandvideobridge)$" },
    workspace = "special:buchhwin-hidden silent",
    float = true,
    size = "1 1",
    max_size = "1 1",
    opacity = "0.0 override",
    no_focus = true,
    no_initial_focus = true,
    no_anim = true,
    no_blur = true,
    no_shadow = true,
})
