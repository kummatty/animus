# Animus

A personal knowledge base, implemented as a [Claude Code](https://claude.com/claude-code) skill backed by this git repo. Tell Claude what you learn; it stores each concept as structured markdown, dedupes against what's already here, and can browse, revise, or quiz you later.

## What's here
- **`SKILL.md`** — the skill Claude loads (store / browse / revise / quiz + dedup + sync).
- **`entries/<topic>/<slug>.md`** — one concept per file, with frontmatter.
- **`INDEX.md`** — auto-generated catalog (don't hand-edit).
- **`scripts/`** — `rebuild-index.py` (regenerate the catalog) and `sync.sh` (commit/push or `--pull`).
- **`INSTALL.md`** — how to set this up on another device.

## Quick start
Install on a device (see [INSTALL.md](INSTALL.md)), then in Claude Code:
- *"Store this: …"* / *"add this to my knowledge base"* — save a concept (dedup-checked).
- *"What do I have on X?"* / *"list my knowledge base"* — browse.
- *"Let's revise networking"* — review a topic.
- *"Quiz me on X"* — get tested from your stored notes.

Everything is plain markdown, so your notes remain readable and portable even without the skill.
