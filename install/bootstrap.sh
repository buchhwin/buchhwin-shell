#!/usr/bin/env bash
# One command from a fresh Fedora, openSUSE Leap 16 or Arch Linux to a
# working buchhwin-shell session. The distribution is detected (install/lib/distro.sh)
# and decides the package manager and the list (install/packages/).
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
#   install/bootstrap.sh --distro NAME ...      fedora | opensuse-leap | arch instead
#                                               of the detected one (tests, CI)
#
# It is run as **you**, not as root. The user step installs into $HOME, and a
# $HOME owned by root is a worse problem than the one this solves; `sudo` is
# called for the steps that need it, so expect a password prompt.
#
# Re-running it is safe: dnf, zypper and pacman skip what is installed, the
# repositories are only added when missing, a default application is only
# set when the category has none, and a session that runs from the stable
# worktree scripts/deploy.sh keeps stays there. On openSUSE the package step
# first asks zypper what it would do and stops if that removes, downgrades or
# switches the vendor of anything already installed - this runs next to a
# working desktop. On Arch it first lets pacman resolve every name, then
# pacman asks itself.
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
    --distro) export BUCHHWIN_DISTRO=${2:?--distro needs a name}; shift 2 ;;
    -h|--help) sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# `--list-packages` prints and exits, so it is the one thing here that is safe
# as root - and a CI container is root. The check belongs to the run, not to
# the reading of the list.
if (( EUID == 0 )) && ! $list_packages; then
  printf 'Run this as yourself, not as root: the user step installs into $HOME.\n' >&2
  printf 'It calls sudo for the parts that need it.\n' >&2
  exit 2
fi

# shellcheck source=install/lib/distro.sh
. "$project_dir/install/lib/distro.sh"
distro=$(distro_detect) || exit 2
# bootstrap_packages, repos, brave_repofile, core, packages, extras,
# app_packages, fetched_binaries; aur_packages only on Arch
aur_packages=()
# shellcheck disable=SC1090
. "$project_dir/install/packages/$distro.sh"

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

# Nerd Fonts neither Fedora nor Leap packages (Arch does; its list installs
# them, and the font step below then finds them). family|archive|faces|directory:
# - "FiraCode Nerd Font Propo" is what the shell asks for by name
#   (theme/Typography.qml); without it every glyph in the interface is an
#   empty box, so this is not an extra.
# - "JetBrainsMono Nerd Font" is the terminal face (Settings > Terminal,
#   kitty/kitty.conf, terminal/alacritty.toml).
# Only the faces named are extracted: each archive holds a few hundred files.
nerd_fonts_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
fonts_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
nerd_fonts=(
  "FiraCode Nerd Font Propo|FiraCode.zip|*Propo*.ttf|FiraCode"
  "JetBrainsMono Nerd Font|JetBrainsMono.zip|JetBrainsMonoNerdFont-*.ttf|JetBrainsMono"
)

