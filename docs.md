# ZombieSim Generator Guide

This guide explains the city generator in normal game-making language. You do not need to be a programmer to adjust the safe settings. The main file is [generator-settings.json](generator-settings.json).

The generator creates a city plan, turns that plan into reusable 5-by-5 cell recipes, then creates VMF files for Hammer. It does not change the hand-authored tile templates in `tiletemplates`.

## Start Here

1. Make a copy of [generator-settings.json](generator-settings.json) before experimenting.
2. Change one group of settings at a time.
3. Make a preview first. The `preview` profile writes VMFs to `generated/src_preview`, separate from the `city` profile's `generated/src` folder.
4. Open the preview image or preview VMFs in Hammer and decide whether the change is worth keeping.

Settings use JSON. Text must be inside double quotes, items in a list need commas, and there must not be a comma after the final item in a list. Do not rename setting names unless this guide calls them advanced.

## Canonical Tile Orientations

All template rotations are measured from these `$0^\circ$` authored orientations. Keep this reference when adding generator placement rules or diagnosing a rotated tile in Hammer:

| Template family | `$0^\circ$` authored direction |
| --- | --- |
| Straight road and motorway | South to north |
| Road and motorway corner | East to south |
| Road and motorway T-junction | East to west, with its connecting stem north |
| Bridge ramp | North to south, rising toward north |
| Motorway road bridge | Motorway east to west below; road north to south above |
| Building | Entrance on the south edge of its tile |
| Border wall | North to south, offset to the east tile edge |
| Border wall corner | North to east, at the north-east tile corner |
| Carpark entrance | Connective tip on the south tile edge; standard variants have local east and west lanes. At `$0^\circ$`, `_deadend_west` closes west and connects east, while `_deadend_east` closes east and connects west. |

The generated border ring sits one tile outside the playable cell. Its corner instances use the Hammer-verified yaws `NW=0`, `NE=270`, `SE=180`, and `SW=90`, placing the authored corner against the level rather than toward the skybox.

### Tile Road Connections

Every building template has one `zn_tile_direction` point entity. Its `direction` identifies the authored-local entrance edge and the point must sit at that edge's midpoint. Buildings in the current library use `south`, so a 1x tile is `0 -320 32`, a 2x tile is `0 -640 32`, and a 3x tile is `0 -960 32`. The planner rotates this entrance edge toward compatible ordinary roads, motorways, or concrete paths without changing the frontage tile by default.

Add zero or more `zn_road_connection` points only where a generated road must physically connect. Each point must be centered on a single exterior footprint segment, and `connection_type` defaults to `none`. A `t_junction` point converts its exact adjacent compatible ordinary straight-road tile into a T-junction; multiple distinct points create multiple T-junctions. The 2x commercial and hospital carpark-frontage templates each use one south-edge T-junction point. A motorway or concrete path is valid frontage but denies a T-junction request and remains unchanged. A marked template is not placed when every requested connection cannot be satisfied. These markers are planning metadata and have no gameplay behavior.

Buildings and landmarks rotate their authored south-edge entrance toward a directly adjacent road, motorway, concrete path, or transport tile. At a road corner, only its connected edges are valid frontage: a building or landmark next to the closed corner edge faces away from that edge instead.

### Carpark Endcap Orientation Contract

Carpark lanes that reach a cell edge receive a deadend cap in the normal generated border ring. The cap's **physical outer side** determines both its VMF and its `func_instance` `angles`; the local `carpark_lane_east` or `carpark_lane_west` role must not be used for either decision. A local west lane can, for example, terminate at the physical east border.

The tile grid uses `tileX` increasing east and `tileY` increasing south. Test the edge tile first, then place the cap one tile beyond that edge:

| Physical cap side | Edge-tile test | Outer cap coordinate | VMF | `angles` |
| --- | --- | --- | --- | --- |
| North | `tileY = 0` | `(tileX, -1)` | `carparks/tile_carpark_deadend_west.vmf` | `0 270 0` |
| East | `tileX = gridSize - 1` | `(gridSize, tileY)` | `carparks/tile_carpark_deadend_east.vmf` | `0 0 0` |
| South | `tileY = gridSize - 1` | `(tileX, gridSize)` | `carparks/tile_carpark_deadend_west.vmf` | `0 90 0` |
| West | `tileX = 0` | `(-1, tileY)` | `carparks/tile_carpark_deadend_east.vmf` | `0 180 0` |

These are output-instance angles, not rotations to bake into either source VMF. [carpark_endcaps.psm1](bin/carpark_endcaps.psm1) owns this table and is imported by both the regular VMF builder and the borderless carpark zoo. Do not duplicate or derive the table from lane roles elsewhere.

One-sided entrance variants use their own Hammer-verified file/yaw pairing because their suffix names the **local** lateral edge that is dead-ended: `tile_carpark_entrance_deadend_west.vmf` closes local west and leaves local east connected, while `tile_carpark_entrance_deadend_east.vmf` closes local east and leaves local west connected. The road connector remains on the authored south edge. The planner selects the suffix from the local closed lane and rotates the entry piece `$180^\circ$` from the carpark assembly yaw. This yields `_east` at `0 0 0` for the south-side short preview entries and `_west` at `0 180 0` for the north-side short fixture. Ordinary deadend-cap orientation remains unchanged. `tile_carpark_entrance_deadend.vmf` is different: it keeps the ordinary entrance-facing yaw but emits no lateral lane tiles.

An enabled lane is deterministically one or two straight tiles long according to `carparks.minimumLaneTiles` and `carparks.maximumLaneTiles`. Both enabled arms in one carpark use the same length. A short lane receives a `carpark_lane_endcap_east` or `carpark_lane_endcap_west` tile in the first unused in-grid space, selected through the same physical-side table. A full-length lane reaches the cell edge and receives the usual outer-border cap.

For the current preview seed, [carparks.vmf](celltemplates/dev/carparks.vmf) provides one repeatable Hammer check for each side:

| Zoo target | Physical side | Expected VMF and `angles` |
| --- | --- | --- |
| `zm_dev_carpark_0_carpark_endcap_3_-1` | North | `deadend_west`, `0 270 0` |
| `zm_dev_carpark_1_carpark_endcap_5_3` | East | `deadend_east`, `0 0 0` |
| `zm_dev_carpark_0_carpark_endcap_3_5` | South | `deadend_west`, `0 90 0` |
| `zm_dev_carpark_1_carpark_endcap_-1_3` | West | `deadend_east`, `0 180 0` |

After changing carpark placement code, refresh the zoo with `.\bin\build_tile_zoos.ps1 -RefreshPlan`, reopen it in Hammer, and inspect both the `file` and `angles` keyvalues against this table. Then rebuild preview source VMFs before compiling. When a carpark junction is on a bridge-ramp cell, the ramp moves to the first bridge-side tile so the junction connects to the highway.

The `cellPlanning.rotations` values in [generator-settings.json](generator-settings.json) rotate these authored orientations into the recipe's required exits. Do not infer a yaw from a filename alone; verify it against this table and the template in Hammer.

## World-Generation Profiles

`worldGeneration.profiles` in [generator-settings.json](generator-settings.json) defines every generated world. A profile owns its grid size, generated file prefix, layer-image setting, source VMF folder, compiler build folder, staged map folder, runtime-world JSON, and optional launcher thumbnail. The included `city` and `preview` entries are normal profiles; add another entry such as `coast` to build a separate custom city without adding another set of special-case settings.

