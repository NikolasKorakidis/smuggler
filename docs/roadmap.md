# Smuggler — Roadmap

No phase starts until the gate before it is passed. Durations assume ~16 h/week of Nikolas's testing time.

| Phase | Goal | Gate to pass | Rough estimate |
| --- | --- | --- | --- |
| 0 · Setup and first flight | Tools installed, repo, Godot ↔ JSBSim bridge built on the Mac. Tutorial plane flies in a flat test world. | Nikolas takes off, flies a circuit and lands with the HOTAS. | 1–2 weeks |
| 1 · Flight core | Cockpit + external camera, period gauges, HOTAS + pedal mapping, engine sound, full engine management, one real terrain tile with dirt and paved strips, 172-type added, headless physics tests. | 172-type matches real stall, climb and takeoff figures; ground handling feels right to Nikolas. | 3–5 weeks |
| 2 · Weather | Wind by altitude, gusts, turbulence, density altitude; clear / fog / rain; day-night with compressed time; night strips without lights. | Gusty crosswind landing at dusk feels hard but fair. | 3–4 weeks |
| 3 · Smuggling loop (vertical slice) | Job board, legit + electronics jobs, cargo weight/balance, fuel, money, wear and repair, radar zones, paper map, 3 strips on one island group, save at base, first mission as tutorial. | One full session is fun to play and fun to watch. | 4–6 weeks |
| 4 · Progression and world | Plane tiers 3–6, upgrades, liveries/registration, heat system (interceptors, helicopters, boats), reputation, bribes, NPC contacts, radio chatter, map expansion toward the continents. | Content-complete for Early Access scope. | 2–4 months |
| 5 · Polish and Early Access | Performance pass, quality presets, Windows build, Steam page, playtest, trailer. | Stable build on Mac + Windows. | 4–6 weeks |

See `design.md` → *Scope reality check* for the release-date decision.
