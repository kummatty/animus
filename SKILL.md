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

`KB_ROOT = ~/.claude/skills/animus` (a symlink to the cloned repo — this path is identical on
every device, so always reference it).

```
$KB_ROOT/
├─ SKILL.md                         # this file
├─ INDEX.md                         # auto-generated catalog (do NOT hand-edit)
├─ entries/<topic>/<slug>.md        # one concept per file
└─ scripts/
   ├─ rebuild-index.py              # regenerates INDEX.md from entry frontmatter
   └─ sync.sh                       # git commit + push, or --pull
```

## Entry format

Every concept is one file: `$KB_ROOT/entries/<topic>/<slug>.md` where `<topic>` is a short
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
One short plain-language paragraph — the elevator pitch of the concept.

## Details
The full explanation: nuance, examples, code, derivations, diagrams-as-text.

## Key points
- Bullet facts that are individually testable. These are what the quiz mode draws from.

## References
- Links / sources (URLs for web findings).

## Related
- [[other-slug]] links to related entries.
```

Get today's date with `date +%F` before writing (used for `created`/`updated`).

## Modes

### 1. STORE  (the user wants to save something)

1. **Pull latest** (best-effort, so dedup sees other devices' entries):
   `bash $KB_ROOT/scripts/sync.sh --pull`
2. **Dedup check — do this before writing anything.**
   - Read `$KB_ROOT/INDEX.md` to scan existing titles, topics, tags, and one-liners.
   - Also `grep -ri "<key term>" $KB_ROOT/entries` for the concept's main keywords.
   - Decide which case applies and **tell the user what you found**:
     - **Exact/near duplicate** → don't create a second file. Offer to expand the existing
       entry instead, or skip if nothing new.
     - **Related but distinct** → create a new entry, and cross-link it via `Related`
       (`[[slug]]`) in both files.
     - **Genuinely new** → create a new entry; mention nearby topics if any.
   - When it's ambiguous (could append vs. could be new), **ask the user** which they prefer.
3. **Write or update the entry:**
   - *New:* pick a topic folder (reuse an existing one if it fits, else make a new one),
     slugify the title, and write `entries/<topic>/<slug>.md` using the template above with
     real content drawn from the conversation. Set `created` and `updated` to today.
   - *Append:* edit the existing file — add to Details / Key points, add any new tags, and
     bump `updated` to today.
4. **Rebuild the index:** `python3 $KB_ROOT/scripts/rebuild-index.py`
5. **Sync to GitHub:** `bash $KB_ROOT/scripts/sync.sh "store: <title>"`
6. **Confirm** to the user: the entry path, whether it was new or expanded, and a one-line summary.

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

- "Sync / pull my knowledge base from other devices": `bash $KB_ROOT/scripts/sync.sh --pull`
- A normal store already commits + pushes via `sync.sh`.

## Conventions

- Keep topics few and broad; prefer tags for finer cross-cutting labels.
- Never hand-edit `INDEX.md` — always regenerate it with `rebuild-index.py`.
- One concept per file. If a "concept" is really several, split it and cross-link.
- Prefer expanding an existing entry over creating near-duplicates.