`build_city.ps1` also stages generated in-game map materials in `content/materials/worlds/<profile>`. The composite world image and its exported layers are placed in `map_layers` with stable names: `world.png` for the composite and `<layer>.png` for every individual layer. One local schematic for each reusable city recipe is rendered in `cells` using the matching BSP name with a `.png` extension. Each local map reflects its planned 5-by-5 tile layout, dark asphalt roads with yellow dotted centerlines, road or motorway topology, blocked exits, building squares, and every carpark entrance, junction, lane, and endcap. Carparks use a lighter surface and outlined parking bays. It marks named landmarks at their exact planned tile positions; commercial-building tiles are marked `COM`, while a future dedicated `tile_market` remains a named `MKT` landmark. Satellite mode always renders the generated named-landmarks overlay above its satellite image and is stitched from the local recipe maps at the highest whole-cell resolution within the 4096px material limit. Source map layers are replaced for each plan while the derived satellite is retained until the stitcher overwrites it. Profile generation automatically removes stale generated source world maps and layers, source VMFs, zoo VMFs, compiler artifacts, staged BSPs, cell maps, and map-layer PNGs; it does not touch authored templates or other profiles. Set `exportLayers` to `true` for any profile that needs the individual world layer images; the release build stops with an actionable error when they have not been generated.

The native client map opens with `M` or the `zombiesim_map` console command. It supports layer toggles, pan and deep zoom, selected-cell inspection, selected-cell right-click waypoints, and dynamic player and road-blockade overlays. A waypoint draws a route from the player that avoids blocked roads when a valid path exists. The title and map key remain fixed in the upper-left and upper-right corners while the world map is moved. It uses Derma and the staged material PNGs directly, so no HTML, CSS, or JavaScript needs to be packaged.

Use `-WorldProfile <name>` with every generator script. Without it, the scripts use `worldGeneration.defaultProfile`, currently `city`. `-Preview` remains a compatibility alias for `-WorldProfile preview` on scripts that already supported it.

```json
"coast": {
	"filePrefix": "coast",
	"gridCells": 48,
	"exportLayers": false,
	"cellDirectory": "generated/src_coast",
	"buildDirectory": "generated/build_coast",
	"releaseMapDirectory": "content/maps/coast",
	"runtimeWorldData": "content/data_static/zombiesim_world_coast.json",
	"overrides": {
		"mapGeneration": {
			"road": { "growthDepth": 4 },
			"blockades": { "chance": 0.15 }
		},
		"cellPlanning": {
			"variants": { "usageThreshold": 8 }
		}
	},
	"thumbnail": {
		"map": "zn_coast",
		"source": "bin/coast_grid_48x48_seed_2026.png",
		"title": "COAST CITY",
		"showLogo": true
	}
}
```

The optional `overrides` object can replace any ordinary generator setting for that profile, including nested `mapGeneration`, `cellPlanning`, `vmfBuild`, `compilation`, `paths`, or `directions` settings. Objects merge recursively, while a scalar value or array replaces the shared value. Command-line parameters still take precedence for one run. Profiles cannot override `schemaVersion` or `worldGeneration` itself.

The profile name should match the `world_profile` key on its launcher map. After adding one, run the ordinary generator pipeline with `-WorldProfile coast`; the configured `filePrefix` keeps its manifests, template plans, required-recipe lists, source maps, build files, staged BSPs, and runtime data separate from all other profiles.

## Preview Workflow

Run these commands from the project root. This uses the small preview city and leaves production cell VMFs alone.

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
```

`-WorldProfile preview` makes the map generator use `worldGeneration.profiles.preview.gridCells` and makes planning, building, and checking use the preview profile's configured folders when no explicit path is supplied. `-Preview` is accepted for existing command files and means the same thing.

## Tile Zoo And Dev Cells

Run the tile-zoo generator after adding, renaming, or moving a tile template. Use `-RefreshPlan` after changing placement logic so the street and carpark fixtures use a newly planned, but not VMF-generated, preview:

```powershell
.\bin\build_tile_zoos.ps1 -RefreshPlan
```

It writes one blank `zoo_<category>.vmf` grid for every direct `tiletemplates` category to `celltemplates/dev`. `streets.vmf` renders one distinct non-carpark road or motorway topology/orientation layout from the current preview plan, and every distinct real-preview layout in `carparks.vmf` renders the exact `tilePlacements` produced by `plan_cell_templates.ps1`. These fixtures exercise the same placement logic as normal generated cells without creating preview source VMFs.

`carparks.vmf` has two planner-derived inspection groups:

- The distinct carpark recipes in the current preview plan, including ordinary and bridge-ramp cases.
- The seven deterministic fixtures from [carpark_zoo_fixture_map.json](bin/carpark_zoo_fixture_map.json): ordinary carparks branching north, east, south, and west; a south branch joined to an east bridge ramp; a terminal one-tile entrance; and a one-sided short row. `build_tile_zoos.ps1` runs this logical map through the same planner and refreshes its derived [carpark_zoo_fixture_template_plan.json](bin/carpark_zoo_fixture_template_plan.json) on every zoo build. It asserts the expected lane counts, short-row caps, and one-sided physical yaw contract. Do not manually compose or rotate its VMF placements.

Use [zoo_carparks.vmf](celltemplates/dev/zoo_carparks.vmf) to inspect the individual authored carpark templates.

The fixture target prefixes are `zm_dev_carpark_fixture_vertical_east`, `vertical_west`, `horizontal_north`, `horizontal_south`, `horizontal_south_bridge_ramp_east`, `vertical_terminal_entrance`, and `horizontal_one_sided_east_short`; use these to frame a specific generated arrangement in Hammer. `zoo_manifest.json` records every zoo tile's grid coordinate. Building zoos are grouped by type and ordered by density tier. These are Hammer-only development cells and are not included in normal city generation or release builds.

`-Seed 1337` is a one-run override. It does not edit the settings file. Keep a seed you like so you can reproduce the same city after changing unrelated assets.

Every generator script also accepts `-SettingsPath <file>`. This lets you keep named presets, such as a testing copy or a large-city copy, without repeatedly editing the main settings file.

## Preview Compile Check

Before committing to the long VVIS and VRAD production compile, run the fast structural check below. It runs VBSP against every preview recipe, so it validates VMF syntax, referenced instances, skybox materials, brushes, props, and BSP generation. It does not calculate visibility or lightmaps.

```powershell
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

This uses the preview profile's `cellDirectory`, `buildDirectory`, `releaseMapDirectory`, and `runtimeWorldData`. It leaves the city profile's maps and runtime data untouched. Omit `-VBSPOnly` only when you want the slower preview VVIS and VRAD pass.

When the current source VMFs, BSPs, and `.prt` files have already passed the VBSP portal preflight, reuse them for a playable VVIS/VRAD-only preview release:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -CleanStagedCity
```

`-SkipVBSP` requires an existing `.bsp` and `.prt` for every required recipe, then runs VVIS and VRAD only. Keep `-SkipRecipeRefresh` with it so the release uses the exact VMFs that produced those portal files. Completed VVIS and VRAD stages are reused when their compiler logs are newer than their `.prt` or VVIS-log input; add `-Force` to run every requested stage again.

Add `-PrioritizePortalCost` to that reuse build to run the maps with the most portals first. The queue uses portal count, then portal-cluster count, from each `.prt` header. It requires `-SkipVBSP`, since a normal VBSP pass has not yet generated portal data when its queue is ordered:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity
```

## Visibility Budget Check

Use the visibility-budget check after changing structural tile geometry. With `-RefreshPortalData`, it runs VBSP only for city recipes and standalone den maps whose portal data is missing, invalid, or older than the source VMF, then reads each generated `.prt` file to report its portal-cluster and portal counts without running VVIS or VRAD. Add `-ForcePortalData` when a full clean portal rebuild is required:

