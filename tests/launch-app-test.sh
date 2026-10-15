#!/usr/bin/env bash
set -euo pipefail
# scripts/launch-app.sh and session/bin/xdg-open: an application starts in a
# systemd scope named after its desktop entry, which is the name the portals
# know it by (see launch-app.sh for the key that went missing without it), and
# the session's xdg-open wraps the system's one the same way.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-launchtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL launch-app: %s\n' "$2"; failures=$((failures + 1)); fi; }

bin="$sandbox/bin"; sys="$sandbox/sys"; calls="$sandbox/calls.log"
mkdir -p "$bin" "$sys"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# systemd-run records its arguments and runs what follows `--`.
stub systemd-run 'while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
stub systemctl
# systemd-escape: the last argument with its dashes escaped.
stub systemd-escape 'for a in "$@"; do last=$a; done; printf "%s\n" "$last" | sed "s/-/\\\\x2d/g"'
stub xdg-settings 'echo com.brave.Browser.desktop'
# The browsers, the notification a refused start sends, and the bus: the
# wallet is open unless a case below says otherwise.
stub brave-browser
stub google-chrome-stable
stub chromium-browser
stub notify-send
owned='printf "NAME PID PROCESS\norg.freedesktop.secrets 42 ksecretd\n"'
wallet_open() { stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"; }
wallet_open
stub xdg-mime 'case "$*" in "query default x-scheme-handler/mailto") echo org.kde.kmail2.desktop ;; "query filetype "*) echo text/plain ;; "query default text/plain") echo org.kde.kate.desktop ;; *) echo "" ;; esac'
# The "system" xdg-open, further down PATH than the session's.
printf '#!/bin/sh\nprintf "real-xdg-open %%s\\n" "$*" >> "%s"\n' "$calls" > "$sys/xdg-open"; chmod +x "$sys/xdg-open"
export PATH="$project_dir/session/bin:$bin:$sys:$PATH"

# ---- launch-app.sh ------------------------------------------------------------
: > "$calls"
out=$("$project_dir/scripts/launch-app.sh" brave-browser printf 'ran %s' hello)
check '[[ $out == "ran hello" ]]' "the command runs inside the scope (got: $out)"
check 'grep -qE "^systemd-run --user --scope --quiet --slice=app.slice --unit=app-buchhwin-brave\\\\x2dbrowser-[0-9]+\.scope -- printf ran %s hello$" "$calls"' \
  "a scope named app-buchhwin-<escaped id>-<pid>, in app.slice ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
"$project_dir/scripts/launch-app.sh" com.brave.Browser.desktop true
check 'grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- true$" "$calls"' "the .desktop suffix is dropped from the id"
status=0; "$project_dir/scripts/launch-app.sh" only-an-id >/dev/null 2>&1 || status=$?
check '[[ $status -eq 2 ]]' "an id without a command is refused"
# No systemd-run anywhere: the command runs as it is.
mkdir -p "$sandbox/min"; ln -s /usr/bin/printf "$sandbox/min/printf" 2>/dev/null || true
: > "$calls"
out=$(PATH="$sandbox/min" /bin/bash "$project_dir/scripts/launch-app.sh" kitty printf plain)
check '[[ $out == plain && ! -s $calls ]]' "without systemd-run the command simply runs"

# ---- scripts/launch-brave.sh ----------------------------------------------------
# Plasma's password store, in its own scope, only with the wallet open. Every
# start's status is caught: under set -e a refused start would otherwise end
# the whole test here, without a FAIL line to say which.
: > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" --new-window || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave-browser --password-store=kwallet6 --new-window$" "$calls"' \
  "Brave starts with --password-store=kwallet6, the key Plasma's Brave uses ($(grep systemd-run "$calls" | head -1))"
check 'grep -q "^brave-browser --password-store=kwallet6 --new-window$" "$calls"' "and the arguments reach Brave"
check 'grep -q -- "--auto-start=no .*get-property org.freedesktop.secrets" "$calls" && ! grep -q Unlock "$calls"' \
  "the wallet is read first, and an open one is not asked anything"
# Shut, and the service offers no prompt: no Brave, and a notification why.
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *Unlock*) printf 'ao 0 o \"/\"\n' ;; *) $owned ;; esac"
: > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^brave-browser" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Brave (status $status)"
check 'grep -q "^notify-send .*Brave not started" "$calls"' "and the user is told why"
# Shut, prompt offered and answered: Brave starts after the prompt.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"/org/freedesktop/secrets/prompt/p1\"\n' ;; *\"Secret.Prompt Prompt\"*) touch \"$sandbox/prompted\" ;; *get-property*) if [ -e \"$sandbox/prompted\" ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
rm -f "$sandbox/prompted"; : > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" || status=$?
check '[[ $status -eq 0 ]] && grep -q "Secret.Prompt Prompt" "$calls" && grep -q "^brave-browser --password-store=kwallet6$" "$calls"' "the prompt is followed and Brave starts once the wallet is open (status $status)"
# Shut, prompt dismissed: no Brave.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"/org/freedesktop/secrets/prompt/p1\"\n' ;; *\"Secret.Prompt Prompt\"*) touch \"$sandbox/prompted\" ;; *introspect*) if [ -e \"$sandbox/prompted\" ]; then exit 1; fi ;; *get-property*) echo 'b true' ;; *) $owned ;; esac"
rm -f "$sandbox/prompted"; : > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^brave-browser" "$calls" && grep -q "^notify-send" "$calls"' "a dismissed prompt means no Brave (status $status)"
wallet_open
# Arch: the AUR's brave-bin is /usr/bin/brave, and gnome-keyring holds the
# generic secret service name while ksecretd answers on its own. Only where
# this machine has no real brave-browser, which would otherwise be started.
rm -f "$bin/brave-browser"
stub brave
if ! command -v brave-browser >/dev/null 2>&1; then
  stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) printf 'NAME PID PROCESS\norg.freedesktop.secrets 41 gnome-keyring-d\norg.kde.ksecretd 42 ksecretd\n' ;; esac"
  : > "$calls"
  status=0; "$project_dir/scripts/launch-brave.sh" --new-window || status=$?
  check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave --password-store=kwallet6 --new-window$" "$calls"' \
    "Arch: Brave starts as brave, same id and password store ($(grep systemd-run "$calls" | head -1))"
  check 'grep -q -- "get-property org.kde.ksecretd" "$calls"' "Arch: the wallet is read from ksecretd, not gnome-keyring"
