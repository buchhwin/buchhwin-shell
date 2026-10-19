#!/usr/bin/env bash
set -euo pipefail

# Give Plasma the same terminal experience as the buchhwin sessions: Kitty as
# default terminal (Ctrl+Alt+T), Zsh with Fastfetch, Starship, autosuggestions
# and syntax highlighting (where the distribution packages the two plugins;
# Leap's repo-oss does not), plus a matching Alacritty profile.
# Dry run by default; --apply writes. Existing files are moved to backups.
#
# A file that is a symlink, or lies in a directory that is one, is kept: that
# is a dotfiles checkout (stow and the like), and replacing the link - or
# writing through a linked directory - changed the checkout instead of this
# machine. The same holds for the two KDE files kwriteconfig6 writes. --force
# replaces and writes them anyway.
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
apply=false
force=false
for arg in "$@"; do
  case $arg in
    --apply) apply=true ;;
    --force) force=true ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

files=(
  "$project_dir/zsh/plasma.zshrc:$HOME/.zshrc"
  "$project_dir/zsh/starship.toml:$config_home/starship.toml"
  "$project_dir/terminal/kitty-plasma.conf:$config_home/kitty/kitty.conf"
  "$project_dir/terminal/colors-dark.conf:$config_home/kitty/buchhwin-colors.conf"
  "$project_dir/terminal/alacritty.toml:$config_home/alacritty/alacritty.toml"
)
kde_files=("$config_home/kdeglobals" "$config_home/kglobalshortcutsrc")

# linked_to PATH: where PATH really is when it, or a directory between it and
# the home directory, is a symlink; nothing otherwise. The home directory
# itself may be a link (/home is one on some systems), and that is no
# dotfiles checkout.
home=${HOME%/}
linked_to() {
  local path=$1 dir=$1
  while [[ -n $dir && $dir != "$home" && $dir != / && $dir != . ]]; do
    if [[ -L $dir ]]; then
      readlink -f -- "$path" 2>/dev/null || readlink -- "$dir"
      return 0
    fi
    dir=$(dirname -- "$dir")
  done
}

# kept PATH: true (and says so) when PATH is a link that --force did not
# override.
kept() {
  local target
  target=$(linked_to "$1")
  [[ -n $target ]] && ! $force || return 1
  printf '  %-8s %s (symlink to %s; --force replaces it)\n' kept "$1" "$target"
}

if ! $apply; then
  printf 'Dry run. These files would be installed (existing ones backed up):\n'
  for entry in "${files[@]}"; do
    target=${entry#*:}
    kept "$target" && continue
    state=new; [[ -e $target || -L $target ]] && state=replace
    printf '  %-8s %s\n' "$state" "$target"
  done
  kde_kept=false
  for kde_file in "${kde_files[@]}"; do kept "$kde_file" && kde_kept=true; done
  if $kde_kept; then
    printf 'Plasma'"'"'s default terminal would stay as it is (a KDE file above is a link).\n'
  else
    printf 'Plasma default terminal and Ctrl+Alt+T would switch to Kitty.\n'
  fi
  printf 'Run %s --apply to continue.\n' "$0"
  exit 0
fi

timestamp=$(date +%Y%m%d-%H%M%S)
for entry in "${files[@]}"; do
  source_path=${entry%%:*}
  target=${entry#*:}
  kept "$target" && continue
  mkdir -p -- "$(dirname -- "$target")"
  if [[ -e $target ]] && cmp -s "$source_path" "$target"; then
    printf 'Unchanged %s\n' "$target"
    continue
  fi
  if [[ -e $target || -L $target ]]; then
    mv -- "$target" "$target.backup-$timestamp"
    printf 'Backed up %s\n' "$target"
  fi
  install -m644 -- "$source_path" "$target"
  printf 'Installed %s\n' "$target"
done

# Fastfetch reads ~/.config/fastfetch/config.jsonc automatically; keep an
# existing one and otherwise reuse the buchhwin session copy.
if [[ ! -e "$config_home/fastfetch/config.jsonc" && -r "$config_home/buchhwin-shell/fastfetch.jsonc" ]] \
    && ! kept "$config_home/fastfetch/config.jsonc"; then
  install -D -m600 -- "$config_home/buchhwin-shell/fastfetch.jsonc" "$config_home/fastfetch/config.jsonc"
  printf 'Installed %s\n' "$config_home/fastfetch/config.jsonc"
fi

# kwriteconfig6 writes through a link into whatever it points at; with
# either file linked, Plasma's terminal stays as it is.
kde_kept=false
for kde_file in "${kde_files[@]}"; do kept "$kde_file" && kde_kept=true; done
if $kde_kept; then
  printf 'Plasma'"'"'s default terminal was left as it is (a KDE file above is a link).\n'
  exit 0
fi
kwriteconfig6 --file kdeglobals --group General --key TerminalApplication kitty
kwriteconfig6 --file kdeglobals --group General --key TerminalService kitty.desktop
kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.konsole.desktop --key _launch none
kwriteconfig6 --file kglobalshortcutsrc --group services --group kitty.desktop --key _launch "Ctrl+Alt+T"
printf 'Plasma default terminal set to Kitty (Ctrl+Alt+T after the next login).\n'
