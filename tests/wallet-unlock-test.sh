#!/usr/bin/env bash
set -euo pipefail
# scripts/wallet-unlock.sh against a stub busctl: what it reports, what it
# asks the bus, and that it never starts anything.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-wallettest.XXXXXX")
standins=()
trap 'kill "${standins[@]}" 2>/dev/null; rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL wallet-unlock: %s\n' "$2"; failures=$((failures + 1)); fi; }

bin="$sandbox/bin"; calls="$sandbox/calls.log"; flag="$sandbox/flag"
# Every run's calls, kept: $calls starts empty for each run, and a check on
# it alone at the end would only ever see the last one.
all_calls="$sandbox/all-calls.log"
mkdir -p "$bin"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# qdbus would activate the very daemons this guards against (kwalletd6); a
# stub records a call instead of reaching the real one.
stub qdbus
stub qdbus6
export PATH="$bin:$PATH"
tool="$project_dir/scripts/wallet-unlock.sh"
run() { : > "$calls"; rm -f "$flag"; out=$("$tool" "$@" 2>/dev/null) && status=0 || status=$?; cat -- "$calls" >> "$all_calls"; }

# The owners of the names are processes of their own, named as the real
# ones are: the script reads the generic name's owner from /proc, and only a
# KDE daemon there counts. A script, not a copied binary (pitfall 69).
standin() {
  printf '#!/usr/bin/env bash\nprintf %%s %s > /proc/$$/comm\nwhile :; do sleep 0.2; done\n' "$1" > "$sandbox/standin-$1"
  chmod +x "$sandbox/standin-$1"
  "$sandbox/standin-$1" & standin_pid=$!
  disown "$standin_pid"
  standins+=("$standin_pid")
  for _ in {1..50}; do [[ $(cat "/proc/$standin_pid/comm" 2>/dev/null) == "$1" ]] && break; sleep 0.05; done
}
standin ksecretd; ksecretd=$standin_pid
standin gnome-keyring-d; keyring=$standin_pid

# The bus: "NAME PID" per owned name in $table. The bus driver's questions
# are answered from it the way the real driver answers them (the unique name
# is :1.PID), `list` prints it, and the cases a test passes come first.
table="$sandbox/table"
bus() {   # bus "NAME PID ..." [CASES]
  printf '%s\n' "$1" | tr -s ' ' '\n' | paste -d' ' - - | grep -v '^ *$' > "$table" || true
  stub busctl "for last in \"\$@\"; do :; done
case \"\$*\" in
  ${2:-}
  *' NameHasOwner s '*) if grep -q \"^\$last \" '$table'; then echo 'b true'; else echo 'b false'; fi ;;
  *' GetNameOwner s '*) pid=\$(sed -n \"s/^\$last //p\" '$table'); [ -n \"\$pid\" ] || exit 1; echo \"s \\\":1.\$pid\\\"\" ;;
  *' GetConnectionUnixProcessID s '*) echo \"u \${last#:1.}\" ;;
  *) printf 'NAME PID PROCESS\n'; cat '$table' ;;
esac"
}
generic="org.freedesktop.secrets $ksecretd"

# ---- status ----------------------------------------------------------------
bus "$generic" "*get-property*) echo 'b false' ;;"
run status
check '[[ $status -eq 0 && $out == open ]]' "an open collection reads open (got $status: $out)"
check 'grep -q -- "get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/kdewallet" "$calls"' \
  "ksecretd on the generic name alone is asked there"
bus "$generic" "*get-property*) echo 'b true' ;;"
run status
check '[[ $status -eq 1 && $out == locked ]]' "a locked collection reads locked (got $status: $out)"
# An activatable name nobody owns yet: the driver says no owner.
bus ""
run status
check '[[ $status -eq 2 && $out == "no service" ]]' "an activatable but unowned name is no service (got $status: $out)"
bus "$generic" "*get-property*) exit 1 ;;"
run status
check '[[ $status -eq 3 && $out == unreadable ]]' "an unreadable property is reported as such (got $status: $out)"

