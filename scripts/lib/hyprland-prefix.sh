# Sourced. Puts a Hyprland built from source into the home directory
# (install/build-hyprland-leap.sh, openSUSE Leap) in front of PATH, the same
# way session/buchhwin-shell-session does for the session, so the checks and
# the nested session run against the Hyprland the desktop runs. A no-op where
# Hyprland is a package (Fedora).
hyprland_prefix=${BUCHHWIN_HYPRLAND_PREFIX:-"$HOME/.local/opt/buchhwin-hyprland"}
if [[ -x $hyprland_prefix/bin/Hyprland && :$PATH: != *":$hyprland_prefix/bin:"* ]]; then
  export PATH="$hyprland_prefix/bin:$PATH"
fi
