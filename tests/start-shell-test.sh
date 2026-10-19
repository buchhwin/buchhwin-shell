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
# Like the real one, it lists by display: the instance lives on wayland-test,
# and `list --path` from anywhere else finds nothing. `list --all` (what
# --reap asks, from a launcher without a display) finds it from anywhere and
# names its configuration by path: $LIST_PATH, the test's own unless a
# scenario says otherwise.
cat > "$SB/bin/quickshell" <<'Q'
#!/usr/bin/env bash
if [[ ${1:-} == list ]]; then
  if [[ " $* " != *" --all "* && ${WAYLAND_DISPLAY:-} != wayland-test ]]; then echo '[]'; exit 0; fi
  l=$(cat "$LINGER" 2>/dev/null || echo 0)
  (( l > 0 )) || exit 1
  echo $((l-1)) > "$LINGER"
  printf '[{"id":"stale","config_path":"%s/shell.qml"}]\n' "${LIST_PATH:-$STUB_CFG}"
  head -c 200000 /dev/zero | tr '\0' ' '; echo
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
[[ -n ${ORDER:-} ]] && echo started >> "$ORDER"
# The environment the shell was given, and that of an application it starts
# through scripts/launch-app.sh, as /proc has them.
[[ -n ${ENVDUMP:-} ]] && tr '\0' '\n' < /proc/$$/environ > "$ENVDUMP"
[[ -n ${APPDUMP:-} ]] && "$REPO/scripts/launch-app.sh" org.example.App \
  sh -c 'tr "\0" "\n" < /proc/$$/environ > "$1"' sh "$APPDUMP"
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
# busctl too: before each start the supervisor ends a kded6 that holds the
# tray's StatusNotifierWatcher name, and the real busctl would report - and
# the supervisor end - the real session's kded6. The stand-in names the owner
# from $TRAY_OWNER ("pid process"), none unless a scenario sets it.
cat > "$SB/bin/busctl" <<'Q'
#!/usr/bin/env bash
printf 'NAME PID PROCESS USER CONNECTION UNIT SESSION DESCRIPTION\n'
[[ -n ${TRAY_OWNER:-} ]] && printf 'org.kde.StatusNotifierWatcher %s buchhwin :1.9 - - -\n' "$TRAY_OWNER"
exit 0
Q
chmod +x "$SB/bin/busctl"
# launch-app.sh, run by the stand-in shell, asks the user manager: a scope
# that runs its command in place, and the session's environment from
# $SESSION_ENV - never the host's.
cat > "$SB/bin/systemd-run" <<'Q'
#!/usr/bin/env bash
while (( $# )) && [[ $1 != -- ]]; do shift; done
shift
exec "$@"
Q
cat > "$SB/bin/systemctl" <<'Q'
#!/usr/bin/env bash
[[ $* == *show-environment* ]] && cat "$SESSION_ENV" 2>/dev/null
exit 0
Q
chmod +x "$SB/bin/systemd-run" "$SB/bin/systemctl"
# hyprctl lists the instances in $HYPR_INSTANCES (a file, `hyprctl instances`
# text), none unless a scenario says so - never the host's: with the real one
# a test run inside the session resolved the session's own signature.
cat > "$SB/bin/hyprctl" <<'Q'
#!/usr/bin/env bash
[[ ${1:-} == instances && -s ${HYPR_INSTANCES:-} ]] && cat "$HYPR_INSTANCES"
exit 0
Q
chmod +x "$SB/bin/hyprctl"
# A Hyprland of the test's own: its signature and socket under a runtime
# directory of the sandbox. sig-alive has a socket, sig-gone none, and
# sig-other is a live Hyprland on another display. The lock files are as
# Hyprland writes them (pid, then socket).
mkdir -p "$SB/run/hypr/sig-alive" "$SB/run/hypr/sig-gone" "$SB/run/hypr/sig-other"
for sig in sig-alive sig-other; do
  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SB/run/hypr/$sig/.socket.sock"
done
printf '1\nwayland-other\n' > "$SB/run/hypr/sig-other/hyprland.lock"
printf '1\nwayland-test\n' > "$SB/run/hypr/sig-alive/hyprland.lock"
real_pkill=$(command -v pkill)
# The stand-in shells run outside any session, so the test says so
# (BUCHHWIN_START_WITHOUT_HYPRLAND); the cases of the session check below
# take it away again. No signature of the caller's reaches the script.
unset HYPRLAND_INSTANCE_SIGNATURE HYPR_INSTANCES
# The configuration is the sandbox's too: the icon theme comes from
# kdeglobals and settings.json, and the caller's own would decide it. So is
# the runtime directory: before it starts the shell, the script clears the
# instance directories Quickshell left there, and a test clears none of the
# caller's.
export PATH="$SB/bin:$PATH" XDG_STATE_HOME="$SB/state" XDG_CONFIG_HOME="$SB/config" XDG_RUNTIME_DIR="$SB/run" \
  COUNT="$SB/count" LINGER="$SB/linger" \
  HELD="$SB/held" PKILLS="$SB/pkills" STUB_CFG="$SB/cfg" SESSION_ENV="$SB/session-env" REPO="$PWD" \
  WAYLAND_DISPLAY=wayland-test BUCHHWIN_START_WITHOUT_HYPRLAND=1
# The shell's own settings and its record of them come from whoever runs this
# test - a terminal or an editor the shell started has them - and would be
# taken for the session's. So does a nested session's flag.
unset MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION \
  QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO QS_DISABLE_CRASH_HANDLER BUCHHWIN_APP_ENV_UNSET BUCHHWIN_APP_QPA_THEME \
  BUCHHWIN_NESTED BUCHHWIN_NESTED_DIR BUCHHWIN_NESTED_MODE BUCHHWIN_NESTED_SCALE XDG_CACHE_HOME
: > "$SESSION_ENV"
echo 0 > "$LINGER"; : > "$PKILLS"
fail=0
check() { if eval "$1"; then :; else printf 'FAIL: %s\n' "$2"; fail=1; fi; }

# two crashes then a clean exit: three runs
echo 0 > "$COUNT"; CRASHES=2 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 3 ]]' "a crash is restarted (got $(cat "$COUNT") runs, wanted 3)"
check 'grep -q "died on signal 11, restarting (1 of 5)" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'

