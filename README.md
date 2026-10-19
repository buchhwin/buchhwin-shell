<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/buchhwin/buchhwin-shell/main/.github/assets/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/buchhwin/buchhwin-shell/main/.github/assets/banner-light.svg">
    <img alt="buchhwin-shell" src="https://raw.githubusercontent.com/buchhwin/buchhwin-shell/main/.github/assets/banner-dark.svg" width="820">
  </picture>
</p>

<p align="center">
  A complete desktop on Hyprland and Quickshell: a notch, panels, a layout editor,<br>
  its own lock and login screens, built on the KDE services already on your machine.
</p>

<p align="center">
  <a href="https://github.com/buchhwin/buchhwin-shell/actions/workflows/test.yml"><img alt="tests" src="https://github.com/buchhwin/buchhwin-shell/actions/workflows/test.yml/badge.svg"></a>
  <img alt="Hyprland 0.56" src="https://img.shields.io/badge/Hyprland-0.56-58e1ff">
  <img alt="Quickshell 0.3" src="https://img.shields.io/badge/Quickshell-0.3-5fafff">
  <img alt="Arch, Fedora, openSUSE Leap" src="https://img.shields.io/badge/Arch%20%C2%B7%20Fedora%20%C2%B7%20openSUSE%20Leap-supported-afd7ff">
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-lightgrey"></a>
</p>

https://github.com/user-attachments/assets/467c2b76-ef77-41a0-a527-854d903a536b

<p align="center"><sub>Also on <a href="https://www.youtube.com/watch?v=5ngu3fTjsfU">YouTube</a></sub></p>

## What it is

- **A quiet desktop.** One shape at a time: a notch at the top that expands on hover,
  a bar of pills on any edge, or free-floating widgets. An optional dock with your
  pinned and running apps hides as soon as a window touches it - or runs along the
  whole edge as a taskbar, with the fastfetch Saturn as its start menu.
- **Panels for everything:** launcher (apps, files, commands, calculator, emoji),
  control center, dashboard with weather and calendar, notifications, clipboard
  history and a live workspace overview.
- **Arranged by hand.** One layout editor for widgets, bar and notch, with snapping
  and per-monitor layouts. Control center tiles and dashboard cards rearrange the same way.
- **Profiles and modes.** Each profile keeps its whole setup. Two come built in,
  `default` and `buchhwin`, each with five modes (minimal, work, gaming, laptop, desk).
- **Its own lock screen and SDDM login theme**, with fingerprint support.
- **No second stack.** Wi-Fi, VPN, Bluetooth, sound, calendar and passwords come from
  NetworkManager, PipeWire, Akonadi and KWallet, and Plasma keeps working alongside.

## Install

One line. It clones the shell and installs everything it needs: packages, fonts,
the session and the lock screen. It runs as you and asks for `sudo` only where it
has to.

```sh
git clone https://github.com/buchhwin/buchhwin-shell.git && cd buchhwin-shell && ./install/bootstrap.sh --apply
```

Then log out, pick **buchhwin-shell** on the login screen, and you're in.

> [!TIP]
> On Arch, bring the system up to date first with `sudo pacman -Syu`. To see every
> command before anything changes, run the line without `--apply`.

**Updating:** Settings › Updates › *The shell*, or `git pull --ff-only && ./install/install.sh --apply`. When the update notice names new packages or changed system files, run the command it gives (`./install/bootstrap.sh --apply`, `sudo ./install/system-install.sh`).

<details>
<summary><b>Distributions and options</b></summary>

<br>

| Distribution | Notes |
| --- | --- |
| **Arch Linux** | Everything comes from the official repositories. Brave comes from the AUR (`brave-bin`, through paru or yay). Bluetooth needs `sudo systemctl enable --now bluetooth` once. |
| **Fedora 44** | Hyprland and Starship come from Coprs (`sachesi/hyprland`, `atim/starship`) and Brave from its RPM repository. Quickshell is Fedora's own package, a 0.2.1 snapshot from February 2026 (the shell is made on 0.3). |
| **openSUSE Leap 16.0** | Quickshell comes from OBS. Hyprland 0.56 is built from pinned sources into `~/.local/opt/buchhwin-hyprland`, and `install/build-hyprland-leap.sh --remove --apply` removes it again. A later 16.x is untried and needs `--distro opensuse-leap`. |

Re-running is safe. Derivatives such as EndeavourOS or CachyOS need `--distro arch`.

| Flag | |
| --- | --- |
| `--minimal` | only what the shell itself needs: no recording, fingerprint, phone, calendar writing or apps |
| `--skip-apps` | no browser, file manager or media apps |
| `--skip-fonts` | leave fonts alone: no font packages, no Nerd Fonts download |
| `--distro NAME` | `arch`, `fedora` or `opensuse-leap` instead of detecting it |

