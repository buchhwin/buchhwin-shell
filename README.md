# buchhwin-shell

A minimal desktop shell for Fedora, Hyprland and Quickshell.

The desktop shows only a clock until you need something. Panels open instantly,
follow one central theme (dark, light or automatic) and talk to the Linux and
KDE services that are already on the machine, so there is no second copy of
your network, sound, calendar or password stack. It does not start Plasma
Shell, Waybar or Rofi.

- **Panels** — control center, launcher, notifications, clipboard, an
  overview of workspaces and windows, and a time/weather/calendar dashboard.
- **Three desktop shapes**, one at a time: free-floating widgets, a bar of
  pills on any of the four screen edges, or a notch at the top centre that
  expands on hover.
- **Arranged by hand.** One layout editor for all of them, with dragging,
  snapping and per-monitor layouts; the control center's tiles, the dashboard's
  cards and the notch's lists are rearranged the same way.
- **Its own lock screen and SDDM login theme**, in the same style, with
  fingerprint support.
- **25 settings pages**, from displays and input to a per-app audio mixer and
  KDE Connect.

The interface is in English.

## Requirements

- **Fedora 44**, **Hyprland 0.56** (the session uses the Lua config;
  `hyprland.conf` stays as a fallback) and **Quickshell 0.2**
- Fonts: Inter Variable, JetBrains Mono and a Nerd Font (FiraCode Nerd Font)

Quickshell is in Fedora's own repositories. Hyprland is not, and on this
machine it comes from a Copr:

```sh
sudo dnf copr enable sachesi/hyprland
sudo dnf install hyprland quickshell
```

## Installation

```sh
git clone https://github.com/buchhwin/buchhwin-shell.git
cd buchhwin-shell
./install/bootstrap.sh            # dry run: prints every command it would run
./install/bootstrap.sh --apply
```

Then log out and choose **buchhwin-shell** from the session list.

`bootstrap.sh` is the only script here that reaches the network, so it is
deliberately the loudest: without `--apply` it prints every command, in order,
and changes nothing. It runs as **you**, not as root, and calls `sudo` for the
steps that need it — the user step installs into `$HOME`, and a `$HOME` owned
by root is a worse problem than the one this solves.

It installs the packages the shell talks to, the icon font (Fedora packages no
Nerd Font, and without one every glyph in the interface is an empty box), a
browser and the handful of applications the session points at, and then runs
the two installers below. Re-running it is safe: `dnf` skips what is already
installed, repositories are only added when missing, and a default application
is only set when that category has none.

| | |
| --- | --- |
| `--minimal` | only what the shell itself needs — no recording, fingerprint, phone, calendar writing or applications |
| `--skip-apps` | no browser, file manager or media applications |
| `--skip-fonts` | leave fonts alone |

Two repositories are added: **Hyprland** from a Copr (Quickshell is in Fedora's
own), and **Brave** from Brave's RPM repository — the native build, not the
Flatpak. Everything else comes from Fedora.

The applications it sets as this session's defaults are Brave (browser),
Dolphin (files), Kitty (terminal), VLC (video and music), Okular (PDF),
Gwenview (images) and Ark (archives). These are **session-local**: they go to
`buchhwin-shell-mimeapps.list`, which is only read when `XDG_CURRENT_DESKTOP`
starts with `buchhwin-shell`, so Plasma keeps its own.

### By hand, if you would rather see each step

<details>
<summary>The packages, the source and the two installers</summary>

```sh
sudo dnf copr enable sachesi/hyprland
sudo dnf install \
  hyprland quickshell \
  kitty zsh starship fastfetch \
  brightnessctl wireplumber pipewire-utils playerctl NetworkManager \
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep \
  swaylock kdialog udisks2 \
  python3-dbus python3-gobject python3-pillow \
  xdg-desktop-portal-kde polkit-kde kf6-kwallet \
  rsms-inter-fonts jetbrains-mono-fonts fontconfig unzip
```

Optional, each for one feature:

```sh
sudo dnf install wf-recorder          # screen recording
sudo dnf install fprintd              # fingerprint on the lock screen
sudo dnf install kde-connect          # the phone page
sudo dnf install hyprland-guiutils    # Hyprland's own dialogs
sudo dnf install sddm                 # the login screen theme
sudo dnf install merkuro kdepim-addons \
  python3-kf6-kcoreaddons python3-kf6-kcalendarcore   # calendar, incl. writing events
```

