# ZombieSim Generator Guide

This guide explains the city generator in normal game-making language. You do not need to be a programmer to adjust the safe settings. The main file is [generator-settings.json](generator-settings.json).

The generator creates a city plan, turns that plan into reusable 5-by-5 cell recipes, then creates VMF files for Hammer. It does not change the hand-authored tile templates in `tiletemplates`.

## Start Here

1. Make a copy of [generator-settings.json](generator-settings.json) before experimenting.
2. Change one group of settings at a time.
3. Make a preview first. Preview VMFs go to `generated/src_preview`, not the production `generated/src` folder.
4. Open the preview image or preview VMFs in Hammer and decide whether the change is worth keeping.

Settings use JSON. Text must be inside double quotes, items in a list need commas, and there must not be a comma after the final item in a list. Do not rename setting names unless this guide calls them advanced.

## Preview Workflow

Run these commands from the project root. This uses the small preview city and leaves production cell VMFs alone.

```powershell
.\bin\generate_map_grid.ps1 -Preview -Seed 1337
.\bin\plan_cell_templates.ps1 -Preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -Preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -Preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
```

`-Preview` makes the map generator use `mapGeneration.previewGridCells` and makes planning, building, and checking use `paths.previewCellDirectory` when no folder is supplied.

`-Seed 1337` is a one-run override. It does not edit the settings file. Keep a seed you like so you can reproduce the same city after changing unrelated assets.

Every generator script also accepts `-SettingsPath <file>`. This lets you keep named presets, such as a testing copy or a large-city copy, without repeatedly editing the main settings file.

## Preview Compile Check

Before committing to the long VVIS and VRAD production compile, run the fast structural check below. It runs VBSP against every preview recipe, so it validates VMF syntax, referenced instances, skybox materials, brushes, props, and BSP generation. It does not calculate visibility or lightmaps.

