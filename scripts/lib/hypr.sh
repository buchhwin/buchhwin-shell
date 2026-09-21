# shellcheck shell=bash
# Helpers for scripts that must work with both Hyprland configuration formats:
# legacy hyprland.conf (dispatch/keyword) and hyprland.lua (Lua expressions,
# required from Hyprland 0.57). Source this file.

hypr_is_lua() {
  [[ $(hyprctl eval 'return 1' 2>/dev/null) == ok ]]
}

# hypr_dispatch LEGACY LUA
hypr_dispatch() {
  if hypr_is_lua; then hyprctl dispatch "$2"; else hyprctl dispatch "$1"; fi
}
