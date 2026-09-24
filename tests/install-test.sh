#!/usr/bin/env bash
set -euo pipefail

# install/install.sh --apply, in a sandbox with a fake HOME and stub commands.
# The case that matters is the second run: the installer may be started through
# the very link it installed, and must recognise that rather than backing the
# link up and replacing it with a link to itself.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-installtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL install: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
mkdir -p "$bin"
for name in systemctl zsh; do
  printf '#!/bin/sh\nexit 0\n' > "$bin/$name"
  chmod +x "$bin/$name"
done
export PATH="$bin:$PATH"
if [[ $(command -v systemctl) != "$bin/systemctl" ]]; then
  printf 'install test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

# A checkout under its deployed name, so the link target and the checkout are
# two different paths exactly as they are in the real session.
home="$sandbox/home"
checkout="$home/.local/share/buchhwin-shell-stable"
link="$home/.local/share/buchhwin-shell"
mkdir -p "$checkout"
for part in install session scripts shell-completion zsh systemd config session/xdg-desktop-portal; do
  mkdir -p "$checkout/$part"
done
cp "$project_dir/install/install.sh" "$checkout/install/"
# The real one, not a stub: the checks below read its contents.
cp "$project_dir/config/fastfetch.jsonc" "$checkout/config/"
for file in session/buchhwin-shell-session scripts/buchhwin shell-completion/_buchhwin \
  zsh/buchhwin.zsh systemd/buchhwin-shell-session.target \
  systemd/buchhwin-shell-autostart.target \
  session/xdg-desktop-portal/buchhwin-shell-portals.conf; do
  : > "$checkout/$file"
done

export HOME="$home"
export XDG_CONFIG_HOME="$home/.config"

# ---- first run: from the checkout by its real path ------------------------
"$checkout/install/install.sh" --apply > "$sandbox/first.log" 2>&1 \
  || { printf 'FAIL install: first --apply exited non-zero\n'; cat "$sandbox/first.log"; exit 1; }

check '[[ -L "$link" ]]' 'the session link is a symlink'
check '[[ $(readlink -f -- "$link") == "$checkout" ]]' 'the session link points at the checkout'

# A machine with no dwl configuration gets the shipped one. Without it
# zsh/buchhwin.zsh passes no --config at all and none of the session's
# Fastfetch look applies, which is what a fresh install used to get.
fastfetch="$XDG_CONFIG_HOME/buchhwin-shell/fastfetch.jsonc"
check '[[ -r "$fastfetch" ]]' 'a fresh install has a Fastfetch configuration'
check '! grep -q "\"source\"" "$fastfetch"' 'the shipped configuration names no image file'
check 'grep -q "Compositor" "$fastfetch"' 'the shipped configuration is the session'"'"'s one'

# ---- second run: through the link it just installed -----------------------
# This is the path a user takes, and it used to back the good link up and
# replace it with a link to itself, leaving no shell at the next login.
"$link/install/install.sh" --apply > "$sandbox/second.log" 2>&1 \
  || { printf 'FAIL install: second --apply exited non-zero\n'; cat "$sandbox/second.log"; exit 1; }

check '[[ -L "$link" ]]' 'the session link is still a symlink after a second run'
check '[[ $(readlink -f -- "$link") == "$checkout" ]]' 'the session link still points at the checkout'
check '[[ $(readlink -- "$link") != "$link" ]]' 'the session link does not point at itself'
check '[[ -d "$link/install" ]]' 'the link is still usable'
check '! compgen -G "$link.backup-*" > /dev/null' 'a second run takes no backup'
check 'grep -q "Already installed" "$sandbox/second.log"' 'the second run reports the links as installed'

# ---- a link that would point at itself is refused -------------------------
selfhome="$sandbox/selfhome"
selfdir="$selfhome/.local/share/buchhwin-shell"
mkdir -p "$selfdir/install"
cp "$project_dir/install/install.sh" "$selfdir/install/"
if HOME="$selfhome" XDG_CONFIG_HOME="$selfhome/.config" \
   "$selfdir/install/install.sh" --apply > "$sandbox/self.log" 2>&1; then
  printf 'FAIL install: a self-referential link was not refused\n'
  failures=$((failures + 1))
else
  check 'grep -q "onto itself" "$sandbox/self.log"' 'the refusal says what it refused'
  check '[[ -d "$selfdir" && ! -L "$selfdir" ]]' 'the checkout is left alone'
fi

# ---- XDG_CONFIG_HOME and XDG_DATA_HOME elsewhere ---------------------------
# systemd, xdg-desktop-portal, zsh and the shell itself read from the XDG
# directories, so a user who moved them used to get links in ~/.config that
# nothing ever read. The session link itself stays at ~/.local/share, the name
# every script and the session entry use.
xdghome="$sandbox/xdghome"
xdgcheckout="$xdghome/.local/share/buchhwin-shell-stable"
mkdir -p "$xdgcheckout"
cp -r "$checkout/." "$xdgcheckout/"
HOME="$xdghome" XDG_CONFIG_HOME="$sandbox/xdg/config" XDG_DATA_HOME="$sandbox/xdg/data" \
  "$xdgcheckout/install/install.sh" --apply > "$sandbox/xdg.log" 2>&1 \
  || { printf 'FAIL install: --apply with XDG dirs elsewhere exited non-zero\n'; cat "$sandbox/xdg.log"; exit 1; }
check '[[ -L "$sandbox/xdg/config/systemd/user/buchhwin-shell-session.target" ]]' 'the systemd target goes under XDG_CONFIG_HOME'
check '[[ -L "$sandbox/xdg/config/xdg-desktop-portal/buchhwin-shell-portals.conf" ]]' 'the portal configuration too'
check '[[ -L "$sandbox/xdg/config/buchhwin-shell/shell.zsh" ]]' 'and the zsh fragment'
check '[[ -f "$sandbox/xdg/config/buchhwin-shell/layout.json" ]]' 'layout.json is created under XDG_CONFIG_HOME'
check '[[ -r "$sandbox/xdg/config/buchhwin-shell/fastfetch.jsonc" ]]' 'the Fastfetch configuration too'
check '[[ ! -e "$xdghome/.config" ]]' 'nothing is written to ~/.config when XDG_CONFIG_HOME is elsewhere'
check '[[ -L "$sandbox/xdg/data/zsh/site-functions/_buchhwin" ]]' 'the completion goes under XDG_DATA_HOME'
check '[[ $(readlink -f -- "$xdghome/.local/share/buchhwin-shell") == "$xdgcheckout" ]]' 'the session link stays at ~/.local/share/buchhwin-shell'
check '[[ -L "$xdghome/.local/bin/buchhwin" ]]' 'and the launchers at ~/.local/bin'

if [[ $failures -gt 0 ]]; then
  printf 'install test: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'install test: ok\n'