```powershell
.\bin\build_city_release.ps1 -Preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

This uses `paths.previewCellDirectory`, writes intermediate files to `paths.previewBuildDirectory`, stages test BSPs in `paths.previewReleaseMapDirectory`, and exports a separate runtime index at `paths.previewRuntimeWorldData`. It leaves `content/maps/city` and `zombiesim_world.json` untouched. Omit `-VBSPOnly` only when you want the slower preview VVIS and VRAD pass.

## Standalone Dens

Safe-room entrance cells remain normal logical city cells. They are not replaced by safe-room maps and safe-room maps are not added to the city grid or its graph. The city recipe for the entrance coordinate continues to compile as normal and should contain a `tile_saferoom` entrance plus its level-changing entity. Planning separately assigns that entrance to a reusable standalone safe-room map such as `zn_den_ra` or `zn_den_md_hospital`.

`build_cell_vmfs.ps1 -RefreshGenerated` copies the selected den VMF and its optional VMX sidecar unchanged into the active source directory. `build_city_release.ps1` compiles and stages those den BSPs alongside city recipe BSPs. The runtime index exposes the selected standalone map as `safeZone.map`; future entrance entities can use `ZM_World:GetSafeZoneMap(cell)` to obtain its `city/<den-map>` transition name. The city-cell APIs continue to return the safe-zone entrance cell, never the den itself.

Safe-room templates are selected by semantic biome/profile tags, never by `environment.terrain`. `settlement` is deliberately excluded because it describes the city entrance context rather than the destination. `radioactive` therefore selects `cell_ra_safezone.vmf` even when its city entrance cell happens to use grassland, sandy, or dirt terrain. `gr` means the `grasslands` default den style. The active destination codes are `gr`, `co`, `fi`, `ra`, `fo`, `mi`, `md`, `es`, `rl`, `ss`, `rc`, and `pk`. The existing `st`, `sa`, and `di` placeholder pairs are retained for future semantic profiles, but are not selected from entrance context or terrain labels.

District safe-room placement first prefers an available `Hospital`, `Army Base`, or `Bunker` landmark cell; when none is available, it selects the usual generic safe-room entrance. A supported landmark at the entrance takes precedence over the generic biome map, choosing `cell_<biome>_safezone_hospital.vmf`, `cell_<biome>_safezone_army_base.vmf`, or `cell_<biome>_safezone_bunker.vmf`. All current biome and landmark templates are copies of `cell_gr_safezone.vmf` plus its VMX sidecar, ready for independent Hammer editing. When multiple supported landmarks occur, `Hospital`, then `Army Base`, then `Bunker` is the configured precedence order.

All entrances selecting the same biome and landmark variant point to one compiled destination BSP. `build_cell_vmfs.ps1 -RefreshGenerated` refreshes each selected reusable map from its template and removes obsolete `zn_den_*` source maps from the active source folder. Edit the templates in `celltemplates/safezones`, not the copied `generated/src*` build inputs; normal `build_city_release.ps1` runs this refresh before compiling.

## Compile Monitoring and Profiles

The compiler prints its current map, stage, elapsed stage time, and remaining map count. It writes a `compile-report.json` beside the intermediate BSPs, for example `generated/build_preview/compile-report.json` for a preview. Each map record includes its stage status, exit code, duration, and stdout/stderr log paths.

The default `compilation.activeProfile` is `stock-gmod`. Its VBSP, VVIS, and VRAD tools are resolved from Garry's Mod's `bin` directory and retain the existing `-game <garrysmod>` arguments. Set a longer or shorter one-run budget without editing the settings file:

```powershell
.\bin\compile_cell_vmfs.ps1 -Preview -VBSPOnly -VbspTimeoutSeconds 120 -DeferredGraceSeconds 180
```

When a stage reaches its timeout it is deferred, not killed, and the next map starts. After all normal work has started, the runner waits for `deferredGraceSeconds`, then records the remaining deferred work in the report. By default it returns an error while any map is failed or unfinished. Pass `-FinalizeWithIncomplete` to finish after writing the report without waiting further. That option does not stage an incomplete release through `build_city_release.ps1`; it stops before copying BSPs or writing runtime data.

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
.\bin\build_city_release.ps1 -MapData .\bin\map_grid_64x64_seed_1337.json -PlanData .\bin\map_grid_64x64_seed_1337_template_plan.json -CleanStagedCity
```

`build_city_release.ps1` runs the sequential VBSP, VVIS, and VRAD compiler pass for every VMF in `paths.cellDirectory`, using `generated/build` as an intermediate folder. It copies only the recipe BSPs selected by the plan to `paths.releaseMapDirectory` and writes the compact gameplay world index to `paths.runtimeWorldData`.

The release script refreshes generated recipe VMFs first, so changes to the base cell template are included in the compile. Pass `-SkipRecipeRefresh` only when the selected source recipes have already been deliberately refreshed.

The BSP names identify reusable recipes, not coordinates. The runtime index maps every logical cell coordinate to its selected BSP name and contains its navigation graph, environment, safe zone, landmark, metro, and atmosphere data. Build a map transition name from `world.mapDirectory .. "/" .. cell.map`, which defaults to `city/<recipe>`. Read the staged index in Garry's Mod with `file.Read("data_static/zombiesim_world.json", "GAME")` after it is packaged at the addon root.

## What Is Safe To Change?

Safe first experiments are:

