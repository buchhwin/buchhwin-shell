#!/usr/bin/env bash
set -euo pipefail

# Give Plasma the same terminal experience as the buchhwin sessions: Kitty as
# default terminal (Ctrl+Alt+T), Zsh with Fastfetch, Starship, autosuggestions
# and syntax highlighting, plus a matching Alacritty profile.
# Dry run by default; --apply writes. Existing files are moved to backups.
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
apply=false
[[ ${1:-} == "--apply" ]] && apply=true

files=(
  "$project_dir/zsh/plasma.zshrc:$HOME/.zshrc"
  "$project_dir/zsh/starship.toml:$config_home/starship.toml"
  "$project_dir/terminal/kitty-plasma.conf:$config_home/kitty/kitty.conf"
  "$project_dir/terminal/colors-dark.conf:$config_home/kitty/buchhwin-colors.conf"
  "$project_dir/terminal/alacritty.toml:$config_home/alacritty/alacritty.toml"
)

if ! $apply; then
  printf 'Dry run. These files would be installed (existing ones backed up):\n'
  for entry in "${files[@]}"; do
    target=${entry#*:}
    state=new; [[ -e $target ]] && state=replace
    printf '  %-8s %s\n' "$state" "$target"
  done
  printf 'Plasma default terminal and Ctrl+Alt+T would switch to Kitty.\n'
  printf 'Run %s --apply to continue.\n' "$0"
  exit 0
fi

timestamp=$(date +%Y%m%d-%H%M%S)
for entry in "${files[@]}"; do
  source_path=${entry%%:*}
  target=${entry#*:}
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
if [[ ! -e "$config_home/fastfetch/config.jsonc" && -r "$config_home/buchhwin-shell/fastfetch.jsonc" ]]; then
  install -D -m600 -- "$config_home/buchhwin-shell/fastfetch.jsonc" "$config_home/fastfetch/config.jsonc"
  printf 'Installed %s\n' "$config_home/fastfetch/config.jsonc"
fi

kwriteconfig6 --file kdeglobals --group General --key TerminalApplication kitty
kwriteconfig6 --file kdeglobals --group General --key TerminalService kitty.desktop
kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.konsole.desktop --key _launch none
kwriteconfig6 --file kglobalshortcutsrc --group services --group kitty.desktop --key _launch "Ctrl+Alt+T"
printf 'Plasma default terminal set to Kitty (Ctrl+Alt+T after the next login).\n'
