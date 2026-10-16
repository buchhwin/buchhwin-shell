#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
# The session's own shell is never a nested test's to touch. The environment
# that makes this possible is the one docs/testing.md tells you to export - the
# nested WAYLAND_DISPLAY, signature and XDG dirs - while BUCHHWIN_SHELL_PATH,
# the only thing that otherwise keeps this script local, is not mentioned there
# at all. Without this guard, running it from a development checkout inside a
# nested session stops the shell on the user's own screen and, in the case of
# reload, starts a replacement pointed at the nested display.
if [[ $(readlink -f "${BUCHHWIN_SHELL_PATH:-$installed_dir}") == "$(readlink -f "$installed_dir")" ]] \
   && nested_environment; then
  printf 'reload-shell: the environment points at a nested session; refusing to act on %s\n' "$installed_dir" >&2
  printf 'reload-shell: set BUCHHWIN_SHELL_PATH to say which shell you mean\n' >&2
  exit 1
fi
# Half of a nested session's environment is refused too (see
# nested_mixed_environment for the 16.10. case): a signature and a display of
# two different sessions mean no shell at all.
if nested_mixed_environment; then
  printf 'reload-shell: HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY belong to different sessions; refusing\n' >&2
  printf 'reload-shell: for the nested session export both (and its XDG dirs) from scripts/nested-session.sh start\n' >&2
  exit 1
fi
# No Hyprland session here - a reload or a deploy run from Plasma, or with a
# signature of a Hyprland that has gone: there is no shell of this session to
# restart, and start-shell.sh would refuse the new one anyway (it used to
# start it on KWin's display, and end Plasma's kded6 first; round 12,
# scripts#0). Said, and nothing is stopped. Before the redirect below, so an
# older session copy without the check is not reached either. Tests that run
# stand-in shells outside any session say BUCHHWIN_START_WITHOUT_HYPRLAND=1.
if [[ ${BUCHHWIN_START_WITHOUT_HYPRLAND:-0} != 1 ]] && ! hyprland_session >/dev/null; then
  printf 'reload-shell: no Hyprland session here (WAYLAND_DISPLAY %s); the shell is left alone and starts with the next Hyprland login\n' \
    "${WAYLAND_DISPLAY:-unset}" >&2
  exit 1
fi
# Called from another checkout (the development repository while the session
# runs from the stable worktree, see scripts/deploy.sh): act on the session's
# own copy instead of starting or stopping a shell from this checkout.
if [[ ${BUCHHWIN_SHELL_PATH:-$installed_dir} == "$installed_dir" && -x "$installed_dir/scripts/reload-shell.sh" \
      && $(readlink -f "$installed_dir") != "$(readlink -f "$project_dir")" ]]; then
  exec "$installed_dir/scripts/reload-shell.sh" "$@"
fi
if [[ -e "$installed_dir/shell.qml" && $(readlink -f "$installed_dir") == "$project_dir" ]]; then
  config_dir="$installed_dir"
else
  config_dir=${BUCHHWIN_SHELL_PATH:-$project_dir}
