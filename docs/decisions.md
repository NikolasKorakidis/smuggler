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
| 2026-10-11 | On-screen checklist (top right) that ticks itself; optional, K hides | Teaches the start procedure; an aid like the assists, not a flight HUD |
| 2026-10-11 | Checklist guidance: only the current section open, big NEXT STEP box, pulsing ring on the cockpit part to use (5th column in checklist.txt) | Nikolas: easier, more visual step-by-step help |
| 2026-10-11 | Parking brake toggle (. key, bindable HOTAS button, 172 knob); checklists set and release it | Requested; frees the hands during run-up |
| 2026-10-11 | The checklist doubles as the tutorial: sections can 'until:' a later event so skipped checks never block it | Cub list got stuck when a check was skipped and Nikolas took off |
| 2026-10-11 | Tutorial navigation uses a real landmark (radio tower) plus distance/clock hints in the checklist, not a HUD marker | Keeps the no-HUD rule for flying; hints are part of the optional aid |
| 2026-10-11 | Hangar apron is paved; parking square is the tutorial end point | Gives the taxi-in a clear target |
| 2026-10-11 | Automated tutorial flight test with a scripted pilot for both aircraft | Proves the whole tutorial can be completed after every change |
| 2026-10-11 | Merged parallel agent branches feature/engine-sound and feature/terrain-tile into phase1-172 | Work done in parallel worktrees; no file overlaps, all tests pass after merge |
| 2026-10-11 | JSBSim ground contact via a Godot callback (height + normal per wheel) | Slopes and hills under each wheel; flat world unchanged |
| 2026-10-11 | Terrain tile is the default world; flat test world kept for fast tests | Phase 1 goal; tutorial verified on both |
| 2026-10-11 | Worlds share a tutorial interface: point(), strip_heading(), strip_length(), on_strip(); tower and parking square in world/landmarks.gd | Same checklist/tutorial works in any world |
| 2026-10-11 | 172 flaps: drag 0.020/0.045/0.075 (stock 0.007/0.012/0.018), flap pitch moment less nose-down (-0.035/-0.048/-0.054) | Nikolas: flaps at 80 kt felt like nothing. Now ~+7° nose-up balloon and ~-20 kt at full flaps hands-off; tests added |
| 2026-10-11 | Tutorial altitudes are 'above the field' and hints give the altimeter reading | AGL over hills never matched the altimeter; the 1000 ft step didn't tick |
| 2026-10-11 | 'Look at objective' (L / bindable button, hold): view turns to tower/strip/hangar with name + distance label | Nikolas: how do I know where the tower is? Tutorial aid, not a flight HUD |
| 2026-10-11 | Step-done toast + chime in the checklist | Clearer feedback that a step ticked |
| 2026-10-11 | Phase 2 started before the scope/date decision | Weather is needed in both release options; scope decided before Phase 3 |
| 2026-10-11 | Wind model: power-law boundary layer (alpha 0.143) to 300 m, blending to the wind aloft by ~1000 m, veering with height; gusts as discrete events (rise 1-2 s, hold, decay) | Simple, believable, testable; JSBSim Dryden turbulence on top |
| 2026-10-11 | On the ground the relative wind is never allowed to come from behind | JSBSim aero tables only cover forward flow; a parked 172 flipped in a 20 kt tailwind |
| 2026-10-11 | Altimeter reads pressure altitude + (setting - 29.92) x 1000 ft; starts at 29.92 each flight | Teaches setting the altimeter; matters with low/high pressure presets |
| 2026-10-11 | Cub brake strength 0.3 (weak J-3 heel brakes); per-aircraft brake_strength | Stock JSBSim Cub noses over above ~30% braking; full brakes now stop it without flipping |
| 2026-10-11 | Open pasture rolling friction 3x paved (was 4x) | The Cub couldn't taxi on open grass at half power |
| 2026-10-11 | Game clock in local solar time, 4x compressed by default; full moon at night for now | Simple and playable; moon phases later |
| 2026-10-11 | Custom sky shader instead of PhysicalSkyMaterial | PhysicalSky's night-sky texture can't fade, so stars showed in daylight |
| 2026-10-11 | Aircraft lights only on aircraft with electrics (has_master); positions from JSBSim data | Cub stays period-correct; real models can keep the same light points |
| 2026-10-11 | Instrument faces dim with darkness unless panel lights are on; needles stay faintly luminous | Night flying needs the panel lights, like the real 172 |
| 2026-10-11 | Weather changes blend over 20 s; gusts rise over 1.5-4 s with ±8° direction swing; gust strength fades with height (full below 50 m, 30% above 1000 m) | Nikolas: the plane felt too light in wind. Instant wind changes and gusts scaled up aloft drove ±30° pitch swings; now ±1-3° at cruise with a pilot, gusty near the ground |
| 2026-10-11 | Cub pitch inertia Iyy 520 slug·ft² (stock 387) | Stock value low for a J-3 by radius-of-gyration estimate; made it twitchy. 172 inertias are Roskam's published values (unchanged) |
| 2026-10-11 | Lighting overhaul: physically based sky (single scattering, Rayleigh+Mie+ozone) at quarter/half res; sun colour from the same transmittance; AgX tonemap, glow, SSAO, sky-tinted aerial fog; soft 4-split sun shadows to 2.5 km; heightmap hill shadows and terrain AO beyond | Nikolas: lighting too simple, night not good. Result: realistic sunsets, hill shadows at low sun, convincing night |
| 2026-10-11 | Night: moon phase from the date (1983 calendar), Milky Way, airglow, desaturated night vision, exposure up to 6x | Real nights vary: crescent nights are dark, full-moon nights readable |
| 2026-10-11 | Perf after overhaul: terrain 81-127 fps at 1080p on M4 (was 164-288) | Still above the 60 fps budget; sky radiance updates incrementally, clouds at half res, atmosphere at quarter res |
| 2026-10-11 | Fair-weather cloud layer driven by Weather.cloud_cover | Sky realism; base for the fog/rain/cloud step |
