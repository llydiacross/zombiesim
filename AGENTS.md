# ZombieSim Agent Guide

ZombieSim is an installed Garry's Mod gamemode. It combines realm-specific Lua gameplay code with a PowerShell pipeline that generates and compiles reusable Source VMF recipe maps.

## Active Task Tracker

- **Fixture-review preference:** when the user chooses to inspect fixtures,
  open the exact requested VMFs in the installed Hammer++ for them; do not
  merely provide paths or ask them to find the files. Identify which opened
  fixture covers each review case. Preserve unsaved editor work and do not
  treat opening a fixture as visual acceptance.

- **Active milestone: [Alpha 3.1.5](todo-alpha.3.1.5.md).** The user authorized
  implementation on 2026-10-06 after adding the edge tiles. Phase 0 is accepted:
  nine edge sources inventoried, current 179-recipe baseline and verified
  restoration copies retained, focused launcher baseline captured. User carried
  coast/gate photographs and full quality/cold-warm baseline into A/B/G; do not
  reopen Phase 0 for those limits. Preserve approved source overhangs.
  **Phase B is in progress**, then follow Phases C-I in order. Shared bounds,
  deterministic outer-ring generation and layout metadata are implemented but
  disabled in normal settings. Isolated checks: outer edges 519 assertions,
  GLua 184/0, border showcase/entrances pass, ten VBSP/portal fixtures pass,
  BSP entity checks retain 287 corrected dynamic props, live bounds 6/6 in the
  preview launcher. Human confirmed north-facing straights and NW-opening
  corners, and approved class-only correction of 15 incompatible new-edge
  trees/signs; original brush/prop placement and overhangs are unchanged.
  User accepted both land/coast Hammer fixtures on 2026-10-06 after the agent
  opened them in Hammer++; the user closed the editor windows after review.
  User subsequently accepted both enlarged land/coast in-game geometry
  reviews in Sandbox. Two isolated BSPs completed VVIS/VRAD without failures;
  temporary runtime copies were removed after verified return to
  `zn_preview_start`/preview. Before/after city and preview survivor persistence
  snapshots match exactly; live bounds remain 6/6. This is geometry acceptance,
  not integrated ZombieSim pursuit, loot, skyline or gate acceptance.
  **Phase A is accepted**; the user authorized Phase B on 2026-10-06,
  carrying integrated pursuit/loot/gate checks into later phases. Generated
  fixture sources/zoos are under `generated/outer_edges`; no enlarged maps,
  skyline or runtime exports staged. Gates/transition-road blocking geometry
  still require the planned Phase C migration. Preview-first; production
  city rebuilds and Workshop publication require separate approval. The supplied
  logo, exact globe asset clearance and live baseline gaps are explicit gates,
  not permission to guess. No phase is accepted solely by static checks.
- Phase B source/isolation checks now pass: shared 5760 pitch, schema-2
  plan/bounds/coast compatibility, recursive source hashes and complete model
  companion caches. User explicitly retained the original procedural beach
  beyond the 2240 coast edge; do not replace it with a water-only strip.
  Six isolated skyline fixtures: 177 assertions, manifest/tower/height pass,
  VBSP/portals 417/1317 maximum; installed legacy manifest 179 recipes still
  passes. GLua186/0, fresh isolated geometry8/8, packaging57/57.
  `generated/skybox_edges` contains models/room/VMFs/reports; none staged.
  Fresh expanded renderer visuals and matched performance remain Phase B
  gates. Launcher reloads verified logic only, not renderer appearance.
- **Coast clarification 2026-10-07:** the requested fixture is the Storm Drain
  grid `(0,12)` / logical `(0,0)`, not the SE authored water-corner fixture.
  Omit new outer scenery only along the west 3D-skybox ocean; preserve all old
  border and water-corner tiles. `skyboxOceanSides` drives omission/renderer
  attachment separately from `waterBorderSides`. West recipes use
  `-oceanw-edge2`; expanded preview187 recipes vs unchanged legacy179.
  Exact Storm Drain has21 unchanged border pieces,23 outer pieces,zero west
  outer pieces. West skybox shoreline attaches at-2240, not-2880; its640-unit
  band fills the gap while retaining the approved beach. Skyline275 assertions/
  eight recipes, outer1158/exact old source transforms, original border/entrance
  suites and VBSP/portals474/1517 pass. New no-gap live case not run
  because game closed; expanded visual review remains pending. Do not stage
  or treat earlier SE-corner review as approval of this corrected coast.