# A start sweeps the instance directories of shells that are gone from its
# runtime directory (scripts/lib/quickshell-dirs.sh): an unlocked one older
# than an hour goes, a fresh one stays. In the sandbox's runtime directory,
# never the host's.
qs_dirs="$SB/run/quickshell/by-id"
mkdir -p "$qs_dirs/deadold1" "$qs_dirs/deadnew1"
: > "$qs_dirs/deadold1/instance.lock"; : > "$qs_dirs/deadnew1/instance.lock"
touch -d '2 hours ago' "$qs_dirs/deadold1"
echo 0 > "$COUNT"; CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ ! -e $qs_dirs/deadold1 && -d $qs_dirs/deadnew1 ]]' "a start removes a gone instance's directory older than an hour, and keeps a new one"
# The shell does not wait for the sweep: the first one of a runtime directory
# with a thousand directories took four seconds. A slow `find` stands in for
# that; the shell starts first, and the sweep is still done when the script
# has ended.
mkdir -p "$SB/slowbin" "$qs_dirs/deadold2"
: > "$qs_dirs/deadold2/instance.lock"; touch -d '2 hours ago' "$qs_dirs/deadold2"
real_find=$(command -v find)
printf '#!/usr/bin/env bash
sleep 1
echo swept >> "$ORDER"
exec %q "$@"
' "$real_find" > "$SB/slowbin/find"
chmod +x "$SB/slowbin/find"
: > "$SB/order"
echo 0 > "$COUNT"; ORDER="$SB/order" PATH="$SB/slowbin:$PATH" CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(head -n1 "$SB/order") == started ]]' "the shell starts before the sweep has looked ($(tr '\n' ' ' < "$SB/order"))"
check '[[ ! -e $qs_dirs/deadold2 ]]' "and the sweep is done by the time the script ends"

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
# was checked - and only real orphans, adopted by PID 1 (or the user
# manager). Never one that a living quickshell still owns, which is what a
# nested test session's helpers are to the real session and the other way
# round, and never one of the user's own: `nmcli monitor` in a terminal has
# the terminal's zsh for a parent, and went on every reload (16.10.).
( sleep 120 </dev/null >/dev/null 2>&1 & echo $! > "$SB/orphan.pid" )
orphan=$(cat "$SB/orphan.pid")        # its parent is gone: adopted
trap 'kill "$orphan" 2>/dev/null; rm -rf -- "$SB"' EXIT
sleep 120 & users_own=$!              # its parent is this test, as a terminal's zsh
"$SB/bin/quickshell" hold & held_shell=$!
for _ in {1..50}; do [[ -s $HELD ]] && break; sleep 0.1; done
held=$(cat "$HELD")
printf '%s\n%s\n%s\n' "$orphan" "$users_own" "$held" > "$SB/orphans"
adopter=$(awk '/^PPid:/ { print $2 }' "/proc/$orphan/status" 2>/dev/null)
# A subreaper other than PID 1 or the user manager (some container runtimes)
# adopts it here: the reaping checks below cannot be made then.
orphans_testable=0
if [[ $adopter == 1 || $(cat "/proc/$adopter/comm" 2>/dev/null) == systemd ]]; then orphans_testable=1; fi
(( orphans_testable )) || printf 'start-shell-test: the orphan was adopted by %s (%s); reaping checks skipped\n' "$adopter" "$(cat "/proc/$adopter/comm" 2>/dev/null)"
uid=$(id -u)
cfg_pattern=$(printf '%s' "$SB/cfg" | sed 's,[][\.*^$+?(){}|\\],\\&,g')
expect_nmcli="-u $uid -P $adopter -f ^(\\S*/)?nmcli monitor\$"
expect_drives="-u $uid -P $adopter -f ^(\\S+ )?$cfg_pattern/scripts/drives\\.py monitor\$"
expect_agent="-u $uid -P $adopter -f ^(\\S+ )?$cfg_pattern/scripts/bluetooth-agent\\.py\$"
expect_paste="-u $uid -P $adopter -f ^(\\S*/)?wl-paste --type (text|image) --watch cliphist -db-path \\S*/buchhwin-shell/cliphist\\.db -max-items [0-9]+ store\$"
expect_udev="-u $uid -P $adopter -f ^(\\S*/)?udevadm monitor --udev --subsystem-match=backlight\$"
expect_inhibit="-u $uid -P $adopter -f ^(\\S*/)?systemd-inhibit --what=handle-lid-switch --who=buchhwin-shell .* sleep infinity\$"
expect_udisks="-u $uid -P $adopter -f ^(\\S*/)?udisksctl monitor\$"
expect_gio="-u $uid -P $adopter -f ^(\\S*/)?gio mount -o\$"
: > "$PKILLS"
echo 0 > "$COUNT"; echo 3 > "$LINGER"; ORPHANS="$SB/orphans" CRASHES=1 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 2 ]]' "the restart still happens (got $(cat "$COUNT") runs, wanted 2)"
if (( orphans_testable )); then
  check '[[ $(grep -c "^run=1 " "$PKILLS") == 8 ]]' "one pkill per helper after the crash and before the replacement ($(grep -c "^run=1 " "$PKILLS") calls, wanted 8)"
  check '[[ $(grep -c "^run=2 " "$PKILLS") == 8 ]]' "and once more on the way out ($(grep -c "^run=2 " "$PKILLS") calls, wanted 8)"
  for expected in "$expect_nmcli" "$expect_drives" "$expect_agent" "$expect_paste" "$expect_udev" "$expect_inhibit" \
      "$expect_udisks" "$expect_gio"; do
    check 'grep -qF -- "$expected" "$PKILLS"' "this user, the orphan's parent, the exact command line: $expected"
  done
  check 'grep -q "ended 8 helper(s) left behind" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says what was ended'
