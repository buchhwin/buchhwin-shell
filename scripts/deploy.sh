#!/usr/bin/env bash
set -euo pipefail

# The running session uses a separate git worktree on the `stable` branch, so
# edits on `main` never reach the desktop half-written. This script moves
# `stable` forward to a tested commit and reloads what changed.
#
#   scripts/deploy.sh --init       create the stable worktree, point the session
#                                  links at it (install/install.sh --apply)
#   scripts/deploy.sh              test main, fast-forward stable, reload
#   scripts/deploy.sh --status     deployed commit vs main, no changes
#   scripts/deploy.sh --rollback   return stable to the previously deployed commit
# Options: --no-test (skip scripts/test.sh --session), --no-reload,
#          --ref REF (deploy another commit than main)
# BUCHHWIN_STABLE_DIR overrides ~/.local/share/buchhwin-shell-stable (tests).

project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
stable_dir=${BUCHHWIN_STABLE_DIR:-"$HOME/.local/share/buchhwin-shell-stable"}
action=deploy
run_tests=true
reload=true
ref=main
while (( $# )); do
  case "$1" in
    --init) action=init; shift ;;
    --status) action=status; shift ;;
    --rollback) action=rollback; shift ;;
    --no-test) run_tests=false; shift ;;
    --no-reload) reload=false; shift ;;
    --ref) ref=${2:?--ref needs a commit}; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

git_dev() { git -C "$project_dir" "$@"; }
git_stable() { git -C "$stable_dir" "$@"; }

if [[ $(git_dev rev-parse --show-toplevel) != "$project_dir" ]]; then
  printf 'deploy: %s is not the repository root\n' "$project_dir" >&2
  exit 1
fi
if [[ $project_dir == "$(readlink -f -- "$stable_dir" 2>/dev/null || true)" ]]; then
  printf 'deploy: run this from the development checkout, not from the stable worktree\n' >&2
  exit 1
fi

have_stable() { [[ -e $stable_dir/.git ]]; }

# Hyprland watches its configuration and reloads by itself, and a checkout
# replaces a file by removing and writing it - so it can read exactly while the
# file is gone and leave "cannot open hyprland.lua" on screen although the
# configuration is fine. An explicit reload afterwards clears that, which is
# why this also runs when the deploy was started from outside the session
# (no HYPRLAND_INSTANCE_SIGNATURE) and why it checks the result.
reload_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  local signature=${HYPRLAND_INSTANCE_SIGNATURE:-} instances
  if [[ -z $signature ]]; then
    instances=$(hyprctl instances 2>/dev/null | grep -c '^instance ' || true)
    # More than one means a nested test session is running: never guess which.
    [[ $instances == 1 ]] || { printf 'Hyprland was not reloaded (no session found).\n'; return 0; }
    signature=$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)
    [[ -n $signature ]] || return 0
  fi
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl reload >/dev/null 2>&1 || return 0
  if [[ -n $(HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl configerrors 2>/dev/null | tr -d '[:space:]') ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl reload >/dev/null 2>&1 || true
  fi
  printf 'Reloaded the Hyprland configuration.\n'
}

# Reload the running session from the stable copy: Hyprland only when its
# configuration changed, the shell when anything it loads changed.
reload_changes() {
  local from=$1 to=$2 changed
  $reload || { printf 'Skipped reloading (--no-reload).\n'; return 0; }
  changed=$(git_stable diff --name-only "$from" "$to")
  # An empty diff is one empty line to a here-string, and `grep -v` matches it
  # against nothing and succeeds - so a deploy that changed no file at all
  # restarted the shell and said so. The same predicate is what keeps a
  # docs-only deploy from restarting it, so it has to be right about nothing
  # too.
  if [[ -z $changed ]]; then
    printf 'No files changed; the shell keeps running.\n'
    return 0
  fi
  if grep -q '^hypr/' <<<"$changed"; then
    reload_hyprland
  fi
  if grep -qvE '^(hypr/|[^/]+\.md$|docs/|Promt$|tests/|install/|session/sddm/|\.gitignore$)' <<<"$changed"; then
    "$stable_dir/scripts/reload-shell.sh"
    printf 'Restarted the shell.\n'
  else
    printf 'No shell files changed; the shell keeps running.\n'
  fi
}

case "$action" in
  status)
    if ! have_stable; then
      printf 'No stable worktree at %s (run scripts/deploy.sh --init).\n' "$stable_dir"
      exit 0
    fi
    deployed=$(git_stable rev-parse --short HEAD)
    target=$(git_dev rev-parse --short "$ref")
    printf 'Deployed: %s %s\n' "$deployed" "$(git_stable log -1 --format=%s)"
    printf '%-9s %s %s\n' "$ref:" "$target" "$(git_dev log -1 --format=%s "$ref")"
    printf 'Commits not deployed: %s\n' "$(git_dev rev-list --count "$(git_stable rev-parse HEAD)..$ref")"
    link=$(readlink -f -- "$HOME/.local/share/buchhwin-shell" 2>/dev/null || true)
    printf 'Session link: %s\n' "${link:-missing}"
    exit 0
    ;;

  init)
    if have_stable; then
      printf 'Stable worktree already exists at %s\n' "$stable_dir"
    else
      commit=$(git_dev rev-parse --verify "$ref^{commit}")
      if git_dev show-ref --verify --quiet refs/heads/stable; then
        git_dev worktree add "$stable_dir" stable
        git -C "$stable_dir" merge --ff-only "$commit"
      else
        git_dev worktree add -b stable "$stable_dir" "$commit"
      fi
      printf 'Created the stable worktree at %s (%s)\n' "$stable_dir" "$(git_stable rev-parse --short HEAD)"
    fi
    # Point ~/.local/share/buchhwin-shell and the other session links at the
    # stable copy (existing links are backed up by install.sh).
    "$stable_dir/install/install.sh" --apply
    if $reload; then
      "$stable_dir/scripts/reload-shell.sh"
      printf 'Restarted the shell from the stable worktree.\n'
    fi
    exit 0
    ;;