- Alpha 3.1.0 development is complete: the user
  accepted final Phase H and the milestone on 2026-10-06 after a bounded fresh
  launcher check. [docs/todo-alpha-3.1.0.md](docs/todo-alpha-3.1.0.md) archives
  its evidence and validation limits. Do not reopen accepted phases or infer
  work from historical pending lists.
- Final live checks: renderer 8/8, catalogue/materials 78/78 and
  browser/flight/fog/cleanup 15/15. Human confirmed smooth automatic tour,
  replacement night, soundtrack fade, blackout and return. The captured
  Coastal tour is scoped CPU operation evidence, not a matched/GPU benchmark.
  Final preference/audio/return-state capture was rejected because no connected
  preview admin was available; retain that limit separately from human review.
  User subsequently confirmed Default restored and returned to their survivor.
- Workshop release remains separately deferred: rights/IDs, navmeshes,
  production export/skyline and clean mounts/downloads. Version status is
  `in development` for Alpha 3.1.5, not `released`; no production rebuild/upload
  is authorized. Preview remains the default for approved iteration.

### Archived Alpha 3.1.0 chronology

The notes below record earlier decisions and evidence. Their pending/active
wording is superseded by the final acceptance above, not a current task list.

- The user accepted Alpha 3.0 on 2026-10-04; [docs/todo-alpha-3.0.md](docs/todo-alpha-3.0.md) archives its implementation, regression/live evidence and retained validation limits. Its uncaptured checks are historical limitations, not new Alpha 3.1.0 work.
- Alpha 3.1.0 Phase E is accepted; the user carried remaining sign integration into Phase G. Phase F Wardrobe and revised spiral fabric direction are approved. Filename/fabric catalogue builds; actual client pool regressions pass 5/5 after fixing owned-material pins and failed-build retries. Generated equipment survives reload and independent restoration with exact original inventory cleanup; scoreboard composition moved to PreRender after a verified clipping regression. Cuff-anchored/opposite-limb/front-back calibration, real gore visuals, bloody/walker variants and representative performance remain pending; Phase F is not accepted. Optional client-local sky palettes are Phase H; settle imported provenance and baked-light compatibility before staging/distribution.
- Clothing follow-up: the user subsequently requested hundreds of fabrics, smooth high-detail dye, centred `_chest` artwork and fixes for visible full-back/repeating-back seams. Source now expands to 206 fabrics, supports pink/chest and uses inspected torso-triangle back projection. Physical continuity checks pass 38/38 and rebuilt prototype checks 248/248. Full expanded catalogue staging and fresh human visual review are the immediate gate; do not carry the earlier spiral approval forward as approval of these new outputs.
- Latest clothing direction supersedes combined front/back shirts: user approved enlarged/lowered chest, requested removing combined shirts, raising back prints, colourful untagged backgrounds (explicit light/dark rules unchanged), and raised left/right thigh prints. Published790finishes/792Wardrobe/3178owned files, matching896finish caps and unchanged16target pool. Both thigh placements pass actual topology checks118/118; built catalogue5124/5124, fabrics2754/2754, prototype266/266 and fresh preview static18/18/inventory51/51 pass. Human review of the newest back/thigh/palette outputs remains pending. Do not repeat earlier accepted chest/dye/back-fix questions; review only the newest placement/palette changes.
- Distribution work is authorized within Alpha3.1.0 before further large content expansion. **Both city and preview ship; preview is the player sandbox.** `workshop-settings.json` and `bin/build_workshop_packages.ps1` own allowlisted inventory, report-only exclusions/orphans, byte-budget shards and isolated staging/GMA verification. Never delete reported unowned assets automatically or migrate the installed development tree. Strict release is blocked by missing navmeshes, legacy city export/no city skyline manifest, rights clearance and final Workshop IDs; no production rebuild/publication is authorized by packaging work. Packaged manifests/markers enforce compatibility and deployment gates; loose development remains unchanged. Clean package mounts/downloads and human visual checks remain separate acceptance gates.
- Launcher Content Addons/Recheck/Back UI is user-approved in loose preview. Core owns both launcher BSPs. Settings use safe `pending:<package-id>` labels, never fake numeric Steam IDs; real IDs are assigned by creating private Workshop items, then rebuilding/updating those same items. Builder does not upload. Subscription/download/mount states are distinct and mounted compatibility gates deployment, not subscription alone. Fixtures46/46/live distribution9/9 pass; actual published-ID and clean-mount acceptance still deferred until publication.
- Cuff-up extension is published and user-reviewed on male/female left/right sides:866finishes/868Wardrobe/3482ownedfiles. Separate bottom-aligned `pants_cuff`/`pants_cuff_right` presets preserve all790priorfinish/itemdefinitions and ownedfiles; `_pants_cuff` permits artist opt-in restrictions. Artwork25/25, topology134/134, prototype306/306, published7319/7319, fabrics2754/2754, GLua175/0; fresh live static18/18/distribution9/9/pool5/5. Package audit6659files/7packs remains within shard budgets;387releaseblockers unchanged. Rear-facing limbs, bloody/walker integration and representative animation/gore/performance remain unfinished; cuff review is not Phase F acceptance.
- Rear-limb artist tags and placements now implemented/user-approved for all eight male/female left/right rear thigh/upper-arm combinations. No rear-tagged PNGs currently; default866finishes/896cap unchanged. Parser106/106,topology170/170,prototype370/370,published7335/7335,GLua175/0. Temporary live fixtures removed,inventory/equipment untouched. Next is bloody/walker integration: mountedgroup03inspection48/48 shows2048sheets/differentUVfingerprints, so survivor1024charts are not approved there. Separategroup03report preserves defaultinspection; group02player path failed lookup and is unverified. Preserve existing gore overrides/material copies and unsupported-model appearance. Phase F remains unaccepted.
- Offline Phase F continuation: user chose shared original blood overlays, not duplicateitems/budget expansion. `build_clothing_blood.ps1` stages3sharedlayers/6files (~4MiB); exhaustiveblood32/32, survivor170/170, independentlynamedgroup03charts/fullbodytriangles56/56, catalogue5753/5753, packaging47/47, GLua175/0. Preview-onlyWardrobeBLOODtoggle and clean/bloodypoolkeys implemented; newclientpoolcases/render/gore acceptance **not run: game closed**. Group03diagnostics remain mask-unapproved; existingnativewalkerblood unchanged. Run chart writers serially for isolation checks. Actualaudit6681files/7packs/387releaseblockers; no maps/uploads/inventory changes. Phase F still needs live blood/gore/performance and independently calibrated walker clothing.
- [docs/todo-alpha-2.9.2.md](docs/todo-alpha-2.9.2.md) archives the completed client performance and quality-presets milestone (accepted 2026-10-02); its baseline and validation remain useful for Alpha 3.0 comparisons.
- Current Phase F evidence supersedes the closed-game/group03 next steps above:
  the user approved blood preview, all fifteen independently calibrated group01
  citizens and actual citizen walker/corpse/detached-piece appearance. **Never
  apply catalogue clothing to rebels**; preserve their native mounted blood.
  Engine mesh transfers pass80/80; no per-model catalogue texture duplication.
  The user subsequently chose independent full-catalogue outfits per zombie,
  not a shared outfit per model/cell, and approved96 shared targets (~384MiB
  maximum RGBA storage plus source/material memory). Individual/ticket identities
  preserve outfits through blood refresh and immutable corpse/limb copies.
  Pool-only publication retains866finishes/868Wardrobe, now3642ownedfiles;
  catalogue8035/8035, packaging48/48, GLua175/0. Live Gore16/16, static18/18,
  inventory51/51, clientpool9/9; the enlarged stress test initially froze/flushed
  the renderer, so capacity/citizen tests now run across frames and passed9/9 again.
  Runtime composition uses a2ms soft frame budget; individual cold builds can
  exceed it. Verified15same-model independent outfits and15mixed-model composites.
  One clean warm mixed-crowd run measured60FPS/0.02034ms clothing-hook average;
  cold builds16.807ms mean/21.452ms max and a failed/stale native-control comparison
  remain validation limits. Actualaudit6842files/7packs/387blockers. Owned probes
  removed, quality restored, survivor alive at preview22,0.
