# Current phase: 0 — Setup and first flight

Gate: Nikolas takes off, flies a circuit and lands with the HOTAS.

## Nikolas (one-time, ~30 min)
- [x] Format a folder on the external drive as **APFS** if the drive is exFAT/NTFS (Git and Godot misbehave on those). Check: Finder → right-click drive → Get Info → Format.
- [x] Copy this `smuggler` folder onto the external drive.
- [x] Install VS Code + the Claude Code extension (see README).
- [x] Open the folder in VS Code, open the Claude Code panel, type: `Run scripts/bootstrap.sh and start Phase 0.`
- [x] Decide: GitHub repo private or public. → **public**

## Claude
- [ ] Run `scripts/bootstrap.sh`; install anything missing (Xcode CLT, Git, Python 3, CMake, Godot 4.7, SCons).
- [x] `git init`, first commit, create GitHub repo (public, per Nikolas), push.
- [ ] Create Godot project skeleton in `game/` (folders: `aircraft/`, `world/`, `systems/`, `ui/`, `audio/`).
- [ ] Add JSBSim as a git submodule; build it for macOS arm64.
- [ ] Build the GDExtension in `extensions/jsbsim_gd/` (start from godotjsbsim prior art): expose init, step, set/get property, reset.
- [ ] `FDM` node in Godot: steps JSBSim at 120 Hz, maps JSBSim position/attitude to the aircraft node.
- [ ] Tutorial aircraft: start with JSBSim's stock J-3 Cub model (placeholder visuals).
- [ ] Flat test world: ground plane, one 800 m grass strip, sky, sun.
- [ ] Input map: T.Flight HOTAS (pitch, roll, throttle, rudder twist) + Thrustmaster pedals (rudder, toe brakes) + keyboard fallback. Add an in-game axis tester.
- [ ] Chase camera + basic cockpit camera.
- [ ] Minimal debug overlay (dev builds only, F3): airspeed, altitude, AoA, fps.
- [ ] Headless test: Cub takeoff roll, stall speed, climb rate vs published figures.
- [ ] Summary in chat: what to fly and what to look for.
