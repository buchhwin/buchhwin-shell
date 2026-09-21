#!/usr/bin/env bash
set -euo pipefail

# reload-shell.sh and stop-shell.sh against stub commands in a sandbox. What is
# under test is which shell they act on. Both redirect to the copy the session
# runs from when BUCHHWIN_SHELL_PATH is unset - and docs/testing.md has you
# export the nested WAYLAND_DISPLAY, signature and XDG dirs without ever
# mentioning BUCHHWIN_SHELL_PATH, so a hand-run from a development checkout
# inside a nested session used to stop the shell on the user's own screen and
# start a replacement pointed at the nested display. That happened.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-controltest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL shell-control: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
mkdir -p "$bin"
cat > "$bin/quickshell" <<'EOF'
#!/bin/sh
printf 'quickshell %s\n' "$*" >> "$CALLS"
exit 0
EOF
cat > "$bin/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$bin"/*
export PATH="$bin:$PATH"
if [[ $(command -v quickshell) != "$bin/quickshell" ]]; then
  printf 'shell-control test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

# A development checkout and the copy the session runs from, each with the real
# scripts. The installed copy's own reload/stop only record that they ran, so a
# redirect is visible as itself rather than as its effects.
home="$sandbox/home"
checkout="$sandbox/checkout"
installed="$home/.local/share/buchhwin-shell"
mkdir -p "$checkout/scripts/lib" "$installed/scripts"
for name in reload-shell.sh stop-shell.sh; do
  cp "$project_dir/scripts/$name" "$checkout/scripts/"
  printf '#!/bin/sh\nprintf "redirected %s\\n" >> "$CALLS"\nexit 0\n' "$name" > "$installed/scripts/$name"
done
cp "$project_dir/scripts/lib/nested-guard.sh" "$checkout/scripts/lib/"
printf '#!/bin/sh\nprintf "start-shell %%s\\n" "$*" >> "$CALLS"\nexit 0\n' > "$checkout/scripts/start-shell.sh"
chmod +x "$checkout/scripts/"*.sh "$installed/scripts/"*.sh
touch "$installed/shell.qml"

# A nested session, as scripts/nested-session.sh leaves it on disk.
nested="$sandbox/nested"
mkdir -p "$nested"
echo "wayland-9" > "$nested/wayland-display"
echo "nested-signature" > "$nested/instance"
echo 1 > "$nested/hyprland.pid"

# The sandbox has to be the whole environment, not most of it. The user's own
# session exports BUCHHWIN_SHELL_PATH - it is how a terminal inside the session
# knows which shell it belongs to - so a test that leaves it through is testing
# the caller's machine and not the script. It cost an hour: the case below that
# passes BUCHHWIN_NESTED=1 silently answered "no refusal" because the leaked
# value had already sent the script down a different branch.
sandboxed() {
  env -u BUCHHWIN_SHELL_PATH -u BUCHHWIN_NESTED -u WAYLAND_DISPLAY \
    -u HYPRLAND_INSTANCE_SIGNATURE CALLS="$calls" HOME="$home" \
    BUCHHWIN_NESTED_DIR="$nested" "$@"
}

run() {
  local script=$1; shift
  : > "$calls"
  sandboxed "$@" bash "$checkout/scripts/$script" \
    >"$sandbox/out.log" 2>"$sandbox/err.log"
}
said() { grep -q "$1" "$calls"; }

# The environment the testing recipe tells you to export, and nothing else.
nestedenv=(WAYLAND_DISPLAY=wayland-9 HYPRLAND_INSTANCE_SIGNATURE=nested-signature)

for script in reload-shell.sh stop-shell.sh; do
  if run "$script" "${nestedenv[@]}"; then
    printf 'FAIL shell-control: %s did not refuse inside a nested session\n' "$script"
    failures=$((failures + 1))
  fi
  check '! said "redirected"' "$script does not redirect to the session's copy from a nested session"
  check '! said "^quickshell kill"' "$script kills nothing from a nested session"
  check 'grep -q "nested session" "$sandbox/err.log"' "$script says why it refused"
done

# The same environment with BUCHHWIN_SHELL_PATH: the caller has said which
# shell they mean, so the checkout's own is acted on and the session's is not.
: > "$calls"
sandboxed "${nestedenv[@]}" BUCHHWIN_SHELL_PATH="$checkout" \
  bash "$checkout/scripts/stop-shell.sh" >"$sandbox/out.log" 2>&1
check 'said "^quickshell kill --path '"$checkout"'$"' "with BUCHHWIN_SHELL_PATH set, the checkout's own shell is stopped"
check '! said "redirected"' 'and the session copy is left alone'

# Outside a nested session the redirect is still what it always was: deploy.sh
# runs these from the development checkout while the session runs from stable.
run stop-shell.sh WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature
check 'said "redirected stop-shell.sh"' 'in the real session it still redirects to the session copy'

# A nested session that has been stopped leaves no display file behind, so the
# guard must not keep refusing afterwards.
rm -f -- "$nested/wayland-display" "$nested/instance"
run stop-shell.sh WAYLAND_DISPLAY=wayland-9 HYPRLAND_INSTANCE_SIGNATURE=nested-signature
check 'said "redirected stop-shell.sh"' 'a stopped nested session does not block the real one'

# BUCHHWIN_NESTED alone is enough, whatever the display says.
echo "wayland-9" > "$nested/wayland-display"
: > "$calls"
if sandboxed BUCHHWIN_NESTED=1 WAYLAND_DISPLAY=wayland-0 \
   bash "$checkout/scripts/stop-shell.sh" >"$sandbox/out.log" 2>&1; then
  printf 'FAIL shell-control: BUCHHWIN_NESTED=1 did not refuse\n'
  failures=$((failures + 1))
fi
check '! said "redirected"' 'BUCHHWIN_NESTED=1 refuses on its own'

if (( failures )); then
  printf 'shell-control: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'shell-control: ok\n'
