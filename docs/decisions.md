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
| 2026-10-11 | Instruments: dial faces drawn once into textures + 3D needles; horizon/turn/compass faces redraw per frame. One panel scene per aircraft, positioned from the eyepoint | Crisp, cheap, and every aircraft's panel is data |
| 2026-10-11 | 172 eyepoint moved to the left seat (y −14 in) | Stock JSBSim had it on the centreline |
| 2026-10-11 | Placeholder sounds synthesised live from FDM data (no audio files) | Hear something now; recorded engine sounds replace the synth later with the same inputs |
| 2026-10-11 | Perf note: 172 cockpit ~90 fps, Cub ~145 fps uncapped at 1080p (M4) | Within the 60 fps budget; watch as cockpit detail grows |
| 2026-10-11 | Start procedure modelled on top of JSBSim by withholding spark until a start would catch (prime, flooding, warmth) | JSBSim starts any engine with spark + fuel + rpm |
| 2026-10-11 | Cub is hand-propped: pull through with switch OFF primes, each 'contact' swing is one chance to catch | Period-correct J-3, no electrics |
| 2026-10-11 | Spawn cold and dark in the test world; Ctrl+E auto-start assist | Assists are options, not defaults (design.md) |
| 2026-10-11 | Carb heat = higher intake impedance (~80 rpm drop) | Same hook carb icing will use in Phase 2 |
| 2026-10-11 | JSBSim gotcha: propulsion/set-running = N starts engine N; stop via propulsion/engine[i]/set-running = 0 | Cost a debugging round; documented in fdm.gd |
| 2026-10-11 | Cockpit clicks hit-tested in aircraft space, not physics | Physics positions lag the interpolated camera by up to 0.5 m at cruise |
