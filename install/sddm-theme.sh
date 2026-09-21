#!/usr/bin/env bash
set -euo pipefail

# Installs or removes the buchhwin SDDM login theme (session/sddm/buchhwin).
# Called by install/system-install.sh --sddm-theme / --sddm-theme-remove.
#
#   sddm-theme.sh install [--wallpaper PATH] [--settings FILE] [--avatar PATH]
#                         [--user NAME] [--use-sddm] [--root DIR]
#   sddm-theme.sh remove [--root DIR]
#
# install copies the theme to /usr/share/sddm/themes/buchhwin, copies the
# wallpaper into it (SDDM runs as its own user and cannot read home
# directories), writes /etc/sddm.conf.d/buchhwin-theme.conf and comments out
# other [Theme] Current= lines after backing their files up. Without
# --wallpaper it uses wallpaper.path from the user's buchhwin-shell
# settings.json (the sudo user), else the bundled gradient. --use-sddm makes
# SDDM the display manager at the next boot (Fedora 44 ships Plasma Login
# Manager). remove restores the backups and the previous display manager.
# --root DIR works below DIR without systemctl (tests); otherwise root is needed.

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
theme_source="$project_dir/session/sddm/buchhwin"

action=${1:-}
[[ $action == install || $action == remove ]] || {
  printf 'Usage: %s install|remove [options]\n' "$0" >&2
  exit 2
}
shift

root=""
wallpaper=""
settings=""
avatar=""
user=${SUDO_USER:-}
use_sddm=false
while (( $# )); do
  case "$1" in
    --wallpaper) wallpaper=${2:?--wallpaper needs a path}; shift 2 ;;
    --settings) settings=${2:?--settings needs a file}; shift 2 ;;
    --avatar) avatar=${2:?--avatar needs a path}; shift 2 ;;
    --user) user=${2:?--user needs a name}; shift 2 ;;
    --use-sddm) use_sddm=true; shift ;;
    --root) root=${2:?--root needs a directory}; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z $root ]] && (( EUID != 0 )); then
  printf 'Run this step as root: sudo %s/install/system-install.sh --sddm-theme\n' "$project_dir" >&2
  exit 1
fi

theme_dir="$root/usr/share/sddm/themes/buchhwin"
conf_dir="$root/etc/sddm.conf.d"
conf_file="$conf_dir/buchhwin-theme.conf"
state_dir="$root/var/lib/buchhwin-shell/sddm-theme"
faces_dir="$root/usr/share/sddm/faces"
marker='# buchhwin-shell theme:'

