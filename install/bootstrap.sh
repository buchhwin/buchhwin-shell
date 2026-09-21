#!/usr/bin/env bash
# One command from a fresh Fedora to a working buchhwin-shell session.
#
# The other two installers assume the packages the shell talks to are already
# there; this one puts them there first and then calls them. It is the only
# script here that reaches the network, and it is deliberately the loudest: a
# dry run prints every command it would run, in order, before anything happens.
#
#   install/bootstrap.sh                 dry run (default)
#   install/bootstrap.sh --apply         do it
#   install/bootstrap.sh --apply --minimal      only what the shell needs
#   install/bootstrap.sh --apply --skip-fonts   leave fonts alone
#   install/bootstrap.sh --apply --skip-apps    no browser, no file manager
#   install/bootstrap.sh --list-packages        every package name, one per line
#
# It is run as **you**, not as root. The user step installs into $HOME, and a
# $HOME owned by root is a worse problem than the one this solves; `sudo` is
# called for the steps that need it, so expect a password prompt.
#
# Re-running it is safe: dnf skips what is installed, the repositories are only
# added when missing, and a default application is only set when the category
# has none.
set -euo pipefail

project_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
apply=false
minimal=false
fonts=true
apps=true
list_packages=false

while (( $# )); do
  case "$1" in
    --apply) apply=true; shift ;;
    --minimal) minimal=true; shift ;;
    --skip-fonts) fonts=false; shift ;;
    --skip-apps) apps=false; shift ;;
    --list-packages) list_packages=true; shift ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if (( EUID == 0 )); then
  printf 'Run this as yourself, not as root: the user step installs into $HOME.\n' >&2
  printf 'It calls sudo for the parts that need it.\n' >&2
  exit 2
fi

# `dnf copr` and `dnf config-manager` live here, and step 2 needs both - so
# this cannot wait until the package step or the installer fails on its own
# first command.
bootstrap_packages=(dnf5-plugins)

# Hyprland is not in Fedora's repositories; Quickshell is. Brave ships its own,
# because the native build is wanted rather than the Flatpak.
copr_repo="sachesi/hyprland"
brave_repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

core=(hyprland quickshell)

packages=(
  # terminal and prompt
  kitty zsh starship fastfetch
  # the backends the shell drives
  brightnessctl wireplumber pipewire-utils playerctl NetworkManager
  plocate jq curl grim slurp swappy wl-clipboard cliphist gammastep
  swaylock kdialog udisks2
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

# category:desktop-id, read off a working installation rather than guessed.
# Set through scripts/default-apps.py, which writes a session-local
# buchhwin-shell-mimeapps.list - Plasma's own defaults are untouched.
app_defaults=(
  "browser:brave-browser.desktop"
  "files:org.kde.dolphin.desktop"
  "terminal:kitty.desktop"
  "video:vlc.desktop"
  "music:vlc.desktop"
  "pdf:org.kde.okular.desktop"
  "images:org.kde.gwenview.desktop"
  "archives:org.kde.ark.desktop"
)

# The shell asks for "FiraCode Nerd Font Propo" by name (theme/Typography.qml).
# Fedora packages no Nerd Font at all, and without it every glyph in the
# interface is an empty box - so this is not an extra.
font_name="FiraCode Nerd Font Propo"
font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"
font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/FiraCode"

# Not a pipeline: `grep -q` exits at the first match, `fc-list` then dies of
# SIGPIPE, and with `set -o pipefail` the whole thing reports failure even
# though the font was found. The dry run claimed it had to download a font that
# was already installed.
font_present() {
  local list
  list=$(fc-list 2>/dev/null) || return 1
  grep -qi "$font_name" <<<"$list"
}

to_install=("${core[@]}" "${packages[@]}")
$minimal || to_install+=("${extras[@]}")
if $apps && ! $minimal; then to_install+=("${app_packages[@]}"); fi

# The list, for whoever wants to check it against the repositories without
# reading the script. Everything, regardless of --minimal and --skip-apps:
# the question "does this name exist" is about the name, not about this run.
if $list_packages; then
  printf '%s\n' "${bootstrap_packages[@]}" "${core[@]}" "${packages[@]}" \
    "${extras[@]}" "${app_packages[@]}"
  exit 0
fi

say() { printf '\n%s\n' "$1"; }
run() {
  if $apply; then
    printf '  + %s\n' "$*"
    "$@"
  else
    printf '  %s\n' "$*"
  fi
}

$apply || printf 'Dry run. These are the steps, in order:\n'

say '1. The dnf plugins the next step needs'
run sudo dnf -y install "${bootstrap_packages[@]}"

say '2. Repositories'
run sudo dnf -y copr enable "$copr_repo"
if $apps && ! $minimal; then
  if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then
    printf '  Brave: already configured\n'
  else
    run sudo dnf config-manager addrepo --from-repofile="$brave_repofile"
  fi
fi

say "3. Packages (${#to_install[@]} of them; already-installed ones are skipped)"
run sudo dnf -y install "${to_install[@]}"
$minimal && printf '  (--minimal: recording, fingerprint, phone, calendar writing and the apps are left out)\n'

say '4. The icon font, which Fedora does not package'
if ! $fonts; then
  printf '  skipped (--skip-fonts)\n'
elif font_present; then
  printf '  "%s" is already installed\n' "$font_name"
elif $apply; then
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' EXIT
  printf '  + downloading %s\n' "$font_url"
  curl -fsSL --retry 3 -o "$tmp/FiraCode.zip" "$font_url"
  mkdir -p -- "$font_dir"
  # Only the proportional faces: the archive holds a few hundred files and the
  # shell asks for one family.
  unzip -o -j "$tmp/FiraCode.zip" '*Propo*.ttf' -d "$font_dir" >/dev/null
  fc-cache -f "$font_dir" >/dev/null
  font_present || { printf '  the font did not register; look in %s\n' "$font_dir" >&2; exit 1; }
  printf '  + installed into %s\n' "$font_dir"
else
  printf '  download %s\n' "$font_url"
  printf '  extract the *Propo*.ttf faces into %s and run fc-cache -f\n' "$font_dir"
fi

say '5. The shell itself, into your home directory'
run "$project_dir/install/install.sh" --apply

say '6. The session entry, the launcher wrapper and the lock PAM services'
run sudo "$project_dir/install/system-install.sh"

say '7. Default applications for this session'
if ! $apps || $minimal; then
  printf '  skipped\n'
else
  defaults_tool="$project_dir/scripts/default-apps.py"
  for entry in "${app_defaults[@]}"; do
    category=${entry%%:*}
    desktop_id=${entry#*:}
    if $apply; then
      current=$("$defaults_tool" get "$category" 2>/dev/null || true)
      if [[ -n $current ]]; then
        printf '  %-9s keeps %s\n' "$category" "$current"
      else
        printf '  + %-9s %s\n' "$category" "$desktop_id"
        "$defaults_tool" set "$category" "$desktop_id" >/dev/null
      fi
    else
      printf '  %-9s %s (only if the category has none)\n' "$category" "$desktop_id"
    fi
  done
fi

if $apply; then
  printf '\nDone. Log out and choose **buchhwin-shell** from the session list.\n'
  printf 'Then, inside the session:  %s/scripts/session-check.sh\n' "$project_dir"
else
  printf '\nNothing was changed. Run %s --apply to continue.\n' "$0"
fi
