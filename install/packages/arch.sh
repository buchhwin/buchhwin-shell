# Packages for Arch Linux, sourced by install/bootstrap.sh after the
# distribution was detected (install/lib/distro.sh). Same names as
# install/packages/fedora.sh; every package below was looked up with
# `pacman -Si` in core and extra, except aur_packages.

# pacman needs nothing extra to install from its own repositories.
bootstrap_packages=()

# Everything is in extra - Hyprland, its portal and Quickshell included, the
# same versions Leap had to build (Hyprland 0.56.2, Quickshell 0.3.2) - so
# there is no repository to add. Brave is only in the AUR (below).
repos=()
brave_repofile=""

core=(hyprland quickshell xdg-desktop-portal-hyprland)

packages=(
  # terminal and prompt
  kitty zsh starship fastfetch
  # zsh/.zshrc sources both; Arch keeps them under /usr/share/zsh/plugins
  zsh-autosuggestions zsh-syntax-highlighting
  # the backends the shell drives; pw-metadata and pw-record are in pipewire
  brightnessctl wireplumber pipewire playerctl networkmanager
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep
  swaylock swayidle kdialog udisks2 wireguard-tools
  # checkupdates: the update check (scripts/updates-check.sh); it syncs its
  # copy of the database through fakeroot and stops without it, which
  # pacman-contrib does not pull in (base-devel does, not every system has it)
  pacman-contrib fakeroot
  # setpriv: the shell's long-running helpers die with it (--pdeathsig)
  util-linux
  # the helper scripts in scripts/ are Python
  python-dbus python-gobject python-pillow
  # KDE pieces the session reuses instead of carrying its own; kwallet-pam
  # opens the wallet at the SDDM login (scripts/session-init.sh hands it on)
  xdg-desktop-portal-kde polkit-kde-agent kwallet kwallet-pam
  # services/CalendarService.qml imports org.kde.akonadi, which merkuro
  # ships; without it the service fails to load and takes the shell with it,
  # as on Leap, so this is not an extra here either.
  merkuro
  # interface and monospace faces, and both Nerd Fonts: Arch packages them,
  # so the font step finds them and fetches nothing
  inter-font ttf-jetbrains-mono ttf-firacode-nerd ttf-jetbrains-mono-nerd
  fontconfig unzip
)

# Not here, compared with Fedora: the Akonadi Python bindings (not packaged),
# so Arch can show calendar events but not write them, as on Leap.
extras=(
  wf-recorder                 # screen recording
  fprintd                     # fingerprint on the lock screen
  kdeconnect                  # the phone page
  gvfs-mtp                    # phones in the drives list (scripts/drives.py)
  hyprland-guiutils           # Hyprland's own dialogs
  sddm                        # the login screen theme (the display manager is
                              # NOT switched); Arch's sddm is the Qt 6 build
  kdepim-addons
  cmatrix cava                # terminal extras that follow the shell accent
)

app_packages=(dolphin vlc okular gwenview ark)

# Not in Arch's repositories: installed with an AUR helper (paru or yay) when
# one is there, else named with the command. Kept out of --list-packages,
# which is what CI resolves against the repositories.
aur_packages=(brave-bin)

# Fetched rather than installed: nothing on Arch.
fetched_binaries=()
