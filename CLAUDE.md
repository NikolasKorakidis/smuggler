# CLAUDE.md — Smuggler

This file is read by Claude Code at the start of every session. Keep it short and current.

## What this project is
**Smuggler**: a single-player flight game set in a fictional 1978–1988 world. The player smuggles cargo by plane, starting with a cheap, worn-out aircraft and working up to better ones. Physics and weather come first; graphics serve them.

Owner: Nikolas (test pilot, art director, final say on feel). Claude writes and tests the code.

## Stack (do not change without discussing with Nikolas)
- **Engine:** Godot 4.7.x, GDScript (standard build, not .NET)
- **Flight dynamics:** JSBSim (C++, LGPL), linked through a GDExtension in `extensions/jsbsim_gd/`
- **Physics tests:** JSBSim Python package, headless, in `tests/fdm/`
- **3D assets:** Blender (imported models, Claude rigs and animates via the Blender bridge)
- **Version control:** Git + GitHub
- **Dev machine:** MacBook (macOS 26), Apple Silicon. Project lives on an external drive.
- **Input:** Thrustmaster HOTAS (T.Flight HOTAS 4/5 class), Thrustmaster rudder pedals, keyboard/mouse, PS4/PS5 pads

## Commands
- Build bridge: `scripts/build_extension.sh` (rebuild after any change in `extensions/`)
- Physics tests: `.venv/bin/pytest tests/fdm`
- Godot smoke test (takeoff in-engine): `godot --headless --path game --fixed-fps 60 res://dev/smoke_test.tscn -- --aircraft=0` (1 = 172)
- Full tutorial flight (scripted pilot): `godot --headless --path game --fixed-fps 120 res://dev/tutorial_flight_test.tscn -- --aircraft=1` (0 = Cub)
- Checklist walk (both aircraft): `godot --headless --path game --fixed-fps 120 res://dev/checklist_test.tscn`
- Engine start tests: `godot --headless --path game --fixed-fps 120 res://dev/engine_test.tscn`
- JSBSim sign conventions: elevator −1 = nose up, rudder +1 = nose LEFT, steering +1 = nose right. The input layer handles this once for all aircraft.

## Source of truth
- `docs/design.md` — game design decisions (from Nikolas's kickoff answers)
- `docs/roadmap.md` — phases and gates
- `docs/tasks.md` — current phase task list; tick items as they are done
- `docs/decisions.md` — log every non-trivial decision: date, what, why

Read `docs/tasks.md` before starting work. Update it before ending a session.

## How to work with Nikolas
- He does **not** want to learn the code. Don't explain implementation unless asked. Explain **what changed and what to test**.
- End every session with a **short summary in chat**: what changed, what to fly/test, what's next. 5 lines max.
- Design disagreements: **discuss**. Propose, give the trade-off in one or two lines, let him decide.
- Be direct. No hype. Flag risks and scope problems plainly.
- Sessions are daily, 2–3 hours. Keep each change testable within one session.

## Engineering rules
- Work on a branch per feature; merge to `main` only after Nikolas has flown it.
- Every aircraft is data (JSBSim XML + a Godot `.tres` for visuals/sounds). No aircraft-specific code paths.
- Every flight model change must pass `tests/fdm/` before Nikolas tests it. Benchmark: real Cessna 172 numbers (he knows it well from MSFS).
- Performance budget: 60 fps at 1080p on the MacBook. Check it after every visual feature.
- Weather state is one object that feeds **both** JSBSim (wind, gusts, turbulence, density) and the visuals. Never fake one without the other.
- No HUD in flight. Information comes from instruments and the paper map only.
- Commit messages: imperative, short, what changed.

## Content rules
- All aircraft, companies, places and people are fictional. No real manufacturer names or logos in game.
- The repo is public. Store pages, YouTube and other public material must not reveal game details Nikolas hasn't approved for release.