- The user subsequently **accepted Phases F and G on 2026-10-05**, explicitly
  confirming existing checks/earlier skybox reviews are sufficient and asking
  to proceed directly to **Phase H**. Do not repeat Phase G regeneration or
  visual checks merely to close historical checklist entries. Uncaptured
  cold/lifecycle/matched-performance and sign integration checks remain
  validation limits, not pending phase gates; no new checks are implied by
  acceptance. Workshop release rights/IDs/navmesh/production export/clean-mount
  blockers remain deferred. Phase H source eligibility and palette/control
  decisions must be settled before changing the optional client sky renderer.
- Phase H's first-selector source choice is approved: mounted game skies plus
  original procedural palettes; uncleared imports remain excluded. Reference
  mounted paths without extracting/copying assets. Palette/control design and
  actual renderer appearance remain separate implementation decisions.
- Phase H prototype now uses `cl_sky_palettes.lua`: saved Default/Natural/
  Cinematic Options, original context gradients and temporary individual
  preview commands. Default remains native; no BSP relighting or server weather
  changes. Natural daytime layering is user-reviewed. Mounted `sky_day03_06c`
  remains a development candidate, referenced in place. Measured texture-edge
  matching corrected side/top mapping; a subsequent tiny seam was fixed with
  half-texel UV insets without changing rotation. User confirmed seam gone
  after fresh reload; live5/5, GLua176/0. Do not repeat accepted F/G checks.
  Phase H still needs context/persistence/reset/launcher/den/capture/weather/
  performance review and final palette membership. Publication stays deferred.
