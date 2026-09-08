# ZombieSim Agent Guide

ZombieSim is an installed Garry's Mod gamemode. It combines realm-specific Lua gameplay code with a PowerShell pipeline that generates and compiles reusable Source VMF recipe maps.

## Read First

- [readme.md](readme.md) contains the supported build, staging, in-game, and Walker simulator command sequences.
- [docs.md](docs.md) is the generator reference, including profile behavior, authored tile orientation, Hammer checks, and compile diagnostics.
- [docs/gdd.md](docs/gdd.md) describes intended gameplay behavior. Consult it before changing player progression or survival systems.
- [generator-settings.json](generator-settings.json) is the authoritative configuration schema. Do not infer settings or output paths from filenames.
- [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md) describes multi-tile template work.
- `bin/walker-simulator` is the portable C++ walker project; it stays isolated from Lua and generated assets, and its behavior and commands are documented in the root README.

## Runtime Architecture

- Keep Lua realm boundaries explicit: `init.lua` and `sv_*.lua` are server-side, `cl_*.lua` is client-side, and `shared.lua` / `sh_*.lua` run in both realms. Send shared and client files with `AddCSLuaFile`, then `include` files that must execute on the server.
- Preserve the existing Lua style: `//` comments, spaced function calls, four-space indentation in server files, and tabs where an existing shared/client file already uses tabs.
- World data is accessed through `ZM_World`; safe-zone lookup is owned by `ZM_SafeZones`. Use their APIs rather than duplicating coordinate, map-path, or profile resolution logic.
- Register network strings on the server before sending. Keep player persistence server-only through the SQL helpers and retain profile scoping.
- Treat raw grid coordinates as diagnostics only. Display and manipulate logical world coordinates through `ZM_World`; for a cross-map change, verify persisted `CellX`/`CellY`, safe-zone id, and resolved map path with `zombiesim_player_status` after the destination loads.
- Before changing a request involving a “map,” identify the intended surface: the world-map window, HUD minimap, satellite/level view, or Garry's Mod level transition. Locate its owning module and input binding; ask a focused question when the request does not distinguish them.

## Generator And Asset Boundaries

- Hand-authored tile VMFs live in `tiletemplates`; base maps and standalone safe rooms live in `celltemplates`. Edit these source assets, not generated files in `generated/src*`.
- Treat generated manifests, plans, VMFs, BSPs, staged profile maps, runtime JSON, and map materials as pipeline outputs. Regenerate them with the matching profile rather than hand-editing them.
- Every generator script must resolve settings through `bin/resolve_world_generation_profile.ps1`. Use `-WorldProfile preview` for normal iteration; it is isolated from the production `city` profile.
- Preserve canonical rotations and carpark endcap rules. `bin/carpark_endcaps.psm1` owns carpark cap selection and yaw; do not duplicate or derive it from lane role. Confirm orientation changes in Hammer.
- Before changing a placement or yaw mapping, inspect the canonical authored orientation and the exact generated `func_instance` that fails. Validate all four cardinal outputs plus any affected exceptional recipe in the developer zoo; never apply a global yaw offset from a single screenshot or recipe.
- Do not change a native model's `ModelOffset` to correct Backrooms placement. Correct the generator's block-cell placement.
- Standalone safe-zone maps are complete templates copied unchanged. Edit `celltemplates/safezones`, not their generated copies.

## Focused Validation

Run PowerShell commands from the repository root. For changes to planning or VMF generation, use the preview pipeline and start with the fast structural check:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

- After structural tile changes, run `./bin/check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData`; inspect affected layouts in Hammer, including generated developer zoos when applicable.
- Only use `-SkipVBSP` with `-SkipRecipeRefresh` when the source VMFs are unchanged from the portal preflight. Review `generated/build_<profile>/compile-report.json` for failed or incomplete stages.
- A full VVIS/VRAD build and in-game launch are deliberate final checks. Batch related changes before launching Garry's Mod; reload `zn_preview` after preview staging or `zn_start` after city staging.

## Environment Notes

- The repository is already under Garry's Mod. The active compiler profile resolves `vbsp`, `vvis`, and `vrad` from the game's `bin` directory.
- The development command bridge source is `content/data_static/consolecommands.txt`; its acknowledgement is deliberately written outside the repository to Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`.
- Scripts use `Set-StrictMode` and `$ErrorActionPreference = 'Stop'`. Retain parameter validation, path construction via `Join-Path`, and profile-driven paths. In Windows PowerShell 5.1, use `System.Diagnostics.Process` for monitored compiler processes because `Start-Process -PassThru` can expose an empty `ExitCode`.