# ---- ensure ----------------------------------------------------------------
bus "$generic" "*get-property*) echo 'b false' ;;"
run ensure --prompt
check '[[ $status -eq 0 && $out == "open (already)" ]]' "an open wallet is not asked anything (got $status: $out)"
check '! grep -q Unlock "$calls"' "no Unlock on an open wallet"
# The service holds the login password: Unlock opens it without a prompt.
bus "$generic" "*Unlock*) touch '$flag'; printf 'ao 1 \"/org/freedesktop/secrets/collection/kdewallet\" o \"/\"\n' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;;"
run ensure
check '[[ $status -eq 0 && $out == "open (after unlock)" ]]' "an Unlock the service can answer opens it (got $status: $out)"
check '[[ $(grep -c -- "--auto-start=no .*Unlock ao 1 /org/freedesktop/secrets/collection/kdewallet" "$calls") -eq 1 ]]' "asked once, without activating anything"
check '! grep -q "Secret.Prompt" "$calls"' "no prompt when none was offered"
# A prompt is offered. Without --prompt it is left alone.
prompt='/org/freedesktop/secrets/prompt/p1'
bus "$generic" "*Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *'Secret.Prompt Prompt'*) touch '$flag' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;;"
run ensure
check '[[ $status -eq 1 && $out == "locked (prompt not followed)" ]]' "without --prompt the prompt is not followed (got $status: $out)"
check '! grep -q "Secret.Prompt" "$calls"' "and Prompt is not called"
# With --prompt it is followed, and the wallet opens.
run ensure --prompt
# The seconds are wall time: a loaded machine (the whole suite) can make it 1.
check '[[ $status -eq 0 && $out =~ ^open\ \(after\ prompt,\ [0-9]+\ s\)$ ]]' "a followed prompt that opens the wallet (got $status: $out)"
check '[[ $(grep -c -- "--auto-start=no .*$prompt org.freedesktop.Secret.Prompt Prompt s " "$calls") -eq 1 ]]' "Prompt called once, on the offered path, without activating anything"
# The prompt is dismissed: the prompt object is gone and the wallet is shut.
bus "$generic" "*Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *'Secret.Prompt Prompt'*) touch '$flag' ;; *introspect*) if [ -e '$flag' ]; then exit 1; fi ;; *get-property*) echo 'b true' ;;"
run ensure --prompt --timeout 5
check '[[ $status -eq 1 && $out == "locked (prompt dismissed)" ]]' "a dismissed prompt is reported, before the timeout (got $status: $out)"
# The dialog stays open past the timeout.
bus "$generic" "*Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *get-property*) echo 'b true' ;;"
run ensure --prompt --timeout 1
check '[[ $status -eq 1 && $out == "locked (timed out)" ]]' "an unanswered prompt times out (got $status: $out)"
# No owner, with and without waiting.
bus ""
run ensure
check '[[ $status -eq 2 && $out == "no service" ]]' "no owner: no service (got $status: $out)"
start=$(date +%s); run ensure --wait 1; end=$(date +%s)
check '[[ $status -eq 2 && $(( end - start )) -ge 1 ]]' "--wait waits for an owner before giving up"
# ---- Arch: gnome-keyring holds the generic name ------------------------------
# pam_gnome_keyring starts it at every SDDM login there; its collection is
# "login", not the KDE wallet. ksecretd is reached by its own name instead.
both="org.freedesktop.secrets $keyring org.kde.ksecretd $ksecretd"
bus "$both" "*get-property*) echo 'b false' ;;"
run status
check '[[ $status -eq 0 && $out == open ]]' "with gnome-keyring on the generic name the wallet still reads open (got $status: $out)"
check 'grep -q -- "get-property org.kde.ksecretd /org/freedesktop/secrets/collection/kdewallet" "$calls"' "asked through org.kde.ksecretd"
check '! grep -q -- "get-property org.freedesktop.secrets" "$calls"' "and never gnome-keyring"
check '[[ $(grep -c "NameHasOwner\|GetNameOwner\|GetConnectionUnixProcessID" "$calls") -eq 1 ]]' \
  "one question to the bus driver finds ksecretd's own name ($(grep -c "org.freedesktop.DBus" "$calls") asked)"
bus "$both" "*Unlock*) touch '$flag'; printf 'ao 1 \"/org/freedesktop/secrets/collection/kdewallet\" o \"/\"\n' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;;"
run ensure
check '[[ $status -eq 0 && $out == "open (after unlock)" ]]' "Unlock through ksecretd's own name (got $status: $out)"
check 'grep -q -- "call org.kde.ksecretd /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock" "$calls"' "the Unlock goes to org.kde.ksecretd"
# gnome-keyring alone (ksecretd not up yet, or no KWallet at all): no service,
# and --wait keeps waiting for ksecretd rather than settling for it.
bus "org.freedesktop.secrets $keyring"
run status
check '[[ $status -eq 2 && $out == "no service" ]]' "gnome-keyring alone is not the KDE wallet (got $status: $out)"
check 'grep -q -- "GetConnectionUnixProcessID s :1.$keyring" "$calls"' "its owner was looked up by its process"
start=$(date +%s); run ensure --wait 1; end=$(date +%s)
check '[[ $status -eq 2 && $(( end - start )) -ge 1 ]]' "--wait waits for ksecretd while gnome-keyring holds the generic name"

# Nothing the script does may activate a service - over every run above.
# Each busctl call carries --auto-start=no; none is `status`, and qdbus is
# never used. The owners are asked of the bus driver: the whole list, with
# every name's process and unit looked up, is never read any more.
# Captured, then searched (pitfall 15).
busctl_calls=$(grep '^busctl ' "$all_calls" || true)
activating=$(grep -v -- '--auto-start=no' <<<"$busctl_calls" || true)
check '[[ $(grep -c . <<<"$busctl_calls") -gt 20 ]]' "the calls of every run were kept ($(grep -c . <<<"$busctl_calls") busctl calls)"
check '[[ -z $activating ]]' "every busctl call has --auto-start=no (not: $(head -n 3 <<<"$activating"))"
check '! grep -qE -- "--auto-start=yes|^busctl (.* )?status( |$)" "$all_calls"' "never busctl status, never auto-start"
check '! grep -qE "^busctl (--[a-z0-9=-]+ )*list( |$)" "$all_calls"' "never the whole list of names"
check '! grep -qE "^qdbus6? " "$all_calls"' "never qdbus"

if (( failures )); then printf 'TESTS FAILED wallet-unlock (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED wallet-unlock\n'