```powershell
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

The initial budgets are `250` portal clusters and `900` portals. They are configured under `compilation.visibilityBudget` in [generator-settings.json](generator-settings.json), can be overridden for one run with `-MaxPortalClusters` and `-MaxPortals`, and write `vis-budget-report.json` beside the preview BSPs. For every over-budget recipe, the report also ranks its instanced tiles by their aggregate non-`func_detail` brush-solid count and shows each tile's detail-solid, entity, and prop counts. This is a diagnostic lead rather than a portal attribution: open sightlines between tiles can also create high VVIS cost. The command exits nonzero for over-budget, missing, or invalid portal files.

## Selecting City Data In Hammer

Place exactly one `zn_world_profile` point entity in a launcher map and set its `world_profile` keyvalue. It is a dedicated ZombieSim entity, so other `info_target` or map-logic entities are ignored. Add [zombiesim.fgd](zombiesim.fgd) to the Hammer game configuration to expose it in the entity browser.

The built-in values are `city`, which loads `data_static/zombiesim_world.json`, and `preview`, which loads `data_static/zombiesim_world_preview.json`. The included `zn_start` and `zn_preview` launcher maps use those values. A custom profile such as `coast` loads `data_static/zombiesim_world_coast.json`; profile names may only use lowercase letters, digits, `_`, and `-`. Its optional `start_delay` property is a non-negative number of seconds to wait before a first-time player changes level to the world-origin safe room, allowing an opening intro to play. The default is `0`.

The selected profile is retained when changing level to a city recipe or standalone safe-room map, where no selector entity is needed. A map containing conflicting `zn_world_profile` values is rejected so it cannot load ambiguous city data.

## Launcher Thumbnails

`build_launcher_thumbnails.ps1` writes map-menu thumbnails only for profiles with a `thumbnail` entry under `worldGeneration.profiles` in [generator-settings.json](generator-settings.json). By default it refreshes the built-in `city` and `preview` entries:

```powershell
.\bin\build_launcher_thumbnails.ps1
```

Use `-Profile` to refresh one or more named profiles, or `-AllProfiles` to refresh every configured entry that defines a thumbnail. A selected profile only writes its configured target map thumbnail.

```powershell
.\bin\build_launcher_thumbnails.ps1 -Profile coast
.\bin\build_launcher_thumbnails.ps1 -Profile city, coast
.\bin\build_launcher_thumbnails.ps1 -AllProfiles
```

Pass `-CellThumbnails` to additionally create the Garry's Mod map-browser thumbnail for every rendered recipe map in the selected profile. These thumbnails reuse the existing local cell-material images and are written below `content/maps/thumb/<profile>/<map>.png`, matching the staged map path such as `content/maps/preview/<map>.bsp`.

```powershell
.\bin\build_cell_map_materials.ps1 -WorldProfile preview
.\bin\build_launcher_thumbnails.ps1 -Profile preview -CellThumbnails
```

Use the default profiles to refresh both the `city` and `preview` map-browser thumbnails:

```powershell
.\bin\build_launcher_thumbnails.ps1 -CellThumbnails
```

To give a custom city its own launcher thumbnail, add a `thumbnail` object to its profile. `map` is the launcher BSP name without `.bsp`, `source` is an existing project-relative image path, and `title` and `showLogo` control the thumbnail overlay:

```json
"thumbnail": {
  "map": "zn_coast",
  "source": "bin/coast_grid_48x48_seed_2026.png",
  "title": "COAST CITY",
  "showLogo": true
}
```

The script writes the result as `content/maps/thumb/<map>.png`, so this example produces `content/maps/thumb/zn_coast.png`. Use `-SettingsPath` with a separate settings preset when the custom city does not use the main configuration.

## Standalone Dens

Safe-room entrance cells remain normal logical city cells. They are not replaced by safe-room maps and safe-room maps are not added to the city grid or its graph. The city recipe for the entrance coordinate continues to compile as normal and should contain a `tile_saferoom` entrance plus its level-changing entity. Planning separately assigns that entrance to a reusable standalone safe-room map such as `zn_den_ra` or `zn_den_md_hospital`.

`build_cell_vmfs.ps1 -RefreshGenerated` copies the selected den VMF and its optional VMX sidecar unchanged into the active source directory. `build_city.ps1` compiles and stages those den BSPs alongside city recipe BSPs. The runtime index exposes the selected standalone map as `safeZone.map`; future entrance entities can use `ZM_World:GetSafeZoneMap(cell)` to obtain its `city/<den-map>` transition name. The city-cell APIs continue to return the safe-zone entrance cell, never the den itself.

Safe-room templates are selected by semantic biome/profile tags, never by `environment.terrain`. `settlement` is deliberately excluded because it describes the city entrance context rather than the destination. `radioactive` therefore selects `cell_ra_safezone.vmf` even when its city entrance cell happens to use grassland, sandy, or dirt terrain. `gr` means the `grasslands` default den style. The active destination codes are `gr`, `co`, `fi`, `ra`, `fo`, `mi`, `md`, `es`, `rl`, `ss`, `rc`, and `pk`. The existing `st`, `sa`, and `di` placeholder pairs are retained for future semantic profiles, but are not selected from entrance context or terrain labels.

District safe-room placement first prefers an available `Hospital`, `Army Base`, or `Bunker` landmark cell; when none is available, it selects the usual generic safe-room entrance. A supported landmark at the entrance takes precedence over the generic biome map, choosing `cell_<biome>_safezone_hospital.vmf`, `cell_<biome>_safezone_army_base.vmf`, or `cell_<biome>_safezone_bunker.vmf`. All current biome and landmark templates are copies of `cell_gr_safezone.vmf` plus its VMX sidecar, ready for independent Hammer editing. When multiple supported landmarks occur, `Hospital`, then `Army Base`, then `Bunker` is the configured precedence order.

All entrances selecting the same biome and landmark variant point to one compiled destination BSP. `build_cell_vmfs.ps1 -RefreshGenerated` refreshes each selected reusable map from its template and removes obsolete `zn_den_*` source maps from the active source folder. Edit the templates in `celltemplates/safezones`, not the copied `generated/src*` build inputs; normal `build_city.ps1` runs this refresh before compiling.

## Compile Monitoring and Profiles

The compiler prints its current map, stage, elapsed stage time, and remaining map count. It writes a `compile-report.json` beside the intermediate BSPs, for example `generated/build_preview/compile-report.json` for a preview. Each map record includes its stage status, exit code, duration, and stdout/stderr log paths.

The default `compilation.activeProfile` is `stock-gmod`. Its VBSP, VVIS, and VRAD tools are resolved from Garry's Mod's `bin` directory and retain the existing `-game <garrysmod>` arguments. Set a longer or shorter one-run budget without editing the settings file:

```powershell
.\bin\compile_cell_vmfs.ps1 -Preview -VBSPOnly -VbspTimeoutSeconds 120 -DeferredGraceSeconds 180
```

When a stage reaches its timeout it is deferred, not killed, and the next map starts. After all normal work has started, the runner waits for `deferredGraceSeconds`, then records the remaining deferred work in the report. By default it returns an error while any map is failed or unfinished. Pass `-FinalizeWithIncomplete` to finish after writing the report without waiting further. That option does not stage an incomplete release through `build_city.ps1`; it stops before copying BSPs or writing runtime data.

To use another compiler suite, add a complete profile under `compilation.profiles`, then select it with `compilation.activeProfile` or `-CompilerProfile`. `toolDirectory` may be absolute or project-relative. Argument templates are JSON arrays and may use `{gameDirectory}`, `{mapVmf}`, and `{mapBsp}`:

```json
"my-compiler": {
	"toolDirectory": "C:\\Tools\\my-compiler",
	"executables": { "vbsp": "vbsp.exe", "vvis": "vvis.exe", "vrad": "vrad.exe" },
	"arguments": {
		"vbsp": ["-game", "{gameDirectory}", "{mapVmf}"],
		"vvis": ["-game", "{gameDirectory}", "{mapBsp}"],
		"vrad": ["-game", "{gameDirectory}", "{mapBsp}"]
	}
}
```

Hammer++ is an editor/orchestration tool and BSPSource is a decompiler, so neither is a drop-in compiler profile. Compatibility of third-party compiler suites, including HVAC/HAC-style tools, with Garry's Mod's Source branch is not established here. Keep them opt-in and validate a preview `-VBSPOnly` build before a full VVIS/VRAD pass.

## Production Release Workflow

After reviewing the preview, regenerate production recipes so they inherit the current base cell template, including its lighting and fog entities. Then build the release:

```powershell
.\bin\build_cell_vmfs.ps1 -PlanData .\bin\map_grid_64x64_seed_1337_template_plan.json -RefreshGenerated
.\bin\build_city.ps1 -MapData .\bin\map_grid_64x64_seed_1337.json -PlanData .\bin\map_grid_64x64_seed_1337_template_plan.json -CleanStagedCity
```

`build_city.ps1` runs the sequential VBSP, VVIS, and VRAD compiler pass for every VMF in the selected profile's `cellDirectory`, using that profile's `buildDirectory` as an intermediate folder. It copies only the recipe BSPs selected by the plan to the profile's `releaseMapDirectory` and writes the compact gameplay world index to its `runtimeWorldData` path.

The release script refreshes generated recipe VMFs first, so changes to the base cell template are included in the compile. Pass `-SkipRecipeRefresh` only when the selected source recipes have already been deliberately refreshed.

The BSP names identify reusable recipes, not coordinates. The runtime index maps every logical cell coordinate to its selected BSP name and contains its navigation graph, environment, safe zone, landmark, metro, and atmosphere data. Build a map transition name from `world.mapDirectory .. "/" .. cell.map`, which defaults to `city/<recipe>`. Read the staged index in Garry's Mod with `file.Read("data_static/zombiesim_world.json", "GAME")` after it is packaged at the addon root.

## What Is Safe To Change?

Safe first experiments are:

- `mapGeneration.seed`
- Each profile's `gridCells`
- Road, bridge, blockade, and carpark chances
- Building-density values
- District names, positions, radii, and colours
- City-name word lists
- `cellPlanning.variants.usageThreshold` and `maximumPerRecipe`
- `atmosphere.profiles` fog and colour-correction values
- `atmosphere.lightingProfiles` light colours and brightness

Advanced settings control how prefabs connect or rotate. Change those only after checking the result in Hammer:

- `directions`
- `cellPlanning.topologyTemplates`
- `cellPlanning.transportTemplates`
- `cellPlanning.rotations`
- `cellPlanning.templatePatterns`
- `cellPlanning.filenameAbbreviations`
- `vmfBuild.tileSize`

## How Settings Are Chosen

The default values come from [generator-settings.json](generator-settings.json). A command-line value takes priority for that one command. For example:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 9001 -RoadDepth 5
```

