#!/usr/bin/env bash
set -euo pipefail

# install/install.sh [--apply] [--relink]
project_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
apply=false
relink=false
[[ ${BUCHHWIN_RELINK:-0} == 1 ]] && relink=true
for arg in "$@"; do
  case $arg in
    --apply) apply=true ;;
    --relink) relink=true ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
session_link="$HOME/.local/share/buchhwin-shell"

# The session may run from the stable worktree scripts/deploy.sh keeps (a
# worktree of this same repository, on branch `stable`), so that edits reach
# the desktop only through a deploy. Run from the development checkout - the
# README's update line, or bootstrap.sh again to add a package - this used to
# back that link up and point the session at the half-edited files of main
# at its next start. The links now go where the session already runs from,
# and the run says so; --relink (or BUCHHWIN_RELINK=1) moves the session to
# this checkout on purpose, which is the way back from a deploy setup.
# deploy.sh --init runs the stable worktree's own copy of this script, so
# its link from the development checkout to the stable one is made as before.
link_dir=$project_dir
if ! $relink && [[ -L $session_link ]] && command -v git >/dev/null 2>&1; then
  current=$(readlink -f -- "$session_link" 2>/dev/null) || current=""
  if [[ -n $current && $current != "$project_dir" && -d $current ]]; then
    here_common=$(git -C "$project_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || here_common=""
    there_common=$(git -C "$current" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || there_common=""
    there_top=$(git -C "$current" rev-parse --show-toplevel 2>/dev/null) || there_top=""
    there_branch=$(git -C "$current" symbolic-ref --short -q HEAD 2>/dev/null) || there_branch=""
    if [[ -n $here_common && $here_common == "$there_common" && $there_top == "$current" && $there_branch == stable ]]; then
      link_dir=$current
      printf 'The session runs from the stable worktree %s; the links stay with it.\n' "$link_dir"
      printf 'Changes reach it through scripts/deploy.sh. To run the session from %s instead: %s --apply --relink\n' \
        "$project_dir" "$0"
    fi
  fi
fi

# What systemd, xdg-desktop-portal and the shell itself (services/Paths.qml)
# read lives under XDG_CONFIG_HOME, and zsh's site-functions under
# XDG_DATA_HOME, so the links go where those look. Two paths stay literal on
# purpose: ~/.local/bin is where the session entry and PATH expect the
# launchers, and ~/.local/share/buchhwin-shell is the name the session entry,
# the systemd targets, hypr/ and every script use for the running copy.
links=(
  "$link_dir:$session_link"
  "$link_dir/session/buchhwin-shell-session:$HOME/.local/bin/buchhwin-shell-session"
  "$link_dir/scripts/buchhwin:$HOME/.local/bin/buchhwin"
  "$link_dir/shell-completion/_buchhwin:$data_home/zsh/site-functions/_buchhwin"
  "$link_dir/zsh/buchhwin.zsh:$config_home/buchhwin-shell/shell.zsh"
  "$link_dir/systemd/buchhwin-shell-session.target:$config_home/systemd/user/buchhwin-shell-session.target"
  "$link_dir/systemd/buchhwin-shell-autostart.target:$config_home/systemd/user/buchhwin-shell-autostart.target"
  "$link_dir/session/xdg-desktop-portal/buchhwin-shell-portals.conf:$config_home/xdg-desktop-portal/buchhwin-shell-portals.conf"
)
# The XDG autostart entries the session keeps out (scripts/lib/autostart-skip.sh)
# get a drop-in each (systemd/autostart-skip.conf): skipped while
# XDG_CURRENT_DESKTOP names buchhwin-shell, run as before in Plasma. The login
# then masks nothing, which made the user manager reload before the autostart
# apps could start (session-init.sh masks only an entry without one).
if [[ -r $link_dir/scripts/lib/autostart-skip.sh ]] && command -v systemd-escape >/dev/null 2>&1; then
  # shellcheck source=../scripts/lib/autostart-skip.sh
  source "$link_dir/scripts/lib/autostart-skip.sh"
  while IFS= read -r unit; do
    [[ $unit == app-?*@autostart.service ]] || continue
    links+=("$link_dir/systemd/autostart-skip.conf:$config_home/systemd/user/$unit.d/buchhwin-shell.conf")
  done < <(autostart_skip_units)
fi

fastfetch_source="$config_home/buchhwin-dwl/fastfetch.jsonc"
fastfetch_target="$config_home/buchhwin-shell/fastfetch.jsonc"
# What a machine without a dwl configuration gets. Shipped rather than copied,
# so a fresh install has the greeting the session was designed around instead
# of Fastfetch's own defaults - `zsh/buchhwin.zsh` only passes --config when
# this file exists, so without it nothing here applies at all.
fastfetch_default="$link_dir/config/fastfetch.jsonc"

if ! $apply; then
  printf 'Dry run. The following links would be installed:\n'
  for entry in "${links[@]}"; do
    printf '  %s -> %s\n' "${entry#*:}" "${entry%%:*}"
  done
  if [[ ! -e "$fastfetch_target" ]]; then
    if [[ -r "$fastfetch_source" ]]; then
      printf 'The Fastfetch configuration would be copied once:\n  %s -> %s\n' \
        "$fastfetch_source" "$fastfetch_target"
    else
      printf 'The shipped Fastfetch configuration would be installed:\n  %s -> %s\n' \
        "$fastfetch_default" "$fastfetch_target"
    fi
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

# Without a user manager to talk to (su or sudo -iu from another login, a
# container) the links are all there is to do: systemd reads the targets at
# the next login. Under set -e a failing reload ended the run here, before
# layout.json and the Fastfetch configuration - and the bootstrap with it.
systemctl --user daemon-reload 2>/dev/null \
  || printf 'Note: no user manager reachable; the targets load at the next login.\n'

# The completion only loads when zsh looks in the user's site-functions. Say so
# instead of editing the user's .zshrc.
# The wrappers reach a personal .zshrc only when it sources the fragment.
if [[ -r "$HOME/.zshrc" ]] && ! grep -q 'buchhwin-shell/shell.zsh' "$HOME/.zshrc"; then
  printf 'For fastfetch, cmatrix and cava in the shell accent, add this line to ~/.zshrc:\n  source %s\n' \
    "$config_home/buchhwin-shell/shell.zsh"
fi

completion_dir="$data_home/zsh/site-functions"
zsh_fpath=$(zsh -c "print -l \$fpath" 2>/dev/null) || zsh_fpath=""
if ! grep -qx -- "$completion_dir" <<<"$zsh_fpath"; then
  printf 'For "buchhwin" completion, add this line to ~/.zshrc before compinit:\n  fpath=(%s $fpath)\n' \
    "$completion_dir"
fi

mkdir -p -- "$config_home/buchhwin-shell"
if [[ ! -e "$config_home/buchhwin-shell/layout.json" ]]; then
  printf '{\n  "configVersion": 1,\n  "monitors": {}\n}\n' \
    > "$config_home/buchhwin-shell/layout.json"
  printf 'Created %s\n' "$config_home/buchhwin-shell/layout.json"
fi

# Reuse the Fedora dwl session's Fastfetch look as an independent copy. The
# source is only read, and an existing session copy is never replaced.
if [[ -e "$fastfetch_target" ]]; then
  printf 'Kept existing %s\n' "$fastfetch_target"
elif [[ -r "$fastfetch_source" ]]; then
  mkdir -p -- "$(dirname -- "$fastfetch_target")"
  install -m600 -- "$fastfetch_source" "$fastfetch_target"
  printf 'Copied Fastfetch configuration to %s\n' "$fastfetch_target"
elif [[ -r "$fastfetch_default" ]]; then
  mkdir -p -- "$(dirname -- "$fastfetch_target")"
  install -m600 -- "$fastfetch_default" "$fastfetch_target"
  printf 'Installed the shipped Fastfetch configuration at %s\n' "$fastfetch_target"
else
  printf 'No Fastfetch configuration found; Fastfetch uses its defaults.\n'
fi

printf 'Global Kitty settings were not changed; the session uses %s directly.\n' "$link_dir/kitty/kitty.conf"
printf 'Install the SDDM entry separately with: sudo %s/install/system-install.sh\n' "$project_dir"
