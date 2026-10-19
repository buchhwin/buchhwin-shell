#!/usr/bin/env bash
set -euo pipefail

# For CI: every service and theme singleton of the shell, loaded offscreen
# from a copy of the repository the way the shell loads them, so that an
# import a distribution's Quickshell lacks or a type error in a service fails
# a job - in the session such a service takes the whole shell down (the
# calendar's once did). The QML unit tests load only what each test touches,
# and NetworkService (Quickshell.Networking) was in none of them.
#
# Not the components under shell/: their PanelWindows cannot be made without
# a Wayland compositor (testing.md, pitfall 87), and one that fails makes
# its whole module "not installed". That takes a headless compositor.
#
# Not for a developer's machine: the services start their helpers and talk
# to the system bus (logind inhibitors, NetworkManager, UDisks) as the real
# shell does, beside the real one. It refuses to run outside GitHub Actions
# unless BUCHHWIN_LOAD_ISOLATED=1 says this is a sandbox of its own (no /run,
# no home, a network of its own - a bwrap, say).
#
#   tests/ci-load-services.sh [SECONDS]     how long the services run (15)
if [[ ${GITHUB_ACTIONS:-} != true && ${BUCHHWIN_LOAD_ISOLATED:-0} != 1 ]]; then
  printf 'ci-load-services: refusing outside CI - the services would reach this machine'"'"'s system bus.\n' >&2
  printf 'Set BUCHHWIN_LOAD_ISOLATED=1 only inside a sandbox of its own.\n' >&2
  exit 2
fi
seconds=${1:-15}
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-load.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
root="$sandbox/root"
mkdir -p "$root" "$sandbox/config" "$sandbox/state" "$sandbox/cache"
mkdir -m 700 "$sandbox/run"
tar -C "$project_dir" --exclude=.git -cf - . | tar -C "$root" -xf -

# One property per singleton: reading it makes the singleton, as the first
# use in the shell would.
singletons=()
for file in "$project_dir"/services/*.qml "$project_dir"/theme/*.qml; do
  grep -q '^pragma Singleton' "$file" || continue
  singletons+=("$(basename -- "$file" .qml)")
done
(( ${#singletons[@]} > 40 )) || { printf 'ci-load-services: only %d singletons found\n' "${#singletons[@]}" >&2; exit 1; }
{
  printf 'import QtQuick\nimport Quickshell\nimport qs.services\nimport qs.theme\n\nScope {\n'
  for name in "${singletons[@]}"; do printf '    readonly property var load%s: %s\n' "$name" "$name"; done
  printf '    Component.onCompleted: console.info("SERVICES LOADED: %d")\n}\n' "${#singletons[@]}"
} > "$root/__load__.qml"

# A private session bus; no compositor, no display, no Hyprland. The helpers
# the services start fail here, which is not what this checks: their stderr
# (the services log it as "... stderr:") is left out of the verdict. The
# display goes before the bus is started: what the bus activates (the
# portals) has the bus daemon's environment, not quickshell's.
output="$sandbox/output.log"
status=0
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_SHELL_PATH dbus-run-session -- env \
  QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME="$sandbox/config" XDG_STATE_HOME="$sandbox/state" \
  XDG_CACHE_HOME="$sandbox/cache" XDG_RUNTIME_DIR="$sandbox/run" \
  timeout --kill-after=5 "$seconds" quickshell -p "$root/__load__.qml" >"$output" 2>&1 || status=$?

failures='TypeError|ReferenceError|SyntaxError|is not a type|is not installed|[Ff]ailed to load|Unable to assign|Cannot assign|Binding loop|recursive rearrange'
problems=$(grep -v 'stderr: ' "$output" | grep -E "$failures") || problems=""
if ! grep -q "SERVICES LOADED: ${#singletons[@]}" "$output"; then
  cat "$output"
  printf 'ci-load-services: the services did not load (quickshell exited %d)\n' "$status" >&2
  exit 1
fi
if [[ -n $problems ]]; then
  printf '%s\n' "$problems"
  printf 'ci-load-services: %d service problem line(s) above\n' "$(grep -c . <<<"$problems")" >&2
  exit 1
fi
printf 'ci-load-services: %d services and theme singletons loaded\n' "${#singletons[@]}"
