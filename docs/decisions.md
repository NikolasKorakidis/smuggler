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
| 2026-10-12 | Night sky from real data: Yale Bright Star Catalogue (9,096 stars) as screen-space points + NASA SVS Deep Star Maps 2020 Milky Way layer; both rotated by local sidereal time | Nikolas: night sky not realistic. Real constellations in the right place for date/time/place; credits in docs/CREDITS.md |
| 2026-10-12 | Star brightness on a perceptual curve (flux^0.55), Milky Way shown grey-white at eye brightness | Linear flux hid ~90% of naked-eye stars; photo colours look fake to the eye |
| 2026-10-12 | Calendar maths via exact unix days (sidereal time, moon phase) | Approximate 365.25-day years put the sky ~5.5 h out |
| 2026-10-12 | In-game developer menu (` / F10) that changes the live sim: weather sliders override preset blending; airborne spawn through JSBSim initial conditions | Nikolas wants to test conditions in depth without restarting; one place for every tunable |
| 2026-10-12 | Real places in Mexico and the United States; aircraft are not real types (fictional, altered names, no real brands or logos); people and companies fictional | Nikolas's call. Replaces the earlier all-fictional world and a draft that allowed real aircraft types |
| 2026-10-12 | Release scope vs date parked | Nikolas: doesn't matter for now |
| 2026-10-12 | Twilight: added a multiple-scattering glow (fitted so stars come out on the real timetable: mag ~3 at -6°, ~5.4 at -12°, ~6.4 at -18°) and a moonless night-sky floor | Single scattering went black at -9° while real twilight lasts to -18°; the night then sat on a flat plateau |
| 2026-10-12 | Eye adaptation from the luminance of the sky actually drawn (plus moonlit ground), on a power curve to 6x on a moonless night; stars shown by limiting magnitude from the same luminance | Brightness only ever falls through dusk (no rebound or plateau, max ~9% change per game minute); bright stars first, Milky Way last; full moon washes out faint stars |
| 2026-10-12 | Moonlight no longer fades in with darkness; Milky Way core ~10x the night-sky glow | Real moonlight doesn't depend on the sun; the photographic Milky Way looked like a long exposure |
| 2026-10-12 | Volumetric clouds from SunshineClouds 2 (MIT addon), driven directly from Weather (not through its driver node) | Flyable clouds that hide terrain correctly; the driver rounds light energy (steps at dusk) and has no sky light, so twilight clouds went black |
| 2026-10-12 | Anti-aliasing: MSAA 4x replaced by SMAA | The clouds addon can't run with MSAA on Metal; SMAA also smooths shader edges and is cheaper |
| 2026-10-12 | Own fog compositor effect: analytic integral of haze (exponential), fog deck (soft-topped slab, undulating top) and storm rain shafts (Gaussian columns, erf) along each view ray; curtains composited in depth order | Godot's height fog is per-surface, wrong for thick ground fog; analytic is exact and ~1 ms |
| 2026-10-12 | Rain visibility = 12 km x R^-0.65 (R mm/h); Koschmieder 3.912/visibility for extinction | Power-law fit in the range of published rain extinction studies: ~3 km in moderate rain, <1 km violent |
| 2026-10-12 | Thunderstorm winds: Vicroy (1991) axisymmetric microburst (downdraft + outflow), plus gust front and growth-stage updraft; vertical wind fed to JSBSim | Standard simple wind-shear model; storms you can fly into and feel |
| 2026-10-12 | Carburettor icing from the intake temperature drop (12-28 °C by throttle) and relative humidity, rate tuned to the FAA icing chart; carb heat melts it with meltwater roughness | Real hazard for both planes on humid days; dry days show none (first version iced in the calm preset and crashed the scripted Cub) |
| 2026-10-12 | Rain on the windshield is a procedural shader on a glass quad from aircraft data (windshield_center/size/rake) | No usable licensed shader did airflow streaking; aircraft stay data |
| 2026-10-12 | Weather effects run right after the sky (POST_SKY) | Refracting glass samples the screen before PRE_TRANSPARENT effects run, so drops showed clear sky through overcast |
| 2026-10-12 | Own volumetric cloud renderer replaces SunshineClouds 2 (removed) | Nikolas: clouds looked silly; aim at Ace Combat 8 (in-house 'Cloudly', layered clouds). Built on Schneider/Nubis shapes (weather map, Perlin-Worley + Worley erosion, height profiles per type) and Hillaire lighting (sun march, multi-scatter octaves, dual-lobe phase, powder); half res + temporal reprojection; ~2.5 ms vs 6-9 ms before |
| 2026-10-12 | Weather map generated once on CPU (seamless FastNoiseLite: cumulus cells, regional, mid, fine); cover -> threshold from its histogram | Cover 0.3 really covers 30% of the sky; the same map answers 'in cloud?' for physics |
| 2026-10-12 | Cloud shadows: shadow map on the cloud-base plane (512 px over 24 km), terrain projects along the sun ray; the fog pass uses it for god rays | Drifting shade on the ground and light beams through gaps, from the same clouds |
| 2026-10-12 | Thunder synthesised per strike from its channel geometry (N-wave per few-metre piece, beaming, distance delay, echoes, air absorption) | Unique, distance-correct thunder (crack and crackle close, long rumble far) without recorded assets or licences |
| 2026-10-12 | Cloud engine: data-driven CloudType library (world/clouds/types: cumulus humilis/mediocris/congestus, cumulonimbus, stratocumulus, stratus, nimbostratus, altocumulus, altostratus), up to 3 layers, profiles as curves; designer tab in the dev menu | Nikolas: build our own engine like Ace Combat's Cloudly and tune it ourselves; layers give altitude cues |
| 2026-10-12 | Clouds lit by the sun as seen at cloud height (later sunset, not dimmed by the overcast itself) | Overcast decks looked flat grey because they used the ground's deck-dimmed sunlight |
| 2026-10-12 | Cloud cells grow and dissolve (evolving noise, ~20 min per cell) | Clouds frozen in place looked painted on |
| 2026-10-12 | Rain sound: impact-grain synthesis in four layers on a filtered bus, driven by sweep rate sqrt(fall^2 + airspeed^2) | Nikolas: rain didn't sound good and must get stronger with speed; a recording can replace the dense layer (audio/rain/rain.ogg) |
| 2026-10-12 | The weather and cloud system is **Anemos** (Greek: wind), a self-contained Godot addon in game/addons/anemos, copyright Nikolas Korakidis, all rights reserved (proprietary LICENSE.md) | Nikolas wants to own it and possibly sell or license it; prefixed classes (Anemos*), no Smuggler dependencies, sky/vehicle providers, ground shader include with global shader parameters, JSBSim link moved to the game (WeatherPhysics) |
| 2026-10-12 | Anemos stays in this public repo for now; flagged: public source can be read (copyright still protects it) - move to a private repo before selling | Keeps development simple today |
| 2026-10-12 | World map (part two): south-western/southern US + northern Mexico + small Bahamas and northern Cuba, about 1:12 scale with the Gulf and deserts squeezed more; typical run ~20 min, LA-Miami ~1.5 h; fuel burn scaled to the map | Nikolas: fun pacing, not 10-hour flights. Details (mountain heights, layout) when we reach that step |