fi
rm -f "$bin/brave"
stub brave-browser
wallet_open

# ---- scripts/launch-chrome.sh, launch-chromium-browser.sh ----------------------
# Chrome and Chromium keep the same two keys in the wallet as Brave, so they
# share its guard (scripts/launch-chromium.sh): the password store, a scope
# named after their entries, and no start against a shut wallet.
: > "$calls"
status=0; "$project_dir/scripts/launch-chrome.sh" --new-window || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.google\.Chrome-[0-9]+\.scope -- google-chrome-stable --password-store=kwallet6 --new-window$" "$calls"' \
  "Chrome starts with --password-store=kwallet6 in a scope of its own ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium-browser.sh" || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-chromium\\\\x2dbrowser-[0-9]+\.scope -- chromium-browser --password-store=kwallet6$" "$calls"' \
  "Chromium starts with --password-store=kwallet6 in a scope of its own ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium.sh" com.google.Chrome >/dev/null 2>&1 || status=$?
check '[[ $status -ne 0 ]] && ! grep -q systemd-run "$calls"' "launch-chromium.sh without a command is refused (status $status)"
# Shut, no prompt offered: neither starts, and the notification names the browser.
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *Unlock*) printf 'ao 0 o \"/\"\n' ;; *) $owned ;; esac"
: > "$calls"
status=0; "$project_dir/scripts/launch-chrome.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^google-chrome-stable" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Chrome (status $status)"
check 'grep -q "^notify-send .*Google Chrome not started" "$calls"' "and the notification names Chrome"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium-browser.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^chromium-browser" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Chromium (status $status)"
check 'grep -q "^notify-send .*Chromium not started" "$calls"' "and the notification names Chromium"
wallet_open

# ---- session/bin/xdg-open -------------------------------------------------------
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave-browser --password-store=kwallet6 https://example.org/page$" "$calls"' \
  "a web link for Brave goes through launch-brave.sh: Plasma's store, the browser's scope"
