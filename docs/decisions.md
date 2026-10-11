# Decisions log

| Date | Decision | Why |
| --- | --- | --- |
| 2026-10-11 | Godot 4.7 + JSBSim via GDExtension | Free, runs on MacBook, real 6-DOF flight model, aircraft as data |
| 2026-10-11 | Claude Code in VS Code is the main workspace | Same agent as the terminal, plus visible files, diffs and an integrated terminal |
| 2026-10-11 | Repo **public** (`NikolasKorakidis/smuggler`) | Nikolas wants to share it and invite contributors; accepts that design docs and code are visible |
| 2026-10-11 | Cessna 172 is the feel benchmark | Nikolas knows it well from MSFS |
| 2026-10-11 | JSBSim v1.3.2 and godot-cpp 10.0.0 pinned as submodules; Python tests use jsbsim==1.3.2 | Game and tests run identical physics; godot-cpp 10 targets the Godot 4.7 API |
| 2026-10-11 | One folder per aircraft in `game/aircraft/<Model>/`: JSBSim XML (+ Engines/, Systems/) and a Godot `.tres` | Aircraft are data; the game and `tests/fdm` load the same files |
| 2026-10-11 | JSBSim steps once per Godot physics tick (120 Hz), physics interpolation on | Fixed-rate FDM, smooth rendering at any frame rate |
| 2026-10-11 | Tutorial Cub: prop `cp_factor 0.44`, `ct_factor 0.66`, added airframe drag 0.034 | Stock model: 1440 static rpm, 87 kt top speed. Now ~2100 rpm, 77 kt, 450 fpm, stall ~34 KCAS |
| 2026-10-11 | Joystick bindings made in-game (F2) by moving the control; stored per device GUID | HOTAS/pedal axis numbers differ per OS and driver; no guessing |
| 2026-10-11 | Placeholder airframe generated from each aircraft's JSBSim data | Any new aircraft is flyable and visible before its model exists |
| 2026-10-11 | Ground surface (grass/paved/rough) sets JSBSim's global ground friction from where the aircraft is | JSBSim ignores per-wheel surface factors |
| 2026-10-11 | T.Flight Hotas 5 must be in PC mode (green LED); built-in default bindings by USB id | PlayStation mode hides throttle/pedal axes from macOS |
| 2026-10-11 | Phase 0 gate passed (HOTAS circuit flown by Nikolas) | — |
| 2026-10-11 | 172-type tuned: BSFC 0.43 (was 0.32), prop cp 0.80 / ct 1.08, +0.014 parasite drag, CL ×1.10 | Stock engine made ~226 hp. Now at 2400 lb: 710 fpm, 122 kt, 911 ft roll, stall 51.5/46.9 KCAS vs 700/123/890/51/46 published |
| 2026-10-11 | Physics tests for the 172 run at 2400 lb max gross | Published figures are at max gross |
| 2026-10-11 | Joystick axes ignored until they first move | macOS reports unmoved axes as centred: throttle read 50%, toe brakes 50% at start-up |
| 2026-10-11 | Flap notches defined per aircraft in its .tres | Aircraft are data; Cub has none, 172 has 0/10/20/30° |
