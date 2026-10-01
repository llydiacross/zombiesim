# Alpha 2.8.6 (Landmark Safe Zones, The Storm Drain, and Safe-Zone Entrances)

Alpha 2.8.6 is queued after Alpha 2.8.5 closes and must close before Alpha 2.9 starts. It is the only milestone in this sequence that deliberately changes the generated world. See Phase F.

## Features to Implement

These are the original requests, with the clarifications agreed on 2026-10-01.

- I have changed how safezone cells work. please check the celltemplates/safezones and instead of having a safezone for each environment now there is just a safezone for each landmark, cell_safezone is the default safezone for all landmarks unless otherwise specified.
- I have created a new savezone called cell_safezone in celltemplates/safezones/cell_safezone.vmf it should include the new den all the npcs along with the bank and the player stash. This should be the default safezone if we can't determin one for what ever reason
- Please change the current implement to no longer take an environment parameter and instead rely on the landmark-specific safezone configuration.
- Rename "The Evac Zone" to "The Storm Drain" as cell_safezone at 0,0 should now be the Storm Drain.
- In tiletemplates/safezones/ there is now entrance_safezone_3x that should be used for cell_safezone entrances. This is the 3x3 tile that is placed on the map as the entrance to take you to the den, so in this case tiletemplates/safezones/entrance_safezone_3x.vmf takes you to celltemplates/safezones/cell_safezone.vmf
- 3x3 tiles may take up border tiles
- These entrances are placed in the cell the safezone is in, always place them next to a road.
- In the case of 0,0 for "The Evac Zone" now "The Storm Drain" place the entrance_safezone_2x on the north side of the cell after aligned so the t-section road piece is in the middle.
  - **Clarified:** `entrance_safezone_2x` is `entrance_safezone_3x`; no 2x entrance exists.
  - **Corrected (2026-10-01):** keep the generated world roads unchanged.
    - The origin in the current preview is a T-junction with roads north, east and south (`missing-west`).
    - Centre the Storm Drain entrance on the T's empty side (west in the current plan), facing east onto the junction, so the T piece is in the middle of its front edge.
    - This supersedes the earlier "north corner" clarification. Don't force the origin into a different T orientation, because that would change the world graph.
  - **Generalised:** any safe-zone cell with a side that has no road uses the same edge-centred placement on that side.
- If the tile is 3x3, place it in the corner, taking up a bit of the border
  - **Corrected (2026-10-01):** the corner placement is used only when every side has a road, which means a crossroads.
  - A corner entrance covers one 2x2 corner quadrant of the 5x5 playable grid, plus one row and one column of the border ring outside it, and faces an adjacent road.
  - Either placement replaces the border-ring pieces it covers, so the entrance must seal the level itself.

## Findings From the Planning Audit (2026-10-01)

- **The "environment parameter" is the safe-zone biome.**
  - The planner chooses a den from `cellPlanning.safeZones.biomePriority`, `biomeCodes` and `defaultBiome`, using `templateFilenameFormat` `cell_{biome}_safezone{landmarkSuffix}.vmf`.
  - It names the output `zz_<profile>_den_<biomeCode>[_<landmark>].vmf`.
  - `export_runtime_world_data.ps1` exports `biome` and `landmarkVariant`, and `ZM_SafeZones:GetBiome` / `GetLandmarkVariant` read them. Neither function has a caller.
- **The world pipeline is currently broken for safe zones.**
  - The current preview plan still references `cell_gr_safezone.vmf`, `cell_ra_safezone.vmf`, `cell_fo_safezone_bunker.vmf` and similar files. Those templates no longer exist.
  - Any planner run fails its template-existence check until Phase B lands.
  - The loaded preview world and its compiled dens (`zz_preview_den_gr` and others) keep working, because nothing has been regenerated.
- **Leftover landmark templates.**
  - `cell_safezone_hospital.vmf`, `cell_safezone_army_base.vmf` and `cell_safezone_bunker.vmf` are old 84 KB placeholder copies.
  - They have no den NPCs, bank or stash, so mapping a landmark to one would produce an empty den.