uses seed `9001` and road depth `5` once, even if the JSON file says something else. The next run returns to the JSON defaults.

## `schemaVersion`

`schemaVersion` identifies the format of the settings file. Use `2` for named world-generation profiles. The scripts also accept version `1` settings files, translating their city and preview values for compatibility, but new profiles require version `2`.

## `paths`

These are project-relative folders and files. Use forward slashes or backslashes consistently. Paths are relative to the project root, not the `bin` folder.

| Setting | What it controls | Notes |
| --- | --- | --- |
| `templateDirectory` | The root folder containing hand-authored tile VMFs. | Default: `tiletemplates`. Do not point this at generated cell VMFs. |
| `baseCellTemplate` | The border/base VMF inserted behind generated prefab instances. | Default: `celltemplates/template_border_s.vmf`. It must exist and contain a `cameras` block. |
| `scriptOutputDirectory` | Folder for PNG previews, JSON plans, required-VMF lists, and filename keys. | Default: `bin`. |
| `safeZoneTemplateDirectory` | Complete standalone den-map templates. | Default: `celltemplates/safezones`. These are copied as whole VMFs, not assembled from tiles. |

## `worldGeneration`

`defaultProfile` is used when a generator command has no `-WorldProfile` argument. Every entry in `profiles` is a complete, isolated generated-world configuration.

| Profile setting | What it controls |
| --- | --- |
| `filePrefix` | Prefix for the profile's generated map image, manifest, template plan, required-recipe list, and filename key. |
| `gridCells` | Width and height of this city in logical cells. `64` means a 64-by-64 city. |
| `exportLayers` | Whether generation writes separate terrain, roads, buildings, highways, landmarks, safe zones, metro, grid, labels, and key PNG layers. |
| `cellDirectory` | Generated VMF source folder for this profile. |
| `buildDirectory` | Intermediate compiler output folder for this profile. |
| `releaseMapDirectory` | Staging folder for the profile's compiled BSPs; its leaf directory becomes the runtime map directory. |
| `runtimeWorldData` | Compact gameplay world index. Package it under `data_static` and select the matching profile with `zn_world_profile`. |
| `overrides` | Optional partial generator settings that recursively merge over the shared settings for this profile. |
| `thumbnail` | Optional map-menu image definition for `build_launcher_thumbnails.ps1`. |

## `compilation`

These settings control the profile-driven VMF compiler runner. Command-line timeout/profile parameters override them for one command.

| Setting | What it controls | Notes |
| --- | --- | --- |
| `activeProfile` | Compiler profile used when `-CompilerProfile` is omitted. | Default: `stock-gmod`. |
| `progressRefreshMilliseconds` | How often the active-stage progress display refreshes. | Keep at least `100`. Default: `1000`. |
| `stageTimeoutSeconds.vbsp`, `.vvis`, `.vrad` | Soft timeout budget for each compiler stage. | A stage is deferred after this budget while the remaining queue continues. Defaults: `300`, `900`, `1800`. |
| `deferredGraceSeconds` | Extra wait after the normal queue for deferred compiler processes. | Default: `300`. |
| `profiles.<name>.toolDirectory` | Folder containing that profile's executables. | Empty for the stock Garry's Mod `bin`; otherwise absolute or project-relative. |
| `profiles.<name>.executables` | Names or absolute paths for `vbsp`, `vvis`, and `vrad`. | All three keys are required, including VBSP-only runs. |
| `profiles.<name>.arguments` | Argument-template arrays for `vbsp`, `vvis`, and `vrad`. | Use the supported placeholders shown above. |

## `directions` (Advanced)

The generator treats roads as a north, east, south, west grid. These settings define the shared vocabulary used by map generation and cell planning. They are not cosmetic labels.

| Setting | What it controls | Editing advice |
| --- | --- | --- |
| `cardinal` | The four valid direction codes and their order. | Keep `N`, `E`, `S`, `W` in clockwise order. Reordering changes turning logic and can change a seeded city. |
| `names` | Long names used for cell orientation, such as `north-east` and `missing-west`. | Keep keys matched to `cardinal`; values must match the rotation and filename tables. |
| `opposites` | The direction at the far end of a connection. | Every pair must agree: `N` maps to `S`, `E` maps to `W`, and vice versa. A mistake creates disconnected roads. |
| `linearTileYaw` | Hammer yaw for straight road pieces running toward each direction. | Default is `0` for north/south and `90` for east/west. Confirm a different value visually in Hammer before keeping it. |

## `mapGeneration`

This section creates the city-wide map layout and its PNG preview. A map cell is one playable VMF recipe. The selected profile's `gridCells` is the number of cells across and down, not the number of 640-unit chunks inside a cell.

### Basic Size And Seed

| Setting | What it controls | Good values |
| --- | --- | --- |
| `cellSizePixels` | Size of one cell in the PNG planning image. | `64` gives a 1536-by-1536 image for a 24-by-24 preview. This affects the picture, not Hammer tile size. |
| `seed` | Default random seed. The same seed and the same settings create the same layout. | Any whole number. Prefer passing `-Seed` for a temporary test. |
| `landmarks.maximumPerCell` | Maximum named landmarks on an eligible city cell. | `4` is the current limit. Icons use a two-column grid and the map tooltip lists every landmark on the cell. Keep it between `1` and `4`. |

### `road`

Road settings determine how far the road network grows and how tangled it becomes.

