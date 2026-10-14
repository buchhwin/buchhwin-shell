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
# Resolved, so the helper patterns below carry one spelling of the path.
SB=$(readlink -f -- "$(mktemp -d)"); trap 'rm -rf -- "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/cfg" "$SB/state/buchhwin-shell"
touch "$SB/cfg/shell.qml"
# `list` says the instance is still there for $LINGER more calls (the lag
# after a crash before quickshell drops the dead instance), then not. It says
# so at length - far more than a pipe holds - because the real answer is long
# too, and a `| grep -q` on the other end quits at the first match and leaves
# the writer with SIGPIPE, which pipefail then reads as "no instance".
# `hold` is a shell that stays alive holding a helper (its child), for the
# check that a living shell's helpers are left alone.
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
if [[ ${1:-} == list ]]; then
  l=$(cat "$LINGER" 2>/dev/null || echo 0)
  (( l > 0 )) || exit 1
  echo $((l-1)) > "$LINGER"
  echo '[{"id":"stale"}]'; head -c 200000 /dev/zero | tr '\0' ' '; echo
  exit 0
fi
if [[ ${1:-} == hold ]]; then
  # The supervisor tells a shell by its process name; a script run through
  # `env bash` is named bash, the real binary quickshell.
  printf quickshell > /proc/$$/comm
  sleep 120 & helper=$!
  trap 'kill "$helper" 2>/dev/null' TERM EXIT
  echo "$helper" > "$HELD"
  wait "$helper"
  exit 0
fi
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
echo "run $n"
# exit 139 is what the supervisor's wait sees from a shell killed by
# SIGSEGV (128 + 11), without a real crash: a real one is a coredump, and
# on a Plasma desktop DrKonqi reports every one of them as a crash of bash.
if (( n <= ${CRASHES:-0} )); then exit 139; fi
exit ${FINAL_EXIT:-0}
Q
chmod +x "$SB/bin/quickshell"
# The supervisor ends the helpers a crashed shell left behind through pgrep
# and pkill. Both are stand-ins for the whole run, whatever the scenario: the
# real ones would find the real session's leftovers on the machine running
# this test and end them. pgrep answers with the pids in $ORPHANS (none, unless
# a scenario sets it) whatever the pattern; pkill only records its arguments
# and the run the shell was at.
cat > "$SB/bin/pgrep" <<'Q'
#!/usr/bin/env bash
[[ -s ${ORPHANS:-} ]] || exit 1
cat "$ORPHANS"
Q
cat > "$SB/bin/pkill" <<'Q'
#!/usr/bin/env bash
printf 'run=%s %s\n' "$(cat "$COUNT" 2>/dev/null || echo 0)" "$*" >> "$PKILLS"
Q
chmod +x "$SB/bin/pgrep" "$SB/bin/pkill"
real_pkill=$(command -v pkill)
export PATH="$SB/bin:$PATH" XDG_STATE_HOME="$SB/state" COUNT="$SB/count" LINGER="$SB/linger" \
  HELD="$SB/held" PKILLS="$SB/pkills"
echo 0 > "$LINGER"; : > "$PKILLS"
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
check '[[ ! -s $PKILLS ]]' "nothing to reap, nothing killed ($(wc -l < "$PKILLS") pkill calls)"

# the helpers a crashed shell left behind are ended before the replacement
# starts: by their exact command lines, this user only, by the parent that
# was checked - and never one that a living quickshell still owns, which is
# what a nested test session's helpers are to the real session and the other
# way round
sleep 120 & orphan=$!                 # its parent is this test, not a shell
"$SB/bin/quickshell" hold & held_shell=$!
for _ in {1..50}; do [[ -s $HELD ]] && break; sleep 0.1; done
held=$(cat "$HELD")
printf '%s\n%s\n' "$orphan" "$held" > "$SB/orphans"
uid=$(id -u)
cfg_pattern=$(printf '%s' "$SB/cfg" | sed 's,[][\.*^$+?(){}|\\],\\&,g')
expect_nmcli="-u $uid -P $$ -f ^(\\S*/)?nmcli monitor\$"
expect_drives="-u $uid -P $$ -f ^(\\S+ )?$cfg_pattern/scripts/drives\\.py monitor\$"
expect_agent="-u $uid -P $$ -f ^(\\S+ )?$cfg_pattern/scripts/bluetooth-agent\\.py\$"
expect_paste="-u $uid -P $$ -f ^(\\S*/)?wl-paste --type (text|image) --watch cliphist -db-path \\S*/buchhwin-shell/cliphist\\.db -max-items [0-9]+ store\$"
expect_udev="-u $uid -P $$ -f ^(\\S*/)?udevadm monitor --udev --subsystem-match=backlight\$"
expect_inhibit="-u $uid -P $$ -f ^(\\S*/)?systemd-inhibit --what=handle-lid-switch --who=buchhwin-shell .* sleep infinity\$"
: > "$PKILLS"
echo 0 > "$COUNT"; echo 3 > "$LINGER"; ORPHANS="$SB/orphans" CRASHES=1 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 2 ]]' "the restart still happens (got $(cat "$COUNT") runs, wanted 2)"
check '[[ $(grep -c "^run=1 " "$PKILLS") == 6 ]]' "one pkill per helper after the crash and before the replacement ($(grep -c "^run=1 " "$PKILLS") calls, wanted 6)"
check '[[ $(grep -c "^run=2 " "$PKILLS") == 6 ]]' "and once more on the way out ($(grep -c "^run=2 " "$PKILLS") calls, wanted 6)"
for expected in "$expect_nmcli" "$expect_drives" "$expect_agent" "$expect_paste" "$expect_udev" "$expect_inhibit"; do
  check 'grep -qF -- "$expected" "$PKILLS"' "this user, the orphan's parent, the exact command line: $expected"
