# Z-Nation

Please read the [GDD](docs/gdd.md) for an overview of the game's design and mechanics.

Work in progress

# Folder Structure

- `tiletemplates/` and `celltemplates/` contain authored VMFs, including launcher sources in `celltemplates/launchers`.
- `content/` contains distributable addon data read by Garry's Mod, including flat `content/maps` BSPs, thumbnails, materials, and runtime world indexes.
- `generated/` contains compiler artifacts, reports, intermediate BSPs, developer zoos, and launcher build output under `generated/launcher_build`.

These are compiled reusable recipe maps for the city. A recipe can serve more than one logical city cell, so its filename does not identify a coordinate.

`content/data_static/zombiesim_world.json` maps every cell coordinate to its selected recipe BSP and provides the navigation graph and gameplay metadata. Build a transition map name from `world.mapDirectory .. "/" .. cell.map`; it is the authoritative lookup for map transitions.

Generated recipe BSPs use compact `zz_<profile>_<hash>` basenames, for example `zz_city_5b87e00b9082-v1.bsp`. Runtime staging is flat under `content/maps` and engine maps; launcher maps retain `zn_city_start` and `zn_preview_start`.

# Powershell Commands

Run these from the project root. The preview profile is isolated from production and stages its playable maps flat under `content/maps`.

Generate the deterministic preview world image, manifest, and map layers:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
```

Plan its recipes and write the required-map list:

```powershell
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
```

Refresh the generated recipe VMFs, prune obsolete generated files, and verify every required recipe exists:

```powershell
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview
```

Generate Hammer-only template zoos in `celltemplates/dev`. `-RefreshPlan` first replans the preview so `streets.vmf` and `carparks.vmf` reflect current placement rules; `landmarks.vmf` lists every template matched by `cellPlanning.landmarkTemplatePatterns` in `generator-settings.json` and automatically includes future configured landmark templates:

```powershell
.\bin\build_tile_zoos.ps1 -RefreshPlan
```

Create or refresh portal files for every required city recipe and standalone den map, then report portal and cluster budget violations. Valid current portal data is reused; only missing, invalid, or source-stale maps run through VBSP. This must run first when using `-PrioritizePortalCost`; add `-ForcePortalData` for a full portal rebuild:

```powershell
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

Render and stage a finished preview from existing validated BSPs. It runs the largest portal workloads first and skips VVIS/VRAD stages that already completed; add `-Force` for a clean rerun of both stages:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity -VvisTimeoutSeconds 1800 -VradTimeoutSeconds 3600
```

Run a complete clean preview build, including fresh BSPs, visibility, lighting, and staging:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -Force  -CleanStagedCity -VvisTimeoutSeconds 1800 -VradTimeoutSeconds 3600
```

## Export To Garry's Mod

This workspace is already installed inside Garry's Mod under `garrysmod/gamemodes/zombiesim`. The export commands stage the selected compiled BSPs, generated map materials, and matching runtime-world JSON into this gamemode's `content` directory. Use the profile-wide command instead of copying individual BSPs so map files, satellite materials, and runtime references stay synchronized.