| Setting | What it controls | Lower value | Higher value |
| --- | --- | --- | --- |
| `widthPixels` | Width of ordinary roads in the PNG preview. | Thinner map drawing. | Thicker map drawing. This does not change the Hammer road prefab. |
| `growthDepth` | Maximum recursive depth for side-road growth. | Smaller, simpler street network. | More branches and more intersections. Large values can make a very busy city. |
| `branchChance` | Chance from `0` to `1` that a growing road creates a side branch. | Fewer side roads. | More connected, denser streets. |
| `turnChance` | Chance from `0` to `1` that a growing road turns at a growth step. | Straighter suburban roads. | More corners and irregular blocks. |
| `minimumSegmentSteps` | Shortest number of cells a growing road continues before it may end or branch. | Short local roads. | Longer road runs. Must be smaller than `maximumSegmentStepsExclusive`. |
| `maximumSegmentStepsExclusive` | First length the random road segment will not use. | Shorter maximum road run. | Longer maximum road run. The actual maximum is this value minus one. |
| `deadEndRepairRadius` | Furthest search distance, in map cells, used to connect repairable dead ends. | Keeps more dead ends. | Repairs more dead ends into connected roads. |
| `centralSpineChance` | Chance from `0` to `1` for each regular position on the central arterial to grow a north/south branch. | A cleaner main road. | More districts linked to the main road. |
| `maximumJunctionDegree` | Most connections allowed at one ordinary-road cell, from `2` to `4`. | `3` prevents four-way cross junctions. | `4` allows full intersections. |

After generating local roads, the generator checks every district center for a route to the origin road network. An isolated district receives a direct ordinary-road connection that respects `maximumJunctionDegree` and avoids highway cells. This guarantee also applies when highways and metro are disabled.

### `highways`

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables the deterministic interstate grid, its crossings, bridges, and district ramps. Set `false` for a local-road-only profile. |

### `bridges` And `blockades`

| Setting | What it controls | Range and warning |
| --- | --- | --- |
| `bridges.chance` | Chance for an eligible interstate crossing to become a bridge. | `0` to `1`. Use small values; `0.04` already produces occasional bridges. |
| `bridges.deadEndChance` | Chance that an eligible road dead end near a highway becomes a bridge connection. | `0` to `1`. Raising it can make highway areas much more accessible. |
| `blockades.chance` | Chance for an eligible ordinary-road connection to be blocked. | `0` to `1`. High values can make the city feel fragmented. Highways are not chosen for this rule. |

### `terrain` (Advanced)

Terrain values decide whether a map cell becomes grassland, sandy, or dirt. The generator calculates a weight for each terrain type, adds deterministic noise, then picks the largest weight. These values affect district appearance and which planner decorations/buildings are preferred later.

| Setting | What it controls |
| --- | --- |
| `minimumWeight` | Lowest allowed terrain weight after calculations. Keep above `0`. |
| `grassBaseWeight`, `sandBaseWeight`, `dirtBaseWeight` | Starting preference for each terrain type. Larger means more common before location effects. |
| `grassYWeight` | Grass change from top to bottom of the map. A negative value means less grass farther south. |
| `grassWestWeight` | Extra grass toward the west (left) side. |
| `sandCenterWeight` | Extra sand near the horizontal center of the map. |
| `sandNorthWeight` | Extra sand toward the north (top) side. |
| `dirtYWeight` | Extra dirt farther south (down). |
| `dirtEastWeight` | Extra dirt toward the east (right) side. |
| `noiseXMultiplier`, `noiseYMultiplier` | Deterministic variation pattern across the map. These are pattern controls, not probabilities. |
| `noiseModulo` | Repetition length for terrain variation. Must be a positive whole number, never `0`. |
| `sandNoiseMultiplier`, `dirtNoiseBaseline`, `dirtNoiseMultiplier` | Fine controls for how the noise shifts sand and dirt. Leave these alone unless deliberately tuning biome distribution. |

The default terrain recipe makes grass more common to the west/north, dirt more common to the south/east, and sand more likely near the center/north. Extreme numbers can make one terrain dominate the whole city.

### `metro`

| Setting | What it controls | Editing advice |
| --- | --- | --- |
| `enabled` | Enables the guided metro routes and stops. | Set `false` for a profile with no metro system. |
| `minimumStationSpacing` | Minimum straight-line distance, in map cells, between metro stops. | `6` avoids crowded labels. Lower values create more nearby stops. |
| `routeStopInterval` | Number of route cells between automatically considered metro stops. | Higher values make lines have fewer stops. Keep it a positive whole number. |
| `stopSuffixes` | Words used to name minor metro stops. | Add or replace simple names. Empty lists are invalid because a stop needs a name. |

### `settlements` And `population`

| Setting | What it controls |
| --- | --- |
| `settlements.minimumDensity` | Baseline chance for an eligible roadside district cell to become settled in `random` mode. |
| `settlements.districtCenterDensity` | Additional settlement chance at a district center in `random` mode. |
| `settlements.placementMode` | `random` uses the density values above. `hash_modulo` selects a stable sparse scattering based on each cell's coordinates and seed. |
| `settlements.spacing` | In `hash_modulo` mode, selects roughly one eligible cell in this many cells. Must be at least `2`. |
| `population.base` | Starting population used in the generator overview. |
| `population.perBuildingCell` | Population added for every settled city cell. |
| `population.seedVariation` | Deterministic seed-based population variation. Set `0` to disable it. |
| `population.roundToNearest` | Rounds the generated population to this interval. Use `1` to avoid rounding. |

### `radiation`

Radiation is a deterministic, source-centered fallout field. The first detonation is placed at `epicenterXFraction` across the map and at a seed-selected Y coordinate within the configured range. Larger maps add more deterministically placed sources, subject to `additionalSourceEveryGridCells` and `maximumSources`. Intensity decreases linearly with radial distance until it reaches `0` at the fallout radius. The generator exports a transparent `radiation` PNG layer, and the runtime applies radiation damage outside standalone safe rooms.

Every source cell is a special `The Epicenter` landmark, marked with an `EPI` map key and an `epicenter` environment tag. Cells at or above `destroyedThreshold` receive the `destroyed` environment tag. The planner gives these cells a high building density and prefers templates matching `destroyedBuildings` when they are available; until then, it falls back to ordinary building templates.

`cellMiles` supplies a lore scale for the grid. The displayed yield equivalence uses $Y = (R / R_{1\,MT})^3$, where $R$ is `falloutRadiusCells * cellMiles` and $R_{1\,MT}$ is `loreReferenceFalloutMilesAtOneMegaton`. With the preview defaults, a 9-cell radius at 4 miles per cell is 36 miles and produces a `27 MT` equivalence. This is a configurable lore approximation, not a physical fallout prediction: real deposition also depends on burst height, weapon design, wind, weather, terrain, and time.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables radiation intensity, the fallout overlay, and runtime damage data. |
| `epicenterXFraction` | Horizontal source location. `0.6` places the detonation three-fifths of the way east. Must be greater than `0` and less than `1`. |
| `epicenterYMinimumFraction`, `epicenterYMaximumFraction` | Inclusive vertical range used to choose the source from the seed. Both must be from `0` through `1` and ordered low to high. |
| `falloutRadiusCells` | Fixed fallout radius in grid cells. Intensity is `0` beyond this distance from each epicenter. |
| `additionalSourceEveryGridCells` | Adds one possible source for each complete interval of grid width after the first source. |
| `maximumSources` | Upper limit on the total number of detonation sources. |
| `cellMiles` | Lore distance represented by one grid cell. |
| `loreReferenceFalloutMilesAtOneMegaton` | Lore reference radius representing 1 MT in the yield-equivalence calculation. |
| `destroyedThreshold` | Radiation intensity from greater than `0` to `1` at which a cell receives the `destroyed` tag and destroyed-city planning. |
| `damagePerSecondAtPeak` | Health damage per second at full radiation intensity. Damage scales linearly below the peak. |
| `overlayMaximumAlpha` | Opacity from `0` to `255` used by every discrete radiation grid cell. |

### `danger`

Danger is a generated scalar for enemy scaling, stored on every world cell alongside, but independent from, its environment tags and radiation level. It begins at world `(0,0)` and progresses in nested right-facing chevrons using $d=x+|y|$. Safe-zone cells always have danger `0`. The generator exports a transparent `danger` layer that colors each cell outline by its discrete danger tier, leaving the filled building square visible.

