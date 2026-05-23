# Installing Animus on another device

**Prereqs:** `git`, `python3`, and Claude Code (CLI / desktop / web / IDE).

### 1. Clone the repo
```bash
git clone https://github.com/kummatty/animus.git ~/animus
```
(The clone path can be anything — `~/animus` is just a suggestion.)

### 2. Symlink it into your personal skills directory
This is how Claude Code discovers the skill. The symlink name **must** be `animus`:
```bash
mkdir -p ~/.claude/skills
ln -s ~/animus ~/.claude/skills/animus
```
On Windows (admin terminal): `mklink /D "%USERPROFILE%\.claude\skills\animus" "<clone-path>"`, or just copy the folder there.

### 3. Verify
In Claude Code, say *"store this in my knowledge base"* or *"quiz me"*. Claude should pick up the `animus` skill.

### Syncing
- Storing a concept auto-commits and pushes.
- To pull updates made on another device:
  ```bash
  bash ~/.claude/skills/animus/scripts/sync.sh --pull
  ```
  or just tell Claude *"sync my knowledge base"*.

### Phone note
The skill automation (dedup, index, quiz, auto-sync) needs Claude Code, which runs on CLI / desktop / web / IDE — not the phone app. But since everything is plain markdown in this repo, you can still **read and search your notes** from the GitHub mobile app or website on a phone, and point mobile Claude at the repo manually.
