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
  # the backends the shell drives; pw-metadata is in pipewire, pw-record (the
  # level meter in Settings > Audio) in pipewire-audio, which also carries
  # the ALSA devices WirePlumber finds the sound cards through - without it a
  # system that never had Plasma has an empty volume panel
  brightnessctl wireplumber pipewire pipewire-audio playerctl networkmanager
  # the alarm clock a timer rings with, and the notification sounds (pw-play)
  sound-theme-freedesktop
  # PulseAudio clients (Brave, VLC) through PipeWire. Asked for as what it
  # provides (arch_provided_by below), so a system that runs PulseAudio
  # itself keeps it: the two conflict, and pacman would offer to remove it.
  pipewire-pulse
  # realtime priority for PipeWire's audio threads (D-Bus activated, nothing
  # to enable): without it PipeWire and WirePlumber log "RTKit error:
  # org.freedesktop.DBus.Error.ServiceUnknown" and run at normal priority
  rtkit
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep
  # xclip: reads what an X11 program (Citrix) copied, for the clipboard
  # bridge (scripts/x11-clipboard-bridge.py)
  xclip
  swaylock swayidle kdialog udisks2 wireguard-tools
  # the Bluetooth daemon (Arch does not enable it: sudo systemctl enable
  # --now bluetooth) and the power profiles behind the profile controls,
  # which tuned-ppd provides as well; a system with it keeps it
  bluez power-profiles-daemon
  # nm-applet is the session's only NetworkManager secret agent - without it
  # no VPN or saved-secret password is asked for - and plasma-nm the dialog
  # an enterprise (802.1X) network is set up in (kcm_networkmanagement)
  network-manager-applet plasma-nm
  # WebP wallpapers (the picker offers them; Qt reads them through this),
  # the Notification portal the session's portals.conf names (gtk), and the
  # user directories the wallpaper folder and the start menu's places use
  qt6-imageformats xdg-desktop-portal-gtk xdg-user-dirs
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
  # services/CalendarService.qml imports org.kde.akonadi (akonadi, which
  # merkuro pulls in) and org.kde.plasma.PimCalendars (kdepim-addons, which
  # nothing here depends on); without either the service fails to load and
  # takes the shell with it, as on Leap, so neither is an extra here.
  merkuro kdepim-addons
  # what the font step itself needs: fc-cache/fc-list and an unpacker
  fontconfig unzip
)

# Interface and monospace faces, both Nerd Fonts and the emoji the picker
# draws: Arch packages them all, so the font step finds the Nerd Fonts and
# fetches nothing. --skip-fonts leaves these out.
font_packages=(inter-font ttf-jetbrains-mono ttf-firacode-nerd ttf-jetbrains-mono-nerd noto-fonts-emoji)

# Asked for as the name after the bar: installed only when no installed
# package provides that already (install/lib/distro.sh, arch_needed).
# NAME|DEPENDENCY
arch_provided_by=("pipewire-pulse|pulse-native-provider")

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
  cmatrix cava                # terminal extras that follow the shell accent
)

app_packages=(dolphin vlc okular gwenview ark)

# Not in Arch's repositories: installed with an AUR helper (paru or yay) when
# one is there, else named with the command. Kept out of --list-packages,
# which is what CI resolves against the repositories.
aur_packages=(brave-bin)

# Fetched rather than installed: nothing on Arch.
fetched_binaries=()
