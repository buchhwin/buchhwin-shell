#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy.sh against a throwaway clone and a fake HOME: --init creates
# the stable worktree and points the session links at it, a deploy
# fast-forwards and restarts the shell only for shell files, --rollback returns
# to the previous commit, and dirty or diverged states are refused. systemctl,
# hyprctl, quickshell and everything the shell's start reaches are stubs, so
# nothing reaches the real session.
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
# reload-shell.sh starts the (stub) shell detached; give it a moment to finish.
cleanup() { rm -rf -- "$work" 2>/dev/null || { sleep 1; rm -rf -- "$work"; }; }
trap cleanup EXIT

fail() { printf 'deploy-test: %s\n' "$*" >&2; exit 1; }

mkdir -p "$work/home"
# Every tool that would reach the host's session is a stand-in that records
# its call. reload-shell.sh starts the clone's real start-shell.sh, and that
# would otherwise run in a scope of the real user manager (systemd-run,
# setsid), end a real kded6 holding the tray (busctl) and reap real helpers
# of the user's on its way out (pgrep, pkill) - the header's promise did not
# hold for those (16.10.). systemd-run and setsid run what they are given in
# place; `quickshell list` names an instance once one was started and until
# a `kill`, so a reload returns after one start; systemctl knows no unit as
# running; pgrep finds nothing.
mkdir -p "$work/bin"
for tool in busctl pkill notify-send; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$tool" "$work" > "$work/bin/$tool"
done
# hyprctl lists no instance (`-j instances` answers for the stand-in nested
# compositor below, once its pid file is there).
cat > "$work/bin/hyprctl" <<EOF
#!/bin/sh
echo "hyprctl \$*" >> "$work/calls.log"
if [ "\$*" = "-j instances" ] && [ -s "$work/nested/hyprland.pid" ]; then
  printf '[{"instance":"nested-stub","pid":%s,"wl_socket":"wayland-nested-stub"}]\n' "\$(cat "$work/nested/hyprland.pid")"
fi
exit 0
EOF
# The stand-in nested compositor: it only lives, with the environment
# nested-session.sh gives it.
printf '#!/bin/sh\nexec sleep 30\n' > "$work/bin/Hyprland"
cat > "$work/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >> "$work/calls.log"
case "\$*" in *is-active*) exit 3 ;; esac
exit 0
EOF
cat > "$work/bin/pgrep" <<EOF
#!/bin/sh
echo "pgrep \$*" >> "$work/calls.log"
exit 1
EOF
cat > "$work/bin/quickshell" <<EOF
#!/bin/sh
echo "quickshell \$*" >> "$work/calls.log"
case "\$1" in
  kill) rm -f "$work/up" ;;
  list) [ -e "$work/up" ] && echo '[{"id":"stand-in"}]' ;;
  *) touch "$work/up" ;;
