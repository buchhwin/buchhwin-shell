#!/usr/bin/env bash
# scripts/apply-x11-dpi.sh and the X11 half of scripts/apply-cursor-env.sh,
# against a stand-in `xrdb` that records what it is given. What is under test
# is what reaches the X resource database: with "Sharp X11 applications" on,
# X11 clients are told the screen's real scale through `Xft.dpi`, and off
# again the key goes without taking the cursor entries with it. A nested
# session must not touch the host's database at all.
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 1
SB=$(mktemp -d); trap 'rm -rf -- "$SB"' EXIT
mkdir -p "$SB/bin"
# xrdb: -query prints the database, -merge appends stdin, -load replaces.
cat > "$SB/bin/xrdb" <<'Q'
#!/usr/bin/env bash
printf 'xrdb %s\n' "$*" >> "$CALLS"
case "$1" in
  -query) cat "$DB" 2>/dev/null ;;
  -merge) cat >> "$DB" ;;
  -load) cat > "$DB" ;;
esac
Q
# The cursor script also talks to the compositor and systemd; record and agree.
for stub in hyprctl systemctl dbus-update-activation-environment; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "$CALLS"\n' "$stub" > "$SB/bin/$stub"
done
chmod +x "$SB/bin/"*
# The sandbox is the whole environment: a nested session's files in the
# default BUCHHWIN_NESTED_DIR, or a stray BUCHHWIN_NESTED, would turn every
# ordinary case below into the refusal and read as a pass.
mkdir -p "$SB/no-nested"
unset BUCHHWIN_NESTED
export PATH="$SB/bin:$PATH" DB="$SB/xrdb.db" CALLS="$SB/calls" DISPLAY=:9 XDG_CONFIG_HOME="$SB/config" \
  BUCHHWIN_NESTED_DIR="$SB/no-nested"
fail=0
check() { if eval "$1"; then :; else printf 'FAIL: %s\n' "$2"; fail=1; fi; }

# on: the key is merged in
printf 'Xcursor.theme:\tmacOS\nXcursor.size:\t24\n' > "$DB"
bash ./scripts/apply-x11-dpi.sh 144
check 'grep -q "^Xft.dpi: 144$" "$DB"' 'Xft.dpi 144 reaches the database'
check '[[ $(grep -c "^Xcursor" "$DB") == 2 ]]' 'the cursor entries stay'

# off: the key says 96, and nothing else is touched - a merge, never a
# snapshot loaded back over what another writer merged meanwhile
bash ./scripts/apply-x11-dpi.sh reset
check 'grep -q "^Xft.dpi: 96$" "$DB"' 'reset writes Xft.dpi 96'
check '[[ $(grep -c "^Xcursor" "$DB") == 2 ]]' 'and keeps the cursor entries'
check '! grep -q "load" "$CALLS"' 'and never loads a snapshot'

# reset on an empty database is not an error
: > "$DB"
check 'bash ./scripts/apply-x11-dpi.sh reset' 'reset on an empty database succeeds'

# the two writers take turns: both merge, and the lock is asked for
: > "$DB"; : > "$CALLS"
bash ./scripts/apply-x11-dpi.sh 144 & bash ./scripts/apply-cursor-env.sh macOS 24 36; wait
check 'grep -q "^Xft.dpi: 144$" "$DB" && grep -q "^Xcursor.size: 36$" "$DB"' 'a DPI merge and a cursor merge at once both land'

# nonsense is refused before anything is written
printf 'Xcursor.size:\t24\n' > "$DB"
bash ./scripts/apply-x11-dpi.sh '144; rm -rf /' 2>/dev/null
check '[[ $? == 2 ]]' 'an invalid value is refused'
check '! grep -q "Xft" "$DB"' 'and nothing was written'

# a nested session never reaches the host's database
BUCHHWIN_NESTED=1 bash ./scripts/apply-x11-dpi.sh 144 2>/dev/null
check '! grep -q "Xft" "$DB"' 'a nested session writes nothing'