- `mapGeneration.seed`
- `mapGeneration.gridCells` and `mapGeneration.previewGridCells`
- Road, bridge, blockade, and carpark chances
- Building-density values
- District names, positions, radii, and colours
- City-name word lists
- `cellPlanning.variants.usageThreshold` and `maximumPerRecipe`

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
.\bin\generate_map_grid.ps1 -Preview -Seed 9001 -RoadDepth 5
```

uses seed `9001` and road depth `5` once, even if the JSON file says something else. The next run returns to the JSON defaults.

## `schemaVersion`

`schemaVersion` identifies the format of the settings file. Leave it as `1`. The scripts refuse a settings file with an unsupported version instead of guessing how to read it.

## `paths`

These are project-relative folders and files. Use forward slashes or backslashes consistently. Paths are relative to the project root, not the `bin` folder.

| Setting | What it controls | Notes |
| --- | --- | --- |
| `templateDirectory` | The root folder containing hand-authored tile VMFs. | Default: `tiletemplates`. Do not point this at generated cell VMFs. |
| `cellDirectory` | Production output folder for generated cell recipes. | Default: `generated/src`. Use only when ready to create production VMFs. |
| `previewCellDirectory` | Preview output folder. | Default: `generated/src_preview`. Used by `-Preview` on planning, building, and checking scripts. |
| `baseCellTemplate` | The border/base VMF inserted behind generated prefab instances. | Default: `celltemplates/template_border_s.vmf`. It must exist and contain a `cameras` block. |
| `scriptOutputDirectory` | Folder for PNG previews, JSON plans, required-VMF lists, and filename keys. | Default: `bin`. |
| `buildDirectory` | Intermediate compiler output folder. | Default: `generated/build`. The batch compiler copies VMFs here before creating BSP/VIS/RAD files. |
| `previewBuildDirectory` | Intermediate compiler output folder for `-Preview`. | Default: `generated/build_preview`. It is isolated from production BSP artefacts. |
| `releaseMapDirectory` | Release staging folder for compiled city BSPs. | Default: `content/maps/city`. The final release script copies only plan-referenced BSPs here. |
| `previewReleaseMapDirectory` | Release staging folder for `-Preview` BSPs. | Default: `content/maps/preview`. The preview runtime index uses `preview` as its map directory. |
| `runtimeWorldData` | Release staging path for the compact gameplay world index. | Default: `content/data_static/zombiesim_world.json`. Package it as root `data_static/zombiesim_world.json` and read it from the `GAME` mount. |
| `previewRuntimeWorldData` | Release staging path for the compact `-Preview` gameplay world index. | Default: `content/data_static/zombiesim_world_preview.json`. Keep it separate from the production index. |
| `safeZoneTemplateDirectory` | Complete standalone den-map templates. | Default: `celltemplates/safezones`. These are copied as whole VMFs, not assembled from tiles. |

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

This section creates the city-wide map layout and its PNG preview. A map cell is one playable VMF recipe. `gridCells` is the number of cells across and down, not the number of 640-unit chunks inside a cell.

### Basic Size And Seed

| Setting | What it controls | Good values |
| --- | --- | --- |
| `gridCells` | Width and height of a normal generated city. `64` means a 64-by-64 city, or 4,096 map cells. | Use `24` to `64` while testing. Larger values create many more unique recipes and take longer to inspect. |
| `previewGridCells` | Width and height used by `-Preview`. | `24` is a fast, useful default. Keep it smaller than `gridCells`. |
| `cellSizePixels` | Size of one cell in the PNG planning image. | `64` gives a 1536-by-1536 image for a 24-by-24 preview. This affects the picture, not Hammer tile size. |
| `seed` | Default random seed. The same seed and the same settings create the same layout. | Any whole number. Prefer passing `-Seed` for a temporary test. |

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
| `minimumStationSpacing` | Minimum straight-line distance, in map cells, between metro stops. | `6` avoids crowded labels. Lower values create more nearby stops. |
| `routeStopInterval` | Number of route cells between automatically considered metro stops. | Higher values make lines have fewer stops. Keep it a positive whole number. |
| `stopSuffixes` | Words used to name minor metro stops. | Add or replace simple names. Empty lists are invalid because a stop needs a name. |

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
| `previewExportsLayers` | Whether `-Preview` writes separate terrain, roads, buildings, highways, landmarks, safe zones, metro, grid, labels, and key PNG layers. `true` is recommended for troubleshooting. You can still explicitly request `-ExportLayers` for a non-preview run. |

## `cellPlanning`

This section turns the wide city map into a 5-by-5 grid of Hammer prefab instances for each unique cell recipe.

### Basic Cell Size

| Setting | What it controls | Important note |
| --- | --- | --- |
| `cellTileGridSize` | Number of prefab spaces across and down inside one generated cell. | Default `5` gives 25 prefab spaces. Use an odd number so roads have a true center tile. Changing it requires source border templates sized for the same layout. |

### `templatePatterns` (Advanced)

These regular-expression filters decide which VMF files from `templateDirectory` are eligible for each role. Paths are relative to `tiletemplates`, use `/`, and matching is case-insensitive.

| Setting | Eligible files |
| --- | --- |
| `genericBuildings` | Ordinary building and construction assets. Special landmarks are intentionally excluded. |
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
| `transport.onrampByDirection` | Yaw for motorway on-ramps that exit toward each direction. |

Use only `0`, `90`, `180`, or `270` for the current square tiles. Test any change in a preview VMF in Hammer. A wrong yaw can make an apparently valid road point into a building or a cell border.

### `environment`

`profilePriority` decides which special identity a cell gets when it has more than one environment tag. The first matching item wins. For example, with the default order, `radioactive` wins over `commercial` if both tags exist. Moving an item higher makes it override the entries below it.

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
| `carparks.roadStraightChancePercent` | Chance from `0` to `100` that an eligible non-landmark straight-road cell gets a carpark. |

Carparks only replace an eligible building space beside a road. They do not overwrite roads, ramps, bridges, or landmarks.

### `variants`

Variants prevent a highly repeated recipe from making every intersection look identical.

| Setting | What it controls |
| --- | --- |
| `usageThreshold` | A base recipe gets variants only when it is used more than this number of times. `15` means 16 or more uses. |
| `maximumPerRecipe` | Maximum number of layouts made for one repeated base recipe. The generator distributes uses as evenly as possible among them. |
| `suffix` | Letter before the variation number in filenames. Default `v` produces `-v1` through `-v5`. Keep `x` free for the future `_2x` prefab-footprint convention. |

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

`format` is the literal filename pattern: `zn_<environment>_<topology>-<orientation>[-<transport>]-d<density>_<landmarks>.vmf`. The bracketed transport segment is removed when a cell has no bridge or ramp feature. Keep every code short, lowercase, and unique within its group. Changing this pattern or its abbreviations changes VMF names; rebuild and update any compile or map-loading references afterwards.

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

## `vmfBuild`

| Setting | What it controls | Warning |
| --- | --- | --- |
| `tileSize` | Distance in Hammer units between the centers of neighbouring tile instances. | Default `640` must match the physical width of normal tiletemplate VMFs. Do not use this to correct a misplaced model inside a source prefab. |
| `tileZOffset` | Vertical offset, in Hammer units, applied to every generated tile instance. | Default `0`. A non-zero value moves all generated chunks up or down together. |

## Common Problems

### The script says a settings file is missing

Run commands from the project root, or supply an explicit path:

```powershell
.\bin\generate_map_grid.ps1 -Preview -SettingsPath .\generator-settings.json
```

### The JSON will not load

Check for a missing comma, an extra comma after the final list item, curly quotation marks copied from a document, or a number that was placed inside quotes. Restore the backup if necessary.

### A generated VMF cannot find a tile

Check the relevant `terrainTemplates`, `topologyTemplates`, or `transportTemplates` path. It must exist below `templateDirectory`. Then check whether a `templatePatterns` filter accidentally excludes the new building or decoration.

### Roads look wrong in Hammer

Restore the canonical source VMF first. Then inspect the appropriate `rotations` entry and change the generated yaw only after verifying the source prefab's authored orientation. Do not move model offsets inside a native prefab to compensate for generator placement.

### Preview generation is too slow or produces too many recipes

Reduce `previewGridCells`, use a smaller `growthDepth`, lower `branchChance`, or raise `variants.usageThreshold`. Make one change, regenerate, and compare the preview key before changing more.

## Future 2x Prefabs

`_2x.vmf` is reserved for a future centered prefab that occupies four tile spaces but emits one `func_instance`. It is not implemented yet. The placement and validation plan is in [two_by_two_tile_templates_plan.md](two_by_two_tile_templates_plan.md).