esac

if ! have_stable; then
  printf 'deploy: no stable worktree at %s; run scripts/deploy.sh --init first\n' "$stable_dir" >&2
  exit 1
fi
if [[ -n $(git_stable status --porcelain --untracked-files=no) ]]; then
  printf 'deploy: the stable worktree has local changes; not touching it\n' >&2
  git_stable status --short --untracked-files=no >&2
  exit 1
fi
previous=$(git_stable rev-parse HEAD)

if [[ $action == rollback ]]; then
  target=$(git_stable rev-parse --verify --quiet refs/tags/deploy-previous || true)
  if [[ -z $target ]]; then
    printf 'deploy: nothing to roll back to (no deploy-previous tag)\n' >&2
    exit 1
  fi
  git_stable reset --hard "$target" >/dev/null
  git_dev tag -f deploy-previous "$previous" >/dev/null
  printf 'Rolled back stable from %s to %s\n' "$(git_dev rev-parse --short "$previous")" "$(git_dev rev-parse --short "$target")"
  reload_changes "$previous" "$target"
  exit 0
fi

target=$(git_dev rev-parse --verify "$ref^{commit}")
if [[ $target == "$previous" ]]; then
  printf 'Already deployed: %s\n' "$(git_dev log -1 --format='%h %s' "$target")"
  exit 0
fi
if ! git_dev merge-base --is-ancestor "$previous" "$target"; then
  printf 'deploy: %s does not contain the deployed commit %s (no fast-forward)\n' "$ref" "$(git_dev rev-parse --short "$previous")" >&2
  exit 1
fi
if [[ $ref == main && -n $(git_dev status --porcelain --untracked-files=no) ]]; then
  printf 'deploy: the development checkout has uncommitted changes; commit them first\n' >&2
  exit 1
fi

if $run_tests; then
  if [[ $(git_dev rev-parse HEAD) != "$target" ]]; then
    printf 'deploy: tests run on the checked-out commit; check out %s or pass --no-test\n' "$ref" >&2
    exit 1
  fi
  printf 'Running scripts/test.sh --session …\n'
  if ! BUCHHWIN_NESTED_DIR=${BUCHHWIN_NESTED_DIR:-/tmp/buchhwin-nested-deploy} "$project_dir/scripts/test.sh" --session; then
    printf 'deploy: tests failed; stable stays at %s\n' "$(git_dev rev-parse --short "$previous")" >&2
    exit 1
  fi
fi

git_stable merge --ff-only --quiet "$target"
git_dev tag -f deploy-previous "$previous" >/dev/null
printf 'Deployed %s → %s:\n' "$(git_dev rev-parse --short "$previous")" "$(git_dev rev-parse --short "$target")"
git_dev log --oneline "$previous..$target" | sed 's/^/  /'
reload_changes "$previous" "$target"