fi
check '! grep -qw -- "$held_shell" "$PKILLS"' "a helper whose parent is a living quickshell is left alone"
check '! grep -qw -- "-P $$" "$PKILLS" && ! grep -q -- "-P [0-9]*,$$" "$PKILLS"' "a helper whose parent is the user's own process (a terminal's zsh) is left alone"

# a kded6 holding the tray name is ended (SIGKILL) before the shell starts;
# a process of another name under that name is left alone, and so is
# everything in a nested session
# A script, not a copy of sleep: Fedora's coreutils-single is one binary that
# picks the tool by its own name and refuses to run as "kded6".
printf '#!/usr/bin/env bash\nprintf kded6 > /proc/$$/comm\nwhile :; do sleep 0.2; done\n' > "$SB/kded6"
chmod +x "$SB/kded6"
"$SB/kded6" & tray=$!
disown "$tray"   # its SIGKILL is expected, not a job to report
for _ in {1..20}; do [[ $(cat /proc/$tray/comm 2>/dev/null) == kded6 ]] && break; sleep 0.05; done
# The session the tray belongs to: the test's own Hyprland, socket and all.
in_session=(HYPRLAND_INSTANCE_SIGNATURE=sig-alive XDG_RUNTIME_DIR="$SB/run")

# ---- no Hyprland, no shell ----------------------------------------------------
# A deploy or a reload run from Plasma started the shell on KWin's display and
# SIGKILLed Plasma's kded6 for holding the tray name. Without a Hyprland to
# belong to - none listed, a signature whose socket is gone, or one instance
# on another display - nothing starts and the tray owner is left alone; the
# opt-in of the tests starts a shell but still never touches the tray.
shell_log="$SB/state/buchhwin-shell/quickshell.log"
refused() {   # refused LABEL ENV...: refused with a note, nothing started, kded6 alive
  local label=$1 rc=0; shift
  echo 0 > "$COUNT"; : > "$SB/start.err"
  env -u BUCHHWIN_START_WITHOUT_HYPRLAND "$@" TRAY_OWNER="$tray kded6" CRASHES=0 FINAL_EXIT=0 \
    bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>"$SB/start.err" || rc=$?
  check '[[ $rc -ne 0 && $(cat "$COUNT") == 0 ]]' "$label: the shell is not started (status $rc, $(cat "$COUNT") runs)"
  check 'kill -0 "$tray" 2>/dev/null' "$label: and the kded6 holding the tray name is left alone"
  check 'grep -q "not starting the shell" "$SB/start.err" && grep -q "not starting the shell" "$shell_log"' "$label: and it says so"
}
refused "no Hyprland at all (Plasma)" WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE
refused "a signature whose socket is gone" HYPRLAND_INSTANCE_SIGNATURE=sig-gone XDG_RUNTIME_DIR="$SB/run"
# A Hyprland still running on another VT: the user manager hands its live
# signature to a Plasma terminal, whose WAYLAND_DISPLAY is KWin's.
refused "a live signature of another display" HYPRLAND_INSTANCE_SIGNATURE=sig-other XDG_RUNTIME_DIR="$SB/run"
check 'grep -q "runs on wayland-other, this is wayland-test" "$SB/start.err"' 'and names both displays'
printf 'instance sig-alive:\n\ttime: 1\n\tpid: 1\n\twl socket: wayland-other\n\n' > "$SB/instances"
refused "the one instance on another display" HYPR_INSTANCES="$SB/instances" XDG_RUNTIME_DIR="$SB/run"
check 'grep -q "runs on wayland-other, this is wayland-test" "$SB/start.err"' 'and names both displays'
# the one instance on this display is the session: adopted, and started
printf 'instance sig-alive:\n\ttime: 1\n\tpid: 1\n\twl socket: wayland-test\n\n' > "$SB/instances"
echo 0 > "$COUNT"; : > "$SB/shell.env"
env -u BUCHHWIN_START_WITHOUT_HYPRLAND HYPR_INSTANCES="$SB/instances" XDG_RUNTIME_DIR="$SB/run" ENVDUMP="$SB/shell.env" \
  TRAY_OWNER="$tray other" CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]] && grep -qx HYPRLAND_INSTANCE_SIGNATURE=sig-alive "$SB/shell.env"' \
  "the one instance on this display is adopted and the shell starts ($(cat "$COUNT") runs)"
