# City Improvements Plan

## Current Atmosphere Template

`celltemplates/template_border_s.vmf` now provides one shared atmosphere setup for every generated cell recipe:

- `light_environment` named `LIGHT_ENVIRONMENT`
- `env_fog_controller` named `FOG_CONTROLLER`
- `shadow_control` named `SHADOW_CONTROLLER`
- one `env_cubemap` at `(0, 0, 128)`

The current light is a bright neutral baseline, and the fog begins at 200 units and ends at 2000 units. Regenerate a recipe with `build_cell_vmfs.ps1 -RefreshGenerated` before compiling it, so it receives the new base-template entities.

## Important Design Rule

A generated recipe VMF is reusable: the same compiled BSP can represent many logical city coordinates. Therefore it cannot safely contain baked settings that depend on a specific coordinate, such as "closer to the city centre means heavier fog." The runtime world index must assign each logical cell an atmosphere profile, and Garry's Mod must apply the coordinate-specific parts when that cell is loaded.

`light_environment` is baked by VRAD. It cannot be made darker or turned from day to night after compilation. Give each reusable recipe a stable baked lighting profile. Use runtime fog, colour correction, and selected dynamic practical lights for changes that must follow the player's logical location.

If future map transitions require unique BSPs per coordinate rather than reusable recipe BSPs, the generator can bake coordinate-specific lighting and fog into those unique VMFs. That is a larger build-cost and storage decision, not a template-only change.

## Atmosphere Profiles

Add small indexed profiles to the future runtime world export. Each cell stores an `atmosphereProfile` index rather than repeating visual settings.

Suggested first profiles:

| Profile | Use | Fog | Lighting feeling |
| --- | --- | --- | --- |
| `outskirts` | Den and outer residential/grassland cells | Long visibility, low density | Cool, readable morning light |
| `suburbs` | Low-threat settlement cells | Medium visibility | Neutral overcast daylight |
| `inner_city` | Commercial and dense centre cells | Shorter visibility, moderate density | Dim grey daylight, stronger shadows |
| `dead_zone` | Radioactive or story-danger areas | Short visibility, tinted and dense | Sickly, low-contrast ambience |
| `safe_zone` | Dens and protected hubs | Long visibility, restrained fog | Warm practical light and safe contrast |
| `storm` | Temporary event modifier | Reduces existing profile visibility | Darker sky and rain-compatible colour correction |

A radial distance from the den or configured city centre should choose the default profile, then environment and landmark rules may override it. Keep the minimum practical visibility above a whole street block so players can still read exits and fight fairly.

## Fog Implementation

1. Export an `atmosphereProfile` for every logical cell in `zombiesim_world.json`.
2. When a player changes cell, the server sends only that profile identifier to the client.
3. A client world module applies fog with `SetupWorldFog` and `SetupSkyboxFog`; this is per-player and avoids changing a shared server entity for every player.
4. Keep `FOG_CONTROLLER` as the VMF fallback and for Hammer testing. Do not rely on a single named fog entity for per-player gameplay fog.
5. Test a route from the den through the centre, checking that fog strengthens gradually and that doorways, road entrances, and zombies remain readable.

The fog profile should control colour, start distance, end distance, maximum density, and a storm multiplier. Use the existing `fogblend`/secondary-colour setup only after it has been visually tested in Garry's Mod; do not make the red secondary colour a permanent centre-city default without that check.

## Lighting and Sky

Use two layers of lighting:

- Baked layer: a small family of recipe lighting profiles such as `clear_day`, `overcast_day`, `dusty_day`, and `dead_zone`. Each profile is selected when a recipe is generated and compiled, ensuring VRAD lightmaps are coherent.
- Runtime layer: colour correction, fog, skybox fog, weather particles, and practical lights. This gives the illusion of travel and changing conditions without recompiling the city.

A sensible early visual gradient is cooler and brighter around the den, flatter overcast districts through the suburbs, and dimmer/desaturated conditions in the centre or dead zones. Avoid changing the sun angle between neighbouring reusable recipe BSPs: players crossing a map transition should not see shadows reverse direction. Keep one global sun direction and vary intensity, ambient fill, fog, and tint instead.

`SHADOW_CONTROLLER` is useful as a fixed artistic default. Treat it as per-map ambience, not a cell-by-cell gameplay control, unless its Garry's Mod inputs are verified in a prototype.

## Cubemap Policy

The single base-template cubemap is acceptable for an initial compile test, but it should be replaced by a generated placement policy before a full city release.

- Never place `env_cubemap` in reusable tile templates. A 5-by-5 recipe could then expand to 25 probes, wasting cubemap budget and producing redundant reflections.
- Generate cubemaps only in the final cell VMF, after tile placement is known.
- Start with one probe for open/low-density recipes, two for standard road or residential recipes, and no more than three for dense commercial or landmark recipes.
- Prefer a position 64-128 units above a clear road centre, plaza, or pavement. Place a second probe only in a materially different space, such as a covered forecourt, a large junction, or in front of a reflective landmark facade.
- Do not place a probe inside solid geometry, under a roof, in a sealed interior, directly against a wall, or at every building frontage.
- Use stable placement anchors from the 5-by-5 plan: central road tile, road junction, landmark forecourt, then the widest open non-road tile. Fall back to the template origin only when no valid anchor exists.
- Compile BSP/VIS/RAD first. Then launch each compiled map and run `buildcubemaps`; cubemap capture is a post-compile in-game build step, not a replacement for VRAD.
- Treat generated cubemap textures as release artefacts. Rebuild them whenever the sky, lighting, fog, reflective materials, or map geometry changes.

Before enabling cubemap placement at scale, compile one open, one road, one dense commercial, and one landmark recipe. Check reflection seams, compile time, BSP size, and whether the probe count gives a visible return. Three probes per 3200-by-3200-unit cell is a firm initial ceiling; reduce it if the results do not justify it.

## Life and Readability Improvements

Prioritise atmosphere that also helps players understand danger and travel:

- Add district soundscapes: distant traffic and wind outside, electrical hum in commercial streets, alarms and Geiger ticks in dead zones, and human activity in safe zones.
- Use sparse practical lights near navigation decisions: road entrances, safe-zone gates, metro stops, landmark doors, and high-risk intersections. Keep their colours tied to the atmosphere profile.
- Add weather as a server-authoritative event layer with client particle effects, sound, fog multiplier, and optional AI/loot modifiers.
- Give landmarks distinct skyline silhouettes, sound cues, and visible approach lighting so they are recognisable before the player reaches them.
- Add controlled ambient props and effects: drifting paper, distant smoke stacks, flickering signs, broken streetlights, occasional trains, and radio transmissions. Cap density per cell and make effects deterministic from the world seed.
- Use map entrances to communicate direction. North/east/south/west transitions need consistent road signs, barriers, lighting, and audio fades so the logical graph feels physically connected.
- Add a low-frequency event director for sirens, distant gunfire, temporary blackout, supply drop, evacuation broadcast, or dead-zone surge. It should choose from the runtime index and never mutate the immutable base graph.

## Delivery Order

1. Refresh generated recipes from the edited base template and visually test one recipe in Hammer.
2. Add a compact `atmosphereProfiles` table and per-cell `atmosphereProfile` reference to the runtime-world exporter.
3. Add the client fog module and verify profile changes through normal cell travel.
4. Extend the cell-VMF builder with deterministic cubemap-anchor selection and a `-WhatIf` report showing expected probe counts.
5. Compile four representative recipes, run the in-game cubemap capture pass, and inspect reflections before batch compiling all recipes.
6. Add soundscape, practical-light, weather, and event systems after the world-index and map-transition foundations are working.