- Phase H UI follow-up supersedes the dropdown/preview-only restriction:
  user chose automatic palettes plus locally saved individual skies. The
  thumbnail browser offers12cards, context warnings and parent-safe Back/X/
  Escape cleanup; mounted sky remains outside automatic palette membership.
  Options has9collapsible sections and a friendly engine-owned audio notice;
  existing controls/precision/presets/server guards retained. Fresh GLua177/0,
  renderer7/7, browser/Options5/5; user confirmed grid/grouped Options, saved
  selection/reopening and restored mouse/camera control look/work correctly.
- Latest Phase H palette UI replaces state dropdowns with four clickable
  preview slots on the left and individual/native thumbnail choices on the
  right. Built-in Edit creates a personal copy; custom Edit retains its ID.
  Draft assignment/cancel never changes the saved choice. Expanded browser and
  revised editor are user-approved: all four slots visible and picker works. The catalogue
  now has82individuals/12built-ins/36imports,432materialfiles/391.48MiB;
  supplied-author permission specifically clears the additional nine sets
  including MR53. Retain original README files in `data_static/sky_licences`
  and common packages. Assets2383/2383, packagefixtures50/50, GLua180/0;
  fresh renderer7/7, UI/inspection9/9 and materials76/76 pass. Deferred parent
  cleanup is fixed; ordinary editor heights show all four slots. New full-cube
  appearance/aerial-render human review remains; no map builds/publication or F/G redo.
- Latest H continuation adds six automatic variants (18built-ins total), using
  all new sets except John Tron at the user's explicit request; keep that sky
  individual/custom only. User approved variants and real aerial preview/return.
  Fresh renderer7/7, browser9/9, catalogue/context78/78, GLua180/0. Isolated
  weather/light boundaries pass; real weather visuals are not thereby accepted.
  Actual selected custom "Test" (`custom_1`/dusk `imported_mr53`) survives preview
  changelevel with six meshes and byte-identical store. Leave user's custom
  selection active. H still needs live weather/context, launcher/den/map-capture
  and representative performance; do not reopen F/G or deferred publication.