done
check '! grep -qw -- "$held_shell" "$PKILLS"' "a helper whose parent is a living quickshell is left alone"
check 'grep -q "ended 6 helper(s) left behind" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says what was ended'

# a shell that ends without a crash - SIGTERM, the compositor gone (how every
# nested test session ends) - is not restarted, but its leftovers are ended
: > "$PKILLS"
echo 0 > "$COUNT"; ORPHANS="$SB/orphans" CRASHES=0 FINAL_EXIT=143 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "a SIGTERM status is not restarted (got $(cat "$COUNT") runs)"
check '[[ $(grep -c "^run=1 " "$PKILLS") == 6 ]]' "but its helpers are ended on the way out ($(grep -c . "$PKILLS") pkill calls)"

# the session launcher asks for the same at logout, with --reap: no shell is
# started, the log is not rotated, and the helpers go only once the instance
# is gone
: > "$PKILLS"; echo marker-before-reap >> "$SB/state/buchhwin-shell/quickshell.log"
echo 0 > "$COUNT"; echo 3 > "$LINGER"; ORPHANS="$SB/orphans" bash ./scripts/start-shell.sh --reap "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 0 ]]' "--reap starts no shell (got $(cat "$COUNT") runs)"
check '[[ $(cat "$LINGER") == 0 ]]' "and waits for the lingering instance first ($(cat "$LINGER") list answers unused)"
check 'grep -q marker-before-reap "$SB/state/buchhwin-shell/quickshell.log"' "and does not rotate the log"
check '[[ $(grep -c . "$PKILLS") == 6 ]] && grep -qF -- "$expect_inhibit" "$PKILLS"' "and ends the helpers ($(grep -c . "$PKILLS") pkill calls)"
# an instance that never goes keeps its helpers
: > "$PKILLS"; echo 500 > "$LINGER"
ORPHANS="$SB/orphans" timeout 30 bash ./scripts/start-shell.sh --reap "$SB/cfg" >/dev/null 2>&1
check '[[ ! -s $PKILLS ]]' "an instance still listed after the wait keeps its helpers ($(grep -c . "$PKILLS") pkill calls)"
check 'grep -q "still listed - leaving its helpers alone" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'
echo 0 > "$LINGER"
kill "$orphan" "$held_shell" 2>/dev/null; wait "$orphan" "$held_shell" 2>/dev/null

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
exit 139
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
exit 139
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
if (( n <= 1 )); then exit 139; fi
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
trap 'exit 139' TERM
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
"$real_pkill" -f "$SB/bin/quickshell" 2>/dev/null || true

# a SIGTERM while the supervisor waits to restart a crashed shell - the pause,
# then the wait for the dead instance, with no child to forward it to - ends
# the watching too: no fresh shell into a session that is ending. The second
# run would loop until killed, so a supervisor that restarts never ends.
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
if [[ ${1:-} == list ]]; then
  l=$(cat "$LINGER" 2>/dev/null || echo 0)
  (( l > 0 )) || exit 1
  echo $((l-1)) > "$LINGER"
  echo '[{"id":"stale"}]'
  exit 0
fi
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
if (( n <= 1 )); then exit 139; fi
while true; do sleep 0.1; done
Q
chmod +x "$SB/bin/quickshell"
log="$SB/state/buchhwin-shell/quickshell.log"
: > "$log"; echo 0 > "$COUNT"; echo 40 > "$LINGER"
bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1 &
sup=$!
# Signalled once the crash is noted, i.e. inside the pause before the restart.
for _ in {1..100}; do grep -q "restarting (1 of 5)" "$log" && break; sleep 0.05; done
kill -TERM "$sup"
for _ in {1..100}; do kill -0 "$sup" 2>/dev/null || break; sleep 0.1; done
check '! kill -0 "$sup" 2>/dev/null' 'a SIGTERM during the restart pause ends the supervisor'
check '[[ $(cat "$COUNT") == 1 ]]' "and no shell is started after it (got $(cat "$COUNT") runs)"
check 'grep -q "asked to stop while waiting to restart" "$log"' 'and the log says why'
kill "$sup" 2>/dev/null; wait "$sup" 2>/dev/null
"$real_pkill" -f "$SB/bin/quickshell" 2>/dev/null || true
echo 0 > "$LINGER"

(( fail )) && exit 1
echo "TESTS PASSED start-shell supervision"