The icon font is not packaged; take the `*Propo*` faces out of
[FiraCode.zip](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip),
put them in `~/.local/share/fonts/FiraCode` and run `fc-cache -f`.

Then look before you install — neither of these changes anything:

```sh
./scripts/doctor.sh          # what this machine has and what it is missing
./scripts/test.sh            # static checks and QML/JS/Python unit tests
./scripts/test.sh --session  # plus nested Hyprland smoke tests (conf and Lua)
./install/install.sh         # dry run: prints every file it would touch
```

and install:

```sh
./install/install.sh --apply
sudo ./install/system-install.sh
```

</details>

### What the two installers do

The user step links the project to `~/.local/share/buchhwin-shell`, the session
launcher to `~/.local/bin`, the systemd targets
(`buchhwin-shell-session.target`, `buchhwin-shell-autostart.target`) and the
portal routing file `buchhwin-shell-portals.conf` to
`~/.config/xdg-desktop-portal/`. Existing targets are moved to timestamped
backups. It also copies the Fedora dwl Fastfetch configuration once, if
present.

The root step installs a small `/usr/local/bin/buchhwin-shell-session` wrapper
that runs `~/.local/share/buchhwin-shell/session/buchhwin-shell-session` (so
launcher updates need no sudo), the display-manager entry, and the lock screen
PAM services `buchhwin-lock` and `buchhwin-lock-password` (existing files are
kept).

### Logging in

The session runs Hyprland with `hypr/hyprland.lua`. If that start fails within
ten seconds it starts once more with `hypr/hyprland.conf`. To choose the format
yourself (for example from a TTY), write `lua` or `conf` to
`~/.config/buchhwin-shell/hypr-config` or set `BUCHHWIN_HYPR_CONFIG`.

All visual choices are session-local. KDE's wallet, dialogs and colours are
reused: the session identifies as `buchhwin-shell:Hyprland`, routes the Secret
portal to KWallet (Brave keeps sync and cookies), uses KDE file dialogs and
sets `QT_QPA_PLATFORMTHEME=kde`.

### Optional login screen theme

`session/sddm/buchhwin` is an SDDM theme in the style of the lock screen
(blurred wallpaper, large clock, avatar, password pill, session and power
buttons). Fedora 44 uses Plasma Login Manager by default, which has no themes;
`--use-sddm` makes SDDM the display manager from the next boot.

```sh
sudo ./install/system-install.sh --sddm-theme --use-sddm   # wallpaper from settings
sudo ./install/system-install.sh --sddm-theme --wallpaper ~/Pictures/wall.jpg
sudo ./install/system-install.sh --sddm-theme-remove       # restore theme and display manager
sddm-greeter-qt6 --test-mode --theme session/sddm/buchhwin  # preview in a window
```

The installer copies the wallpaper into the theme (SDDM cannot read home
directories) and backs up other `[Theme] Current=` settings. If the login
screen ever fails, switch to a TTY and run
`sudo rm /etc/sddm.conf.d/buchhwin-theme.conf`.

All visual choices are session-local. KDE's wallet, dialogs and colours are
reused: the session identifies as `buchhwin-shell:Hyprland`, routes the Secret
portal to KWallet (Brave keeps sync and cookies), uses KDE file dialogs and sets
`QT_QPA_PLATFORMTHEME=kde`.

## Using the shell