# the session's own signature with its socket: started
echo 0 > "$COUNT"
env -u BUCHHWIN_START_WITHOUT_HYPRLAND "${in_session[@]}" TRAY_OWNER="$tray other" CRASHES=0 FINAL_EXIT=0 \
  bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "the session's own signature starts the shell ($(cat "$COUNT") runs)"
# the tests' opt-in starts the stand-in, and still leaves the tray alone
echo 0 > "$COUNT"; TRAY_OWNER="$tray kded6" CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]] && kill -0 "$tray" 2>/dev/null' "without a session the opt-in starts a shell and ends no kded6"

echo 0 > "$COUNT"; env "${in_session[@]}" BUCHHWIN_NESTED=1 TRAY_OWNER="$tray kded6" CRASHES=0 FINAL_EXIT=0 \
  bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check 'kill -0 "$tray" 2>/dev/null' 'a nested session never ends the tray owner'
echo 0 > "$COUNT"; env "${in_session[@]}" TRAY_OWNER="$tray other" CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check 'kill -0 "$tray" 2>/dev/null' 'a tray owner that is not kded6 is left alone'
echo 0 > "$COUNT"; env "${in_session[@]}" TRAY_OWNER="$tray kded6" CRASHES=0 FINAL_EXIT=0 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
for _ in {1..20}; do kill -0 "$tray" 2>/dev/null || break; sleep 0.05; done
check '! kill -0 "$tray" 2>/dev/null' 'a kded6 holding the tray name is ended before the shell starts'
check 'grep -q "ended kded6 (pid $tray)" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'
kill "$tray" 2>/dev/null || true

