---
name: world-build
description: "Generate, compile, stage, or validate ZombieSim procedural worlds, VMF recipes, BSPs, tile templates, map materials, and world profiles. Use for preview builds, Hammer checks, visibility budgets, or Garry's Mod world-release troubleshooting."
argument-hint: "Describe the changed asset or script, optional profile, and desired validation depth"
---

# ZombieSim World Build

Use this skill to rebuild only the necessary parts of a procedural ZombieSim world and validate the changed behavior. Default to the isolated `preview` profile. Do not run a full VVIS/VRAD build or launch Garry's Mod until the focused checks pass and the requester needs a playable result.

For configuration meanings, template-orientation contracts, and compiler diagnostics, consult the [generator guide](../../../docs.md). For the complete release and in-game command reference, consult the [project readme](../../../readme.md).

## Decide The Smallest Workflow

1. Identify the change surface before running commands.
   - Lua-only runtime changes: do not regenerate or compile maps unless the Lua code changes how it consumes generated data.
   - Hand-authored tile VMFs or placement/orientation logic: refresh the relevant developer zoo and preview VMFs, then run VBSP. Inspect changed arrangements in Hammer.
   - Generator settings, map generation, or planning logic: regenerate the preview manifest and plan before rebuilding VMFs.
   - VMF writer, base-cell, or safe-zone-template changes: rebuild preview VMFs and run VBSP; run visibility budgets for structural geometry changes.
   - Map-material renderer changes: regenerate and stitch preview materials; compilation is unnecessary unless VMFs also changed.
2. Use `-WorldProfile preview` unless the request explicitly requires a production `city` build. Keep the seed stable at `1337` while comparing changes.
3. Never edit generated manifests, plans, VMFs, BSPs, staged profile maps, runtime JSON, or map material outputs by hand. Edit their source or generator, then regenerate.

## Preview Generation And VMF Check

Run this sequence from the repository root when planning inputs, template selection, or generation logic changed:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
```

Use the existing matching manifest and plan instead of regenerating them only when the change cannot affect world layout or recipe selection:

```powershell
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
```

Then run the focused structural compile check:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

Treat a nonzero result, a missing required VMF, or a failed/incomplete entry in `generated/build_preview/compile-report.json` as a failed check. Correct the source VMF, instance path, planner, or configuration before escalating to a full compile.

## Template And Topology Inspection

After adding, moving, renaming, rotating, or changing tile-placement behavior, regenerate the Hammer development fixtures:

```powershell
.\bin\build_tile_zoos.ps1 -RefreshPlan
```

Open the relevant VMF under `celltemplates/dev` in Hammer. Confirm physical connections, `func_instance` files, and angles against the canonical table in [docs.md](../../../docs.md). For carpark work, `bin/carpark_endcaps.psm1` is the sole owner of cap file/yaw selection; do not duplicate its mapping or select it from a lane role. Do not fix Backrooms placement by changing a native model `ModelOffset`; correct the generator's block-cell placement.

## Geometry And Visibility Checks

After an edit can alter brush geometry, portals, skybox closure, or large sightlines, run:

```powershell
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

Investigate nonzero exits in `generated/build_preview/vis-budget-report.json` and the affected recipe before a VVIS/VRAD build. The check can reuse valid portal files; use `-ForcePortalData` only when a clean portal preflight is needed.

## Materials-Only Workflow

For local map renderers, satellite composition, or staged material changes that do not alter source VMFs:

```powershell
.\bin\stage_world_map_materials.ps1 -WorldProfile preview
.\bin\build_cell_map_materials.ps1 -WorldProfile preview
.\bin\build_world_satellite_material.ps1 -WorldProfile preview
```

When a manifest or template plan changes, also refresh the runtime index after the required BSPs exist:

```powershell
.\bin\export_runtime_world_data.ps1 -WorldProfile preview -RequireCompiledMaps
```

## Playable Preview Or Release

Only after VBSP and, when applicable, visibility checks have passed, build a playable preview from known-good portal data:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity
```

`-SkipVBSP` is valid only when every source VMF is unchanged from the portal preflight. It must be paired with `-SkipRecipeRefresh`; otherwise the staged release may combine new VMFs with old portal data.

For a deliberate full preview compile, use:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -Force -CleanStagedCity -VvisTimeoutSeconds 1800 -VradTimeoutSeconds 3600
```

Review `generated/build_preview/compile-report.json` before staging or testing. Compiler timeouts are deferred rather than killed; incomplete work blocks release staging. For in-game verification, reload `zn_preview`, test the changed map behavior, and use `zombiesim_player_status` for profile/cell resolution issues. Batch related changes before one deliberate game launch.

For production, replace `preview` with `city` only after the preview is accepted. Use the selected profile's current manifest and template-plan paths; do not mix artifacts between profiles.

## Completion Criteria

- Generated artifacts came from the matching profile and current source inputs.
- `check_required_cells` and the relevant VBSP or material checks completed successfully.
- Structural edits also have a passing visibility-budget check and Hammer inspection where applicable.
- Playable builds have no failed or incomplete compiler stages, and the staged world index and BSPs belong to the same profile.