# Not a pipeline: `grep -q` exits at the first match, `fc-list` then dies of
# SIGPIPE, and with `set -o pipefail` the whole thing reports failure even
# though the font was found. The dry run claimed it had to download a font that
# was already installed.
font_present() {
  local list
  list=$(fc-list 2>/dev/null) || return 1
  grep -qi -- "$1" <<<"$list"
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

printf 'Distribution: %s\n' "$distro"

say '1. What the package manager needs for the next step'
if (( ${#bootstrap_packages[@]} )); then
  pkg_install "$distro" "${bootstrap_packages[@]}"
else
  printf '  nothing\n'
fi

say '2. Repositories'
for repo in "${repos[@]}"; do
  repo_add "$distro" "$repo"
done
if $apps && ! $minimal; then
  case $distro in
    fedora)
      if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then
        printf '  Brave: already configured\n'
      else
        run sudo dnf config-manager addrepo --from-repofile="$brave_repofile"
      fi ;;
    opensuse-leap) repo_add "$distro" "brave-browser|$brave_repofile|99" ;;
    arch) printf '  Brave: from the AUR, no repository (step 3b)\n' ;;
  esac
fi
repos_refresh "$distro"

say "3. Packages (${#to_install[@]} of them; already-installed ones are skipped)"
# pacman installs against the database it has; one that is days old asks for
# versions the mirrors no longer carry, and a refresh alone (-Sy) would be a
# partial upgrade. The system is brought up to date first, by you.
[[ $distro == arch ]] && printf '  (run sudo pacman -Syu first if the system was not updated today)\n'
if [[ $distro == opensuse-leap ]]; then
  # Only the repositories this list comes from: another one at the same
  # priority (X11:Wayland, on the machine this was written on) would otherwise
  # offer newer builds of libraries the desktop runs on.
  oss=$(leap_oss_alias)
  zypper_repo_args=(--repo "${oss:-repo-oss}")
  for repo in "${repos[@]}"; do zypper_repo_args+=(--repo "${repo%%|*}"); done
  if $apps && ! $minimal; then zypper_repo_args+=(--repo brave-browser); fi
  packman=$(leap_packman_alias)
  [[ -n $packman ]] && zypper_repo_args+=(--repo "$packman")
fi
pkg_install_safe "$distro" "${to_install[@]}"
zypper_repo_args=()
$minimal && printf '  (--minimal: recording, fingerprint, phone, calendar writing and the apps are left out)\n'

if (( ${#aur_packages[@]} )) && $apps && ! $minimal; then
  say '3b. From the AUR'
  aur_helper=""
  for candidate in paru yay; do
    command -v "$candidate" >/dev/null 2>&1 && { aur_helper=$candidate; break; }
  done
  for package in "${aur_packages[@]}"; do
    if pacman -Q "$package" >/dev/null 2>&1; then
      printf '  %s is already installed\n' "$package"
    elif [[ -n $aur_helper ]]; then
      # As you, not through sudo: an AUR helper builds as the user and asks
      # for sudo itself when it installs. A declined or failed build costs
      # that one package, not the steps after it (fonts, the shell, the
      # session entry), which set -e would otherwise skip.
      aur_status=0
      run "$aur_helper" -S --needed "$package" || aur_status=$?
      if (( aur_status )); then
        printf '  %s was not installed (%s exited %d); continuing\n' "$package" "$aur_helper" "$aur_status"
      fi
    else
      printf '  %s: no AUR helper (paru or yay) here; install it with one\n' "$package"
    fi
  done
fi

say '4. The fonts and the tools the distribution does not package'
for entry in "${nerd_fonts[@]}"; do
  IFS='|' read -r font_name archive faces font_subdir <<<"$entry"
  font_dir="$fonts_dir/$font_subdir"
  if ! $fonts; then
    printf '  %s: skipped (--skip-fonts)\n' "$font_name"
  elif font_present "$font_name"; then
    printf '  "%s" is already installed\n' "$font_name"
  elif $apply; then
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    printf '  + downloading %s/%s\n' "$nerd_fonts_url" "$archive"
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "$tmp/$archive" "$nerd_fonts_url/$archive"
    mkdir -p -- "$font_dir"
    unzip -o -j "$tmp/$archive" "$faces" -d "$font_dir" >/dev/null
    fc-cache -f "$font_dir" >/dev/null
    font_present "$font_name" || { printf '  "%s" did not register; look in %s\n' "$font_name" "$font_dir" >&2; exit 1; }
    printf '  + installed "%s" into %s\n' "$font_name" "$font_dir"
    rm -rf -- "$tmp"
  else
    printf '  "%s": download %s/%s\n' "$font_name" "$nerd_fonts_url" "$archive"
    printf '  extract the %s faces into %s and run fc-cache -f\n' "$faces" "$font_dir"
  fi
done

bin_dir="$HOME/.local/bin"
for entry in "${fetched_binaries[@]}"; do
  IFS='|' read -r binary url sum <<<"$entry"
  if command -v "$binary" >/dev/null 2>&1; then
    printf '  %s is already installed\n' "$binary"
  elif $apply; then
    tmp_bin=$(mktemp)
    printf '  + downloading %s\n' "$url"
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "$tmp_bin" "$url"
    if [[ $(sha256sum "$tmp_bin" | cut -d' ' -f1) != "$sum" ]]; then
      rm -f -- "$tmp_bin"
      printf '  %s does not match its checksum; not installed\n' "$binary" >&2
      exit 1
    fi
    install -Dm0755 "$tmp_bin" "$bin_dir/$binary"
    rm -f -- "$tmp_bin"
    printf '  + installed %s\n' "$bin_dir/$binary"
  else
    printf '  download %s into %s (sha256 %s)\n' "$binary" "$bin_dir" "${sum:0:12}..."
  fi
done

if [[ $distro == opensuse-leap ]]; then
  say '4b. Hyprland, built from source into your home directory'
  # Its own dry run when this is one, with its own zypper check for the
  # build dependencies when it is not.
  hyprland_args=()
  $apply && hyprland_args=(--apply)
  "$project_dir/install/build-hyprland-leap.sh" "${hyprland_args[@]}" \
    | sed '/^Dry run\./d; /^Nothing was changed\./d; s/^/  /'
fi

say '5. The shell itself, into your home directory'
run "$project_dir/install/install.sh" --apply

say '6. The session entry, the launcher wrapper and the lock PAM services'
# The distribution this run settled on, handed through: sudo starts with a
# clean environment, and system-install.sh would detect again without a
# --distro or BUCHHWIN_DISTRO given here (an Arch derivative then reads as
# nothing it knows).
run sudo env BUCHHWIN_DISTRO="$distro" "$project_dir/install/system-install.sh"

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
      # kitty's package registers kitty-open.desktop for inode/directory, and
      # without a choice of anyone's that system default wins over Dolphin
      # (mimeinfo.cache order): Super+E opened a terminal, on Leap and on Arch.
      # It is kitty's "open here" helper, not a file manager.
      [[ $category == files && $current == kitty-open.desktop ]] && current=""
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