Export an already compiled preview without running VBSP, VVIS, or VRAD again:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipCompile -CleanStagedCity
```

This copies the selected preview BSPs from `generated/build_preview` to flat `content/maps`, stages generated world layers in `content/materials/worlds/preview/map_layers`, renders local recipe maps in `content/materials/worlds/preview/cells`, rebuilds `satellite.png`, and writes `content/data_static/zombiesim_world_preview.json`. `-CleanStagedCity` removes stale BSPs from the selected profile's staging area while preserving other profiles.

Stage existing engine-generated navmeshes for the same profile without requiring a BSP rebuild:

```powershell
.\bin\stage_world_navmeshes.ps1 -WorldProfile preview -CleanStagedCity
```

This copies matching `.nav` files from `garrysmod/maps` into `content/maps`. It does not modify the engine's runtime navmesh files.

After rebuilding recipe BSPs, clear the profile's old navmeshes before generating fresh ones in Garry's Mod:

```powershell
.\bin\clear_world_navmeshes.ps1 -WorldProfile preview
```

This removes both engine runtime navmeshes from `garrysmod/maps` and their staged copies. Reload `zn_preview_start`, run `zombiesim_generate_navmeshes`, then rebuild `wireframe.png` after the batch completes.

Export an already compiled production city with the same process:

```powershell
.\bin\build_city.ps1 -WorldProfile city -OnlyRequiredMaps -SkipRecipeRefresh -SkipCompile -CleanStagedCity
```

The production outputs are flat BSPs in `content/maps`, profile materials in `content/materials/worlds/city`, and `content/data_static/zombiesim_world.json`.

To refresh only generated map materials after a visual renderer change, while keeping existing BSPs and runtime data, run:

```powershell
.\bin\stage_world_map_materials.ps1 -WorldProfile preview
.\bin\build_cell_map_materials.ps1 -WorldProfile preview
.\bin\build_world_satellite_material.ps1 -WorldProfile preview
```

When the map manifest or template plan has changed, also refresh the matching runtime index after the required BSPs exist:

```powershell
.\bin\export_runtime_world_data.ps1 -WorldProfile preview -RequireCompiledMaps
```

After staging, reload the `zn_preview_start` launcher map for the preview profile or `zn_city_start` for the city profile so Garry's Mod loads the matching staged world index.

Build cubemaps for every unique recipe and safe-zone map in the loaded world profile. Run this from the in-game server console or as an admin; it changes level to the first map and prints the native command to run:

```
zombiesim_build_cubemaps
```

Generate navmeshes for the same map queue:

```
zombiesim_generate_navmeshes
```

The navmesh batch automatically generates and saves navigation data only for ordinary city-cell maps that do not already have a `.nav` file in the active profile. Existing navmeshes are skipped. Clear the profile navmeshes after a BSP rebuild to force a fresh full pass. To generate one missing map first, pass its basename or profile-relative name:

```
zombiesim_generate_navmeshes <mapName>
```

Wireframe materials read existing Source navmesh files directly from `garrysmod/maps`; no map transitions are needed to render them. When rendering preview, a city navmesh is reused only when its deterministic recipe hash matches the preview recipe exactly; cells without a matching generated navmesh remain marked unavailable:

```powershell
.\bin\build_world_wireframe_material.ps1 -WorldProfile preview
```

Use `zombiesim_navmesh_status` to inspect the loaded map, matching nav file, and nav-area count. Use `zombiesim_map_batch_status` for queue progress, `zombiesim_map_batch_retry` after a failed map, or `zombiesim_map_batch_cancel` to stop. For each cubemap map, run `buildcubemaps` in your console; after its reload, run `zombiesim_map_batch_next` to load the next map.

# In-Game Commands

Run this from an in-game admin console to reset your attributes, progression, health, stamina, and location, then return to the active world's origin den:

```
zombiesim_reset_player
```

Run this from an in-game admin console to print your saved raw grid cell, logical world coordinate, safe-zone id, and map resolution:

```
zombiesim_player_status
```

## Development Command Bridge

For local development, edit [content/data_static/consolecommands.txt](content/data_static/consolecommands.txt). Give every request a new `# request:` identifier and place one server-console command on each uncommented line. The bridge polls the mounted file and executes each identifier once, including across map changes. It is enabled by default only for non-dedicated servers; toggle `zombiesim_dev_console_enabled` to control it.

The bridge writes an acknowledgement and any structured diagnostic data to `garrysmod/data/zombiesim/consolecommands.result.json`. This location is the GMod `DATA` mount, so it is intentionally outside the gamemode source tree. Ordinary engine-console output remains in the game console; use the structured persistence probe for automation:

```
zombiesim_dev_persistence_report STEAM_0:1:31630
```

That report includes the raw `city` and `preview` player/attribute rows, active map and profile, actual live health, resolved world-cell id, safe-zone status, radiation intensity, elapsed exposure time, time until the next radiation tick, and the current Strength-based health floor. Radiation below 75% intensity deals 1 damage every 120 seconds; intensity at or above 75% deals 2 damage every 60 seconds. Radiation cannot reduce health below 64 at Strength 0-4, 72 at Strength 5-9, or 80 at Strength 10+. Leaving radiation or changing cells resets the interval.

Two preview-only bridge commands require an active admin preview session: `zombiesim_preview_refill` restores health and survival reserves; `zombiesim_preview_restore` also moves the player to the origin safe room and respawns them if needed.

## Local Development Session

Use the scripts below from the repository root to start a local ZombieSim session through Steam with the game console, `console.log`, and Source server logs enabled:

```powershell
.\bin\start_zombiesim_dev.ps1 -WorldProfile preview
.\bin\read_zombiesim_dev_log.ps1 -Lines 200
.\bin\send_zombiesim_dev_command.ps1 zombiesim_walker_status
.\bin\stop_zombiesim_dev.ps1
```

`send_zombiesim_dev_command.ps1` overwrites the bridge input with a fresh request id, as required by `sv_dev_console.lua`. Use `read_zombiesim_dev_log.ps1 -Console` for the `-condebug` capture, or add `-Follow` when manually observing an active session. `stop_zombiesim_dev.ps1` closes the local `gmod.exe` window first so the server can run normal shutdown hooks; use `-Force` only when it cannot exit gracefully.

Validate every loaded gamemode and utility Lua file with Garry's Mod's native GLua parser without executing the files:

```
zombiesim_validate_scripts
```

When invoked through the bridge, `consolecommands.result.json` includes `reports.scriptValidation` with the checked, passed, and failed counts plus one result for each source file. Syntax failures are also printed in the server console with their mounted `GAME` path.

For an offline syntax check without launching the game, run `.\bin\test_glua_syntax.ps1`. It uses the `gluac.exe` bundled with the GLua Enhanced VS Code extension and exits with code 1 on any failure.

# Mounted Garry's Mod Assets