| Shortcut | Action |
| --- | --- |
| `Super+Enter` | Default terminal (Kitty: Zsh, Starship, Fastfetch) |
| `Super+B` / `Super+E` | Default browser / file manager (Brave / Dolphin unless changed) |
| `Super+D` | Launcher: apps by category, `>` commands, `/` files, `@` settings, `=` calculator, `?` web search (`Tab` mode, `Ctrl+↑/↓` category) |
| `Super+O` | Control center |
| `Super+I` | Settings |
| `Super+N` | Notifications |
| `Super+K` | Dashboard: time, weather and calendar (also: click the clock) |
| `Super+W` | Overview of workspaces and windows |
| `Alt+Tab` / `Alt+Shift+Tab` | Window switcher (release Alt to focus, Esc cancels) |
| `Super+V` | Clipboard history |
| `Super+.` | Emoji picker (Enter copies) |
| `Super+S` / `Super+Shift+S` / `Super+Alt+S` / `Print` | Screenshot of a region / screen / window / region |
| `Super+Shift+R` / `Super+Ctrl+Shift+R` | Start or stop recording a region / the screen |
| `Super+M` | Session and power menu |
| `Super+L` | Lock screen |
| `Super+F1` | Every keyboard shortcut, with a search field |
| `Super+Alt+E` | Layout editor |
| `Super+Alt+D` | Desktop mode: widgets → bar → notch |
| `Super+Ctrl+R` | Restart the shell |
| `Super+Q` / `Super+F` | Close window / fullscreen |
| `Super+1…9`, `Super+Shift+1…9` | Switch workspace / move window silently |
| `Super+Arrows` | Resize the active window (repeatable) |
| `Super+Alt+Arrows` | Move focus |
| `Super` + left / right mouse drag | Move / resize a window |
| Volume, brightness, media keys | Direct system control with an on-screen display |
| Lid switch | Settings > Power "When the lid closes" |

Own shortcuts for apps and commands can be added in Settings > Shortcuts.

Touchpad gestures (change or turn off in Settings > Input): three fingers
left/right switch workspaces, three fingers up open the overview, three
fingers down close the open panel, a four-finger pinch opens the launcher.

**Control center** — Wi-Fi, Bluetooth, Do Not Disturb and microphone tiles,
brightness with night light, battery, media with seeking, audio output and
per-app volume and output device, removable drives (while connected), chips for
power profile, dark mode, displays and focus mode, tray apps in the header.
Chevrons open detail pages for network and VPN, Bluetooth, audio, Do Not
Disturb, power, drives and tray menus. The pencil in the header arranges the
tiles: drag one onto another to move it, take one off, put it back.

**Dashboard** (`Super+K` or click on the clock) — time, weather from
Open-Meteo (current conditions, next hours, seven days) for the city chosen in
Settings > Weather, a month or week calendar with the events of the selected
day from your KDE calendars (Akonadi, including Google accounts added in
Merkuro). "+" creates a new event in a writable calendar, with a repetition if
you want one; an existing event opens a details dialog where you can change or
delete it - a recurring one asks first whether you mean this occurrence or the
whole series. Weather and calendar are also desktop widgets, and the clock shows a
small hint shortly before an event.

**Pill bar and notch** (optional) — Settings > Widgets and Settings > Bar &
Pills switch the desktop between exactly one of widgets, a slim bar at the top
(floating pills or one continuous bar) and a notch. Every widget can
become a pill item (full or symbol only; the media pill also has an expanded
mode with controls), pills can be combined, split and moved between left,
centre and right. The workspace pill shows open workspaces or a fixed number.
Clicking a pill opens a small popup for that topic: Wi-Fi, VPN, Bluetooth, a
horizontal media player with a spinning vinyl cover, sound, battery, weather,
today's events, privacy and system usage. The pills can also be joined into
one continuous bar, floating below the top edge or attached to it; items then
sit flat in the bar with a hover highlight, and colour, transparency and
corners follow Appearance. The bar can reserve space for windows and hides
during fullscreen unless set to stay visible.
The notch is a black, MacBook-style notch at the top centre that only shows the
time (and a recording indicator). Hovering it morphs it like the Dynamic Island
into a small overview: time and date, weather, the next event of today, now
playing with controls and a status row; clicks open the dashboard, media popup
or control center, and hotkey panels open centred below the notch.

**Lock screen** (`Super+L`) — a macOS-style lock in its own process: an
unreadably blurred capture of the screen, a large animated clock, avatar and a
password field that moves to the centre while typing. It locks before sleep,
survives shell restarts and restarts itself after a crash. Fingerprints can be
enrolled in Settings > Lock Screen; the lock shows the reader prompt and still
accepts the password at once. Media controls, battery/layout and power buttons
are optional.

**Notifications** — popups appear below the clock with actions. Do Not Disturb
can last one hour, until tomorrow morning or until switched off, and
notifications are silenced automatically during fullscreen apps and games. The
history groups notifications by app.