# a shell that ends without a crash - SIGTERM, the compositor gone (how every
# nested test session ends) - is not restarted, but its leftovers are ended
: > "$PKILLS"
echo 0 > "$COUNT"; ORPHANS="$SB/orphans" CRASHES=0 FINAL_EXIT=143 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "a SIGTERM status is not restarted (got $(cat "$COUNT") runs)"
if (( orphans_testable )); then
  check '[[ $(grep -c "^run=1 " "$PKILLS") == 8 ]]' "but its helpers are ended on the way out ($(grep -c . "$PKILLS") pkill calls)"
fi

# the session launcher asks for the same at logout, with --reap: no shell is
# started, the log is not rotated, and the helpers go only once the instance
# is gone. It has no WAYLAND_DISPLAY, and `quickshell list --path` only lists
# the instances of its own display, so the instance is looked for on all of
# them, by its configuration's path.
: > "$PKILLS"; echo marker-before-reap >> "$SB/state/buchhwin-shell/quickshell.log"
echo 0 > "$COUNT"; echo 3 > "$LINGER"
ORPHANS="$SB/orphans" env -u WAYLAND_DISPLAY bash ./scripts/start-shell.sh --reap "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 0 ]]' "--reap starts no shell (got $(cat "$COUNT") runs)"
check '[[ $(cat "$LINGER") == 0 ]]' "and waits for the lingering instance first, without a display ($(cat "$LINGER") list answers unused)"
check 'grep -q marker-before-reap "$SB/state/buchhwin-shell/quickshell.log"' "and does not rotate the log"
if (( orphans_testable )); then
  check '[[ $(grep -c . "$PKILLS") == 8 ]] && grep -qF -- "$expect_inhibit" "$PKILLS"' "and ends the helpers ($(grep -c . "$PKILLS") pkill calls)"
fi
# an instance that never goes keeps its helpers
: > "$PKILLS"; echo 500 > "$LINGER"
ORPHANS="$SB/orphans" timeout 30 bash ./scripts/start-shell.sh --reap "$SB/cfg" >/dev/null 2>&1
check '[[ ! -s $PKILLS ]]' "an instance still listed after the wait keeps its helpers ($(grep -c . "$PKILLS") pkill calls)"
check 'grep -q "still listed - leaving its helpers alone" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'
# an instance of another configuration is no reason to wait
: > "$PKILLS"; echo 500 > "$LINGER"
ORPHANS="$SB/orphans" LIST_PATH="$SB/other" timeout 30 bash ./scripts/start-shell.sh --reap "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$LINGER") -gt 490 ]]' "another configuration's instance is not waited for ($((500 - $(cat "$LINGER"))) list answers used)"
echo 0 > "$LINGER"
kill "$orphan" "$users_own" "$held_shell" 2>/dev/null; wait "$users_own" "$held_shell" 2>/dev/null

# ---- the shell's environment, and its applications' -------------------------
# The shell runs with settings of its own (two malloc arenas, Mesa without its
# threads, no KDE platform theme); an application it starts through
# launch-app.sh gets the session's back. Applications from the launcher used
# to get the shell's.
envcase() {
  : > "$SB/shell.env"; : > "$SB/app.env"
  echo 0 > "$COUNT"
  env "$@" ENVDUMP="$SB/shell.env" APPDUMP="$SB/app.env" CRASHES=0 FINAL_EXIT=0 \
    bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
}
has() { grep -qx -- "$2" "$SB/$1.env"; }
lacks() { ! grep -q -- "^$2=" "$SB/$1.env"; }
# Everything the shell sets for itself, in the order of the record.
own_names="MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO QS_DISABLE_CRASH_HANDLER"
own_pattern="^(MALLOC|mesa|GALLIUM|QT_WAYLAND_DISABLE|QSG_|QS_|BUCHHWIN_ICON)"
envcase -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME=kde
check 'has shell MALLOC_ARENA_MAX=2 && has shell mesa_glthread=false && has shell GALLIUM_THREAD=0 && lacks shell QT_QPA_PLATFORMTHEME' \
  "the shell runs with its own settings and without the platform theme"
