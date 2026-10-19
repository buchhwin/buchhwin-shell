#!/usr/bin/env bash
set -euo pipefail

# install/plasma-terminal.sh in a sandbox home with a stand-in kwriteconfig6.
# The home is laid out like a stow-managed one: ~/.zshrc and the KDE
# shortcuts file are links into a dotfiles checkout, and ~/.config/alacritty
# is a linked directory. --apply used to move the links aside, write the
# Alacritty profile into the checkout and point kwriteconfig6 through the
# link, so the checkout - not this machine - got the changes.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
script="$project_dir/install/plasma-terminal.sh"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-plasmaterm.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL plasma-terminal: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
mkdir -p "$bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$KWRITE_LOG"\n' > "$bin/kwriteconfig6"
chmod +x "$bin/kwriteconfig6"
export PATH="$bin:$PATH" KWRITE_LOG="$sandbox/kwrite.log"
if [[ $(command -v kwriteconfig6) != "$bin/kwriteconfig6" ]]; then
  printf 'plasma-terminal test: the stand-in kwriteconfig6 is not first in PATH, refusing to run\n' >&2
  exit 1
fi

# make_home NAME: a stow-like home under $sandbox/NAME; prints its path.
make_home() {
  local home="$sandbox/$1" dots="$sandbox/$1-dotfiles"
  mkdir -p "$home/.config" "$dots/alacritty" "$dots/kde"
  printf '# my zshrc\n' > "$dots/zshrc"
  printf '# my alacritty\n' > "$dots/alacritty/alacritty.toml"
  printf '[services]\n' > "$dots/kde/kglobalshortcutsrc"
  ln -s "$dots/zshrc" "$home/.zshrc"
  ln -s "$dots/alacritty" "$home/.config/alacritty"
  ln -s "$dots/kde/kglobalshortcutsrc" "$home/.config/kglobalshortcutsrc"
  printf '%s\n' "$home"
}
in_home() { local home=$1; shift; HOME="$home" XDG_CONFIG_HOME="$home/.config" "$@"; }

home=$(make_home stow)
dots="$sandbox/stow-dotfiles"
: > "$KWRITE_LOG"
dry=$(in_home "$home" "$script")
check '[[ $dry == *"kept     $home/.zshrc (symlink to $dots/zshrc"* ]]' "the dry run keeps a linked file and says where it points ($dry)"
check '[[ $dry == *"kept     $home/.config/alacritty/alacritty.toml (symlink to $dots/alacritty/alacritty.toml"* ]]' \
  'and a file in a linked directory'
check '[[ $dry == *"new      $home/.config/starship.toml"* ]]' 'and installs what is not linked'
check '[[ $dry == *"default terminal would stay as it is"* ]]' 'and leaves Plasma'"'"'s terminal while a KDE file is a link'
check '[[ ! -s $KWRITE_LOG ]]' 'the dry run writes nothing'

out=$(in_home "$home" "$script" --apply)
check '[[ -L $home/.zshrc && $(cat "$dots/zshrc") == "# my zshrc" ]]' '--apply keeps the linked ~/.zshrc and its target'
check '! compgen -G "$home/.zshrc.backup-*" >/dev/null' 'and moves no link aside'
check '[[ $(cat "$dots/alacritty/alacritty.toml") == "# my alacritty" ]] && ! compgen -G "$dots/alacritty/*.backup-*" >/dev/null' \
  'nothing is written into the linked directory'
check '[[ -f $home/.config/starship.toml && ! -L $home/.config/starship.toml ]]' 'the files that are not linked are installed'
check 'cmp -s "$project_dir/terminal/kitty-plasma.conf" "$home/.config/kitty/kitty.conf"' 'kitty'"'"'s profile among them'
check '[[ ! -s $KWRITE_LOG && $(cat "$dots/kde/kglobalshortcutsrc") == "[services]" ]]' \
  'kwriteconfig6 does not write through the linked shortcuts file'
check '[[ $out == *"default terminal was left as it is"* ]]' 'and the run says so'

# Without the KDE links Plasma's terminal is set as before.
rm -f -- "$home/.config/kglobalshortcutsrc"
: > "$KWRITE_LOG"
in_home "$home" "$script" --apply >/dev/null
check '[[ $(grep -c . "$KWRITE_LOG") -eq 4 ]] && grep -q "kitty.desktop --key _launch Ctrl+Alt+T" "$KWRITE_LOG"' \
  'with plain KDE files kwriteconfig6 sets kitty and Ctrl+Alt+T'

# --force replaces the links, backing them up as any other file.
home=$(make_home forced)
dots="$sandbox/forced-dotfiles"
: > "$KWRITE_LOG"
in_home "$home" "$script" --apply --force >/dev/null
check '[[ -f $home/.zshrc && ! -L $home/.zshrc ]] && compgen -G "$home/.zshrc.backup-*" >/dev/null' '--force replaces a linked file and keeps the link as a backup'
check '[[ $(grep -c . "$KWRITE_LOG") -eq 4 ]]' 'and writes the KDE files'

# A home directory that is itself a link (/home is one on some systems) is
# no dotfiles checkout.
real_home="$sandbox/real-home"
mkdir -p "$real_home/.config"
ln -s "$real_home" "$sandbox/home-link"
linked_dry=$(in_home "$sandbox/home-link" "$script")
check '[[ $linked_dry != *kept* && $linked_dry == *"new      $sandbox/home-link/.zshrc"* ]]' "a linked home directory keeps nothing ($linked_dry)"

status=0; in_home "$home" "$script" --aply >/dev/null 2>&1 || status=$?
check '[[ $status -eq 2 ]]' 'an unknown option is refused'

if (( failures )); then
  printf 'TESTS FAILED plasma-terminal (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED plasma-terminal\n'