The generated value is clamped to $0 \leq D \leq 1$ and classified in the manifest as `safe`, `low`, `moderate`, `high`, or `extreme`. Runtime consumers can read it through `ZM_World:GetDangerIntensity(...)` or `ply:GetDangerIntensity()` and combine it with `ZM_World:GetEnvironment(...)` tags when selecting enemy types, counts, or modifiers. Radiation is visualized separately as discrete grid-cell fills with fixed contamination colors.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables danger generation and the danger overlay. |
| `tierCount` | Number of discrete danger bands expanding from world origin `(0,0)`. Must be from `2` through `12`. |

### `airports`

Airports are deterministic `AIR` landmarks on reachable roads outside the radiation field. Normal map sizes receive exactly one airport. Larger maps can receive additional airports only after `additionalAirportEveryGridCells`, and each one must be at least `minimumSeparationCells` away from every other airport. The planner uses an ordinary fallback until a template matching `tile_airport*.vmf` exists.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables airport placement. |
| `additionalAirportEveryGridCells` | Grid-width interval required before another airport may be considered. |
| `maximumAirports` | Hard limit on airport count. |
| `minimumSeparationCells` | Required Euclidean distance between airports in grid cells. |

### `cityNaming`

`prefixes` and `suffixes` build the city name from the seed. Add words without spaces if you want a single-name city, or use spaces deliberately for a two-word result. Keep both lists non-empty.

### `districts`

Each item creates a named district. District locations are authored for the normal 64-by-64 layout and are scaled automatically for other city sizes.

| Field | What it controls |
| --- | --- |
| `name` | District name shown on the PNG and used by metro stop naming. Use a distinct, readable name. |
| `x`, `y` | District center on the 64-by-64 reference grid. `x` increases east/right; `y` increases south/down. |
| `radius` | District size in map cells before scaling. Larger districts influence a wider part of the city. |
| `color` | PNG overlay colour as `[alpha, red, green, blue]`. Each number is `0` to `255`; alpha is transparency, where `0` is invisible and `255` is solid. |

Avoid placing two district centers at exactly the same coordinates. Their names still work, but labels and district-based systems become harder to understand.

### `deadZones`

Each dead-zone item has `x`, `y`, and `radius`, using the same 64-by-64 reference grid as districts. Dead zones are scaled with city size. They prevent normal district activity in their area and help shape the hostile parts of the city. Keep radii positive.

### `rendering`

| Setting | What it controls |
| --- | --- |
| `biomeOpacity` | Transparency of terrain colour on the planning image, from `0` to `255`. It changes only the image, not the game world. |

## `cellPlanning`

This section turns the wide city map into a 5-by-5 grid of Hammer prefab instances for each unique cell recipe.

### Basic Cell Size

| Setting | What it controls | Important note |
| --- | --- | --- |
| `cellTileGridSize` | Number of prefab spaces across and down inside one generated cell. | Default `5` gives 25 prefab spaces. Use an odd number so roads have a true center tile. Changing it requires source border templates sized for the same layout. |

### `safeZones`

These settings choose the reusable standalone den map for a safe-zone entrance. They do not change the city recipe at the entrance coordinate.

| Setting | What it controls |
| --- | --- |
| `biomePriority` | Ordered environment tags used to select a den biome. The first tag present on an entrance cell wins. |
| `biomeCodes` | Short biome code used in the safe-zone template filename. Every value must correspond to an authored `cell_<code>_safezone*.vmf` template. |
| `defaultBiome` | Biome key used when no tag in `biomePriority` applies. It must be a key in `biomeCodes`. |
| `landmarkPriority` | Ordered landmark names eligible for a specialised den variant. The first matching landmark at the entrance wins. |
| `landmarkVariants` | Maps an eligible landmark name to its filename suffix, such as `hospital` for `_hospital`. |
| `templateFilenameFormat` | Filename pattern for a safe-zone source template. Keep `{biome}` and `{landmarkSuffix}` placeholders intact. |

Changing these values changes which den VMFs are copied into the active source directory. Confirm every referenced template exists in `celltemplates/safezones`, then refresh recipes before compiling.

### `templatePatterns` (Advanced)

These regular-expression filters decide which VMF files from `templateDirectory` are eligible for each role. Paths are relative to `tiletemplates`, use `/`, and matching is case-insensitive.

| Setting | Eligible files |
| --- | --- |
| `genericBuildings` | Ordinary building and construction assets. Special landmarks are intentionally excluded. |
| `destroyedBuildings` | Optional destroyed building assets, such as `buildings/tile_destroyed_*.vmf`. They are selected for `destroyed` fallout-core cells when at least one matching template exists. |
| `warehouses` | Warehouse assets usable by generic building selection. |
| `commercial` | Commercial assets. They are only allowed in commercial profiles or a Market landmark cell. |
| `industry` | Industry assets. They are only allowed on dirt terrain or radioactive profiles. |
| `decorations` | Decoration assets. Dirt and radioactive cells prefer these more often. |
| `carparks` | Carpark variants. They are only considered next to ordinary straight roads, not landmarks. |

Do not remove the `.vmf` ending. A pattern that matches nothing can leave a profile without the prefabs you expected. A pattern that is too broad can accidentally select unfinished or special assets.

### Templates Used By Terrain And Transport

`terrainTemplates` maps terrain names to their fallback VMF. `default` is used for any terrain name without its own entry.

`topologyTemplates` maps road and motorway shapes to their center VMF:

- `road-straight`, `road-corner`, `road-tjunction`, `road-crossjunction`, and `road-deadend`
- `motorway-straight`, `motorway-corner`, `motorway-tjunction`, `motorway-crossjunction`, and `motorway-deadend`

`transportTemplates` chooses special pieces for bridges and highway ramps:

| Setting | Use |
| --- | --- |
| `bridge-ramp` | Center of a road-to-bridge approach. |
| `bridge` | Motorway bridge crossing center. |
| `onramp` | Single motorway ramp center. |
| `onramp-dual` | Motorway ramp center with two exits. |
| `bridgeRoad` | Road continuation across the bridge deck. |
| `roadDeadEnd` | Ground-side cap for a bridge approach. |

Every referenced VMF must exist below `tiletemplates`. Do not rotate source VMFs to fix a generated placement. Correct the matching yaw setting after checking the canonical prefab in Hammer.

### `rotations` (Advanced)

All values are Hammer yaw angles in degrees. The generator rotates the generated `func_instance`, not the source tile VMF.

| Group | Meaning |
| --- | --- |
| `layout.road-deadend` | Yaw for a road dead end that opens toward each named direction. |
| `layout.motorway-deadend` | Equivalent yaw table for motorway dead ends. It is separate because the asset family may later use a different canonical orientation. |
| `layout.straight` | Yaw for vertical and horizontal straight roads. |
| `layout.corner` | Yaw for each two-direction road corner. |
| `layout.tjunction` | Yaw keyed by the missing direction of a T-junction. |
| `transport.bridge-vertical` and `transport.bridge-horizontal` | Center yaws for motorway bridge crossings. |
| `transport.bridgeRampByDirection` | Yaw for road ramps that face the bridge direction. |
| `transport.onrampByDirection` | Yaw for motorway on-ramps whose authored north-edge road connects toward each direction. |

Use only `0`, `90`, `180`, or `270` for the current square tiles. Test any change in a preview VMF in Hammer. A wrong yaw can make an apparently valid road point into a building or a cell border.

### `environment`

`profilePriority` decides which special identity a cell gets when it has more than one environment tag. The first matching item wins. For example, with the default order, `destroyed` wins over `radioactive` and `commercial` when a cell lies in the fallout core. Moving an item higher makes it override the entries below it.

`buildingDensity` is the chance from `0` to `1` that an eligible empty prefab space receives a building or decoration.

