#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
apply=false
[[ ${1:-} == "--apply" ]] && apply=true

links=(
  "$project_dir:$HOME/.local/share/buchhwin-shell"
  "$project_dir/session/buchhwin-shell-session:$HOME/.local/bin/buchhwin-shell-session"
  "$project_dir/scripts/buchhwin:$HOME/.local/bin/buchhwin"
  "$project_dir/shell-completion/_buchhwin:$HOME/.local/share/zsh/site-functions/_buchhwin"
  "$project_dir/zsh/buchhwin.zsh:$HOME/.config/buchhwin-shell/shell.zsh"
  "$project_dir/systemd/buchhwin-shell-session.target:$HOME/.config/systemd/user/buchhwin-shell-session.target"
  "$project_dir/systemd/buchhwin-shell-autostart.target:$HOME/.config/systemd/user/buchhwin-shell-autostart.target"
  "$project_dir/session/xdg-desktop-portal/buchhwin-shell-portals.conf:$HOME/.config/xdg-desktop-portal/buchhwin-shell-portals.conf"
)

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
fastfetch_source="$config_home/buchhwin-dwl/fastfetch.jsonc"
fastfetch_target="$config_home/buchhwin-shell/fastfetch.jsonc"

if ! $apply; then
  printf 'Dry run. The following links would be installed:\n'
  for entry in "${links[@]}"; do
    printf '  %s -> %s\n' "${entry#*:}" "${entry%%:*}"
  done
  if [[ -r "$fastfetch_source" && ! -e "$fastfetch_target" ]]; then
    printf 'The Fastfetch configuration would be copied once:\n  %s -> %s\n' \
      "$fastfetch_source" "$fastfetch_target"
  fi
  printf 'Run %s --apply to continue.\n' "$0"
  exit 0
fi

timestamp=$(date +%Y%m%d-%H%M%S)
for entry in "${links[@]}"; do
  source_path=${entry%%:*}
  target_path=${entry#*:}
  mkdir -p -- "$(dirname -- "$target_path")"
  # Both sides resolved: project_dir is physical, so a link that already points
  # at this checkout is recognised even when the script was started through it.
  if [[ -L "$target_path" && $(readlink -f -- "$target_path") == "$source_path" ]]; then
    printf 'Already installed %s\n' "$target_path"
    continue
  fi
  # A link to itself is never what was meant: the working link would already be
  # a backup by then and the session would have no shell at the next login.
  if [[ "$target_path" == "$source_path" ]]; then
    printf 'Refusing to link %s onto itself.\n' "$target_path" >&2
    exit 1
  fi
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    backup_path="$target_path.backup-$timestamp"
    printf 'Backing up %s to %s\n' "$target_path" "$backup_path"
    mv -- "$target_path" "$backup_path"
  fi
  ln -s -- "$source_path" "$target_path"
  printf 'Installed %s\n' "$target_path"
done

systemctl --user daemon-reload

# The completion only loads when zsh looks in the user's site-functions. Say so
# instead of editing the user's .zshrc.
# The wrappers reach a personal .zshrc only when it sources the fragment.
if [[ -r "$HOME/.zshrc" ]] && ! grep -q 'buchhwin-shell/shell.zsh' "$HOME/.zshrc"; then
  printf 'For fastfetch, cmatrix and cava in the shell accent, add this line to ~/.zshrc:\n  source ~/.config/buchhwin-shell/shell.zsh\n'
fi

completion_dir="$HOME/.local/share/zsh/site-functions"
if ! zsh -c "print -l \$fpath" 2>/dev/null | grep -qx -- "$completion_dir"; then
  printf 'For "buchhwin" completion, add this line to ~/.zshrc before compinit:\n  fpath=(%s $fpath)\n' \
    "$completion_dir"
fi

mkdir -p -- "$HOME/.config/buchhwin-shell"
if [[ ! -e "$HOME/.config/buchhwin-shell/layout.json" ]]; then
  printf '{\n  "configVersion": 1,\n  "monitors": {}\n}\n' \
    > "$HOME/.config/buchhwin-shell/layout.json"
  printf 'Created %s\n' "$HOME/.config/buchhwin-shell/layout.json"
fi

# Reuse the Fedora dwl session's Fastfetch look as an independent copy. The
# source is only read, and an existing session copy is never replaced.
if [[ -e "$fastfetch_target" ]]; then
  printf 'Kept existing %s\n' "$fastfetch_target"
elif [[ -r "$fastfetch_source" ]]; then
  mkdir -p -- "$(dirname -- "$fastfetch_target")"
  install -m600 -- "$fastfetch_source" "$fastfetch_target"
  printf 'Copied Fastfetch configuration to %s\n' "$fastfetch_target"
else
  printf 'No dwl Fastfetch configuration found; Fastfetch uses its defaults.\n'
fi

printf 'Global Kitty settings were not changed; the session uses %s directly.\n' "$project_dir/kitty/kitty.conf"
printf 'Install the SDDM entry separately with: sudo %s/install/system-install.sh\n' "$project_dir"
