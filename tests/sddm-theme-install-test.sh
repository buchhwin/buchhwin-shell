#!/usr/bin/env bash
set -euo pipefail

# Installs and removes the SDDM theme below a scratch root (install/sddm-theme.sh
# --root): wallpaper from a synthetic settings.json, avatar, backup of other
# [Theme] Current= settings, display manager switch and full restore.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-sddmtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
root="$sandbox/root"
home="$sandbox/home/tester"
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL sddm-theme: %s\n' "$2"; failures=$((failures + 1)); fi
}

mkdir -p "$root/etc/sddm.conf.d" "$root/etc/systemd/system" "$home/.config/buchhwin-shell" "$home/Pictures"
printf '[General]\nNumlock=on\n\n[Theme]\nCurrent=breeze\nCursorTheme=Breeze\n\n[Users]\nMaximumUid=60000\n' > "$root/etc/sddm.conf"
printf '[Theme]\n  Current = maya\n' > "$root/etc/sddm.conf.d/10-other.conf"
printf '[Wayland]\nCurrent=not-a-theme\n' > "$root/etc/sddm.conf.d/20-unrelated.conf"
ln -s /usr/lib/systemd/system/plasmalogin.service "$root/etc/systemd/system/display-manager.service"
printf 'synthetic image' > "$home/Pictures/Wall.WEBP"
printf 'synthetic face' > "$sandbox/face.png"
printf '{ "wallpaper": { "path": "~/Pictures/Wall.WEBP" } }\n' > "$home/.config/buchhwin-shell/settings.json"
cp -p "$root/etc/sddm.conf" "$sandbox/sddm.conf.orig"
cp -p "$root/etc/sddm.conf.d/10-other.conf" "$sandbox/10-other.conf.orig"
cp -p "$root/etc/sddm.conf.d/20-unrelated.conf" "$sandbox/20-unrelated.conf.orig"

output=$("$project_dir/install/sddm-theme.sh" install --root "$root" \
  --settings "$home/.config/buchhwin-shell/settings.json" --avatar "$sandbox/face.png" --user tester --use-sddm)
theme="$root/usr/share/sddm/themes/buchhwin"
check '[[ -f $theme/Main.qml && -f $theme/metadata.desktop && -f $theme/assets/background.svg ]]' "theme copied"
check 'cmp -s "$home/Pictures/Wall.WEBP" "$theme/background.webp"' "wallpaper copied with a lower-case extension"
check 'grep -qx "background=background.webp" "$theme/theme.conf.user"' "theme.conf.user selects the wallpaper"
check 'grep -qx "Current=buchhwin" "$root/etc/sddm.conf.d/buchhwin-theme.conf"' "theme selected"
check '! grep -qE "^[[:space:]]*Current" "$root/etc/sddm.conf" && grep -qx "CursorTheme=Breeze" "$root/etc/sddm.conf"' "sddm.conf theme selection commented out, rest kept"
check '! grep -qE "^[[:space:]]*Current" "$root/etc/sddm.conf.d/10-other.conf"' "conf.d theme selection commented out"
check 'cmp -s "$sandbox/20-unrelated.conf.orig" "$root/etc/sddm.conf.d/20-unrelated.conf"' "Current= outside [Theme] untouched"
check 'cmp -s "$sandbox/face.png" "$root/usr/share/sddm/faces/tester.face.icon"' "avatar installed"
check 'grep -q "Would run: systemctl disable plasmalogin.service" <<<"$output" && grep -q "Would run: systemctl enable sddm.service" <<<"$output"' "display manager switch planned"

# Unsupported files are refused; a second install keeps the first backups.
printf 'text' > "$sandbox/notes.txt"
check '! "$project_dir/install/sddm-theme.sh" install --root "$root" --wallpaper "$sandbox/notes.txt" >/dev/null 2>&1' "unsupported wallpaper refused"
check '! "$project_dir/install/sddm-theme.sh" install --root "$root" --wallpaper "$sandbox/missing.jpg" >/dev/null 2>&1' "missing wallpaper refused"
printf 'second' > "$sandbox/second.jpg"
"$project_dir/install/sddm-theme.sh" install --root "$root" --wallpaper "$sandbox/second.jpg" >/dev/null
check '[[ ! -e $theme/background.webp && -f $theme/background.jpg ]]' "reinstall replaces the wallpaper"
"$project_dir/install/sddm-theme.sh" install --root "$root" --settings "$sandbox/missing.json" >/dev/null
check '[[ -f $theme/theme.conf.user ]] && ! grep -q "^background=" "$theme/theme.conf.user"' "no wallpaper falls back to the bundled gradient"

