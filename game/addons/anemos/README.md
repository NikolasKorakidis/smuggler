# Anemos

*Anemos* (Greek ἄνεμος, "wind") is a weather and cloud system for Godot 4.7
(Forward+). Everything comes from one weather state, so what you see, hear and
fly through always agree.

Copyright (c) 2026 Nikolas Korakidis. All rights reserved. Proprietary — see
[LICENSE.md](LICENSE.md).

## What it does

| Part | What you get |
|---|---|
| **Weather** (`core/`) | Wind with height (boundary layer, veer), gusts, turbulence, temperature and dew point, pressure, visibility, fog decks that burn off after sunrise, rain, ground wetness, METAR line, presets. Thunderstorm cells that grow, mature and die, with microburst downdrafts and outflow (Vicroy model), gust fronts, updrafts and lightning. |
| **Cloud engine** (`clouds/`, `render/clouds.glsl`) | Volumetric clouds in up to three layers plus storm towers, each layer one of a library of cloud types (cumulus humilis / mediocris / congestus, cumulonimbus, stratocumulus, stratus, nimbostratus, altocumulus, altostratus). Self-shadowed, multiple-scattering light, silver linings, sunset colours, cells that grow and dissolve, cumulus that build through the afternoon, cloud shadows on the ground. |
| **Atmosphere** (`render/`) | Fog, haze and rain shafts integrated exactly along every view ray, clouds composited in depth order, god rays through cloud gaps, a vehicle's landing light beam in fog and rain. |
| **Precipitation** (`precipitation/`) | Falling rain around the camera at any speed, rain on glass (beads, runners, film, airflow), rain sounds that grow denser and brighter with airspeed. |
| **Storms** (`storms/`) | Lightning bolts and flashes lighting the clouds, sky and ground; thunder synthesised from each bolt's channel (crack and crackle close, rolling rumble far, real delay). |
| **Ground** (`ground/`) | A shader include for wet ground and cloud shadows. |

## Setting it up

1. Copy `addons/anemos/` into the project and enable the **Anemos** plugin
   (it registers four global shader parameters). Use the Forward+ renderer and
   screen-space AA (SMAA/FXAA/TAA), not MSAA.
2. Add the nodes:

```gdscript
var weather := AnemosWeather.new()
add_child(weather)                       # it ticks (gusts, storms, wetness)
var anemos := Anemos.new()
anemos.weather = weather
anemos.sky = my_sky                      # see "Sky provider"
anemos.vehicle = my_vehicle              # optional, see "Vehicle provider"
anemos.environment_node = $WorldEnvironment
anemos.field_elevation_m = 120.0         # weather heights are above this
add_child(anemos)
weather.set_preset(9)                    # "Afternoon thunderstorms"
```

3. Ground shaders: `#include "res://addons/anemos/ground/anemos_ground.gdshaderinc"`,
   then multiply the sun's light by `anemos_cloud_sunlight(world_pos)` and call
   `anemos_wet_surface(albedo, roughness, specular, darken, gloss)`.
4. Physics: read the air from the weather — `weather.air_velocity(agl_m, world_pos)`
   (m/s, y up, storms included), `weather.turbulence_at(pos)`, `weather.temp_at(h)`,
   `weather.dewpoint_at(h)`, `weather.qnh_hpa`, `weather.wetness`.

### Sky provider

Any object with these methods (Anemos calls them every frame):

| Method | Returns |
|---|---|
| `anemos_sun()`, `anemos_moon()` | the DirectionalLight3D nodes (moon may be null) |
| `anemos_sun_direction()` | unit vector towards the sun |
| `anemos_sun_elevation_deg()` | sun elevation |
| `anemos_sky_colors()` | `[horizon, zenith, horizon towards sun, horizon away]` radiance (Vector3) |
| `anemos_transmittance(dir, alt_m)` | sunlight colour reaching that altitude (Vector3) |
| `anemos_exposure()` | camera exposure |
| `anemos_hours()` | local solar time (cumulus build through the day) |
| `anemos_flash(level)` *(optional)* | brighten the sky for lightning |
| `anemos_sky_changed(horizon, zenith)` *(optional)* | sky colours, every 0.2 s |

### Vehicle provider (optional)

`anemos_velocity()` (m/s, world), `anemos_airspeed()` (m/s),
`anemos_is_inside(camera)` (cockpit view), `anemos_beam_light()` (SpotLight3D
or null), `anemos_load_factor()` (g), `anemos_on_ground()`.

## Tuning

- Cloud types are resources in `clouds/types/` (made by `tools/make_cloud_types.gd`).
- At run time, `anemos.clouds.layers[i]` can be taken over (`set_manual`) and
  given any type, cover and heights; `anemos.clouds.steps` / `light_steps` set quality.
- `anemos.atmosphere.clouds_enabled` / `fog_enabled` switch the parts.

## Cost

About 2.5 ms per frame for the clouds at 1080p on an Apple M4 (half-resolution
ray march, temporally accumulated), about 1 ms for fog and god rays.
