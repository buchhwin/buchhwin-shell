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
for part in install session scripts shell-completion zsh systemd session/xdg-desktop-portal; do
  mkdir -p "$checkout/$part"
done
cp "$project_dir/install/install.sh" "$checkout/install/"
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

if [[ $failures -gt 0 ]]; then
  printf 'install test: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'install test: ok\n'