Garry's Mod content is often stored in Valve VPK archives rather than as loose files. The default Steam install keeps the game under `steamapps\common\GarrysMod`; its main shared archive is `garrysmod\garrysmod_dir.vpk`, and the VPK listing tool is `bin\vpk.exe`. Other VPKs, enabled addons, and mounted games may provide additional assets, so the main archive is not an exhaustive list of everything available at runtime.

Use the installed VPK tool to search an archive without extracting copyrighted game content:

```powershell
$gmodRoot = 'C:\Program Files (x86)\Steam\steamapps\common\GarrysMod'
$archive = Join-Path $gmodRoot 'garrysmod\garrysmod_dir.vpk'
$vpk = Join-Path $gmodRoot 'bin\vpk.exe'
& $vpk l $archive | Select-String -SimpleMatch 'models/weapons/cstrike/c_pist_usp.mdl'
```

Replace `$gmodRoot` if Steam is installed in a different library. To audit beyond the main archive, enumerate the VPKs under the installed game/addon and mounted-game locations and run `vpk.exe l` on each candidate archive. VPK paths are virtual asset paths: reference mounted model/material paths in item definitions rather than copying extracted Valve assets into the addon. Before using a candidate at runtime, verify it with `util.IsValidModel` (or the matching material/sound check) in Garry's Mod and visually check its suitability.

Garry's Mod ships its own copies of Half-Life 2 and Counter-Strike: Source content under `GarrysMod\sourceengine`, so these are mounted even without the separate games installed. Most prop and item models are there, not in `garrysmod_dir.vpk`:

| Archive | Examples |
| --- | --- |
| `sourceengine\hl2_misc_dir.vpk` | HL2 items and props: `models/items/boxsrounds.mdl`, `boxmrounds.mdl`, `boxbuckshot.mdl`, `boxsniperrounds.mdl`, `healthkit.mdl`, `models/props_junk/*`, `models/props_interiors/vendingmachinesoda01a.mdl` |
| `sourceengine\content_hl2_dir.vpk` | Further HL2 content, such as `models/items/ammocrate_pistol.mdl` |
| `sourceengine\content_cstrike_dir.vpk` | CSS props: `models/props/cs_assault/money.mdl`, `models/props/de_prodigy/ammo_can_01.mdl` |
| `garrysmod\garrysmod_dir.vpk` | Garry's Mod content, including CSS weapon view/world models under `models/weapons/` |

```powershell
Get-ChildItem -LiteralPath $gmodRoot -Recurse -Filter '*_dir.vpk' | Select-Object -ExpandProperty FullName
& $vpk l (Join-Path $gmodRoot 'sourceengine\hl2_misc_dir.vpk') | Select-String -Pattern '^models/items/.*\.mdl$'
```

For bulk item and world-loot work, use the VPK listing to build a metadata-only candidate catalog, then curate item semantics and stable IDs. Map authored loot-container classes/models to explicit loot groups in `content/data_static/entity_loot.json`; for example, vending machines should favor drinks, while military/ammo containers should favor weapons and ammunition. Do not infer loot solely from a generic prop class or make unknown props produce generic loot. See Phase K in `todo-alpha-2.8.md` for the planned cataloging and validation pipeline.

Regenerate and validate the metadata-only candidate catalog without extracting any archive content:

```powershell
.\bin\build_mounted_asset_catalog.ps1
.\bin\test_mounted_asset_catalog.ps1
```

The catalog is written to `generated/asset_catalog/mounted_asset_catalog.json`. The builder lists `*_dir.vpk` archives under the installed `garrysmod` and `sourceengine` trees and paths configured in `garrysmod/cfg/mount.cfg`; disabled addon archives are reported as unmounted. It retains one canonical record per virtual model path, its source archive(s), family/tags, mounted status, and whether an authored item uses it as an icon or world model. Item and loot data remain curated in `content/data_static/`; catalog output and reports are generated artifacts.

# Static Data (Items, Loot, Enemies, Bosses, Economy)

`ZM_StaticData` loads these files from `content/data_static/` in both realms. A load that has any error keeps the previous registry.

