#!/usr/bin/env bash
set -euo pipefail
# scripts/wallet-unlock.sh against a stub busctl: what it reports, what it
# asks the bus, and that it never starts anything.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-wallettest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
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
owned='printf "NAME PID PROCESS\norg.freedesktop.secrets 42 ksecretd\n"'
run() { : > "$calls"; rm -f "$flag"; out=$("$tool" "$@" 2>/dev/null) && status=0 || status=$?; cat -- "$calls" >> "$all_calls"; }

# ---- status ----------------------------------------------------------------
stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"
run status
check '[[ $status -eq 0 && $out == open ]]' "an open collection reads open (got $status: $out)"
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *) $owned ;; esac"
run status
check '[[ $status -eq 1 && $out == locked ]]' "a locked collection reads locked (got $status: $out)"
stub busctl 'printf "NAME PID PROCESS\norg.freedesktop.secrets - -\n"'
run status
check '[[ $status -eq 2 && $out == "no service" ]]' "an activatable but unowned name is no service (got $status: $out)"
stub busctl "case \"\$*\" in *get-property*) exit 1 ;; *) $owned ;; esac"
run status
check '[[ $status -eq 3 && $out == unreadable ]]' "an unreadable property is reported as such (got $status: $out)"

# ---- ensure ----------------------------------------------------------------
stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"
run ensure --prompt
check '[[ $status -eq 0 && $out == "open (already)" ]]' "an open wallet is not asked anything (got $status: $out)"
check '! grep -q Unlock "$calls"' "no Unlock on an open wallet"
# The service holds the login password: Unlock opens it without a prompt.
stub busctl "case \"\$*\" in *Unlock*) touch '$flag'; printf 'ao 1 \"/org/freedesktop/secrets/collection/kdewallet\" o \"/\"\n' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
run ensure
check '[[ $status -eq 0 && $out == "open (after unlock)" ]]' "an Unlock the service can answer opens it (got $status: $out)"
check '[[ $(grep -c -- "--auto-start=no .*Unlock ao 1 /org/freedesktop/secrets/collection/kdewallet" "$calls") -eq 1 ]]' "asked once, without activating anything"
check '! grep -q "Secret.Prompt" "$calls"' "no prompt when none was offered"
# A prompt is offered. Without --prompt it is left alone.
prompt='/org/freedesktop/secrets/prompt/p1'
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *\"Secret.Prompt Prompt\"*) touch '$flag' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
run ensure
check '[[ $status -eq 1 && $out == "locked (prompt not followed)" ]]' "without --prompt the prompt is not followed (got $status: $out)"
check '! grep -q "Secret.Prompt" "$calls"' "and Prompt is not called"
# With --prompt it is followed, and the wallet opens.
run ensure --prompt
check '[[ $status -eq 0 && $out == "open (after prompt, 0 s)" ]]' "a followed prompt that opens the wallet (got $status: $out)"
check '[[ $(grep -c -- "--auto-start=no .*$prompt org.freedesktop.Secret.Prompt Prompt s " "$calls") -eq 1 ]]' "Prompt called once, on the offered path, without activating anything"
# The prompt is dismissed: the prompt object is gone and the wallet is shut.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *\"Secret.Prompt Prompt\"*) touch '$flag' ;; *introspect*) if [ -e '$flag' ]; then exit 1; fi ;; *get-property*) echo 'b true' ;; *) $owned ;; esac"
run ensure --prompt --timeout 5
check '[[ $status -eq 1 && $out == "locked (prompt dismissed)" ]]' "a dismissed prompt is reported, before the timeout (got $status: $out)"
# The dialog stays open past the timeout.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"$prompt\"\n' ;; *get-property*) echo 'b true' ;; *) $owned ;; esac"
run ensure --prompt --timeout 1
check '[[ $status -eq 1 && $out == "locked (timed out)" ]]' "an unanswered prompt times out (got $status: $out)"
# No owner, with and without waiting.
stub busctl 'printf "NAME PID PROCESS\norg.freedesktop.secrets - -\n"'
run ensure
check '[[ $status -eq 2 && $out == "no service" ]]' "no owner: no service (got $status: $out)"
start=$(date +%s); run ensure --wait 1; end=$(date +%s)
check '[[ $status -eq 2 && $(( end - start )) -ge 1 ]]' "--wait waits for an owner before giving up"
# ---- Arch: gnome-keyring holds the generic name ------------------------------
# pam_gnome_keyring starts it at every SDDM login there; its collection is
# "login", not the KDE wallet. ksecretd is reached by its own name instead.
both='printf "NAME PID PROCESS\norg.freedesktop.secrets 41 gnome-keyring-d\norg.kde.ksecretd 42 ksecretd\n"'
stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $both ;; esac"
run status
check '[[ $status -eq 0 && $out == open ]]' "with gnome-keyring on the generic name the wallet still reads open (got $status: $out)"
check 'grep -q -- "get-property org.kde.ksecretd /org/freedesktop/secrets/collection/kdewallet" "$calls"' "asked through org.kde.ksecretd"
check '! grep -q -- "get-property org.freedesktop.secrets" "$calls"' "and never gnome-keyring"
stub busctl "case \"\$*\" in *Unlock*) touch '$flag'; printf 'ao 1 \"/org/freedesktop/secrets/collection/kdewallet\" o \"/\"\n' ;; *get-property*) if [ -e '$flag' ]; then echo 'b false'; else echo 'b true'; fi ;; *) $both ;; esac"
run ensure
check '[[ $status -eq 0 && $out == "open (after unlock)" ]]' "Unlock through ksecretd's own name (got $status: $out)"
check 'grep -q -- "call org.kde.ksecretd /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock" "$calls"' "the Unlock goes to org.kde.ksecretd"
# gnome-keyring alone (ksecretd not up yet, or no KWallet at all): no service,
# and --wait keeps waiting for ksecretd rather than settling for it.
stub busctl 'printf "NAME PID PROCESS\norg.freedesktop.secrets 41 gnome-keyring-d\n"'
run status
check '[[ $status -eq 2 && $out == "no service" ]]' "gnome-keyring alone is not the KDE wallet (got $status: $out)"
start=$(date +%s); run ensure --wait 1; end=$(date +%s)
check '[[ $status -eq 2 && $(( end - start )) -ge 1 ]]' "--wait waits for ksecretd while gnome-keyring holds the generic name"

# Nothing the script does may activate a service - over every run above.
# Each busctl call either reads the bus's list (which starts nothing) or
# carries --auto-start=no; none is `status`, and qdbus is never used.
# Captured, then searched (pitfall 15).
busctl_calls=$(grep '^busctl ' "$all_calls" || true)
activating=$(grep -vE -- '--auto-start=no|^busctl (--[a-z-]+ )*list( |$)' <<<"$busctl_calls" || true)
check '[[ $(grep -c . <<<"$busctl_calls") -gt 20 ]]' "the calls of every run were kept ($(grep -c . <<<"$busctl_calls") busctl calls)"
check '[[ -z $activating ]]' "every busctl call reads the list or has --auto-start=no (not: $(head -n 3 <<<"$activating"))"
check '! grep -qE -- "--auto-start=yes|^busctl (.* )?status( |$)" "$all_calls"' "never busctl status, never auto-start"
check '! grep -qE "^qdbus6? " "$all_calls"' "never qdbus"

if (( failures )); then printf 'TESTS FAILED wallet-unlock (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED wallet-unlock\n'
