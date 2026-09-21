#!/usr/bin/env bash
set -euo pipefail

# Reproducible checks that do not need a running desktop session.
#   scripts/test.sh            static checks and QML/JS unit tests
#   scripts/test.sh --session  additionally load the shell in a nested Hyprland
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
strict_style=${BUCHHWIN_STRICT_STYLE:-1}

printf '== JSON\n'
python3 "$project_dir/scripts/lib/checks.py" json

printf '== Shell scripts\n'
# bash -n only parses its first file argument, so check each file.
for script in "$project_dir"/scripts/*.sh "$project_dir"/install/*.sh \
  "$project_dir"/tests/*.sh "$project_dir/session/buchhwin-shell-session" \
  "$project_dir"/scripts/lib/*.sh "$project_dir/scripts/nested-pointer"; do
  bash -n "$script"
done
sh -n "$project_dir/session/buchhwin-shell-session-wrapper"
zsh -n "$project_dir/zsh/.zshrc"
sh -n "$project_dir/session/pam/buchhwin-lid-closed"

printf '== Hyprland configuration\n'
verify_output=$(Hyprland --verify-config --config "$project_dir/hypr/hyprland.conf" 2>&1)
grep -q 'config ok' <<<"$verify_output" || { printf '%s\n' "$verify_output"; exit 1; }
printf 'config ok\n'
python3 "$project_dir/scripts/lib/checks.py" binds
# The two dialects are the same session written twice; nothing but this holds
# them together, because --verify-config only says each file parses on its own.
python3 "$project_dir/scripts/lib/checks.py" hypr
lua_output=$(Hyprland --verify-config --config "$project_dir/hypr/hyprland.lua" 2>&1)
grep -q 'config ok' <<<"$lua_output" || { printf '%s\n' "$lua_output"; exit 1; }
printf 'lua config ok\n'

printf '== Style tokens\n'
if [[ $strict_style == 1 ]]; then
  python3 "$project_dir/scripts/lib/checks.py" style --strict
else
  python3 "$project_dir/scripts/lib/checks.py" style
fi

printf '== Signal handler parameters\n'
python3 "$project_dir/scripts/lib/checks.py" handlers
python3 "$project_dir/scripts/lib/checks.py" icons

printf '== QML lint\n'
qmllint_bin=$(command -v qmllint || command -v qmllint-qt6 || true)
[[ -z $qmllint_bin && -x /usr/lib64/qt6/bin/qmllint ]] && qmllint_bin=/usr/lib64/qt6/bin/qmllint
if [[ -n $qmllint_bin ]]; then
  "$qmllint_bin" --max-warnings -1 $(find "$project_dir/shell" "$project_dir/services" "$project_dir/theme" -name '*.qml' 2>/dev/null) || true
else
  printf 'skipped (qmllint not installed; package qt6-qtdeclarative-devel)\n'
fi

printf '== QML/JS unit tests\n'
for test_file in "$project_dir"/tests/qml/*Test.qml; do
  "$project_dir/tests/run-qml-test.sh" "$test_file"
done

printf '== Python helpers\n'
python3 -m py_compile "$project_dir"/scripts/*.py
for test_file in "$project_dir"/tests/python/*_test.py; do
  python3 "$test_file"
done

printf '== Installers and session launcher\n'
"$project_dir/tests/install-test.sh"
"$project_dir/tests/bootstrap-test.sh"
"$project_dir/tests/sddm-theme-install-test.sh"
"$project_dir/tests/session-launcher-test.sh"
"$project_dir/tests/deploy-test.sh"

printf '== Session actions\n'
"$project_dir/tests/session-action-test.sh"
"$project_dir/tests/shell-control-test.sh"

printf '== Fingerprint lid installer\n'
"$project_dir/tests/fingerprint-lid-install-test.sh"

printf '== Environment\n'
"$project_dir/scripts/doctor.sh" >/dev/null || { "$project_dir/scripts/doctor.sh"; exit 1; }
printf 'doctor ok\n'

printf '== Private data\n'
# The only check in this file that used no `command -v` guard: without ripgrep
# it simply passed, so the one thing that must never be wrong was not being
# looked at. A missing tool is a failure here, not a pass.
if ! command -v rg >/dev/null; then
  printf 'ripgrep is required for the private-data check. Refusing success.\n' >&2
  exit 1
fi
if rg -n --hidden --glob '!.git/**' \
  '[-+]?[0-9]{1,3}\.[0-9]{4,}[[:space:]]*[,;][[:space:]]*[-+]?[0-9]{1,3}\.[0-9]{4,}' \
  "$project_dir"; then
  printf 'Possible coordinates found. Refusing success.\n' >&2
  exit 1
fi
printf 'none found\n'

if [[ ${1:-} == --session ]]; then
  printf '== Nested session smoke test\n'
  "$project_dir/scripts/smoke-session.sh" --nested
  printf '== Nested session smoke test (Lua config)\n'
  BUCHHWIN_NESTED_LUA=1 "$project_dir/scripts/smoke-session.sh" --nested
fi

printf 'All checks passed.\n'
