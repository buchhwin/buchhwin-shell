#!/usr/bin/env bash
set -euo pipefail

# scripts/share-picker.sh, the picker xdg-desktop-portal-hyprland runs, against
# a stand-in shell in a sandbox: each answer the shell can give (a screen, a
# window, a region through slurp, cancel), the exact line the portal reads,
# the window list kept to a private file and off every command line, and the
# portal's own picker - with the portal's arguments - whenever something goes
# wrong: no shell, a refusal, an answer that is not a choice, a shell that
# dies while its picker is open. A picker left open past the limit is closed
# and the share cancelled.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-sharepickertest.XXXXXX")
holders="$sandbox/holders"
cleanup() {
  # The stand-in shells, by the pids they wrote: a pattern could end
  # someone else's sleep.
  if [[ -r $holders ]]; then
    while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$holders"
  fi
  rm -rf -- "$sandbox"
}
trap cleanup EXIT
failures=0
check() {
  if eval "$1"; then :; else printf 'FAIL share-picker: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
seen="$sandbox/seen"
mkdir -p "$bin" "$sandbox/home" "$sandbox/runtime" "$sandbox/tree" "$seen"
chmod 700 "$sandbox/runtime"

# The stand-in quickshell: `list` names the stand-in shell's pid (or none),
# `ipc … request DIR ALLOW` copies what it was handed and answers on the
# FIFO the way SharePickerService does, `ipc … cancel` is noted.
cat > "$bin/quickshell" <<EOF
#!/usr/bin/env bash
printf 'quickshell %s\n' "\$*" >> '$calls'
case "\$1" in
  list)
    [[ \${STUB_NO_SHELL:-} == 1 ]] && exit 1
    printf '[\n    {\n        "config_path": "x",\n        "pid": %s,\n        "shell_id": "y"\n    }\n]\n' "\$(cat '$sandbox/shell.pid')"
    ;;
  ipc)
    fn=\$6 dir=\$7
    if [[ \$fn == request ]]; then
      cp -p -- "\$dir/windows" '$seen/windows'
      stat -c %a -- "\$dir" > '$seen/dir-mode'
      stat -c %a -- "\$dir/windows" > '$seen/file-mode'
      [[ -p \$dir/answer ]] && echo fifo > '$seen/answer-kind'
      printf '%s\n' "\$8" > '$seen/allow'
      if [[ -n \${STUB_REPLY:-} ]]; then printf '%s\n' "\$STUB_REPLY"; exit 0; fi
      if [[ \${STUB_KILL_SHELL:-} == 1 ]]; then
        ( sleep 0.3; kill "\$(cat '$sandbox/shell.pid')" ) >/dev/null 2>&1 &
      elif [[ -n \${STUB_ANSWER:-} ]]; then
        ( sleep 0.3; printf '%s\n' "\$STUB_ANSWER" > "\$dir/answer" ) >/dev/null 2>&1 &
      fi
      echo opened
    fi
    ;;
esac
EOF
cat > "$bin/hyprland-share-picker" <<EOF
#!/usr/bin/env bash
printf 'hyprland-share-picker %s\n' "\$*" >> '$calls'
printf 'the portal picker speaks\n' >&2
printf '[SELECTION]/screen:FALLBACK\n'
EOF
cat > "$bin/slurp" <<EOF
#!/usr/bin/env bash
printf 'slurp %s\n' "\$*" >> '$calls'
[[ \${SLURP_FAIL:-} == 1 ]] && exit 1
printf '%s' "\${SLURP_OUT:-eDP-1@10,20,300,200}"
EOF
chmod +x "$bin/quickshell" "$bin/hyprland-share-picker" "$bin/slurp"
if [[ $(PATH="$bin:$PATH" command -v quickshell) != "$bin/quickshell" ]]; then
  printf 'share-picker test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

# A living stand-in shell for the wait to watch.
new_shell() {
  sleep 60 &
  printf '%s\n' "$!" > "$sandbox/shell.pid"
  printf '%s\n' "$!" >> "$holders"
}

