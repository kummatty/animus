#!/usr/bin/env bash
# Sync the Animus knowledge base with GitHub.
#   scripts/sync.sh "commit message"   -> stage all, commit, push
#   scripts/sync.sh --pull             -> pull latest from remote (rebase)
set -uo pipefail

KB="${ANIMUS_HOME:-$HOME/.claude/skills/animus}"
cd "$KB" || { echo "Cannot cd to $KB"; exit 1; }

branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
has_upstream() { git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; }

if [ "${1:-}" = "--pull" ]; then
  if has_upstream; then
    git pull --rebase --autostash
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
  git pull --rebase --autostash || true
  git push
else
  git push -u origin "$branch"
fi
