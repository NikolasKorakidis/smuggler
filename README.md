# Smuggler

Private dev repo. Godot 4.7 + JSBSim.

## Setup (once, ~20 minutes)

1. **External drive:** make sure the folder you use is on an **APFS** volume (Finder → Get Info → Format). exFAT breaks Git and Godot imports.
2. Copy this `smuggler` folder onto the drive.
3. Install **VS Code**: https://code.visualstudio.com
4. In VS Code: Extensions (⇧⌘X) → search **Claude Code** → Install → sign in with your Claude account.
5. File → Open Folder → pick `smuggler`.
6. Open the Claude Code panel and paste:

   > Run `scripts/bootstrap.sh --install`, then start Phase 0 from `docs/tasks.md`.

From then on: open the folder, open Claude Code, say what you want. Godot runs in its own window for flying.

## Daily session
1. Open VS Code on this folder → Claude Code panel.
2. Say: `Continue from docs/tasks.md.`
3. Fly what Claude asks you to test. Give feedback like: "at 55 kt with full flaps the nose drops too fast."
4. Claude ends with a short summary of what changed and what's next.

## Layout
```
CLAUDE.md          brief Claude Code reads every session
docs/design.md     game design (your kickoff answers)
docs/roadmap.md    phases and gates
docs/tasks.md      current phase task list
docs/decisions.md  decision log
scripts/           setup and tooling
game/              Godot project (created in Phase 0)
extensions/        JSBSim ↔ Godot bridge (Phase 0)
tests/fdm/         headless flight-model tests (Phase 0)
```