# jemalloc's knob next to glibc's (Arch's quickshell links jemalloc), no
# decorations for windows that never have any, greyscale text.
check 'has shell MALLOC_CONF=narenas:2,background_thread:true,dirty_decay_ms:1000 && has shell QT_WAYLAND_DISABLE_WINDOWDECORATION=1 && has shell QSG_DISTANCEFIELD_ANTIALIASING=gray' \
  "and with jemalloc's arenas, no decorations and greyscale text ($(grep -E "^(MALLOC_CONF|QT_WAYLAND|QSG_)" "$SB/shell.env" | tr '\n' ' '))"
# Quickshell's own crash handler off, or a crash never reaches the restart
# and its count: Quickshell restarts the shell itself, or exits cleanly.
check 'has shell QS_DISABLE_CRASH_HANDLER=1' "and without Quickshell's crash handler"
check 'has shell "BUCHHWIN_APP_ENV_UNSET=$own_names" && has shell BUCHHWIN_APP_QPA_THEME=kde' \
  "and records what it changed ($(grep ^BUCHHWIN_APP "$SB/shell.env" | tr '\n' ' '))"
check '! grep -qE "$own_pattern" "$SB/app.env"' \
  "an application it starts has none of them ($(grep -E "$own_pattern" "$SB/app.env" | tr '\n' ' '))"
check 'has app QT_QPA_PLATFORMTHEME=kde && lacks app BUCHHWIN_APP_ENV_UNSET && lacks app BUCHHWIN_APP_QPA_THEME' \
  "but the session's platform theme, and no record"
# an exported value wins - for the shell, and it was the session's anyway
envcase -u QT_QPA_PLATFORMTHEME MALLOC_ARENA_MAX=4 MALLOC_CONF=narenas:1 QT_WAYLAND_DISABLE_WINDOWDECORATION=0
check 'has shell MALLOC_ARENA_MAX=4 && has app MALLOC_ARENA_MAX=4 && lacks app mesa_glthread' "an exported value is kept for both"
check 'has shell MALLOC_CONF=narenas:1 && has app MALLOC_CONF=narenas:1 && has shell QT_WAYLAND_DISABLE_WINDOWDECORATION=0 && has app QT_WAYLAND_DISABLE_WINDOWDECORATION=0' \
  "jemalloc's and the decorations' too"
check 'lacks app QT_QPA_PLATFORMTHEME' "and a session without a platform theme gives the application none"
# started by something that came from a shell (a reload from a terminal the
# shell opened): the record is undone first, so it is the session's again
envcase -u QT_QPA_PLATFORMTHEME QS_ICON_THEME=breeze MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 \
  MALLOC_CONF=narenas:2 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QSG_DISTANCEFIELD_ANTIALIASING=gray BUCHHWIN_ICON_THEME_AUTO=1 \
  "BUCHHWIN_APP_ENV_UNSET=$own_names" BUCHHWIN_APP_QPA_THEME=kde
check 'has shell "BUCHHWIN_APP_ENV_UNSET=$own_names" && has shell BUCHHWIN_APP_QPA_THEME=kde' \
  "a caller from the shell is taken back to the session's values first"
check 'has app QT_QPA_PLATFORMTHEME=kde && ! grep -qE "$own_pattern" "$SB/app.env"' "and so are its applications"
# A caller from a shell older than these names (an editor opened from the
# launcher before them): its record names the four it had, and the rest are
# set and recorded as for any start.
envcase -u QT_QPA_PLATFORMTHEME QS_ICON_THEME=breeze MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 \
  "BUCHHWIN_APP_ENV_UNSET=MALLOC_ARENA_MAX mesa_glthread GALLIUM_THREAD QS_ICON_THEME" BUCHHWIN_APP_QPA_THEME=kde
check 'has shell "BUCHHWIN_APP_ENV_UNSET=$own_names" && ! grep -qE "$own_pattern" "$SB/app.env"' \
  "a caller from a shell before the newer names gets the whole record"
