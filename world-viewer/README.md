# ZombieSim World Viewer

A standalone C++/raylib viewer for a generated ZombieSim world. It reads the
generated recipe VMFs referenced by a plan, expands every `func_instance`
recursively with Source's origin/angle transforms, and renders the brushes.
Use it to review a generated world before the multi-hour Source compile.

It is a review aid only. It does not replace VBSP/portal budgets, VVIS/VRAD,
navmesh, gate travel, the 3D-skybox coast or in-game review.

## Build

From `world-viewer/` (same MinGW toolchain as `walker-simulator/`):

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
```

The executable is written to the repository `bin/` folder as
`zombiesim-world-viewer.exe`. CMake may print warnings on stderr; check the
output for `error` rather than relying on the PowerShell exit status.

## Run

From the repository root:

```powershell
.\bin\zombiesim-world-viewer.exe --plan generated\preview_alpha34_20261101\plan.json
```

| Option | Meaning |
| --- | --- |
| `--plan <plan.json>` | Generated plan to load (required). |
| `--repo <root>` | ZombieSim root, if not run from it. |
| `--cell x y` | Start looking at grid cell `x y` (the overlay also shows its logical coordinates). |
| `--street` | With `--cell`, start low on the cell's centre road. |
| `--overview` | Start with the whole world in view. |
| `--untextured` | Start with flat material colours. |
| `--lit` | Start in lit mode (VMF light entities). |
| `--night` | Start in night mode (implies `--lit`). |
| `--size w h` | Window size. |
| `--screenshot out.png --frames N` | Render N frames, save, exit. |
| `--stats` | Load, print mounts/material/light statistics, exit. |

## Controls

| Input | Action |
| --- | --- |
| Right mouse drag | Look |
| W A S D, E/Q | Fly, up/down (Shift = 5x) |
| Middle mouse drag | Pan |
| Mouse wheel | Fly speed |
| Left click | Select cell (world or minimap; minimap also flies there) |
| 1-5 | Minimap colouring: district, environment, density, landmark, radiation |
| T / L / N | Textures / lit / night (night enables lit) |
| G / B / F | Grid / map shell / fog |
| `=` / `-` | Draw distance |
| O | Overview |
| Tab / H | Table / help |
| F12 | Screenshot |

## Textures

Base textures come from each material's `$basetexture`, resolved from the
addon's loose `materials/` and the mounted Garry's Mod and Source engine VPKs
(`garrysmod/*_dir.vpk` and `sourceengine/*_dir.vpk`). Nothing is extracted or
copied. VTFs are decoded and downsampled into one atlas, 128 px per material.
`--stats` lists the mounted VPKs and resolved/failed material counts. Set
`ZMV_DEBUG_MATERIALS=1` to print each material that could not be resolved.

## Lit and night modes

Lit mode reads `light`, `light_spot` and `light_environment` entities from the
expanded VMFs. `light_environment` supplies the sun and ambient colour; point
and spot lights are placed into a 640-unit grid and shaded per pixel. Night
mode turns off the sun and lowers the ambient so only placed lights remain.

Only some building, commercial and laboratory tiles author light entities.
Street lamps are props, so most streets are dark at night; this is the VMF
data, not a viewer fault. `--stats` reports the number of lit cells and the
cell with the most lights (for the current preview, `--cell 18 1 --night`).

## Limits

- No shadows: light passes through walls. No bounce lighting; this is not
  the VRAD lightmap.
- At most 8 lights per 640-unit grid cell; extra lights are dropped.
- Only `$basetexture`; blend textures, water shaders, decals, overlays and
  props are not drawn. Water materials without a base texture use a flat
  colour.
- The RGB565 channel order in the VTF decoder is unverified.
