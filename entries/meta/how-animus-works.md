---
title: How Animus works
slug: how-animus-works
topic: meta
tags: [meta, knowledge-base, claude]
created: 2026-05-23
updated: 2026-05-23
source: conversation
---

## Summary
Animus is a personal knowledge base implemented as a Claude Code skill backed by a GitHub repo of markdown files. You tell Claude to "store" things you learn; Claude saves them as structured entries, dedupes against what already exists, and can later browse, revise, or quiz you on them.

## Details
- Each concept is one markdown file at `entries/<topic>/<slug>.md` with YAML frontmatter (title, tags, created/updated dates, source).
- `INDEX.md` is an auto-generated catalog (`scripts/rebuild-index.py`) used for fast browsing and duplicate detection — never hand-edited.
- `scripts/sync.sh` commits and pushes to GitHub so every device stays in sync; `sync.sh --pull` fetches changes made elsewhere.
- The skill lives in the same repo and is symlinked into `~/.claude/skills/animus`, so cloning the repo on a new device and symlinking it installs the skill there too.

## Key points
- Storing a concept = a new (or expanded) entry file + an INDEX rebuild + a git commit/push.
- Duplicate detection happens at store time, by searching INDEX.md and existing entries before writing anything.
- The quiz is on-demand: say "quiz me" (optionally on a topic/tag) and Claude tests you from your stored Key points — no schedule is tracked.
- Because it's plain markdown in git, the notes stay readable and portable anywhere, even without the skill.

## References
- Built with Claude Code skills.

## Related
- (none yet)
