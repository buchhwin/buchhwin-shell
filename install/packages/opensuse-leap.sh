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
repos=(
  "quickshell-leap16|https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/16.0/|120"
)
brave_repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

# Hyprland and its portal: built, not installed (see above).
core=(quickshell)

packages=(
  # terminal and prompt
  kitty zsh starship fastfetch
  # the backends the shell drives
  brightnessctl wireplumber pipewire-tools playerctl NetworkManager
  plocate jq curl grim slurp swappy wl-clipboard gammastep
  swaylock swayidle kdialog udisks2 wireguard-tools
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
  # interface and monospace faces; the icon font is fetched below
  inter-variable-fonts jetbrains-mono-fonts
  fontconfig unzip
)

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
