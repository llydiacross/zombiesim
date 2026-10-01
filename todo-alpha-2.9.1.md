# Todo Alpha 2.9.1

## Goals & Objectives
- Introduce multi-process map compiling to the build steps to cut compile times drastically across multi-core systems.
- Take advantage of Hammer compiler arguments (such as `-fast` for VVIS/VRAD on preview builds, and `-final`/`-staticproplighting` on final builds).
- Introduce detailed step-by-step console logging in the world generation pipeline (`generate_world_cells.ps1`).
- Increase portal budget constraints to 1.5x the current baseline values (clusters: 500 -> 750, portals: 900 -> 1350).
- Relocate all test Lua files from the `gamemode/` root into a clean `gamemode/tests/` subdirectory and update includes.

---

## Detailed Implementation Plan

### Phase 1: Portal Budget Constraint Adjustment (1.5x)
- [ ] **Update settings schema:** In [generator-settings.json](generator-settings.json), increase `compilation.visibilityBudget.maxPortalClusters` from `500` to `750` and `maxPortals` from `900` to `1350`.
- [ ] **Update script defaults:** In [bin/check_vis_budgets.ps1](bin/check_vis_budgets.ps1), update default fallback values to `750` and `1350`.
- [ ] **Documentation:** Update [docs.md](docs.md) visibility budget section to record the updated 750 cluster / 1,350 portal budget limits.

### Phase 2: Relocate Test Files to Dedicated `gamemode/tests/` Directory
- [ ] **Directory structure:** Create `gamemode/tests/`.
- [ ] **Move test suites:** Move all 14 `sv_*_tests.lua` suites from `gamemode/` to `gamemode/tests/`:
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
- [ ] **Update includes in [gamemode/init.lua](gamemode/init.lua):** Change all `include("sv_*_tests.lua")` statements to `include("tests/sv_*_tests.lua")`.
- [ ] **Static verification:** Run `.\bin\test_glua_syntax.ps1` to ensure all 125+ files parse cleanly without syntax or path issues.

### Phase 3: Comprehensive Console Logging for World Generation
- [ ] **Script:** [bin/generate_world_cells.ps1](bin/generate_world_cells.ps1).
- [ ] Add structured, informative console messages at every key algorithmic phase:
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
- [ ] **Settings schema in [generator-settings.json](generator-settings.json):**
  - Add preset argument definitions under `compilation.stagePresets`:
    - `fast`:
      - `vvis`: `["-game", "{gameDirectory}", "-fast", "{mapBsp}"]`
      - `vrad`: `["-game", "{gameDirectory}", "-fast", "{mapBsp}"]`
    - `final`:
      - `vvis`: `["-game", "{gameDirectory}", "{mapBsp}"]`
      - `vrad`: `["-game", "{gameDirectory}", "-final", "-staticproplighting", "-staticproppolys", "{mapBsp}"]`
- [ ] **Parameters in [bin/compile_cell_vmfs.ps1](bin/compile_cell_vmfs.ps1) & [bin/build_city.ps1](bin/build_city.ps1):**
  - Add `[switch]$Fast` and `[switch]$Final` switches.
  - Automatically default to `fast` when `-WorldProfile preview` is active, unless `-Final` is explicitly supplied.
  - Default production (`city`) builds to `final`.

### Phase 5: Multi-Process Parallel Map Compiling Pool
- [ ] **Configuration:** Add `compilation.maxParallelProcesses` to [generator-settings.json](generator-settings.json) (default: `[Math]::Max(1, [int]([Environment]::ProcessorCount / 2))` or 4).
- [ ] **Parallel runner in [bin/compile_cell_vmfs.ps1](bin/compile_cell_vmfs.ps1):**
  - Replace the monolithic single-map sequential loop with a process pool queue using `[System.Diagnostics.Process]` (PowerShell 5.1 compliant).
  - Manage a list of active compile slots up to `$MaxParallelProcesses`.
  - Track per-slot state: `MapName`, `CurrentStage` (`vbsp` -> `vvis` -> `vrad`), `Process`, `Stopwatch`, and log paths.
  - While work remains in queue or slots are active:
    - Poll running processes every `$progressRefreshMilliseconds`.
    - If a process finishes with exit code 0, advance that map to its next stage (`vvis` or `vrad`).
    - If a process finishes its last stage (or fails), finalize the map record and assign the next map from the queue to the free slot.
    - Monitor timeouts per active process slot.
  - Throttle internal tool threads by passing `-threads` to prevent CPU oversubscription.
- [ ] **Verification:** Validate parallel compilation on a test subset of preview maps and compare total wall-clock time against sequential execution.
