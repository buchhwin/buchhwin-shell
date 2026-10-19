# Hyprland patches

Applied by `install/build-hyprland-leap.sh` to a clean checkout of the pinned
Hyprland before building. Adding, changing or removing one makes the build out
of date (the build record keeps each patch's hash), so the next run rebuilds.

- `0001-xwayland-cursor-monitor-scale.patch` (Hyprland 0.56.2): with
  `xwayland:force_zero_scaling` the X server draws in physical pixels, but its
  cursor surfaces still report buffer scale 1, so Hyprland enlarged every
  cursor an X11 client set by the monitor scale (a Windows cursor forwarded by
  Citrix came out 1.67x on a 1.67 screen). The patch treats XWayland cursor
  surfaces as scaled by the monitor they are shown on, size and hotspot alike.
  Theme cursors drawn by XWayland itself follow `Xcursor.size`, which the shell
  already sets to the scaled size (scripts/apply-cursor-env.sh).
