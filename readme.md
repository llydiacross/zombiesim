# Z-Nation

## Workshop distribution planning

The working `content` tree is **not a release package**. A read-only audit on
2026-10-05, during the clothing rebuild, measured **4,749,338,238 bytes
(4.75 decimal GB / 4.42 GiB)**:

| Surface | Working-tree size |
| --- | ---: |
| Materials | 3.016 GiB |
| Maps/navmeshes | 1.149 GiB |
| Models | 0.218 GiB |
| Audio | 0.033 GiB |
| Static data | 0.007 GiB |

Clothing alone occupied **3073.65 MiB**: **1423.12 MiB** belonged to the last
published 561-finish manifest, **1612.51 MiB** was hash-named clothing outside
that manifest, and **39.35 MiB** was prototype/other clothing. The unowned
category includes the rebuild's not-yet-published outputs as well as possible
interrupted-build leftovers; it is not an approved deletion list. Successful
catalogue publication prunes files owned by the previous manifest, but cannot
recover ownership of every interrupted-build orphan.

These textures already use **DXT5** (VTF format 15), not uncompressed RGBA.
A typical 1024-square layer with eleven mip levels is **1,398,360 bytes**.
Hundreds of finishes multiply full sheets: separate male/female shirts,
model-specific thigh prints and flat back-print icons, even where much of the
sheet is transparent. The current 866-finish plan needs up to **1725 layers /
2300.4 MiB** before deduplication, plus small VMT/metadata files. The sixteen
runtime render targets at that audit limited live composites, not shipped source texture size.
The subsequently approved citizen outfit pool has 96 targets, created on demand
(up to approximately 384 MiB RGBA storage, before other texture/material memory).
Do not reduce texture quality or remove mipmaps without a separate visual gate.

Maps include both production and preview assets (**239.92 MiB** city/generated,
**921.68 MiB** preview, **0.76 MiB** other/launchers). **Both city and preview
ship: preview is a player-accessible sandbox, as confirmed by the user.**
Do not include every historical recipe by recursively copying this tree. The current
preview required-recipe list contains 179 entries; standalone maps and
navmeshes need their own dependency coverage. Model size is mostly generated
skyline cells (**223.44 MiB**).

### Proposed addon boundaries

1. **ZombieSim Core:** gamemode/entity Lua, **both launcher BSPs** (so missing
   content can be diagnosed before city/sandbox deployment), bootstrap and canonical gameplay
   definitions, release/package compatibility manifest, and minimal essential
   UI. The current gameplay/entity code is approximately **2.33 MiB**.
2. **ZombieSim Common Content:** shared original models/materials, signage,
   UI/fonts/audio and required supporting assets.
3. **ZombieSim Clothing Content 01, 02, ...:** deterministic shards containing
   the exact clothing-manifest-owned VTF/VMT files. One virtual path has one
   owner; never duplicate differing files across packs.
4. **ZombieSim World Content 01, 02, ...:** both shipped profiles' selected
   required BSP/nav/model/map-material dependency closure, sharded by bytes
   without separating model companions or losing cross-cell skyline assets.

The implemented packaging tool keeps current source/build locations intact
and creates isolated, allowlisted staging directories. It inventories raw and
actual GMA bytes, rejects virtual-path collisions/missing dependencies, and
emits reproducible ownership/hash reports. The default **1 GiB raw per content
shard** is a conservative target, not a claimed platform limit. One MiB is
reserved for generated metadata; actual staged and packed sizes are checked
again. Uploaded/compressed bytes remain unknown until a deliberate publish.

