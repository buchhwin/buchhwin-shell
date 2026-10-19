# Packages for openSUSE Leap 16, sourced by install/bootstrap.sh after the
# distribution was detected (install/lib/distro.sh). Same names as
# install/packages/fedora.sh; every package below was looked up in Leap 16.0's
# repo-oss or in the two repositories named here.

# zypper needs nothing extra to add a repository.
bootstrap_packages=()

# Leap has neither Hyprland nor Quickshell. Quickshell comes from the Open
# Build Service, at priority 120 - a lower priority than repo-oss (99) - so
# the repository can only *add* what Leap does not have and never replace a
# package of the running system. Hyprland is built from source instead
# (install/build-hyprland-leap.sh, step 4 of bootstrap.sh): the community
# repository that packaged it for Leap is broken, its Hyprland needing
# libraries it no longer ships and its libraries a newer libinput than Leap's.
# $releasever is zypper's, not the shell's: zypper puts the running release
# in (16.0), so the repository follows a system upgraded to the next one -
# Quickshell is built against that release's Qt and must not outlive it.
repos=(
  "quickshell-leap16|https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/\$releasever/|120"
)
brave_repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

# Hyprland and its portal: built, not installed (see above).
core=(quickshell)

packages=(
  # terminal and prompt. Not zsh-autosuggestions and zsh-syntax-highlighting,
  # which zsh/.zshrc sources where they are: Leap 16.0's repo-oss has
  # neither, only the shells: OBS project does.
  kitty zsh starship fastfetch
  # the backends the shell drives
  brightnessctl wireplumber pipewire-tools playerctl NetworkManager
  plocate jq curl grim slurp swappy wl-clipboard gammastep
  # xclip: reads what an X11 program (Citrix) copied, for the clipboard
  # bridge (scripts/x11-clipboard-bridge.py); in Leap 16.0's repo-oss
  xclip
  swaylock swayidle kdialog udisks2 wireguard-tools
  # the Bluetooth daemon
  bluez
  # nm-applet is the session's only NetworkManager secret agent - without it
  # no VPN or saved-secret password is asked for - and plasma6-nm the dialog
  # an enterprise (802.1X) network is set up in (kcm_networkmanagement)
  NetworkManager-applet plasma6-nm
  # WebP wallpapers (the picker offers them; Qt reads them through this),
  # the Notification portal the session's portals.conf names (gtk), and the
  # user directories the wallpaper folder and the start menu's places use
  qt6-imageformats xdg-desktop-portal-gtk xdg-user-dirs
  # setpriv: the shell's long-running helpers die with it (--pdeathsig)
  util-linux
  # the helper scripts in scripts/ are Python
  python313-dbus-python python313-gobject python313-Pillow
  # KDE pieces the session reuses instead of carrying its own
  xdg-desktop-portal-kde6 polkit-kde-agent-6 kf6-kwallet
  # services/CalendarService.qml imports org.kde.akonadi, and on Leap only
  # merkuro ships that QML module, and org.kde.plasma.PimCalendars, which
  # kdepim-addons ships. Without either the service fails to load and takes
  # the shell with it, so neither is an extra here.
  merkuro kdepim-addons
  # what the font step itself needs: fc-cache/fc-list and an unpacker
  fontconfig unzip
)

# Interface and monospace faces and the emoji the picker draws; the icon
# font is fetched (bootstrap.sh, step 4). --skip-fonts leaves these out.
font_packages=(inter-variable-fonts jetbrains-mono-fonts google-noto-coloremoji-fonts)

# Not here, compared with Fedora: hyprland-guiutils (not packaged for Leap;
# install/build-hyprland-leap.sh builds it with Hyprland), cmatrix (not
# packaged), and the Akonadi Python bindings, so Leap can show calendar events
# but not write them.
extras=(
  wf-recorder                 # screen recording
  fprintd                     # fingerprint on the lock screen
  kdeconnect-kde              # the phone page
  sddm-qt6                    # the login screen theme (the display manager is
                              # NOT switched); Leap's plain "sddm" is the Qt 5
                              # build and conflicts with it
  cava
)

app_packages=(brave-browser dolphin vlc okular gwenview ark)

# Not packaged for Leap, a single static binary upstream: pinned and checked,
# because "latest" from someone else's release page is not something to put
# into ~/.local/bin unseen. NAME|URL|SHA256
fetched_binaries=(
  "cliphist|https://github.com/sentriz/cliphist/releases/download/v0.7.0/v0.7.0-linux-amd64|d21ca6846bd25f7bd2dabb157912e2e07226db76be32885bc53d7f27db98d08a"
)