- H live continuation: user confirmed rain/Level-view return, normal den
  first-person/Options round trip and launcher Options. Profiler now includes
  PostDraw2DSkyBox; warm Natural draw CPU0.04866ms/frame is scoped operation
  evidence, not native/GPU comparison. User paused to author a **launcher-only**
  preview area in Hammer with point_camera `Preview_skybox`: camera-only
  position/angles, no survivor teleport; replaces launcher upward sweep only,
  not implemented yet. City cells retain their existing sky/current preview;
  do not add areas or rebuild city templates for this request.
  Weather scheduling restored/verified auto1/manual0. Client remains at preview
  launcher; when ready restore/verify Default and slot2 Jim at logical22,0
  (raw22,12), safe-zone none. Do not move them or rebuild maps while paused.
  Options sections default closed and persist each section's open/closed state.
  The preview-launcher-only TOOLS tab is user-approved. Its left column offers
  Wardrobe, Item/Map Atlas, Sky browser and Content Status. Atlases and Content
  Status use the right side of the launcher frame, not a hub window. Tools are
  read-only; Back/Escape always returns to the main menu, and the window tools
  sit below a rule. Live tests pass: Tools4/4 and browser/Options10/10.
  `content/data_static/version.json` is the single version source; update it
  (and the matching `changelog.json` entry, marked `+`/`-`/`?`) whenever a
  milestone, phase or release status changes. Packaging blocks release until
  its status is `released`. Pre-2.6 changelog entries are reconstructed guesses.
  Full H is not accepted: fresh-load archived persistence, automatic weather/
  context, launcher/den/map-capture and visual/performance gates remain.
- Clothing repeat rules (2026-10-06): placed art has no repeat unless
  `_repeating`; `_notrepeating` suppresses it; new `_sleeve_cuff`/`_sleeves`
  hem placement (`sleeve_cuffs.json`). Published698finishes/2994ownedfiles;
  builder prunes unreferenced caches and unowned staged `catalog_*` files. Static
  suites pass. Follow-up: sleeve canvas is now 112x200 (flames climb from the hem);
  new two-piece `sleeve_cuff_both`/`pants_cuff_both`. Published735finishes/
  3142ownedfiles; static suites pass, live pool9/9; human review pending.
- Launcher follow-up (2026-10-06): user confirmed perfect 3D-sky alignment,
  added invisible G-Man support and saved both launcher scenes. Preserve those
  authored edits. Launcher-only sky inspection now takes off from its authored
  island camera into an eased banking flight; shared pose/PVS, obstruction
  checks and render-scoped selected-sky haze are implemented. Main menu/credits,
  city/den sweep, gameplay weather and baked lighting remain unchanged. Static
  GLua183/0 and mocked-engine Lua flight/fog3786assertions pass; game closed,
  so new live browser cases, route clearance/PVS and motion/haze/performance
  review remain pending. No maps rebuilt; Phase H still unaccepted.
- Latest launcher continuation: user approved flight/haze appearance but reports
  lag. Launcher flight now replaces the main RenderScene (no second panel scene)
  and excludes the menu globe. Automatic profiles tour their four existing
  Day/Overcast/Dusk/Night slots over20seconds; individuals retain10seconds,
  saved choice/serverweather unchanged. GLua183/0 and71mocked tour/render tests
  pass; fresh live tour and matched performance remain pending. User closed
  game and authorized both latest authored launcher builds: preview/city
  VBSP/VVIS/VRAD and staged hashes pass. No world-cell maps regenerated; Phase H
  remains unaccepted.
- Sky retirement (2026-10-06): user requested removing Tropospheric night1
  without diagnosis. Published35imports/420materials;81individuals/18builtins.
  Tropospheric1-3/World'sEnd night slots now use night2; other assignments and
  individual/custom-only JohnTron unchanged. Saved selections/custom slots
  migrate to night2 with custom backup; source/old loose files preserved but
  current sky ownership excludes retired materials from packaging. Catalogue
  2319/2319,GLua183/0,packaging53/53,offline migration90assertions pass.
  Fresh live removal/replacement/migration review remains pending.
- When a milestone runs, phases proceed in order and each phase gets focused static/automated checks as changes land; fix failures before advancing and record static and live results separately. A phase is accepted only on the user's confirmation; a successful map compile alone does not establish in-game acceptance.
- [docs/todo-alpha-2.9.1.md](docs/todo-alpha-2.9.1.md) archives the completed compiler-pool, preset, generation-diagnostics, portal-budget, and test-organization milestone.
- `docs/todo-alpha-2.8.6.md` remains as milestone history and source context for the safe-zone contract and Storm Drain work that landed before the current cycle.
- `docs/todo-alpha-2.8.5.md` and `docs/todo-alpha-2.8.md` are historical context only unless explicitly promoted back into the active tracker.
- When the active milestone changes, update this guide and the root tracker together; do not infer current work from historical phase labels. Archive a completed tracker in `docs/` and re-root its relative links.

## Read First

