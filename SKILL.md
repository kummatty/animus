---
name: animus
description: >-
  Personal knowledge base for things the user learns. Use this skill when the user wants to
  STORE a concept/idea/fact/web-finding ("save this", "add to my knowledge base", "remember
  this concept", "note this down"), BROWSE or look up what they already know ("what do I have
  on X", "show my notes on Y", "list my knowledge base"), REVISE/review a topic, or be QUIZZED
  on previously stored concepts ("quiz me", "test me on networking"). Also handles syncing the
  knowledge base across devices. Backed by a git repo of markdown at ~/.claude/skills/animus.
---

# Animus — Personal Knowledge Base

A personal knowledge base of concepts the user has learned (from conversations with Claude or
from the web). Everything is plain markdown in a git repo, so it is portable, version-controlled,
and synced across devices via GitHub.

## Location & layout

The knowledge base lives at the absolute path `~/.claude/skills/animus` (a symlink to the
cloned repo — identical on every device). **Always use this absolute path in shell commands.**
This skill can be invoked from *any* project, so never assume the current working directory is
the KB, and never use relative paths like `scripts/sync.sh` — they break when run from
elsewhere. (The scripts themselves `cd` to this path first, so once invoked correctly they only
ever act on the KB repo, never your current project.)

```
~/.claude/skills/animus/
├─ SKILL.md                         # this file
├─ INDEX.md                         # auto-generated catalog (do NOT hand-edit)
├─ entries/<topic>/<slug>.md        # one concept per file
└─ scripts/
   ├─ rebuild-index.py              # regenerates INDEX.md from entry frontmatter
   └─ sync.sh                       # git commit + push, or --pull
```

## Entry format

Every concept is one file: `~/.claude/skills/animus/entries/<topic>/<slug>.md` where `<topic>` is a short
lowercase folder (e.g. `networking`, `rust`, `economics`) and `<slug>` is a kebab-case title.

```markdown
---
title: <Human Readable Title>
slug: <kebab-case-slug>
topic: <topic>
tags: [tag1, tag2]
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
source: conversation        # or: web (include URL in References)
---

## Summary
One plain-language paragraph — the elevator pitch of the concept. Avoid jargon;
if a term is unavoidable, gloss it briefly.

## Details
The full explanation: nuance, derivations, diagrams-as-text. When the concept is
technical, include at least one worked example, code block, or diagram — don't
just describe it abstractly.

## Key points
- Each bullet is one self-contained, testable fact, phrased so it could stand alone
  as a quiz question. These are exactly what quiz mode draws from, so favor concrete
  facts over vague restatements.

## References
- Links / sources. For `source: web`, a URL is mandatory; include the access date.

## Related
- `[Other Title](../<other-topic>/<other-slug>.md)` — relative repo-path links, so they
  click through both on GitHub and in local markdown viewers. Same-topic link drops the
  `../`: `[Title](<other-slug>.md)`. Always attempt at least one link; if none fit, write
  "(none yet)" so it's clear the check was done.
```

Get today's date with `date +%F` before writing (used for `created`/`updated`).

## Accuracy & sourcing (vet before writing or expanding any entry)

The knowledge base must contain only things that are actually true and traceable —
never invented detail.

- **Only assert what is verifiable.** A claim is OK to write if it came from (a) the
  user — stated or explicitly confirmed by them as true, (b) the conversation we just
  had, or (c) a credible source — official docs, peer-reviewed papers, primary sources,
  or well-established reference material.
- **Never fabricate specifics.** Do not invent URLs, citations, version numbers,
  function/API names, quotes, statistics, or dates. No real value → don't write a
  plausible-looking one.
- **When unsure, resolve it — don't guess.** Either verify against the official source
  (look it up), ask the user, or leave it out. If something is useful but unconfirmed,
  label it inline ("Unverified —" / "recollection, not confirmed") rather than stating
  it as fact.
- **References must be real** — sources actually seen, not reconstructed from memory.

These rules reduce errors but can't make them impossible; prefer verifying load-bearing
facts against a primary source at store time.

## Modes

### 1. STORE  (the user wants to save something)

1. **Pull latest** (best-effort, so dedup sees other devices' entries):
   `bash ~/.claude/skills/animus/scripts/sync.sh --pull`
2. **Dedup check — do this before writing anything.**
   - Read `~/.claude/skills/animus/INDEX.md` to scan existing titles, topics, tags, and one-liners.
   - Also `grep -ri "<key term>" ~/.claude/skills/animus/entries` for the concept's main keywords.
   - Decide which case applies and **tell the user what you found**:
     - **Exact/near duplicate** → don't create a second file. Offer to expand the existing
       entry instead, or skip if nothing new.
     - **Related but distinct** → create a new entry, and cross-link it via `Related`
       (relative repo-path markdown links, e.g. `[Title](../topic/slug.md)`) in both files.
     - **Genuinely new** → create a new entry; mention nearby topics if any.
   - When it's ambiguous (could append vs. could be new), **ask the user** which they prefer.
3. **Vet for accuracy** per `## Accuracy & sourcing` — confirm or flag every factual
   claim before writing; do not add anything you can't trace.
4. **Write or update the entry:**
   - *New:* pick a topic folder (reuse an existing one if it fits, else make a new one),
     slugify the title, and write `entries/<topic>/<slug>.md` using the template above with
     real content drawn from the conversation. Set `created` and `updated` to today.
   - *Append:* edit the existing file — add to Details / Key points, add any new tags, and
     bump `updated` to today.
5. **Rebuild the index:** `python3 ~/.claude/skills/animus/scripts/rebuild-index.py`
6. **Sync to GitHub:** `bash ~/.claude/skills/animus/scripts/sync.sh "store: <title>"`
7. **Confirm** to the user: the entry path, whether it was new or expanded, and a one-line summary.

### 2. BROWSE  (the user wants to look something up or list what they have)

- "What do I have on X" / "show my notes on Y": `grep -ri` the term across `INDEX.md` and
  `entries/`, then list matches as `topic / title — one-liner`, and offer to open any in full.
- "List my knowledge base" / general browse: show `INDEX.md` (grouped by topic). If it looks
  stale, run `rebuild-index.py` first.

### 3. REVISE  (the user wants to review/re-read)

- Ask for scope if unclear: a topic, a tag, or "recent". Pull latest first.
- Read the relevant entries and present them for review: **Summary first, then Key points**,
  expanding to Details on request. Keep it readable, not a raw dump.

### 4. QUIZ  (on-demand — the user wants to be tested)

- Determine scope: everything, a topic/tag, "recent", or a question count. Pull latest first.
- Read the relevant entries (focus on their **Key points** and Details).
- Ask questions **one at a time**, then wait for the answer. Mix formats: recall, "explain in
  your own words", fill-in-the-blank, and "why/how" questions.
- After each answer: grade it, give the correct answer + a brief explanation, and cite the
  entry it came from (`topic/slug`).
- At the end: summarize the score and list the concepts worth revisiting. If the user wants,
  offer to add a note or new entry capturing what was fuzzy. (Quiz is on-demand — no schedule
  tracking is stored.)

### SYNC  (explicit)

- "Sync / pull my knowledge base from other devices": `bash ~/.claude/skills/animus/scripts/sync.sh --pull`
- A normal store already commits + pushes via `sync.sh`.
- **Conflicts are never auto-resolved or masked.** If a pull/rebase conflicts (or a push is
  rejected), `sync.sh` stops and reports it — surface that to the user verbatim and let them
  resolve it (`git rebase --continue` after fixing, or `git rebase --abort`). Do not edit the
  conflicted files yourself.

## Conventions

- Keep topics few and broad; prefer tags for finer cross-cutting labels.
- Never hand-edit `INDEX.md` — always regenerate it with `rebuild-index.py`.
- One concept per file. If a "concept" is really several, split it and cross-link.
- Prefer expanding an existing entry over creating near-duplicates.
