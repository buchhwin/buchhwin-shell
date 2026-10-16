#!/usr/bin/env bash
set -euo pipefail

# Reproducible checks that do not need a running desktop session.
#   scripts/test.sh            static checks and QML/JS unit tests
#   scripts/test.sh --session  additionally load the shell in a nested Hyprland
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/hyprland-prefix.sh
if [[ -r "$project_dir/scripts/lib/hyprland-prefix.sh" ]]; then source "$project_dir/scripts/lib/hyprland-prefix.sh"; fi
strict_style=${BUCHHWIN_STRICT_STYLE:-1}

# A section that needs a binary this machine does not have is **named**, here
# and again at the end. Two of the thirteen need one (Hyprland and Quickshell)
# and both are installable, so a skip is a fact about the machine, not about
# the suite - and a run that skipped something must not read the same as one
# that did not. The private-data check never skips: the one thing that must
# never be wrong is not worth a "passed" that means "not looked at".
skipped=()
note_skip() {
  skipped+=("$1")
  printf 'skipped: %s\n' "$1"
}

printf '== JSON\n'
python3 "$project_dir/scripts/lib/checks.py" json

printf '== Shell scripts\n'
# bash -n only parses its first file argument, so check each file. The ones
# without a .sh name are listed by hand: the user's `buchhwin` command and
# the nested key tool, whose parse error the smoke test would only report as
# "tool cannot build" (a skip), and the session's xdg-open.
for script in "$project_dir"/scripts/*.sh "$project_dir"/install/*.sh \
  "$project_dir"/tests/*.sh "$project_dir/session/buchhwin-shell-session" \
  "$project_dir"/scripts/lib/*.sh "$project_dir/scripts/nested-pointer" \
  "$project_dir/scripts/nested-keys" "$project_dir/scripts/buchhwin" "$project_dir/session/bin/xdg-open"; do
  bash -n "$script"
done
sh -n "$project_dir/session/buchhwin-shell-session-wrapper"
zsh -n "$project_dir/zsh/.zshrc"
zsh -n "$project_dir/shell-completion/_buchhwin"
sh -n "$project_dir/session/pam/buchhwin-lid-closed"

printf '== Hyprland configuration\n'
# The two dialects are the same session written twice; nothing but the drift
# check holds them together, because --verify-config only says each file parses
# on its own. That check is pure Python, so it runs whether or not Hyprland is
# installed - only the two parses need the binary.
python3 "$project_dir/scripts/lib/checks.py" binds
python3 "$project_dir/scripts/lib/checks.py" hypr
if command -v Hyprland >/dev/null; then
  verify_output=$(Hyprland --verify-config --config "$project_dir/hypr/hyprland.conf" 2>&1)
  grep -q 'config ok' <<<"$verify_output" || { printf '%s\n' "$verify_output"; exit 1; }
  printf 'config ok\n'
  lua_output=$(Hyprland --verify-config --config "$project_dir/hypr/hyprland.lua" 2>&1)
  grep -q 'config ok' <<<"$lua_output" || { printf '%s\n' "$lua_output"; exit 1; }
  printf 'lua config ok\n'
else
  note_skip 'Hyprland configuration parses (Hyprland not installed; package hyprland on Fedora and Arch, or install/build-hyprland-leap.sh on Leap)'
fi

printf '== Style tokens\n'
if [[ $strict_style == 1 ]]; then
  python3 "$project_dir/scripts/lib/checks.py" style --strict
else
  python3 "$project_dir/scripts/lib/checks.py" style
fi

printf '== Signal handler parameters\n'
python3 "$project_dir/scripts/lib/checks.py" handlers
python3 "$project_dir/scripts/lib/checks.py" icons
python3 "$project_dir/scripts/lib/checks.py" ipc
python3 "$project_dir/scripts/lib/checks.py" reserved
python3 "$project_dir/scripts/lib/checks.py" plaintext

printf '== QML lint\n'
# The Qt 6 one, by name first: on openSUSE `qmllint` is Qt 5's, which rejects
# --max-warnings, and `|| true` turned the whole step into a no-op.
qmllint_bin=""
for candidate in qmllint6 qmllint-qt6 /usr/lib64/qt6/bin/qmllint /usr/lib/qt6/bin/qmllint qmllint; do
  path=$(command -v "$candidate" 2>/dev/null) || continue
  version=$("$path" --version 2>/dev/null) || version=""
  if [[ $version == *" 6."* ]]; then qmllint_bin=$path; break; fi
done
if [[ -n $qmllint_bin ]]; then
  # Without Quickshell's qmltypes every `qs.*` name is unresolved, so the full
  # report (tens of thousands of lines) goes to a file and only the kinds that
  # mean something without them are shown. Warnings do not fail the run - a
  # syntax error does: Quickshell compiles a file only when something uses
  # it, so a broken panel no unit test loads passed here, and CI runs no
  # smoke test that would load it.
  lint_log=${XDG_CACHE_HOME:-$HOME/.cache}/buchhwin-shell/qmllint.log
  mkdir -p "${lint_log%/*}"
  "$qmllint_bin" --max-warnings -1 $(find "$project_dir/shell" "$project_dir/services" "$project_dir/theme" -name '*.qml' 2>/dev/null) >"$lint_log" 2>&1 || true
  lint_shown=$(grep -E '\[(duplicate-property-binding|syntax|read-only-property)\]' "$lint_log" || true)
  [[ -n $lint_shown ]] && printf '%s\n' "$lint_shown"
  printf '%s: %s warnings in all, full report in %s\n' "${qmllint_bin##*/}" "$(grep -c '^Warning' "$lint_log" || true)" "$lint_log"
  if grep -q '\[syntax\]' "$lint_log"; then
    printf 'qmllint found syntax errors (the [syntax] lines above). Refusing success.\n' >&2
    exit 1
  fi
