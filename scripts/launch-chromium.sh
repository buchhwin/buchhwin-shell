#!/usr/bin/env bash
set -euo pipefail

# A Chromium-based browser in this session, with the keys Plasma's copy of it
# uses - so the profile stays readable across sessions and nobody is logged
# out of anything. Brave, Google Chrome and Chromium keep the same two items
# in the wallet ("<Browser> Keys/<Browser> Safe Storage" through kwalletd6,
# the Secret Service item "<Browser> Safe Storage"), so one guard serves all
# three. The wrappers launch-brave.sh, launch-chrome.sh and
# launch-chromium-browser.sh only fix the desktop id and the command, because
# LauncherService.appOverrides and the Hyprland binds run a script without
# arguments.
#
#   launch-chromium.sh <desktop-id> <command> [args...]
#
# How Chromium encrypts on Linux (chrome/browser/browser_process_impl.cc,
# components/os_crypt/async/browser/*, checked 2026-10-13, Brave 1.97):
#
#   - Two key providers. SecretPortalKeyProvider asks the XDG Secret portal and
#     is only allowed to *decrypt* (kSecretPortalKeyProviderUseForEncryption is
#     off by default). FreedesktopSecretKeyProvider does the encrypting, and it
#     picks its backend from --password-store, else from the desktop:
#     KDE -> org.kde.kwalletd6 and the entry "Brave Keys/Brave Safe Storage";
#     anything else -> the Secret Service item "Brave Safe Storage" (Chrome
#     and Chromium: the same two names with theirs). Plasma is KDE; this
#     session is "buchhwin-shell:Hyprland", which is "anything else". Two
#     backends, two keys, and everything one session wrote was unreadable in
#     the other. Hence --password-store=kwallet6: the backend Plasma's browser
#     gets by itself. kwalletd6 is a shim over ksecretd's Secret Service on
#     this system (KF 6.16), so it is the same wallet.
#   - A backend that cannot be opened is "permanently unavailable" to Chromium,
#     which then encrypts with a fallback key: a third key, and the same logout.
#     So the browser only starts once scripts/wallet-unlock.sh says the wallet
#     is open; if it is shut, the KWallet prompt is shown first, and a
#     dismissed prompt means no browser, with a notification saying why.
#   - The application's name towards the portals is not something this script
#     can set: Chromium moves itself into app-org.chromium.Chromium-<pid>.scope
#     (components/dbus/xdg/systemd.cc) in every session, Plasma included. The
#     scope launch-app.sh makes is harmless and keeps other applications
#     named; it was never the key that went missing.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
id=${1:?usage: launch-chromium.sh <desktop-id> <command> [args...]}
exe=${2:?usage: launch-chromium.sh <desktop-id> <command> [args...]}
shift 2
# The browser's name for the notification and the log comes from the command
# rather than from its desktop entry, so the guard reads nothing and behaves
# the same in a test sandbox as on the desktop.
case ${exe##*/} in
  brave*) name=Brave ;;
  google-chrome*) name="Google Chrome" ;;
  chromium*) name=Chromium ;;
  *) name=${exe##*/} ;;
esac
wallet="$project_dir/scripts/wallet-unlock.sh"
if [[ -x $wallet ]]; then
  if ! state=$("$wallet" ensure --prompt --wait 2 --timeout 60); then
    message="The KDE wallet is $state. $name encrypts its cookies and sign-ins with a key kept there; started now it would make a new key and log you out everywhere. Unlock the wallet and try again."
    printf 'launch-chromium: not starting %s: %s\n' "$name" "$message" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -a buchhwin-shell -u critical "$name not started" "$message" || true
    exit 1
  fi
fi
exec "$project_dir/scripts/launch-app.sh" "$id" "$exe" --password-store=kwallet6 "$@"