**Desktop utilities** — on-screen display for volume and brightness,
screenshots with an edit action, screen recording with a red indicator
(wf-recorder or gpu-screen-recorder; sound and frame rate in Settings),
clipboard history with images, a workspace overview with live previews, night
light, focus mode, removable drive notifications with safe eject, low battery
warnings and dimming before the screen turns off.

**Settings** — `Super+I`, the gear icon in the control center or `@` in the
launcher. Pages: Appearance (theme, accent or accent from wallpaper, night
light, panel colour and per-window transparency, fonts, blur, window and shell
corners, borders and gaps, animations, cursor, optionally KDE/GTK apps
following the theme), Wallpaper (per monitor, favourites, slideshow), Desktop &
Widgets, Bar & Pills, Terminal (Kitty, Starship prompt, Fastfetch), Notifications,
Weather, Calendar, Network, Bluetooth, Phone (KDE Connect), Audio (devices,
per-app output, input level), Lock Screen (fingerprint, extras), Power
(separate settings on battery and plugged in, low battery, lid action including
"Screen off" for docks), Shortcuts, Input, Displays, Default Apps (for this
session only; Plasma keeps its own), Updates (read-only dnf5 and Flatpak
check), Autostart and About. `scripts/install-cursor-macos.sh` (also reachable
from Settings) installs the macOS cursor for the current user.

**Layout editor** (`Super+Alt+E`) — one editor for every desktop mode, with the
mode selector in its toolbar. Widgets: add them by category, drag them with
live snapping to edges, centre, other widgets or the grid (hold `Alt` to skip),
resize with the handle, choose Minimal/Capsule/Card style and size, group
widgets into a row, move them to another monitor. Bar: the three zones appear
below the real bar, pills are dragged between and inside them (zone highlight
and insertion marker), added from the same picker, and the inspector sets the
display, order, zone, merge and removal. Notch: a frame marks it as fixed and
shows its options. Plus profiles (Minimal, Work, Gaming, Laptop, Docked) and
undo. Keyboard: `Tab` select, arrows move, `+`/`-` scale, `S` style or pill
display, `A` add, `G` grid, `H` hide, `Delete`, `Ctrl+Z`, `Esc`.

Configuration lives in `~/.config/buchhwin-shell/` (`settings.json`,
`layout.json`, `monitors.json`, `wallpapers.json`, `shortcuts.json` and the
generated terminal files), runtime state in `~/.local/state/buchhwin-shell/`.
Layout files are versioned; older files migrate with a backup, newer or broken
files are never overwritten.

## Plasma terminals

`./install/plasma-terminal.sh --apply` gives Plasma the same terminal: Kitty as
default (Ctrl+Alt+T), Zsh with Fastfetch (`ff`), Starship, autosuggestions and
syntax highlighting, plus a matching Alacritty profile. Existing files are
backed up.

## After the first login

Run `~/.local/share/buchhwin-shell/scripts/session-check.sh` in a terminal
inside the session. It changes nothing and reports what works and what needs
attention.

If the screen ever stays locked, switch to a TTY (Ctrl+Alt+F3), log in and run
`systemctl --user restart buchhwin-shell-lock`.

## Reload and debugging

`Super+Ctrl+R` runs `scripts/reload-shell.sh`. Logs are written to
`${XDG_STATE_HOME:-~/.local/state}/buchhwin-shell/quickshell.log`.

```sh
quickshell list
quickshell log --path ~/.local/share/buchhwin-shell
quickshell ipc --path ~/.local/share/buchhwin-shell show
./scripts/smoke-session.sh            # reload in the running session and check logs
./scripts/nested-session.sh start     # disposable nested Hyprland, sandboxed config
Hyprland --verify-config --config ./hypr/hyprland.conf
```


## Privacy

This repository must remain safe to publish. Never commit coordinates, account
data, OAuth files, tokens, passwords, private keys, host-specific exports or
copied user configuration. Keep local values in ignored files under
`config/local/` or `config/private/`. Before pushing, inspect staged content:

```sh
git diff --cached
git grep -nEi '(password|passwd|api.?key|access.?token|refresh.?token|client.?secret|latitude|longitude)'
```

## License

MIT. See [LICENSE](LICENSE).
