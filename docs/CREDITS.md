# Credits and data sources

## Night sky
- **Milky Way** (`game/world/sky/milkyway_4k.webp`): NASA/Goddard Space Flight Center Scientific Visualization Studio, *Deep Star Maps 2020* (https://svs.gsfc.nasa.gov/4851), "milkyway_2020" layer, built from Gaia DR2 (ESA/Gaia/DPAC), Hipparcos-2 and Tycho-2. SVS content is public domain. Converted to 8-bit WebP with `tools/convert_milkyway.gd`.
- **Stars** (`game/world/sky/bsc5_stars.txt`): *Yale Bright Star Catalogue*, 5th revised edition (Hoffleit & Warren 1991), from the Harvard-Smithsonian Center for Astrophysics catalog server / NASA HEASARC. Positions (J2000), V magnitudes and B-V colours of the 9,096 stars with a J2000 position and magnitude.

## Weather
- **Volumetric clouds** are our own (`game/world/weather_fx/clouds.glsl`), built on published techniques: A. Schneider, *The Real-time Volumetric Cloudscapes of Horizon Zero Dawn* (SIGGRAPH 2015, Advances in Real-Time Rendering) and *Nubis* (2017); S. Hillaire, *Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite* (SIGGRAPH 2016). (An earlier build used the MIT SunshineClouds 2 addon by David House; it has been removed.)
- **Thunder** is synthesised from the lightning channel geometry (superposed N-waves, after Few 1969 and Ribner & Roy 1982).
- Microburst winds: D. D. Vicroy (1991), *A Simple, Analytical, Axisymmetric Microburst Model for Downdraft Estimation*, NASA TM-104053.

## Flight dynamics
- **JSBSim** (LGPL 2.1), aircraft models J3Cub and c172p from the JSBSim distribution, tuned for Smuggler (see `docs/decisions.md`).