- **`cell_safezone.vmf` contents:**
  - four `zn_den_npc` entities:

    | NPC | Profession | Trader |
    | --- | --- | --- |
    | Ketamine Keith | Scientist | none |
    | Dr Marc Laidlaw | Doctor | `clinic` |
    | Mr Cheese | Army Soldier | `quartermaster` |
    | Simon Whistler | Capitalist | `general` |

  - one `zn_den_stash` and one `zn_bank`;
  - `info_player_start` at the south;
  - the `NORTH_ENTRANCE`, `SOUTH_ENTRANCE`, `EAST_ENTRANCE` and `WEST_ENTRANCE` landmarks;
  - three `func_areaportal` entities.
- **Den NPC names don't reach the game.**
  - The NPC names are authored in `targetname`, but `sv_den_npcs.lua` reads only `npc_name`.
  - The NPCs would therefore display as their trader or profession name, not as Ketamine Keith and the others.
- **The den has no way out.** It contains no exit interaction.
- **The entrance tile has no interaction points.**
  - `entrance_safezone_3x.vmf` is 1920x1920 units (3 x 640) and 512 units tall.
  - Its single `zn_tile_direction` is `west` at `-960 0 40`. The documented 3x midpoint is `-960 0 32`; only the edge and axis matter.
  - Its doors are plain `prop_dynamic_override` models. It has no entry interaction and no arrival point for players returning from the den.
- **Players can't physically walk between a city cell and a den today.** Dens are reached only through:
  - `GM:EnterOriginSafeZone`, for a new character or session;
  - the preview teleport in `sv_preview.lua`.

  The cell-to-cell gates in `sv_transitions.lua` handle only the four border directions. `docs.md` still refers to a never-built `tile_saferoom` entrance.
- **Placement code:**
  - Safe-zone placement lives in `generate_world_cells.ps1`: one per district, preferring the `Hospital`, `Army Base` and `Bunker` landmarks.
  - The origin is hard-coded as `"The Evac Zone"`, with the same name also in the completion message.
  - Safe-zone ids are `safezone-<x>-<y>`. They key `player_data.CurrentSafeZoneId`, `den_stash_items`, the trade stock and the trade ledger.
  - Because the placement algorithm doesn't change, ids for the same seed must stay identical after this milestone.
- **Overlap with Alpha 2.9.**
  - Alpha 2.9 Phase B (den camera, entrances, transition gates) assumes den entry and exit already exist, and Alpha 2.9 forbids regenerating the world.
  - Alpha 2.8.6 therefore owns the physical entrance and exit, plus the one approved regeneration.
  - Alpha 2.9 Phase B then layers the camera and cinematic presentation on this contract.

## Implementation Plan

### Source of Truth / Working Rules

- This file is the authoritative tracker for Alpha 2.8.6 scope, decisions, phase status and remaining verification. Don't start it until Alpha 2.8.5 is closed. Close it before Alpha 2.9 Phase A.
- Hand-authored assets stay the source of truth. Edit these, never their `generated/` copies:
  - `celltemplates/safezones/*.vmf`
  - `tiletemplates/safezones/*.vmf`
  - `zombiesim.fgd`
  - `generator-settings.json`

  Hammer-placed entities in the source VMFs are authored by the user in Hammer. When a plain-text VMF edit is agreed, add only point entities, and reopen the file in Hammer to confirm.
- All generator scripts resolve settings through `bin/resolve_world_generation_profile.ps1`. Iterate on focused fixtures and developer zoos first.
- **The preview world is regenerated once, only in Phase F, and only after explicit approval.** The production `city` profile isn't touched in this milestone.
- The server owns safe-zone entry, exit and persistence. Clients only present, and every door interaction is re-validated on the server.
- Reuse `ZM_World`, `ZM_SafeZones`, `ZM_Transitions`, `GM:EnsurePlayerWorldMap` and `ply:SetCurrentSafeZone`. Don't duplicate map-path, profile or coordinate resolution.
- Report each phase's static and automated results separately from in-game and Hammer checks.
- Run `.\bin\test_glua_syntax.ps1` after every Lua change.

### Phase A: Contracts, Asset Audit, and Decisions

