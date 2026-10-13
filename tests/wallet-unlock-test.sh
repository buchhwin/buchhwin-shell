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
mkdir -p "$bin"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
export PATH="$bin:$PATH"
tool="$project_dir/scripts/wallet-unlock.sh"
owned='printf "NAME PID PROCESS\norg.freedesktop.secrets 42 ksecretd\n"'
run() { : > "$calls"; rm -f "$flag"; out=$("$tool" "$@" 2>/dev/null) && status=0 || status=$?; }

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
# Nothing the script does may activate a service.
check '! grep -qE -- "--auto-start=yes|busctl status" "$calls"' "never busctl status, never auto-start"

if (( failures )); then printf 'TESTS FAILED wallet-unlock (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED wallet-unlock\n'