- [readme.md](readme.md) contains the supported build, staging, in-game, and Walker simulator command sequences.
- [docs.md](docs.md) is the generator reference, including profile behavior, authored tile orientation, Hammer checks, and compile diagnostics.
- [docs/gdd.md](docs/gdd.md) describes intended gameplay behavior. Consult it before changing player progression or survival systems.
- [generator-settings.json](generator-settings.json) is the authoritative configuration schema. Do not infer settings or output paths from filenames.
- [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md) describes multi-tile template work.
- `bin/walker-simulator` is the portable C++ walker project; it stays isolated from Lua and generated assets, and its behavior and commands are documented in the root README.

## Source-First Engine and API Work

- Consult the [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/) for GLua functions, hooks, realms, signatures, return values, prediction, and documented caveats before introducing or changing an unfamiliar API call. Consult the [Valve Developer Community](https://developer.valvesoftware.com/wiki/Main_Page) for Source entities, keyvalues/inputs, materials, Hammer, and compiler behavior. Do not guess API names, flags, entity behavior, or engine limitations.
- When documentation leaves a concrete question unanswered, inspect relevant public [Valve Source SDK 2013 code](https://github.com/ValveSoftware/source-sdk-2013), which includes HL2, HL2:DM, and TF2 game code and tools. It is not the complete engine source or an exact representation of Garry's Mod's engine branch. Use it as evidence with branch/version caveats, not proof of GMod behavior.
- For lighting questions such as what `light_environment` does, distinguish runtime entity behavior from VBSP/VRAD processing and baked BSP lighting; inspect the relevant game/tool implementation where available rather than inferring behavior from an entity name or keyvalue.
- Record the relevant wiki URL or SDK file/revision with a non-obvious finding. If a source is inaccessible, say so; do not claim it was verified. Use known local implementations and a small targeted in-engine probe for remaining GMod-specific uncertainty. Read public sources in place where practical; do not install another SDK, rebuild maps, or copy SDK/Valve assets into this addon merely to answer a reference question.
- Reuse established repository architecture and previously verified findings. Reading the relevant owner before editing is necessary; repeating a project-wide realm audit or prototyping documented standard APIs is not. Feature-specific decisions and uncertain behavior belong at the start of their owning phase, not in a milestone-wide research prerequisite.
- Try publicly available archives before treating an inaccessible live wiki page as a research blocker.


## Runtime Architecture

- Keep Lua realm boundaries explicit: `init.lua` and `sv_*.lua` are server-side, `cl_*.lua` is client-side, and `shared.lua` / `sh_*.lua` run in both realms. Send shared and client files with `AddCSLuaFile`, then `include` files that must execute on the server.
- Preserve the existing Lua style: `//` comments, spaced function calls, four-space indentation in server files, and tabs where an existing shared/client file already uses tabs.
- World data is accessed through `ZM_World`; safe-zone lookup is owned by `ZM_SafeZones`. Use their APIs rather than duplicating coordinate, map-path, or profile resolution logic.
- Server services share small helpers through `ZM_Util` (`gamemode/utils/server.lua`: first human, profile, whole-number checks, console replies, admin gates, command registration). New `zn_test_*` suites use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`). Alias these instead of redefining local copies.
- Work that runs behind the loading screen reports progress through `ZM_Loading` (`gamemode/sh_loading.lua`): `Step`, `Begin`/`Finish` (pending then `ok`/`warn`/`fail`/`info`), and `Reset`. Server calls take a player target; client calls are local. Use it for new load-time work, including future online services, instead of custom loading text.
- `sh_music.lua` must load before `sh_static_data.lua`, which builds its registry during include. Music uses the engine `snd_musicvolume` control; Source effects retain native `volume_sfx`/master scaling. Do not multiply master/SFX volume again on Source audio calls.
- Register network strings on the server before sending. Keep player persistence server-only through the SQL helpers and retain profile scoping.
- The future online-services API is maintained separately in the root `api/`
  Git submodule; see [`api/README.md`](api/README.md) for its current project
  behavior. It is not yet integrated with live gamemode features. Before any
  API integration, inspect that README and its repository instructions, define
  the client/server trust boundary and request contract, and keep secrets out of
  the client and source control. Steam OpenID proves browser account ownership,
  not live GMod presence; the API README requires a separate server credential
  for presence reports. Preserve the API submodule's independent history and
  any pre-existing changes; do not modify or commit API implementation work
  unless the task explicitly includes that repository. The submodule's current
  remote is GitLab (`git@gitlab.com:gcnet-uk/games/zombiesim-api`); verify
  `.gitmodules` rather than assuming a hosting provider.
- Treat raw grid coordinates as diagnostics only. Display and manipulate logical world coordinates through `ZM_World`; for a cross-map change, verify persisted `CellX`/`CellY`, safe-zone id, and resolved map path with `zombiesim_player_status` after the destination loads.
- Before changing a request involving a “map,” identify the intended surface: the world-map window, HUD minimap, satellite/level view, or Garry's Mod level transition. Locate its owning module and input binding; ask a focused question when the request does not distinguish them.
- Before adding client-side GLua or Derma calls, confirm the API signature from a compatible local call site or current Garry's Mod documentation. Validate new client scripts for syntax and exercise prompt first-run, decline/reset, and reopening paths.

## Generator And Asset Boundaries

- Hand-authored tile VMFs live in `tiletemplates`; base maps, launcher VMFs (`celltemplates/launchers`), and standalone safe rooms live in `celltemplates`. Edit these source assets, not generated files in `generated/src*`.
- `content/` is distributable addon content only. Keep compiler logs/reports/intermediate BSPs and other developer outputs under `generated/`; launcher compiler output belongs in `generated/launcher_build`, while required packaged BSPs/materials remain under `content/`.
- Treat generated manifests, plans, VMFs, BSPs, staged profile maps, runtime JSON, and map materials as pipeline outputs. Regenerate them with the matching profile rather than hand-editing them.
- Every generator script must resolve settings through `bin/resolve_world_generation_profile.ps1`. Use `-WorldProfile preview` for normal iteration; it is isolated from the production `city` profile.
- Preserve canonical rotations and carpark endcap rules. `bin/carpark_endcaps.psm1` owns carpark cap selection and yaw; do not duplicate or derive it from lane role. Confirm orientation changes in Hammer.
- Before changing a placement or yaw mapping, inspect the canonical authored orientation and the exact generated `func_instance` that fails. Validate all four cardinal outputs plus any affected exceptional recipe in the developer zoo; never apply a global yaw offset from a single screenshot or recipe.
- For a visual placement report, identify the selected instance and express the intended relationship in logical tile coordinates and cardinal directions. If the screenshot does not establish whether a piece should be edge-adjacent or in-line/in-front, ask one focused clarification before changing placement logic.
- Before diagnosing or validating a generated layout, resolve its exact recipe filename from the current matching plan, rebuild that recipe from current inputs, and confirm the inspected VMF's instance name, source template, origin, and angles. Do not infer freshness or behavior from a similarly named recipe or an older zoo output.
- Do not change a native model's `ModelOffset` to correct Backrooms placement. Correct the generator's block-cell placement.
- Standalone safe-zone maps are complete templates copied unchanged. Edit `celltemplates/safezones`, not their generated copies.
- Before changing a placement, orientation, or UI layout direction, restate the intended relationship in logical coordinates and cardinal directions, including whether it is edge-adjacent, in-line, in-front, left, or right. If the visual evidence leaves that relationship ambiguous, ask one focused clarification before editing.
- Treat generated plans, VMFs, BSPs, navmesh outputs, and runtime exports as potentially stale until the current matching input is resolved and the affected output is regenerated. Validate the exact artifact that was produced, not a similarly named or previously inspected file.

## Focused Validation

Run PowerShell commands from the repository root. For changes to planning or VMF generation, use the preview pipeline and start with the fast structural check:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

- After structural tile changes, run `./bin/check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData`; inspect affected layouts in Hammer, including generated developer zoos when applicable.
- For planner yaw changes, extend and run focused regressions for the reported recipe and previously correct affected cases before broad regeneration. Building frontage changes must pass `./bin/test_building_frontage.ps1` and `./bin/test_multi_tile_templates.ps1` before refreshing the preview plan and VMFs.
- Only use `-SkipVBSP` with `-SkipRecipeRefresh` when the source VMFs are unchanged from the portal preflight. Review `generated/build_<profile>/compile-report.json` for failed or incomplete stages.
- Builds are incremental: `build_cell_vmfs.ps1` writes a generated VMF or den copy only when its content changed, and `compile_cell_vmfs.ps1` / `check_vis_budgets.ps1` recompile a map only when its BSP is missing or the VMF or any `func_instance` it references (recursively, via `bin/vmf_source_dependencies.psm1`) is newer than the build output. Before a compile, state which maps a source edit affects. Do not pass `-Force` or `-ForcePortalData` for routine rebuilds; reserve them for compiler/config changes or a deliberate clean build.
- A full VVIS/VRAD build and in-game launch are deliberate final checks. Batch related changes before launching Garry's Mod; reload `zn_preview_start` after preview staging or `zn_city_start` after city staging.
- For iterative Lua live checks, use Garry's Mod's available hot-reload workflow instead of closing and relaunching the game. When a clean map/spawn cycle is needed, `changelevel <current-map>` reloads the same map without closing the client; verify the destination and player state before interpreting the result.
- For `cl_*.lua`, camera, Derma, and map-transition changes, parsing or compilation is only static validation. Do not report behavior as verified until the affected input path has been exercised in a running client; otherwise state that an in-game check remains.
- For visual results (fades, camera motion, outlines, prompts, highlights, placement), ask the human at the running client to look and report before building automated probes. Use the bridge for state evidence such as `zombiesim_player_status`, not as a substitute for eyes.
- After any Lua change, run `./bin/test_glua_syntax.ps1` for an offline GLua syntax check. It uses the `gluac.exe` bundled with the GLua Enhanced VS Code extension (Garry's Mod's own `lua_shared.dll`), so `//`, `!=`, `&&`, and `continue` parse correctly. Stock `lua`/`luac` cannot parse GLua. This checks syntax only, not GMod APIs or realms.
- For runtime changes, use a two-part validation matrix: run the narrowest static or automated check first, then exercise the affected in-game command, input path, persistence transition, or client flow. Report static success and live success separately, and explicitly state when live verification remains.
- In long implementation sessions, create or refresh a checkpoint after each subsystem boundary and after a failed validation loop. Record the current hypothesis, exact artifact or command under test, result, and next discriminating check before moving to another subsystem.

## Environment Notes

- The repository is already under Garry's Mod. The active compiler profile resolves `vbsp`, `vvis`, and `vrad` from the game's `bin` directory.
- To find or verify a model or material, list the mounted game VPKs with the installed `GarrysMod\bin\vpk.exe l <path-to-_dir.vpk>` (for example `sourceengine\content_hl2_dir.vpk` or `garrysmod\garrysmod_dir.vpk`) and reference the mounted virtual path. Do not search the user's `addons` folder, and do not extract or copy Valve content into the addon.
- The development command bridge source is `content/data_static/consolecommands.txt`; its acknowledgement is deliberately written outside the repository to Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`.
- Send bridge requests with `./bin/invoke_dev_bridge.ps1 -Command '<cmd>'[, '<cmd>']` instead of hand-written wait loops. It returns the result JSON (exit 0) and waits for the reloaded map after `changelevel`. Exit 2 means the server heartbeat (`data/zombiesim/consolecommands.heartbeat.json`) is stale: the game is paused in the Escape menu or loading, so ask the player before resending. Exit 3 means Garry's Mod is not running; exit 4 means a ticking server ignored the request.
- For cross-map command automation or `buildcubemaps`, first run a one-command in-engine capability probe and verify its bridge acknowledgement. Confirm permissions and persistence before implementing a sequencer; retain a single-step manual command fallback.
- Never invoke `lua_*` commands (including `lua_refresh`) through the development console bridge; Garry's Mod security restrictions block that route. To reload changed Lua during a preview test, use `changelevel <current-map>` after confirming the active profile and map. Do not try alternate bridge/RCON paths for Lua execution or refresh.
- Starting `zn_preview_start` puts the client in the launcher/character main-menu flow, not in deployed gameplay. Wait for any briefings and the character menu, deploy an existing appearance-complete survivor, then enter the intended den or city cell before running gameplay/live checks. Confirm the loaded map and player state after transitions; do not treat a connected menu player as deployed.
- Scripts use `Set-StrictMode` and `$ErrorActionPreference = 'Stop'`. Retain parameter validation, path construction via `Join-Path`, and profile-driven paths. In Windows PowerShell 5.1, use `System.Diagnostics.Process` for monitored compiler processes because `Start-Process -PassThru` can expose an empty `ExitCode`.