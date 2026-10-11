# Current phase: 2 — Weather

Gate: a gusty crosswind landing at dusk feels hard but fair.
Rule: one Weather object feeds JSBSim and the visuals (systems/weather.gd).

## Claude
- [x] Weather core: wind with height (boundary layer + veer), gusts, Dryden turbulence, temperature (density altitude), QNH. Presets, U cycles.
- [x] Windsocks at every strip, driven by the same wind (gusts included).
- [x] Barometric altimeter with Kollsman window and setting knob; "altimeter set" checklist step.
- [x] Ground handling in tailwinds: no reversed-flow aero (JSBSim tables don't cover it).
- [x] Day/night: compressed clock (4x, Y jumps), real sun path for date/latitude, custom sky (dusk colours, stars, moon), moonlight, night exposure. 172: landing/nav/panel light switches (need master), panel clock; gauges go dark at night without panel lights. Cub: no electrics. Hangar lamp at dusk; strips unlit.
- [ ] Fog (visibility), rain (particles, windshield, wet grass/dirt friction), simple cloud layer.
- [ ] Weather menu / pick conditions before a flight (instead of U), and an 80s-style radio forecast.
- [ ] Gate scenario: gusty crosswind at dusk on the valley strip; scripted-pilot test that it is landable.

## Nikolas
- [ ] Fly the presets (U): gusty crosswind and hot afternoon especially. Report how gusts and turbulence feel.
- [ ] Phase 1 gate: confirm 172 feel (stall, climb, takeoff, ground handling) incl. the new flaps.
- [ ] Fictional names for the tutorial plane and the 172-type.
- [ ] (Before Phase 3) Release scope vs date.

---

# Phase 1 — Flight core ✅ (pending Nikolas's gate: 172 feel vs MSFS — flaps fixed after first feedback)

Gate: 172-type matches real stall, climb and takeoff figures; ground handling feels right to Nikolas.

## Claude
- [x] 172-type aircraft (JSBSim c172p as base) + headless tests vs C172P figures at 2400 lb (8 tests).
- [x] Flaps control (G/T keys + bindable HOTAS buttons) and aircraft switching (N) in the test world.
- [x] 3D cockpit with period gauges: ASI, attitude, altimeter, turn coordinator, heading, VSI, tachometer, compass, oil temp/pressure, fuel. Panels per aircraft (Cub: ASI in mph).
- [x] Clickable cockpit switches (hover shows name and state; wheel turns knobs).
- [x] Full engine management: master, magnetos, starter (Cub: hand-propping), primer, mixture, carb heat, fuel selector with fuel in the lines. Priming/flooding/cold starts. Ctrl+E start-up assist. Electric and vacuum instruments.
- [x] Tutorial flight in the checklist: start, takeoff (172: flaps 10°), radio tower ~2 km out and back, land on the strip, taxi to the hangar apron, shut down. Skipped steps don't block it.
- [x] Flaps: 172 flap switch + position indicator in the cockpit; flaps move on the placeholder model.
- [x] Self-ticking start-up / before-takeoff checklists per aircraft (top right, K toggles; text files in aircraft/<model>/checklist.txt).
- [x] Engine sound driven by RPM and power: data-driven synth per aircraft (engine, prop, airframe, cabin/outside views). Recorded sounds can replace it later.
- [x] One terrain tile (16 x 16 km): paved valley strip with hangar/apron, dirt ridge strip; JSBSim wheels follow real ground height and slope. Now the default world; tutorial runs on it.
- [x] Performance check at 1080p: terrain 164-288 fps, 172 cockpit ~90 fps on flat world (M4).

## Nikolas
- [ ] Fly the 172-type: compare stall, climb, takeoff and ground handling with what you know from MSFS.
- [ ] Pick fictional names for the tutorial plane and the 172-type.
- [ ] (Before Phase 2) Decide release scope vs date — see design.md → Scope reality check.

---

# Phase 0 — Setup and first flight ✅ passed 2026-10-11

Gate: Nikolas takes off, flies a circuit and lands with the HOTAS.

## Nikolas (one-time, ~30 min)
- [x] Format a folder on the external drive as **APFS** if the drive is exFAT/NTFS (Git and Godot misbehave on those). Check: Finder → right-click drive → Get Info → Format.
- [x] Copy this `smuggler` folder onto the external drive.
- [x] Install VS Code + the Claude Code extension (see README).
- [x] Open the folder in VS Code, open the Claude Code panel, type: `Run scripts/bootstrap.sh and start Phase 0.`
- [x] Decide: GitHub repo private or public. → **public**

## Claude
- [x] Run `scripts/bootstrap.sh`; install anything missing (Xcode CLT, Git, Python 3, CMake, Godot 4.7, SCons).
- [x] `git init`, first commit, create GitHub repo (public, per Nikolas), push.
- [x] Create Godot project skeleton in `game/` (folders: `aircraft/`, `world/`, `systems/`, `ui/`, `audio/`).
- [x] Add JSBSim as a git submodule; build it for macOS arm64.
- [x] Build the GDExtension in `extensions/jsbsim_gd/`: expose init, step, set/get property, reset.
- [x] `FDM` node in Godot: steps JSBSim at 120 Hz, maps JSBSim position/attitude to the aircraft node.
- [x] Tutorial aircraft: start with JSBSim's stock J-3 Cub model (placeholder visuals). Prop and drag tuned to J-3C-65 figures.
- [x] Flat test world: ground plane, one 800 m grass strip, sky, sun (+ trees and a hangar for height/speed cues).
- [x] Input map: keyboard + gamepad defaults; HOTAS/pedals bound in the in-game joystick setup (J). T.Flight Hotas 5 default profile (PC mode, green LED). Verified by Nikolas.
- [x] Chase camera + basic cockpit camera.
- [x] Minimal debug overlay (dev builds only, F3): airspeed, altitude, AoA, fps.
- [x] Headless test: Cub takeoff roll, stall speed, climb rate vs published figures (`tests/fdm`, 7 tests).
- [ ] Summary in chat: what to fly and what to look for.

## Nikolas — fly it (gate test)
- [x] Open Godot → Import → `game/project.godot` → Run (F5). Or from the Claude panel: "run the game".
- [x] F2 / J: bind stick pitch/roll, throttle, rudder twist or pedals, toe brakes. Tick Invert where a control moves the wrong way.
- [x] Take off from the grass strip, fly a circuit, land back on the strip.
- [x] Feedback: ground handling on the takeoff roll, tail-up speed, stall feel, landing flare.

## Open / next
- [ ] Rename the placeholder "J3Cub" model to a fictional type before any public material (content rule).
- [ ] Engine starts already running (simplified start-up). Full start procedure is Phase 1.