| File | Contents | Documented in |
| --- | --- | --- |
| `item_definitions.json` | Items: weapons (SWEP class, CSS models, ammo, firing mode), ammo, food, materials, medical, implants | [Inventory](#inventory), [Food](#food), [Implants](#implants) |
| `loot.json`, `entity_loot.json` | Loot groups and container-to-group rules | [Loot Rolls](#loot-rolls), [World Loot Spots](#world-loot-spots) |
| `enemy_definitions.json`, `enemy_spawns.json`, `boss_spawns.json` | Enemies, spawn groups, bosses | [Enemies](#enemies) |
| `recipe_definitions.json` | Den crafting recipes and profession research services | [Crafting](#crafting), [Professions](#professions) |
| `profession_definitions.json` | Jobs, stat bonuses, daily deliveries, services | [Professions](#professions) |
| `den_service_definitions.json` | Mastercraft and job-change credit prices | [Credits and Mastercrafting](#credits-and-mastercrafting) |
| `trade_definitions.json` | Trader tables, multipliers, limits, NPC fees, essential ammo | [Den Trading and NPCs](#den-trading-and-npcs) |

The authoritative field bounds are the validators in `gamemode/sh_static_data.lua`; `tests/static_data/` holds one malformed fixture per file with the errors each must produce. Admin/server commands:

```
zn_validate_static [file ...]   // validate the files on disk; the live registry is unchanged
zn_validate_loot                // validate loot.json and entity_loot.json only
zn_reload_static                // reload and, on success, tell clients to reload
zn_test_static_data             // run the fixture tests in tests/static_data/cases.json
zn_test_weapon_catalog          // check local SWEP/model/item mappings at runtime
```

`zn_validate_static`, `zn_reload_static`, `zn_test_static_data`, and `zn_test_weapon_catalog` run synchronously through the development bridge and add structured reports to `consolecommands.result.json`. Warnings for missing SWEPs, icon models, models, or entity classes never block a load.

## Automated Test Suites

Each gameplay service has a server-side suite that uses throwaway SteamIDs and profiles and removes every row it writes. Run them from an admin console or through the bridge; each writes `garrysmod/data/zombiesim/<name>_tests.json` and a bridge report, and a bridge command fails when any case fails:

```
zn_test_static_data zn_test_weapon_catalog zn_test_inventory zn_test_loot zn_test_loot_spots zn_test_enemies
zn_test_bosses zn_test_crafting zn_test_implants zn_test_professions zn_test_mastercraft zn_test_trading
```

New suites use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`): `NewSuite()`, `suite:Add(name, function(check) ... end)`, `suite:Run({ before, after })`, and `ZM_TestHarness.Register({ command, label, file, report, help, run })`. Shared server helpers for command runners (first human, profile, whole-number checks, replies, admin gates, command registration) are in `ZM_Util` (`gamemode/utils/server.lua`).

## Item Icons

Inventory tiles and loot offers render each item's mounted model as a Garry's Mod spawn icon (the engine `ModelImage` panel that `SpawnIcon` uses, which generates and caches `materials/spawnicons/...` on first view). The icon model resolves in this order:

1. `iconModel` in the item definition, for non-weapon items or when the world model is a poor icon.
2. `worldModel` for explicitly mapped weapons.
3. `models/props_junk/cardboard_box004a.mdl` as a generic fallback.

An authored `materials/items/<thumbnail>.png` is an optional override and takes precedence when present; it is no longer required, so a missing PNG does not warn. Runtime validation instead warns when an icon model is not mounted. Pick icon models from the mounted archives (for example HL2 ammunition boxes such as `models/items/boxsrounds.mdl` in `sourceengine\hl2_misc_dir.vpk`, or CSS props such as `models/props/cs_assault/money.mdl` in `sourceengine\content_cstrike_dir.vpk`) using the VPK listing workflow under Mounted Garry's Mod Assets.

# Inventory

Each player has a 20-slot backpack and a 60-slot den stash, stored per profile in the `player_items` SQLite table. The backpack is lost on death; the stash can only be changed inside the player's current den. Admin commands (from the server console or bridge they act on the first connected player):

```
zn_inventory                                              // print backpack and stash
zn_give_item <itemId> [count] [level] [mastercraft 0/1]   // add to the backpack
zn_remove_item <itemId> [count] [container]
zn_move_item <instanceId> <backpack|stash> [slot] [count]
zn_test_inventory                                         // operation and persistence tests (throwaway SteamID/profile)
zn_ammo_status                                            // live, persisted, and reserve rounds for equipped firearms
```

Through the bridge these add `reports.inventory` or `reports.inventoryTests`. The bridge-only `zombiesim_dev_kill_player` kills the first player for death-path tests, because the engine blocks `lua_run` sent through `game.ConsoleCommand`.

Firearm reserve ammunition is stored as stackable backpack items (`ammo9mm`, `ammo556`, `ammo762`, `ammoShells`, and `ammo50Bmg`). A weapon instance stores its loaded `clip`; firing changes only the live server-owned SWEP clip, while reload atomically removes the weapon's mapped reserve item and persists the resulting clip. Weapon switches, player saves, map transitions, disconnects, and orderly shutdown synchronize live clips instead of writing SQLite for every shot. New firearms start empty, mismatched ammunition cannot reload them, and an interrupted reload consumes nothing.

For bridge-driven live checks, `zombiesim_dev_reload_active` starts the active firearm's normal timed reload and `zombiesim_dev_fire_active` fires one round. `zombiesim_dev_test_weapon_round <instanceId|itemId>` performs a server-side one-round/cadence probe on an equipped firearm and writes `reports.ammoRuntime`. `zombiesim_dev_equip_ammo_test_weapon <instanceId|itemId>` is a preview-development helper for equipping a level-gated test weapon without changing the player's persisted level.

## Food

An `entity` item becomes food by adding a `food` block: `{ "tier": 0-5, "preparation": "raw|preserved|cooked", "shelfLifeHours": n, "effects": { "nutrition", "hydration", "health", "stamina" } }`. `ZM_StaticData.FoodTiers` bounds every effect and shelf life per tier (tier 0 is already spoiled and has no shelf life; higher tiers give more and last longer), and each food needs at least one positive effect. `ZM_Food` (`sh_food.lua`) owns all freshness rules:

- Freshness is derived from the instance `createdAt` timestamp and wall-clock time, so it keeps decaying while offline or in the stash; moving, saving, loading, and depositing do not reset it.
- Bands: fresh above 50% of shelf life (full effects), stale above 0% (60%), spoiled (25% plus a 10 health penalty).
- Food only stacks within the same band; a merged stack keeps the oldest timestamp.
- Using food applies bounded effects once, after the removal is persisted; a failed save restores the item and grants nothing. Eating is refused when it would not restore at least one point.

Inventory tooltips show the tier, preparation, band, time until the next band, and per-unit effects; a coloured corner marker on the tile shows the band.

## Crafting

Recipes live in `content/data_static/recipe_definitions.json` (`schemaVersion`, integer `recipeVersion`, `recipes`). Each recipe id is `recipe<CamelCase>` and has `name`, `category` (Food/Medical/Ammunition/Materials/Weapons), `station` (a tag in `ZM_StaticData.CraftingStations`; only `workbench` → `zn_crafting_station` exists), `craftTime` (0.5–600 s per batch), optional `levelRequirement`, `statRequirements` (player attributes), and `jobs`, plus 1–8 `ingredients` and 1–4 `results` as `{ "item", "count" }`. Weapons cannot be ingredients, weapon results have count 1, mastercraft results are rejected (mastercrafts come from the Mastercrafting Station), and a result cannot also be an ingredient. Recipes that produce food need `freshness`: `new` (fresh now) or `inherit` (the count-weighted freshness of the consumed food ingredients). An invalid reload keeps the last good registry.

`ZM_CraftingService` (`sv_crafting.lua`) owns all crafting. The client sends only a recipe id and batch count (1–10); the server requires the player to be alive, inside their den, and within 128 units of a matching station, and checks requirements and ingredients for every batch. One job runs per player. Each batch re-checks the ingredients when it completes and swaps them for the results in a single saved mutation (backpack and stash written in one SQL transaction), taking from the backpack before the stash and oldest items first, and placing results in the backpack and then the stash. A failed save, missing ingredient, or full inventory stops the job without changing anything. Leaving the den or station range, dying, disconnecting, the station being removed, losing a requirement, or the recipe changing interrupts the job; finished batches are kept and the unfinished batch costs nothing.

```
zn_crafting                     // recipe eligibility, active job, stations, and inventory rows
zn_craft <recipeId> [count]     // start a job at a nearby station in the den
zn_craft_cancel                 // cancel the active job
zn_dev_craft_finish             // development: finish the current batch now
zn_dev_goto_station             // development: stand at the nearest workbench, or spawn a temporary one
zn_test_crafting                // crafting service tests
```

Through the bridge these add `reports.crafting` and `reports.craftingTests`. Den maps do not place a `zn_crafting_station` yet; it is spawnable from the entity menu, and `zn_dev_goto_station` spawns a frozen temporary one.

All recipes use the workbench for now. Separate stations (for example ammunition at its own bench and food at a cooker) are planned.

## Professions

Professions live in `content/data_static/profession_definitions.json` (`professionVersion`, `professions`). Each PascalCase id has a `name`, a `description`, optional `aliases`, `statBonuses` (at most 5 per attribute and 6 in total), `services` (`cook`, `treat`, `research`, `implant`, `extract`), and `deliveries`: level bands that start at `minLevel` 1 and ascend, each listing up to 8 `{ "item", "min", "max" }` entries (no weapons). `Civilian` is the default, with no bonuses, services, or deliveries. `ZM_Professions` (`sh_professions.lua`) resolves ids and aliases. `ply:GetStat` returns the stored stat plus the profession bonus; the bonus is never saved.

`ZM_ProfessionService` (`sv_professions.lua`) handles:

- **Daily deliveries.** The day is the server's UTC date. The first time a player with a delivery table is in their den each day, they receive the band for their level. Counts are deterministic per player, profile, and day, so a retry gives the same items. A claim row keyed by profile and day is written in the same SQL transaction as the items. Map changes, reconnects, and job changes therefore never grant a second delivery. Missed days are not made up. If the delivery does not fit (backpack first, then stash), it is refused, retried every 60 s, and the player is told once per day.
- **Services.** Services work between two players in the den within 160 units, or on yourself. The customer supplies the items and pays a whole-number cash fee; self-service is free and has no prompt. For another player, the provider gets a 60-second offer to accept or decline.
  - `cook` (Chef, Hunter) turns 1–10 unspoiled raw food with `cooksInto` into the cooked item, keeping its freshness.
  - `treat` (Doctor) uses one medical item from the customer's backpack. A Doctor heals 50% more.
  - `research` (Scientist) makes a service recipe (`"service": true`, no station) from the customer's ingredients. The workbench refuses service recipes.
  - The provider's level caps the level of the items they can work.
  - The items, results, and both cash changes are saved in one transaction, so a failure changes nothing.

Items with a `medical` block (`health` 1–100) are used as `MedicalItem`, and raw food may name a cooked `cooksInto` target of the same or a higher tier.

```
zn_profession                             // job, bonuses, services, today's claim, and pending offers
zn_services                               // client: open the services window (also a button in the crafting window)
zn_service <kind> <ref> [count] [fee|-] [provider]  // request a service; provider = userId, n:<entIndex>, or npc (default: yourself; - = the NPC's fee)
zn_service_respond <offerId> <1|0>        // accept or decline an offer
zn_set_job <professionId>                 // admin: set a job (ids or aliases such as Medic, Soldier, Police)
zn_claim_delivery                         // admin: claim today's delivery now
zn_dev_advance_day [days]                 // development: shift the claim day (0 resets)
zn_dev_reset_claims                       // development: delete the caller's claim rows
zn_dev_set_health <hp>                    // development: set health for treat tests
zn_test_professions                       // profession service tests
```

Through the bridge these add `reports.professions` and `reports.professionTests`.

## Implants

An implant is a generic item (`maxStack` 1) with an `implant` block: a `slot` (`Neural`, `Ocular`, or `Dermal`) and `effects`, each `[valueAtMinLevel, valueAtMaxLevel]`. The instance level picks a value between the two. Effects and their limits are listed in `ZM_StaticData.ImplantEffects`:

| Effect | Per implant | Total cap |
|---|---|---|
| `lootWeapons`, `lootAmmo`, `lootMedical`, `lootFood`, `lootCash`, `lootMaterials` | 0.5 | 0.75 |
| `xpGain` | 0.3 | 0.5 |
| `moveSpeed` | 0.15 | 0.2 |
| `healthRegen` (HP/min) | 6 | 10 |

A Doctor installs an implant from the customer's backpack (`implant` service) and removes one by slot (`extract` service). Both follow the usual service rules: in the den, the customer pays the fee, and the provider's level must be at least the implant's level. An implant already in the slot, or one that is extracted, goes back to the backpack. Installed implants are saved per profile in `player_implants`, survive death, and are cleared by a character reset. The Services window lists the slots and the combined (capped) effects.

Loot bonuses multiply the weights of entries whose item `lootCategory` matches. They apply to your loot-spot searches and to drops from enemies you kill, but not to boss loot, activation chance, drop chance, or counts. Every item has a `lootCategory`, derived from its definition unless it sets one: weapons, ammo, medical, food, cash, materials, implants, or other. Implants are never boosted.

```
zn_service implant <itemId|instanceId>   // install (as a Doctor, or with a Doctor's providerUserId)
zn_service extract <Neural|Ocular|Dermal> // remove into the backpack
zn_implants                              // installed implants, capped effects, speed, and loot bonuses
zn_dev_clear_implants                    // development: delete installed implants (items are not returned)
zn_test_implants                         // implant tests
```

Through the bridge these add `reports.implants` and `reports.implantTests`.

## Credits and Mastercrafting

Credits are a whole-number currency separate from cash, from 0 to 1,000,000 per profile. They are stored in `player_credits`, and every change writes a `credit_ledger` row (delta, balance, reason, reference) in the same transaction. Credits survive death and a character reset. In Alpha 2.8 they come only from admin grants; there are no purchases.

The Mastercrafting Station (`zn_mastercraft_station`) works only inside a den, within 128 units. Prices are in `content/data_static/den_service_definitions.json`:

- **Mastercraft:** `baseCredits + ceil(level x creditsPerLevel)` (shipped: 5 + 0.5 per level). It upgrades an ordinary weapon in your backpack in place, keeping its instance and level. The weapon becomes a mastercraft and its attributes are re-rolled, each within one point of the maximum. With `ultraChance` (shipped 1%), every attribute is at the maximum: an **Ultra Mastercraft**, worth 5x instead of 3x and shown as "(Ultra MC)". The credits are spent whatever the roll. Each weapon gets one attempt, recorded in `mastercraft_attempts`.
- **Job change:** `jobChange.credits` (shipped 25) sets a different profession.

The client asks for a quote. The server returns the price under a single-use token that lasts 60 s. Confirming spends the token even if it fails (a confirmation with the wrong token also discards the pending quote), and re-checks the weapon, station, balance, and price. The item, the credits, and the attempt record are saved in one transaction. Skill-point resets and appearance changes are deferred: no spending or appearance API exists yet.

```
zn_credits                                   // balance and the last ten ledger entries
zn_grant_credits <amount> [reason]           // admin: add credits (negative removes)
zn_dev_reset_credits                         // development: delete this profile's credits, ledger, and attempts
zn_mastercraft                               // station state: credits, weapons and costs, pending quote
zn_station_quote <mastercraft|job> <ref>     // admin: quote a weapon (instanceId or itemId) or a job
zn_station_confirm <quoteId|current> [seed]  // admin: spend the quote; the seed makes the roll repeatable
zn_dev_goto_mastercraft                      // development: spawn a temporary station in front of you
zn_test_mastercraft                          // credit, quote, mastercraft, and job change tests
```

Through the bridge these add `reports.credits`, `reports.mastercraft`, and `reports.mastercraftTests`.

## Den Trading and NPCs

Den NPCs are `zn_den_npc` point entities placed in a den's VMF in Hammer (`zombiesim.fgd`). Their keyvalues are `npc_name`, `profession` (a profession id or alias; empty for none), `service_level` (1–300, the level cap for the items they work), `fees` (for example `cook=5 treat=10`), `trader` (`general`, `quartermaster`, `clinic`, or empty), and `model`. An NPC can be a trader, a professional, or both. Settings are resolved against the live static data; a rejected setting is logged, and an NPC without a valid profession offers no services. Pressing E opens the trading window (with a Services button when the NPC also has a profession) or the Services window.

- **NPC professionals** appear in the Services window next to players. They accept at once, work at their `service_level`, and charge a fixed cash fee (the `fees` keyvalue, else `npcServiceFees` in `trade_definitions.json`). The fee is taken from the customer in the same transaction as the items and credited to no one. All normal service rules apply: in the den, within 160 units, the customer supplies the items.
- **Trading** uses `content/data_static/trade_definitions.json` (`tradeVersion`). Each trader table lists the loot categories it `buys` and its `offers` (`item`, `bundle`, `minStock`–`maxStock`, `minDanger`–`maxDanger`, optional `mastercraft` and `credits`). A trader with `essentialAmmo` always stocks the common ammunition (shipped: 10 × 30 rounds of 9mm, shells, 5.56, and 7.62).
  - **Stock** is shared by everyone in the den and resets at midnight UTC. It is rolled deterministically from the profile, den, trader, day, and offer; only units sold are stored (`trade_stock`).
  - **Danger:** the den's danger is its entrance cell's. Offers outside their danger range are hidden, and weapon levels rise with danger (up to halfway through their level range). The window shows the danger tier: Safe, Guarded, Dangerous, or Deadly.
  - **Prices:** ordinary goods cost `ceil(value × 1.5)` cash; mastercraft weapons and implants cost a fixed number of credits. Traders pay `floor(value × 0.4)` cash for backpack items in categories they buy, up to 2,500 cash per player per day. Equipped weapons, spoiled food, cash, and implants cannot be sold. Purchases go to the backpack; if they do not fit, nothing is bought.
  - **Atomicity:** a buy or sell saves the items, the cash or credits, the stock, and a `trade_ledger` row in one transaction. Each request carries a unique id, so a replay fails. The server rebuilds the offer and refuses a stale day, price, currency, or stock count.

```
zn_den_npcs                                    // NPCs on this map with their resolved settings and problems
zn_trade [entIndex]                            // the nearest trader's offers, stock, prices, and today's sales
zn_trade_buy <offerKey> [units] [requestId]    // admin: buy (offer keys are 1, 2, ... or ammo:<itemId>)
zn_trade_sell <instanceId|itemId> [count] [requestId]  // admin: sell from the backpack
zn_trade_window                                // client: open the trading window for the nearest trader
zn_dev_spawn_den_npc <profession|none> [level] [trader|-] [sideOffset] [fees]  // development: temporary NPC
zn_dev_clear_den_npcs                          // development: remove temporary NPCs
zn_dev_trade_danger <0..1|off>                 // development: override the den danger
zn_dev_reset_trade                             // development: delete your trade ledger and this profile's stock
zn_test_trading                                // trading and den NPC tests
```

Through the bridge these add `reports.denNpcs`, `reports.trade`, and `reports.tradingTests`.
# Loot Rolls

`ZM_Loot` (server) rolls items from the resolved loot groups, entity-loot rules, enemies, and bosses. Weights interpolate linearly from `minWeight` (danger 0) to `maxWeight` (danger 1); `activationChance` and the enemy loot-drop chances are probabilities, not weights.

```
zn_test_loot_roll <group> <danger 0-1> [samples] [seed]   // expected vs observed shares, average count, mastercraft rate
zn_give_loot <group> [danger]                             // roll for the player and add it to the backpack
zn_test_loot                                              // loot engine tests
```

Through the bridge these add `reports.lootRoll`, `reports.lootGrant`, and `reports.lootTests`.

# Enemies

`ZM_Enemies` (server) picks the enemy type for each Walker ticket from the spawn groups matching the cell's environment tags (or `defaultGroup`), limited to enemies whose `minDanger`..`maxDanger` contains the cell danger. Health, speed, and spawn weight scale across each enemy's own danger range. A player kill awards the enemy's `xp` and rolls its loot drop once; despawns give nothing.

```
zn_spawn_enemy [enemyId|auto] [danger]   // development spawn in front of the player (not Walker-ticketed)
zn_kill_enemies                          // kill nearby defined enemies, credited to the player
zn_test_enemies                          // selection, scaling, and reward tests
```

Through the bridge these add `reports.enemySpawn`, `reports.enemyKills`, and `reports.enemyTests`.

# World Loot Spots

`ZM_LootSpots` (server) turns matching map props from `entity_loot.json` into loot spots when a player loads into a city cell. Spot state is saved per profile and cell in SQLite; a cell re-rolls on the next load after 5 minutes with nobody in it. Press E near a highlighted prop to search it, then accept or decline the offered item (declining keeps the same item on the spot).

ZombieSim disables Garry's Mod's default `+use` physics-prop pickup globally. Pressing E can still activate ZombieSim interactions, doors, buttons, and transition gates, but cannot carry barrels, crates, or other physics props.

```
zn_loot_spots            // matching props and spot states in the current cell
zn_loot_spots_refresh    // re-roll every spot now
zn_test_loot_spots       // loot spot tests (throwaway profiles)
zn_dev_loot_offer <modelSubstring> [limit]   // development: roll then decline matching offers (no inventory changes)
zn_dev_scavenge <modelSubstring> [limit]   // development: search and accept matching spots as the first player
```

Barrels are scavenged for resources. Blue plastic (`props_borealis/bluebarrel001`) and wooden (`props_c17/woodbarrel001`) barrels give `itemBarrelWater`; oil drums, warning barrels, `de_train/barrel`, and barrel pallets give `itemOil`. Rules match `prop_physics`, `prop_physics_multiplayer`, `prop_physics_override`, and `prop_dynamic` by normalized model path; other barrel models, broken barrel gibs, and `prop_static` are not loot spots.

Semantic container rules are also model-specific: the CSS and HL2 vending machines roll bottled water or soda; ammunition crates and the listed CSS military crates roll weapons/ammunition only; and the listed wooden crates roll food, medical supplies, or materials. No generic prop-class rule grants fallback loot, so unsupported models remain non-lootable.

`celltemplates/dev/zz_preview_loot_fixture.vmf` is a developer-only physical-prop fixture for these five representative models. It is intentionally excluded from the preview/city template plan and must not be staged as a gameplay map.

Through the bridge these add `reports.lootSpots`, `reports.lootSpotTests`, and `reports.scavengeProbe`. The bridge-only `zombiesim_dev_teleport_cell <gridX> <gridY>` moves the first player to a raw grid cell through the normal world transition.

# Runtime World Data

`ZM_World` loads `data_static/zombiesim_world.json` from the `GAME` mount during gamemode initialization. It returns `nil` or `false, error` when the index is unavailable, so gameplay code can fail safely while a release is being assembled.

```lua
local cell = ZM_World:GetCell(0, 0)
local mapName = ZM_World:GetMapPath(cell)
local target, exit, mode = ZM_World:CanTravel(cell, "N", "road")
local route = ZM_World:FindPath({ x = 0, y = 0 }, { x = 8, y = 12 }, { mode = "any" })
```

Player helpers use their persisted `CellX` and `CellY` coordinates: `ply:GetWorldCell()`, `ply:GetNeighbouringCell("N")`, `ply:GetNeighbouringCells()`, and `ply:GetReachableNeighbouringCells("road")`. Both British and American `Neighbouring`/`Neighboring` spellings are available.

The service provides cell lookup by coordinates/id/map, map transition resolution, exit and blockade checks, environment/district/safe-zone/landmark/metro/atmosphere data, indexed metadata searches, nearest-cell searches, and A* routing. Recipe map names can refer to multiple logical cells; use `GetCellsForMap` when a map name is ambiguous.

- ./source

The .vmf files for the cells of the city, should match a map file in the content folder idealily.

# Generator Settings

Generation is controlled from [generator-settings.json](generator-settings.json). Start with the plain-language guide in [docs.md](docs.md); it explains every setting, shows the preview workflow, and marks settings that are safe to experiment with.

For future multi-tile prefab support, see [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md).

# Walker Simulator

The authoritative native population system and its Alpha 2 ticket contract are documented in [docs/walker_simulation.md](docs/walker_simulation.md). Run these commands from [bin/walker-simulator](bin/walker-simulator):

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
ctest --preset test-mingw-debug --output-on-failure
```

Build and install the optional Win64 server module:

```powershell
cmake --preset mingw-gmod-module-debug
cmake --build --preset build-mingw-gmod-module-debug
.\scripts\install-local-win64.ps1 -GarrysModRoot "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

In game, run `zombiesim_walker_smoke`, load `zn_preview_start`, then use `zombiesim_walker_status` and `zombiesim_walker_noise <strength> <radius> [durationTicks]`. Record live evidence in [docs/alpha_2_test_log.md](docs/alpha_2_test_log.md).

Compatible Walker checkpoints persist horde movement, attractors, terminal ticket outcomes, and the server ticket-request counter across level changes and restarts. Checkpoints are profile-scoped in the server SQLite `walker_checkpoints` table; periodic serialization runs on the native worker thread. Map-local NextBots are reconciled as despawned after restore, then the materializer resumes normally. Use `zombiesim_walker_checkpoint_status`, `zombiesim_walker_checkpoint_save`, and `zombiesim_walker_checkpoint_clear <profile>` for server-side checkpoint diagnostics and administration. Workshop uploads cannot distribute the DLL; install releases manually under `garrysmod/lua/bin` using the script above.