| Setting | Default effect |
| --- | --- |
| `grassland`, `sandy`, `dirt` | Density for those plain terrain profiles. |
| `parkland`, `recreation`, `settlement` | Density for these named profiles. Settlement is intentionally the densest listed profile. |
| `fallbackByTerrain` | Density for profiles without their own density entry, based on the terrain below them. `default` is the final fallback. |

`densityTiers` controls building height preference, not how many buildings appear. Tags in `highTags`, `mediumTags`, and `lowTags` override profile defaults. Then `highProfiles` produces tier 3, `mediumProfiles` produces tier 2, and all other profiles produce tier 1.

### `buildingSelection`

| Setting | What it controls |
| --- | --- |
| `maximumHeightTier` | Highest filename-derived building-height tier the weighting system considers. |
| `minimumWeight` | Minimum chance weight for an allowed building asset. Keep at least `1`. |
| `baseWeight` | Starting preference for a building whose height matches the cell density tier. |
| `heightDistanceWeight` | How quickly preference drops when building height differs from the cell density tier. Higher numbers make districts specialize more strongly by height. |
| `commercialProfiles` | Profiles allowed to use commercial building assets, in addition to Market landmark cells. |
| `industryTerrains` | Terrain types allowed to use industry assets. |
| `industryProfiles` | Special profiles allowed to use industry assets. |

Building height is inferred from the letter count after the number in names such as `tile_building_1a.vmf`, `tile_building_1aa.vmf`, and `tile_building_1aaa.vmf`. Keep that naming convention for new ordinary building prefabs.

### `decorations` And `carparks`

| Setting | What it controls |
| --- | --- |
| `decorations.preferredTerrains` | Terrain types that prefer decoration placement over normal building placement. |
| `decorations.preferredProfiles` | Profiles with the same decoration preference. |
| `preferredChancePercent` | Decoration chance from `0` to `100` in preferred terrain/profile areas. |
| `standardChancePercent` | Decoration chance from `0` to `100` elsewhere. |
| `carparks.roadStraightChancePercent` | Optional extra chance from `0` to `100` that an eligible non-landmark straight-road recipe gets a carpark after coverage selection. Keep it at `0` for the most even distribution. |
| `carparks.coverageCellSpan` | World-grid width and height of each coverage region. The planner reserves carparks across each region in separate passes, preferring straight roads and using junctions only when needed. Junction carparks branch from a spare internal road arm and keep the central road exits intact. Keep it at least `1`; the current `3` spreads coverage more evenly than the former 4-cell regions. |
| `carparks.coverageCarparksPerRegion` | Number of eligible cells reserved per coverage region. The current value is `3`; selection is separation-aware, so a road-poor region can contribute fewer rather than cluster adjacent carparks. Keep it at least `1`. |
| `carparks.minimumCellSeparation` | Minimum Chebyshev distance between forced carpark cell coordinates. The current value is `2`, preventing side-by-side and diagonal carpark cells. Keep it at least `1`. |
| `carparks.minimumLaneTiles` | Minimum straight-tile length for each enabled carpark lane. The current value is `2`, so ordinary straight-road carparks use their full available lane length. Keep it at least `1`. |
| `carparks.maximumLaneTiles` | Maximum straight-tile length for each enabled carpark lane. It must be at least the minimum and no greater than the available distance to the cell edge. |

Carparks only replace an eligible building space beside a road. They do not overwrite roads, ramps, bridges, or landmarks. Before recipes are built, the planner makes separate world-wide coverage passes and reserves up to `coverageCarparksPerRegion` eligible cells per `coverageCellSpan` region. It rejects candidates closer than `minimumCellSeparation` under Chebyshev grid distance and prefers full straight-road layouts before compact junction sidecars. Forced straight-road coverage uses a through entrance and two full-length arms so it reads as a long carpark on the satellite. A junction carpark replaces an internal road-arm tile with a T-junction and occupies only adjacent free tiles, leaving the center intersection intact. Its one-sided lane is one tile long so it can terminate at the cell edge without cutting a perpendicular road. Reserved recipes use a stable `-cp.vmf` basename and the plan records each selected coordinate in `carparkCoverage`; planning fails if any reserved cell lacks a carpark entrance. The selected entrance layout and its lane length are deterministic for a recipe: through entrances create two arms, `_deadend_east` and `_deadend_west` create one, and the unsuffixed `_deadend` entrance creates no arms.

### `variants`

Variants prevent a highly repeated recipe from making every intersection look identical.

| Setting | What it controls |
| --- | --- |
| `usageThreshold` | A base recipe gets variants only when it is used more than this number of times. `15` means 16 or more uses. |
| `maximumPerRecipe` | Maximum number of layouts made for one repeated base recipe. The generator distributes uses as evenly as possible among them. The current limit is `2`. |
| `suffix` | Letter before the variation number in filenames. The current limit produces `-v1` and `-v2`. Keep `x` free for the future `_2x` prefab-footprint convention. |

Variants preserve road topology and transport pieces. They vary non-transport placement choices such as buildings and decorations. They are deterministic: the same city seed and settings produce the same variant assignments.

### `landmarkTemplatePatterns`

This table maps landmark names produced by the map generator to VMF file patterns. The key must remain the landmark's exact display name, including spaces and capitalization, such as `Petrol Station` or `Army Base`.

If a landmark has no matching VMF, the planner uses the normal compatible layout instead. `Market` has a special fallback to the first eligible commercial template.

### `filenameAbbreviations` (Advanced)

These tables shorten recipe filenames so they remain readable and practical in Garry's Mod map folders. They affect generated recipe filenames, the required-VMF list, and the filename key.

| Group | Example |
| --- | --- |
| `environmentProfiles` | `settlement` becomes `st`. |
| `topologies` | `road-crossjunction` becomes `rx`. |
| `orientations` | `missing-north` becomes `mn`. |
| `transportFeatures` | A bridge or on-ramp receives a compact transport segment. |
| `landmarks` | `petrol-station` becomes `ps`. |

`format` is the literal filename pattern: `zn_<environment>_<topology>-<orientation>[-<transport>]-d<density>_<landmarks>.vmf`. The bracketed transport segment is removed when a cell has no bridge or ramp feature. Macro layouts append `-m<width><height>-<template>-p<x>-<y>-q<quarter-turn>`; for example, `m22-c2a-p0-3-q0` means the `commercial_2a` 2x2 prefab anchored at `(0,3)` with zero rotation. Keep every code short, lowercase, and unique within its group. Changing this pattern or its abbreviations changes VMF names; rebuild and update any compile or map-loading references afterwards.

### Complete Filename Reference

This is the complete current set of keys in `filenameAbbreviations`. The names on the left are generator values; the short forms on the right are the text placed in recipe filenames.

| Environment profile | Filename code | Environment profile | Filename code |
| --- | --- | --- | --- |
| `grassland` | `gr` | `sandy` | `sa` |
| `dirt` | `di` | `settlement` | `st` |
| `commercial` | `co` | `financial` | `fi` |
| `radioactive` | `ra` | `safe_zone` | `sz` |
| `fortified` | `fo` | `military` | `mi` |
| `medical` | `md` | `emergency_services` | `es` |
| `religious` | `rl` | `service_station` | `ss` |
| `recreation` | `rc` | `parkland` | `pk` |

| Topology | Filename code | Topology | Filename code |
| --- | --- | --- | --- |
| `open` | `o` | `road-straight` | `rs` |
| `road-corner` | `rc` | `road-tjunction` | `rt` |
| `road-crossjunction` | `rx` | `road-deadend` | `rd` |
| `road-isolated` | `ri` | `motorway-straight` | `ms` |
| `motorway-corner` | `mc` | `motorway-tjunction` | `mt` |
| `motorway-crossjunction` | `mx` | `motorway-deadend` | `md` |
| `motorway-isolated` | `mi` |  |  |

`road-isolated` and `motorway-isolated` are reserved names for a road/highway record with no live connections. They do not have center-template entries because there is no road surface to draw; the planner falls back to compatible terrain/building placement.

