#!/usr/bin/env bash
# scripts/shell-update.sh against a bare "remote" and a clone that follows it,
# in a fake HOME with stub systemctl, hyprctl, quickshell and notify-send: a
# check names the commits the remote has, an apply fast-forwards, re-links and
# restarts the shell, and a checkout with local changes or local commits is
# refused - nothing of the user's is ever merged over. A checkout that follows
# no remote (the development machine) says so, and so does a directory that is
# no checkout at all. A nested session cannot apply.
set -uo pipefail
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
work=$(mktemp -d)
cleanup() { rm -rf -- "$work" 2>/dev/null || { sleep 1; rm -rf -- "$work"; }; }
trap cleanup EXIT
fail=0
check() { if eval "$1"; then :; else printf 'FAIL shell-update: %s\n' "$2"; fail=1; fi; }

mkdir -p "$work/bin" "$work/home"
for tool in systemctl hyprctl quickshell notify-send; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$tool" "$work" > "$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH="$work/bin:$PATH" HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_STATE_HOME="$work/home/.local/state"
export HYPRLAND_INSTANCE_SIGNATURE=shell-update-test
unset BUCHHWIN_NESTED BUCHHWIN_NESTED_DIR WAYLAND_DISPLAY
unset BUCHHWIN_SHELL_PATH
gitc() { git -c user.email=test@example.invalid -c user.name=test "$@"; }

# the remote, and a clone the session runs from
gitc clone --quiet --bare --no-hardlinks "$project_dir" "$work/remote.git"
# The remote's main is the commit under test, whichever branch the checkout is
# on: a worktree on another branch, with main moved on meanwhile, otherwise
# starts the clone behind its own remote and every push below is rejected.
gitc -C "$work/remote.git" update-ref refs/heads/main "$(git -C "$project_dir" rev-parse HEAD)"
gitc -C "$work/remote.git" symbolic-ref HEAD refs/heads/main
gitc clone --quiet "$work/remote.git" "$work/home/.local/share/buchhwin-shell-src"
src="$work/home/.local/share/buchhwin-shell-src"
gitc -C "$src" checkout --quiet -B main origin/HEAD 2>/dev/null || gitc -C "$src" checkout --quiet -B main
gitc -C "$src" branch --quiet --set-upstream-to=origin/main main 2>/dev/null \
  || { gitc -C "$src" push --quiet origin main:main && gitc -C "$src" branch --quiet --set-upstream-to=origin/main main; }
# the scripts under test are the working-tree ones
mkdir -p "$src/scripts/lib"
cp "$project_dir/scripts/shell-update.sh" "$project_dir/scripts/reload-shell.sh" "$project_dir/scripts/stop-shell.sh" "$src/scripts/"
cp "$project_dir/scripts/lib/reload.sh" "$project_dir/scripts/lib/nested-guard.sh" "$src/scripts/lib/"
gitc -C "$src" add -A && gitc -C "$src" commit --quiet -m "test: current scripts" && gitc -C "$src" push --quiet origin main
mkdir -p "$HOME/.local/share" && ln -s "$src" "$HOME/.local/share/buchhwin-shell"
update() { "$src/scripts/shell-update.sh" "$@"; }
sec() { awk -v s="@$1 " 'index($0, s) == 1 {p=1; next} /^@/ {p=0} p' ; }

# up to date
report=$(update check)
check '[[ $(sed -n "/^@repo/{n;p;q}" <<<"$report") == ok ]]' 'a clone that follows a remote reports ok'
check '[[ $(sec behind <<<"$report") == 0 ]]' 'and is not behind'
check 'grep -q "^@fetch 0" <<<"$report"' 'the fetch succeeded'

# the fetch can never wait at a prompt: the shell runs the check on a timer
# with nobody at a terminal. ssh is a stub here that records what git hands it
# and refuses, standing in for a remote that would ask for a passphrase.
printf '#!/bin/sh\necho "ssh $*" >> "%s/calls.log"\nexit 255\n' "$work" > "$work/bin/ssh"
chmod +x "$work/bin/ssh"
gitc -C "$src" remote set-url origin ssh://example.invalid/shell.git
: > "$work/calls.log"
report=$(GIT_ASKPASS=/bin/false update check)
check 'grep -q "^@fetch [1-9]" <<<"$report"' 'an ssh remote that refuses is a failed fetch, not a hang'
check 'grep -q "^ssh .*-oBatchMode=yes" "$work/calls.log"' 'and ssh was told never to ask'
gitc -C "$src" remote set-url origin "$work/remote.git"
rm -f "$work/bin/ssh"