else
  note_skip 'QML lint (qmllint not installed; package qt6-qtdeclarative-devel, qt6-declarative on Arch)'
fi

printf '== QML/JS unit tests\n'
if command -v quickshell >/dev/null; then
  # The runner first: a runner that lets a binding loop pass would pass
  # every test below for the wrong reason.
  "$project_dir/tests/qml-runner-test.sh"
  for test_file in "$project_dir"/tests/qml/*Test.qml; do
    "$project_dir/tests/run-qml-test.sh" "$test_file"
  done
else
  note_skip 'QML/JS unit tests (quickshell not installed; package quickshell)'
fi

printf '== Python helpers\n'
python3 -m py_compile "$project_dir"/scripts/*.py
# A test exits 77 (the autotools skip status) when this machine cannot run
# it - pam_lid_test.py without a libpam that has pam_start_confdir - and says
# why on its last line; that goes into the summary rather than into "passed".
for test_file in "$project_dir"/tests/python/*_test.py; do
  test_status=0; test_output=$(python3 "$test_file" 2>&1) || test_status=$?
  printf '%s\n' "$test_output"
  if [[ $test_status -eq 77 ]]; then
    note_skip "${test_file##*/} ($(tail -n 1 <<<"$test_output"))"
  elif [[ $test_status -ne 0 ]]; then
    exit "$test_status"
  fi
done

printf '== Installers and session launcher\n'
"$project_dir/tests/install-test.sh"
"$project_dir/tests/bootstrap-test.sh"
"$project_dir/tests/build-hyprland-test.sh"
"$project_dir/tests/sddm-theme-install-test.sh"
"$project_dir/tests/session-launcher-test.sh"
"$project_dir/tests/deploy-test.sh"

printf '== Session actions\n'
"$project_dir/tests/start-shell-test.sh"
"$project_dir/tests/session-action-test.sh"
"$project_dir/tests/shell-control-test.sh"
"$project_dir/tests/launch-app-test.sh"
"$project_dir/tests/launch-terminal-test.sh"
"$project_dir/tests/launch-default-test.sh"
"$project_dir/tests/app-env-test.sh"
"$project_dir/tests/wallet-unlock-test.sh"
"$project_dir/tests/x11-dpi-test.sh"
"$project_dir/tests/shell-update-test.sh"
"$project_dir/tests/updates-check-test.sh"
"$project_dir/tests/screenshot-test.sh"
"$project_dir/tests/record-test.sh"

printf '== Lid installers\n'
"$project_dir/tests/fingerprint-lid-install-test.sh"
"$project_dir/tests/logind-lid-install-test.sh"
"$project_dir/tests/bluetooth-autoenable-test.sh"

printf '== Environment\n'
# doctor.sh asks whether **this machine** can run the session - Kitty, Brave,
# Dolphin, the backends. That is a fact about the machine, not about the code,
# so a container that only builds and tests says so rather than installing a
# browser to satisfy a check.
if [[ ${BUCHHWIN_SKIP_ENVIRONMENT:-0} == 1 ]]; then
  note_skip 'Environment (doctor.sh checks a session host: Kitty, Brave, Dolphin; BUCHHWIN_SKIP_ENVIRONMENT=1)'
else
  "$project_dir/scripts/doctor.sh" >/dev/null || { "$project_dir/scripts/doctor.sh"; exit 1; }
  printf 'doctor ok\n'
fi

printf '== Private data\n'
# Places (side by side and under lat/lon keys), private keys, tokens, e-mail
# addresses and this user's home, in every file Git would commit; the rules
# and their allow-list are in checks.py. It used to be an rg pattern that only
# knew "a, b" pairs - and without ripgrep it passed unlooked. Python is always
# there; findings name the file and line, never the text.
if ! python3 "$project_dir/scripts/lib/checks.py" private; then
  printf 'Possible private data found. Refusing success.\n' >&2
  exit 1
fi
printf 'none found\n'

# The smoke test exits 77 when it had to skip its pointer steps (the tool
# cannot build here) and everything else passed; that is a skip to name.
smoke() {
  local label=$1 smoke_status=0
  "$project_dir/scripts/smoke-session.sh" --nested || smoke_status=$?
  if [[ $smoke_status -eq 77 ]]; then
    note_skip "$label: pointer steps (scripts/nested-pointer cannot build)"
  elif [[ $smoke_status -ne 0 ]]; then
    exit "$smoke_status"
  fi
}
if [[ ${1:-} == --session ]]; then
  printf '== Nested session smoke test\n'
  smoke 'Nested session smoke test'
  printf '== Nested session smoke test (Lua config)\n'
  BUCHHWIN_NESTED_LUA=1 smoke 'Nested session smoke test (Lua config)'
fi

if (( ${#skipped[@]} )); then
  printf 'All checks passed, with %d section(s) skipped:\n' "${#skipped[@]}"
  printf '  %s\n' "${skipped[@]}"
else
  printf 'All checks passed.\n'
fi
