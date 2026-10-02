# Todo Alpha 2.9.1

## Goals & Objectives
- Introduce bounded multi-process map compiling to reduce compile times across multi-core systems.
- Use Hammer compiler presets (`-fast` for preview VVIS/VRAD and `-final`/static-prop lighting flags for final builds).
- Introduce detailed step-by-step console logging in the world generation pipeline (`generate_world_cells.ps1`).
- Increase portal budget constraints to 1.5x the current baseline values (clusters: 500 -> 750, portals: 900 -> 1350).
- Relocate all test Lua files from the `gamemode/` root into a clean `gamemode/tests/` subdirectory and update includes.

---

## Detailed Implementation Plan

### Phase 1: Portal Budget Constraint Adjustment (1.5x)
- [x] **Update settings schema:** In [generator-settings.json](../generator-settings.json), increase `compilation.visibilityBudget.maxPortalClusters` from `500` to `750` and `maxPortals` from `900` to `1350`.
- [x] **Update script defaults:** In [bin/check_vis_budgets.ps1](../bin/check_vis_budgets.ps1), update default fallback values to `750` and `1350`.
- [x] **Documentation:** Update [docs.md](../docs.md) visibility budget section to record the updated 750 cluster / 1,350 portal budget limits.

### Phase 2: Relocate Test Files to Dedicated `gamemode/tests/` Directory
- [x] **Directory structure:** Create `gamemode/tests/`.
- [x] **Move test suites:** Move all 14 `sv_*_tests.lua` suites from `gamemode/` to `gamemode/tests/`:
  - `sv_characters_tests.lua` -> `gamemode/tests/sv_characters_tests.lua`
  - `sv_static_data_tests.lua` -> `gamemode/tests/sv_static_data_tests.lua`
  - `sv_weapon_catalog_tests.lua` -> `gamemode/tests/sv_weapon_catalog_tests.lua`
  - `sv_inventory_tests.lua` -> `gamemode/tests/sv_inventory_tests.lua`
  - `sv_crafting_tests.lua` -> `gamemode/tests/sv_crafting_tests.lua`
  - `sv_professions_tests.lua` -> `gamemode/tests/sv_professions_tests.lua`
  - `sv_implants_tests.lua` -> `gamemode/tests/sv_implants_tests.lua`
  - `sv_mastercraft_tests.lua` -> `gamemode/tests/sv_mastercraft_tests.lua`
  - `sv_trading_tests.lua` -> `gamemode/tests/sv_trading_tests.lua`
  - `sv_loot_tests.lua` -> `gamemode/tests/sv_loot_tests.lua`
  - `sv_enemies_tests.lua` -> `gamemode/tests/sv_enemies_tests.lua`
  - `sv_bosses_tests.lua` -> `gamemode/tests/sv_bosses_tests.lua`
  - `sv_loot_spots_tests.lua` -> `gamemode/tests/sv_loot_spots_tests.lua`
  - `sv_safezone_doors_tests.lua` -> `gamemode/tests/sv_safezone_doors_tests.lua`
- [x] **Update includes in [gamemode/init.lua](../gamemode/init.lua):** Change all `include("sv_*_tests.lua")` statements to `include("tests/sv_*_tests.lua")`.
- [x] **Static verification:** Run `.\bin\test_glua_syntax.ps1` to ensure all 125+ files parse cleanly without syntax or path issues (125 files, zero failures).

### Phase 3: Comprehensive Console Logging for World Generation
- [x] **Script:** [bin/generate_world_cells.ps1](../bin/generate_world_cells.ps1).
- [x] Add structured, informative console messages at every key algorithmic phase:
  - `[WorldGen][Init]`: Grid dimensions, cell size, seed, active profile, and destination paths.
  - `[WorldGen][Radiation]`: Calculated epicenter coordinates, fallout radius, and megaton yields.
  - `[WorldGen][Roads]`: Grid spine seeding, arterial growth depth, branching passes, and total road cells.
  - `[WorldGen][Highways]`: Interstate placement, crossing restrictions, overpasses/bridges, and district ramp links.
  - `[WorldGen][Repairs]`: Dead-end repair counts and cross-highway connectivity checks.
  - `[WorldGen][SafeZones]`: Safe-zone / den selection per district, spacing criteria checks, and disconnected entrance repairs.
  - `[WorldGen][Blockades]`: Highway-reachability exit validations and placed blockades count.
  - `[WorldGen][Landmarks]`: Placed special landmarks (hospitals, police stations, bunkers, labs, epicenter).
  - `[WorldGen][Metro]`: Station selection and A* track routing across lines.
  - `[WorldGen][Environment]`: Terrain categorization, building footprint counts, and danger zoning tiers.
  - `[WorldGen][Export]`: Writing cell JSON data and rendering layer PNGs.
  - `[WorldGen][Complete]`: Summary of total cells, populations, road density, and file locations.

### Phase 4: Fast vs. Final Hammer Compiler Flags
- [x] **Settings schema in [generator-settings.json](../generator-settings.json):**
  - Add preset argument definitions under `compilation.stagePresets`:
    - `fast`:
      - `vvis`: `["-game", "{gameDirectory}", "-fast", "{mapBsp}"]`
      - `vrad`: `["-game", "{gameDirectory}", "-fast", "{mapBsp}"]`
    - `final`:
      - `vvis`: `["-game", "{gameDirectory}", "{mapBsp}"]`
      - `vrad`: `["-game", "{gameDirectory}", "-final", "-staticproplighting", "-staticproppolys", "{mapBsp}"]`
