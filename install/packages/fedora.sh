# Packages for Fedora, sourced by install/bootstrap.sh after the distribution
# was detected (install/lib/distro.sh). install/packages/opensuse-leap.sh
# defines the same names for openSUSE Leap 16.

# `dnf copr` and `dnf config-manager` live here, and step 2 needs both - so
# this cannot wait until the package step or the installer fails on its own
# first command.
bootstrap_packages=(dnf5-plugins)

# Hyprland is not in Fedora's repositories; Quickshell is. Neither is Starship,
# which is the prompt Settings > Terminal configures - it was in this list from
# the start and only ever resolved because the machine it was written on had
# the Copr enabled already. A run against a fresh Fedora found it, which is
# what that check is for. Brave ships its own repository, because the native
# build is wanted rather than the Flatpak.
repos=(sachesi/hyprland atim/starship)
brave_repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

core=(hyprland quickshell)

packages=(
  # terminal and prompt; zsh/.zshrc sources both plugins when they are there
  kitty zsh starship fastfetch zsh-autosuggestions zsh-syntax-highlighting
  # the backends the shell drives
  brightnessctl wireplumber pipewire-utils playerctl NetworkManager
  # the alarm clock a timer rings with, and the notification sounds (pw-play)
  sound-theme-freedesktop
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep
  # xclip: reads what an X11 program (Citrix) copied, for the clipboard
  # bridge (scripts/x11-clipboard-bridge.py)
  xclip
  swaylock swayidle kdialog udisks2 wireguard-tools
  # the Bluetooth daemon
  bluez
  # nm-applet is the session's only NetworkManager secret agent - without it
  # no VPN or saved-secret password is asked for - and plasma-nm the dialog
  # an enterprise (802.1X) network is set up in (kcm_networkmanagement)
  network-manager-applet plasma-nm
  # WebP wallpapers (the picker offers them; Qt reads them through this),
  # the Notification portal the session's portals.conf names (gtk), and the
  # user directories the wallpaper folder and the start menu's places use
  qt6-qtimageformats xdg-desktop-portal-gtk xdg-user-dirs
  # setpriv: the shell's long-running helpers die with it (--pdeathsig).
  # util-linux requires util-linux-core, so setpriv is there whichever of the
  # two carries it on this release.
  util-linux
  # the helper scripts in scripts/ are Python
  python3-dbus python3-gobject python3-pillow
  # KDE pieces the session reuses instead of carrying its own
  xdg-desktop-portal-kde polkit-kde kf6-kwallet
  # services/CalendarService.qml imports org.kde.akonadi (akonadi-server
  # ships it) and org.kde.plasma.PimCalendars (kdepim-addons); without either
  # the service fails to load and takes the shell with it, so neither is an
  # extra: nothing else here pulls them in, and --minimal left both out.
  # merkuro is where the shell sends you to set calendars up (Settings >
  # Calendar, "Open in Merkuro").
  akonadi-server kdepim-addons merkuro
  # what the font step itself needs: fc-cache/fc-list and an unpacker.
  # bsdtar is not on every Fedora, unzip is the fallback that must exist.
  fontconfig unzip
)

# Interface and monospace faces and the emoji the picker draws; the icon
# font is fetched (bootstrap.sh, step 4). --skip-fonts leaves these out.
font_packages=(rsms-inter-fonts jetbrains-mono-fonts google-noto-color-emoji-fonts)

# Features that fail quietly rather than loudly when they are missing: the
# recording key does nothing, the fingerprint page has nothing to enrol, the
# phone page stays empty. Installed by default because "everything works" is
# the point; --minimal leaves them out.
extras=(
  wf-recorder                 # screen recording
  fprintd                     # fingerprint on the lock screen
  kde-connect                 # the phone page
  hyprland-guiutils           # Hyprland's own dialogs
  sddm                        # the login screen theme (the display manager is
                              # NOT switched; system-install.sh --use-sddm does
                              # that, on purpose and separately)
  python3-kf6-kcoreaddons python3-kf6-kcalendarcore  # writing calendar events
  cmatrix cava                # terminal extras that follow the shell accent
)

# Without these, Super+B and Super+E point at nothing on a fresh system.
# Brave is native, from Brave's own repository, not a Flatpak.
app_packages=(brave-browser dolphin vlc okular gwenview ark)

# Fetched rather than installed: nothing on Fedora.
fetched_binaries=()