list='305419896[HC>]brave-teams[HT>]Secret meeting title[HE>]93968578707456[HA>]17[HC>]Alacritty[HT>]~[HE>]0[HA>]'
out="$sandbox/out"
status=0
pick() {
  : > "$calls"
  rm -f "$seen"/*
  new_shell
  status=0
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_NESTED \
    PATH="$bin:$PATH" HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/runtime" BUCHHWIN_SHELL_PATH="$sandbox/tree" \
    XDPH_WINDOW_SHARING_LIST="$list" "$@" bash "$project_dir/scripts/share-picker.sh" --allow-token > "$out" 2>"$sandbox/err" || status=$?
}
printed() { cat "$out"; }
called() { grep -c "^$1 " "$calls" 2>/dev/null || true; }
leftovers() { find "$sandbox/runtime/buchhwin-shell/share-picker" -mindepth 1 2>/dev/null | wc -l; }

# ---- a screen ----------------------------------------------------------------------
pick STUB_ANSWER='[SELECTION]r/screen:eDP-1'
check '[[ $status == 0 ]]' "a screen: exit 0 (got $status)"
check '[[ $(printed) == "[SELECTION]r/screen:eDP-1" ]]' "a screen: the line the portal reads"
check '[[ $(tail -c 1 "$out" | od -An -c | tr -d " ") == "\\n" ]]' "the line ends in exactly one newline (the portal drops the last character of an output's name)"
check '[[ $(wc -l < "$out") == 1 ]]' "one line, nothing after it"
check '[[ $(called hyprland-share-picker) == 0 ]]' "a screen: not the portal's picker"
check '[[ $(cat "$seen/windows") == "$list" ]]' "the window list reached the shell whole"
check '[[ $(cat "$seen/dir-mode") == 700 && $(cat "$seen/file-mode") == 600 ]]' "in a private directory, a private file ($(cat "$seen/dir-mode" 2>/dev/null)/$(cat "$seen/file-mode" 2>/dev/null))"
check '[[ $(cat "$seen/answer-kind" 2>/dev/null) == fifo ]]' "the answer comes on a FIFO"
check '! grep -q "Secret meeting" "$calls"' "no title on any command line"
check '[[ $(cat "$seen/allow") == true ]]' "--allow-token reaches the shell as the toggle's default"
check 'grep -q "^quickshell ipc --pid $(cat "$sandbox/shell.pid") call sharePicker request $sandbox/runtime/buchhwin-shell/share-picker/req\." "$calls"' "the request goes to the instance found, by pid"
check 'grep -q "^quickshell list --json --path $sandbox/tree" "$calls"' "the shell found by BUCHHWIN_SHELL_PATH"
check '[[ $(leftovers) == 0 ]]' "the request's directory is gone afterwards"

# ---- a window, and no token ---------------------------------------------------------
pick STUB_ANSWER='[SELECTION]/window:305419896'
check '[[ $status == 0 && $(printed) == "[SELECTION]/window:305419896" ]]' "a window by its handle"

# ---- a region through slurp -----------------------------------------------------------
pick STUB_ANSWER='region r'
check '[[ $status == 0 && $(printed) == "[SELECTION]r/region:eDP-1@10,20,300,200" ]]' "a region: slurp's output-relative place (got $(printed))"
check 'grep -q "^slurp .*-f %o@%X,%Y,%W,%H" "$calls"' "slurp asked for the output and its own coordinates"
pick STUB_ANSWER='region' SLURP_FAIL=1
check '[[ $status != 0 && ! -s $out && $(called hyprland-share-picker) == 0 ]]' "Escape in slurp cancels the share"
pick STUB_ANSWER='region' SLURP_OUT='eDP-1@10,20,0,0'
check '[[ $status != 0 && ! -s $out && $(called hyprland-share-picker) == 0 ]]' "a click without a drag is no region"
pick STUB_ANSWER='region' SLURP_OUT='<unknown>@1,2,3,4'
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "a region slurp could not place: the portal's picker"

# ---- cancel --------------------------------------------------------------------------------
pick STUB_ANSWER='cancel'
check '[[ $status != 0 && ! -s $out ]]' "cancel: nothing printed, a cancelled share"
check '[[ $(called hyprland-share-picker) == 0 ]]' "cancel: not the portal's picker"
check '[[ $(leftovers) == 0 ]]' "cancel: the directory is gone"

# ---- the portal's own picker on every error -------------------------------------------
pick STUB_REPLY='disabled'
check '[[ $status == 0 && $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "a refusal: the portal's picker"
check 'grep -q "^hyprland-share-picker --allow-token$" "$calls"' "with the portal's own arguments"
check '[[ $(leftovers) == 0 ]]' "the directory goes before the handover"
check 'grep -q "^the portal picker speaks$" "$sandbox/err"' "its stderr still reaches the portal (the journal)"
pick STUB_NO_SHELL=1
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" && $(called "quickshell ipc") == 0 ]]' "no shell: the portal's picker, no request"
pick STUB_ANSWER='[SELECTION]/screen:eDP-1 extra'
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "an answer that is not a choice: the portal's picker"
pick STUB_ANSWER='something else'
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "an unknown answer: the portal's picker"
pick STUB_ANSWER='fallback'
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "the shell's picker did not come up: the portal's picker"
started=$SECONDS
pick STUB_KILL_SHELL=1
check '[[ $(printed) == "[SELECTION]/screen:FALLBACK" ]]' "a shell that dies while its picker is open: the portal's picker"
check '(( SECONDS - started < 10 ))' "and soon"

# ---- left open too long ----------------------------------------------------------------------
started=$SECONDS
pick BUCHHWIN_SHARE_PICKER_TIMEOUT=2
check '[[ $status != 0 && ! -s $out && $(called hyprland-share-picker) == 0 ]]' "past the limit: a cancelled share"
check 'grep -q "^quickshell ipc --pid [0-9]* call sharePicker cancel $sandbox/runtime/buchhwin-shell/share-picker/req\." "$calls"' "and the shell's picker closed"
check '(( SECONDS - started < 10 ))' "at the limit, not later"
check '[[ $(leftovers) == 0 ]]' "past the limit: the directory is gone"

if (( failures )); then
  printf 'share-picker test: %d failed\n' "$failures"
  exit 1
fi
printf 'share-picker test: ok\n'
