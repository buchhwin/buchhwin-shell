#!/usr/bin/env bash
set -euo pipefail

# reload-shell.sh and stop-shell.sh against stub commands in a sandbox. What is
# under test is which shell they act on, and with what. Both redirect to the
# copy the session runs from when BUCHHWIN_SHELL_PATH is unset - and
# docs/testing.md once had you export the nested WAYLAND_DISPLAY, signature
# and XDG dirs without ever mentioning BUCHHWIN_SHELL_PATH, so a hand-run from
# a development checkout inside a nested session used to stop the shell on the
# user's own screen and start a replacement pointed at the nested display.
# That happened.
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
# `list` names an instance once the checkout's start-shell.sh has run, and a
# `kill` ends it: a reload then returns after one start, and no late second
# start lands in the next case's log.
cat > "$bin/quickshell" <<'EOF'
#!/bin/sh
printf 'quickshell %s\n' "$*" >> "$CALLS"
case "$1" in
  kill) rm -f "$CALLS.up" ;;
  list) [ -e "$CALLS.up" ] && echo '[{"id":"stand-in"}]' ;;
esac
exit 0
EOF
# pgrep answers from the environment: $SHELL_PIDS for a shell's command line,
# $PACMAN_PIDS for a package manager, nothing otherwise - never the host's.
cat > "$bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in
  *"pacman|paru|yay"*) [ -n "${PACMAN_PIDS:-}" ] || exit 1; printf '%s\n' $PACMAN_PIDS ;;
  *"^quickshell "*) [ -n "${SHELL_PIDS:-}" ] || exit 1; printf '%s\n' $SHELL_PIDS ;;
  *) exit 1 ;;
esac
EOF
# The user manager: the units in $ACTIVE_UNITS are running.
cat > "$bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$CALLS"
case "$*" in
  *is-active*)
    for unit in ${ACTIVE_UNITS:-}; do case " $* " in *" $unit "*) exit 0 ;; esac; done
    exit 3 ;;