- **Configuration contract.** Record the replacement for `cellPlanning.safeZones`:
  - `templateDirectory`: the existing `safeZoneTemplateDirectory` remains.
  - `defaultTemplate`: `cell_safezone.vmf`.
  - `landmarkPriority`: which landmark wins when a cell has several.
  - `landmarkTemplates`: a map from landmark name to template filename. An unmapped landmark, a cell with no landmark, or an unresolved case all use `defaultTemplate`.
  - `entrance`: `template` `safezones/entrance_safezone_3x.vmf`, `footprint` `3`, and `origin` rules.
  - Remove `biomePriority`, `biomeCodes`, `defaultBiome` and `templateFilenameFormat`.
  - **Decision (recommended):** start with an empty `landmarkTemplates`, so every safe zone, including the origin, uses `cell_safezone.vmf`.
  - Leave the placeholder landmark templates unreferenced until the user authors them. Deleting them is the user's decision.
- **Den map naming.**
  - The default den is `zz_<profile>_den.vmf`; landmark dens are `zz_<profile>_den_<landmark_slug>.vmf`.
  - All safe zones sharing a template share one BSP.
  - Stash and trade data stay per safe-zone id, not per map.
- **Placement contract** (tile grid: `tileX` increases east, `tileY` increases south; 5x5 playable grid `0..4`; border ring at `-1` and `5`):
  - **Placement mode:** the cell's active road entrances (`activeEntrances`, the N/E/S/W sides whose centre edge has a road) decide the mode.
    - **Edge-centred** when at least one side has no road: T-junctions, straights, corners and dead ends.
    - **Corner** only when all four sides have a road (a crossroads).
  - **Edge slots** (edge-centred mode):
    - `W` covers tiles `(-1..1, 1..3)`, `E` `(3..5, 1..3)`, `N` `(1..3, -1..1)` and `S` `(1..3, 3..5)`.
    - Each covers six playable tiles plus the three ring tiles on that side. A roadless side has no transition gate, so the slot never covers one.
    - The front edge faces inward onto the centre column or row (tiles `(2, 1..3)` for `W`), so the centre road piece, such as the T-junction, sits in the middle of the front edge.
    - **Side choice:**
      - a T-junction uses its single missing side;
      - a corner or straight has two roadless sides, a dead end three;
      - choose among them with the cell's placement seed. For a dead end, prefer the two sides adjacent to the road, so the front faces a road tile as well as the dead-end cap.
  - **Quadrants** (corner mode):
    - `NW` covers tiles `(-1..1, -1..1)`, `NE` `(3..5, -1..1)`, `SW` `(-1..1, 3..5)` and `SE` `(3..5, 3..5)`. Each covers the 2x2 playable corner plus five ring tiles.
    - **Facing:** the entrance faces the adjacent road on one of its two inner edges. Both always touch a road at a crossroads, so prefer a straight road tile over the junction, then break a tie with the placement seed.
  - **Every placement:**
    - Its front edge must be directly adjacent to an ordinary road tile, or to the centre junction.
    - None of its playable tiles is reserved by an exclusive landmark such as The Epicenter.
    - None of its ring tiles is a water border, a carpark endcap or a transition gate.
    - The entrance's authored `west` front edge is rotated to the chosen facing. `W` faces east, `E` west, `N` south and `S` north.
    - If the preferred edge slot is invalid, try the other roadless sides, then the corner quadrants, before failing.
  - **Origin rule (the Storm Drain):** use the general rule. In the current preview plan the origin is `missing-west`, which gives the `W` slot facing east onto the T-junction.
    - Add a focused regression that pins this result for the origin.
    - Confirm it in Hammer before regenerating.
  - **No valid placement:** planning fails with the cell coordinate and the reason, rather than dropping the entrance silently.
