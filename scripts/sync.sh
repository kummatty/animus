#!/usr/bin/env bash
# Sync the Animus knowledge base with GitHub.
#   scripts/sync.sh "commit message"   -> stage all, commit, pull --rebase, push
#   scripts/sync.sh --pull             -> pull latest from remote (rebase)
#
# Conflicts are never masked or auto-resolved: on a rebase conflict (or a rejected
# push) the script stops, reports it, and leaves the repo as-is for you to resolve.
set -uo pipefail

KB="${ANIMUS_HOME:-$HOME/.claude/skills/animus}"
cd "$KB" || { echo "Cannot cd to $KB"; exit 1; }

branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
has_upstream() { git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; }

# Pull with rebase. On conflict, stop loudly and leave the repo for the user to fix.
pull_rebase() {
  if ! git pull --rebase --autostash; then
    echo ""
    echo "⚠️  Merge conflict during rebase — sync STOPPED. Nothing was pushed."
    echo "    Resolve the files below, then:  git rebase --continue"
    echo "    Or to back out entirely:        git rebase --abort"
    git status --short
    exit 1
  fi
}

if [ "${1:-}" = "--pull" ]; then
  if has_upstream; then
    pull_rebase
  else
    echo "No upstream set yet; nothing to pull."
  fi
  exit 0
fi

msg="${1:-kb update $(date '+%Y-%m-%d %H:%M')}"

git add -A
if git diff --cached --quiet; then
  echo "Nothing to commit."
else
  git commit -m "$msg"
fi

if has_upstream; then
  pull_rebase
  if ! git push; then
    echo ""
    echo "⚠️  Push was rejected — sync STOPPED. Your commit is local only."
    echo "    The remote likely moved on. Run 'scripts/sync.sh --pull', then sync again."
    exit 1
  fi
else
  git push -u origin "$branch"
fi