# The look of the login screen comes from the user's own settings, because the
# greeter runs as another user and cannot read them itself.
cat > "$sandbox/login-settings.json" <<'JSON'
{ "appearance": { "accent": "#62d394", "fontFamily": "Inter Variable" },
  "login": { "blur": false, "accent": "shell", "font": "shell", "dateFormat": "dd.MM.yyyy" } }
JSON
"$project_dir/install/sddm-theme.sh" install --root "$root" --settings "$sandbox/login-settings.json" >/dev/null
check 'grep -qx "blur=false" "$theme/theme.conf.user"' "login blur written"
check 'grep -qx "accent=\"#62d394\"" "$theme/theme.conf.user"' "\"shell\" accent resolves to the shell accent"
check 'grep -qx "font=Inter Variable" "$theme/theme.conf.user"' "\"shell\" font resolves to the shell font"
check 'grep -qx "dateFormat=\"dd.MM.yyyy\"" "$theme/theme.conf.user"' "date format written"

# As much of the lock screen's arrangement as the login screen can draw: the
# order and the presence, as a comma-string beside layout.json.
cat > "$sandbox/layout.json" <<'JSON'
{ "configVersion": 2, "lock": { "lock": [
  { "id": "lock-1", "items": [{ "type": "date", "w": 2, "h": 1 }] },
  { "id": "lock-2", "items": [{ "type": "clock", "w": 2, "h": 2 }] },
  { "id": "lock-3", "items": [{ "type": "media", "w": 2, "h": 2 }] }] } }
JSON
cp "$sandbox/login-settings.json" "$sandbox/settings.json"
"$project_dir/install/sddm-theme.sh" install --root "$root" --settings "$sandbox/settings.json" >/dev/null
check 'grep -qx "lockItems=\"date,clock,media\"" "$theme/theme.conf.user"' "the lock arrangement is carried over"

cat > "$sandbox/layout.json" <<'JSON'
{ "lock": { "lock": [{ "id": "x", "items": [{ "type": "clock\nInput=evil" }] }] } }
JSON
"$project_dir/install/sddm-theme.sh" install --root "$root" --settings "$sandbox/settings.json" >/dev/null
check '! grep -q "Input=evil" "$theme/theme.conf.user"' "a type that is not a plain word is dropped"

cat > "$sandbox/bad-login.json" <<'JSON'
{ "login": { "blur": "maybe", "accent": "red; rm -rf /", "font": "", "dateFormat": "" } }
JSON
"$project_dir/install/sddm-theme.sh" install --root "$root" --settings "$sandbox/bad-login.json" >/dev/null
check '! grep -qE "^(blur|accent|font|dateFormat|lockItems)=" "$theme/theme.conf.user"' "invalid login values are dropped"

output=$("$project_dir/install/sddm-theme.sh" remove --root "$root")
check '[[ ! -e $theme && ! -e $root/etc/sddm.conf.d/buchhwin-theme.conf ]]' "theme and selection removed"
check 'cmp -s "$sandbox/sddm.conf.orig" "$root/etc/sddm.conf"' "sddm.conf restored"
check 'cmp -s "$sandbox/10-other.conf.orig" "$root/etc/sddm.conf.d/10-other.conf"' "conf.d file restored"
check '[[ ! -e $root/usr/share/sddm/faces/tester.face.icon ]]' "avatar removed"
check 'grep -q "Would run: systemctl enable plasmalogin.service" <<<"$output"' "previous display manager restored"
check '[[ ! -e $root/var/lib/buchhwin-shell/sddm-theme ]]' "state removed"

if (( failures )); then
  printf 'TESTS FAILED sddm-theme (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED sddm-theme\n'