esac
exit 0
EOF
cat > "$bin/notify-send" <<'EOF'
#!/bin/sh
printf 'notify-send %s\n' "$*" >> "$CALLS"
EOF
# reload-shell.sh starts the shell in a transient scope; the stub runs what
# follows `--` in place, so nothing reaches the host's user manager.
cat > "$bin/systemd-run" <<'EOF'
#!/bin/sh
printf 'systemd-run %s\n' "$*" >> "$CALLS"
while [ $# -gt 0 ] && [ "$1" != "--" ] && [ "$1" != "true" ]; do shift; done
[ "$1" = "--" ] && shift
exec "$@"
EOF
# hyprctl lists the instances in $HYPR_INSTANCES (`hyprctl instances` text),
# none otherwise - never the host's.
cat > "$bin/hyprctl" <<'EOF'
#!/bin/sh
[ "$1" = instances ] && [ -n "${HYPR_INSTANCES:-}" ] && printf '%b' "$HYPR_INSTANCES"
exit 0
EOF
chmod +x "$bin"/*
export PATH="$bin:$PATH"
# The sessions the cases name, each with its compositor socket, in a runtime
# directory of the sandbox: reload-shell.sh only acts inside a Hyprland
# session whose socket is there.
runtime="$sandbox/run"
for signature in real-signature nested-signature other-vt-signature; do
  mkdir -p "$runtime/hypr/$signature"
  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$runtime/hypr/$signature/.socket.sock"
done
# A Hyprland still running on another VT names its display in its lock file
# (pid, then socket, as Hyprland writes it).
printf '1\nwayland-1\n' > "$runtime/hypr/other-vt-signature/hyprland.lock"
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
# The checkout's start-shell.sh records how it was started: its arguments,
# its environment and its working directory.
# Written aside and moved, so a reader never sees half of it.
printf '#!/bin/sh\npwd > "$CALLS.pwd"; env > "$CALLS.env.part"; mv -f "$CALLS.env.part" "$CALLS.env"\nprintf "start-shell %%s\\n" "$*" >> "$CALLS"\ntouch "$CALLS.up"\nexit 0\n' > "$checkout/scripts/start-shell.sh"
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
    -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_START_WITHOUT_HYPRLAND -u HYPR_INSTANCES \
    -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME -u BUCHHWIN_NESTED_MODE \
    CALLS="$calls" HOME="$home" XDG_RUNTIME_DIR="$runtime" \
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

# A reload of the checkout's own shell starts it in a transient scope of its
# own, not in the caller's (an editor's or a terminal's).
rm -f -- "$nested/wayland-display" "$nested/instance"
: > "$calls"
sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature BUCHHWIN_SHELL_PATH="$checkout" \
  bash "$checkout/scripts/reload-shell.sh" >"$sandbox/out.log" 2>&1 || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^systemd-run --user --scope --quiet --collect --unit buchhwin-shell-[0-9]*-[0-9]* -- "' 'reload starts the shell in a scope of its own'
check 'said "^start-shell '"$checkout"'$"' 'and that scope runs start-shell.sh for the checkout'

# ---- half of a nested session's environment ----------------------------------
# The nested signature without the nested display (the testing recipe once
# exported just that), or the other way round: quickshell looks for the shell
# on the display, found none on the user's screen and started a second
# development shell there. Refused, for reload and stop alike.
echo "wayland-9" > "$nested/wayland-display"
echo "nested-signature" > "$nested/instance"
for script in reload-shell.sh stop-shell.sh; do
  for mixed in "WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=nested-signature" \
               "WAYLAND_DISPLAY=wayland-9 HYPRLAND_INSTANCE_SIGNATURE=real-signature"; do
    : > "$calls"
    # shellcheck disable=SC2086
    if sandboxed $mixed BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/$script" >"$sandbox/out.log" 2>"$sandbox/err.log"; then
      printf 'FAIL shell-control: %s did not refuse %s\n' "$script" "$mixed"
      failures=$((failures + 1))
    fi
    check '! said "^quickshell kill" && ! said "^start-shell"' "$script acts on no shell with $mixed"
    check 'grep -q "different sessions" "$sandbox/err.log"' "$script says why ($mixed)"
  done
done

# ---- a reload for the nested session ---------------------------------------------
# What the recipe once had you export - the nested signature and display and
# BUCHHWIN_SHELL_PATH, no XDG dirs and no BUCHHWIN_NESTED: the restarted shell
# took itself for a real session and ran on the user's own configuration
# (pitfall 121). Refused now, before anything is stopped.
: > "$calls"
status=0
sandboxed "${nestedenv[@]}" BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" \
  >"$sandbox/out.log" 2>"$sandbox/err.log" || status=$?
check '[[ $status -ne 0 ]] && ! said "^quickshell kill" && ! said "^start-shell"' \
  "a nested reload without the sandbox's XDG dirs is refused before anything is stopped (status $status)"
check 'grep -q "XDG dirs outside its sandbox" "$sandbox/err.log"' "and says why ($(cat "$sandbox/err.log"))"
# With what nested-session.sh prints (here without BUCHHWIN_NESTED, which the
# reload adds itself): the checkout's shell, as a nested one, on the sandbox.
rm -f "$calls.env"
: > "$calls"
sandboxed "${nestedenv[@]}" BUCHHWIN_SHELL_PATH="$checkout" XDG_CONFIG_HOME="$nested/config" \
  XDG_STATE_HOME="$nested/state" XDG_CACHE_HOME="$nested/cache" \
  bash "$checkout/scripts/reload-shell.sh" >"$sandbox/out.log" 2>"$sandbox/err.log" || true
for _ in {1..20}; do [[ -s $calls.env ]] && break; sleep 0.1; done
check 'said "^start-shell '"$checkout"'$"' "a nested reload with the sandbox's XDG dirs starts the checkout's shell"
check 'grep -qx BUCHHWIN_NESTED=1 "$calls.env" && grep -qx "XDG_CONFIG_HOME=$nested/config" "$calls.env" && grep -qx "XDG_STATE_HOME=$nested/state" "$calls.env"' \
  "and starts it as a nested shell on the sandbox"
# The session's own copy acts on itself whatever BUCHHWIN_SHELL_PATH says.
# Run as the deploy runs it - from the stable worktree that the session link
# points at - with the nested exports and BUCHHWIN_SHELL_PATH at a checkout,
# it got past the guard and started a second installed shell in the nested
# compositor. Refused, for reload and stop alike.
stable="$sandbox/stable"
home2="$sandbox/home2"
mkdir -p "$stable/scripts/lib" "$home2/.local/share"
cp "$project_dir/scripts/reload-shell.sh" "$project_dir/scripts/stop-shell.sh" "$stable/scripts/"
cp "$project_dir/scripts/lib/nested-guard.sh" "$stable/scripts/lib/"
cp "$checkout/scripts/start-shell.sh" "$stable/scripts/"
touch "$stable/shell.qml"
ln -s "$stable" "$home2/.local/share/buchhwin-shell"
for script in reload-shell.sh stop-shell.sh; do
  : > "$calls"
  status=0
  sandboxed "${nestedenv[@]}" HOME="$home2" BUCHHWIN_SHELL_PATH="$checkout" XDG_CONFIG_HOME="$nested/config" \
    XDG_STATE_HOME="$nested/state" XDG_CACHE_HOME="$nested/cache" \
    bash "$stable/scripts/$script" >"$sandbox/out.log" 2>"$sandbox/err.log" || status=$?
  check '[[ $status -ne 0 ]] && ! said "^quickshell kill" && ! said "^start-shell"' \
    "the stable copy's $script refuses the nested environment although BUCHHWIN_SHELL_PATH names a checkout (status $status)"
  check 'grep -q "nested session" "$sandbox/err.log"' "and the stable copy's $script says why"
done
rm -f -- "$nested/wayland-display" "$nested/instance"

# ---- no Hyprland session --------------------------------------------------------
# Run from Plasma - no Hyprland at all, a signature the user manager kept from
# the last Hyprland login, or the one instance on another display - a reload
# stopped nothing and started the shell on KWin's display, after ending
# Plasma's kded6. Refused before anything is stopped,
# and said. The tests' opt-in goes on as before.
no_session() {   # no_session LABEL ENV...
  local label=$1 status=0; shift
  : > "$calls"
  sandboxed "$@" BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" \
    >"$sandbox/out.log" 2>"$sandbox/err.log" || status=$?
  check '[[ $status -ne 0 ]] && ! said "^quickshell kill" && ! said "^start-shell"' "$label: reload refuses and touches no shell (status $status)"
  check 'grep -q "no Hyprland session here" "$sandbox/err.log"' "$label: and says why ($(cat "$sandbox/err.log"))"
}
no_session "no Hyprland at all" WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE
no_session "a signature whose socket is gone" WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=gone-signature
no_session "a live signature of another display" WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=other-vt-signature
no_session "the one instance on another display" WAYLAND_DISPLAY=wayland-0 HYPR_INSTANCES='instance real-signature:\n\twl socket: wayland-1\n'
# the one instance on this display is the session
: > "$calls"
sandboxed WAYLAND_DISPLAY=wayland-1 HYPR_INSTANCES='instance real-signature:\n\twl socket: wayland-1\n' BUCHHWIN_SHELL_PATH="$checkout" \
  bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^quickshell kill" && said "^start-shell"' "the one instance on this display is a session to reload"
# a signature whose lock file names this display is the session too
: > "$calls"
sandboxed WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=other-vt-signature BUCHHWIN_SHELL_PATH="$checkout" \
  bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^quickshell kill" && said "^start-shell"' "a signature on this display is a session to reload"
# the tests' way past the check
: > "$calls"
sandboxed BUCHHWIN_START_WITHOUT_HYPRLAND=1 BUCHHWIN_SHELL_PATH="$checkout" \
  bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^start-shell"' "BUCHHWIN_START_WITHOUT_HYPRLAND=1 reloads without a session"

# ---- what the shell is started with --------------------------------------------
# Not the caller's own environment: a deploy from an editor by a coding agent
# gave the live shell - and every application it started - the agent's
# variables and session token, ELECTRON_RUN_AS_NODE and VSCODE_*. Those go;
# everything else stays, so nothing the session set is lost. And it starts in
# the home directory, as from Hyprland, not in the deploying checkout.
mkdir -p "$home"
reload_env() {
  : > "$calls"; rm -f "$calls.env" "$calls.pwd"
  ( cd "$checkout" && sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
      BUCHHWIN_SHELL_PATH="$checkout" "$@" bash "$checkout/scripts/reload-shell.sh" >"$sandbox/out.log" 2>"$sandbox/err.log" ) || true
  for _ in {1..20}; do [[ -s $calls.env ]] && break; sleep 0.1; done
}
started_with() { grep -qx -- "$1" "$calls.env"; }
started_without() { ! grep -q -- "^$1=" "$calls.env"; }
reload_env CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s CLAUDE_CODE_MESSAGING_TOKEN=t CLAUDE_PID=7 AI_AGENT=a \
  ELECTRON_RUN_AS_NODE=1 VSCODE_PID=9 VSCODE_GIT_IPC_HANDLE=/h GIT_ASKPASS=/vscode/askpass.sh CHROME_DESKTOP=code.desktop \
  TERM_PROGRAM=vscode TERM_PROGRAM_VERSION=1.2 KITTY_WINDOW_ID=3 INVOCATION_ID=abc JOURNAL_STREAM=8:9 \
  QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=buchhwin-shell:Hyprland SSH_AUTH_SOCK=/agent \
  ELECTRON_OZONE_PLATFORM_HINT=wayland SESSION_OWN=kept
check '[[ -s $calls.env ]]' "the shell was started at all"
for name in CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_PID AI_AGENT ELECTRON_RUN_AS_NODE \
    VSCODE_PID VSCODE_GIT_IPC_HANDLE GIT_ASKPASS CHROME_DESKTOP TERM_PROGRAM TERM_PROGRAM_VERSION KITTY_WINDOW_ID \
    INVOCATION_ID JOURNAL_STREAM; do
  check 'started_without "$name"' "the shell is started without the caller's $name"
done
for kept in QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=buchhwin-shell:Hyprland SSH_AUTH_SOCK=/agent \
    ELECTRON_OZONE_PLATFORM_HINT=wayland SESSION_OWN=kept WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature; do
  check 'started_with "$kept"' "and with the session's $kept"
done
check '[[ $(cat "$calls.pwd" 2>/dev/null) == "$home" ]]' "in the home directory, not the caller's ($(cat "$calls.pwd" 2>/dev/null))"
# A GIT_ASKPASS that is not VS Code's is the session's; a ZDOTDIR is the
# window's only when it is a buchhwin checkout's (the session kitty) or VS
# Code's in front of the user's own.
mkdir -p "$sandbox/kitty-tree/scripts" "$sandbox/kitty-tree/zsh" "$sandbox/userzsh"
printf '#!/bin/sh\n' > "$sandbox/kitty-tree/scripts/launch-kitty.sh"; chmod +x "$sandbox/kitty-tree/scripts/launch-kitty.sh"
reload_env GIT_ASKPASS=/usr/bin/ksshaskpass ZDOTDIR="$sandbox/userzsh"
check 'started_with GIT_ASKPASS=/usr/bin/ksshaskpass && started_with "ZDOTDIR=$sandbox/userzsh"' "the session's own GIT_ASKPASS and ZDOTDIR stay"
# An agent's shell runs git without an editor (GIT_EDITOR=true): a terminal
# opened from the launcher then could not write a commit message. Its
# corepack setting and the editor's GTK accessibility switch go too, and the
# extension host's own variables; a session's own values of the same names
# stay when no agent or editor is the caller.
reload_env CLAUDECODE=1 VSCODE_PID=9 GIT_EDITOR=true COREPACK_ENABLE_AUTO_PIN=0 NO_AT_BRIDGE=1 EGL_PLATFORM=wayland FC_FONTATIONS=1 \
  COPILOT_OTEL_FILE_EXPORTER_PATH=/dev/null MCP_CONNECTION_NONBLOCKING=true APPLICATION_INSIGHTS_NO_STATSBEAT=true \
  MXC_BIN_DIR=/code/bin NoDefaultCurrentDirectoryInExePath=1
for name in GIT_EDITOR COREPACK_ENABLE_AUTO_PIN NO_AT_BRIDGE EGL_PLATFORM FC_FONTATIONS COPILOT_OTEL_FILE_EXPORTER_PATH MCP_CONNECTION_NONBLOCKING \
    APPLICATION_INSIGHTS_NO_STATSBEAT MXC_BIN_DIR NoDefaultCurrentDirectoryInExePath; do
  check 'started_without "$name"' "the shell is started without the agent's or editor's $name"
done
# (Whoever runs this test may be an agent in an editor: its own names go first.)
( for name in $(compgen -e); do
    case $name in CLAUDECODE | VSCODE_*) unset "$name" ;; esac
  done
  reload_env GIT_EDITOR=nvim COREPACK_ENABLE_AUTO_PIN=0 NO_AT_BRIDGE=1 COPILOT_MODEL=own )
check 'started_with GIT_EDITOR=nvim && started_with COREPACK_ENABLE_AUTO_PIN=0 && started_with NO_AT_BRIDGE=1 && started_with COPILOT_MODEL=own' \
  "the session's own editor, corepack, accessibility and Copilot settings stay"
# Whatever else a caller keeps for itself goes by its kind - a token, a key,
# a password, a cloud CLI's settings, an activated Python environment and its
# place in PATH, a preload - and Hyprland's own token stays.
reload_env GH_TOKEN=gh OPENAI_API_KEY=k DB_PASSWORD=p MY_SECRET_FILE=/s AWS_PROFILE=dev \
  VIRTUAL_ENV=/work/.venv VIRTUAL_ENV_PROMPT=venv CONDA_PREFIX=/opt/conda CONDA_DEFAULT_ENV=base \
  PYTHONPATH=/work NODE_OPTIONS=--inspect LD_PRELOAD=/lib/libfake.so HL_INITIAL_WORKSPACE_TOKEN=hl \
  PATH="/work/.venv/bin:/opt/conda/bin:$PATH"
for name in GH_TOKEN OPENAI_API_KEY DB_PASSWORD MY_SECRET_FILE AWS_PROFILE VIRTUAL_ENV VIRTUAL_ENV_PROMPT \
    CONDA_PREFIX CONDA_DEFAULT_ENV PYTHONPATH NODE_OPTIONS LD_PRELOAD; do
  check 'started_without "$name"' "the shell is started without the caller's $name"
done
check 'started_with HL_INITIAL_WORKSPACE_TOKEN=hl' "and with Hyprland's own HL_INITIAL_WORKSPACE_TOKEN"
check '! grep -q "^PATH=.*/work/.venv/bin" "$calls.env" && ! grep -q "^PATH=.*/opt/conda/bin" "$calls.env" && grep -q "^PATH=$bin:" "$calls.env"' \
  "and with PATH without the environments' bin directories ($(grep '^PATH=' "$calls.env" 2>/dev/null))"
reload_env ZDOTDIR="$sandbox/kitty-tree/zsh"
check 'started_without ZDOTDIR' "the session kitty's zsh profile does not"
reload_env ZDOTDIR=/tmp/vscode-zsh USER_ZDOTDIR="$sandbox/userzsh"
check 'started_without ZDOTDIR && started_without USER_ZDOTDIR' "nor VS Code's shell integration"

# ---- the shell found by its display ---------------------------------------------
# A quickshell of the same path on another display (a nested session runs the
# checkout too) is not waited for; one on this display is, until it goes.
env WAYLAND_DISPLAY=wayland-other sleep 30 & other_display=$!
env WAYLAND_DISPLAY=wayland-0 sleep 30 & same_display=$!
sleep 0.2
: > "$calls"
SHELL_PIDS=$other_display sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
  BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 &
reload=$!
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^start-shell"' "another display's shell of the same path is not waited for"
kill "$reload" 2>/dev/null || true; wait "$reload" 2>/dev/null || true
: > "$calls"
SHELL_PIDS=$same_display sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
  BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 &
reload=$!
sleep 1.5
check '! said "^start-shell"' "this display's shell is waited for"
kill "$same_display" 2>/dev/null || true; wait "$same_display" 2>/dev/null || true
for _ in {1..30}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^start-shell"' "and the new one starts once it is gone"
kill "$reload" "$other_display" 2>/dev/null || true; wait "$reload" "$other_display" 2>/dev/null || true

# ---- an upgrade in a terminal ----------------------------------------------------
# The page's terminals are units of their own now: said, and the reload goes
# ahead. A pacman below the shell being replaced (a shell from before that,
# whose kitty is its own child) would be ended mid-transaction: refused, and
# said in a notification, since Super+Ctrl+R has no terminal.
: > "$calls"
ACTIVE_UNITS=buchhwin-upgrade sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
  BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" >"$sandbox/out.log" 2>"$sandbox/err.log" || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'grep -q "buchhwin-upgrade.service is running" "$sandbox/err.log" && said "^start-shell"' "a running upgrade unit is named, and the reload goes ahead"
bash -c 'sleep 30 & echo $! > "$1"; wait' sh "$sandbox/pacman.pid" & fake_shell=$!
for _ in {1..20}; do [[ -s $sandbox/pacman.pid ]] && break; sleep 0.05; done
fake_pacman=$(cat "$sandbox/pacman.pid")
: > "$calls"
status=0
SHELL_PIDS=$fake_shell PACMAN_PIDS=$fake_pacman sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
  BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" >"$sandbox/out.log" 2>"$sandbox/err.log" || status=$?
check '[[ $status -ne 0 ]] && ! said "^quickshell kill" && ! said "^start-shell"' "a pacman below the shell refuses the reload (status $status)"
check 'grep -q "package upgrade (pid $fake_pacman)" "$sandbox/err.log" && said "^notify-send .*The shell was not restarted"' "and says so, in a notification too"
: > "$calls"
sleep 30 & unrelated=$!
SHELL_PIDS=$unrelated PACMAN_PIDS=$fake_pacman sandboxed WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=real-signature \
  BUCHHWIN_SHELL_PATH="$checkout" bash "$checkout/scripts/reload-shell.sh" >/dev/null 2>&1 || true
for _ in {1..20}; do said "^start-shell" && break; sleep 0.1; done
check 'said "^quickshell kill" && said "^start-shell"' "a pacman elsewhere does not"
kill "$fake_pacman" "$fake_shell" "$unrelated" 2>/dev/null || true; wait "$fake_shell" "$unrelated" 2>/dev/null || true

if (( failures )); then
  printf 'shell-control: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'shell-control: ok\n'
