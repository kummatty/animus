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
Animus is a personal knowledge base implemented as a Claude Code skill backed by a GitHub repo of markdown files. You tell Claude to "store" things you learn; Claude vets the content, saves it as a structured entry, dedupes against what already exists, and can later browse, revise, or quiz you on it.

## Details
- Each concept is one markdown file at `entries/<topic>/<slug>.md` with YAML frontmatter (title, tags, created/updated dates, source).
- Entries follow a fixed template (`## Entry format` in `SKILL.md`): Summary, Details, Key points, References, Related. There are no length/count caps — guidance is qualitative (e.g. technical concepts should carry a worked example, code block, or diagram).
- **Accuracy is vetted before writing.** Claude only asserts what is verifiable — facts you stated or confirmed, the conversation itself, or credible sources (official docs, papers, primary sources). It never fabricates URLs, citations, versions, quotes, or dates; anything unconfirmed is flagged inline rather than stated as fact.
- **`Related` uses relative repo-path links** like `[Title](../topic/slug.md)`, so they click through both on GitHub and in local markdown viewers (the old `[[wiki]]` style is not clickable on GitHub).
- `INDEX.md` is an auto-generated catalog (`scripts/rebuild-index.py`) used for fast browsing and duplicate detection — never hand-edited.
- `scripts/sync.sh "msg"` stages, commits, pulls `--rebase`, then pushes; `sync.sh --pull` just fetches changes made on other devices.
- **Conflicts are never masked or auto-resolved.** On a rebase conflict (or a rejected push) `sync.sh` stops, reports what to do (`git rebase --continue` / `--abort`), and leaves the repo for you to resolve — nothing is pushed.
- The skill lives in the same repo and is symlinked into `~/.claude/skills/animus`, so cloning the repo on a new device and symlinking it installs the skill there too.

## Key points
- Storing a concept = vet for accuracy → write/expand the entry file → rebuild INDEX → commit + push.
- Duplicate detection happens at store time, by searching INDEX.md and existing entries before writing anything.
- Only verifiable information is stored: sourced from you, the conversation, or credible references — never hallucinated detail.
- Related entries are linked with relative repo paths (`../topic/slug.md`) so navigation works on GitHub and offline.
- Sync is commit → pull --rebase → push; a conflict or rejected push halts it loudly and is left for you to fix, never silently swallowed.
- The quiz is on-demand: say "quiz me" (optionally on a topic/tag) and Claude tests you from your stored Key points — no schedule is tracked.
- Because it's plain markdown in git, the notes stay readable and portable anywhere, even without the skill.

## References
- Built with Claude Code skills.

## Related
- (none yet)
