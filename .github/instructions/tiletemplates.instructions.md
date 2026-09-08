---
name: "ZombieSim Tile Templates"
description: "Use when editing, adding, renaming, rotating, or validating ZombieSim Hammer tiletemplate VMF or VMX assets, including roads, buildings, carparks, fences, terrain, decorations, and skybox tiles."
applyTo:
  - "tiletemplates/**/*.vmf"
  - "tiletemplates/**/*.vmx"
---

# ZombieSim Tile Template Rules

- `tiletemplates` contains hand-authored source assets. Do not edit generated recipe VMFs, BSPs, staged maps, or developer-zoo cells to change a tile; regenerate them from the source asset instead.
- A normal tile occupies one $640 \times 640$ Hammer-unit grid cell and is authored at its canonical $0^\circ$ orientation. Keep geometry within its intended footprint and verify directions visually in Hammer; never infer yaw from a filename.
- Follow the canonical orientations in [docs.md](../../docs.md): roads/motorways run south-to-north at $0^\circ$, buildings expose their entrance on the north edge, carpark entrances connect on the south edge, and border assets have their documented edge orientation.
- Use the existing `tile_<category>_<name>.vmf` naming pattern. New templates must match the appropriate discovery pattern in [generator-settings.json](../../generator-settings.json), or planning will not select them. Update explicit topology, transport, or landmark patterns when renaming a referenced template.
- Name new multi-tile assets with an unambiguous terminal footprint suffix such as `_2x2` or `_3x3`. A multi-tile building needing vehicle frontage has exactly one `zn_road_connection` entity whose `direction` names its authored-local edge.
- Preserve companion `.vmx` metadata when a tile has one. Rename or regenerate the companion file alongside the VMF when appropriate.
- `bin/carpark_endcaps.psm1` owns generated carpark cap VMF and yaw selection. Do not encode that policy in an authored lane role or duplicate the mapping in a tile asset.
- Do not correct Backrooms placement by changing a native model `ModelOffset`; correct the generator's block-cell placement.

## Required Checks

1. After adding, renaming, rotating, or changing a placement-sensitive tile, run `./bin/build_tile_zoos.ps1 -RefreshPlan` and inspect the relevant generated fixture in Hammer.
2. When the edit affects recipe generation, run the focused preview VMF/VBSP workflow in the [world-build skill](../skills/world-build/SKILL.md).
3. For geometry, portal, skybox, or sightline changes, run the preview visibility-budget check before a full VVIS/VRAD build.