- [x] **Parameters in [bin/compile_cell_vmfs.ps1](../bin/compile_cell_vmfs.ps1) & [bin/build_city.ps1](../bin/build_city.ps1):**
  - Add `[switch]$Fast` and `[switch]$Final` switches.
  - Automatically default to `fast` when `-WorldProfile preview` is active, unless `-Final` is explicitly supplied.
  - Default production (`city`) builds to `final`.

### Phase 5: Multi-Process Parallel Map Compiling Pool
- [x] **Configuration:** Add `compilation.maxParallelProcesses` to [generator-settings.json](../generator-settings.json) (default `4`).
- [x] **Parallel runner in [bin/compile_cell_vmfs.ps1](../bin/compile_cell_vmfs.ps1):**
  - Replace the monolithic single-map sequential loop with a process pool queue using `[System.Diagnostics.Process]` (PowerShell 5.1 compliant).
  - Manage a list of active compile slots up to `$MaxParallelProcesses`.
  - Track per-slot state: `MapName`, `CurrentStage` (`vbsp` -> `vvis` -> `vrad`), `Process`, `Stopwatch`, and log paths.
  - While work remains in queue or slots are active:
    - Poll running processes every `$progressRefreshMilliseconds`.
    - If a process finishes with exit code 0, advance that map to its next stage (`vvis` or `vrad`).
    - If a process finishes its last stage (or fails), finalize the map record and assign the next map from the queue to the free slot.
    - Monitor timeouts per active process slot.
  - The installed stock Hammer tools expose `-threads` as a valueless switch, not a numeric thread limit; VBSP/VVIS reject an appended thread count. The runner therefore caps active compiler processes with the pool rather than passing an invalid or misleading argument. This compatibility deviation is documented in [docs.md](../docs.md) and [readme.md](../readme.md).
- [x] **Initial verification:** Compiled the same two preview maps through VBSP/VVIS/VRAD using the `fast` preset: sequential (pool 1) took 20.7s; parallel (pool 2) took 14.0s in the measured comparison and 14.7s in a repeat verification (about 29–32% faster for this small subset). Both reports show 2/2 compiled, 0 failed, 0 incomplete.
- [x] **Pool-size benchmark (2026-10-01):** Recompiled the same eight required preview city recipes, stratified from high- to low-portal cost, with VBSP/VVIS/VRAD and the `fast` preset. Each run used a fresh isolated build directory, `-Force`, and identical inputs on an AMD Ryzen 5 5600GT (6 cores / 12 logical processors; 16 GB RAM). All runs completed 8/8 recipes with 0 failures and 0 incomplete stages.

  | Pool size | Wall time | Speedup vs. 1 | Peak compiler working set | Minimum available memory |
  | ---: | ---: | ---: | ---: | ---: |
  | 1 | 90.8 s | baseline | 455 MB | 4,055 MB |
  | 2 | 54.3 s | 1.67x | 825 MB | 3,931 MB |
  | 4 | 48.4 s | 1.88x | 1,761 MB | 3,208 MB |
  | 6 | 48.0 s | 1.89x | 2,347 MB | 2,546 MB |

  **Decision:** Keep the configured default at 4. Pool 6 improved this single run by only 0.4 seconds over pool 4 while increasing peak compiler memory by about 586 MB; the result does not justify raising the default. The sample is focused rather than a full 170-recipe preview build, so remeasure on a larger workload before changing the default.
- [x] **Larger pool-size comparison (2026-10-01):** To check sustained queue behavior, compiled the same 24 preview city recipes, stratified across portal costs, with `-Fast -Force` in fresh isolated build directories. Pools 4, 6, and 8 all completed 24/24 recipes with 0 failures and 0 incomplete stages on the same 6-core / 12-logical-processor, 16 GB system.

  | Pool size | Wall time | Speedup vs. 4 | Peak compiler working set | Minimum available memory |
  | ---: | ---: | ---: | ---: | ---: |
  | 4 | 129.5 s | baseline | 1,672 MB | 3,364 MB |
  | 6 | 122.9 s | 1.05x | 2,464 MB | 2,395 MB |
  | 8 | 117.2 s | 1.11x | 3,296 MB | 1,652 MB |

  The eight-process cap was reached and sustained for 31 one-second samples; the count then tapered as the queue drained (10 samples at 7, 9 at 6, and so on). This is expected pool behavior, not even CPU allocation: the runner fills available slots, advances each map through its compiler stages, then launches queued work as slots free. Windows schedules CPU time dynamically; the pool neither pins processes to cores nor gives each process an equal CPU share. Pool 8 works for this workload, but its 12.3-second gain over pool 4 came with about 1.6 GB more peak compiler memory and a minimum available-memory reading of 1.65 GB. Keep the default at 4; consider 6/8 only as explicit machine-specific overrides and validate memory headroom during a full preview build.

## Completion Notes
- `.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337` completed and emitted `[WorldGen]` diagnostics for all generation/export phases.
- PowerShell parser checks passed for the modified scripts; `generator-settings.json` parsed successfully.
- The full current seed-1337 preview plan was refreshed and all 170 required city/den maps completed VBSP/VVIS/VRAD with the `fast` preset and pool size 4 in 862 seconds (14m 22s). The pool reached four concurrent processes; peak compiler working set was 1,786 MB and minimum available system memory was 3,336 MB. The build had zero failed/incomplete maps, missing BSP/portal outputs, or non-empty compiler stderr logs; all maps passed the 750-cluster / 1,350-portal audit. See [Alpha 2.9 tracker](../todo-alpha-2.9.md) and the isolated [compile report](../generated/build_preview_full_20261001/compile-report.json).
- No maps or materials were staged to `content/`, and no production `city` build or live in-game verification was run.
- Alpha 2.9's pending live-client and full preview acceptance checks remain governed by [todo-alpha-2.9.md](../todo-alpha-2.9.md); this tooling milestone does not close them.
