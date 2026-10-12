# Smuggler — Design

Source: Nikolas's kickoff questionnaire, 2026-10-11. Items marked **OPEN** need a decision later. Items marked **FLAG** conflict with something else and need discussion.

## Vision
- **Purpose:** personal project, YouTube devlog and paid Steam game.
- **Price / release:** $20–30, Early Access. Target given: early 2027. **FLAG:** see Scope reality check.
- **Player feeling:** "Wow, everything looks pretty from up there… oh crap, focus on the instruments, it's windy."
- **Sim vs game:** mostly sim. "MSFS 2024-level physics with Aces of Thunder fun."
- **Tone:** dark comedy mixed with grounded. Vibe: *Miami Vice*, *American Made*.
- **Inspirations:** MSFS 2024 (flying), Aces of Thunder / War Thunder (fun, look), Euro Truck Simulator (job loop), Cyberpunk 2077 (world, factions).
- **Target player:** sim nerds, casual mid-aged guys.
- **Not:** no plane-vs-plane shooting. Minimal on-foot shooting allowed later (e.g. shooting back at a chasing helicopter).

## World
- Real places in **Mexico and the United States**. Era 1978–1988. (Nikolas, 2026-10-12.) Which region to build first: **OPEN**.
- **FLAG:** both countries are far bigger than the 150 × 150 km v1 recommendation. Plan: build one region first, expand in Early Access.
- Locations: jungle strips, beaches, roads, farms, cities, villages, oil rigs, carrier ships.
- Landing: mostly defined strips; beaches and some flat areas also landable.
- Very few villages and people. None to little other air traffic.
- Float planes: later.

## Flight and physics
- All behaviours matter: stall/spin, ground handling, crosswind, engine management, weight and balance, P-factor, ground effect, icing.
- Engine management: **full depth** (mixture, carb heat, prop, cowl flaps).
- Failures: scripted failures + standard wear and damage.
- Crash: restart mission for now; later a mix (lose plane/cargo, harsher outcomes).
- Damaged planes can limp home.
- Assists available as options: auto-trim, auto-mixture, landing guidance, simplified start-up.
- Feel benchmark: **Cessna 172**.
- Fuel: realistic burn.

## Weather and time
- v1 weather: clear, fog, rain. Wind always.
- Weather is a tool (hide in cloud/fog from radar) and a threat.
- Forecasts: unreliable 80s radio forecasts.
- Compressed time; day/night cycle.
- Night flights with no runway lights: most of the time.
- Seasons: possible later.

## Aircraft and progression
- Ladder: Cub-type → 172-type → 206-type → light twin → Twin Otter-type → DC-3-type.
- Plus an even simpler, cheaper plane for the tutorial and first missions. **OPEN:** which type (ultralight / Aeronca Champ / tired Cub).
- Aircraft are **not real types**: each has a fictional, altered name, with no real manufacturer or model names, logos or trade dress. The "-type" labels above only say which real plane a flight model is based on. (Nikolas, 2026-10-12.)
- Buy and upgrade planes. Upgrades: engine, long-range tanks, STOL kit, radar altimeter, paint, hidden cargo bays, radios.
- One plane at a time; no fleet.
- Custom liveries and registration (to dodge tracking).
- Must-have types: **OPEN**. Helicopters: **OPEN**.

## Gameplay loop and economy
- Missions 30–60 minutes.
- Cargo progression: electronics first, later drugs and guns. (Steam allows this content; keep it non-graphic and check rating needs before release.)
- Legit cargo jobs for cover and low-risk income.
- Cargo mechanics: **OPEN** (default: weight + volume; fragile/perishable later).
- Delivery: landings and airdrops.
- Money sinks: repairs, fuel, bribes, hangar rent, plane loans.
- One home hangar.
- Reputation with factions/clients.
- Free-roam between jobs (interpreted from "yes"; confirm).

## Heat (law enforcement)
- Chasers: coast guard, customs, DEA, military, rival smugglers.
- Detection: radar coverage, visual spotting, informants, airport inspections.
- Interceptor planes and helicopters.
- Combat: minimal; being chased and shot at by helicopters or boats.
- Caught: lose money, cargo, plane; prison time; lose respect and popularity.
- Bribes and corrupt officials.
- Flying low under radar is a core skill.

## Story
- Campaign and sandbox.
- Silent, unnamed player character (for now).
- NPCs: mechanic, fixer, cartel contact, rival pilot, cop.
- Story delivery: **OPEN**.
- No ending. Real places; fictional people, companies and aircraft.

## Cockpit, controls and UI
- Cameras: cockpit and external.
- 3D cockpit vs flat gauges: **OPEN** (default: 3D cockpit with readable gauges, mouse-clickable switches).
- Navigation: paper map + compass; GPS later. In-flight map becomes better progressively.
- **No HUD.** Instruments and physical maps only.
- No replay system.
- Head tracking possible; VR hopefully later.

## Graphics
- Realistic style. References: MSFS 2024, Aces of Thunder, War Thunder.
- 60 fps at 1080p on the MacBook. **FLAG:** realistic MSFS-like visuals and 60 fps on a MacBook Air pull against each other. We aim for "realistic lighting and materials, modest geometry" and add higher presets for the planned RTX 5080 PC.
- Assets: imported models in Blender; Claude rigs and animates. Asset budget: **OPEN**.
- UI: 80s style.

## Audio
- Music from free libraries.
- Engine sounds: maybe self-recorded, else libraries.
- Voices: maybe YouTube friends.
- Radio chatter (ATC, police, clients) is important.

## Saves and difficulty
- Save only at base.
- No difficulty settings (Elden Ring approach). Assists are separate options.
- First mission is the tutorial.
- English only. Accessibility: subtitles, remapping, colour-blind support.

## Release
- Steam, Windows + Mac.
- Early Access. Company setup (KvK/BTW): **OPEN**. Playtests and mods: **OPEN**. VR: hoped for, later.

## Scope reality check
Early 2027 Early Access is about 3–5 months away at ~16 hours/week. That is enough for **Phase 0–3** (flying, weather, a playable smuggling loop on one island group), not for two continents, six planes and police chases. Two honest options:
1. **Keep the date, cut scope:** Early Access in spring 2027 = 2 planes, one island group, clear/fog/rain, basic heat. Everything else ships in updates.
2. **Keep scope, move the date:** Early Access late 2027 or later.

Decision: **parked** — Nikolas, 2026-10-12: release scope doesn't matter for now.

## Conflicts to resolve
- **Public repo vs secrecy.** Resolved 2026-10-11: repo is **public** to allow sharing and contributions. Accepted trade-off: name, concept, design doc and code are visible.
- **Windows builds.** Current PC has a GTX 1060; a new RTX 5080 PC is planned. Windows testing waits for that or uses GitHub Actions builds on the 1060.
