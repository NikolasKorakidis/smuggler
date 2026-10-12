# Weather — full plan

Phase 2 goal: weather you can see, hear and feel, all coming from **one Weather object** (`game/systems/weather.gd`). What the pilot sees (fog, cloud, rain, lightning) and what JSBSim flies in (wind, downdrafts, turbulence, density, icing, wet runway) are the same numbers.

Gate: a gusty crosswind landing at dusk feels hard but fair; a thunderstorm is something you plan around.

## Packages (light, permissive, no lock-in)
| Need | Choice | Why |
|---|---|---|
| Volumetric clouds you can fly into | **SunshineClouds 2** (MIT, Godot 4.4+, Metal support, maintained, Godot 4.7 fix Sep 2026) | Ray-marched clouds that hide terrain correctly, become fog when you're inside, take sun/moon/point lights (lightning), and 64 "effectors" to build storm towers. Lives in `addons/`; we drive its few parameters from Weather. |
| Fog, haze, rain shafts | **Own compositor effect** | Godot's height fog is per-surface, not along the view ray, so thick ground fog looks wrong. An analytic fog integral is cheap and exact. |
| Rain, windshield, lightning, sounds | **Own shaders and procedural audio** | The available rain-on-glass shaders are screen overlays or unlicensed, and none does airflow streaking. Ours are small, and the sounds come from the existing synth (no recorded assets). |
| Microburst / downdraft wind | **Vicroy (NASA/FAA 1991) analytic model** | The standard simple model used in wind-shear simulation studies. |

## W1 — The weather model (single source of truth)
- [x] Temperature, **dew point** (humidity), lapse rate; morning inversions.
- [x] **Visibility** from haze, mist, fog and rain (Koschmieder: extinction = 3.912 / visibility). Rain visibility from the rain rate R (≈ 12·R^-0.65 km: ~3 km moderate, <1 km violent).
- [x] **Cloud layers** in oktas (FEW/SCT/BKN/OVC) with base and top. Cumulus base from the temperature/dew-point spread (~400 ft per °C).
- [x] **Fog**: radiation fog (calm clear nights, fills valleys, burns off after sunrise into low stratus) and advection fog; top height and visibility inside.
- [x] **Precipitation**: drizzle, rain, showers, thunderstorm; rate in mm/h; showers tied to cells.
- [x] **Storm cells**: position, size, growth → mature → dissipating (≈ 45–60 min), drift with the wind aloft. Each has a rain shaft, downdraft/microburst (Vicroy), gust front, inflow under the base, severe turbulence inside, lightning.
- [x] **Ground wetness**: builds up in rain, dries with sun, wind and temperature.
- [x] Weather evolves: presets blend smoothly; storms form at a set rate per hour and drift in. (Afternoon heating driving it: later.)
- [x] Presets (METAR-style): CAVOK; Hazy summer; Morning valley fog; Low overcast and drizzle; Steady rain; Afternoon thunderstorms; Squall line; plus the existing Calm / Breeze / Gusty crosswind / Hot afternoon / Windy low.
- [x] **To JSBSim**: 3D wind including storm outflow and **vertical wind** (downdrafts/updrafts), turbulence in cloud and storms, temperature/pressure, small heavy-rain penalty.

## W2 — Visibility and fog (compositor effect)
- [x] Analytic fog along every view ray: clear-air haze (thinning with height) + fog deck with a soft top (valleys fill, hills poke through, you can fly over it).
- [x] Rain shafts: grey curtains under storm cells, visible from far away.
- [x] Fog colour from the sky and sun (bright towards the sun, correct at dusk and night).
- [ ] Landing light beam visible in fog and rain.
- [x] Replaces the current Godot fog; also fogs the sky.

## W3 — Clouds
- [x] SunshineClouds 2 installed; performance tested at 1080p on the MacBook (budget 60 fps with terrain).
- [x] Driven by Weather: coverage, density, base/top, drift with the wind aloft, sun and moon light, sky ambient.
- [x] Flying into cloud = instrument conditions (whiteout, light turbulence in cumulus, smooth in stratus).
- [x] Storm towers (cumulonimbus) from effectors, dark bases.
- [x] High cirrus stays in our sky shader.
- [~] Overcast days darker and flatter (done); cloud shadows on the ground (later).

## W4 — Rain
- [x] Rain streaks around the camera (GPU, constant density at any speed), slanted by your airspeed, lit by the landing light.
- [x] **Rain on the windshield**: drops land and merge, run down when slow, are blown up and back at flying speed, water film in heavy rain, refraction and blur of the view, glints from lights; stays wet for a while after you leave the rain. Cloud moisture too.
- [x] Wet ground: darker earth and grass, glossy runway with a sheen; dries afterwards.
- [x] Rain drumming on the airframe (louder with rain rate and speed).
- [ ] Rainbow when the sun is low behind you and rain is ahead.
- [ ] (Later) Splashes on the runway.

## W5 — Storms
- [x] Lightning: cloud-to-ground bolts and in-cloud flashes; the flash lights the clouds, sky and ground.
- [x] Thunder with real delay (distance / 343 m/s), procedural rumble, sharp crack when close.
- [x] Gust front ahead of the cell (wind shift and surge), microburst downdraft and outflow (wind shear on approach), updrafts under the base, severe turbulence in the cell.

## W6 — Aircraft and engine
- [x] **Carburettor icing** from temperature, dew point and throttle position, shaped to match the FAA icing chart: RPM loss, rough running, possible engine stoppage. Carb heat clears it with the classic "RPM drops, then rises" sign.
- [x] Wet runway and wet grass: less braking, more rolling drag (mud).

## W7 — Control and info
- [x] Dev menu: every new field. Spawn a storm at a bearing and distance, trigger lightning, set rain rate, fog top and visibility, wetness.
- [ ] Pick the weather before a flight; 80s-style radio forecast (later).
- [x] METAR-style weather line.

## W8 — Tests and gate
- [x] Headless tests: visibility numbers, storm wind field against the Vicroy equations, carb ice against the chart zones, wet friction, cell lifecycle.
- [ ] Visual sweeps (screenshots) for fog, rain and storm; frame-time bench with storm, rain and clouds at 1080p.
- [ ] Gate scenario: gusty crosswind at dusk on the valley strip; scripted pilot proves it is landable.

## Sources
- SunshineClouds 2: https://github.com/Bonkahe/SunshineClouds2 (MIT)
- Vicroy, D. D. (1991), *A Simple, Analytical, Axisymmetric Microburst Model for Downdraft Estimation*, NASA TM-104053 / DOT/FAA/RD-91/2: https://ntrs.nasa.gov/citations/19910011819
- Oseguera & Bowles (1988), NASA TM-100632: https://ntrs.nasa.gov/citations/19880018674
- FAA SAIB CE-09-35 carburettor icing probability chart; NTSB Safety Alert SA-029: https://data.ntsb.gov/advocacy/safety-alerts/Documents/SA-029.pdf
- Rain extinction vs rate (power law), Koschmieder visibility: https://www.revistascca.unam.mx/atm/index.php/atm/article/view/53491