- **Interaction contract.**
  - Add two FGD point entities:
    - `zn_safezone_door` with `role` `enter` or `exit`, and an optional `use_radius` (default 96);
    - `zn_safezone_arrival` with angles.
  - The **entrance tile** gets one or more `enter` doors at its door props, and one `zn_safezone_arrival` outside the front door. Players returning from the den spawn there.
  - The **den** gets `exit` doors at its entrance door or doors.
    - Entering places the player at `SOUTH_ENTRANCE` (the den's front door, beside `info_player_start`).
    - Look up entities by class, not name, because instance name fix-up prefixes the targetnames of point entities inside func_instances.
  - **Entry:** use the door → the server checks the conditions below → persist `CurrentSafeZoneId` → sync ammo and change level through `EnsurePlayerWorldMap` → spawn at `SOUTH_ENTRANCE`. The server checks:
    - the player's persisted cell is this cell, and the cell has a safe zone;
    - there is exactly one human player, matching the gate rule;
    - no transition is already queued;
    - persistent state is loaded.
  - **Exit:** use the door → clear `CurrentSafeZoneId` → change level to the city cell map → the pending entry places the player at `zn_safezone_arrival`.
  - **Failure paths:** a persistence failure rolls back and prints a centre message. A missing arrival point falls back to the cell's `info_player_start`.
- **Asset audit.** Record these fixes against the source assets:
  - den NPC names: add a `targetname` fallback in code (Phase E), or have the user fill in `npc_name`. **Recommended:** add the code fallback, which keeps existing Hammer data working;
  - validate that the professions and traders resolve (`zn_den_npcs`);
  - confirm the entrance tile seals the world where it replaces ring pieces: outer faces, a ceiling or skybox as tall as the ring, and no leak through the door gaps;
  - confirm the den compiles on its own (VBSP only, output to `generated/`, nothing staged).
- **Acceptance:** the contracts above are recorded here, the asset list is shared with the user, and any Hammer work needed for Phase D is agreed. No generated world output changes.

### Phase B: Landmark Safe-Zone Configuration (No Environment Parameter)

- **`generator-settings.json`:** replace `cellPlanning.safeZones` with the Phase A schema, and update any profile override in the preview and city profiles.
- **`plan_cell_templates.ps1`:**
  - Remove `Get-SafeZoneBiome` and the use of the biome code.
  - Resolve the template in this order: highest-priority mapped landmark in the cell, then `defaultTemplate`.
  - Validate that every configured template exists and that every `landmarkTemplates` key is a landmark name the generator knows.
  - Emit these fields on `safeZoneMaps`: `landmark`, `templateFilename`, `mapFilename` and `mapName`. Drop `biome` and `biomeCode`.
- **`build_cell_vmfs.ps1`:**
  - Copy the selected den templates unchanged, with the VMX sidecar when one exists.
  - Keep the filename-conflict checks.
  - Prune obsolete `zz_<profile>_den_*` sources, such as `_den_gr`, only with `-PruneStaleGenerated`.
- **`export_runtime_world_data.ps1`:** export `landmark` and `template` instead of `biome` and `landmarkVariant`. Keep `id`, `name`, `isOrigin`, `district`, `cell`, `difficult` and `map` unchanged.
- **`generate_world_cells.ps1`:** rename the origin to **"The Storm Drain"**, including in the completion message.
  - Safe-zone placement scoring doesn't change.
  - Add a regression that fails if the set of safe-zone ids and coordinates for seed 1337 differs from the pre-change list.
- **Acceptance:**
  - A focused planner run on a fixture map, not the preview world, selects `cell_safezone.vmf` for landmark-less cells, unmapped landmarks and the origin.
  - A temporary fixture-only mapping proves landmark overrides and priority.
  - A missing template fails with a clear message.
  - Safe-zone ids are unchanged.

### Phase C: Safe-Zone Entrance Placement in the Planner

- Reserve the entrance before buildings, landmarks, carparks and decorations are placed in a safe-zone cell. Those passes skip reserved tiles, and a multi-tile landmark keeps a valid placement outside the reserved footprint.
- Apply the placement-mode (edge-centred or corner), facing and fallback rules from Phase A.
- **Emit on the cell plan:**
  - `safeZoneEntrance`, containing:
    - `template`;
    - `mode`: `edge` or `corner`;
    - `slot`: `N`, `E`, `S` or `W` for an edge placement, `NW`, `NE`, `SW` or `SE` for a corner;
    - `anchorTile`: the footprint's top-left tile, which may be `-1`;
    - `footprint`, `yaw`, `frontage`;
    - the adjacent road tile.
  - `suppressedBorderTiles`: the ring coordinates the entrance replaces.
- **Carparks:** keep carpark endcap selection in `bin/carpark_endcaps.psm1`. A lane that would put an endcap on a suppressed ring tile makes that placement invalid; don't move or duplicate the endcap.
- **Filename hash:** fold the entrance into the recipe hash, so identical layouts still share recipes and different entrance placements don't collide.
- **Focused regression:** add `bin/test_safezone_entrances.ps1` with a fixture map covering:
  - edge-centred placement on each T-junction orientation (`missing-north`, `-east`, `-south` and `-west`), with the T piece in the middle of the front edge;
  - edge placement for straight, corner and dead-end cells, including the seed choice between roadless sides;
  - corner placement for a crossroads in each quadrant, with the facing preference and tie-break;
  - the origin: `missing-west` gives the `W` slot facing east;
  - an exclusive-landmark conflict;
  - water-border and carpark-endcap rejection, falling back to another slot;
  - a no-valid-placement failure.

  Also run the existing `test_building_frontage.ps1`, `test_multi_tile_templates.ps1` and `test_phase_c2_layouts.ps1`.
- **Acceptance:** every focused test passes, and the plan for fixture cells matches the Phase A contract, stated in logical tile coordinates and cardinal directions. Nothing in the preview world is regenerated.

### Phase D: VMF Writer, Assets, and Developer Zoo

- **`build_cell_vmfs.ps1`:**
  - Write the entrance as one `func_instance` at the centre of its 3x3 footprint, with the planned `angles`.
  - Omit ring instances at `suppressedBorderTiles`. An edge placement replaces three ring pieces on its side; a corner placement replaces the corner ring piece and its four neighbours. The rest of the ring and the gates are unchanged.
- **Entities:** add `zn_safezone_door` and `zn_safezone_arrival` to `zombiesim.fgd`.
- **User work in Hammer:** place `enter` doors and the arrival point in `entrance_safezone_3x.vmf`, and `exit` doors in `cell_safezone.vmf`. This is either done by the user, or added as agreed plain-text point entities that are then confirmed in Hammer.
- **Developer zoo:** extend `build_tile_zoos.ps1` with a safe-zone entrance zoo. It covers:
  - edge placement on all four T-junction orientations, plus a straight, a corner and a dead end;
  - corner placement in all four crossroads quadrants;
  - the origin case (`missing-west`, `W` slot).
  - Run `.\bin\build_tile_zoos.ps1 -RefreshPlan`.
  - Inspect each arrangement in Hammer: the front door faces the road, the ring is replaced cleanly, no gaps into the skybox, and the gates are untouched.
- **Compile checks:** run a VBSP-only compile of the zoo and of the standalone den, both output to `generated/`. They must show no leaks and no missing instance paths. Run the visibility-budget check on the zoo, because the entrance changes the sightlines along the border.
- **Acceptance:** Hammer inspection is recorded for every zoo arrangement, and the compile and visibility reports are clean. The preview world is still unchanged.

### Phase E: Runtime Entry, Exit, and Safe-Zone Data

- **`gamemode/utils/safezone.lua`:**
  - Remove `GetBiome`.
  - Replace `GetLandmarkVariant` with `GetLandmark` and `GetTemplate`.
  - Add `GetEntrance(id)`, which returns the entrance's tile anchor, footprint, yaw and frontage from runtime data.
  - Update the comment in `world.lua`.
  - Keep the old runtime data readable until Phase F: a missing `landmark` or `entrance` means "unknown", never an error.
- **Export:** `export_runtime_world_data.ps1` exports `safeZones[*].entrance`, using the Phase C plan fields.
- **Server door service:** new `gamemode/sv_safezone_doors.lua`, or an extension of `sv_transitions.lua` that reuses its pending-entry, one-human and queued-transition guards.
  - Implement the Phase A entry and exit flows. Use a pending-entry record with an `anchorClass`, so an exit places the player at `zn_safezone_arrival` and an entry at `SOUTH_ENTRANCE`.
  - Show a use prompt for nearby doors, matching the existing gate behaviour.
- **Den NPC names:** `sv_den_npcs.lua` falls back to the entity's Hammer `targetname` when `npc_name` is empty. Document the precedence.
- **Keep working unchanged:**
  - `GM:EnterOriginSafeZone`: new characters start in the Storm Drain;
  - the preview teleport;
  - stash, bank and trade gating (`CanAccessStash` compares against `ZM_SafeZones:GetMap`);
  - `CurrentSafeZoneId` persistence;
  - death and respawn inside a den.
- **Presentation:**
  - The world map and the HUD compass show the entrance marker at its tile position inside a safe-zone cell.
  - A waypoint set on a safe-zone cell points at the entrance. Alpha 2.9 Phase B adds the camera and cinematic treatment later.
- **Tests:** add a `zn_test_safezones` suite using `ZM_TestHarness`. It covers:
  - runtime field resolution, including old data;
  - rejected entry: wrong cell, cell without a safe zone, queued transition, persistence failure;
  - entry followed by exit, restoring `CurrentSafeZoneId` and the cell;
  - the NPC name fallback.

  Also rerun `zn_test_inventory`, `zn_test_trading`, `zn_test_professions` and `zn_test_characters`.
- **Acceptance:** GLua syntax passes, and the in-game suites pass against the existing preview world, with entrance data absent and handled gracefully. Live door checks wait for Phase F.

### Phase F: Approved Preview World Regeneration and Staging

- **Gate:** get the user's explicit go-ahead first, and record the current preview safe-zone id and coordinate list. Back up the live `sv.db` character data before any world or map change that loads for real players.
- **Regenerate** the preview profile with seed 1337 (world-build skill):

  ```powershell
  .\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
  .\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
  .\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
  .\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
  .\bin\check_required_cells.ps1 -WorldProfile preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
  .\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
  .\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
  ```

- **Before the full compile:**
  - Confirm that the safe-zone ids and coordinates match the recorded list.
  - Confirm every safe-zone cell plan has a `safeZoneEntrance`.
  - Confirm the origin entrance is centred on the west side of `(0, 0)`, facing east with the T-junction in the middle of its front edge. If the regenerated origin has a different T orientation, the entrance must be on its missing side.
  - Open the origin recipe and one other safe-zone recipe in Hammer, and check the `func_instance` name, source template, origin and angles.
- **Build and stage:**
  - Run the full preview compile and review `generated/build_preview/compile-report.json`.
  - Refresh the map materials and the satellite view.
  - Run `export_runtime_world_data.ps1 -WorldProfile preview -RequireCompiledMaps`.
  - Refresh the walker test fixture (`bin/walker-simulator/tests/fixtures/preview-world.json`) only if its schema consumer needs the new fields, then run the walker `ctest`.
  - Build cubemaps for the den and the changed recipes.
- **Acceptance:** the compile report has no failed or incomplete stages, the staged index and BSPs belong to the preview profile, the old `zz_preview_den_*` BSPs are pruned, and `zz_preview_den` is staged.

### Phase G: Live Verification, Documentation, and Close-Out

- **Live checks**, after reloading `zn_preview_start`:
  - a new character spawns in the Storm Drain den;
  - the NPC names are Ketamine Keith, Dr Marc Laidlaw, Mr Cheese and Simon Whistler;
  - trading, services, the bank and the stash all work;
  - the exit door puts the player at the Storm Drain entrance, on the T-junction's empty side of `(0, 0)` and facing the junction;
  - re-entering works;
  - walking to a second safe zone and entering it gives a separate stash;
  - disconnecting and reconnecting inside a den, and dying inside a den, both behave correctly;
  - `zombiesim_player_status` shows the cell, safe-zone id and map after every transition.
- **Regressions:** rerun the Phase E suites, plus `zn_validate_static`, `zn_test_loot_spots` and the cell-to-cell gates in all four directions from a safe-zone cell.
- **Documentation:**
  - Rewrite the `docs.md` "Standalone Dens" section and the safe-zone settings table.
  - Replace the `tile_saferoom` wording.
  - Document the entrance tile orientation contract.
  - Update the `readme.md` safe-zone and den NPC notes (the name precedence) and the FGD entity list.
  - Update `AGENTS.md` and this tracker to show the milestone as closed and Alpha 2.9 as active.
  - Update Alpha 2.9 Phase B so it builds on the door contract, rather than on still-missing den entry and exit.
- **Acceptance:** every live item passes, with static and live results recorded separately below, or is explicitly deferred with a reason.

## Status

- [ ] Phase A: Contracts, Asset Audit, and Decisions
- [ ] Phase B: Landmark Safe-Zone Configuration
- [ ] Phase C: Safe-Zone Entrance Placement
- [ ] Phase D: VMF Writer, Assets, and Developer Zoo
- [ ] Phase E: Runtime Entry, Exit, and Safe-Zone Data
- [ ] Phase F: Approved Preview World Regeneration (needs explicit approval)
- [ ] Phase G: Live Verification, Documentation, and Close-Out
