#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy.sh against a throwaway clone and a fake HOME: --init creates
# the stable worktree and points the session links at it, a deploy
# fast-forwards and restarts the shell only for shell files, --rollback returns
# to the previous commit, and dirty or diverged states are refused. systemctl,
# hyprctl and quickshell are stubs, so nothing reaches the real session.
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
# reload-shell.sh starts the (stub) shell detached; give it a moment to finish.
cleanup() { rm -rf -- "$work" 2>/dev/null || { sleep 1; rm -rf -- "$work"; }; }
trap cleanup EXIT

fail() { printf 'deploy-test: %s\n' "$*" >&2; exit 1; }

mkdir -p "$work/bin" "$work/home"
for tool in systemctl hyprctl quickshell; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$tool" "$work" > "$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH="$work/bin:$PATH" HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
export HYPRLAND_INSTANCE_SIGNATURE=deploy-test BUCHHWIN_SHELL_PATH=
unset XDG_STATE_HOME
[[ $(command -v systemctl) == "$work/bin/systemctl" ]] || fail "stubs are not first in PATH"

dev="$work/dev"
git clone --quiet --no-hardlinks "$project_dir" "$dev"
git -C "$dev" checkout --quiet -B main HEAD
git -C "$dev" config user.email test@example.invalid
git -C "$dev" config user.name test
# The clone's own copy of the script under test (with the working tree version).
cp "$project_dir/scripts/deploy.sh" "$project_dir/scripts/reload-shell.sh" \
  "$project_dir/scripts/stop-shell.sh" "$dev/scripts/"
git -C "$dev" add -A && git -C "$dev" commit --quiet -m "test: current scripts" || true
export BUCHHWIN_STABLE_DIR="$work/home/.local/share/buchhwin-shell-stable"
deploy() { "$dev/scripts/deploy.sh" "$@"; }

deploy --status | grep -q 'No stable worktree' || fail "status without worktree"
deploy --no-test --no-reload >/dev/null 2>&1 && fail "deploy without worktree must fail"

deploy --init --no-reload >/dev/null
[[ -e $BUCHHWIN_STABLE_DIR/.git ]] || fail "stable worktree missing"
[[ $(readlink -f "$HOME/.local/share/buchhwin-shell") == "$BUCHHWIN_STABLE_DIR" ]] || fail "session link not on stable"
[[ $(readlink -f "$HOME/.local/bin/buchhwin-shell-session") == "$BUCHHWIN_STABLE_DIR/session/buchhwin-shell-session" ]] \
  || fail "launcher link not on stable"
[[ $(git -C "$dev" rev-parse stable) == $(git -C "$dev" rev-parse main) ]] || fail "stable not at main"

# A docs-only change deploys without restarting the shell.
echo "docs" >> "$dev/README.md"
git -C "$dev" commit --quiet -am "docs: change"
: > "$work/calls.log"
deploy --no-test >/dev/null
[[ $(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD) == $(git -C "$dev" rev-parse main) ]] || fail "docs deploy not applied"
grep -q 'quickshell kill' "$work/calls.log" && fail "docs deploy restarted the shell"
grep -q 'hyprctl reload' "$work/calls.log" && fail "docs deploy reloaded Hyprland"

# A deploy that changed no file at all restarts nothing. An empty diff is one
# empty line to a here-string, and `grep -v` matched it against nothing and
# succeeded - so this said "Restarted the shell." for a commit that touched
# nothing, using the very predicate that keeps a docs-only deploy quiet.
git -C "$dev" commit --quiet --allow-empty -m "chore: nothing at all"
: > "$work/calls.log"
deploy --no-test >/dev/null
[[ $(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD) == $(git -C "$dev" rev-parse main) ]] || fail "empty deploy not applied"
grep -q 'quickshell kill' "$work/calls.log" && fail "a deploy that changed nothing restarted the shell"
grep -q 'hyprctl reload' "$work/calls.log" && fail "a deploy that changed nothing reloaded Hyprland"

# A shell and Hyprland change restarts both.
echo "// test" >> "$dev/shell.qml"
echo "# test" >> "$dev/hypr/hyprland.conf"
git -C "$dev" commit --quiet -am "fix: shell and hypr change"
: > "$work/calls.log"
deploy --no-test >/dev/null
grep -q 'quickshell kill --path' "$work/calls.log" || fail "shell deploy did not restart the shell"
grep -q 'hyprctl reload' "$work/calls.log" || fail "hypr deploy did not reload Hyprland"
deployed=$(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD)

# Rollback returns to the previous deployment, a second rollback goes forward again.
deploy --rollback --no-reload >/dev/null
[[ $(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD) == $(git -C "$dev" rev-parse main~1) ]] || fail "rollback target"
deploy --rollback --no-reload >/dev/null
[[ $(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD) == "$deployed" ]] || fail "second rollback target"

# Refusals: uncommitted changes in the development checkout, local changes in
# stable, a non-fast-forward target, running from the stable worktree.
echo "dirty" >> "$dev/README.md"
git -C "$dev" commit --quiet --allow-empty -m "chore: empty"
deploy --no-test --no-reload >/dev/null 2>&1 && fail "dirty development checkout must be refused"
git -C "$dev" checkout --quiet -- README.md
echo "local" >> "$BUCHHWIN_STABLE_DIR/README.md"
deploy --no-test --no-reload >/dev/null 2>&1 && fail "dirty stable worktree must be refused"
git -C "$BUCHHWIN_STABLE_DIR" checkout --quiet -- README.md
git -C "$dev" checkout --quiet -b diverged "$(git -C "$dev" rev-parse main~3)"
echo "other" >> "$dev/README.md"
git -C "$dev" commit --quiet -am "diverged"
deploy --no-test --no-reload --ref diverged >/dev/null 2>&1 && fail "non-fast-forward deploy must be refused"
git -C "$dev" checkout --quiet main
"$BUCHHWIN_STABLE_DIR/scripts/deploy.sh" --status >/dev/null 2>&1 && fail "deploy from the stable worktree must be refused"

# reload-shell.sh from the development checkout acts on the stable copy.
: > "$work/calls.log"
"$dev/scripts/reload-shell.sh" >/dev/null 2>&1 || true
grep -q "quickshell kill --path $HOME/.local/share/buchhwin-shell" "$work/calls.log" \
  || fail "reload from the development checkout did not target the session copy"

printf 'deploy test ok\n'
