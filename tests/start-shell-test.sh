#!/usr/bin/env bash
# scripts/start-shell.sh watches the shell it starts: a crash comes back, a
# clean exit and a SIGTERM do not, and five restarts in a minute is the end of
# it. A stand-in `quickshell` on PATH plays each of those parts, because what
# is being tested is the supervision and not the shell.
#
# It matters because quickshell really does crash: six SIGSEGVs in one day on
# 2026-09-22, every one of them inside Qt's own HTTP/2 header parser. Before
# this, the desktop simply had no shell afterwards.
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 1
SB=$(mktemp -d); trap 'rm -rf -- "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/cfg" "$SB/state/buchhwin-shell"
touch "$SB/cfg/shell.qml"
# `list` says the instance is still there for $LINGER more calls (the lag
# after a crash before quickshell drops the dead instance), then not.
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
if [[ ${1:-} == list ]]; then
  l=$(cat "$LINGER" 2>/dev/null || echo 0)
  (( l > 0 )) || exit 1
  echo $((l-1)) > "$LINGER"; echo '[{"id":"stale"}]'; exit 0
fi
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
echo "run $n"
if (( n <= ${CRASHES:-0} )); then kill -SEGV $$; fi
exit ${FINAL_EXIT:-0}
Q
chmod +x "$SB/bin/quickshell"
export PATH="$SB/bin:$PATH" XDG_STATE_HOME="$SB/state" COUNT="$SB/count" LINGER="$SB/linger"
echo 0 > "$LINGER"
fail=0
check() { if eval "$1"; then :; else printf 'FAIL: %s\n' "$2"; fail=1; fi; }

# two crashes then a clean exit: three runs
echo 0 > "$COUNT"; CRASHES=2 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 3 ]]' "a crash is restarted (got $(cat "$COUNT") runs, wanted 3)"
check 'grep -q "died on signal 11, restarting (1 of 5)" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'

# after a crash the dead instance may still be listed for a moment; the
# restart waits for it to go rather than starting a --no-duplicate shell that
# exits 0 against it (which then reads as a clean exit and ends the watch)
echo 0 > "$COUNT"; echo 6 > "$LINGER"; CRASHES=1 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 2 ]]' "the restart still happens (got $(cat "$COUNT") runs, wanted 2)"
check '[[ $(cat "$LINGER") == 0 ]]' "and only after the lingering instance was gone ($(cat "$LINGER") list answers unused)"
echo 0 > "$LINGER"

# a clean exit is not restarted
echo 0 > "$COUNT"; CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "a clean exit stops (got $(cat "$COUNT"))"

# SIGTERM is a request, not a fault
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
kill -TERM $$
Q
chmod +x "$SB/bin/quickshell"
echo 0 > "$COUNT"; bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "SIGTERM is not restarted (got $(cat "$COUNT"))"

# the brake holds
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
kill -SEGV $$
Q
chmod +x "$SB/bin/quickshell"
echo 0 > "$COUNT"; timeout 60 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 6 ]]' "it gives up after five restarts (got $(cat "$COUNT"), wanted 6 runs)"
check 'grep -q "not restarting it again" "$SB/state/buchhwin-shell/quickshell.log"' 'and says why'
# a crash while the compositor is gone is not restarted: with a signature and
# no socket for it, the shell stays down
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
kill -SEGV $$
Q
chmod +x "$SB/bin/quickshell"
mkdir -p "$SB/run/hypr/sig-gone"
echo 0 > "$COUNT"; HYPRLAND_INSTANCE_SIGNATURE=sig-gone XDG_RUNTIME_DIR="$SB/run" timeout 30 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "no compositor, no restart (got $(cat "$COUNT"))"
check 'grep -q "the compositor is gone" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'

# with the compositor's socket present the same crash is restarted
mkdir -p "$SB/run/hypr/sig-alive"
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SB/run/hypr/sig-alive/.socket.sock"
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
if (( n <= 1 )); then kill -SEGV $$; fi
exit 0
Q
chmod +x "$SB/bin/quickshell"
echo 0 > "$COUNT"; HYPRLAND_INSTANCE_SIGNATURE=sig-alive XDG_RUNTIME_DIR="$SB/run" timeout 30 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 2 ]]' "compositor alive, the crash is restarted (got $(cat "$COUNT"))"

# SIGTERM to the supervisor reaches the shell and ends the watching - even
# when the shell then dies on a fault signal, as Quickshell does on the way out
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == list ]] && exit 1
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
trap 'kill -SEGV $$' TERM
while true; do sleep 0.1; done
Q
chmod +x "$SB/bin/quickshell"
echo 0 > "$COUNT"
bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1 &
sup=$!
sleep 1
kill -TERM "$sup"
for _ in {1..50}; do kill -0 "$sup" 2>/dev/null || break; sleep 0.1; done
check '! kill -0 "$sup" 2>/dev/null' 'the supervisor ends on SIGTERM'
check '[[ $(cat "$COUNT") == 1 ]]' "and does not restart the shell it was told to stop (got $(cat "$COUNT"))"
check 'grep -q "asked to stop" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says it was asked'
pkill -f "$SB/bin/quickshell" 2>/dev/null || true

(( fail )) && exit 1
echo "TESTS PASSED start-shell supervision"