fi
# Absolute: the shell starts from the home directory below.
[[ $config_dir == /* ]] || config_dir="$PWD/$config_dir"
# pgrep -f takes a regular expression; the path is a literal, so every
# character that means something to an ERE is escaped first (a checkout in a
# directory such as `worktrees/x+y` used to match the wrong thing, or nothing).
config_pattern=$(printf '%s' "$config_dir" | sed 's,[][\.*^$+?(){}|\\],\\&,g')
shell_pids() { pgrep -u "$(id -u)" -f "^quickshell .*--path ${config_pattern}$" 2>/dev/null || true; }

# Settings > Updates runs its terminals as user services of their own
# (scripts/launch-app.sh --unit), which a restart leaves alone; it is said all
# the same. A pacman below the running shell is another matter: a shell from
# before that change (16.10.) has the terminal as its own child, and stopping
# the shell ends the terminal and the transaction in it - pacman stops between
# packages and skips its hooks, a new kernel without its initramfs. Refused,
# and said where Super+Ctrl+R can see it.
for unit in buchhwin-upgrade buchhwin-flatpak-update; do
  if systemctl --user -q is-active "$unit" 2>/dev/null; then
    printf 'reload-shell: %s.service is running; it is not part of the shell and keeps running\n' "$unit" >&2
  fi
done
upgrade_below_shell() {
  local shells pid parent
  shells=" $(shell_pids | tr '\n' ' ') "
  [[ $shells == *[0-9]* ]] || return 1
  for pid in $(pgrep -x 'pacman|paru|yay' 2>/dev/null || true); do
    parent=$pid
    for _ in {1..40}; do
      parent=$(awk '/^PPid:/ { print $2 }' "/proc/$parent/status" 2>/dev/null) || break
      [[ $parent =~ ^[0-9]+$ ]] && (( parent > 1 )) || break
      if [[ $shells == *" $parent "* ]]; then
        printf '%s' "$pid"
        return 0
      fi
    done
  done
  return 1
}
if upgrading=$(upgrade_below_shell); then
  message="a package upgrade (pid $upgrading) runs in a terminal the shell started, and a restart would end it halfway; restart the shell once it has finished"
  printf 'reload-shell: %s\n' "$message" >&2
  if command -v notify-send >/dev/null 2>&1; then
    timeout 5 notify-send --app-name=buchhwin-shell --icon=dialog-warning -- "The shell was not restarted" "${message^}." 2>/dev/null || true
  fi
  exit 1
fi

quickshell kill --path "$config_dir" 2>/dev/null || true
# Quickshell acknowledges the IPC request before the old process has fully
# released its instance lock, and a busy shell can take several seconds to
# exit. Wait for it (up to 10 s): a replacement started too early exits at
# once because of --no-duplicate and leaves the session without a shell.
# The list is captured before it is matched: `| grep -q` quits at the first
# match and leaves quickshell with SIGPIPE, which pipefail reads as "gone"
# (pitfall 15, as in start-shell.sh).
#
# A quickshell of the same path on another display is not this one: a nested
# session runs the development checkout too, and a reload of the shell on the
# user's screen waited the full 10 s for the nested one to go.
instance_running() {
  local listed pid line display
  for pid in $(shell_pids); do
    display=""
    while IFS= read -r -d '' line; do
      if [[ $line == WAYLAND_DISPLAY=* ]]; then display=${line#*=}; fi
    done 2>/dev/null <"/proc/$pid/environ" || continue
    [[ $display == "${WAYLAND_DISPLAY:-}" ]] && return 0
  done
  listed=$(quickshell list --path "$config_dir" --json 2>/dev/null) || listed=""
  [[ $listed == *'"id"'* ]]
}
for _ in {1..200}; do
  instance_running || break
  sleep 0.05
done
# start-shell.sh rotates quickshell.log for the new instance.
#
# In a scope of its own: run from a terminal or an editor, the shell used to
# land in that application's scope (`app-<its id>-….scope`) and to share its
# fate when that scope is stopped. The restart key (Hyprland's
# exec) and session-init.sh start it from the login session anyway. Without a
# user manager to ask it starts as before.
#
# And without the caller's own environment. The shell keeps what it is started
# with, and every application it starts inherits it: run from an editor or by
# a coding agent, the live shell and everything opened from it carried the
# caller's variables - an agent's session token among them,
# ELECTRON_RUN_AS_NODE=1 and an editor's VSCODE_* - and an agent's CLI in a
# terminal opened from the launcher took itself for a nested session and kept
# no history. The names that belong to whoever ran this - an agent, an editor, a
# terminal window, a systemd unit - are left out; everything else stays, so
# nothing the session set is lost (the shell's own settings that a caller
# from the shell carries are start-shell.sh's to undo). The working directory
# is the home directory, as from Hyprland: it was the deploying checkout, and
# a terminal opened from the launcher started there.
caller_only=()
editor_only=()
vscode=0
vscode_git=0
for name in $(compgen -e); do
  case $name in
    VSCODE_GIT_*) vscode=1 vscode_git=1 ;;
    VSCODE_*) vscode=1 ;;
  esac
  case $name in
    CLAUDECODE | CLAUDE_* | AI_AGENT \
      | ELECTRON_RUN_AS_NODE | ELECTRON_NO_ATTACH_CONSOLE | CHROME_DESKTOP | VSCODE_* | USER_ZDOTDIR \
      | TERM_PROGRAM | TERM_PROGRAM_VERSION | KITTY_WINDOW_ID | KITTY_PID | KITTY_LISTEN_ON | KITTY_PUBLIC_KEY \
      | ALACRITTY_WINDOW_ID | ALACRITTY_SOCKET | WINDOWID | TMUX | TMUX_PANE \
      | INVOCATION_ID | JOURNAL_STREAM | SYSTEMD_EXEC_PID | MANAGERPID | NOTIFY_SOCKET)
      caller_only+=(-u "$name") ;;
    # What VS Code's extension host hands its agents and terminals: Copilot's
    # and the agent's switches, Electron's GTK accessibility switch.
    COPILOT_* | MCP_CONNECTION_NONBLOCKING | APPLICATION_INSIGHTS_NO_STATSBEAT | MXC_BIN_DIR \
      | NoDefaultCurrentDirectoryInExePath | NO_AT_BRIDGE)
      editor_only+=(-u "$name") ;;
  esac
done
# Those go only when VS Code is the caller; a session may set one itself.
if (( vscode )); then caller_only+=("${editor_only[@]}"); fi
# VS Code's askpass helper is gone once VS Code is; git in a terminal opened
# later asked it all the same. A GIT_ASKPASS of the session's own stays.
if (( vscode_git )) && [[ -n ${GIT_ASKPASS+set} ]]; then caller_only+=(-u GIT_ASKPASS); fi
# An agent's shell has no editor: GIT_EDITOR=true, and a `git commit` in a
# terminal opened from the launcher then aborted for an empty message.
# Nobody's session chooses `true` for an editor. An agent that sets
# CLAUDECODE also turns corepack's pinning off; that stays unless such an
# agent is the caller.
if [[ ${GIT_EDITOR-} == true ]]; then caller_only+=(-u GIT_EDITOR); fi
if [[ -n ${CLAUDECODE+set} && -n ${COREPACK_ENABLE_AUTO_PIN+set} ]]; then caller_only+=(-u COREPACK_ENABLE_AUTO_PIN); fi
# The zsh profile of a buchhwin checkout (launch-kitty.sh), or the one VS
# Code's shell integration puts in front of the user's (USER_ZDOTDIR): the
# window's, not the session's.
if [[ -n ${ZDOTDIR:-} ]]; then
  if [[ -x "$(dirname -- "$ZDOTDIR")/scripts/launch-kitty.sh" ]] \
     || [[ -n ${USER_ZDOTDIR:-} && $ZDOTDIR != "$USER_ZDOTDIR" ]]; then
    caller_only+=(-u ZDOTDIR)
  fi
fi
start_shell() {
  if systemd-run --user --scope --quiet --collect true >/dev/null 2>&1; then
    ( cd -- "$HOME" 2>/dev/null || cd /
      setsid -f env "${caller_only[@]}" systemd-run --user --scope --quiet --collect --unit "buchhwin-shell-$$-$RANDOM" \
        -- "$project_dir/scripts/start-shell.sh" "$config_dir" </dev/null >/dev/null 2>&1 )
  else
    ( cd -- "$HOME" 2>/dev/null || cd /
      nohup env "${caller_only[@]}" "$project_dir/scripts/start-shell.sh" "$config_dir" >/dev/null 2>&1 & )
  fi
}
start_shell
# If the old instance still held the lock, the new one exited; try once more.
for _ in {1..40}; do
  sleep 0.1
  instance_running && exit 0
done
start_shell