# Files that may set [Theme] Current= besides ours (later files win in SDDM).
other_configs() {
  local file
  for file in "$root/etc/sddm.conf" "$conf_dir"/*.conf; do
    [[ -f $file && $file != "$conf_file" ]] && printf '%s\n' "$file"
  done
  return 0
}

# Prints an active Current= line inside a [Theme] section, if any.
theme_current() {
  awk '/^[[:space:]]*\[/ { section = $0; gsub(/[[:space:]]/, "", section) }
       section == "[Theme]" && /^[[:space:]]*Current[[:space:]]*=/ { print; found = 1 }
       END { exit !found }' "$1"
}

active_display_manager() {
  local link="$root/etc/systemd/system/display-manager.service"
  [[ -L $link ]] && basename -- "$(readlink -- "$link")" || true
}

run_systemctl() {
  if [[ -n $root ]]; then
    printf 'Would run: systemctl %s\n' "$*"
  else
    systemctl "$@"
  fi
}

install_theme() {
  [[ -r $theme_source/Main.qml ]] || { printf 'Theme sources missing: %s\n' "$theme_source" >&2; exit 1; }

  # Default wallpaper: the user's buchhwin-shell choice.
  if [[ -z $wallpaper ]]; then
    local home=""
    if [[ -z $settings && -n $user ]]; then
      home=$(getent passwd "$user" | cut -d: -f6 || true)
      [[ -n $home ]] && settings="$home/.config/buchhwin-shell/settings.json"
    fi
    if [[ -n $settings && -r $settings ]]; then
      [[ -z $home ]] && home=$(dirname -- "$(dirname -- "$(dirname -- "$settings")")")
      wallpaper=$(jq -r '.wallpaper.path // empty' "$settings" 2>/dev/null || true)
      [[ $wallpaper == "~/"* ]] && wallpaper="$home/${wallpaper#\~/}"
    fi
    if [[ -n $wallpaper && ! -r $wallpaper ]]; then
      printf 'Configured wallpaper not readable, using the bundled gradient: %s\n' "$wallpaper"
      wallpaper=""
    fi
  elif [[ ! -r $wallpaper ]]; then
    printf 'Wallpaper not readable: %s\n' "$wallpaper" >&2
    exit 1
  fi

  local extension=""
  if [[ -n $wallpaper ]]; then
    extension=${wallpaper##*.}
    extension=${extension,,}
    case "$extension" in
      jpg|jpeg|png|webp|avif|jxl|bmp|svg) ;;
      *) printf 'Unsupported wallpaper format: %s\n' "$wallpaper" >&2; exit 1 ;;
    esac
  fi

  mkdir -p -- "$theme_dir"
  # Replace the theme files but keep nothing stale from older versions.
  find "$theme_dir" -mindepth 1 -delete
  cp -r -- "$theme_source"/. "$theme_dir"/
  chmod -R u=rwX,go=rX -- "$theme_dir"

  # theme.conf.user carries everything the login screen may differ in. The
  # values come from the user's own settings (Settings > Login Screen), which
  # this script already reads for the wallpaper - the greeter runs as another
  # user and cannot read them itself.
  local user_conf="$theme_dir/theme.conf.user"
  printf '[General]\n' > "$user_conf"
  if [[ -n $wallpaper ]]; then
    install -m0644 -- "$wallpaper" "$theme_dir/background.$extension"
    printf 'background=background.%s\n' "$extension" >> "$user_conf"
    printf 'Copied wallpaper %s\n' "$wallpaper"
  else
    printf 'Using the bundled gradient as background.\n'
  fi
  if [[ -n $settings && -r $settings ]]; then
    local blur accent font date_format shell_accent shell_font
    # `// empty` would swallow a real `false`, because jq's alternative
    # operator treats false like null.
    blur=$(jq -r 'if .login.blur == null then "" else (.login.blur | tostring) end' "$settings" 2>/dev/null || true)
    accent=$(jq -r '.login.accent // empty' "$settings" 2>/dev/null || true)
    font=$(jq -r '.login.font // empty' "$settings" 2>/dev/null || true)
    date_format=$(jq -r '.login.dateFormat // empty' "$settings" 2>/dev/null || true)
    shell_accent=$(jq -r '.appearance.accent // empty' "$settings" 2>/dev/null || true)
    shell_font=$(jq -r '.appearance.fontFamily // empty' "$settings" 2>/dev/null || true)
    [[ $accent == "shell" ]] && accent=$shell_accent
    [[ $font == "shell" ]] && font=$shell_font
    [[ $blur == "true" || $blur == "false" ]] && printf 'blur=%s\n' "$blur" >> "$user_conf"
    [[ $accent =~ ^#[0-9a-fA-F]{6}$ ]] && printf 'accent="%s"\n' "$accent" >> "$user_conf"
    [[ -n $font && $font != *$'\n'* ]] && printf 'font=%s\n' "$font" >> "$user_conf"
    [[ -n $date_format && $date_format != *$'\n'* ]] && printf 'dateFormat="%s"\n' "$date_format" >> "$user_conf"
    printf 'Applied the login screen settings from %s\n' "$settings"
  fi
  # What the lock screen was arranged to show, so the login screen can follow
  # it as far as it honestly can. The arrangement lives in layout.json beside
  # the settings; the greeter runs as another user and cannot read either.
  #
  # Only the order and the presence carry over, as a comma-string - the theme
  # is a separate QML application that cannot import the shell's components,
  # so it has the blocks it has and no grid at all. `Logic.configString` in the
  # theme splits the string back up.
  local layout_file="${settings%/settings.json}/layout.json"
  if [[ -n $settings && -r $layout_file ]]; then
    local lock_items
    lock_items=$(jq -r '[.lock.lock[]?.items[0].type] | map(select(test("^[a-z]+$"))) | join(",")' \
                   "$layout_file" 2>/dev/null || true)
    [[ -n $lock_items && $lock_items != *$'\n'* ]] && printf 'lockItems="%s"\n' "$lock_items" >> "$user_conf"
  fi
  chmod 0644 -- "$user_conf"

  mkdir -p -- "$state_dir"
  if [[ -n $avatar ]]; then
    [[ -r $avatar && -n $user ]] || { printf 'Avatar needs a readable file and a user\n' >&2; exit 1; }
    mkdir -p -- "$faces_dir"
    if [[ -e $faces_dir/$user.face.icon && ! -e $state_dir/face-installed ]]; then
      cp -p -- "$faces_dir/$user.face.icon" "$state_dir/$user.face.icon.backup"
    fi
    install -m0644 -- "$avatar" "$faces_dir/$user.face.icon"
    printf '%s\n' "$user" > "$state_dir/face-installed"
    printf 'Installed avatar for %s\n' "$user"
  fi

  # Back up and disable other theme selections so ours applies.
  local file
  while IFS= read -r file; do
    theme_current "$file" >/dev/null || continue
    local backup
    backup="$state_dir/$(printf '%s' "${file#"$root"}" | tr '/' '_').backup"
    [[ -e $backup ]] || cp -p -- "$file" "$backup"
    printf '%s\n' "${file#"$root"}" >> "$state_dir/restore-list"
    sed -i "/^[[:space:]]*\[Theme\]/,/^[[:space:]]*\[/ s|^\([[:space:]]*Current[[:space:]]*=.*\)|$marker \1|" "$file"
    printf 'Disabled the theme selection in %s (backup %s)\n' "${file#"$root"}" "$backup"
  done < <(other_configs)
  [[ -f $state_dir/restore-list ]] && sort -u -o "$state_dir/restore-list" "$state_dir/restore-list"

  mkdir -p -- "$conf_dir"
  printf '# Installed by buchhwin-shell (install/system-install.sh --sddm-theme).\n[Theme]\nCurrent=buchhwin\n' > "$conf_file"
  chmod 0644 -- "$conf_file"
  printf 'Installed the SDDM theme to %s\n' "${theme_dir#"$root"}"

  local manager
  manager=$(active_display_manager)
  if $use_sddm && [[ $manager != sddm.service ]]; then
    [[ -e $state_dir/display-manager ]] || printf '%s\n' "$manager" > "$state_dir/display-manager"
    [[ -n $manager ]] && run_systemctl disable "$manager"
    run_systemctl enable sddm.service
    printf 'SDDM becomes the display manager at the next boot (was %s).\n' "${manager:-none}"
  elif [[ $manager != sddm.service ]]; then
    printf 'Note: the active display manager is %s; the theme is only used by SDDM.\n' "${manager:-unknown}"
    printf 'Switch at the next boot with: sudo %s/install/system-install.sh --sddm-theme --use-sddm\n' "$project_dir"
  fi
}

remove_theme() {
  rm -f -- "$conf_file"
  if [[ -f $state_dir/restore-list ]]; then
    local file backup
    while IFS= read -r file; do
      backup="$state_dir/$(printf '%s' "$file" | tr '/' '_').backup"
      if [[ -f $backup ]]; then
        cp -p -- "$backup" "$root$file"
        printf 'Restored %s\n' "$file"
      fi
    done < "$state_dir/restore-list"
  fi
  if [[ -f $state_dir/face-installed ]]; then
    local face_user
    face_user=$(<"$state_dir/face-installed")
    if [[ -f $state_dir/$face_user.face.icon.backup ]]; then
      cp -p -- "$state_dir/$face_user.face.icon.backup" "$faces_dir/$face_user.face.icon"
    else
      rm -f -- "$faces_dir/$face_user.face.icon"
    fi
    printf 'Removed the avatar of %s\n' "$face_user"
  fi
  if [[ -f $state_dir/display-manager ]]; then
    local previous
    previous=$(<"$state_dir/display-manager")
    if [[ -n $previous ]]; then
      run_systemctl disable sddm.service
      run_systemctl enable "$previous"
      printf '%s is the display manager again from the next boot.\n' "$previous"
    fi
  fi
  rm -rf -- "$theme_dir" "$state_dir"
  printf 'Removed the buchhwin SDDM theme.\n'
}

if [[ $action == install ]]; then install_theme; else remove_theme; fi
