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
  # terminal and prompt
  kitty zsh starship fastfetch
  # the backends the shell drives
  brightnessctl wireplumber pipewire-utils playerctl NetworkManager
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep
  # xclip: reads what an X11 program (Citrix) copied, for the clipboard
  # bridge (scripts/x11-clipboard-bridge.py)
  xclip
  swaylock swayidle kdialog udisks2 wireguard-tools
  # setpriv: the shell's long-running helpers die with it (--pdeathsig).
  # util-linux requires util-linux-core, so setpriv is there whichever of the
  # two carries it on this release.
  util-linux
  # the helper scripts in scripts/ are Python
  python3-dbus python3-gobject python3-pillow
  # KDE pieces the session reuses instead of carrying its own
  xdg-desktop-portal-kde polkit-kde kf6-kwallet
  # interface and monospace faces; the icon font is fetched below
  rsms-inter-fonts jetbrains-mono-fonts
  # what the font step itself needs: fc-cache/fc-list and an unpacker.
  # bsdtar is not on every Fedora, unzip is the fallback that must exist.
  fontconfig unzip
)

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
  merkuro kdepim-addons python3-kf6-kcoreaddons python3-kf6-kcalendarcore
  cmatrix cava                # terminal extras that follow the shell accent
)

# Without these, Super+B and Super+E point at nothing on a fresh system.
# Brave is native, from Brave's own repository, not a Flatpak.
app_packages=(brave-browser dolphin vlc okular gwenview ark)

# Fetched rather than installed: nothing on Fedora.
fetched_binaries=()
