#!/usr/bin/env bash
set -euo pipefail

# Install the macOS-style cursor theme (ful1e5/apple_cursor, GPL-3.0) into
# ~/.local/share/icons for the current user. Nothing system-wide is changed.
repo="ful1e5/apple_cursor"
target="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

printf 'Looking up the latest %s release …\n' "$repo"
url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
  | grep -oE '"browser_download_url": *"[^"]*macOS\.tar\.xz"' \
  | sed -E 's/.*"(https[^"]+)"/\1/' | head -n1)
if [[ -z $url ]]; then
  printf 'Could not find macOS.tar.xz in the latest release.\n' >&2
  exit 1
fi

printf 'Downloading %s\n' "$url"
curl -fL --progress-bar -o "$work/macOS.tar.xz" "$url"
tar -xJf "$work/macOS.tar.xz" -C "$work"
mkdir -p -- "$target"
for theme in "$work"/macOS*; do
  [[ -d $theme && -f $theme/index.theme && -d $theme/cursors ]] || continue
  name=$(basename -- "$theme")
  if [[ -e $target/$name ]]; then
    mv -- "$target/$name" "$target/$name.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  cp -r -- "$theme" "$target/$name"
  printf 'Installed %s\n' "$target/$name"
done
printf 'Done. Choose the cursor in buchhwin-shell Settings > Appearance.\n'