esac
exit 0
EOF
cat > "$work/bin/systemd-run" <<EOF
#!/bin/sh
echo "systemd-run \$*" >> "$work/calls.log"
while [ \$# -gt 0 ] && [ "\$1" != "--" ] && [ "\$1" != "true" ]; do shift; done
[ "\$1" = "--" ] && shift
exec "\$@"
EOF
cat > "$work/bin/setsid" <<EOF
#!/bin/sh
echo "setsid \$*" >> "$work/calls.log"
[ "\$1" = "-f" ] && shift
exec "\$@"
EOF
chmod +x "$work/bin"/*
export PATH="$work/bin:$PATH" HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
# A Hyprland session of the test's own: its signature and socket in a runtime
# directory of the sandbox (the shell is only restarted inside a session,
# round 12, scripts#0). The nested sandbox goes there too.
export HYPRLAND_INSTANCE_SIGNATURE=deploy-test BUCHHWIN_SHELL_PATH= XDG_RUNTIME_DIR="$work/run"
mkdir -p -m 700 "$XDG_RUNTIME_DIR/hypr/deploy-test" "$XDG_RUNTIME_DIR/hypr/nested-stub"
for sig in deploy-test nested-stub; do
  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$XDG_RUNTIME_DIR/hypr/$sig/.socket.sock"
done
unset XDG_STATE_HOME BUCHHWIN_NESTED BUCHHWIN_NESTED_DIR BUCHHWIN_START_WITHOUT_HYPRLAND BUCHHWIN_NESTED_FRESH
# The shell's own settings and its record of them, from a caller the shell
# started, would send start-shell.sh to the user manager (a stub here too).
unset MALLOC_ARENA_MAX mesa_glthread GALLIUM_THREAD QS_ICON_THEME BUCHHWIN_APP_ENV_UNSET BUCHHWIN_APP_QPA_THEME
for tool in systemctl hyprctl quickshell systemd-run setsid busctl pgrep pkill Hyprland; do
  [[ $(command -v "$tool") == "$work/bin/$tool" ]] || fail "the $tool stub is not first in PATH"
done

dev="$work/dev"
git clone --quiet --no-hardlinks "$project_dir" "$dev"
git -C "$dev" checkout --quiet -B main HEAD
git -C "$dev" config user.email test@example.invalid
git -C "$dev" config user.name test
# The clone's own copy of the script under test (with the working tree version)
# and of what they source: reload-shell.sh and stop-shell.sh call guards from
# nested-guard.sh, and with the committed one a new guard was "command not
# found", which an `if` reads as false - the reload went ahead unguarded.
cp "$project_dir/scripts/deploy.sh" "$project_dir/scripts/reload-shell.sh" \
  "$project_dir/scripts/stop-shell.sh" "$project_dir/scripts/start-shell.sh" \
  "$project_dir/scripts/nested-session.sh" "$dev/scripts/"
mkdir -p "$dev/scripts/lib" && cp "$project_dir/scripts/lib/reload.sh" "$project_dir/scripts/lib/app-env.sh" \
  "$project_dir/scripts/lib/nested-guard.sh" "$dev/scripts/lib/"
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
# The restart went through the stand-ins, and only once.
grep -q "^setsid -f env .*systemd-run --user --scope .* -- $BUCHHWIN_STABLE_DIR/scripts/start-shell.sh\|^setsid -f env .*systemd-run --user --scope .*/buchhwin-shell/scripts/start-shell.sh" "$work/calls.log" \
  || fail "the shell was not started through the stand-in scope"
[[ $(grep -c '^quickshell --no-duplicate' "$work/calls.log") == 1 ]] || fail "the shell was started $(grep -c '^quickshell --no-duplicate' "$work/calls.log") times, wanted once"
grep -q '^busctl --user --auto-start=no list' "$work/calls.log" || fail "start-shell.sh did not ask the stand-in bus"
deployed=$(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD)

# What the running shell never reads restarts nothing: the page's files, the
# terminals' zsh files, the completion. A unit change reloads the user
# manager instead (the shell never loads the units).
mkdir -p "$dev/.github" "$dev/zsh" "$dev/systemd"
echo "x" >> "$dev/.github/note.txt"; echo "# x" >> "$dev/zsh/buchhwin.zsh"; echo "x" >> "$dev/LICENSE"
git -C "$dev" add -A && git -C "$dev" commit --quiet -m "chore: page and terminal files"
: > "$work/calls.log"
out=$(deploy --no-test)
grep -q 'quickshell kill' "$work/calls.log" && fail "a deploy of .github/, zsh/ and LICENSE restarted the shell"
grep -q 'No shell files changed' <<<"$out" || fail "and did not say so ($out)"
echo "# x" >> "$dev/systemd/buchhwin-shell-session.target"
git -C "$dev" commit --quiet -am "chore: a unit"
: > "$work/calls.log"
out=$(deploy --no-test)
grep -q '^systemctl --user daemon-reload' "$work/calls.log" || fail "a unit change did not reload the user manager"
grep -q 'quickshell kill' "$work/calls.log" && fail "a unit change restarted the shell"
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
# An untracked file the commit does not carry: the suite would test it, stable
# would not get it (round 12, scripts#1). Ignored files do not count.
git -C "$dev" commit --quiet --allow-empty -m "chore: before an untracked file"
echo "Item {}" > "$dev/shell/NotAdded.qml"
echo "x" > "$dev/scratch.log"
out=$(deploy --no-test --no-reload 2>&1) && fail "an untracked file must be refused"
grep -q 'shell/NotAdded.qml' <<<"$out" || fail "and named ($out)"
grep -q 'scratch.log' <<<"$out" && fail "an ignored file is not named ($out)"
rm -f "$dev/shell/NotAdded.qml"
deploy --no-test --no-reload >/dev/null || fail "an ignored file alone does not refuse the deploy"
rm -f "$dev/scratch.log"

# No Hyprland session here (a deploy run from Plasma, or with the signature
# of a Hyprland that has gone): stable moves, the shell is neither stopped
# nor started, and the output says when it will be (round 12, scripts#0).
echo "// test" >> "$dev/shell.qml"
git -C "$dev" commit --quiet -am "fix: a shell change without a session"
: > "$work/calls.log"
out=$(env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE "$dev/scripts/deploy.sh" --no-test 2>&1) \
  || fail "a deploy without a session failed ($out)"
[[ $(git -C "$BUCHHWIN_STABLE_DIR" rev-parse HEAD) == $(git -C "$dev" rev-parse main) ]] || fail "the deploy without a session did not move stable"
grep -q 'No Hyprland session found' <<<"$out" || fail "the deploy without a session did not say so ($out)"
grep -q '^quickshell \|start-shell\|^busctl' "$work/calls.log" && fail "a deploy without a session touched the shell or the bus"
echo "// test" >> "$dev/shell.qml"
git -C "$dev" commit --quiet -am "fix: a shell change with a gone signature"
: > "$work/calls.log"
out=$(HYPRLAND_INSTANCE_SIGNATURE=gone-signature deploy --no-test 2>&1) || fail "a deploy with a gone signature failed ($out)"
grep -q 'No Hyprland session found' <<<"$out" || fail "a gone signature is no session ($out)"
grep -q '^quickshell ' "$work/calls.log" && fail "a deploy with a gone signature touched the shell"
: > "$work/calls.log"
out=$(env -u HYPRLAND_INSTANCE_SIGNATURE "$dev/scripts/deploy.sh" --init 2>&1) || fail "--init without a session failed ($out)"
grep -q 'No Hyprland session found' <<<"$out" || fail "--init without a session did not say so ($out)"
grep -q '^quickshell ' "$work/calls.log" && fail "--init without a session touched the shell"
# reload-shell.sh itself refuses there, before it stops anything.
: > "$work/calls.log"
env -u HYPRLAND_INSTANCE_SIGNATURE "$BUCHHWIN_STABLE_DIR/scripts/reload-shell.sh" >/dev/null 2>"$work/err.log" \
  && fail "reload-shell.sh without a session must refuse"
grep -q 'no Hyprland session here' "$work/err.log" || fail "and say why ($(cat "$work/err.log"))"
grep -q '^quickshell ' "$work/calls.log" && fail "reload-shell.sh without a session touched the shell"

# The deploy's nested sandbox starts empty (BUCHHWIN_NESTED_FRESH, which
# deploy.sh passes to the suite): settings.json and layout.json of the last
# run are gone, a seeded settings.json keeps the welcome tour out, and
# without the flag the sandbox is kept (pitfall 92; round 12, scripts#6).
# Driven against the stand-in compositor above - nothing nested starts.
nested() { env BUCHHWIN_NESTED_DIR="$work/nested" WAYLAND_DISPLAY=wayland-parent-stub "$@"; }
seeded='{ "configVersion": 1, "onboarding": { "completed": true } }'
nested BUCHHWIN_NESTED_FRESH=1 "$dev/scripts/nested-session.sh" start >/dev/null || fail "the stand-in nested session did not start"
[[ $(cat "$work/nested/config/buchhwin-shell/settings.json" 2>/dev/null) == "$seeded" ]] || fail "a first fresh start is not seeded"
nested "$dev/scripts/nested-session.sh" stop
echo '{ "stale": true }' > "$work/nested/config/buchhwin-shell/settings.json"
echo '{ "stale": true }' > "$work/nested/config/buchhwin-shell/layout.json"
mkdir -p "$work/nested/state/buchhwin-shell" && echo stale > "$work/nested/state/buchhwin-shell/launcher.json"
nested "$dev/scripts/nested-session.sh" start >/dev/null || fail "the stand-in nested session did not start again"
grep -q stale "$work/nested/config/buchhwin-shell/settings.json" || fail "without BUCHHWIN_NESTED_FRESH the sandbox is not kept"
nested BUCHHWIN_NESTED_FRESH=1 "$dev/scripts/nested-session.sh" start >/dev/null || fail "the stand-in nested session did not restart fresh"
[[ $(cat "$work/nested/config/buchhwin-shell/settings.json" 2>/dev/null) == "$seeded" ]] || fail "a fresh start keeps the last settings.json"
[[ ! -e $work/nested/config/buchhwin-shell/layout.json && ! -e $work/nested/state/buchhwin-shell/launcher.json ]] \
  || fail "a fresh start keeps the last layout or state"
nested "$dev/scripts/nested-session.sh" stop
grep -q 'start-shell.sh' "$work/nested/hypr/hyprland.conf" 2>/dev/null || fail "the sandbox's conf does not start start-shell.sh"

# reload-shell.sh from the development checkout acts on the stable copy.
: > "$work/calls.log"
"$dev/scripts/reload-shell.sh" >/dev/null 2>&1 || true
grep -q "quickshell kill --path $HOME/.local/share/buchhwin-shell" "$work/calls.log" \
  || fail "reload from the development checkout did not target the session copy"

printf 'deploy test ok\n'
