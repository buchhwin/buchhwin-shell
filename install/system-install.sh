#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Optional login theme (install/sddm-theme.sh):
#   --sddm-theme [--wallpaper PATH] [--avatar PATH] [--use-sddm]
#   --sddm-theme-remove   restores the previous theme and display manager
#   --root DIR            install below DIR without root rights (tests)
# Optional, system-wide fingerprint rule (install/fingerprint-lid.sh), run on
# its own: sudo, polkit and logins skip pam_fprintd while the lid is closed.
#   --fingerprint-lid         adds the authselect profile custom/buchhwin-lid
#   --fingerprint-lid-remove  selects the previous profile again
#   (install/fingerprint-lid.sh status works without root)
# Optional, system-wide lid handling (install/logind-lid.sh), also on its own:
# logind stops acting on the lid so the shell is the only thing that decides.
#   --logind-lid              writes /etc/systemd/logind.conf.d/50-buchhwin.conf
#   --logind-lid-remove       puts back whatever was there before
#   (install/logind-lid.sh status works without root)
# Optional, system-wide Bluetooth policy (install/bluetooth-autoenable.sh), on
# its own: BlueZ stops powering the adapter on at every boot.
#   --bluetooth-manual        writes /etc/bluetooth/main.conf.d/50-buchhwin-autoenable.conf
#   --bluetooth-auto          removes it, and BlueZ decides again
#   (install/bluetooth-autoenable.sh status works without root)
sddm_action=""
lid_action=""
logind_action=""
bluetooth_action=""
sddm_args=()
root=""
while (( $# )); do
  case "$1" in
    --sddm-theme) sddm_action=install; shift ;;
    --sddm-theme-remove) sddm_action=remove; shift ;;
    --fingerprint-lid) lid_action=install; shift ;;
    --fingerprint-lid-remove) lid_action=remove; shift ;;
    --logind-lid) logind_action=install; shift ;;
    --logind-lid-remove) logind_action=remove; shift ;;
    --bluetooth-manual) bluetooth_action=off; shift ;;
    --bluetooth-auto) bluetooth_action=on; shift ;;
    --wallpaper|--avatar) sddm_args+=("$1" "${2:?$1 needs a path}"); shift 2 ;;
    --use-sddm) sddm_args+=("$1"); shift ;;
    --root) root=${2:?--root needs a directory}; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if (( ${#sddm_args[@]} )) && [[ $sddm_action != install ]]; then
  printf '%s needs --sddm-theme\n' "${sddm_args[0]}" >&2
  exit 2
fi

if [[ -n $lid_action && ( -n $sddm_action || ${#sddm_args[@]} -gt 0 || -n $root ) ]]; then
  printf '%s\n' '--fingerprint-lid options run on their own' >&2
  exit 2
fi

if [[ -n $logind_action && ( -n $sddm_action || ${#sddm_args[@]} -gt 0 || -n $lid_action ) ]]; then
  printf '%s\n' '--logind-lid options run on their own' >&2
  exit 2
fi

if [[ -n $bluetooth_action && ( -n $sddm_action || ${#sddm_args[@]} -gt 0 || -n $lid_action || -n $logind_action ) ]]; then
  printf '%s\n' '--bluetooth options run on their own' >&2
  exit 2
fi

if [[ -n $root ]]; then
  root=$(realpath -m -- "$root")
  sddm_args+=(--root "$root")
elif (( EUID != 0 )); then
  printf 'Run this step as root: sudo %s\n' "$0" >&2
  exit 1
fi

if [[ -n $bluetooth_action ]]; then
  exec "$project_dir/install/bluetooth-autoenable.sh" "$bluetooth_action" ${root:+--root "$root"}
fi

if [[ -n $logind_action ]]; then
  exec "$project_dir/install/logind-lid.sh" "$logind_action" ${root:+--root "$root"}
fi

if [[ -n $lid_action ]]; then
  exec "$project_dir/install/fingerprint-lid.sh" "$lid_action"
fi

if [[ $sddm_action == remove ]]; then
  exec "$project_dir/install/sddm-theme.sh" remove ${root:+--root "$root"}
fi

# The session command is a wrapper that runs the launcher from the user's
# ~/.local/share/buchhwin-shell, so launcher changes need no new sudo step.
install -Dm0755 \
  "$project_dir/session/buchhwin-shell-session-wrapper" \
  "$root/usr/local/bin/buchhwin-shell-session"
install -d "$root/usr/share/wayland-sessions"
sed 's|@SESSION_EXEC@|/usr/local/bin/buchhwin-shell-session|' \
  "$project_dir/session/buchhwin-shell.desktop.in" \
  > "$root/usr/share/wayland-sessions/buchhwin-shell.desktop"
chmod 0644 "$root/usr/share/wayland-sessions/buchhwin-shell.desktop"
# PAM services of the lock screen (with fingerprint and password only); existing
# files are left alone.
for service in buchhwin-lock buchhwin-lock-password; do
  if [[ ! -e $root/etc/pam.d/$service ]]; then
    install -Dm0644 "$project_dir/session/pam/$service" "$root/etc/pam.d/$service"
  fi
done

printf 'Installed the buchhwin-shell display-manager session.\n'
printf 'User code and settings remain under each user home directory.\n'

if [[ $sddm_action == install ]]; then
  "$project_dir/install/sddm-theme.sh" install "${sddm_args[@]}"
fi