The user reports an approximately **4 GB maximum per Workshop addon**; treat
that as a ceiling to avoid, not a safe target. The official
[creation guide](https://wiki.facepunch.com/gmod/Workshop_Addon_Creation)
describes a separate compression/upload step and oversized-addon failures,
but does not state a numeric limit. Reports distinguish compressed upload
limits from extracted/GMA sizes; verify the actual installed tool/Steam limits
and measure produced packages before publishing. No upload-limit probe or
Workshop publication was performed for this audit.

Required content must be declared explicitly in a Workshop collection/server
configuration and requested for clients; a collection on the server alone is
not proof that every clothing pack reached each client. See
[dedicated-server mounting](https://wiki.facepunch.com/gmod/Workshop_for_Dedicated_Servers)
and [resource.AddWorkshop](https://wiki.facepunch.com/gmod/resource.AddWorkshop):
the latter requests client downloads, **not server installation**.
Core/package versions must agree; missing mandatory packs should produce a
clear startup/deployment error rather than silently discarding clothing items.
Split addons improve update granularity, not total required download size.

Exclude development zoos/UV probes, source art/editor files (including
the existing packaged `.pdn`), bridge command files, logs and unowned hashes.
Stage audio at the addon-root `sound` path, not the current developer
`sounds` folder. Supplied artwork is not release-cleared; rights/provenance
remain an independent blocker. The Walker native DLL remains a separately
installed server component; Workshop cannot distribute it (see Walker below).

### Packaging commands

`workshop-settings.json` owns the static/common allowlists, profile selection,
one-GiB budget, provenance sign-off and final Workshop IDs. Defaults include
**city and preview**. Source and installed assets are never pruned or moved
by these commands:

```powershell
# Audit only: payload ownership, exclusions, dependencies and release blockers.
.\bin\build_workshop_packages.ps1

# Create isolated development packages and hash-verify every staged file.
.\bin\build_workshop_packages.ps1 -Stage

# Also build GMAs with bundled gmad and extract/hash-check every payload.
.\bin\build_workshop_packages.ps1 -Pack

# Fixtures: exact byte thresholds, companions, collisions, missing assets,
# deterministic identity, source preservation and real gmad round trips.
.\bin\test_workshop_packages.ps1

# Independently recheck a completed output, using stageRoot from the report.
.\bin\test_workshop_packages.ps1 -StagedDirectory '.\generated\workshop\<release-prefix>'

# Strict release gate; currently expected to fail until blockers are resolved.
.\bin\build_workshop_packages.ps1 -Release -Pack
```

Reports live at `generated/workshop/inventory-report.json` and, after a
successful build, `<release-prefix>/package-report.json`. Staging uses a
short prefix of the full SHA256 release identity to stay within native Windows
path limits; the full identity is retained in manifests/markers/reports.
Existing staging is refused, not overwritten. Interrupted staging remains
for inspection; cleanup is a separate, explicitly scoped action. Temporary
extraction-verification directories and test fixtures are cleaned automatically.
For a narrower **developer-only** inventory, pass `-WorldProfiles preview`;
this does not change the default two-world shipping contract.

Core owns the canonical static registries. Clothing shards use the current
catalogue ownership manifest, not a directory-wide copy; current fixed
Wardrobe/diagnostic finishes remain because the shipped sandbox uses them.
Maps come from each runtime world's cells/safe zones and launcher, keeping
nav companions together. Skyline recipes/snow/towers/detail retain custom
model companions; mounted engine assets are reported as external requirements,
not copied. Local-map images are limited to referenced recipes. Root audio
and its staged registry are transformed together; developer source paths remain
unchanged. Staging also replaces the old hardcoded core Workshop ID with the
configured ID (blank until assigned), without editing the source descriptor.

Every staged pack has a content-revision marker; core additionally binds the
complete release identity. Unchanged content revisions remain compatible across
core-only updates: do not republish every content addon just to update core.
Packaged core enables strict
startup file-size/ownership and marker/version validation in both realms,
requests all required packs (including core's static content) for clients on the server, and blocks character
deployment if server/client validation fails or the active profile is not
included. A packaged core with its manifest removed fails explicitly; loose
development with no distribution manifest retains existing behavior.
Offline SHA256 validation covers all files and generated metadata; runtime
size/marker checks are compatibility diagnostics, not cryptographic proof.
Run `zn_test_distribution` and `zn_test_music` for the focused runtime suites.

### Launcher subscriptions and first publication

The launcher checks required Workshop entries when it opens. **Content Addons**
shows per-pack subscription and mounted/downloaded state, with **Open Workshop**
buttons for real IDs and **Recheck Content** to rerun compatibility checks.
Deployment rechecks mounted files/revisions before sending the select request.
Subscription is advisory: server-downloaded or local packages can be usable
without a personal subscription; being subscribed does not prove files are
downloaded, enabled, current or mounted. Compatibility remains the deployment
gate. Subscriptions are never changed automatically. After subscribing/enabling,
finish Steam downloads and restart/rejoin if the addon has not mounted.
The content page uses the launcher's existing keyboard/back/exit lifecycle,
not another popup competing with optional-component briefings.

Temporary IDs in `workshop-settings.json` are symbolic **`pending:<package-id>`**
values. The builder places them in a separate `workshopIdPlaceholder` field
and leaves the actionable `workshopId` empty. They are never passed to
`resource.AddWorkshop`, `steamworks.IsSubscribed` or `steamworks.ViewFile`;
there is no invented numeric ID that could refer to somebody else's addon.
Strict release builds reject pending IDs. New shards automatically receive
pending labels until their own actual IDs are assigned.

**Adding content:** keep authoring under the existing content/source pipeline.
Already-owned catalogue/world assets and supported common material directories
are picked up automatically on the next build. A new content domain or shared
asset dependency must be added to the relevant allowlist/dependency owner;
check the exclusion report so unrelated developer files never ship silently.
The builder **packages, hashes and verifies; it does not upload**. Uploading is
a deliberate authenticated operation after provenance and release checks.

**Bootstrapping IDs without a circular dependency:**

1. Create one Workshop item per stable package identity using only an original,
   minimal reservation payload and a compliant512-square JPEG icon. Keep the
   item **Private**, verify visibility on its Workshop page, and do not upload
   uncleared artwork just to obtain an ID. No reservation/upload has been made
   by this implementation.
2. Steam assigns a `PublishedFileId` when creating the item. Record the
   returned ID (also the `id=` number in its Workshop URL). Put core's real
   string ID in `coreWorkshopId`, and the other IDs under their matching
   `workshopIds` keys, replacing `pending:` values. IDs cannot be chosen locally.
3. Build the cleared release with those IDs. The core descriptor and dependency
   manifest now contain the actual IDs. **Update the existing private items**
   using `gmpublish update -addon "<package.gma>" -id "<assigned-id>"`, rather
   than creating new items on each build; updates retain their item IDs.
4. Test private content with accounts that actually have access. Private items
   are not a generally accessible public dependency; public-server collections/
   downloads must not depend on inaccessible private items. When ready, make
   required packs available to the intended audience, verify collection/client
   downloads, then publish the core entry. Links/requirements are useful but
   do not replace actual mounted-file/version checks.

Sources:
[Facepunch creation workflow](https://wiki.facepunch.com/gmod/Workshop_Addon_Creation),
[updating the same item](https://wiki.facepunch.com/gmod/Workshop_Addon_Updating),
[Steam item creation/returned ID](https://partner.steamgames.com/doc/features/workshop/implementation#Creating_a_Workshop_Item),
[IsSubscribed](https://wiki.facepunch.com/gmod/steamworks.IsSubscribed),
[GetAddons](https://wiki.facepunch.com/gmod/engine.GetAddons) and
[ViewFile](https://wiki.facepunch.com/gmod/steamworks.ViewFile).

Launcher follow-up validation: **46 packaging fixture checks** passed, including
placeholder-to-real-ID strict-release staging and preservation of the assigned
core ID. GLua **175/0**, live distribution **9/9**, music **10/10**, static data
**18/18** pass. The user approved the **Content Addons / Recheck / Back** page
in the loose preview installation. Actual published-ID subscription/download/
mount behavior awaits the real Workshop items and clean installation tests;
temporary labels are not claimed as live Workshop verification.

**Current release gates:** rights sign-off, final non-duplicate Workshop IDs,
all required navmeshes, a current explicitly profiled city runtime export and
city skyline manifest, verified external game mounts, and a clean client/server
mount/download/deployment test. No production regeneration, Workshop publication
or live installation migration is implied by a development package build.

**Earlier verified development build (2026-10-05, before launcher/subscription
follow-up):** `generated/workshop/b89bee899d6e`
contains seven extracted-and-SHA256-verified GMAs. Total staged payload/
metadata is **3,737,841,516 bytes**; total GMA size is **3,738,385,682 bytes**.
These are not compressed upload measurements.

| Addon | Actual GMA MiB |
| --- | ---: |
| Core | 12.30 |
| Common Content 01 | 36.85 |
| Clothing Content 01 / 02 / 03 | 1023.14 / 1021.80 / 89.38 |
| World Content 01 / 02 | 1021.54 / 360.20 |

Focused fixtures passed **37/37**, independent actual-output checks
**6414/6414**, GLua **175 files / 0 failures**. After a clean same-map preview
reload, loose-development live suites passed **distribution 8/8, music 10/10,
static data 18/18, inventory 51/51**. The exclusion audit reports **1505 files /
480,176,180 bytes**, including **612 unowned clothing files / 408.13 MiB** after
publication; none was deleted. Clean isolated mounted-package/download testing
is still pending. The obsolete offline package build created during this task
was removed after validation; no source or installed asset was pruned.

## Launcher characters

On `zn_preview_start` or `zn_city_start`, the optional Volt/Walker briefings precede the character menu. The launcher is not yet deployed gameplay: load an existing slot or create one of three profile-specific survivors, complete any required appearance, and deploy the character. Only after the server accepts deployment does play continue into the character's saved city cell or safe zone; for a gameplay test, then enter the intended den or cell. Choose a name, citizen model/appearance, profession, and spend exactly ten starting attribute points when creating a survivor. A migrated slot-1 survivor requires an appearance before deployment. Deleting a slot requires typing its name. Options in the launcher use the same settings controls as the in-game radial menu; Exit disconnects. Keyboard navigation supports Up/Down, Enter and Escape.

The main menu draws an original procedural globe at the authored `menu_globe` marker. Each slot's origin dot uses the profile's geographic anchor in `content/data_static/launcher_scene.json`; selecting a slot turns the globe to that dot. The profile anchors are fictional presentation coordinates, **not** a real-world geolocation of generated cells. The globe defaults to low detail (`zombiesim_globe_quality 0`); enable **High-detail menu globe** in Options (or set the convar to `1`) for a finer mesh. No external imagery or copied textures are packaged.

Credits uses the same maintained JSON file for its crawl. It hides the menu and cuts to `credits_camera`, then cycles through the four named dancers; Escape, Enter, Space, or click returns to the menu. The server supplies camera poses, dancer entity indexes, and credits-area visibility; credits fog is confined to the credits view. For camera tuning, `zombiesim_credits_shot gman` (or `alyx`, `barney`, `kleiner`; empty to unlock) and `zombiesim_credits_debug 1` expose the shot and obstruction trace. Admins can run `zombiesim_launcher_flexes` to inspect available model flex controllers. The dancing, flex replication, camera clearance, and presentation still require live-client verification.

For admin development sessions, `zombiesim_dev_autoload_character 1` (or slot 2/3) attempts to deploy that existing, appearance-complete slot after the dependency briefings; `0` disables autoload. It does not create a character. Run `zn_test_characters` in an admin console for server-side character storage and validation checks. Player models/hands, menu camera framing, first-run briefings, and cross-map transitions still require verification in a running client.

Character persistence uses a profile-specific three-slot roster. Existing per-profile player data is assigned to slot 1 at first startup, retaining the original player-owned table layouts while replacing the owner key with an immutable character ID. Garry's Mod blocks Lua from reading `sv.db`, so startup requires a verified logical SQLite export (every schema statement and row, checked by row count) at `garrysmod/data/zombiesim/backups/sv_db_alpha_2_8_5_backup.json`; if backup or migration fails, character spawning is blocked rather than saving under the wrong identity. Back up your installed database separately before testing this milestone, then check the server's migration row counts and verify an existing save in-game. The migration and suite have **not** yet been exercised against the installed database.

Please read the [GDD](docs/gdd.md) for an overview of the game's design and mechanics.

Work in progress

## Camera aiming and HUD size

Skybox background activity adds orange explosion flashes, rising blast smoke, muzzle flashes and moving tracer bursts. Persistent skyscraper fires are anchored to actual vertical wall triangles, including stepped upper floors, rather than model bounds. Activity is cosmetic and silent: it causes no damage, spawns no gameplay entities, and changes no city lighting. The **Skybox fires, smoke and distant combat** toggle controls all of these effects. Limits are 24 activity sites, at most 2 simultaneous explosions and 2 gunfire bursts, and 8 additional facade fires within 8 cells. Heavy fog and map captures suppress combat activity. Preview admins can use `zombiesim_dev_skybox_activity` for a 12-second accelerated visual check; `zombiesim_skybox_status` reports sites, active effects, facade fires and tracer counts. No BSP rebuild is needed.

Beyond the world grid, the skybox coast renders a rock embankment at each city edge. Below it, a noise-shaped sand beach with rocky outcrops descends into shallow turquoise water that deepens with distance. Additive ripple layers drift across the water, and foam crests roll toward the shore along depth contours. Ripple and foam textures are procedural 256² render targets generated once at startup. The geometry is built only when the sky placement changes, in chunked static meshes (about 40 ms at a shore cell), and is drawn in the fogged sky pass, so it does not touch collision, puddles, snowfall or map captures. Snow cover lightens the beach and rocks. `zombiesim_skybox_status` reports coast quad, mesh, build-time and texture readiness. For preview self-review, `zombiesim_dev_capture <label> [pitch yaw [x y z]]` saves a PNG plus skybox/clothing diagnostics under `data/zombiesim/screenshots/`. With pitch and yaw, it renders an eye-height view in that direction; optional coordinates move only the capture camera, never the survivor. At most eight requests queue for successive rendered frames, so a bridge dispatch acknowledgement is not proof the PNG has been written.

Each skybox edge has its own terrain:

- **North:** rolling grass hills.
- **East:** a snow-capped mountain range, high enough to be visible from every city cell, including the far west.
- **South:** low flatlands.
- **West:** the ocean coast described above.

The north-east and south-east corners blend the neighbouring landforms. The ocean takes both western corners, and north and south land lowers to beach height as it meets the west shore. The terrain uses grass with height- and slope-weighted rock and snow overlays, takes on fog brightness, and receives weather snow cover. It is built once per map load in static meshes (about 150 ms, around 42,000 quads) and is purely cosmetic. Preview admins can run `zombiesim_dev_skybox_edges` for the cardinal, corner, seam, and visibility regression; it writes `data/zombiesim/skybox_edges.json`. No BSP rebuild is needed.

Options in both the launcher and radial menu now include **Skybox - live tuning**. Adjust **Skybox fog amount** (0-2, default 0.8), **fog distance** (0.5-3, default 0.9), **horizon haze** (0-1.5, default 0.5), **distant tower fog** (0-1, default 0.8), and **model brightness** (0-2, default 0.25). Values save locally and update immediately without a map rebuild or reload. Matched lighting must be enabled for model brightness to apply. Fog amount thickens the sky beyond the city fog: 0 continues the city fog exactly, 1 is halfway to opaque, and 2 is opaque. The sky is never clearer than the city fog. On dark-lit cells, the measured cell lighting darkens the shared city and sky fog colour, so distant mountains and buildings don't glow; daylight cells keep the profile colour. Distant tower silhouettes follow the fog brightness. Under pale fog (outskirts, suburbs, and safe zones such as the Storm Drain) they share the neighbour scenery's fog curve, so they fade into the haze instead of standing out black. Under dark fog, and on dark-lit cells, they keep the plain **distant tower fog** value. Nearby detail rings, clouds, props/wrecks, and fires/smoke are also exposed there. Lowering fog/haze may expose the scenery boundary; playable-city fog density is unchanged. Quality presets still control detail/clouds/props/fires but leave the five presentation sliders and matched-lighting preference untouched. **Reset skybox fog / lighting tuning** resets only those presentation settings, not quality or other preferences. **Copy skybox tuning values** copies the current values for sharing. `zombiesim_skybox_status` and fresh atmosphere diagnostics include the tuning snapshot.

Middle-click toggles the overhead and orbit camera. Scroll into shoulder view for mouse-look with full horizontal and vertical weapon aiming. **Hold Z** in shoulder view to fix the camera direction and aim with a visible, freely moving cursor; release Z to ease back to normal shoulder aiming. Middle-click returns to overhead view; scrolling out returns to orbit mouse-look. Point-and-click aiming never enables the Derma mouse cursor, so normal firing remains available and menus retain their own mouse focus. The pistol uses the normal player aiming animation driven by the same aim angles as the shot.

Options (in the launcher or the in-game radial menu) includes **Compass height** and **Minimap size** sliders. Both update immediately and are saved locally. Console equivalents are `zombiesim_compass_height` (0.55-1.5, default `0.55`) and `zombiesim_minimap_size` (0.7-1.75, default `1`). **Mouse sensitivity** defaults to `0.3`. Existing saved preferences are preserved. Compass height changes the available label rows without shrinking text; the XP bar and notifications follow its lower edge. Minimap size changes its on-screen map area, not its zoom, and keeps the survival labels readable. The panel above the minimap shows current-cell danger as 0–6 stars. A Fallout-style top-right radiation meter adds the fictional 0–10 Sv cell baseline and 0–10 Sv radiated-walker proximity, up to 20 Sv, and hides when that value rounds to zero; the world-map cell inspector retains danger stars and a cell-only 0–100% intensity readout. Damage from a directional source produces a brief, damage-scaled arrow near the screen perimeter; damage without a reliable direction produces a subtle perimeter pulse. Both feedbacks fade, avoid reserved HUD panels, and are suppressed while a menu is open or the player is in a safe zone. The aim crosshair is neutral gray without a valid target, gold for searchable loot or a nearby dropped-item crate, and red with corner ticks for a live enemy; its color no longer reflects player health. Both Options screens scroll when needed.

## Firearm presentation

Inside a safe zone/den, equipped firearms and melee weapons are holstered: world/view models, hands, weapon/ammo panels, crosshair and hit markers are hidden. Attacks and reloads are blocked server-side; entering cancels pending reloads without consuming ammunition. Equipped slots and clips are retained and weapons automatically return when leaving. City entrance cells outside the den remain combat-enabled; inventory management remains available inside.

The shared hitscan base sends one server-confirmed presentation event per shot. Pistol/SMG, 5.56/7.62 rifle, shotgun and sniper profiles select mounted casing models and flash/smoke sizes. The .50 profile uses a scaled mounted rifle casing; no new Valve assets are copied into the addon. The flash uses a separately tinted yellow material and is centered four units forward along the muzzle attachment, without shifting smoke or bullet origins. Tracers converge from the world-model muzzle to each actual spread pellet's engine trace endpoint. Named muzzle/ejection attachments are preferred, with attachment 1 and an aim-relative ejection position as model fallbacks.

CSS firearms use their mounted weapon-specific firing and reload sounds instead of generic HL2 pulse-rifle/crossbow sounds. Pump/bolt firearms also play their cycling sound after a successful shot. Aim recoil accumulates per weapon, recovers exponentially, and is capped at 4 degrees upward and 1.5 degrees sideways; shots and the impact crosshair share the same recoil offset. Den shots remain level with lateral recoil. Damage, range, random spread, ammunition consumption and reload timing remain unchanged; bullet physics force is now class-specific.

The server's close-range firing impulse scatters at most eight loose physics props per shot within 96 units of the firing origin. Only movable, unparented, unconstrained props weighing at most 12 kg qualify; loot props, doors, ragdolls and characters are excluded. Walls block the impulse, each prop has a 0.1-second cooldown, and additional speed is bounded by a 180-unit/second budget. This is a restrained gameplay effect, not a realistic simulation of firearm blast pressure.

For an admin-only preview check, `zombiesim_dev_muzzle_blast_probe start` places three green loose cans and one red frozen control on clear ground ahead. Fire away from them while staying nearby. `status` reports displacement and whether a firing impulse reached each can; `clear` removes only the tracked test props. They also automatically disappear after 180 seconds. No inventory or saved world data is changed.

Each client keeps at most 32 shot effects and 32 casings. Flash lasts 0.045 seconds, tracers 0.08 seconds, smoke 1.4 seconds and casings 2 seconds. Smoke is a thin, curling ribbon sampled from the rendered muzzle for up to 0.375 seconds, with at most 16 points per shot (512 total). New shots stop the previous shot's emission on that weapon; emitted points continue rising and fading in world space rather than following the moving gun. Casings bounce against map brushes without affecting gameplay physics. Fine detail is culled beyond 1,800 units, all shot effects beyond 4,096; cleanup also runs on map cleanup and Lua auto-refresh. `zombiesim_weapon_effects_status` prints the current client counts (both should return to zero after firing stops).

Run `zn_test_weapon_effects` for profile/asset, trace, ballistic, single-shot and dry-fire/reload contracts, plus `zn_test_weapon_catalog` and `zn_test_inventory`. These do not replace live firing checks in overhead, orbit, shoulder, hold-Z and den views.

Short-lived dust appears only on concrete, dirt, sand, wood or tile impacts and nearby brush ground. It supplements the engine's normal impact effects rather than replacing them; no dust is added for flesh, metal, glass, water or sky. Each shot retains at most four dust puffs for 0.45 seconds (128 globally under the shot cap). The effects suite also checks recoil recovery, blast exclusions/walls/bounds, mounted audio and dust surface selection without moving live world props.

## AFK menus

Choosing **Inventory**, **Scoreboard** or **Options** from the Tab radial starts a three-second server countdown ("OPENING INVENTORY 2.4"). You can move during it; pressing Tab again or taking any damage cancels it. When it finishes the menu opens and you are AFK: zombies drop you as a target and cannot damage you. **Cheats** opens instantly and makes operators AFK at once. Switching between AFK menus does not restart the countdown. Closing the last AFK menu leaves AFK with three seconds of protection, shown as "PROTECTED"; firing ends it early, moving does not. Death, respawn and cell/den transitions clear all AFK state without grace. The server owns the state (`gamemode/sv_afk.lua`); the client (`gamemode/cl_afk.lua`) reports when the last menu closes and sends a heartbeat, so a client that stops reporting loses AFK after six seconds. The world map and den service windows are not AFK menus.

# Folder Structure

- `tiletemplates/` and `celltemplates/` contain authored VMFs, including launcher sources in `celltemplates/launchers`.
- `content/` contains distributable addon data read by Garry's Mod, including flat `content/maps` BSPs, thumbnails, materials, and runtime world indexes.
- `generated/` contains compiler artifacts, reports, intermediate BSPs, developer zoos, and launcher build output under `generated/launcher_build`.

These are compiled reusable recipe maps for the city. A recipe can serve more than one logical city cell, so its filename does not identify a coordinate.

`content/data_static/zombiesim_world.json` maps every cell coordinate to its selected recipe BSP and provides the navigation graph and gameplay metadata. Build a transition map name from `world.mapDirectory .. "/" .. cell.map`; it is the authoritative lookup for map transitions.

Generated recipe BSPs use compact `zz_<profile>_<hash>` basenames, for example `zz_city_5b87e00b9082-v1.bsp`. Runtime staging is flat under `content/maps` and engine maps; launcher maps retain `zn_city_start` and `zn_preview_start`.

# Powershell Commands

Run these from the project root. The preview profile is isolated from production and stages its playable maps flat under `content/maps`.

## Clothing model discovery

Clothing-workflow discovery is read-only: `.\bin\inspect_clothing_models.ps1` inspects the fifteen installed citizen player models through mounted VPKs, reporting materials, bodygroups, UV bounds/hashes and texture dimensions under `generated\clothing_preview` without extracting models/textures. `.\bin\test_clothing_model_inspection.ps1` regenerates and validates those findings. This is not yet a clothing asset builder or an equip/appearance implementation; the active tracker records the shared-body-sheet and equipment-contract limits.

Build the original garment UV calibration atlas with `.\bin\build_clothing_uv_probe.ps1`, then run `.\bin\test_clothing_uv_probe.ps1`. Only one diagnostic texture/material is compiled and staged into content and the development game root; no mounted artwork/models are copied. After reloading a confirmed preview map, `zombiesim_dev_clothing_uv on [current|male|female]` through the bridge creates two temporary non-solid fixtures: a stock citizen and the same mesh with the coloured A1-H8 grid on its combined body sheet. Use front/back/side views to establish garment regions and orientation; `off` removes both and they expire after five minutes. It does not change player appearance, equipment or saved inventory. The atlas PNG is at `generated\clothing_preview\uv_probe\source\uv_probe.png`; it is a diagnostic, not an accepted shirt/pants finish or a universal UV guide.

Build the original masked finish prototype with `.\bin\build_clothing_prototype.ps1`, then run `.\bin\test_clothing_prototype.ps1`. Editable colours, UV-aligned image/logo inputs and independently preserved/coloured inner-shirt regions live in `assets\clothing\prototype.json`. `assets\clothing\prints.json` provides chest-left/right, sleeve-left/right, small-back, centre-front and full-back presets using the supplied deer PNG; aspect ratio/transparency are retained and split-back UV islands share one image. See [the clothing artist workflow](docs/clothing_artist_workflow.md). Reload the confirmed preview map and use `zombiesim_dev_clothing_uv on male|female shirt|pants|both [style]` to compare native clothing with artwork on `male_03` or `female_01`. `zombiesim_dev_clothing_capture <label> front|back|left|right|neckline` automatically captures the second fixture without moving your survivor. Placement searches nine nearby clear areas and rejects blocking collision before capture; inspect the PNG for non-solid visual occluders too. This is a fixture-only prototype, not clothing items/equipment or an accepted universal mask. User-supplied deer artwork has not been cleared for release.

The `repeat` style tiles the supplied image across both axes, not just coloured checker squares. `prints.json` has separate shirt/pants motif sizes, spacing and offsets. Build only these layers with `.\bin\build_clothing_prototype.ps1 -PrintStyles repeat`; select `zombiesim_dev_clothing_uv on male|female shirt|pants|both repeat`. Both-axis coverage, exact repeat pixels, exclusions, spacing and staged VTF alpha are covered by the prototype test. Automatic filename discovery and bloody/zombie variants remain pending.

The `pants_leg` diagnostic style adds a single-image canvas down the front of one pant leg, selected by the user instead of a thigh/pocket badge. `prints.json` has separate verified male/female UV placements; use `.\bin\build_clothing_prototype.ps1 -PrintStyles pants_leg`, then `zombiesim_dev_clothing_uv on male|female pants|both pants_leg` after preview reload. The other leg keeps the base pants fabric; the native shirt, skin and footwear are unchanged in pants-only mode. The user selected uncropped, aspect-preserving fitting: tall artwork fills the leg, while wider artwork stays shorter and centered. This is not yet an automatic filename-derived wearable item.

Fixed-finish equipment now adds `itemPrototypeShirt` and `itemPrototypePants`, using original base artwork from `prototype.json`. SHIRT/PANTS occupy slots 5/6 independently of weapons 1-3 and armour 4, with Inventory equip/unequip/drag-drop and existing character/profile persistence. Use `zn_give_item <itemId>` and `zn_equip_item <itemId|instanceId>` in an admin preview; `zn_inventory` includes model compatibility and clothing selections. Only male_03/female_01 render these finishes; unsupported models retain native clothing. Six separate equipment material patches/targets prevent diagnostic fixtures changing survivors. Live male/female restoration, Inventory/scoreboard pixels and immutable real-corpse rendering are verified; representative performance and catalogue acceptance remain separate.

For preview-admin clothing inspection, the bridge supports `zombiesim_dev_ui inventory|scoreboard|close` through the existing window owners. A `zombiesim_dev_capture <label>` without camera angles captures these open windows after VGUI; explicit camera captures retain the world-only path. Requests still capture at most once per frame; JSON records `afterVGUI`, `frameNumber` and UI receipt/window state. `zombiesim_dev_clothing_model male|female|unsupported|restore` temporarily selects male_03, female_01 or unsupported male_01 on a deployed living survivor without saving character appearance. It retains the original model/skin/bodygroups for `restore`, rejects a changed character scope and updates native hands. Restore before unrelated testing; a same-map reload also reapplies persisted appearance. These commands do not grant/remove items.

Generate mesh-aligned wireframe guides with `.\bin\inspect_clothing_models.ps1 -UvGuideModels @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')`. The inspection test also generates/validates these two guides. The tool reads matching MDL/VVD/VTX root-LOD topology in memory and draws UV edges over the same A1-H8 grid at `generated\clothing_preview\uv_male_03.png` and `uv_female_01.png`; no mounted model or base texture is written out. These two layouts are visibly different. Wireframe guides are inspection products, not approved garment masks or proof that arbitrary artwork fits every citizen.

For filename-driven clothing, run `.\bin\build_clothing_catalogue.ps1 [-PlanOnly]`
and `.\bin\test_clothing_catalogue.ps1`. Optional artwork suffixes `_dark`/`_light`
select contrasting lighter/darker fabric palettes; `_notblack` and other
`not<colour>` tags exclude named backgrounds. They combine with explicit colours
and placement tags and apply to single-image and X/Y repeating variants.
Use `_chest` for a centred upper-chest logo or `_front`/`_front_full` for the
larger torso print. Untagged shirts include both.
Untagged artwork defaults to colourful yellow/blue/orange/red/teal/green/pink
shirt backgrounds; explicit `_light`/`_dark` rules are unchanged. Single pants
graphics now have separate left/right thigh choices (`pants_leg` and
`pants_leg_right`); both are raised above the former knee-centred placement.
Combined front-and-back shirts were removed at the user's request.
Contradictions or exhausted palettes fail explicitly. See the
[clothing artist workflow](docs/clothing_artist_workflow.md#filename-driven-catalogue)
for examples and contrast limits. Generated wearable/cache live acceptance remains pending.

Preview admins can open **WARDROBE** from the Tab radial menu or with
`zombiesim_dev_wardrobe` (`zombiesim_dev_ui wardrobe` through the bridge).
It lists available clothes as actual print/fabric swatches beside a rotatable
male/female model. Selection dresses only that window model; no inventory or
appearance is saved. Search, shirt/pants filters and native-garment reset buttons
are included. See [Wardrobe controls](docs/clothing_artist_workflow.md#preview-wardrobe).

`assets\clothing\fabrics.json` defines the bounded original stripe/check/tie-dye
shirt library and restrained pants finishes, generated alongside image families.
It now expands to 206 fabrics across fourteen colourways and distinct shirt/
pants treatments. Dye is rendered per texel at 1024 square (not 8x8 colour
blocks), with spiral, rings, cloud and marble styles. Stable original IDs and
the 896-finish limit are retained; the user-approved runtime outfit pool now has
96 shared targets. Use `.\bin\build_clothing_catalogue.ps1 -PoolOnly` to refresh
only pool patches/ownership metadata while retaining existing finishes and textures.
All fifteen verified group01 citizens can use the full catalogue. Each walker
has an independent stable outfit seed (ticket identity for ticketed walkers);
rebels retain native bloody appearance. Corpse and severed-piece copies keep
their original garments. Composition is frame-budgeted, not a whole-crowd
synchronous build.
Run `.\bin\test_clothing_fabrics.ps1 -ValidateBuilt` after the catalogue build.
`.\bin\test_clothing_catalogue.ps1 -ValidateBuilt` checks every image finish,
flat back-print icons and owned staging hashes. The model inspector also writes
torso topology for continuous back-print/fabric/motif projection; run
`.\bin\test_clothing_back_projection.ps1` after inspection. Inspect the corrected
backs and smooth dyes in a freshly reloaded preview before visual acceptance.
Preview-only `zombiesim_dev_test_clothing_pool` exercises actual client texture
capacity/recovery and immutable gore-reference pinning; inspect its asynchronous
`data/zombiesim/clothing_pool_tests.json` result, not just bridge dispatch.
The suite now advances the capacity and citizen tests across frames; the initial
`running: true` report is not a completed result. `zn_gore_probe crowd` creates
fifteen harmless citizen fixtures; `zn_gore_probe crowd male_03` checks outfit
variety on the same model, and appending `native` provides a control.
Remove only these owned fixtures with `zn_gore_probe off`.
See [fabric controls and pool validation](docs/clothing_artist_workflow.md#original-fabric-library).

## Sky browser and Options

Options groups settings under nine collapsible headers, including Interface,
Camera & controls, Graphics & effects, Weather detail, Audio, Radiation
feedback, Sky appearance, Advanced sky & horizon and server Zombie population.
Fine-tuning starts collapsed; existing sliders, precision, presets and server
permissions remain intact. The Audio notice points to Garry's Mod Options >
Audio for master/effects/music levels; these remain engine-owned.

**Sky appearance > Choose sky...** opens a separate responsive thumbnail grid
over Options. It offers **Default (map)**, eighteen built-in automatic palettes
and 82 individual skies (eight original gradients, 38 mounted HL2 sets and
36 licensed imports). Custom palettes add further cards. Click a card to apply and save it;
Back or the close button returns to Options. Closing the parent also closes
the browser. `zombiesim_sky_palette` persists locally; **Restore map sky**
resets it and clears temporary previews. These
backdrops do not relight BSPs, alter authoritative weather or replace skyline
geometry. Default leaves the native sky intact.

Automatic palettes choose a fixed sky for each Day/Overcast/Dusk/Night state
using existing scenery-light/weather context. Built-in palettes include curated
original, mounted and imported choices, including six Tropospheric profiles.
The additional **Cloud prelude**, **Terrassee horizons**, **World's End horizons**
and **Cloudbound** profiles combine the new skies with Tropospheric clouds and
night skies. **Neon twilight (stylized)** and **Alien embers (stylized)** are
explicit cosmetic alternatives, using Waporvave/Alien red at dusk and
Cinematic silver-blue/Moonlit clouds at night. John Tron is not used by any
built-in automatic palette; it remains an individual/custom choice.
Broader visual/context/performance acceptance is still pending. Mounted HL2
textures are referenced, not copied into packages.
Fixed skies do not switch with the atmosphere, and the browser warns when their
context differs from current lighting. Gradient thumbnails use the backdrop's
colour curve; mounted thumbnails reference an existing face. The native-map
card uses the map's mounted face when available, otherwise a labelled map-managed
placeholder. No per-card render targets or scene renders are created.
**New custom palette** opens a visual editor in the browser. Click one of the
four preview slots on the left, then click an individual sky thumbnail on the
right to assign it. Search filters the available images; automatic palette
cards are hidden while editing. The native-map card can fill any slot.
Name the palette and choose **Save & use** to apply it. **Cancel** or Escape
discards the draft and restores the previous search/filter without changing
the saved selection.

Select an automatic palette to enable **Edit selected**. Built-in palettes
open as a named personal copy, preserving the original; custom palettes retain
their ID when edited and can be deleted with confirmation. Custom palettes
are saved locally in `data/zombiesim/sky_custom_palettes.json`.

Licensed imports include Moonlit Night, 26 Tropospheric sets and nine additional
sets supplied with author-confirmed permission. The sky builder retains full
licence/credit metadata and byte-identical README files under
`content/data_static/sky_licences`; the package builder includes the latter
in common content. Run `bin/build_sky_catalogue.ps1`, then
`bin/test_sky_catalogue.ps1` after changing the source allowlist.
Uncleared imports are not staged. Workshop publication remains a separate future task.

**Preview current skybox** performs a ten-second camera-only aerial inspection
and returns to the browser; Escape or Space returns early. The survivor is
not teleported, but the world keeps running. This previews the active saved
sky, not an unsaved palette slot. Human visual verification remains required.

Preview-admin commands:

```text
zombiesim_dev_sky_palette natural_day
zombiesim_dev_sky_palette cinematic_day
zombiesim_dev_sky_palette mounted_day
zombiesim_dev_sky_palette restore
zombiesim_dev_test_sky_palettes
zombiesim_dev_test_sky_browser
zombiesim_dev_test_launcher_tools
zombiesim_dev_ui options
zombiesim_dev_ui tools
zombiesim_dev_ui sky
zombiesim_dev_ui sky_edit
```

Individual previews expire after120seconds and do not change the saved palette.
The test results are `data/zombiesim/sky_palette_tests.json` and
`data/zombiesim/sky_browser_tests.json`. Close Options/browser before their UI
tests; temporary selections are restored. Screenshot metadata includes
`skyPalette` and `skyBrowser`; Options/browser captures include VGUI.

Options sections start closed and remember their open/closed state. A **VIEW
CHANGELOG** button below every section opens the shipped changelog
(`ZM_Changelog`, `cl_changelog.lua`, shared with Content Status): in game it
opens a Changelog window above Options (Escape or X closes only that window), and
on the launcher Options page it uses the right side of the launcher (the button
toggles it, and BACK/Escape returns to the main menu). In the
preview launcher (`zn_preview_start`, preview profile), **TOOLS** switches the
left launcher column to Wardrobe, Item Atlas, Map Atlas, Sky browser and
Content Status, then a rule above Wardrobe and Sky browser (which open their
own windows). Atlases and Content Status open on the right side of the
launcher. BACK or Escape always returns to the main menu and closes any open
view. Tools are read-only; Map Atlas images are staged PNGs, not live renders.
Atlas cards widen to fill each row. Clothing items everywhere (inventory, loot,
crafting, trading, atlases) draw a fabric swatch cropped from the actual garment
layer (`ZM_ItemIcons:DrawClothing`, shared with the Wardrobe), with a shirt or
pants badge, a repeat badge for repeat/checker/stripe fabrics and, at 72px or
larger, a placement tag such as CHEST, BACK or L THIGH. Placement prints show the
whole crop over a dim fabric fill; they never fall back to the box model.
`zombiesim_dev_test_launcher_tools` writes
`data/zombiesim/launcher_tools_tests.json`.

The game version lives in `content/data_static/version.json` (the single source
of truth, loaded by `ZM_Version` in `sh_version.lua`), and the shipped changelog
lives in `content/data_static/changelog.json`. Changelog highlights start with
`+` (added, green), `-` (removed, red) or `?` (changed, fixed or in progress,
yellow), listed in that order: additions, changes, then removals. Entries
before 2.6 are inferred from Git history (a `reconstructed` data flag only;
the UI does not label them). Content Status shows the following sections: a version
banner, build health problems, version and source (local Git commit when loose),
distribution and packages, world (profile, map, cells, dens, mounted BSPs and
city map images), loaded registry counts and the changelog. Workshop
packaging ships both files in core, stamps `gameVersion`/`gameStage`/`gameStatus`
into the distribution manifest and report, and adds a release blocker until
`version.json` status is `released`.
The user approved the thumbnail grid, grouped Options, expanded custom-palette
browser and revised four-slot visual editor (all slots visible and picker works).
Fresh renderer tests pass 7/7, browser/editor/inspection lifecycle tests 9/9 and
incremental catalogue/material/context tests 78/78. The latter include exact
new-profile coverage and isolated day/overcast/dusk/night light boundaries,
rain/snow and storm-threshold checks without changing live server weather.
Run after the arrival/loading hold
finishes. The user reviewed the new automatic variants and aerial preview/return.
An actual selected custom palette also survives a fresh preview map reload with
unchanged saved JSON. Broader weather/context, launcher/den/capture and performance
acceptance remains; these results do not establish full Phase H completion.

## Original billboard artwork

For local Hammer/GMod development, run `.\bin\stage_sign_assets.ps1` to copy and hash-verify the current sign models/materials into the installed `garrysmod` root, or add `-StageToGame` when building sign assets. Generate a six-variant Hammer showroom with `.\bin\build_sign_zoo.ps1`; add `-Compile` to compile and stage **one standalone development BSP**, `zn_dev_sign_zoo`. Open `generated\signs_preview\zoo\zn_dev_sign_zoo.vmf` in Hammer, or use `map zn_dev_sign_zoo` in a sandbox development session. This does not rebuild city recipes, change production staging, or package the zoo for release.

Build the six original sign variants with `.\bin\build_sign_assets.ps1 -WorldProfile preview`: detailed freestanding and lamp-lit billboards, legless panel, small wall sign, thin framed print and borderless poster. Use `-ArtworkPath` for a finished opaque 1024 x 512 panel, or `-ImagePath` / `-BackgroundImagePath` for aspect-preserving foreground/background layers. The sign JSON controls image paths, self-lighting and independent leg/rim/back textures; mounted Source textures are referenced, not copied. Run `.\bin\test_sign_assets.ps1` after building. This compiles six small models and two original textures, not city BSPs. The [artist workflow](docs/sign_artist_workflow.md) documents geometry budgets, settings, placement prefabs, light baking, skybox limits and packaging. Preview admins can use `zombiesim_dev_sign on [freestanding|panel|illuminated|wall|print|poster]` through the bridge, and `off` to remove it; it expires after three minutes. The print and poster mount to the aimed wall, and the two-triangle poster has no collision or physical border. The illuminated preview casts a temporary real projected light, while its Hammer prefab uses a baked spotlight. Live appearance of the detailed billboard and both thin variants was approved by the user; compiled-tile collision, baked lighting and an actual skybox view remain integrated checks.

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

Preview builds default to Hammer's `-fast` VVIS/VRAD preset. Production `city` builds default to the `final` preset (full VVIS plus VRAD `-final -staticproplighting -staticproppolys`). Override the preset with `-Fast` or `-Final`, and tune the bounded compile pool with `-MaxParallelProcesses`; its default is `4`. Stock Hammer tools do not accept a numeric `-threads` value, so the runner uses the process-pool limit rather than passing an invalid argument.

## Export To Garry's Mod

### Launcher maps (independent of world generation)

The two authored launchers are `celltemplates\launchers\zn_preview_start.vmf` and `zn_city_start.vmf`. Their menu room camera is `menu_camera` at `(0, -160, 112)`, facing north (+Y); the `menu_globe` marker is at `(96, 32, 112)`, to the camera's right, leaving the left of the view for menu options. Both `point_camera` entities (`menu_camera` and `credits_camera`) start off; they are scene pose markers, not active monitor feeds. The dance rigs in the credits area remain unchanged. Check camera framing, globe size, lighting and dance visibility in Hammer and in a running client; a successful compile alone does not verify the view.

Run the focused parity check and compile each small launcher independently, without regenerating or compiling any world recipes:

```powershell
.\bin\test_launcher_parity.ps1
.\bin\build_launchers.ps1 -WorldProfile preview
.\bin\build_launchers.ps1 -WorldProfile city
```

Each build copies the current VMF into `generated\launcher_build`, runs VBSP/VVIS/VRAD, fails on a leak or nonzero compiler exit, and copies the resulting BSP to both `content\maps` and Garry's Mod `garrysmod\maps` (which otherwise can shadow the content copy). The script verifies SHA-256 equality of the built and staged files. Reload each launcher map after staging. Hammer `.vmx` backups are not build inputs and are not modified.

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

The den camera selects first-person when the loaded map matches a den in the active world profile, including the brief exit interval when the saved safe-zone ID has already been cleared; outside dens it retains the top-down/orbit controls. The weapon HUD reads clip capacity from the active weapon and reserve rounds from the server-synchronized inventory snapshot. An unavailable inventory snapshot displays `--` rather than pretending the reserve is empty. Hammer `npc_name` takes precedence for den NPC display names; if absent, the entity's `targetname` is used.

In a generated safe-zone cell, approach an authored `zn_safezone_door` and press E to enter its den; use the exit point at the den's south entrance to return to the same city cell. The server checks loaded player state, the active map and safe zone, and the single-human transition guard before persisting a map change. Arrivals use the authored `zn_safezone_arrival` point when available, with `info_player_start` as a fallback. The client displays a nearby-door prompt, but the server owns the interaction. Run `zn_test_safezones` in an in-game admin console to exercise the safe-zone door and arrival suite; GLua syntax checks alone do not exercise a map transition.

To compare the client atmosphere before and after respawning in the same cell, run `zombiesim_atmosphere_status` in the client console. It prints the active and expected profile indexes/ids, logical cell, whether world data was loaded when the server profile arrived, pending profile application, a bounded application history, storm intensity, effective fog settings, and the latest world-fog, skybox-fog, and colour-correction hook results. The colour-correction hook intentionally returns `nil` after drawing so it does not suppress other addons' render hooks; `applied=true` indicates ZombieSim called `DrawColorModify`. This is a diagnostic, not proof that lighting and fog match visually; record output and screenshots across first join, respawn, map reload, and cell transition.

## Development Command Bridge

For local development, edit [content/data_static/consolecommands.txt](content/data_static/consolecommands.txt). Give every request a new `# request:` identifier and place one server-console command on each uncommented line. The bridge polls the mounted file and executes each identifier once, including across map changes. It is enabled by default only for non-dedicated servers; toggle `zombiesim_dev_console_enabled` to control it.

The bridge writes an acknowledgement and any structured diagnostic data to `garrysmod/data/zombiesim/consolecommands.result.json`. This location is the GMod `DATA` mount, so it is intentionally outside the gamemode source tree. While the server ticks, the bridge also refreshes `consolecommands.heartbeat.json` about once per second. A stale heartbeat while `gmod.exe` is running means the game is paused (Escape menu in singleplayer) or loading.

`.\bin\invoke_dev_bridge.ps1 -Command 'zn_test_safezones'` sends a request and prints the matching result. After `changelevel` it waits for the reloaded map to tick. Its exit codes:

- 0: acknowledged
- 2: server not ticking (paused or loading)
- 3: Garry's Mod not running
- 4: a ticking server did not acknowledge in time

`zombiesim_dev_door_report` (preview only) reports the live safe-zone door and arrival entities, their model bounds and the player's pose.

Ordinary engine-console output remains in the game console; use the structured persistence probe for automation:

```
zombiesim_dev_persistence_report STEAM_0:1:31630
```

That report includes the raw `city` and `preview` player/attribute rows, active map and profile, actual live health, resolved world-cell id, safe-zone status, both radiation channels, combined Sv, suit protection, acute-exposure status, elapsed exposure time, time until the next radiation tick, and the nominal/effective health floors. At combined readings of 15 Sv or lower, cell radiation below 75% intensity deals 1 damage every 120 seconds; cell intensity at or above 75% deals 2 damage every 60 seconds. That ambient damage cannot reduce health below 64 at Strength 0-4, 72 at Strength 5-9, or 80 at Strength 10+. Strictly above 15 combined Sv, the policy switches to 1 HP every 2 seconds with no health floor, and can kill. Entering/leaving acute exposure, changing cells, entering a den, or equipping a radiation suit resets the interval. The preview survival lock still suppresses damage.

Two preview-only bridge commands require an active admin preview session: `zombiesim_preview_refill` restores health and survival reserves; `zombiesim_preview_restore` also moves the player to the origin safe room and respawns them if needed.

For launcher testing, the bridge also supports `zombiesim_dev_character_slots` (read-only slot summary) and `zombiesim_dev_deploy_character <slot>` (selects an existing character and deploys it from `zn_preview_start`). Deployment requires an admin and the preview launcher. `zombiesim_dev_teleport_cell <gridX> <gridY>` uses the normal profile-aware transition path; cell coordinates are persisted, so capture `zombiesim_dev_persistence_report` before moving and restore the original cell/safe-zone afterward. `zombiesim_preview_restore` deliberately moves the preview character into the origin safe room and refills survival values; use it only when that state change is intended.

For a live preview atmosphere snapshot, submit `zombiesim_dev_atmosphere_status` through the bridge. The admin-only request asks the local client for its active/expected profile, fog, and render-hook diagnostic and writes the response to `garrysmod/data/zombiesim/atmosphere_status.json`. This is separate from the server bridge acknowledgement and is only available in the preview profile.

For a client frame-cost profile, run `zombiesim_dev_profile_hooks [seconds]` (default 10, maximum 120; also reachable through the bridge). It temporarily wraps named render, Think and HUD hooks, including `PostDraw2DSkyBox` for palette drawing, records frame times and Lua allocation, restores the original hooks, prints the top entries and writes `garrysmod/data/zombiesim/hook_profile.json`. Hook timings are CPU-side call measurements, not isolated GPU cost; record camera, weather, quality and population/render counts before making comparisons.

Weather follows a seasonal schedule driven by the server's clock (northern hemisphere): every 8–25 minutes the server rolls clear, rain or snow from the current month's chances. Snow is rare, most likely in December, guaranteed all of Christmas Day (25 December) and never falls in June–August; out-of-season snow is replaced at once. The schedule state is archived (`zombiesim_weather_until`, `zombiesim_weather_manual`), so level changes do not reroll it. From the server console or an admin client, `zombiesim_weather clear`, `zombiesim_weather rain` or `zombiesim_weather snow` (and the preview cheat buttons) override the weather for one spell, after which the schedule resumes; `zombiesim_weather auto` resumes it immediately, `zombiesim_weather` with no argument reports the mode and time to the next change, and `zombiesim_weather_auto 0` keeps the weather steady. Rain and snow effects are limited to outdoor city cells; sheltered interiors and dens remain dry. Puddle footsteps retain the textured ground footprint/ring and throw five short-lived upward water-splash particles, with a mounted slosh sound when available. The footprint material is rebound after rain crowns so they cannot change its appearance. In multiplayer, puddle steps replace the ordinary footstep sound; singleplayer retains the distance-based layered fallback because its client does not receive `PlayerFootstep`. Wet-ground and lying-snow footsteps still use the existing distance-based effects. Rain impacts are bounded to 240 single-quad rings and 40 crowns, rather than expanded procedural ripple meshes. Rain also forms client-local puddles at fixed map locations; off-screen puddles remain in world space and are rendered only when visible. Their irregular, feathered water meshes grow while forming and shrink/fade as they dry, with bounded cluster and per-frame render limits. Puddles that stay wet slowly spread, and some become large pools where the surrounding ground is level. The launcher and in-game Options panels include **Rain density** (0.5-2.0, default 1.5), **Puddle opacity** (0.05-0.45, default 0.15), and **Puddle amount** (0.5-3.0, default 1.0). All three are saved locally. Lower puddle opacity shows more ground through the water, and higher puddle amounts form more puddles at some extra frame cost. Snow cools the colour grade and fog, adds breath, a frost edge, and wind, and gradually lays a snow blanket over exposed outdoor ground (built client-side per map, no recompile). The cover settles in drifting patches over about three minutes of snowfall before joining up and thickening. The server owns the lying-snow amount (`zombiesim_snow_cover`, archived), so it carries over level changes. When snow is lying, a newly loaded map keeps the loading screen up until the cover is built (normally 1–2 s, capped at 12 s). Walking through the snow carves a trail, which fresh snowfall fills back in. The cover melts when the weather clears or turns to rain. Weather does not change movement. The options menu's “Subtle film grain” toggle is off by default.

Player-step splash particles use the mounted `effects/splash2` material (`UnlitGeneric`), while ground footprints retain `effects/select_ring`. The former `particle/water/watersplash_001a` asset uses `SpriteCard` and produced a bright streak in this emitter path. Client atmosphere diagnostics include both splash-material shader/availability values and the rain-impact quad count and maximum index budget.

Level-view map captures (including the minimap's level mode) hide players, airborne weather particles, target halos, and transient puddle impacts/footprints for the capture only. Lying snow stays visible. The minimap refreshes when weather, snow cover, or replicated loot state changes, including after the final melt and after snow meshes finish rebuilding, with a three-second refresh throttle. Looting a prop therefore refreshes its old yellow tint in the captured image. Both level and cell minimaps draw nearby active loot as gold `?` markers, gray when declined; consumed loot loses its marker. These reuse the existing 1,500-unit loot marker range and quarter-second cache. The open level map retains its periodic refresh. `zombiesim_dev_atmosphere_status` includes capture state/count, loot revisions, particle suppression/restoration state, and shoulder-camera mode. Normal weather drawing is restored immediately after a capture.

In shoulder-camera mode, local search progress, stamina, and short-lived player notifications use separate lower-center HUD rows instead of following the player's head. Search hints also move to this HUD area, while loot markers stay in world space. The anchor shifts clear of an enlarged minimap. Locked and orbit modes retain overhead indicators; the den's first-person camera is not classified as shoulder mode.

Map captures also suppress camera occlusion halos and player-owned weapon models/shadows. Player and weapon `NoDraw`/`EF_NOSHADOW` flags are retained and restored after each capture; ordinary gameplay rendering and world-prop shadows remain unchanged.

Ordinary Walker spawns in radioactive cells have a radiated-variant chance of half the cell's normalized radiation intensity (0% to 50%). Ticket spawns select this repeatably using a separate variant RNG stream; the enemy selection, health, speed, loot, XP, and boss behavior are unchanged. Server-owned `ZM_Radiated` and `ZM_RadiatedIntensity` values publish the variant for proximity presentation. `zn_test_enemies` covers spawn state; `zn_test_radiation_feedback` covers proximity falloff, source filtering, sensory cadence, and the additive meter.

Radiated walkers contribute exposure within 600 units, with quadratic distance falloff and only the strongest living source counted. The existing radiation meter adds up to 10 fictional Sv of proximity to its 0-10 Sv cell baseline (maximum 20 Sv); there is no separate proximity panel. Above 15 Sv, unprotected exposure becomes damaging as described above. Geiger cadence uses the stronger channel with an 8% quiet threshold; authentic mounted `player/geiger1.wav`, `geiger2.wav`, and `geiger3.wav` recordings have irregular, bounded 0.06-4 second intervals and smoothed exposure-dependent volume. Clicks use local non-positional playback ([EmitSound entity -2](https://wiki.facepunch.com/gmod/Global.EmitSound)), so camera distance cannot attenuate them. No Valve audio is copied into the addon.

Radiation camera shake and postprocessing now activate only above 15 Sv, easing into full black-and-white and increasingly harsh contrast/darkening and up to three degrees of cosmetic camera tremor at 20 Sv; they do not alter aim commands or movement. The launcher and in-game Options share saved controls: `zombiesim_geiger_volume` (default 0.35), `zombiesim_geiger_visual` (meter pulse, default 1), `zombiesim_radiation_extreme_grayscale` (default 1), and `zombiesim_radiation_extreme_shake` (default 1). The new extreme-only settings replace the earlier low-exposure grayscale/shake controls. Zero disables each effect without removing the numeric warning or changing server damage. Dens, loading screens, and menus suppress sensory effects.

Unprotected exposure also adds a soft green-dark vignette at all four screen corners. It scales with the combined 0-20 Sv reading, fades smoothly, preserves the clear center/HUD text, and disappears immediately while wearing the suit. The top-left nuclear warning symbol remains visible even while protected; higher exposure increases its smooth pulse frequency from 0.2 to a bounded 1.5 Hz, rather than a rapid strobe. Both suppress very low exposure (combined normalized intensity at/below 8%), menus, dens, and map captures. Options controls `zombiesim_radiation_corners` (0-1 intensity) and `zombiesim_radiation_symbol` (0/1) default to 1. Corners use four feathered quads behind the HUD, with an original 64x64 radial RGBA mask built once, rather than opaque black-backed glow sprite texels. The trefoil uses cached convex polygons and reserves its HUD rectangle so damage arrows cannot overlap it.

The **Radiation Protection Suit** (`itemRadiationSuit`) occupies the dedicated **ARMOR** slot, separate from the three weapon slots. Carrying one does not protect you: double-click/right-click **Equip**, or drag it onto ARMOR. Right-click **Unequip**, double-click the equipped suit, or drag it back to a free backpack slot to remove it. Armour changes use atomic, character/profile-scoped item persistence. While worn, the suit blocks ambient/acute radiation damage and radiation screen effects immediately, but keeps the meter and Geiger warnings and ordinary weather presentation. It provides no bullet/melee immunity. It is sold by the Quartermaster (base value 400 before normal trading multipliers) and can rarely appear in general crates. Admin preview testing can use `zn_give_item itemRadiationSuit 1` and `zn_equip_item itemRadiationSuit`; the mounted HEV suit model supplies its inventory icon without changing the survivor's selected appearance.

Living radiated walkers have a green, view-dependent reflective `VertexLitGeneric` overlay and depth-tested red eye glows; ordinary walkers remain unchanged. The effect preserves skin, animations, and severed-bone transforms, hides eyes when the head is severed, and is excluded from map captures. `zombiesim_radiated_visuals` controls off/reduced/full (0/1/2, default 2), limiting overlays to the nearest 8/24 walkers within 1,500 units. It creates no lights, particles, or extra model entities. The Fresnel/envmap sheen approximates iridescence using a mounted cubemap rather than relying on the level's baked cubemaps. Parameters were checked against [Source SDK 2013's VertexLitGeneric shader](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/materialsystem/stdshaders/vertexlitgeneric_dx9.cpp); that branch is not Garry's Mod's exact engine, so the preview appearance was also reviewed in-game.

For an admin deployed in a preview city cell, `zombiesim_dev_radiation_probe on` places one temporary stationary radiated walker facing the player for approach/retreat checks; `off` removes it. It grants no rewards and expires after 120 seconds. Approaching can now cause lethal radiation above 15 Sv; wear a suit for protected visual checks. For actual health-loss validation, unequip the suit and turn off preview **God mode** and **Survival lock**; those cheats intentionally prevent damage even while the meter and warnings show high exposure. Atmosphere diagnostics include both radiation channels, extreme severity/blend, suit protection, click requests, sound availability/playback, corner-mask readiness/version, settings, and walker shader/eye/draw-budget state. Click request counts are not proof of audible playback.

In an admin preview session, the **Cheats** window provides several toggles, which are saved per player in `data/zombiesim/preview_cheats.json` and stay on across level changes:

- god mode, which shows a **GOD MODE** badge under the XP bar
- noclip
- zombies ignore me
- infinite ammo
- survival lock (no hunger, thirst or radiation drain)

It also has one-shot actions: restore vitals, level up, kill nearby zombies, and clear/rain/snow weather. Use the world map for travel.

## Local Development Session

Use the scripts below from the repository root to start a local ZombieSim session through Steam with the game console, `console.log`, and Source server logs enabled:

```powershell
.\bin\start_zombiesim_dev.ps1 -WorldProfile preview
.\bin\read_zombiesim_dev_log.ps1 -Lines 200
.\bin\send_zombiesim_dev_command.ps1 zombiesim_walker_status
.\bin\stop_zombiesim_dev.ps1
```

`send_zombiesim_dev_command.ps1` overwrites the bridge input with a fresh request id, as required by `sv_dev_console.lua`. Use `read_zombiesim_dev_log.ps1 -Console` for the `-condebug` capture, or add `-Follow` when manually observing an active session. `stop_zombiesim_dev.ps1` closes the local `gmod.exe` window first so the server can run normal shutdown hooks; use `-Force` only when it cannot exit gracefully.

For iterative Lua testing, use Garry's Mod hot-reload rather than closing and relaunching the game. To repeat map initialization or a spawn path, issue `changelevel <current-map>` from the server console or through the bridge; this reloads the same map while keeping the game open. Confirm the player has rejoined and the intended profile/cell has loaded before collecting diagnostics.

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

Phase F clothing can be built and checked with Garry's Mod closed:

```powershell
.\bin\build_clothing_blood.ps1
.\bin\test_clothing_blood.ps1
.\bin\test_clothing_model_inspection.ps1
.\bin\test_clothing_walker_inspection.ps1
.\bin\test_glua_syntax.ps1
```

Run these chart writers serially. The blood builder stages three original
shared garment overlays, not duplicate wearable items; the existing866finish
catalogue and sixteen-slot runtime pool remain unchanged. In an admin preview,
Wardrobe's **BLOOD PREVIEW** toggle changes only its window model. The expanded
`zombiesim_dev_test_clothing_pool` suite and blood appearance/seam/corpse checks
must still be run in the client; offline success does not accept Phase F.
Group03 calibration exports are separate2048-square diagnostics, not approved
survivor-mask compatibility or enabled walker clothing. See the
[artist workflow](docs/clothing_artist_workflow.md) for controls and remaining gates.

Each gameplay service has a server-side suite that uses throwaway SteamIDs and profiles and removes every row it writes. Run them from an admin console or through the bridge; each writes `garrysmod/data/zombiesim/<name>_tests.json` and a bridge report, and a bridge command fails when any case fails:

```
zn_test_static_data zn_test_weapon_catalog zn_test_inventory zn_test_loot zn_test_loot_spots zn_test_enemies
zn_test_bosses zn_test_crafting zn_test_implants zn_test_professions zn_test_mastercraft zn_test_bank zn_test_trading zn_test_foliage
zn_test_atmosphere zn_test_gore zn_test_afk zn_test_damage_feedback
```

New suites use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`): `NewSuite()`, `suite:Add(name, function(check) ... end)`, `suite:Run({ before, after })`, and `ZM_TestHarness.Register({ command, label, file, report, help, run })`. Shared server helpers for command runners (first human, profile, whole-number checks, replies, admin gates, command registration) are in `ZM_Util` (`gamemode/utils/server.lua`).

## Item Icons

Inventory tiles and loot offers render each item's mounted model as a Garry's Mod spawn icon (the engine `ModelImage` panel that `SpawnIcon` uses, which generates and caches `materials/spawnicons/...` on first view). The icon model resolves in this order:

1. `iconModel` in the item definition, for non-weapon items or when the world model is a poor icon.
2. `worldModel` for explicitly mapped weapons.
3. `models/props_junk/cardboard_box004a.mdl` as a generic fallback.

An authored `materials/items/<thumbnail>.png` is an optional override and takes precedence when present; it is no longer required, so a missing PNG does not warn. Runtime validation instead warns when an icon model is not mounted. Pick icon models from the mounted archives (for example HL2 ammunition boxes such as `models/items/boxsrounds.mdl` in `sourceengine\hl2_misc_dir.vpk`, or CSS props such as `models/props/cs_assault/money.mdl` in `sourceengine\content_cstrike_dir.vpk`) using the VPK listing workflow under Mounted Garry's Mod Assets.

# Inventory

Each player has a 20-slot backpack and a 60-slot den stash, stored per profile in the `player_items` SQLite table. The backpack is lost on death; the stash can only be changed inside the player's current den. The regular inventory always shows only the backpack. Using the stash in a den opens a separate **DEN + INVENTORY** window with the backpack and **SAFE DEN STASH** in separate columns; drag items between them or use an item's right-click **Move to** action. Admin commands (from the server console or bridge they act on the first connected player):

Aim at a bank terminal or den stash to see the **Press E to interact** prompt.

Right-click a backpack item and choose **Drop** to place the chosen quantity in a crate on the ground just in front of you. A blocked spot rejects the drop without removing the item. Crates are separate, public pickups, persist by profile and logical city-cell or safe-zone location across map changes and server restarts, expire after 24 real-time hours, and leave any amount that does not fit in a backpack in the crate.

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

Den NPCs are `zn_den_npc` point entities placed in a den's VMF in Hammer (`zombiesim.fgd`). Their keyvalues are `npc_name`, `profession` (a profession id or alias; empty for none), `service_level` (1–300, the level cap for the items they work), `fees` (for example `cook=5 treat=10`), `trader` (`general`, `quartermaster`, `clinic`, or empty), `model`, `animation`, and `default_animation`. An NPC can be a trader, a professional, or both. Settings are resolved against the live static data; a rejected setting is logged, and an NPC without a valid profession offers no services. The configured model and animation sequences are applied in-game; an unavailable selected sequence logs a warning and falls back to the default or a supported idle sequence. Aiming at an NPC shows its name, role, and the interaction prompt. Tap E to open its current trading/services screen (or an information card for a resident with no services); hold E to open the radial menu for available services, trade, Talk, and a disabled **COMING SOON** slot. Talk displays the resident's name, role, level, services, and trade availability; it is not a dialogue system. Services opened from an NPC identify that provider and select the first available service, while selecting a service in the radial carries that selection into the screen.

The `model` field on `zn_den_npc`, `zn_den_stash`, and `zn_bank` is honored at runtime, with a logged fallback to the entity's default for an invalid model. Their FGD definitions provide default studio previews in Hammer while keeping the model fields editable. NPC `animation` selects a sequence on its configured model; `default_animation` is tried when that sequence is empty or unavailable.

## Den Banking

Place `zn_bank` in a den's Hammer map. Its `model` keyvalue controls the in-game terminal model. An alive player can use a nearby terminal while in the den; bank access is server-validated for range and clear line of sight.

The bank window keeps the account balance (`player_data.Cash`) separate from physical `itemCashBundle` items. Deposit explicitly at a terminal from cash bundles in the backpack and den stash; entering a den does not automatically deposit them. Withdrawals create cash bundles in the backpack and are refused when it has no room. The server saves the bundle change, account balance, and transaction ledger together and rejects replayed request IDs. The persistent ledger is character/profile-scoped; the window shows the latest 10 transactions. Use the $100/$500/$1,000 presets or enter a whole-dollar amount (up to $1,000,000 per transfer).

Run `zn_test_bank` for atomic deposits/withdrawals, ledger persistence/idempotency, insufficient-funds, and full-backpack checks.

- **NPC professionals** appear in the Services window next to players. They accept at once, work at their `service_level`, and charge a fixed cash fee (the `fees` keyvalue, else `npcServiceFees` in `trade_definitions.json`). The fee is taken from the customer in the same transaction as the items and credited to no one. All normal service rules apply: in the den, within 160 units, the customer supplies the items.
- **Trading** uses `content/data_static/trade_definitions.json` (`tradeVersion`). Each trader table lists the loot categories it `buys` and its `offers` (`item`, `bundle`, `minStock`–`maxStock`, `minDanger`–`maxDanger`, optional `mastercraft` and `credits`). A trader with `essentialAmmo` always stocks the common ammunition (shipped: 10 × 30 rounds of 9mm, shells, 5.56, and 7.62).
  - **Stock** is shared by everyone in the den and resets at midnight UTC. It is rolled deterministically from the profile, den, trader, day, and offer; only units sold are stored (`trade_stock`).
  - **Danger:** the den's danger is its entrance cell's. Offers outside their danger range are hidden, and weapon levels rise with danger (up to halfway through their level range). The window shows the danger tier: Safe, Guarded, Dangerous, or Deadly.
  - **Prices:** ordinary goods cost `ceil(value × 1.5)` cash; mastercraft weapons and implants cost a fixed number of credits. Traders pay `floor(value × 0.4)` cash for backpack items in categories they buy, up to 2,500 cash per player per day. Equipped weapons, spoiled food, cash, and implants cannot be sold. Purchases go to the backpack; if they do not fit, nothing is bought.
  - **Purchase UI:** offers appear as item tiles; hover for level, quality attributes, bundle/ammo details, and select one for stock, stats, and a purchase detail panel. Quantity uses bounded numeric controls and affordable 1x/5x/10x shortcuts, followed by explicit confirmation. Ammunition quantities show total rounds. The server recalculates price, affordability, and stock when the purchase is submitted.
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

Walker and boss zombies are infected survivors: each picks a random stock citizen, refugee or rebel player model (`models/player/group01..03`, validated with `util.IsValidModel`) and skin, and animates with the HL2MP zombie set (one of `ACT_HL2MP_WALK_ZOMBIE_01..05` per zombie, `ACT_HL2MP_IDLE_ZOMBIE`, and the `ACT_GMOD_GESTURE_RANGE_ZOMBIE` attack gesture); a `BodyUpdate` override drives `move_x`/`move_y` for these activities. Corpses copy the zombie's bone pose into the ragdoll. `ZM_Enemies` (server) picks the enemy type for each Walker ticket from the spawn groups matching the cell's environment tags (or `defaultGroup`), limited to enemies whose `minDanger`..`maxDanger` contains the cell danger. Health, speed, and spawn weight scale across each enemy's own danger range. Walkers have 50–65 health (rare walkers 65–90, bosses 500–650), so most guns need four to six body hits. A bullet or pellet that strikes the head hitgroup is lethal to a walker; bosses take triple head damage instead (`Enemies.ApplyHeadshot`, an `EntityTakeDamage` hook fed by the walker's `OnTraceAttack`). Melee damage is unchanged by hit location. The engine subtracts NextBot health after `OnInjured` and then calls `OnKilled`, so `OnInjured` only observes a hit and must not change health itself. A player kill awards the enemy's `xp` and rolls its loot drop once; despawns give nothing.

```
zn_spawn_enemy [enemyId|auto] [danger]   // development spawn in front of the player (not Walker-ticketed)
zn_kill_enemies                          // kill nearby defined enemies, credited to the player
zn_test_enemies                          // selection, scaling, and reward tests
```

Through the bridge these add `reports.enemySpawn`, `reports.enemyKills`, and `reports.enemyTests`.

# World Loot Spots

`ZM_LootSpots` (server) turns matching map props from `entity_loot.json` into loot spots when a player loads into a city cell. Spot state is saved per profile and cell in SQLite; a cell re-rolls on the next load after 5 minutes with nobody in it. Press E to search the targeted spot, then accept or decline the offered item (declining keeps the same item on the spot). `ZM_LootTargeting` (`gamemode/sh_loot_targeting.lua`) runs the same rule in both realms: the spot under the aim trace (the crosshair in shoulder mode) wins when it is searchable, within 110 units and unobstructed; otherwise the nearest such spot is used. The client outlines that target (gold, or grey once declined) with an `[E] Search` hint; aiming at a spot that cannot be searched shows `Empty`, `Too far` or `Blocked`, and the server rejects Use with the matching message. Players, NextBots and ragdolls never count as obstructions; walls, doors and other props do.

Rules cover every whole, container-like mounted model (HL2, CSS, PHX): vehicles and train cars, barrels and fuel cans, vending units and coolers, crates and boxes, ammo cans and footlockers, lockers, cabinets, desks, fridges, kitchen units, shelving, laundry machines, trash cans and dumpsters, electrical boxes, and cash sources such as registers, luggage, and money pallets. Each rule maps to a semantic group: `lootCash` holds cash bundles and `lootMedicalSupplies` holds bandages and painkillers. Gibs, fragments, scenery, loose pickup-sized junk, and PHX building blocks are deliberately excluded. A rule only applies when a template places the model as `prop_physics`/`prop_dynamic` (or their `_override` variants); `prop_static` cannot be looted.

Rules may also target `prop_ragdoll`. Map ragdolls match by model, and `ZM_LootBodies` (`gamemode/sv_loot_bodies.lua`) places 2?4 fallen bodies per city cell on walkable, nav-covered ground before the cell's spots are collected. Placement, models and spot keys (`b1_<attempt>`) come from the profile/cell/map seed, so a reloaded cell recreates the same bodies and keeps their searched state; they settle and freeze after 3 seconds. Body families are weighted civilian (`lootBodyCivilian`: cash, medical, food, a rare handgun), rebel (`lootBodyRebel`: weapons, ammunition, medical), birds, charred remains, police/Combine (`lootBodyMilitary`) and medics. Enemy corpses are never generic candidates (they only carry their one rolled kill reward), and severed limbs are client-only and cannot be searched. A cell that was already stored before bodies existed picks them up at its next re-roll (`zn_loot_spots_refresh` forces one).

ZombieSim disables Garry's Mod's default `+use` physics-prop pickup globally. Pressing E can still activate ZombieSim interactions, doors, buttons, and transition gates, but cannot carry barrels, crates, or other physics props. When a searchable loot spot is explicitly under the player's aim beside a cell gate, searching that spot takes priority; aiming away from nearby fallback loot keeps gate travel available.

```
zn_loot_spots            // matching props and spot states in the current cell
zn_loot_spots_refresh    // re-roll every spot now
zn_test_loot_spots       // loot spot tests (throwaway profiles)
zn_dev_loot_offer <modelSubstring> [limit]   // development: roll then decline matching offers (no inventory changes)
zn_dev_scavenge <modelSubstring> [limit]   // development: search and accept matching spots as the first player
```

Barrels are scavenged for resources. Blue plastic (`props_borealis/bluebarrel001`) and wooden (`props_c17/woodbarrel001`) barrels give `itemBarrelWater`; oil drums, warning barrels, `de_train/barrel`, and barrel pallets give `itemOil`; crushed oil drums, PHX empty/Facepunch barrels and gas cans also use the oil group, and the CSS wine barrel uses the water group. Rules match `prop_physics`, `prop_physics_multiplayer`, `prop_physics_override`, and `prop_dynamic` by normalized model path; broken barrel gibs, unmapped models and `prop_static` are not loot spots.

Semantic container rules are also model-specific: the CSS and HL2 vending machines roll bottled water or soda; ammunition crates and the listed CSS military crates roll weapons/ammunition only; and the listed wooden crates roll food, medical supplies, or materials. No generic prop-class rule grants fallback loot, so unsupported models remain non-lootable.

`celltemplates/dev/zz_preview_loot_fixture.vmf` is a developer-only physical-prop fixture for these five representative models. It is intentionally excluded from the preview/city template plan and must not be staged as a gameplay map.

Through the bridge these add `reports.lootSpots`, `reports.lootSpotTests`, and `reports.scavengeProbe`. The bridge-only `zombiesim_dev_teleport_cell <gridX> <gridY>` moves the first player to a raw grid cell through the normal world transition.

# Runtime Foliage and Ambient Debris

`ZM_Foliage` places a bounded, deterministic set of server-owned trees and berry bushes in each outdoor city cell. It traces ground, places up to 30 nodes on flat grass/dirt/mud/gravel/sand surface properties (rocky `rock`/`boulder` ground grows bushes only), stays inside the 5x5 playable tile grid so the inaccessible border ring is excluded, and rejects road/building materials and occupied spaces. Trees also require suitable ground at four points around their base; edge placements that would overlap paving become shrubs instead. Foliage never edits or regenerates map files. Each full cell has 10 interspersed harvestable resource plants and 20 decorative plants; only available harvestable plants are tinted yellow, depleted harvestables are grey, and decorative foliage keeps its natural color and cannot be harvested. Press E near a harvestable bush to pick Berries by hand; harvestable trees require any equipped melee weapon and yield Wood. Decorative plants do not intercept nearby harvest interactions. The server validates range, life state, tool, season and cooldown before granting through the inventory service.

Each node picks a model deterministically from mounted HL2/CS:S pools in `ZM_Foliage.Models`: trees include `de_inferno/tree_small`, `props_foliage/tree_dry01`/`02`, `tree_dead01`/`03` and `cs_militia/trees1`; bushes include `bushgreensmall`, `largebush01`/`03`, `de_train/bush`/`bush2`, `props_foliage/bush2` and `pi_shrub`. Unmounted models are dropped from the pool with a console warning. Fallen bodies share the same playable-grid bounds. Wood is available year-round. Berries are plentiful March-August, scarce September-November and unavailable December-February, based on server-local time. Harvest cooldowns are shared per profile and logical cell, persisted in SQLite and survive restarts: one day for bushes, seven days for trees. Wood and Berries are generic material items with no sale value or food effects assigned yet.

Ambient debris is client-local, limited to nearby deterministic sites, does not collide with players, and cannot be harvested. Kinds: paper (`props_c17/paper01`, newspaper) flutters and lifts in gusts; bottles and cans (`cs_militia/bottle01`, HL2 glass/plastic bottles, cans) lie on their side and roll; cartons and cardboard slide; rare tumbleweeds (HL2 `props_foliage/bramble001a`, scaled 0.5) roll and bounce with the prevailing wind within a leash of their site. Moving players kick nearby debris, and bullet impacts from any player's `ZM.WeaponShot` broadcast throw debris away from the hit point. Debris only simulates (gravity, wall collision, ground following) while moving and within 2000 units. The client setting `zombiesim_ambient_debris_amount` (0 disables, 1 default, up to 3; quick-menu **Debris amount** slider) scales site density and the model cap (20 × amount, at most 60). `zn_foliage_status` reports current server placement, rejection reasons and the most-sampled surface props/textures; `zn_foliage_rebuild` clears and re-places foliage for the current cell without a map reload. `zombiesim_ambient_debris_status` reports client debris amount, counts per kind and how many are moving. `zn_test_foliage` covers deterministic placement filters, the 10/20 harvestable/decorative split, seasonal rewards, cooldowns, tool checks, duplicate harvests and persistence; run `zn_test_inventory` for inventory regression. Live model, appearance, exclusion, sharing and repeat-visit checks remain required.

# Client Graphics Quality Presets

`gamemode/cl_quality.lua` defines archived, client-only quality settings and the `zombiesim_quality_preset` convar (`low`, `medium`, `high` or `custom`). Choosing a preset in the quick-menu **Options** dropdown, or with the convar, writes the individual settings below. Changing any of them by hand switches the preset to `custom`, unless the new values exactly match another preset. High matches the visuals from before presets existed.

| Setting | Low | Medium | High |
| --- | --- | --- | --- |
| `zombiesim_atmosphere_rain_density` | 0.6 | 1.0 | 1.5 |
| `zombiesim_atmosphere_puddle_amount` | 0.5 | 0.75 | 1 |
| `zombiesim_atmosphere_ripple_amount` (puddle rain ripples, 0.1–1) | 0.35 | 0.65 | 1 |
| `zombiesim_snow_detail` (lying-snow sample density, 0.25–1; a change re-samples the cover in the background) | 0.4 | 0.7 | 1 |
| `zombiesim_snow_draw_distance` (units; 0 culls only at opaque fog) | 2500 | 4500 | 0 |
| `zombiesim_screen_effects` (weather colour grading and film grain; frost edges remain) | 0 | 1 | 1 |
| `zombiesim_ambient_debris_amount` | 0.5 | 0.75 | 1 |

Gore quality, puddle opacity and film grain are preferences rather than performance settings, so the presets leave them unchanged.

# Dismemberment and Gore

`ZM_Gore` (`gamemode/sv_gore.lua`) decides every sever on the server. Bullets record their hitgroup in the zombie's `OnTraceAttack` (pellets in one tick are combined; the region with the most damage wins); melee resolves the nearest bone to the damage position. Regions are the left and right forearm, the legs, the head and the torso. A living zombie can lose a forearm (cosmetic stump) or its legs; legs turn it into a crawler (half walk speed, same damage, low hull) that keeps its model: the root bone is lowered by `Gore.CrawlerBodyOffset` so server hitboxes match the forward `swimming_all` crawl, and clients hide the leg chains. The head pops (blood burst plus the severed head) and the torso splits only on a killing blow. Living severs need accumulated region damage (arms 25% and legs 40% of max health); the chance is `damage / maxHealth × GoreSeverFactor × 1.6` (×1.5 on a kill, capped at 85%). `GoreSeverFactor` is set per weapon: melee 1.4, pistols 0.5, MP5 0.8, M4A1 1.2, AK-47 1.3, Scout 2, AWP and M3 2.5; other damage falls back by type (buckshot 2.5, slash 1.8, club 1.2, otherwise 0.6). Bosses can lose arms while alive and gib as corpses but never become crawlers. Severed regions are networked as the `ZM_GoreSevered` bitmask and carried onto the corpse, which keeps the zombie model, skin and pose and hides the severed regions. Rewards still happen once in `OnEnemyKilled`, and only the main corpse can be a loot spot.

`cl_gore.lua` draws cosmetic `ZM.Gore` events: blood impacts, wall/floor decals, severed limbs, stump spurts, aligned trails and short-lived pools. Hidden chains use scale 0.001, never zero, with guarded bone-matrix writes. NextBots capture the cut pose in `BuildBonePositions`; physics ragdolls explicitly set up their bones in a preserved `RenderOverride` and run the sever pass there when the engine skips the callback. Corpse masks retain all living severs plus the killing sever. Spurts/trails use cut points sampled during bone setup, not randomized body-center offsets; detached limbs use their rigid local cut point. Limbs keep the source model, skin and clothing overrides and fade after 60 seconds.

Rebel player models (`models/player/group03`) use the mounted male/female bloody clothing sheet on their exact clothing slot; their face/eyes, original HL2MP animations, health and rewards remain unchanged. Other clothing/model layouts are not blindly replaced with NPC models. `zn_gore_materials` reports the mounted player/NPC/bloody material definitions in an admin preview session.

`zombiesim_gore_quality` (0 Off, 1 Reduced, 2 Full; Options **Gore**) controls cosmetic effects without removing a crawler's missing legs. Reduced/Full limits are respectively: 4/12 limbs, 8/24 pending events, 4/12 spurts, 8/24 pools, 12/36 blood-effect requests per second and 6/18 decal traces per second, with separate frame caps of 4/12 effects and 2/6 decals. At most 2/4 detached models and 1/2 pools are built per frame; effects beyond 1,500 units are skipped. Engine blood decals are limited to 512 per client/map because they cannot be faded individually. Lowering quality immediately trims the queues and destroys excess models/meshes.

Pools reuse the puddles' flat-ground checking, lifted world-space mesh and depth/capture discipline, but have independent lifetimes: original feathered 24-triangle meshes form over two seconds, fade over their final ten seconds and expire after 90 seconds. Eight rim checks reject walls, kerbs and uneven ground. Meshes are destroyed on expiry, eviction, disabled gore and map cleanup. They do not alter weather puddles or add bloody footsteps; the existing rain footprint/upward-splash presentation is preserved. `zombiesim_dev_atmosphere_status` includes material availability, queues/caps, pool draws/triangles and corpse bone-processing diagnostics.

`zn_gore_sever <leftArm|rightArm|legs|head|torso>` severs a region on the aimed/nearest enemy. `zn_gore_probe on|off` creates/removes two harmless preview-only bloody walker/corpse fixtures, without rewards or Walker tickets; they expire after 120 seconds. `zn_test_gore` covers combat decisions, living-to-corpse masks, compatible clothing, queue disposal, request rates and pool lifetimes. Visual appearance still needs a running client.

## Movement balance

`gamemode/sv_movement.lua` owns walk/sprint scaling (0.90/0.85 of the unmodified speeds) and stamina rates. Implant movement bonuses apply afterward through the existing modifier service without compounding on refresh or spawn. Sprint drain is `60 / (1 + Agility * 0.05 + Strength * 0.03)` per second; recovery is `5.5 * (1 + Agility * 0.05)` per second. Maximum stamina and the held-sprint input rule are unchanged. Exhaustion limits speed to walking and preserves other inputs.

Run `zn_test_movement` for exact old/new percentages, refresh/spawn/implant behavior, sustained/interrupted sprint, clamping and exhaustion input tests. The suite also checks any deployed players' actual speeds/rates without changing their state. `zombiesim_dev_persistence_report` includes `runtime.movement` with captured baseline/current speeds, implant bonus, stat-derived rates, stamina and horizontal velocity for live pace checks.

Development bridge requests support at most 16 commands per batch. The bridge script rejects larger batches before dispatch and ignores stale acknowledgements without a request ID.

For controlled preview profiling, `zn_gore_quality_probe 0|1|2` temporarily selects Off/Reduced/Full without replacing the saved starting preference. `zn_gore_quality_probe restore` restores it; a 120-second safety timer and normal level shutdown also restore it. Pair this with the harmless `zn_gore_probe on|off` fixtures and verify quality/resource counts through the atmosphere report.

## Environment music and game audio settings

`content/data_static/music_definitions.json` registers seven existing recordings under stable city A-D and sewer A-C IDs, independently of their filenames in `content/sounds/music`. Durations were measured with the installed `ffprobe` and are checked against GMod's actual decoded lengths. City/default dens use city variations; the origin Storm Drain den and `metro_station`/`metro_route` environments use sewer variations. Explicit safe-zone IDs can override the origin/default mapping. Environment priority is authored, not dependent on tag iteration order; unknown tags, routes, IDs, missing files, duplicates and invalid durations reject the static load.

Playback is environment-driven, not combat-triggered. It starts after a random 8-12-minute silent interval and schedules another interval after a track ends; it never cuts a song off on an idle timer. One BASS channel is owned at a time, with stale asynchronous callbacks stopped. Departure fades follow the transition fade. Cell-to-cell travel within the same track set resumes the saved position; travel into a different set fades in a destination track immediately after loading. Den entry starts a destination track if music was playing. Leaving a safe zone while its track is playing ends that track and starts a fresh 8-12-minute silent interval, even if the entrance cell uses the same set. Travel during an existing silent interval preserves its deadline. Local presentation state, track routing context and the pending idle deadline persist under `DATA/zombiesim/music_<profile>.json`; loading/launcher holds, disabled music and zero music volume pause playback. A failed playback reports its decoder/duration error and tries a different available default variation once, then schedules silence rather than retrying forever.

Music directly follows Garry's Mod **Music volume** (`snd_musicvolume`), with `zombiesim_music_enabled` as the optional ZombieSim enable switch. Both Options panels display the current engine **Master volume** (`volume`), **Sound effects volume** (`volume_sfx`) and **Music volume** values read-only. Garry's Mod [blocks Lua from changing these convars](https://wiki.facepunch.com/gmod/Blocked_ConCommands), so adjust them in Garry's Mod's own Options > Audio. The BASS channel applies the music slider once; the engine retains master scaling. Geiger, weather, footsteps, weapons and UI cues use Source sound APIs and retain native master/SFX scaling without a second Lua multiplier. Music ducks by at most 45% during active Geiger exposure to preserve warning audibility.

Reference: the GMod wiki documents [BASS playback](https://wiki.facepunch.com/gmod/sound.PlayFile) and [seeking](https://wiki.facepunch.com/gmod/IGModAudioChannel:SetTime); [Facepunch/garrysmod-issues#5532](https://github.com/Facepunch/garrysmod-issues/issues/5532) explains why Source music path modifiers cannot classify BASS channels. Installed-build `help volume_sfx`, `help snd_musicvolume` and `help volume` confirmed the current category controls. These values are never reset by ZombieSim.

Run `zn_test_music` for registry/routing/variation/idle/resume validation. In an admin preview, `zombiesim_dev_music assets` silently decodes all seven files and validates their actual durations; `play` starts the currently resolved set immediately for a listening check, `default`/`sewer` selects that test set, and a catalogue ID such as `cityB` or `sewerA` tests that exact file. `status` writes `DATA/zombiesim/music_status.json`; `zombiesim_dev_atmosphere_status` also includes resolved route, track, position, gain, game audio values, resume save status and asset results. Test probes do not change the audio preferences. Auditory fade/volume and ordinary cell/den transitions still need a running-client check.

Top-down and orbit cameras send level aim from the centre of mass, which passes over a crawler. `ply:GetLevelAim` (`gamemode/sh_player.lua`) therefore dips a level command onto the nearest live crawler (`ZM_GoreSevered` legs bit) whose position lies within 24 units of the facing line and 2048 units ahead, unless a wall or another entity blocks the level line first. The target comes from networked entity state on both realms, never from the client, so the crosshair, shots, melee and recoil share one result; shoulder aim (a cursor pitch) and den aim are unchanged. `zn_test_inventory` covers the rule.
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
