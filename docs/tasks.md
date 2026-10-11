# Current phase: 0 — Setup and first flight

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
- [x] Input map: keyboard + gamepad defaults; HOTAS/pedals bound in the in-game axis tester (F2). **Needs Nikolas's hardware to verify.**
- [x] Chase camera + basic cockpit camera.
- [x] Minimal debug overlay (dev builds only, F3): airspeed, altitude, AoA, fps.
- [x] Headless test: Cub takeoff roll, stall speed, climb rate vs published figures (`tests/fdm`, 7 tests).
- [ ] Summary in chat: what to fly and what to look for.

## Nikolas — fly it (gate test)
- [ ] Open Godot → Import → `game/project.godot` → Run (F5). Or from the Claude panel: "run the game".
- [ ] F2: bind stick pitch/roll, throttle, rudder twist or pedals, toe brakes. Tick Invert where a control moves the wrong way.
- [ ] Take off from the grass strip, fly a circuit, land back on the strip.
- [ ] Feedback: ground handling on the takeoff roll, tail-up speed, stall feel, landing flare.

## Open / next
- [ ] Rename the placeholder "J3Cub" model to a fictional type before any public material (content rule).
- [ ] Engine starts already running (simplified start-up). Full start procedure is Phase 1.
