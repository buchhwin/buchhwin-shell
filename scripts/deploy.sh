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

# The reload itself is shared with scripts/shell-update.sh, which does for a
# clone that follows its remote what this does for the stable worktree.
# shellcheck source=lib/reload.sh
source "$project_dir/scripts/lib/reload.sh"

# Reload the running session from the stable copy: Hyprland only when its
# configuration changed, the shell when anything it loads changed.
reload_changes() {
  $reload || { printf 'Skipped reloading (--no-reload).\n'; return 0; }
  reload_for_changes "$stable_dir" "$1" "$2"
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
  # The smoke test starts a nested session of its own. A second one - one
  # started by hand, or an agent's - shares the runtime directory with it and
  # poisons the run (docs/testing.md, Pitfalls): the failure then looks like a
  # regression in the commit under test. Count first. One instance is the
  # session itself; none is a terminal outside any session.
  instances=$(hyprctl instances 2>/dev/null | grep -c '^instance ' || true)
  if (( instances > 1 )); then
    printf 'deploy: another nested session is running (%s Hyprland instances); stop it before deploying\n' "$instances" >&2
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