| Orientation | Filename code | Orientation | Filename code |
| --- | --- | --- | --- |
| `none` | `n` | `all` | `a` |
| `vertical` | `v` | `horizontal` | `h` |
| `north` | `n` | `east` | `e` |
| `south` | `s` | `west` | `w` |
| `north-east` | `ne` | `east-south` | `es` |
| `south-west` | `sw` | `north-west` | `nw` |
| `missing-north` | `mn` | `missing-east` | `me` |
| `missing-south` | `ms` | `missing-west` | `mw` |

| Landmark | Filename code | Landmark | Filename code |
| --- | --- | --- | --- |
| `none` | `n` | `church` | `ch` |
| `hospital` | `ho` | `police` | `po` |
| `fire` | `fi` | `petrol-station` | `ps` |
| `bank` | `ba` | `army-base` | `ab` |
| `laboratory` | `la` | `bunker` | `bu` |
| `market` | `ma` | `leisure` | `le` |
| `park` | `pk` |  |  |

| Transport key | Configured filename code | How the placeholder is filled |
| --- | --- | --- |
| `none` | empty | No transport filename segment is written. |
| `bridge-vertical` | `bv` | Written directly. |
| `bridge-horizontal` | `bh` | Written directly. |
| `bridge-ramp` | `br<direction>` | `<direction>` becomes the lower-case bridge direction, such as `brn`. |
| `onramp` | `o<direction>` | `<direction>` becomes the lower-case exit direction, such as `oe`. |
| `onramp-dual` | `od<directions>` | `<directions>` becomes both lower-case exits, such as `odns`. |

The exact display-name keys in `landmarkTemplatePatterns` are `Church`, `Hospital`, `Police`, `Fire`, `Petrol Station`, `Bank`, `Army Base`, `Laboratory`, `Bunker`, and `Market`. Each value is a file-search pattern for that landmark's authored VMF. Keep the capitalization and spacing of the key unchanged.

## `atmosphere`

Atmosphere has two layers. `profiles` is client-side fog and colour correction exported with runtime world data, so it can vary by the player's logical cell without recompiling a reusable BSP. `lightingProfiles` is baked into recipe VMFs for VRAD, so changing it requires a VMF refresh and map compile. The generator keeps the sun direction from the base cell template; only sky material, direct light, and ambient fill vary.

The exporter selects `safe_zone` for safe-zone entrances, `dead_zone` for dead zones, `inner_city` for commercial/financial recipes, `outskirts` for grassland/sandy terrain, and `suburbs` otherwise. These five profile ids are required and must remain exactly named as shown, but their values are intended to be tuned.

### `profiles`

Each item is a named client runtime profile. The profile array is compactly indexed in the exported world JSON, so preserve profile order when possible to keep output diffs understandable.

| Setting | What it controls | Tuning guidance |
| --- | --- | --- |
| `id` | Stable profile identifier used by the exporter. | Keep the five required ids: `outskirts`, `suburbs`, `inner_city`, `dead_zone`, and `safe_zone`. |
| `fog.color` | RGB fog colour as `[red, green, blue]`. | Each value is `0` through `255`. Match it broadly to the selected sky. |
| `fog.start` | Distance in Hammer units at which fog starts. | Lower values make nearby streets haze sooner. Keep it below `fog.end`. |
| `fog.end` | Distance in Hammer units at which full fog range is reached. | Keep enough visibility to read road exits and fight fairly. |
| `fog.maxDensity` | Maximum linear-fog density. | `0` is transparent and `1` is fully opaque. Typical values are `0.5` through `0.9`. |
| `fog.stormMultiplier` | Visibility multiplier at full future storm intensity. | Greater than `0` and at most `1`; lower values make storms shorten fog distances more. |
| `colorCorrection.brightness` | Additive client brightness adjustment. | Small changes such as `-0.05` to `0.05` are normally sufficient. |
| `colorCorrection.contrast` | Client contrast multiplier. | `1` is neutral. |
| `colorCorrection.colour` | Client colour saturation multiplier. | `1` is neutral; lower values desaturate the scene. |
| `colorCorrection.add` | RGB additive colour correction as three decimal values. | Keep values small; this is a tint, not a light source. |
| `colorCorrection.multiply` | RGB multiplicative colour correction as three decimal values. | `1, 1, 1` is neutral. Use restrained channel changes for temperature or contamination mood. |

Changing a fog or colour-correction value requires only a runtime-world export:

```powershell
.\bin\export_runtime_world_data.ps1
```

Run the matching `-WorldProfile` export for alternate profiles. Test through normal map travel because fog is applied for each player from the profile of their persisted logical cell.

### `lightingProfiles`

Each named baked-lighting profile supplies the values written into a generated recipe's `worldspawn` and `light_environment` entity.

| Setting | What it controls | Tuning guidance |
| --- | --- | --- |
| `<profile>.skyname` | Source sky material name written to `worldspawn`. | Use a skybox available in Garry's Mod. The default profile names are known Source sky materials. |
| `<profile>.ambient` | `light_environment` ambient RGBA colour as `[red, green, blue, brightness]`. | RGB values are `0` through `255`; tune brightness before making large hue changes. |
| `<profile>.light` | `light_environment` direct sun RGBA colour as `[red, green, blue, brightness]`. | RGB values are `0` through `255`. Keep the base-template sun pitch/yaw unchanged across profiles. |

### `environmentLightingProfiles`

This table maps each planned recipe environment profile to a named item in `lightingProfiles`; `default` handles every environment not explicitly listed. The default mappings give commercial/financial recipes `overcast_day`, sandy/dirt recipes `dusty_day`, and radioactive/destroyed recipes `dead_zone` lighting. Every mapped value must be a key in `lightingProfiles`.

After changing a baked-lighting value or mapping, regenerate the active source VMFs and compile the affected release. `build_city.ps1` performs the refresh automatically unless `-SkipRecipeRefresh` is supplied.

```powershell
.\bin\build_cell_vmfs.ps1 -RefreshGenerated
.\bin\build_city.ps1 -CleanStagedCity
```

Generated recipes receive one to three deterministic `env_cubemap` entities. After a light, sky, fog, or geometry change is compiled, launch representative maps and run `buildcubemaps`; that in-game capture step is separate from VBSP, VVIS, and VRAD.

## `vmfBuild`

| Setting | What it controls | Warning |
| --- | --- | --- |
| `tileSize` | Distance in Hammer units between the centers of neighbouring tile instances. | Default `640` must match the physical width of normal tiletemplate VMFs. Do not use this to correct a misplaced model inside a source prefab. |
| `tileZOffset` | Vertical offset, in Hammer units, applied to every generated tile instance. | Default `0`. A non-zero value moves all generated chunks up or down together. |

## Common Problems

### The script says a settings file is missing

Run commands from the project root, or supply an explicit path:

```powershell
.\bin\generate_world_cells.ps1 -Preview -SettingsPath .\generator-settings.json
```

### The JSON will not load

Check for a missing comma, an extra comma after the final list item, curly quotation marks copied from a document, or a number that was placed inside quotes. Restore the backup if necessary.

### A generated VMF cannot find a tile

Check the relevant `terrainTemplates`, `topologyTemplates`, or `transportTemplates` path. It must exist below `templateDirectory`. Then check whether a `templatePatterns` filter accidentally excludes the new building or decoration.

### Roads look wrong in Hammer

Restore the canonical source VMF first. Then inspect the appropriate `rotations` entry and change the generated yaw only after verifying the source prefab's authored orientation. Do not move model offsets inside a native prefab to compensate for generator placement.

### Preview generation is too slow or produces too many recipes

Reduce `worldGeneration.profiles.preview.gridCells`, use a smaller `growthDepth`, lower `branchChance`, or raise `variants.usageThreshold`. Make one change, regenerate, and compare the preview key before changing more.

## Future 2x Prefabs

`_2x.vmf` is reserved for a future centered prefab that occupies four tile spaces but emits one `func_instance`. It is not implemented yet. The placement and validation plan is in [two_by_two_tile_templates_plan.md](two_by_two_tile_templates_plan.md).