# from a shell older than the record (an editor opened from the launcher
# before it, deploying): the user manager says what the session has
printf 'QT_QPA_PLATFORMTHEME=kde\nXDG_CURRENT_DESKTOP=buchhwin-shell:Hyprland\n' > "$SESSION_ENV"
envcase -u QT_QPA_PLATFORMTHEME QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0
check 'has shell "BUCHHWIN_APP_ENV_UNSET=$own_names" && has shell BUCHHWIN_APP_QPA_THEME=kde' \
  "an old shell's settings are told apart by the user manager's environment ($(grep ^BUCHHWIN_APP "$SB/shell.env" | tr '\n' ' '))"
check 'has app QT_QPA_PLATFORMTHEME=kde && lacks app MALLOC_ARENA_MAX && lacks app GALLIUM_THREAD' "and its applications get the session's"
: > "$SESSION_ENV"

# ---- the icon theme ---------------------------------------------------------
# Qt reads it once, at the start: kdeglobals' [Icons] Theme when there is
# one, else what the panels are (theme/Colors.qml's surfaceDark) - a chosen
# panel colour by its brightness, the theme's own panels by the theme, "auto"
# dark from 19:00 to 07:00. `date +%H` is the test's ($HOUR); everything else
# date says is the real one's.
real_date=$(command -v date)
mkdir -p "$SB/clock" "$SB/config/buchhwin-shell"
printf '#!/bin/sh\nif [ "$1" = "+%%H" ] && [ -n "$HOUR" ]; then echo "$HOUR"; exit 0; fi\nexec %s "$@"\n' "$real_date" > "$SB/clock/date"
chmod +x "$SB/clock/date"
icons() {   # icons SETTINGS-JSON HOUR: the theme the shell got, and whether the panels chose it
  printf '%s\n' "$1" > "$SB/config/buchhwin-shell/settings.json"
  envcase PATH="$SB/clock:$PATH" HOUR="$2"
  printf '%s %s' "$(sed -n 's/^QS_ICON_THEME=//p' "$SB/shell.env")" "$(sed -n 's/^BUCHHWIN_ICON_THEME_AUTO=//p' "$SB/shell.env")"
}
check '[[ $(icons "{}" 12) == "breeze-dark 1" ]]' "no setting: the dark theme's icons ($(icons "{}" 12))"
check '[[ $(icons "{\"appearance\":{\"theme\":\"light\"}}" 22) == "breeze 1" ]]' "light: the light theme's icons"
check '[[ $(icons "{\"appearance\":{\"theme\":\"auto\"}}" 12) == "breeze 1" ]]' "auto by day: the light theme's icons ($(icons "{\"appearance\":{\"theme\":\"auto\"}}" 12))"
check '[[ $(icons "{\"appearance\":{\"theme\":\"auto\"}}" 19) == "breeze-dark 1" && $(icons "{\"appearance\":{\"theme\":\"auto\"}}" 6) == "breeze-dark 1" ]]' \
  "auto at night: the dark theme's icons"
check '[[ $(icons "{\"appearance\":{\"theme\":\"light\",\"panelColor\":\"#000000\"}}" 12) == "breeze-dark 1" ]]' \
  "light with black panels (buchhwin): light icons on the black ($(icons "{\"appearance\":{\"theme\":\"light\",\"panelColor\":\"#000000\"}}" 12))"
check '[[ $(icons "{\"appearance\":{\"theme\":\"dark\",\"panelColor\":\" FFF \"}}" 22) == "breeze 1" ]]' \
  "dark with white panels: dark icons on the white (three digits, no #, spaces)"
check '[[ $(icons "{\"appearance\":{\"theme\":\"light\",\"panelColor\":\"auto\"}}" 3) == "breeze 1" ]]' "an automatic panel colour follows the theme"
printf '[General]\nColorScheme=BreezeDark\n\n[Icons]\nTheme=Papirus\n' > "$SB/config/kdeglobals"
check '[[ $(icons "{\"appearance\":{\"theme\":\"light\"}}" 12) == "Papirus " ]]' "kdeglobals' theme wins, and the panels did not choose ($(icons "{\"appearance\":{\"theme\":\"light\"}}" 12))"
rm -f "$SB/config/kdeglobals" "$SB/config/buchhwin-shell/settings.json"

