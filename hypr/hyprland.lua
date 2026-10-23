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
    -- The headless test output scripts/nested-session.sh creates, by name: a
    -- rule here survives `hyprctl reload`, the one it sends at runtime does
    -- not, and the catch-all then put BUCHTEST on 0x0 over the nested window.
    hl.monitor({ output = "BUCHTEST", mode = nestedMode .. "@60", position = "4000x0", scale = nestedScale })
else
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end

-- Session start -----------------------------------------------------------
hl.on("hyprland.start", function()
    if nested then
        -- start-shell.sh keeps the log in ~/.local/state/buchhwin-shell/.
        hl.exec_cmd(projectPath .. "/scripts/start-shell.sh " .. projectPath)
    else
        -- session-init.sh imports the environment, starts the shell through
        -- start-shell.sh, then restarts the portal and opens the wallet.
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
        -- Colour management is a shader pass per surface, on every output,
        -- and only HDR or wide-gamut screens need it; on SDR panels it is
        -- work for nothing. Off since 2026-10-13; takes effect at the next
        -- compositor start.
        cm_enabled = false,
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
        -- Opaque, since 2026-10-13. At 0.96 every unfocused window was
        -- translucent, so the compositor blended it and (blur ignores
        -- opacity) blurred behind it, and with follow_mouse every hover
        -- across windows animated `fade` over two windows at 4K. The focus
        -- still shows in the border.
        inactive_opacity = 1.0,
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
    -- XWayland draws in real device pixels rather than being scaled up afterwards.
    --
    -- Without this, XWayland tells its clients the *logical* size of a scaled
    -- monitor - `xrandr` reported 2560x1440 for a 3840x2160 screen at 1.5 - so an
    -- X11 application renders 2560x1440 pixels and the compositor stretches them
    -- over 3840x2160. Text in an X11 client (Citrix Workspace, say) then looks
    -- pixelated on a scaled 4K screen and sharp on an unscaled Full HD one,
    -- which is exactly the shape of it: at scale 1 logical and physical are
    -- the same size and nothing is stretched.
    --
    -- The price is that an X11 application now draws at its own idea of 1x on a
    -- 1.5x screen, which is a third smaller. So the shell tells X11 the real
    -- scale through `Xft.dpi` (scripts/apply-x11-dpi.sh), which only X11 clients
    -- read; a toolkit that ignores it still needs its own scale -
    -- `GDK_SCALE`/`GDK_DPI_SCALE` for GTK, `QT_SCALE_FACTOR` for Qt - in the
    -- launcher that starts it. Those cannot be set for the session as a whole,
    -- because the same variables reach Wayland applications, which are already
    -- scaled correctly and would double.
    --
    -- It only applies to surfaces created afterwards: an application already
    -- running when this changes keeps the old scaling until it is restarted.
    xwayland = { force_zero_scaling = false },
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

-- The compositor moves in the same rhythm as the shell (theme/Animations.qml):
-- springs for everything that travels, so a window lands where it is sent and
-- can be interrupted without a jump, and a timed curve for layers fading in
-- and out. Material 3 in spirit - a spatial family with a little overshoot,
-- an effects family that is critically damped - with values of this session's
-- own. services/hypr/HyprAnimations.js re-emits the same table, scaled, when
-- the animation speed changes (a spring ignores `speed`); checks.py holds the
-- three copies together. hyprland.conf has no springs and uses the beziers.
hl.curve("buchhwinSpatialFast", { type = "spring", mass = 1, stiffness = 700, dampening = 50 })
hl.curve("buchhwinSpatial", { type = "spring", mass = 1, stiffness = 380, dampening = 34 })
hl.curve("buchhwinSpatialSlow", { type = "spring", mass = 1, stiffness = 200, dampening = 26 })
hl.curve("buchhwinEffectsFast", { type = "spring", mass = 1, stiffness = 3200, dampening = 113 })
hl.curve("buchhwinEffects", { type = "spring", mass = 1, stiffness = 1400, dampening = 75 })
hl.curve("buchhwinEffectsSlow", { type = "spring", mass = 1, stiffness = 700, dampening = 53 })
hl.curve("buchhwinFast", { type = "bezier", points = { {0.22, 1.0}, {0.36, 1.0} } })
hl.curve("buchhwinSpring", { type = "bezier", points = { {0.2, 1.12}, {0.32, 1.0} } })
hl.curve("buchhwinStandard", { type = "bezier", points = { {0.2, 0.0}, {0.0, 1.0} } })
hl.curve("buchhwinAccel", { type = "bezier", points = { {0.3, 0.0}, {0.8, 0.15} } })
hl.animation({ leaf = "windows", enabled = true, speed = 2.0, spring = "buchhwinSpatial", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.7, spring = "buchhwinSpatialFast", style = "popin 87%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.0, spring = "buchhwinSpatial" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.7, spring = "buchhwinEffects" })
-- A new window's own fade-in, faster than every other fade: 90 % opaque after
-- ~70 ms instead of ~105 (16.10., computed from the springs), so a window that
-- has just started looks there sooner. Its popin is not what waits: the
-- window is drawn from the first frame at 87 %.
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.2, spring = "buchhwinEffectsFast" })
hl.animation({ leaf = "layers", enabled = true, speed = 1.7, bezier = "buchhwinStandard", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "buchhwinAccel", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.2, spring = "buchhwinSpatial", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.0, spring = "buchhwinSpatialSlow", style = "slidevert" })
hl.animation({ leaf = "border", enabled = true, speed = 2.0, spring = "buchhwinEffectsSlow" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "buchhwinFast" })

-- Keybindings ---------------------------------------------------------------
-- Lua binds show up as `__lua` in `hyprctl binds`; the descriptions are the
-- titles Settings > Shortcuts shows (services/shortcuts/ShortcutLogic.js).
local function exec(command) return hl.dsp.exec_cmd(command) end
-- What the shell does on a key: a Hyprland global shortcut,
-- `buchhwin:<target>.<function>[.<argument>]`, which the running shell
-- registered (shell.qml, services/shortcuts/ShellShortcuts.js) and answers by
-- running the IPC function of the same name. Through `exec(ipc .. …)` every
-- press started `sh` and the Quickshell IPC client first - 30-40 ms before
-- the shell knew about it. `true` here is the way back to that.
local shortcutsOverIpc = false
local function shell(action)
    if shortcutsOverIpc then return exec(ipc .. action) end
    return hl.dsp.global("buchhwin:" .. action:gsub("%s+", "."))
end
-- The same, with Hyprland's own dispatcher when no shell is there to answer:
-- a workspace key has to work while the shell restarts. The shell is up when
-- its wallpaper surface is.
local function shellOr(action, fallback)
    if shortcutsOverIpc then return exec(ipc .. action) end
    local shortcut = hl.dsp.global("buchhwin:" .. action:gsub("%s+", "."))
    return function()
        if #hl.get_layers({ namespace = "buchhwin-wallpaper" }) > 0 then hl.dispatch(shortcut)
        else hl.dispatch(fallback) end
    end
end
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
hl.bind(keyFor("SUPER + ALT + E"), shell("editor toggle"), { description = "Layout editor" })
hl.bind(keyFor("SUPER + ALT + D"), shell("desktop cycleMode"), { description = "Desktop mode: widgets, bar, notch" })
hl.bind(keyFor("SUPER + ALT + P"), shell("mode cycle"), { description = "Mode: minimal, work, gaming, laptop, desk" })
-- The work apps (Settings > Apps), started together.
hl.bind(keyFor("SUPER + ALT + W"), shell("sessionApps startWork"), { description = "Start my work apps" })
hl.bind(keyFor("SUPER + P"), shell("profile toggle"), { description = "Profiles and modes" })
-- The display switcher (laptop only, duplicate, extend, external only), and
-- the projector key, which moves on to the next choice while it is open.
hl.bind(keyFor("SUPER + SHIFT + P"), shell("displays toggleSwitcher"), { description = "Display switcher" })
hl.bind(keyFor("XF86Display"), shell("displays key"), { submap_universal = true, description = "Display switcher" })
-- F1, not ?: on a German layout ? is Shift+ss and unreliable as a binding.
hl.bind(keyFor("SUPER + F1"), shell("shortcuts toggleSheet"), { description = "All keyboard shortcuts" })
hl.bind(keyFor("SUPER + D"), shell("launcher toggle"), { description = "Launcher" })
hl.bind(keyFor("SUPER + O"), shell("controlCenter toggle"), { description = "Control center" })
hl.bind(keyFor("SUPER + I"), shell("settings toggle"), { description = "Settings" })
hl.bind(keyFor("SUPER + N"), shell("notifications toggle"), { description = "Notification center" })
hl.bind(keyFor("SUPER + K"), shell("dashboard toggle"), { description = "Dashboard" })
hl.bind(keyFor("SUPER + M"), shell("powerMenu toggle"), { description = "Session menu" })
hl.bind(keyFor("SUPER + W"), shell("overview toggle"), { description = "Overview" })
hl.bind(keyFor("SUPER + SHIFT + W"), shell("wallpaperPicker toggle"), { description = "Wallpaper picker" })
hl.bind(keyFor("SUPER + SHIFT + D"), shell("dock toggle"), { description = "Dock" })
-- The start menu, only while the dock has a start button (the taskbar): what a
-- click on it opens, out of it. Anywhere else the key does nothing.
hl.bind(keyFor("SUPER + SPACE"), shell("startMenu key"), { description = "Start menu" })
hl.bind(keyFor("SUPER + SHIFT + C"), shell("colorPicker pick"), { description = "Pick a color off the screen" })
-- Alt+Tab switcher: releasing Alt focuses the selection (transparent, so apps
-- still see the release; a confirm without an open switcher does nothing).
hl.bind(keyFor("ALT + TAB"), shell("switcher next"), { description = "Next window" })
hl.bind(keyFor("ALT + SHIFT + TAB"), shell("switcher previous"), { description = "Previous window" })
hl.bind(keyFor("ALT + ALT_L"), shell("switcher confirm"), { release = true, transparent = true, description = "Switch to selected window" })
hl.bind(keyFor("SUPER + V"), shell("clipboard toggle"), { description = "Clipboard history" })
hl.bind(keyFor("SUPER + PERIOD"), shell("emoji toggle"), { description = "Emoji picker" })
hl.bind(keyFor("SUPER + L"), exec(projectPath .. "/scripts/session-action.sh lock"), { description = "Lock screen" })

-- Screenshots.
hl.bind(keyFor("SUPER + S"), exec(projectPath .. "/scripts/screenshot.sh region"), { description = "Screenshot of a region" })
hl.bind(keyFor("SUPER + SHIFT + S"), exec(projectPath .. "/scripts/screenshot.sh screen"), { description = "Screenshot of the screen" })
hl.bind(keyFor("SUPER + ALT + S"), exec(projectPath .. "/scripts/screenshot.sh window"), { description = "Screenshot of a window" })
-- Text from a region of the screen (tesseract), on the clipboard.
hl.bind(keyFor("SUPER + ALT + T"), exec(projectPath .. "/scripts/screenshot.sh text"), { description = "Copy text from the screen" })
hl.bind(keyFor("Print"), exec(projectPath .. "/scripts/screenshot.sh region"), { description = "Screenshot of a region" })
-- Screen recording (pressing it again stops).
hl.bind(keyFor("SUPER + SHIFT + R"), shell("recording toggle region"), { description = "Record a region" })
hl.bind(keyFor("SUPER + CTRL + SHIFT + R"), shell("recording toggle screen"), { description = "Record the screen" })

-- Window actions.
hl.bind(keyFor("SUPER + Q"), hl.dsp.window.close(), { description = "Close window" })
hl.bind(keyFor("SUPER + F"), hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Fullscreen" })
-- Floating on and off. There was no binding for this at all until somebody
-- asked how to do it: `hyprctl binds` found none, while the shortcut sheet has
-- known the title "Toggle floating" since it was written. A tiled window
-- floats at a size of its own, centred (HyprlandService.toggleFloating); the
-- tile's own size was the whole screen beside no other window.
hl.bind(keyFor("SUPER + C"), shellOr("window toggleFloating", hl.dsp.window.float()), { description = "Toggle floating" })
-- Minimize (services/MinimizeService.qml): the window to a special workspace of
-- its own, listed on the dock, in the overview and in Alt+Tab. Without a shell
-- to answer, Shift brings every minimized window back
-- (scripts/restore-minimized.sh); Super+H minimizes nothing then - a window
-- minimized without the shell would be listed nowhere.
hl.bind(keyFor("SUPER + H"), shell("window minimize"), { description = "Minimize window" })
hl.bind(keyFor("SUPER + SHIFT + H"), shellOr("window restore", exec(projectPath .. "/scripts/restore-minimized.sh")), { description = "Restore minimized window" })

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

-- Arranging the windows of a workspace: the focused one moves the way the
-- arrow points, taking its neighbour's place (dwindle puts it into that slot);
-- at the screen's edge it goes on to the next monitor, as the focus does.
hl.bind(keyFor("SUPER + CTRL + LEFT"), hl.dsp.window.move({ direction = "left" }), { description = "Move window left" })
hl.bind(keyFor("SUPER + CTRL + RIGHT"), hl.dsp.window.move({ direction = "right" }), { description = "Move window right" })
hl.bind(keyFor("SUPER + CTRL + UP"), hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
hl.bind(keyFor("SUPER + CTRL + DOWN"), hl.dsp.window.move({ direction = "down" }), { description = "Move window down" })

-- Workspaces 1-9, through the shell: with workspaces per monitor, `Super+3`
-- means "the third workspace of the monitor under the focus", and only the
-- shell knows which monitor that is. `shellOr` falls back to the old, global
-- behaviour (Hyprland's own dispatcher) while no shell is running.
-- Moving a window keeps the user on the current workspace.
-- `dont_inhibit`: these keys reach Hyprland even while a window holds the
-- keyboard. A VM console (virt-manager, SPICE) asks to inhibit shortcuts, and
-- Super+1 went to the guest: no way back to a workspace without the mouse.
--
-- Written out rather than in a loop, and each with its command spelled out:
-- these go through `keyFor` like every other bind, so Settings > Shortcuts
-- can move them; the shell reads the default combination out of this file
-- as the literal string `keyFor("SUPER + 1")` (ShortcutLogic.parseDefaults),
-- and scripts/lib/checks.py reads the action out of `shellOr("…")` the same
-- way, so a helper that built the string would hide it from the drift check.
hl.bind(keyFor("SUPER + 1"), shellOr("workspaces switchTo 1", hl.dsp.focus({ workspace = 1 })), { dont_inhibit = true, description = "Go to workspace 1" })
hl.bind(keyFor("SUPER + 2"), shellOr("workspaces switchTo 2", hl.dsp.focus({ workspace = 2 })), { dont_inhibit = true, description = "Go to workspace 2" })
hl.bind(keyFor("SUPER + 3"), shellOr("workspaces switchTo 3", hl.dsp.focus({ workspace = 3 })), { dont_inhibit = true, description = "Go to workspace 3" })
hl.bind(keyFor("SUPER + 4"), shellOr("workspaces switchTo 4", hl.dsp.focus({ workspace = 4 })), { dont_inhibit = true, description = "Go to workspace 4" })
hl.bind(keyFor("SUPER + 5"), shellOr("workspaces switchTo 5", hl.dsp.focus({ workspace = 5 })), { dont_inhibit = true, description = "Go to workspace 5" })
hl.bind(keyFor("SUPER + 6"), shellOr("workspaces switchTo 6", hl.dsp.focus({ workspace = 6 })), { dont_inhibit = true, description = "Go to workspace 6" })
hl.bind(keyFor("SUPER + 7"), shellOr("workspaces switchTo 7", hl.dsp.focus({ workspace = 7 })), { dont_inhibit = true, description = "Go to workspace 7" })
hl.bind(keyFor("SUPER + 8"), shellOr("workspaces switchTo 8", hl.dsp.focus({ workspace = 8 })), { dont_inhibit = true, description = "Go to workspace 8" })
hl.bind(keyFor("SUPER + 9"), shellOr("workspaces switchTo 9", hl.dsp.focus({ workspace = 9 })), { dont_inhibit = true, description = "Go to workspace 9" })
hl.bind(keyFor("SUPER + SHIFT + 1"), shellOr("workspaces move 1", hl.dsp.window.move({ workspace = 1, follow = false })), { dont_inhibit = true, description = "Move window to workspace 1" })
hl.bind(keyFor("SUPER + SHIFT + 2"), shellOr("workspaces move 2", hl.dsp.window.move({ workspace = 2, follow = false })), { dont_inhibit = true, description = "Move window to workspace 2" })
hl.bind(keyFor("SUPER + SHIFT + 3"), shellOr("workspaces move 3", hl.dsp.window.move({ workspace = 3, follow = false })), { dont_inhibit = true, description = "Move window to workspace 3" })
hl.bind(keyFor("SUPER + SHIFT + 4"), shellOr("workspaces move 4", hl.dsp.window.move({ workspace = 4, follow = false })), { dont_inhibit = true, description = "Move window to workspace 4" })
hl.bind(keyFor("SUPER + SHIFT + 5"), shellOr("workspaces move 5", hl.dsp.window.move({ workspace = 5, follow = false })), { dont_inhibit = true, description = "Move window to workspace 5" })
hl.bind(keyFor("SUPER + SHIFT + 6"), shellOr("workspaces move 6", hl.dsp.window.move({ workspace = 6, follow = false })), { dont_inhibit = true, description = "Move window to workspace 6" })
hl.bind(keyFor("SUPER + SHIFT + 7"), shellOr("workspaces move 7", hl.dsp.window.move({ workspace = 7, follow = false })), { dont_inhibit = true, description = "Move window to workspace 7" })
hl.bind(keyFor("SUPER + SHIFT + 8"), shellOr("workspaces move 8", hl.dsp.window.move({ workspace = 8, follow = false })), { dont_inhibit = true, description = "Move window to workspace 8" })
hl.bind(keyFor("SUPER + SHIFT + 9"), shellOr("workspaces move 9", hl.dsp.window.move({ workspace = 9, follow = false })), { dont_inhibit = true, description = "Move window to workspace 9" })

-- The neighbouring workspace of the monitor under the focus: the next or
-- previous pip of its row, one new one past the last (WorkspaceLogic.step),
-- by key and by Super and the wheel - Windows' Win+Ctrl+arrows, GNOME's
-- Super+Page Up/Down. With Shift the window goes along. Through the shell
-- like the numbers, so the per-monitor blocks and the held workspaces count;
-- without one, Hyprland's own `m+1`, the monitor's existing workspaces. One
-- wheel step per binds.scroll_event_delay (300 ms), so a touchpad swipe is a
-- step too, not ten.
hl.bind(keyFor("SUPER + Next"), shellOr("workspaces next", hl.dsp.focus({ workspace = "m+1" })), { description = "Next workspace" })
hl.bind(keyFor("SUPER + Prior"), shellOr("workspaces previous", hl.dsp.focus({ workspace = "m-1" })), { description = "Previous workspace" })
hl.bind(keyFor("SUPER + SHIFT + Next"), shellOr("workspaces moveNext", hl.dsp.window.move({ workspace = "m+1" })), { description = "Move window to the next workspace" })
hl.bind(keyFor("SUPER + SHIFT + Prior"), shellOr("workspaces movePrevious", hl.dsp.window.move({ workspace = "m-1" })), { description = "Move window to the previous workspace" })
hl.bind(keyFor("SUPER + mouse_down"), shellOr("workspaces scroll down", hl.dsp.focus({ workspace = "m+1" })), { description = "Next workspace" })
hl.bind(keyFor("SUPER + mouse_up"), shellOr("workspaces scroll up", hl.dsp.focus({ workspace = "m-1" })), { description = "Previous workspace" })

-- A window kept on top: floated if it is tiled, then pinned - on every
-- workspace of its monitor, above the rest (PowerToys' Win+Ctrl+T). Again to
-- let it go; one the shell floated for this goes back into the layout.
hl.bind(keyFor("SUPER + CTRL + T"), shell("window keepOnTop"), { description = "Keep window on top" })

-- The drop-down terminal: one Alacritty window on a special workspace of its
-- own, shown over whatever is on screen and put away again (Yakuake). The key
-- left of 1 by its place - ^ on a German keyboard, ` on a US one; the first
-- press starts the window. Without a shell the key still shows or hides it.
hl.bind(keyFor("SUPER + code:49"), shellOr("dropdown toggle", hl.dsp.workspace.toggle_special("buchhwin-dropdown")), { description = "Drop-down terminal" })

-- Screen zoom around the pointer, Hyprland's cursor.zoom_factor, in the
-- shell's steps with the OSD (services/hypr/ScreenEffectsLogic.js): Super and
-- + / - / 0, beside each other on the German layout.
hl.bind(keyFor("SUPER + plus"), shell("zoom increase"), { description = "Zoom in" })
hl.bind(keyFor("SUPER + minus"), shell("zoom decrease"), { description = "Zoom out" })
hl.bind(keyFor("SUPER + 0"), shell("zoom reset"), { description = "Reset zoom" })
-- The color filter chosen in Settings > Appearance, on and off (Windows'
-- Win+Ctrl+C).
hl.bind(keyFor("SUPER + CTRL + C"), shell("colorFilter toggle"), { description = "Color filter on or off" })

-- Keyboard passthrough: every key goes to the focused window - Alt+Tab, the
-- Windows key and Super+L reach a Citrix session or a virtual machine instead
-- of this session - until Super+Esc again. The submap holds nothing but that
-- way out, bound here in the compositor so it never waits for the shell; the
-- hardware keys below are bound for every submap (`submap_universal`) and keep
-- working. The shell shows a chip while it lasts and gives the keys back when
-- the focus goes to another window (services/hypr/PassthroughLogic.js). Both
-- binds go through the same keyFor, so moving the key moves the way out too.
hl.bind(keyFor("SUPER + Escape"), hl.dsp.submap("passthrough"), { description = "Pass the keys to the window" })
hl.define_submap("passthrough", function()
    hl.bind(keyFor("SUPER + Escape"), hl.dsp.submap("reset"), { description = "Give the keys back" })
end)

-- Pointer moving and resizing.
hl.bind(keyFor("SUPER + mouse:272"), hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind(keyFor("SUPER + mouse:273"), hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Hardware keys talk to the system backends directly; the shell follows the
-- resulting PipeWire, backlight and MPRIS events. They are bound for every
-- submap: the keyboard passthrough above takes every other key, not these,
-- and not the lid.
--
-- Except the volume keys, which the shell answers in the PipeWire connection
-- it holds anyway (the same 5 % steps, up to 100 %): a held key repeats about
-- 25 times a second, and each repeat was a `wpctl` process connecting to
-- PipeWire. Without a shell they run wpctl, as the conf dialect's do.
hl.bind(keyFor("XF86AudioRaiseVolume"), shellOr("audio up", exec("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+")), { locked = true, submap_universal = true, repeating = true, description = "Volume up" })
hl.bind(keyFor("XF86AudioLowerVolume"), shellOr("audio down", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")), { locked = true, submap_universal = true, repeating = true, description = "Volume down" })
hl.bind(keyFor("XF86AudioMute"), shellOr("audio mute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")), { locked = true, submap_universal = true, description = "Mute audio" })
hl.bind(keyFor("XF86AudioMicMute"), shellOr("audio micMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")), { locked = true, submap_universal = true, description = "Mute microphone" })
-- Push to talk: the default microphone is on while the key is held, and
-- back the way it was when it is let go (AudioService.pushToTalk). The
-- shell takes both edges of the global shortcut (ShellShortcuts.HOLD); a
-- press while held ends the hold, should a release go unheard.
hl.bind(keyFor("SUPER + T"), shell("audio talk"), { description = "Push to talk (hold)" })
-- Caps Lock's message (Settings > Desktop > Messages on screen, off by
-- default): sent on the release, whatever the modifiers, and the key stays
-- the window's.
hl.bind(keyFor("Caps_Lock"), shell("osd capsLock"), { release = true, non_consuming = true, ignore_mods = true, description = "Caps Lock message" })
-- The backlight keys go through the shell, which runs the same brightnessctl
-- step and then re-reads the backlight at once for the OSD (the udev monitor
-- sees the change too - amdgpu sends a change uevent per write - but only
-- after its debounce). As `exec("brightnessctl … && " .. ipc .. "brightness refresh")`
-- every repeat of a held key - about 25 a second - started sh, brightnessctl
-- and the Quickshell IPC client. Without a shell the key runs brightnessctl.
hl.bind(keyFor("XF86MonBrightnessUp"), shellOr("brightness up", exec("brightnessctl -e4 -n2 set 5%+")), { locked = true, submap_universal = true, repeating = true, description = "Brightness up" })
hl.bind(keyFor("XF86MonBrightnessDown"), shellOr("brightness down", exec("brightnessctl -e4 -n2 set 5%-")), { locked = true, submap_universal = true, repeating = true, description = "Brightness down" })
-- The keyboard light goes through the shell rather than running brightnessctl
-- here: the LED's name carries its driver's prefix (tpacpi on ThinkPads,
-- asus or dell elsewhere) and a key binding cannot know it.
hl.bind(keyFor("XF86KbdBrightnessUp"), shell("kbdBacklight up"), { locked = true, submap_universal = true, repeating = true, description = "Keyboard light up" })
hl.bind(keyFor("XF86KbdBrightnessDown"), shell("kbdBacklight down"), { locked = true, submap_universal = true, repeating = true, description = "Keyboard light down" })
hl.bind(keyFor("XF86KbdLightOnOff"), shell("kbdBacklight toggle"), { locked = true, submap_universal = true, description = "Keyboard light on or off" })
hl.bind(keyFor("XF86AudioPlay"), exec("playerctl play-pause"), { locked = true, submap_universal = true, description = "Play or pause" })
hl.bind(keyFor("XF86AudioPause"), exec("playerctl play-pause"), { locked = true, submap_universal = true, description = "Play or pause" })
hl.bind(keyFor("XF86AudioNext"), exec("playerctl next"), { locked = true, submap_universal = true, description = "Next track" })
hl.bind(keyFor("XF86AudioPrev"), exec("playerctl previous"), { locked = true, submap_universal = true, description = "Previous track" })
-- Without a shell (gave up, still starting) `quickshell ipc` exits 255 and the
-- lid still locks the screen.
hl.bind(keyFor("switch:on:Lid Switch"), exec(ipc .. "power lidClosed || " .. projectPath .. "/scripts/session-action.sh lock"), { locked = true, submap_universal = true, description = "Lid closed" })
hl.bind(keyFor("switch:off:Lid Switch"), exec(ipc .. "power lidOpened"), { locked = true, submap_universal = true, description = "Lid opened" })

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
-- corners are two thin strips per screen, empty but for four small shapes
-- (shell/desktop/ScreenCorners.qml).
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
hl.layer_rule({ name = "buchhwin-scrim-noblur", match = { namespace = "^(buchhwin-scrim)$" }, blur = false })
-- Surfaces that animate themselves: every ShellPanel and PopupPanel (the
-- card fades and morphs, and the surface stays mapped until that close has
-- finished - `closeTimer` in shell/components/ShellPanel.qml), the switcher
-- and the OSD, which unmap the same way. The compositor's `layers` fade on
-- top of that multiplied the card's own fade for the first frames of every
-- open, and after every close faded an already empty screen-sized buffer
-- out for another hundred milliseconds. Not here: the notification popups,
-- which rely on the compositor's fade-out, and the colour picker, whose
-- namespace is shared with the full-screen picking overlay that does not
-- animate itself. One regex without a comma: the conf parser in
-- scripts/lib/checks.py splits a layerrule at its first comma.
hl.layer_rule({ name = "buchhwin-self-animated", match = { namespace = "^(buchhwin-(batteryPopup|bluetoothPopup|clipboard|controlCenter|dashboard|driveUnlock|emoji|eventEditor|eventsPopup|launcher|mediaPopup|networkPopup|notifications|overview|pairing|powerMenu|privacyPopup|profilePopup|settings|shortcutSheet|systemPopup|volumePopup|vpnPopup|wallpaperPicker|weatherPopup|welcome|wifiPassword|switcher|osd|dockMenu|dock-preview|startMenu|assistant|sharePicker|displaySwitcher|trayMenu))$" }, no_anim = true })
-- Citrix opens its own dialogs ("disconnect / log off", class Wfica, title
-- exactly "wfica") on a workspace of its choosing, such as 1 while the
-- session sits on 2, which looks like a hung session. Floating, centred and
-- pinned, the dialog shows on whatever workspace its monitor has in view, also
-- over a full-screen session. The session window carries its desktop's name as
-- its title ("RDS-... (SSL/TLS Secured, ...)") and is not matched.
hl.window_rule({
    name = "citrix-dialogs",
    match = { class = "^(Wfica)$", title = "^(wfica)$" },
    float = true,
    center = true,
    pin = true,
})
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
-- A browser's picture-in-picture video (Brave and Chromium title it "Picture
-- in picture", Firefox "Picture-in-Picture"): floating, on every workspace,
-- a quarter of the screen's width at 16:9 in its bottom right corner, clear of
-- a dock or a taskbar, its shape kept when it is resized, and the focus left
-- where it was. Without this it tiled into the layout like any window and was
-- gone with the next workspace switch. The place is worked out from the size
-- the rule gives, not from window_w/window_h: those are the window's size
-- before the size rule (800x600 from the browser), and it landed 344 px from
-- the right edge.
hl.window_rule({
    name = "picture-in-picture",
    match = { title = "^(Picture[- ]in[- ][Pp]icture)$" },
    float = true,
    pin = true,
    keep_aspect_ratio = true,
    no_initial_focus = true,
    size = "monitor_w*0.25 monitor_w*0.140625",
    move = "monitor_w*0.75-24 monitor_h-monitor_w*0.140625-88",
})
-- Chromium's "... is sharing your screen" bar with its Stop and Hide buttons,
-- which a Teams call in Brave opens as a small window of its own: tiled, it
-- squeezed the windows beside it for the length of the call. Floating at the
-- bottom centre on every workspace, and it does not take the focus. English
-- and German titles; `[.]`, not a backslash, so both dialects spell it the
-- same (a Lua string would need two).
hl.window_rule({
    name = "screen-share-indicator",
    match = { title = "^(.* is sharing (your screen|a window|a tab)[.]|.* gibt (Ihren Bildschirm|ein Fenster|einen Tab) frei[.])$" },
    float = true,
    pin = true,
    no_initial_focus = true,
    move = "monitor_w*0.5-window_w*0.5 monitor_h-window_h-88",
})
-- The password prompts of the session - the KDE polkit agent and the KDE
-- wallet's - in the middle of the screen over everything, on whatever
-- workspace is shown: a prompt that tiled beside the windows, or waited on
-- another workspace, looked like nothing was happening.
hl.window_rule({
    name = "system-prompts",
    match = { class = "^(org[.]kde[.]polkit-kde-authentication-agent-1|polkit-kde-authentication-agent-1|org[.]kde[.]ksecretd|org[.]kde[.]kwalletd6)$" },
    float = true,
    center = true,
    pin = true,
})
-- The drop-down terminal (Super+^, services/hypr/WindowToolsLogic.js): its
-- own Alacritty window on its own special workspace, floating across the top
-- of the screen; the specialWorkspace animation slides it in.
hl.window_rule({
    name = "buchhwin-dropdown",
    match = { class = "^(buchhwin-dropdown)$" },
    workspace = "special:buchhwin-dropdown",
    float = true,
    size = "monitor_w*0.9 monitor_h*0.45",
    move = "monitor_w*0.05 monitor_h*0.04",
})
