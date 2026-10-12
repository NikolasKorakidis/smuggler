# Credits and data sources

## Night sky
- **Milky Way** (`game/world/sky/milkyway_4k.webp`): NASA/Goddard Space Flight Center Scientific Visualization Studio, *Deep Star Maps 2020* (https://svs.gsfc.nasa.gov/4851), "milkyway_2020" layer, built from Gaia DR2 (ESA/Gaia/DPAC), Hipparcos-2 and Tycho-2. SVS content is public domain. Converted to 8-bit WebP with `tools/convert_milkyway.gd`.
- **Stars** (`game/world/sky/bsc5_stars.txt`): *Yale Bright Star Catalogue*, 5th revised edition (Hoffleit & Warren 1991), from the Harvard-Smithsonian Center for Astrophysics catalog server / NASA HEASARC. Positions (J2000), V magnitudes and B-V colours of the 9,096 stars with a J2000 position and magnitude.

## Flight dynamics
- **JSBSim** (LGPL 2.1), aircraft models J3Cub and c172p from the JSBSim distribution, tuned for Smuggler (see `docs/decisions.md`).