The default apps it sets (Brave, Dolphin, kitty, VLC, Okular, Gwenview, Ark) apply to
this session only. Plasma keeps its own.

</details>

<details>
<summary><b>Step by step, login theme, Plasma terminal</b></summary>

<br>

Look first. None of these change anything:

```sh
./scripts/doctor.sh          # what this machine has and what it is missing
./install/install.sh         # dry run: every file the user step would link
```

Then install. The user step only creates symlinks into `~/.local` and `~/.config`
and backs up anything it replaces. The root step installs the session entry and the
lock screen's PAM files:

```sh
./install/install.sh --apply
sudo ./install/system-install.sh
```

**Login screen theme** (SDDM, in the lock screen's style):

```sh
sudo ./install/system-install.sh --sddm-theme              # wallpaper from your settings
sudo ./install/system-install.sh --sddm-theme --use-sddm   # also make SDDM the display manager
sudo ./install/system-install.sh --sddm-theme-remove       # undo
```

**Plasma terminal:** `./install/plasma-terminal.sh --apply` gives Plasma the same kitty,
zsh and Starship setup and backs up existing files. A file that is a symlink (a dotfiles
checkout) is kept, and so is Plasma's terminal when its KDE files are links; `--force`
replaces them.

</details>

## Keys

| Key | |
| --- | --- |
| `Super` `D` | Launcher (`>` commands · `/` files · `@` settings · `=` calculator · `:` emoji) |
| `Super` `Enter` · `B` · `E` | Terminal · browser · file manager |
| `Super` `O` | Control center |
| `Super` `K` | Dashboard: time, weather, calendar |
| `Super` `N` | Notifications |
| `Super` `I` | Settings |
| `Super` `W` | Overview of workspaces and windows |
| `Alt` `Tab` | Window switcher |
| `Super` `V` · `.` | Clipboard history · emoji picker |
| `Super` `S` · `Shift` `S` · `Alt` `S` | Screenshot: region · screen · window |
| `Super` `Shift` `R` | Record a region (again to stop) |
| `Super` `Shift` `C` | Pick a color off the screen |
| `Super` `Shift` `W` | Wallpaper picker |
| `Super` `Shift` `D` | Dock (turns it on, then shows it) |
| `Super` `Space` | Start menu (with the Taskbar's start button) |
| `Super` `P` · `Alt` `P` | Profiles and modes · next mode |
| `Super` `Alt` `D` | Desktop shape: widgets → bar → notch |
| `Super` `Alt` `E` | Layout editor |
| `Super` `L` · `M` | Lock · session and power menu |
| `Super` `1`…`9` · `Shift` `1`…`9` | Go to workspace · move window there |
| `Super` `Q` · `F` · `C` | Close · fullscreen · floating |
| `Super` `Ctrl` `←` `→` `↑` `↓` | Arrange: move the window that way, into its neighbour's place |
| `Super` `F1` | **All shortcuts, searchable** |

Every key can be changed in Settings › Shortcuts. Touchpad gestures: swipe three fingers
sideways to switch workspaces, up for the overview and down to close a panel. Pinch to
open the launcher.

## Configuration and help

- Settings live in `~/.config/buchhwin-shell/` (`settings.json`, `layout.json`, …),
  logs in `~/.local/state/buchhwin-shell/quickshell.log`. Share that log (or plain `quickshell log`) in an issue - never
  Quickshell's own `log.qslog` under `/run/user` or a `quickshell log -r "*.debug=true"` dump: they hold window titles,
  network names and device addresses.
- Something not working? `~/.local/share/buchhwin-shell/scripts/session-check.sh` checks the
  session without changing anything.
- `Super` `Ctrl` `R` restarts the shell.
- Locked out? Switch to a TTY (`Ctrl` `Alt` `F3`), log in and run
  `systemctl --user restart buchhwin-shell-lock`.
- The session runs `hypr/hyprland.lua`. If that fails, it falls back to `hypr/hyprland.conf`.

<details>
<summary><b>Development</b></summary>

<br>

```sh
./scripts/test.sh             # static checks and QML/JS/Python/shell tests
./scripts/test.sh --session   # plus smoke tests in a nested Hyprland (opens a window)
./scripts/nested-session.sh start   # a disposable nested session with a sandboxed config
```

Never commit coordinates, tokens, account data or copied user configuration. Keep local
values in `config/local/` or `config/private/`, which are both ignored. `scripts/test.sh`
checks for this.

</details>

## License

MIT. See [LICENSE](LICENSE).