# ---- a shell restarted into a nested session -------------------------------
# From a terminal with the nested signature and display but neither its flag
# nor its sandbox (the testing recipe's exports): the compositor's own
# environment says it is nested, and the shell takes the flag and the
# sandbox's directories from there - not the user's configuration, and the
# live shell's log stays where it is.
nest="$SB/nest"
mkdir -p "$nest/config" "$nest/state" "$nest/cache" "$SB/run/hypr/sig-nest"
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SB/run/hypr/sig-nest/.socket.sock"
env BUCHHWIN_NESTED=1 BUCHHWIN_NESTED_MODE=1280x800 BUCHHWIN_NESTED_SCALE=1 XDG_CONFIG_HOME="$nest/config" \
  XDG_STATE_HOME="$nest/state" XDG_CACHE_HOME="$nest/cache" sleep 120 & compositor=$!
printf '%s\nwayland-nest\n' "$compositor" > "$SB/run/hypr/sig-nest/hyprland.lock"
for _ in {1..20}; do grep -qx BUCHHWIN_NESTED=1 < <(tr '\0' '\n' < "/proc/$compositor/environ" 2>/dev/null) && break; sleep 0.05; done
printf 'LIVE SHELL LOG\n' > "$SB/state/buchhwin-shell/quickshell.log"
rm -f "$SB/state/buchhwin-shell/quickshell.log.old"
envcase -u BUCHHWIN_START_WITHOUT_HYPRLAND HYPRLAND_INSTANCE_SIGNATURE=sig-nest WAYLAND_DISPLAY=wayland-nest XDG_RUNTIME_DIR="$SB/run"
check '[[ $(cat "$COUNT") == 1 ]] && has shell BUCHHWIN_NESTED=1 && has shell BUCHHWIN_NESTED_MODE=1280x800' \
  "the nested compositor's shell is nested ($(grep ^BUCHHWIN_NESTED "$SB/shell.env" | tr '\n' ' '))"
check 'has shell XDG_CONFIG_HOME="$nest/config" && has shell XDG_STATE_HOME="$nest/state" && has shell XDG_CACHE_HOME="$nest/cache"' \
  "and runs on the sandbox's directories ($(grep ^XDG_ "$SB/shell.env" | tr '\n' ' '))"
check '[[ $(cat "$SB/state/buchhwin-shell/quickshell.log") == "LIVE SHELL LOG" && ! -e "$SB/state/buchhwin-shell/quickshell.log.old" ]]' \
  "and the live shell's log is not moved aside"
check 'grep -q "the compositor is a nested session; taken from it: BUCHHWIN_NESTED=1" "$nest/state/buchhwin-shell/quickshell.log"' \
  "and its own log says what it took"
# The real session's compositor carries none of it: nothing changes.
env XDG_CONFIG_HOME="$SB/elsewhere" sleep 120 & real_compositor=$!
printf '%s\nwayland-nest\n' "$real_compositor" > "$SB/run/hypr/sig-nest/hyprland.lock"
for _ in {1..20}; do grep -q '^XDG_CONFIG_HOME=' < <(tr '\0' '\n' < "/proc/$real_compositor/environ" 2>/dev/null) && break; sleep 0.05; done
envcase -u BUCHHWIN_START_WITHOUT_HYPRLAND HYPRLAND_INSTANCE_SIGNATURE=sig-nest WAYLAND_DISPLAY=wayland-nest XDG_RUNTIME_DIR="$SB/run"
check 'lacks shell BUCHHWIN_NESTED && has shell XDG_CONFIG_HOME="$SB/config" && has shell XDG_STATE_HOME="$SB/state"' \
  "a compositor that is not nested hands nothing over ($(grep -E "^(BUCHHWIN_NESTED|XDG_CONFIG)" "$SB/shell.env" | tr '\n' ' '))"
kill "$compositor" "$real_compositor" 2>/dev/null; wait "$compositor" "$real_compositor" 2>/dev/null

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
echo 0 > "$COUNT"; HYPRLAND_INSTANCE_SIGNATURE=sig-gone XDG_RUNTIME_DIR="$SB/run" timeout 30 bash ./scripts/start-shell.sh "$SB/cfg" >/dev/null 2>&1
check '[[ $(cat "$COUNT") == 1 ]]' "no compositor, no restart (got $(cat "$COUNT"))"
check 'grep -q "the compositor is gone" "$SB/state/buchhwin-shell/quickshell.log"' 'and the log says so'

# with the compositor's socket present the same crash is restarted
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
# Until the stand-in runs, not a fixed second: on a loaded machine the TERM
# could land before there is a shell to forward it to.
for _ in {1..100}; do [[ $(cat "$COUNT") == 1 ]] && break; sleep 0.05; done
sleep 0.1
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