# the remote moves on: a docs commit and a shell commit
other="$work/other"
gitc clone --quiet "$work/remote.git" "$other"
echo "docs" >> "$other/README.md"; gitc -C "$other" commit --quiet -am "docs: a line"
echo "// test" >> "$other/shell.qml"; gitc -C "$other" commit --quiet -am "feat: a shell change"
gitc -C "$other" push --quiet origin HEAD:main
report=$(update check)
check '[[ $(sec behind <<<"$report") == 2 ]]' "two commits behind (got $(sec behind <<<"$report"))"
check '[[ $(sec ahead <<<"$report") == 0 ]]' 'none ahead'
check 'sec log <<<"$report" | head -1 | grep -q "feat: a shell change"' 'the log names the newest first'
check 'sec log <<<"$report" | grep -qP "^[0-9a-f]{7,}\tdocs: a line$"' 'hash, tab, subject'
report=$(update check --offline)
check 'grep -q "^@fetch 0" <<<"$report" && [[ $(sec fetch <<<"$report") == skipped ]]' 'offline skips the fetch'
check '[[ $(sec behind <<<"$report") == 2 ]]' 'and still counts against what was fetched'

# apply: fast-forward, relink, restart the shell
: > "$work/calls.log"
out=$(update apply 2>&1)
check '[[ $(git -C "$src" rev-parse HEAD) == $(git -C "$other" rev-parse HEAD) ]]' "apply fast-forwarded ($out)"
check 'grep -q "Updated " <<<"$out"' 'and said so'
check 'grep -q "quickshell kill" "$work/calls.log"' 'a shell change restarted the shell'
check '! grep -q "hyprctl reload" "$work/calls.log"' 'and did not reload Hyprland for it'
check 'grep -q "notify-send" "$work/calls.log"' 'the user was told'
check '[[ $(readlink -f "$HOME/.local/bin/buchhwin") == "$src/scripts/buchhwin" ]]' 'install.sh re-ran (the links exist)'
check '[[ $(update apply 2>&1) == "Already up to date." ]]' 'a second apply has nothing to do'

# local changes and local commits are refused
echo "mine" >> "$src/README.md"
check '! update apply >/dev/null 2>&1' 'local changes refuse the update'
gitc -C "$src" checkout --quiet -- README.md
gitc -C "$src" commit --quiet --allow-empty -m "local: mine"
echo "more" >> "$other/README.md"; gitc -C "$other" commit --quiet -am "docs: more"; gitc -C "$other" push --quiet origin HEAD:main
report=$(update check)
check '[[ $(sec ahead <<<"$report") == 1 && $(sec behind <<<"$report") == 1 ]]' 'diverged: one ahead, one behind'
check '! update apply >/dev/null 2>&1' 'a local commit refuses the update'
check '[[ $(git -C "$src" log -1 --format=%s) == "local: mine" ]]' 'and nothing was merged over it'

# a nested session never applies
check '! BUCHHWIN_NESTED=1 update apply >/dev/null 2>&1' 'a nested session is refused'

# no remote, and no checkout
gitc -C "$src" branch --quiet --unset-upstream
report=$(update check)
check '[[ $(sed -n "/^@repo/{n;p;q}" <<<"$report") == local ]]' 'a checkout without a remote says local'
check '! update apply >/dev/null 2>&1' 'and cannot be updated'
rm "$HOME/.local/share/buchhwin-shell"; mkdir "$HOME/.local/share/buchhwin-shell"
report=$(update check)
check '[[ $(sed -n "/^@repo/{n;p;q}" <<<"$report") == none ]]' 'a directory that is no checkout says none'

(( fail )) && exit 1
echo "TESTS PASSED shell-update"