check 'grep -q "^brave-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "and Brave gets the link, not the system xdg-open"
# Chrome or Chromium as the default browser: the link takes their launchers.
stub xdg-settings 'echo google-chrome.desktop'
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-com\.google\.Chrome-[0-9]+\.scope -- google-chrome-stable --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for Chrome goes through launch-chrome.sh"
stub xdg-settings 'echo chromium-browser.desktop'
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-chromium\\\\x2dbrowser-[0-9]+\.scope -- chromium-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for Chromium goes through launch-chromium-browser.sh"
# Arch's package names its entry chromium.desktop: the same wrapper, not the
# plain scope (no password store, no wallet guard).
stub xdg-settings 'echo chromium.desktop'
: > "$calls"
status=0; xdg-open https://example.org/page || status=$?
check '[[ $status -eq 0 ]] && grep -q "^chromium-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for chromium.desktop goes through launch-chromium-browser.sh too ($(grep systemd-run "$calls" | head -1))"
# And there it runs as chromium - only where this machine has no real
# chromium-browser, which would otherwise be started.
rm -f "$bin/chromium-browser"
stub chromium
if ! command -v chromium-browser >/dev/null 2>&1; then
  : > "$calls"
  status=0; xdg-open https://example.org/page || status=$?
  check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-chromium-[0-9]+\.scope -- chromium --password-store=kwallet6 https://example.org/page$" "$calls"' \
    "Arch: the link reaches chromium with Plasma's store ($(grep systemd-run "$calls" | head -1))"
fi
rm -f "$bin/chromium"
stub chromium-browser
stub xdg-settings 'echo com.brave.Browser.desktop'
: > "$calls"
xdg-open mailto:someone@example.org
check 'grep -qE "unit=app-buchhwin-org\.kde\.kmail2-[0-9]+\.scope -- " "$calls"' "another scheme takes its own handler's name"
printf 'x\n' > "$sandbox/doc.txt"
: > "$calls"
xdg-open "$sandbox/doc.txt"
check 'grep -qE "unit=app-buchhwin-org\.kde\.kate-[0-9]+\.scope -- " "$calls"' "a file takes the handler of its type"
: > "$calls"
xdg-open "$sandbox/does-not-exist"
check '! grep -q systemd-run "$calls" && grep -q "^real-xdg-open $sandbox/does-not-exist$" "$calls"' "no handler known: the system xdg-open runs as it is"
: > "$calls"
xdg-open
check '! grep -q systemd-run "$calls" && grep -q "^real-xdg-open $" "$calls"' "no argument: handed on untouched"

# ---- scripts/launch-alacritty.sh -------------------------------------------------
# The account's Alacritty with Settings > Terminal's opacity on top (for every
# cell background, not only the default one), in its own scope; the default without a setting, and nothing but a number in [0, 1]
# reaches the command line.
stub alacritty
cfg="$sandbox/alacritty-cfg"; mkdir -p "$cfg/buchhwin-shell"
: > "$calls"
XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh" -e true
check 'grep -qE "unit=app-buchhwin-Alacritty-[0-9]+\.scope -- alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true -e true$" "$calls"' \
  "Alacritty starts at the default 0.8 in its scope ($(grep systemd-run "$calls" | head -1))"
if command -v jq >/dev/null 2>&1; then
  printf '{ "terminal": { "opacity": 0.65 } }\n' > "$cfg/buchhwin-shell/settings.json"
  : > "$calls"
  XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh"
  check 'grep -q "^alacritty -o window.opacity=0.65 -o colors.transparent_background_colors=true$" "$calls"' "the opacity follows Settings > Terminal"
  printf '{ "terminal": { "opacity": "1; rm -rf ~" } }\n' > "$cfg/buchhwin-shell/settings.json"
  : > "$calls"
  XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh"
  check 'grep -q "^alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true$" "$calls"' "anything but a number falls back to 0.8"
fi
check 'grep -q "Alacritty.desktop) exec \"\$project_dir/scripts/launch-alacritty.sh\"" "$project_dir/scripts/launch-default.sh"' \
  "the session's default terminal goes through it"

if (( failures )); then printf 'TESTS FAILED launch-app (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED launch-app\n'