# ... and it is recognised by its files, not only by the flag: the testing
# recipe exports the nested WAYLAND_DISPLAY and never BUCHHWIN_NESTED, and both
# scripts used to write the host's database and systemd environment from there
mkdir -p "$SB/nested"
printf 'wayland-9\n' > "$SB/nested/wayland-display"
: > "$CALLS"
BUCHHWIN_NESTED_DIR="$SB/nested" WAYLAND_DISPLAY=wayland-9 bash ./scripts/apply-x11-dpi.sh 144 2>/dev/null
check '[[ $? == 0 ]]' 'a nested environment is skipped, not failed'
check '! grep -q "Xft" "$DB"' 'a nested environment (files, no flag) writes no DPI'
BUCHHWIN_NESTED_DIR="$SB/nested" WAYLAND_DISPLAY=wayland-9 bash ./scripts/apply-cursor-env.sh macOS 24 2>/dev/null
check '! grep -q "Xcursor.theme: macOS" "$DB" && [[ ! -s $CALLS ]]' 'a nested environment sets no cursor anywhere'
printf 'sig-9\n' > "$SB/nested/instance"
BUCHHWIN_NESTED_DIR="$SB/nested" WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=sig-9 bash ./scripts/apply-x11-dpi.sh 144 2>/dev/null
check '! grep -q "Xft" "$DB"' 'the nested signature alone is enough to refuse'
BUCHHWIN_NESTED_DIR="$SB/nested" WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=sig-1 bash ./scripts/apply-x11-dpi.sh 144 2>/dev/null
check 'grep -q "^Xft.dpi: 144$" "$DB"' 'a display and signature that are not the nested ones still write'

# the cursor script: the X resource gets the X11 size, the compositor the real one
: > "$DB"; : > "$CALLS"
bash ./scripts/apply-cursor-env.sh macOS 24 36
check 'grep -q "^Xcursor.size: 36$" "$DB"' 'Xcursor.size is the X11 size'
check 'grep -q "XCURSOR_SIZE,24\|XCURSOR_SIZE=24" "$CALLS"' 'the compositor and systemd get 24'
check '! grep -q "36" "$CALLS"' 'and never the X11 size'
: > "$DB"
bash ./scripts/apply-cursor-env.sh macOS 24
check 'grep -q "^Xcursor.size: 24$" "$DB"' 'left out, the X11 size is the size'
bash ./scripts/apply-cursor-env.sh macOS 24 'x' 2>/dev/null
check '[[ $? == 2 ]]' 'a bad X11 size is refused'

# the GTK settings.ini: the two cursor keys change, everything else stays, the
# file keeps its mode, and there is one backup of the first version - not a
# timestamped copy per change
ini="$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
mkdir -p "${ini%/*}"
printf '[Settings]\ngtk-theme-name=Breeze\ngtk-cursor-theme-name=breeze_cursors\ngtk-cursor-theme-size=24\n' > "$ini"
chmod 640 "$ini"
bash ./scripts/apply-cursor-env.sh macOS 32
check 'grep -q "^gtk-cursor-theme-name=macOS$" "$ini" && grep -q "^gtk-cursor-theme-size=32$" "$ini"' 'settings.ini gets the cursor keys'
check 'grep -q "^gtk-theme-name=Breeze$" "$ini" && [[ $(head -n1 "$ini") == "[Settings]" ]]' 'and keeps its other lines'
check '[[ $(stat -c %a "$ini") == 640 ]]' 'and its mode (mktemp alone would leave 600)'
check 'grep -q "^gtk-cursor-theme-name=breeze_cursors$" "$ini.buchhwin-backup"' 'the first version is backed up'
bash ./scripts/apply-cursor-env.sh Adwaita 24
check 'grep -q "^gtk-cursor-theme-name=Adwaita$" "$ini"' 'a second change lands'
check 'grep -q "^gtk-cursor-theme-name=breeze_cursors$" "$ini.buchhwin-backup"' 'and the backup still holds the first version'
check '[[ $(ls "${ini%/*}" | wc -l) == 2 ]]' 'no timestamped backups and no temporary files are left beside it'
mkdir -p "$XDG_CONFIG_HOME/gtk-4.0"
printf '[Settings]\ngtk-application-prefer-dark-theme=1\n' > "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
bash ./scripts/apply-cursor-env.sh Adwaita 24
check 'grep -q "^gtk-cursor-theme-name=Adwaita$" "$XDG_CONFIG_HOME/gtk-4.0/settings.ini" && grep -q "prefer-dark-theme=1" "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"' 'a file without the keys gets them appended'

# the unscaled launcher: the reciprocal of what X11 is told, 1 when nothing is
printf 'Xft.dpi:\t168\n' > "$DB"
check '[[ $(bash ./scripts/launch-x11-unscaled.sh sh -c "echo \$GDK_DPI_SCALE \$GDK_BACKEND") == "0.571 x11" ]]' 'at 168 DPI the application gets 0.571 and X11'
printf 'Xft.dpi:\t144\n' > "$DB"
check '[[ $(bash ./scripts/launch-x11-unscaled.sh sh -c "echo \$GDK_DPI_SCALE") == "0.667" ]]' 'at 144 it gets 0.667'
: > "$DB"
check '[[ $(bash ./scripts/launch-x11-unscaled.sh sh -c "echo \$GDK_DPI_SCALE") == "1" ]]' 'with no Xft.dpi it gets 1'
check '! bash ./scripts/launch-x11-unscaled.sh 2>/dev/null' 'no command is a usage error'

(( fail )) && exit 1
echo "TESTS PASSED x11 dpi and cursor resources"
