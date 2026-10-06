# Alpha 3.1.0

Status: **ACTIVE — authorized by user on 2026-10-05.**
Current phase: **Phase H — optional user-selectable sky palettes; Phases F and G accepted by the user on 2026-10-05.**

## Milestone Rules

- Work in the order below. Resolve decisions in Phase 0 before implementing dependent behavior.
- Use the isolated `preview` profile and a stable seed (`1337`) for comparisons. Do not change or stage production `city` outputs during ordinary iteration.
- Treat authored tile VMFs, settings, and generator code as sources; regenerate plans, recipes, skybox models, and manifests through their owning scripts.
- Run focused structural and automated checks as each phase lands. Report static/build results separately from live and visual checks.
- Before preview compilation, identify affected recipes. Inspect compiler reports and generated skybox-model manifests rather than assuming a successful command produced complete output.
- Before a broad compile, report the unique required BSP count, its change from the prior accepted plan, and the likely time impact using observed build times. Warn the user and obtain approval before proceeding with a material count/time increase. The user's prior reference is approximately 170 maps in 15 minutes; do not treat a much larger build as routine or promise a linear time estimate.
- Center-weighted skyscraper placement must preserve recipe reuse wherever the realized layout is identical. Selection probabilities and world-cell positions are not, by themselves, reasons to create additional BSP recipes. Measure the revised count and verify the accepted taper before any resumed broad compilation.
- Obtain user visual acceptance for skyline, shoreline, wave, and world-edge appearance before accepting the corresponding phase. A successful compile is not visual acceptance.
- The former `Research` ideas for signage/billboards and artist-friendly clothing are promoted into Phases E and F. Treat them as in-scope discovery and prototyping; only proceed from prototype to a reusable production workflow when its phase exit criteria are met.

## Phase 0 — Scope, Baselines, And Design Decisions

Status: **DESIGN DECISIONS RESOLVED — live baseline recorded with stated limits**

**Initial source inspection (2026-10-05):**

- The starting worktree contains the uncommitted Copilot-instruction improvements and this new tracker; no other tracked source changes were reported. Preserve both.
- Three authored skyscraper variants exist under `tiletemplates/buildings`: `tile_skyscraper_1a`, `tile_skyscraper_1aa`, and `tile_skyscraper_1aaa`, with VMF/VMX companions. The user confirmed standard `skyscraper` spelling; no rename is required. Brush-plane Z extents are 0-1536, 0-2944, and 0-4384 respectively; each VMF contains one `zn_tile_direction` marker. These are source measurements, not compiled geometry or Hammer acceptance.
- The current `genericBuildings` discovery regex accepts only `tile_building` and `tile_construction`; it excludes all three skyscrapers. Phase A must add ordinary-building eligibility, not landmark registration.
- The existing planner already weights ordinary buildings by a density tier. Inspect and extend that owner rather than introducing a competing city-density system.
- The shared sky-room builder currently assumes a playable-cell ceiling near 3152 units. Its placement checks, playable-bound clamps, model bounds, and world-map capture must be reviewed together before increasing supported building height.
- The tallest skyscraper extends to 4384 units, beyond that existing playable-volume assumption. Raising only the scaled sky-room ceiling would not establish that the full-sized playable tower fits; both playable shell and separated sky-room placement need validation.
- The current coastline is a client-built sea, wall, and foam mesh. Shoreline and wave work should start from that renderer rather than assume a new authored water map is needed.
- Numerical skyline/density/performance targets remain open; no generation, compilation, player relocation, or preference changes have occurred.
- The user selected **open ocean with a natural shoreline** for the west edge. The cardinal contract is now north hills, east mountains, south flatlands, west ocean; corner blends remain to be designed.
- Existing preview inputs are a 24x24 manifest, seed-1337 template plan, and skybox manifest with neighbour radius 2. Their timestamps are not proof of matching current sources; resolve/rebuild affected outputs before validation.
- The authored base shell contains sky brush planes at 3088/3152 units. The 4384-unit tower therefore requires a playable-shell review, not just a scaled skybox-model adjustment.
- The user selected **geometric world center with a taper toward the outskirts**, rather than commercial/financial district placement, as the skyscraper-density driver. Preserve existing district behavior for other building families; add a dedicated center-aware skyscraper selection policy.
- The user selected an initial target of **40% skyscrapers at the geometric center, smoothly tapering to 5% at the outer edge**, among eligible single-tile ordinary building selections, not among all terrain tiles. Measure final placements separately because decorations, macros, and exclusions can change the realized share.
- The user selected **detailed nearby cells plus lightweight distant tower silhouettes**, not full distant-cell rendering. Skyline work must preserve the actual planned tower positions and avoid expanding distant scenery/vehicle/fire draws along with tower coverage.
- The user selected **a natural mixed sandy/rocky shoreline with rolling waves and broken foam**, rather than a continuous urban seawall.
- A read-only bridge baseline request returned exit 3: Garry's Mod is not running. No live baseline has been captured; source inspection is not runtime or visual verification.
- At the user's approval, launched the unchanged preview through `start_zombiesim_dev.ps1`. Game processes are present, but the first responsiveness check returned exit 2 with a stale heartbeat while startup/loading was underway. Await a deployed, unpaused client before requesting another sample; launch alone is not a successful baseline.
- The user confirmed deployment/unpause; fresh preview baseline on `zz_preview_cc0c866ea860`, raw grid `(15,13)`, clear weather, snow cover 0: 12 seconds / 240 frames, 20.00 average FPS, p50/p95 49.97/56.63 ms, wrapped Lua hooks 4.579 ms/frame, allocation 80.89 KB/frame. Skybox status: radius 2, 24 neighbour cells, 26 model placements, 139 props and 32 fires drawn in the sampled frame, no missing models/recipes. This is a session baseline, not a matched comparison against older measurements; camera/quality and population evidence must accompany later comparisons.
- The user requested verification of updated launcher rooms. `build_city.ps1` does not invoke `build_launchers.ps1`; authored launcher sources dated October 4 are newer than built/staged BSPs dated September 27. Add an explicit preview launcher validation/build step to the staging sequence; do not rebuild production city implicitly.
- `test_launcher_parity.ps1` passed its required scene-entity/camera/profile checks but failed final whole-file parity. Source comparison found editor mapversion/camera differences, plus city cubemap origin `(16,0,96)` versus preview `(0,0,96)` and city light origin `(-8,0,112)` versus preview `(0,0,112)`. Await user direction on intentional authored differences before changing sources or the parity contract.
- The user chose preview positions for both launcher sources. Aligned the city source's cubemap/light positions; parity now ignores only Hammer mapversion/editor-camera metadata and passes shared runtime parity. Preview launcher VBSP/VVIS/VRAD passed and both staged BSPs have SHA256 `9F6296EC24741D40EFF3981754886529276975420800E6FAD8BA64E2D96ABAA6`. Production city BSP was not rebuilt or staged; no map transition was issued. Updated launcher visual/deployment acceptance remains pending.
- The user prioritized visual detail rather than imposing the proposed combined 1 ms/frame added-rendering cap. Keep detailed neighbour radius 2 and measure/cull distant tower-only rendering; report measured cost and obtain acceptance rather than claiming an unapproved hard performance threshold. Corner treatment will blend north hills into east mountains, east mountains into south flatlands, and the north/south landforms into the west ocean shore.
- The user confirmed the towers are 2x2 buildings and specifically requested the `_2x` suffix. Renamed all three VMF/VMX pairs accordingly without changing geometry/markers. The 40%-center/5%-edge target now applies to eligible automatic multi-tile selection attempts, after the existing macro-placement chance; successful-placement counts remain a separate acceptance measurement.

1. Inspect the current preview manifest, template plan, skyscraper source templates, skybox model manifest, coast renderer, and world-grid edge conventions. Record the seed/profile and identify affected recipes without regenerating them.
2. Define how skyscrapers are classified as ordinary buildings, how city centrality is measured, and what density means (for example, relative share or target counts). Keep skyscrapers out of landmark-only logic.
3. Set a measurable skybox skyline requirement: which distant cells are eligible, how skyscrapers remain visible from ordinary city cells, the maximum skybox radius/part count/draw cost, and the tallest supported source building.
4. Confirm the four edge treatments. The draft specifies north hills, east mountains, and south flatlands, but does not name the west-side treatment; settle it before Phase D. Define how corner transitions blend adjacent edge types.
5. Review the current client-drawn sea, wall, and foam to identify what makes the shoreline look wrong. Choose the shoreline shape and wave direction/scale/animation approach in a small preview prototype before broad rollout.
6. Record the sky-room vertical clearance required by the tallest skyscraper and any set dressing. Preserve the existing separation between playable-world bounds and skybox-only geometry.

**Exit:** Inputs, measurable skyline and density targets, west-edge/corner design, shoreline/wave direction, build impact, and visual acceptance checks are agreed. Do not start broad regeneration in this phase.

## Phase A — Integrate Skyscrapers Into City Density

Status: **ACCEPTED by user (2026-10-05); in-game tower/skyline checks belong to Phase B**

**Progress (2026-10-05):**

- Added ordinary skyscraper discovery, settings for the agreed 40-to-5 percentage taper, symmetric smoothstep centrality rounded to whole percentages, separate deterministic tower selection, and recipe identity separation by selection percentage. Preserved existing height weighting within each family.
- `bin/test_skyscraper_selection.ps1` passes center/edge values, symmetric monotonic taper, three-seed frequency tolerances, ordinary-not-landmark classification, height preference and deterministic recipe identity. These are policy checks, not proof of final world placement.
- The frontage integration check fails during source-marker validation: each skyscraper filename implies 1x, but its south marker is `(0,-640,40)` (the 2x edge). Brush-plane extents are X `-640..640`, Y `-744..640`, for all three variants. Do not move markers or shrink geometry to conceal this mismatch.
- Await user confirmation of intended 2x2 footprint versus a reauthored single-tile asset. The single-tile selection implementation must be adapted if these are macro buildings; the approved percentage denominator must then be clarified rather than claimed achieved.
- Multi-tile checks were not run after the preceding failure. No preview plan/recipe/map generation or staging was performed for these planner changes; affected output remains unverified. Phase B has not started.
- Footprint blocker resolved by user confirmation and requested `_2x` rename, including all VMX companions. Selection now uses the existing ordinary multi-tile path, retaining landmark/forced-fixture exclusions and falling back to compatible ordinary macros if the preferred tower cannot fit.
- Initial policy tests passed but realized center/outer placement did not improve because shared recipe-seed choices correlated with district topology. Corrected the preference roll to use world seed and cell coordinates, and included preference plus rounded chance in recipe identity so variants cannot collapse distinct tower decisions.
- Corrected seed-1337 preview test plan: central band (normalized center distance <0.5) has 19 towers across 144 cells; outer band (distance >=0.8) has 2 across 252 cells. These are realized counts, not proof that every placement achieves a 40%/5% share. Required recipe count is 358; build cost expansion must be reviewed before Phase B compilation.
- Final validation: skyscraper policy and realized-plan checks pass, including no conflicting tower layouts in shared recipes; building frontage passes; multi-tile suite passes (7 fixtures/recipes, 168 markers, 145 junctions, 23 motorway frontages). Editor diagnostics show no errors and `git diff --check` passes. The test-plan artifacts are not a staged/released world, and no live tower/height/skyline result is claimed.

1. Add or verify `tile_skyscraper` as a regular building candidate in the planner, not as a landmark.
2. Bias deterministic ordinary multi-tile building selection toward skyscrapers near the city center and away from the outskirts, using the Phase 0 definition of centrality and density. Preserve ordinary building availability and all existing placement, entrance, adjacency, and exclusion rules.
3. Keep seed reproducibility and avoid changing unrelated landmark selection or world-generation weights.

**Checks:** Add focused planner regressions proving central density exceeds outskirts density over fixed seeds, that skyscrapers remain ordinary non-landmark buildings, and that existing valid road/building placement rules still hold. Generate and inspect a small preview plan before building recipes.

**Exit:** The plan shows the agreed center-to-outskirts distribution, is deterministic for the same inputs, and preserves existing placement invariants.

## Phase B — Fit And Compose The Skyscraper Skyline

Status: **ACCEPTED by user (2026-10-05)** ? skyline, distant activity/facade fires and the engine-audio label reviewed at edge `(23,12)`.

- The user accepted Phase A and authorized Phase B. The tallest current tower reaches 4384 units; the authored playable shell is below it, and the existing map-capture height is 3600. Review playable shell, separated sky-room location, bounds clamps, capture height, model extent and visibility together before staging.
- Raised the authored base shell's inner/outer sky ceiling to 4608/4672 (VMF and VMX geometry coordinates only), moved the shared sky camera to 5120, and made the builder validate separation against the actual base-template maximum plane Z. The map camera now uses the loaded manifest's playable ceiling rather than remaining capped at 3600; capture cache version is 10.
- `bin/test_skyscraper_height.ps1 -Compile` generated three isolated current-source tower fixtures: all 3 VBSP stages passed, no failed/incomplete stages. Their exact visibility check passed: all 3 maps within 1500 clusters/2700 portals, no missing/invalid portal data. GLua syntax passed 168/168; targeted editor diagnostics passed.
- These fixtures are not staged city maps and have not received full VVIS/VRAD, Hammer or in-game visual acceptance. Distant tower representation and matching full preview refresh remain unfinished. Current loaded preview/player state was not changed.
- The user requested that the agent open the exact fixture before asking for Hammer review, rather than leaving them to locate it. Opened `generated/skyscraper_height/src/zz_preview_b2db9aa12dfd-cp.vmf` in installed Hammer++ with the GMod game path; the editor process is responding. Visual confirmation remains pending.
- The user accepted the tallest fixture's Hammer clearance and road/footprint placement on 2026-10-05 ("Looks fine"). This accepts the opened structural fixture only; distant skyline rendering, in-game capture, and integrated Phase B acceptance remain unfinished.
- Added tower-only geometry extraction using the existing SMD builder, plus independently stamped `_t<N>` model compilation and an optional `towers` manifest table with report counters. Full nearby recipe output is unchanged; distant tower parts exclude ordinary terrain/roads and scenery/fire metadata. No new runtime manifest or model files were published in this step.
- `bin/test_skybox_towers.ps1` passes: a rotated/translated tallest tower produces 1 part / 2284 triangles, compared with 2294 for its mixed terrain fixture; extracted SMD matches the tower-only reference exactly, and a recipe without towers emits no tower parts. The first run caught a missing C# regex namespace import; corrected it and reran successfully. Runtime selection/drawing, skyline fog and room coverage remain to be implemented and verified together.
- Added the client distant tower-only pass: actual world-cell offsets, exclusion of current/detailed cells, deterministic nearest-first selection, cleanup, view/distance culling, separate long-range fog, and missing/omitted/placement/frame-draw diagnostics. `skylineRadius = 24` covers the preview grid without expanding nearby props/fires; `maxTowerModels = 128` bounds creation and draws. This is a bounded representation for larger worlds, not a promise of unlimited full-world coverage.
- Enlarged the shared sky room on the existing 1024-unit grid: inner half extent 7168, outer 8192, within Source coordinate limits. Weather and skybox lighting now clamp both minimum/maximum X/Y to the playable manifest cell span. No weather appearance, footprint/splash, gore, or preference changes were made.
- Static checks passed: 168/168 GLua files, tower-only extraction, all 3 enlarged-room fixture VBSP stages, exact room-coverage/coordinate checks, and targeted editor diagnostics/whitespace. Regenerated the matching seed-1337 preview plan and VMFs (358 required recipes); realized distribution remains center 19/144 versus outer 2/252, with consistent shared recipes. Full required-recipe VBSP/portal-budget preflight is running without staging. No updated city BSPs, skybox manifest or tower models have been published; runtime fog/horizon visibility, bounds behavior, model completeness and frame cost still need live verification.

- Full preview structural/portal preflight completed successfully: all 358 city recipe VBSP stages passed, with 0 failed and 0 incomplete. Visibility checks covered 361 maps (358 city recipes plus 3 standalone dens): 0 over budget and 0 missing/invalid portal files under the 1500-cluster/2700-portal limits. No staging was performed. Matching model export, final lighting/visibility compilation and live acceptance remain pending.
- Continued with VVIS/VRAD for all 361 required maps using the validated portal data, without staging. The bridge reports Garry's Mod is closed; no player relocation or preference change was issued. Added `build_skybox_models.ps1 -OutputContentDirectory` to prepare models/wrappers/manifest under `generated/skybox_preview/release_content` without replacing the mounted preview. The isolated model build is running alongside lighting compilation.
- Paused the VVIS/VRAD and isolated model builds after the user challenged the recipe-count increase. Neither partial build is accepted or staged. The planner currently puts rounded skyscraper chance and preference into recipe identity even when these inputs do not change the realized layout; this needlessly splits reusable recipes. Resolve recipe reuse based on actual layout differences before resuming compilation, preserving the accepted center taper and shared-layout consistency.
- Corrected recipe reuse: removed chance/preference from identity and reused the existing realized macro template/footprint/anchor/rotation key. Variant placement now refreshes that key afterward. Matching seed-1337 plan requires **179 city recipes + 3 unique den maps = 182 BSPs**, versus the installed prior manifest's **168 city recipes** (179 is +11, about 6.5%, not the erroneous 358). There are 11 den locations but only 3 reusable den BSPs. Tower distribution remains **19/144 center vs 2/252 outer**, with consistent shared tower and multi-tile layouts. Selection/identity and frontage checks pass; multi-tile regression is running. Refreshed optimized source VMFs only; no resumed compile or staging yet. Reported count/time impact to the user before compilation: roughly the prior 15-minute workload range, not a guaranteed estimate; partial outputs may be reused only when source dependencies are current.
- Multi-tile regression passed (7 fixture templates/recipes, 143 city markers, 120 junctions, 23 motorway frontages); editor diagnostics and whitespace pass. After reporting the optimized count/time impact, resumed preview portal validation followed conditionally by VVIS/VRAD for exactly 182 unique maps, plus isolated model preparation for the 179 city recipes. Both processes are active; no staging or live acceptance yet. The old 358-recipe build remains stopped and is not the release scope.
- Optimized preflight passed: 179/179 city VBSP stages, 0 failed/incomplete; all 182 maps within portal budgets, 0 invalid/missing. Isolated model export and manifest validation passed: 179 recipes, 201 nearby parts, 179 snow parts, 15 unique tower parts; 28 tower-bearing world cells across 576 tested viewpoints, worst distant count 28 against budget 128, no truncated views, all required model companions present and no missing detail models. The only non-tool material omissions are the existing water-shader exclusions. VVIS/VRAD remains running; installed assets/manifest and BSPs have not been staged.
- Optimized final compile passed: 182 maps considered, 179 city recipes compiled, 3 current dens reused, 0 failed/incomplete; VVIS/VRAD duration 549.6 seconds (9m10s), fast preset. With Garry's Mod closed, published the isolated models/wrappers and matching skybox manifest, then staged preview BSPs, map materials and runtime world data. All 182 staged BSP hashes match the compiled files; installed manifest validation and 168/168 GLua syntax checks pass. Production outputs remain untouched. Staging reported no existing runtime navmeshes for the 182 required maps; generated wireframes also report 206 unavailable logical cells, so navigation/wireframe completeness is not established. Live launcher/deploy, skyline, map capture, bounds and performance/visual acceptance remain pending.
- The user reviewed the updated preview launcher and reported it looks correct, then deployed into city recipe `zz_preview_79f6a08bd7a9`. Initial screenshots showed distant towers with hard floating bottoms. Moving opaque towers before the translucent horizon removed the hard cutoff but the original horizon opacity hid their silhouettes entirely; fresh diagnostics showed 26 tower placements, 10 frame draws, no missing assets. Added a skyline-specific graduated horizon blend (legacy blend retained without distant towers), then clean-reloaded the same map. The user confirmed **towers visible and bottoms blend naturally**. This accepts the reported view's correction, not all central/outskirts/edge viewpoints. All 168 GLua syntax checks pass; no BSP recompilation was needed. A fresh 12-second client profile has been requested; map capture and remaining viewpoints still need verification.
- Added `bin/test_skybox_manifest.ps1` to check matching settings/recipe coverage, nonempty MDL/VVD/DX90 companions, tower presence versus planned geometry, and distant model-part counts at every preview viewpoint. Its rejection of the existing stale manifest was verified; the new export's positive validation awaits model-build completion. Editor diagnostics and whitespace checks pass. Do not launch/reload the preview until matching BSPs and manifest are staged together.

1. Rebuild the affected preview cell recipes and per-recipe skybox models from the current source templates.
2. Adjust sky-room height/placement to contain the tallest planned skyscraper without clipping or changing playable-world bounds, foliage/puddle limits, or world-map capture.
3. Extend skybox skyline selection so distant skyscraper silhouettes remain visible from the required city viewpoints, even when the immediately neighbouring recipes have few or no towers. Keep the skyline deterministic and subject to an explicit model/draw budget; do not assume a larger neighbour radius is free.
4. Preserve existing skybox set dressing, weather, snow, lighting seams, and coast behavior except where an intentional, tested interaction requires a change.

**Checks:** Validate model/manifests for missing or stale parts; compile only affected preview recipes; run the structural and visibility-budget checks required by any changed VMFs. Inspect the highest tower and skyline from central, outskirts, and edge cells. Compare skybox frame cost under matched map, weather, camera, quality, and model-count conditions; verify skybox-only height remains excluded from playable bounds and map capture.

**Exit:** Tallest towers fit, the agreed silhouette is visible across the required city viewpoints, frame/draw budgets are met, and existing bounds-dependent systems remain on the playable cell.

**Phase B live refinement checkpoint:** The outskirts skyline visibility/softness and local level-map capture were confirmed by the user, but general skybox washout remains unresolved. A subsequent 0.6 fog-cap/ambient-fill experiment regressed to near-uniform gray geometry and caused a missing placement-origin error. Fixed placement records and versioned their rebuild key; reverted the fog cap to 0.8 and original matched lighting, and disconnected the new cosmetic activity pass to isolate restoration. Syntax passed 168/168 and same outskirts map reloaded; restored appearance awaits confirmation. Do not treat the failed colour experiment or activity prototype as accepted. Original return destination remains raw cell (15,12); edge review and restoration remain pending.

- The user confirmed the earlier appearance is restored and requested configurable Options rather than further guessed fog defaults. Added archived, live skybox tuning (fog amount/distance, horizon haze, distant tower fog, model brightness, matched lighting) to the shared launcher/radial Options builder, plus existing detail/cloud/props/fire controls. Presentation tuning stays independent of quality presets. Reset only affects presentation; Copy exports preferred values. Defaults preserve the restored appearance. Syntax passed 168/168; clean-load Options interaction, tuning persistence and visual review remain pending. No BSP compilation is involved.
- Clean-loaded the same outskirts map with the new controls. The user confirmed **the Options controls work and will tune them**; fresh runtime diagnostics include the tuning values and show fog amount 0.2, with other presentation values at defaults. Do not overwrite those user adjustments or resume blind visual tuning. Archived convars provide persistence, but persistence across another reload, Reset/Copy interaction and launcher UI interaction have not yet been separately exercised. Await preferred copied values; edge review and return to raw (15,12) remain pending.

**Selected skybox tuning:** After reviewing background activity, the user selected fog amount **0.8**, fog distance **0.9**, horizon haze **0.5**, distant tower fog **0.8**, model brightness **0.25**, and matched lighting **enabled**, describing these values as perfect. These supersede the earlier 0.76/1.51/0.20 choices and are adopted as new-user/reset defaults without overwriting existing archived preferences. Copy interaction is verified by the supplied JSON. Edge review and return to raw (15,12) remain pending; this is not blanket Phase B acceptance.

**Background activity refinement:** User requested distant explosions/gunfire and fires emanating from skyscraper sides. Enabled bounded cosmetic explosion flashes/smoke and muzzle/tracer bursts; added up to 8 persistent facade fires anchored to real vertical tower triangles (including stepped upper storeys). Reuses mounted models, existing fire materials and the fires/smoke toggle; preserves archived presentation settings and requires no BSP compilation. Fixed prototype fog restoration and preview-command registration.

- Static: 168/168 GLua files parse; editor diagnostics and whitespace checks pass. Zero-count mesh passes are skipped; long-range activity fog is restored regardless of which event types are active.
- Live: clean-reloaded the existing outskirts preview twice. Fresh diagnostics confirm 24 activity sites, 8 facade fires and a valid tracer material. User confirmed the effects and side fires were visible, then requested much higher gunfire. Increased tracer climb/lifetime/width, with an art ceiling below the existing 512-sky-unit room roof; user explicitly confirmed the revised height looks right. No new skybox/mesh errors in the recent console tail.
- A fresh 12-second accelerated-activity profile measured 721 frames and skybox mean **3.157 ms/frame**, maximum **7.588 ms**. This is not a matched before/after cost comparison. Final live presentation settings were user-adjusted (fog amount 0.8, brightness 0.25); no preference writes were issued.
- Remaining Phase B checks still include edge review, return to raw (15,12), independent toggle/capture/weather checks and matched performance comparison. This accepts the reported background-activity view, not blanket Phase B acceptance.

**Engine audio Options fix:** The user reported `RunConsoleCommand: Command is blocked!` for `volume`, `volume_sfx` and `snd_musicvolume` from slider scratch controls. Garry's Mod blocks Lua writes to these convars (https://wiki.facepunch.com/gmod/Blocked_ConCommands), so the three Options sliders were replaced with a read-only label showing current values and directing players to Garry's Mod Options > Audio. Static: 168/168 GLua files parse and `git diff --check` passes. Clean-loaded via the edge transition; live Options confirmation remains pending.

## Phase C — Redesign Shoreline And Add Waves

Status: **ACCEPTED by user (2026-10-05)** ? corner-cell seam inspection deferred to Phase G.

**Prototype evidence:** At edge `(23,12)` the user reported that "the water doesn't look very watery". The baseline was a single untextured sea plane, pre-lerped 45% toward the fog colour and then fogged again, plus a flat sea wall and plain foam strips. The baseline capture is `coast_baseline`, with 336 sea quads and 7 wall and foam quads. In `cl_skybox.lua` the coast was rebuilt as chunked static meshes:
- a rock embankment;
- a noise-jittered sand beach with ridged rock outcrops, in world-absolute noise so it stays stable across cells;
- depth-shaded water, from shallow turquoise to deep blue, with only a 12% pre-fog lerp;
- two drifting additive ripple layers;
- foam crests that scroll toward the shore along depth contours.

The ripple and foam textures are procedural 256² render targets built once. Static checks: 168/168 GLua files parse and `git diff --check` passes. Live clean reload: no Lua errors. Diagnostics: 6 meshes, 4,501 sea, 1,646 sand, 813 rock and 2,927 foam quads; `coastBuildMs` = 38; all materials valid; textures ready. Eye-height captures `coast_ne`, `coast_beach_a/b` and `coast_beach_c` show turquoise shallows, ripples and moving foam. The sand tint was warmed after `coast_beach_a/b` because fog greyed the beach. The far sea still meets the existing horizon fog wall at the fog edge as a haze band.

Still to verify: user visual approval, rain and snow views, interior-cell views, seams and corners, and a matched profile. `zombiesim_dev_capture` now accepts an optional `pitch yaw` for eye-height review captures.

**Review results:**
- **User:** The user approved the water appearance ("Fantastic") and the snow-covered coast.
- **Rain:** `coast_rain` rendered without errors.
- **Snow:** With `snowAlpha` at 1, `coastBuildMs` was 37.5 with no errors. Weather was returned to `auto` afterwards.
- **Interior cell:** At raw `(15,12)` there are 0 coast meshes and 0 sea quads, with no errors. Status confirms grid 15,12 on `zz_preview_79f6a08bd7a9`.
- **Profile (clear weather, edge `(23,12)`, 10 s):** 59.6 FPS, which is the frame cap. p50/p95 frame times were 16.52/20.12 ms. `ZM.Skybox.Draw` cost 2.74 ms and allocated 37.9 KB per frame, and all Lua hooks totalled 4.36 ms per frame. The earlier accelerated-activity Phase B profile measured 3.16 ms, but that is not a matched comparison; the coast adds a few static-mesh draws per frame and a one-time build of about 38 ms per placement.
- **Deferred:** Corner-cell seam inspection moves to the Phase G integrated review.

1. Prototype changes to the existing skybox coast renderer and shoreline transition based on the Phase 0 review; target a natural connection between land, shore, sea wall, and sea rather than adding detail before correcting the silhouette.
2. Add the agreed wave motion/appearance at the water boundary with a bounded render cost and consistent behavior across camera movement, snow, fog, and weather.
3. Keep this presentation in the skybox rendering path; do not allow coast effects to affect playable-world collision, world-map capture, puddles, or snowfall bounds.

**Checks:** Inspect the prototype at multiple distances and angles, including shore-adjacent and interior city cells, and under clear, rainy, and snowy conditions where available. Check seams and corners, verify no rendering errors or unbounded per-frame allocations, and profile against a matched pre-change capture.

**Exit:** The user approves the shoreline and wave appearance, transitions are seam-free at tested views, and runtime cost is within the Phase 0 budget.

## Phase D — Add Distinct Cardinal World Edges

Status: **ACCEPTED — user confirmed on 2026-10-05.**

1. Implement the agreed north hilly terrain, east mountain range, and south flatlands, plus the west-side treatment selected in Phase 0.
2. Make the east mountains visible as an orienting landmark from every city cell, including viewpoints where they are not the nearest edge. Keep terrain forms and transitions specific to the world edge rather than scattering them as ordinary city tiles.
3. Blend adjacent edge treatments at corners and integrate them with the redesigned shoreline without gaps, overlaps, or reversed cardinal directions.
4. Keep edge scenery deterministic and separate from playable-cell logic. Reuse or extend the existing out-of-grid skybox/coast representation where appropriate rather than placing skybox-only scenery in playable templates.

**Checks:** Add directional/cardinal mapping regressions and preview fixtures covering all four edges and all four corners. Inspect the generated skybox from center and edge cells; verify the mountains remain visible, and confirm world-map capture, foliage/puddle bounds, snow, fog, and existing coast behavior are unaffected. Run focused VBSP and portal/visibility checks for any structural changes.

**Exit:** All edges have their agreed distinct treatment, corners join cleanly, cardinal placement is correct, and the east range provides the agreed city-wide orientation cue.

**Implementation (2026-10-05):** Client-only procedural terrain in `cl_skybox.lua`. No map, VMF, or template change, so VBSP and portal checks do not apply.
- **Classification:** `Skybox.ClassifyEdge` assigns hills (north), mountains (east), flatlands (south), ocean (west and both west corners), and blended NE/SE corners.
- **Coast:** `BuildCoast` now treats only out-of-grid slots west of the grid as sea, and builds embankments only on city cells. As a result, the former east-side ocean is now mountains.
- **Heights:** `Skybox.EdgeHeight` meets the city boundary at street height (+2) and the west shore at beach height (+1), and smooths across corners.
- **Mountain shape:** foothills, a noise massif, and domain-warped ridges, rather than a uniform wall of peaks.
- **Materials:** grass is the base layer. Rock and snow are vertex-alpha overlays weighted by height and slope, which removed the stair-step material seams from the first pass. Weather snow cover is a fourth layer over the grass.
- **Draw order:** when edge terrain exists, the horizon dome no longer writes depth and is drawn before the terrain. This stops the dome's opaque lower ring from cutting a pale band through terrain beyond its radius.

**Static/automated (2026-10-05):**
- GLua syntax passes on 168 files; `git diff --check` is clean.
- `zombiesim_dev_skybox_edges` passes 19/19, covering:
  - classification of all four edges, all four corners, and the centre;
  - landform means (east 319, north 48, south 5.5) and their ordering;
  - city boundary at street height and west shore at beach height, both with 0 deviation;
  - corner seam step of 0.003;
  - east peak at 3.8° from the far-west cell;
  - sky directions east = +X and north = +Y.
- The build takes about 149 ms once per map load and produces 42,106 quads.

**Live (2026-10-05):**
- Captures from `(23,12)`, `(12,0)`, `(12,23)`, `(0,12)`, `(23,0)`, and `(0,0)` confirm the cardinal mapping, the north hills, the intact west coast, and that the east range is visible from the far west and from gameplay views.
- After the blend and dome fix, the east-edge captures show smooth rock/snow transitions and varied massifs.
- The `ZM.Skybox.Draw` hook takes 2.35 ms per frame, compared with 2.74 ms in the Phase C sample.
- The user accepted Phase D on 2026-10-05, including the subsequent fog and silhouette fixes. Dedicated snow-weather cover and corner-view checks remain uncaptured and are retained for Phase G integrated review.

**Fog matching and dark-cell scenery (user report, 2026-10-05):**
- The sky fog now continues the city fog:
  - It matches the city's density at the cell boundary.
  - It never ramps more slowly than the city fog.
  - It never ends below the city's maximum density.
- **Skybox fog amount** now means added thickening on top of the city fog: 0 matches the city, 1 is halfway to opaque, and 2 is opaque. The old post-multiply, which could make the sky clearer than the city, has been removed. Distant tower fog is unchanged.
- The edge light cube is now always sampled. Its top-face brightness gives a per-cell light level, which tints the shared fog colour for both the city fog (`Atmosphere:GetFogSettings`) and the sky fog. Mountains, coast, and fogged buildings on dark cells therefore darken, while daylight cells keep the profile colour.
- Static: syntax passes on 168 files and `zombiesim_dev_skybox_edges` passes 22/22. The new checks cover:
  - Across all five profiles plus a saturated case, the sky fog is never clearer than the city fog (worst difference 0.0000).
  - The daylight tint is 1.000.
  - The dark-cell level is 0.554.
- Live at `(15,12)`: the fog is dim green-grey and matches the night lighting, and distant scenery no longer glows white. The user subsequently accepted Phase D on 2026-10-05.
- **Pale-fog tower silhouettes (user request):** on light profiles such as the Storm Drain, the towers looked black and stood out.
  - **First attempt (did not work):** the user's capture still showed black towers next to fogged neighbour cells. The towers are 3–6 cells away, but their ramp ran to about 13 cells, so they reached only about 25% fog.
  - **Fix:** tower fog now scales with the brightness of the (light-tinted) fog colour. Paleness is a smoothstep between luminance 0.45 and 0.7.
    - Pale fog puts the towers on exactly the same start/end/maximum fog curve as the neighbour-cell scenery. Their maximum density is never below the tower fog setting.
    - Dark fog, and fog on dark-lit cells, keeps the separate long-range ramp and plain silhouettes.
  - **By profile fog colour:** outskirts, suburbs and safe_zone are fully pale (luminance ≈0.72–0.80); inner_city (paleness ≈0.15) and dead_zone (≈0.06) stay close to unchanged.
  - Diagnostics record `towerFogPaleness`, `towerFogStart`, `towerFogEnd` and `towerFogAppliedMaxDensity`.
  - **Static:** syntax passes on 168 files.
  - **Live on `zz_preview_25d80defdcf2`:** paleness 1; the tower fog uses start 826, end 2906 and maximum 0.837 (world units), the same as the sky fog. Ground-level captures were occluded; the user's subsequent Phase D acceptance is recorded separately from that diagnostic evidence.

## Phase E — Artist-Friendly Sign And Billboard Workflow

Status: **ACCEPTED — user confirmed the workflow/zoo on 2026-10-05 and explicitly approved carrying remaining integration checks into Phase G.**

**Initial discovery (2026-10-05):**
- Existing motorway and commercial templates reference mounted `models/props/cs_assault/billboard.mdl`; other templates use mounted street, station and construct signs. These are placement examples, not redistributable model/artwork sources.
- `bin/skybox_models.psm1` already reads authored prop origins, angles and skins, transforms them with their tile instances, and selects billboard models through the existing detail-prop pattern. Original billboard props can use this route without introducing a separate runtime sign renderer.
- The same skybox builder supports world and `func_detail` brush faces. `bin/build_skybox_models.ps1` resolves addon VMTs/VTF dimensions and emits model-compatible materials, so a brush-backed artwork panel is another candidate.
- Hammer, `vtex.exe` and `studiomdl.exe` are installed in the game's `bin` directory. Blender and ImageMagick were not found on PATH; this is not a complete installed-software inventory.
- The user selected an original reusable prop with replaceable artwork. Discovery itself made no asset, tile, generator or map changes; the implementation below followed that choice.
- The live Valve Developer Community material and `prop_static` pages returned an access challenge; their contents have not been verified. Resolve any concrete API/compiler uncertainties from accessible references and focused prototype checks before relying on them.

**Implementation (2026-10-05):**
- Original freestanding billboard at `models/zombiesim/signs/alert_billboard.mdl`, with a 256x128 artwork panel, frame and two posts. At yaw 0 it faces local south (-Y); the origin is ground height and the footprint fits a 640-unit tile.
- `assets/signs/alert_billboard.json` supplies editable original text/colours. `bin/build_sign_assets.ps1` exports a 1024x512 PNG starter and accepts an independently edited opaque PNG through `-ArtworkPath`. It compiles/stages the original model and two lit textures without a model editor, BSP rebuild, generator change or generated-file hand editing.
- Mesh generation, UVs and three-part collision are owned by `bin/sign_assets.psm1`. Reused the existing skybox builder's installed-compiler SMD axis compensation; corrected the initial collision warning before accepting the output.
- The existing billboard detail-prop route carries model, origin, yaw and skin through tile instances. No new client rendering hook was added.
- `zombiesim_dev_sign on|off` is an admin-preview-only bridge probe. It requires a deployed living survivor, creates one non-solid example facing the player, removes/replaces only that player's example and expires after 180 seconds; no player/world persistence is changed.
- [Artist workflow](docs/sign_artist_workflow.md) documents source art, clean builds, opaque image constraints, placement/cardinal facing, packaging/provenance, skybox detail settings and remaining checks. The prototype replaces artwork globally on this one model; it is not yet a multi-sign or multi-skin catalogue.

**Static/automated (2026-10-05):**
- `bin/test_sign_assets.ps1`: **26/26 passed**, checking compiled package completeness, model axis/bounds, VTF dimensions and lit addon material paths, three convex collision parts without fallback, upright/non-mirrored artwork UVs, invalid size/transparency rejection and four cardinal tile-instance transformations through `CellModelBuilder.BuildDetail`.
- Both the JSON-generated default build and the external exported-PNG build path succeeded. The final packaged assets passed the same 26 checks.
- GLua syntax: **168 files, 0 failures**. Editor diagnostics found no errors in the changed Lua and new PowerShell scripts; the focused tracked-file whitespace check passed.
- No BSPs compiled, city recipes changed, production outputs staged or city/skybox manifests regenerated. The compiler's isolated-game `cfg/mount.cfg` warning is recorded; all source geometry/artwork is original and all required model/material outputs were produced.

**Live/user review (2026-10-05):**
- Reloaded only the existing preview map `zz_preview_817d995084d3`, then created the temporary billboard. The bridge confirmed the mounted model and both `models/zombiesim/signs` materials.
- The user selected **"Looks correct - approve the prototype"**, confirming upright/readable artwork and lighting. This is prototype approval, not a claim that compiled tile collision or an actual skybox view was inspected.
- Removed the temporary billboard with `zombiesim_dev_sign off`; the bridge acknowledged success.
- **Remaining:** verify the authored/compiled tile placement and static collision, plus an actual neighbour-cell skybox view. Automated instance-transform evidence is not a substitute for these live checks. Phase E is not yet marked accepted; Phase F has not started.

**Billboard refinement and variants (2026-10-05):**
- The user requested more realistic materials, image/background layering, self-lit panels, independent component textures, legless/lamp-lit/wall variants and a lamp that casts real light.
- The sign JSON now accepts `imagePath`, `backgroundImagePath`, `selfLit`, `selfIllumBrightness`, and independent `materials.legs`, `.rim`, `.back` base textures/optional normal maps. JSON image paths resolve relative to the definition file; CLI overrides and `-DefinitionPath` are supported.
- Layering preserves aspect ratio: foreground contain within a 960x448 safe area; background cover over 1024x512; transparent graphics flatten onto the configured colour. Finished opaque 1024x512 artwork remains a separate supported input.
- Verified mounted HL2 metal material/texture references in place with the repository VPK reader. No Valve textures/models were extracted or copied. Structural surfaces tile rather than stretching one image across an entire post.
- Original geometry now includes I-beam posts and raised border trim. Four compiled models are generated: `alert_billboard`, `_panel`, `_illuminated`, `_wall`. The wall variant is 104x56 with a back-plane origin, and the legless variant has no posts.
- Freestanding/panel/wall artwork supports self-illumination; the frame remains scene-lit. The lamp-lit variant instead has an ordinary lit artwork material, an overhead fixture and glowing lens. Generated Hammer prefabs include its baked `light_spot`; preview uses one temporary shadowless `env_projectedtexture` that is removed with its sign. It does not add dynamic lights throughout the city or skybox.
- Source research caught the static/runtime pitch distinction: VRAD's `SetupLightNormalFromProps` uses negative down-pitch, while the runtime projected light uses positive Source Angle pitch. The prefab uses -60; the live light uses +60. SDK reference/revision and exact branch limits are recorded in the artist guide.
- The user supplied `assets/signs/cs80.jpg` for tests. Both image/background build paths and lighting on/off succeeded. Its redistribution rights remain unverified; the JSON's default artwork remains original. The final preview package currently uses the supplied test image.
- **Static:** 101/101 checks passed in the optional end-to-end JSON image/material-override build; after restoring the intended default metal settings and `cs80` image, the expanded normal suite passed 99/99. All four models' compiled bounds/collision/package outputs, prefab light direction, component settings, image composition and all four cardinal skybox instance rotations for each variant are covered. GLua syntax: 168 files, 0 failures; editor diagnostics and focused whitespace checks pass.
- **Live/user:** the user approved the mounted-metal/self-lit image and confirmed real lamp illumination. The circled blocky lamp housing was reduced to a slim light bar and thinner bracket, then explicitly approved. The user also approved the legless panel and the small wall sign (flush/outward-facing image). Invalid wall-aim attempts returned explicit errors without replacing the previous preview; placement succeeded once the weapon crosshair targeted the wall.
- **Retained limits:** no BSPs compiled and no tile/city recipe changed. Baked prefab lighting, compiled static-prop collision/placement, and an actual neighbouring-cell skybox view remain integration checks; model, dynamic preview and automated instance evidence do not establish these. Generated prefabs must be inserted as direct tile entities, not nested tile `func_instance`s unsupported by the skybox prop collector.

**Thin prints, posters and final detailing (2026-10-05):**
- Added `alert_billboard_print`: the large panel's artwork/outer size in a painting-like wall asset, with a 2-unit backing and 0.3-unit rim rather than the billboard's deep structure. Back-plane centre origin; front faces local south.
- Added `alert_billboard_poster`: borderless image only, 256x128 units, two front-facing triangles at local Y=-0.1. No backing, legs, frame or physics hull; prefab uses `solid 0` and wall placement offsets prevent depth fighting. All six variants preserve image layering and JSON lighting/material settings.
- Detailed the large billboard/panel family with stepped bevel lips and sloped normals, inner gasket, six hex rim fasteners, deeper backing and rear stiffeners. Freestanding variants also have post collars, broad foot plates and foot fasteners; the approved slim lamp remains.
- Measured render triangles: freestanding **398**, panel **206**, illuminated **424**, wall **62**, framed print **62**, poster **2**. Tests bound each below 1,000 triangles and verify bevel normals and the poster's exact image-only geometry. This is a measured mesh budget, not a runtime frame-time profile.
- Build/catalog/prefabs and preview wall-mount selection now cover all six variants. Collision remains simplified: five convex parts for freestanding, seven for illuminated, one for panel/wall/print, none for poster. No city recipe or BSP rebuild was required.
- **Static:** expanded regression **151/151 passed**; GLua **168 files, 0 failures**; focused editor diagnostics clean. All six model/placement/skybox-transform surfaces are covered, alongside the prior image/material checks.
- **Live/user:** after a clean reload of the existing preview map, the user explicitly approved the detailed billboard, the thin painting-like print and the borderless poster (clean wall placement without flickering/disappearing at ordinary views). A rejected wall trace preserved the previous preview; targeting brickwork then succeeded. Temporary examples are cleaned up after review.
- **Later, not current implementation:** retain the user's idea for a large original/licensed generic sign library: health/medical logos, directions/arrows, place/building names and standard environmental signs to help tile artists detail the world. First add distinct output names/design selection so designs coexist instead of overwriting the prototype family. Do not infer approval for a bulk generation/build now.
- Phase E's compiled-tile collision, baked spotlight and actual neighbour-skybox visual checks remain explicit; these additions do not mark those checks or the overall phase accepted.

**Development sign zoo and root mounting (2026-10-05):**
- User requested a complete sign zoo and explicit model/material copies into the installed Garry's Mod root for Hammer/local development; `content` remains the distributable asset source.
- Added `bin/stage_sign_assets.ps1`: stages 37 explicitly scoped original sign files into `garrysmod\models\zombiesim\signs` and `garrysmod\materials\models\zombiesim\signs`, SHA256-verifies each copy, and records a generated staging report. No mounted Valve assets are copied. It stages existing outputs without replacing the current artwork or invoking model compilers. `build_sign_assets.ps1 -StageToGame` is the optional build-and-stage route.
- Added `bin/build_sign_zoo.ps1`: generates `generated\signs_preview\zoo\zn_dev_sign_zoo.vmf`, a sealed standalone showroom with all six direct static props, three general lights, the prefab's real baked spotlight, wall support for the legless panel, wall-mounted thin variants and a central spawn. North-row billboards face south; south-wall variants face north.
- `-Compile` builds/stages only `zn_dev_sign_zoo.bsp`, outside release `content\maps` and all world manifests. It uses final static-prop lighting settings, gates portal counts before VVIS/VRAD, rejects leaks/compiler errors, and skips compilation when sources/assets/settings are current. No city recipe, production map or persistent player state changed.
- **Static/compiled:** existing assets **151/151 passed**; zoo structural/staging **58/58 passed**, compiled-output checks **64/64 passed**; final VBSP/VVIS/VRAD passed with **10 clusters / 18 portals**, six compiled static props and four compiled lights. All 37 root assets and the staged BSP hash-match their source. Incremental rerun confirmed no compilation. Editor diagnostics and focused whitespace checks are clean.
- **Corrections during validation:** fixed PowerShell's null-extension coercion before staging. Initial VBSP rejected stock `sky_day01_01` cubemap texture mismatch; verified all mounted `painted` sky faces in place, then used that source setting. A successful draft compile was followed by a warned rebuild of the same map with final static-prop lighting, not a broader rebuild.
- **Live/visual:** showroom Hammer appearance, in-game static collision and baked spotlight appearance are still pending human review. Existing prototype approvals remain valid; compiled outputs do not establish these integrated acceptance items or the actual neighbour skybox view.

1. Inspect the current tile prop conventions, Source model/material requirements, installed authoring tools, and how authored props enter generated recipes and the skybox. Identify the smallest workflow artists can use to create and update a sign or billboard.
2. Prototype one reusable sign/billboard asset with legible, replaceable artwork and a clear placement convention suitable for tile artists. Prefer a repeatable source-art/material/model pipeline over hand-edited generated assets.
3. Verify how custom artwork and model sources can be packaged and distributed. Reference mounted game assets through their virtual paths; do not extract, copy, or redistribute Valve/Garry's Mod assets as addon source or replacements.
4. Document the artist steps, required source files/tools, texture dimensions/material rules, in-game placement constraints, and how to validate the asset in a tile and skybox.

**Checks:** Build the prototype through the documented workflow; verify materials/models resolve in preview, the sign is readable at intended gameplay distance, and placement survives recipe and skybox generation. Confirm an artist can replace the artwork without editing generated outputs or generator code.

**Exit:** A user-approved prototype and repeatable artist workflow exist, including clear asset provenance/packaging rules and no hidden manual generator step.

## Phase F — Artist-Friendly Human Clothing Workflow

Status: **ACCEPTED — user confirmed on 2026-10-05 that existing checks and visuals are sufficient. Uncaptured cold/lifecycle comparisons remain recorded validation limits, not pending phase acceptance gates.**

**Discovery (2026-10-05):**
- `ZM_CharacterRules.Models` permits nine male and six female `models/player/group01` citizen meshes. `GM:PlayerSetModel` in `gamemode/init.lua` owns applying the persisted character model, skin, bodygroups and player colour; character storage remains profile/character-scoped in `sv_characters.lua`.
- Added `bin/inspect_clothing_models.ps1`: reads installed MDL/VVD/material data in memory through the existing VPK reader and writes only metadata, UV bounds/hashes and material references under `generated\clothing_preview`. It does not extract/copy mounted models/textures or modify live player state.
- All **15** installed models inspected successfully: MDL v48 and matching VVD v4/checksums, one skin and one bodygroup choice each. Each resolves a **1024x1024** `group01/players_sheet` with the existing PlayerColor proxy.
- The body sheet is a combined clothing material, not independent shirt/pants material slots. Its zero-based slot varies by mesh (male: 3,3,4,5,5,1,4,0,3; female: 2,3,3,1,2,4). Resolve by verified material path, never one hard-coded slot. Heads/eyes/mouths are separate material references.
- Body vertex counts/UV sequence hashes differ across models; this does **not** prove UV islands are incompatible, but rules out claiming identical ordered geometry. UV bounds alone do not establish shirt/pants masks, shared layout, logo placement or seam correctness. These need an actual mesh-aligned guide and visual prototype before supporting a mesh.
- `ZM_Items` currently has three weapon slots and armour slot 4, with equipped capacity 4 and no clothing item class. `cl_inventory.lua` has weapon/armour-specific action/display logic; item static-data validation has no clothing field. Shirt/pants integration requires an explicit slot/class/UI contract, not repurposing radiation armour or character base appearance.
- Inventory SQL stores profile/character-scoped item IDs/container slots atomically. Prefer fixed finish selection on independently named clothing definitions for the prototype so the existing item ID persists the appearance; per-instance arbitrary finishes would require a separate validated instance/persistence contract and are not assumed.
- Bloody material replacement currently targets group03 walkers, while survivors use group01. `cl_gore.lua` copies source submaterials into severed cosmetic limbs; corpse and UI preview copies still need their exact ownership traced before wiring finishes. Do not assume walker blood substitution is a survivor appearance path.
- **Static only:** `bin/test_clothing_model_inspection.ps1` regenerated the installed-model report and passed **92/92** checks; editor diagnostics and focused whitespace checks are clean. No runtime clothing prototype, UV-mask acceptance, equip/persistence change or clothing live verification is claimed.

**UV calibration and equipment contract (2026-10-05):**
- The user selected **independent SHIRT and PANTS slots, independent existing armour, cosmetic-only finishes**. Replace the nonfunctional CLOTHING placeholder; retain all three weapon slots and armour slot 4. Shirt/pants slot allocation and client/server rules will land together after verified masks, not as an isolated inventory-capacity change.
- Confirmed `Service:Mutate` and `MutatePlayerItems` persist the draft before replacing live state. Appearance refresh must follow successful commits; failed writes must not change equipped appearance. Equipped items currently survive backpack death loss; do not silently change that policy for cosmetic garments.
- Both mounted clothing materials use base alpha for player-colour masking, normal/phong maps and a PlayerColor proxy. An arbitrary opaque body-texture replacement could affect uncovered surfaces and existing tint. The final garment composition must preserve untouched surfaces and independently restore each unequipped garment.
- The scoreboard model preview currently copies skin/bodygroups but not submaterials; it must be wired when finishes land. Walker corpses explicitly copy material overrides; that does not establish player death-ragdoll behavior. Preserve the source appearance when copying corpses/limbs and restore only overrides owned by clothing.
- Added original `assets\clothing\uv_probe.json`, `bin/build_clothing_uv_probe.ps1` and `bin/test_clothing_uv_probe.ps1`. They generate a 1024-square 8x8 coloured/labelled atlas (A1-H8, orientation marks), compile one VTF/VMT and hash-check content/game-root copies. This is an original diagnostic texture, not extracted Valve artwork.
- Added preview-only `zombiesim_dev_clothing_uv on [current|male|female]` / `off`: creates a stock and checker citizen fixture without changing the survivor or inventory, selects the body slot by its material path, requires clear level ground, preserves existing fixtures on validation failure, expires after five minutes and removes with the owning player.
- **Next human gate:** after static checks and a confirmed preview reload, inspect front/back/sides of the calibration fixtures to establish readable orientation and shirt/pants/skin boundaries. No guessed universal UV mask, production clothing item or equip implementation is accepted from a checker build alone.
- **Static:** original atlas/compiler/staging regressions **135/135 passed**, GLua **168 files / 0 failures**, editor diagnostics and focused whitespace checks clean. The isolated texture compiler's harmless missing `cfg/mount.cfg` warning remains recorded; the VTF was produced and validated.
- **Live state evidence, not visual acceptance:** confirmed active profile/map `preview` / `zz_preview_817d995084d3`, reloaded only that map, then the bridge successfully created both `male_03` fixtures on level ground. Body slot 4 resolved from the mesh; stock override is empty and checker override is `models/zombiesim/clothing/uv_probe`. No player appearance/inventory changes occurred. Human material/pose/UV review is the current gate; Phase F is not accepted.
- **Male checker visual gate:** the user confirmed the texture is visible/readable and ready for mapping review. The subsequent live capture confirms upright grid text on torso/legs and shows the same material also covers hands/neckline; a full-body replacement would not preserve exposed skin.
- Extended the mounted inspector with optional `-UvGuideModels`: reads matching VTX v7 root-LOD triangle lists and maps them through VVD fixups into the body UV sheet, drawing precise wireframe inspection images with the same A1-H8 coordinates. `male_03` and `female_01` guides are generated under `generated\clothing_preview`; no mounted models/base textures are extracted. Unsupported strip formats fail explicitly.
- Inspected the two guide images: torso/sleeves occupy lower-sheet islands, pants upper-right, footwear upper-left, and exposed-hand islands differ substantially between male/female. Keep exact guides and independent verified skin exclusions per supported layout; this is evidence against claiming one universal garment mask. The guides themselves are not garment masks or accepted finishes.
- **Guide validation:** expanded installed-model/guide suite **100/100 passed**. The reviewed male pair was replaced successfully by a stock/checker `female_01` pair (body slot 2), preserving the player's appearance/data. Female visual mapping and precise garment-mask boundaries remain the next human review gate.

**Autonomous camera and finish prototype (2026-10-05):**
- Used the existing development camera rather than requiring human screenshots. Added bounded optional capture coordinates, an eight-request frame queue (fixing overwritten pending requests), clothing diagnostic metadata and fixture-relative front/back/side/neckline capture. No player movement or persistent data changes. Initial crate occlusion was fixed by checking actual prop collision and searching nine nearby placements with clear camera rays.
- Added `assets/clothing/prototype.json`, `bin/build_clothing_prototype.ps1`, `bin/test_clothing_prototype.ps1`, fixture-only `cl_clothing_preview.lua` and `docs/clothing_artist_workflow.md`. Original garment artwork composites over mounted body-sheet pixels only in client runtime targets; native normal/phong/rim references and repeated material proxies remain inherited via small Patch VMTs. No mounted texture/model or shader definition is copied into distributable assets.
- The user chose artist colours on finished garments, retaining character tint on unchanged clothing. RGB composition clears native tint-mask alpha only beneath original opaque artwork. Six bounded runtime targets are reused across print-style changes; source VTF storage is additional. An observed female build took about **5.2 ms**; this is one build observation, not a full performance acceptance.
- The user identified the inner shirt being overpainted. Added independent `native`/`color`/`image` inner-shirt controls and model-family-specific polygon exclusions. Actual geometry/UV landmarks distinguish the charts; close-up live captures show restored native inner shirts on male_03 and female_01. Initial male/partial female exclusions required correction; masks are prototype-only and final visual acceptance remains pending.
- The user supplied `assets/clothing/deer.png` and requested left/right chest, arms, back, large centre and full back. Added seven editable placement presets in `assets/clothing/prints.json`, producing fourteen model-family print variants. The PNG is **644x794**, with real transparent/partial-alpha pixels; contain fitting preserves aspect ratio. Back prints split one source canvas across nonadjacent islands. First sleeve positions were on the inner arm; mesh-coordinate landmark inspection corrected them onto the outer upper arms.
- **Final static:** complete current asset build regenerated/staged **17 layers + 6 material patches / 40 scoped files**; image/mask/staging/checker-period regressions **165/165 passed**; installed-model/UV-landmark inspection **106/106 passed**; GLua **169 files / 0 failures**; unchanged sign regressions **151/151 passed**. The new landmark tests first exposed a PowerShell JSON-array wrapping mistake in the test reader; fixed the reader and reran successfully. Editor diagnostics and tracked whitespace checks are clean.
- **Live observed so far:** native-lit full centre deer on both models; full-back split on both, with exact seam continuity still requiring visual acceptance; female left/right outer sleeves and chest prints; corrected upper-chest placement and repeating checks; neckline close-ups preserve face/hands/native inner shirt. The small-back badge initially crossed a UV seam and lost part of the image; moved it wholly onto an upper-back island and captured the complete deer after a fresh reload. Not every final preset/model combination or inner-shirt colour/image mode has been live-reviewed. Remaining user visual review, clean/bloody/auto-catalogue implementation and service lifecycle checks are pending. No equip/unequip, inventory persistence, animation/corpse propagation or Phase F acceptance is claimed.
- Deer artwork is user-supplied for development; redistribution rights remain unverified. Do not treat generated/staged examples as a production release approval. Phase G/H remain later phases.

1. Trace the existing clothing item definitions, inventory/equipment slots, appearance selection, player-model material overrides, and bloody clothing/corpse handling. Inventory the actual supported player meshes, material slots, bodygroups and UV layouts before choosing a texture pipeline; do not assume every human model shares the same layout.
2. Prototype a skin-like clothing finish: artists can author an interesting repeating pattern, graphic or logo for a shirt and for pants, and see it mapped onto the supported character mesh as a clothing appearance. Treat this as a texture/finish applied to clothing on the character, not as a weapon skin or a replacement player model. Keep shirt and pants artwork independently editable and allow coordinated designs where useful.
3. Compare a UV-aligned source template with visible UV guides, editable pattern/logo layers and automated texture/material generation against the model's real UV/material constraints. Reuse an existing UV layout only when verified on the actual mesh. If artist input can be mapped reliably without opening a model editor, make that the preferred workflow; do not claim automatic UV mapping when seams, islands or material slots require manual mesh work.
4. Make the result part of the clothing system: define how a clothing item carries/selects its finish, how equipped clothing applies the corresponding shirt or pants appearance, and how unequipping/replacing it restores or changes the visible finish. Trace persistence and appearance-loading ownership before proposing schema changes; preserve profile-scoped persistence and server authority for owned/equipped item state. Keep appearance variants distinct from item stats unless a gameplay contract explicitly requires otherwise.
5. Prototype at least one shirt and one pants item/finish, each with an artist-editable source and in-game preview. Demonstrate the complete source-art-to-runtime path and the relationship between the selected clothing item and the visible finish, rather than validating only a standalone texture.
6. Preserve model and asset provenance: do not extract, edit or redistribute mounted Valve/Garry's Mod textures or models as addon assets. Use original or appropriately licensed artwork and document any mounted mesh/material references separately.
7. Verify how equipped finishes interact with the supported models' animations, bodygroups, gore material overrides, damage/corpse appearance and existing clothing choices. Keep unsupported models on a safe existing appearance rather than applying a mismatched UV texture.
8. If the preferred no-model-editor workflow cannot meet the requirements, document the exact mesh/UV/material blocker and the least manual fallback. Present evidence and options for user direction before expanding implementation or making a model editor mandatory.
9. **User-added catalogue scope (2026-10-05), after the core finish/equipment contract is verified:** automatically discover eligible images in `assets/clothing` and generate deterministic filename-based shirt/pants families, e.g. `deer_tshirt` and `deer_pants`. The user explicitly selected **both placed-graphic and repeating-pattern variants for every image**, not filename-suffix-only pattern selection. Include the approved chest/sleeve/front/back placements, repeatable checkered fabric and clean/bloody counterparts. Keep diagnostic inputs out of the wearable catalogue; document eligible filenames, generated IDs, regeneration/stale-output handling, provenance and bounded combination/output budgets before scaling to large image folders.
10. Build original bloody finish overlays and wire the appropriate variants into zombie variety and corpse/gore lifecycle. Inspect the actual walker meshes/UV/material owners first; verify group03 compatibility rather than assuming the group01 survivor masks fit. Preserve existing blood/sever/limb behavior and keep unsupported models on their current safe appearance. Catalogue generation and bloody zombie wiring are still pending, not implied by the current fixture shader inheritance.
11. **Filename/background and procedural fabric refinements requested by the user:** a recognised trailing colour token fixes the garment's background (`deer_black.png` always uses black); an unsuffixed name (`deer.png`) generates a small curated background-colour selection. Parse the colour independently from the artwork identity and retain deterministic collision-safe item/finish IDs. Document supported tokens and unknown-suffix behavior; do not silently infer arbitrary word fragments as colours. Add original deterministic stripes, checks and tie-dye fabric generation with coordinated palettes and artist controls. Keep pants predominantly single-colour, with restrained optional texture/creative variants rather than generating every loud shirt treatment on trousers. Retain both placed-graphic and repeating-image outcomes as already chosen, the independent inner-shirt controls, clean/bloody variants and explicit output budgets.
12. **Placement-token and repetition clarification (2026-10-05):** allow optional filename placement tokens for front, back, left/right arm and pants, combinable with background colour. Keep untagged curated placement outcomes and parse multiword placement/colour suffixes independently from artwork identity, detecting output collisions. The requested "checkered" pattern is **the artwork itself tiled repeatedly in X and Y over the garment**, not the procedural two-colour checker fabric. The user explicitly selected **placement tags restrict only the single graphic, while the repeating counterpart covers the whole applicable garment** (arm-tagged repeats cover the shirt; pants-tagged repeats cover pants). Keep skin/shoes/inner-shirt exclusions and clean/bloody variants. Aspect-preserving image repetition is now implemented for the fixture prototype; filename parsing/catalogue integration remains pending.

**Repeated-image prototype (2026-10-05):**
- Added independent shirt/pants motif size, spacing and offset settings in `prints.json`, shared aspect-preserving fitting, and integer-position motif copies. Direct fractional resampling at every destination initially differed by one RGB level across repeat periods; fitting once and copying fixed this without relaxing the exact-pixel test.
- `repeat` works with shirt, pants or both fixture modes; server material preflight checks only the layers actually used. Skin/shoes and native inner-shirt exclusions remain intact. Reuses the six existing runtime targets; no equipment slots, saved appearance or inventory changes.
- Complete build regenerated/staged **20 layers + 6 patches / 46 scoped files**. **Static:** clothing regressions **198/198 passed**, including RGBA exclusions, spacing, both-axis coverage, exact combined-fabric periods and repeated-layer VTF/hash checks; GLua **169 files / 0 failures**; edited-file diagnostics clean.
- **Live:** reloaded only the confirmed `preview` map `zz_preview_817d995084d3`; inspected female three-quarter/side/back and male side/back screenshots showing actual deer repeats on torso/sleeves/pants with native skin/shoes. Initial front views were partly blocked by the survivor; a camera-only three-quarter capture resolved the female view without moving the player. Diagnostics resolve 1024-square textures, `VertexLitGeneric` and native normals; observed builds about **13.82 ms female / 3.39 ms male**, not performance acceptance. No new affected-module errors in the inspected log tail.
- **Independent pants live check:** female pants-only `repeat` resolves its own native-lit texture (observed build **1.18 ms**) and the reviewed side capture shows the unchanged native shirt, face, hands and shoes. This is appearance evidence, not an equip/persistence check.
- **Human gate:** final garment/motif scale and seam/style approval remains pending before broad equipment/catalogue wiring. Phase F remains in progress, not accepted; automatic filenames, tie-dye, bloody/zombie variants and complete equip/persistence lifecycle remain unfinished.

**Fixed-finish equipment continuation (2026-10-05):**
- User explicitly approved the current garment masks/repeated-image prototype direction and requested continuing equipment integration. This is not whole-phase acceptance.
- Added shared clothing ownership/finish registry and validated `clothing` item definitions, with original base-artwork `itemPrototypeShirt` and `itemPrototypePants`. Independent slots 5/6, preserved weapons 1-3 and armour 4. Cosmetic-only, no radiation/combat changes.
- Wired public equip routing, atomic replacement, move/unequip, snapshot publication after successful persistence, inventory SHIRT/PANTS tiles and actions, native restoration and model guard. Extracted the existing accidentally nested wearable routers from `EquipWeapon` so the new public path is available at startup.
- Equipment composition reuses the shared native-preserving compositor with six separate targets/patches; diagnostic style changes cannot overwrite equipped finishes. Scoreboard selection and server-owned immutable player death-ragdoll snapshots are implemented but their appearance/lifecycle still needs live acceptance. Corpse selection is one packet, independent of later re-equips, source-player presence and delayed visibility.
- **Static/automated:** artwork/patch regressions **216/216 passed**; GLua **171 files / 0 failures**; edited-file diagnostics and focused tracked whitespace clean. **In-engine suites:** static data **18 passed / 0 failed**, inventory **50 passed / 0 failed**, including clothing replacement, wrong-slot rejection, real SQLite round trip, profile isolation, existing death-loss policy, independent unequip selection and failed-save/no-publication checks.
- **Actual live survivor:** confirmed supported `male_03`; saved inventory baseline and temporarily granted exactly one shirt/pants pair to empty slots 5/6. Original weapons/armour stayed in place. Reviewed live screenshot and diagnostics show the independent `equipped_male_both` finish. Same-map preview reload retained both exact clothing instance IDs and finish selections.
- **Further live results:** user confirmed all six Inventory slots and clothing controls work correctly. Removing the shirt restored native shirt appearance while retaining the equipped pants, then removing pants cleared all owned overrides. Verified the exact original inventory rows against the saved baseline; both temporary items are removed. A capture dispatched immediately after removal preceded the 0.25-second client scan; the later settled capture reports `applied = 0`.
- **Final automated:** immutable corpse-snapshot regression added; inventory now **51 passed / 0 failed**, GLua remains **171 files / 0 failures**. This does not verify a real death ragdoll's rendering.
- The subsequently completed core live gates are recorded below. Automatic filename catalogue/tie-dye/bloody zombie variants remain unfinished; Phase F is not accepted.

**Core live completion and restoration (2026-10-05):**
- User explicitly authorized killing/testing the current development survivor. The first real death lost the original **17 backpack stacks** under the existing policy; these remain lost, not restored. Original weapons/armour survived unchanged.
- Real corpse rendering initially failed: the actual client entity is **`class C_HL2MPRagdoll`**, not the server class `hl2mp_ragdoll`. A focused client probe established its exact class/model/material/packet; correcting the scan produced the actual dressed corpse. Server `GetRagdollEntity():GetModel()` may be nil and was not used to infer the client mesh.
- A further real death verified immutable selection after both garments were moved out of equipment while the corpse remained: server player selections were empty, the corpse packet retained both prototype finishes, client diagnostics applied only to the actual ragdoll, and `clothing_corpse_after_unequip` pixels show its teal check shirt/olive pants.
- Inventory was already human-reviewed. Autonomous screenshots initially omitted VGUI despite actual client receipt and dressed dossier diagnostics. Added a final-VGUI path only for ordinary captures with Inventory/scoreboard open, preserving explicit world-camera captures and one capture per frame. Actual Inventory/scoreboard pixels now reviewed; queued Inventory captures used consecutive distinct frames 397841/397842. A mixed explicit-world/ordinary-UI queue also passed on frames 418956/418957 with `afterVGUI = false/true`.
- A preview-only, character-scoped temporary model helper preserves original model/skin/bodygroups and never writes character appearance. Actual female_01 equipment and dossier showed both garments, pants-only with native shirt and fully native restoration. Unsupported male_01 retained native appearance with both clothes equipped and zero owned overrides.
- **Cleanup:** all three temporary garment pairs removed after exact instance/container checks. Original male_03 appearance restored; clean preview reload leaves the survivor alive with native clothing and no helper-opened UI. Exact equipped IDs, slots, levels, clips, attributes and other saved fields match the scoped pre-death record. Authorized backpack loss is not concealed as a full-inventory restoration.
- **Focused performance:** five-second native/equipped single-survivor profiles measured clothing scanning at **0.0098/0.0170 ms per frame**, maximum **0.150/0.140 ms**, positive allocation **0.028/0.044 KiB per frame**. Runs were approximately 20 FPS, not a 60-FPS acceptance or crowd/cache stress check.
- **Next:** automatic filename catalogue and original procedural/bloody variants, with a deliberately bounded reference-safe outfit cache before additional wearable finishes. The current six-target fixed-finish cache must not be overwritten across distinct equipped outfits. Representative performance, remaining seam/animation/gore coverage and Phase F acceptance remain separate.

**Checks:** Verify shirt and pants artwork against the real mesh UVs, including seams and logo placement; regenerate assets from clean editable sources; and test item selection, equip, replacement, unequip, save/reload and profile scoping through the owning clothing/inventory paths. Confirm the appearance updates for the player and relevant corpse/gore copies without breaking animations or material cleanup. Exercise the prototype in a running preview client and obtain visual review.

**Single-image pants preparation (2026-10-05):**
- User selected **a large graphic running down one leg** for the pants single-image default, rather than a small thigh/pocket badge. Repeated-image pants remain a separate whole-pants counterpart.
- Inspected actual mounted-model triangle/UV landmarks; positive anatomical X agrees with the already reviewed left-sleeve mapping, and negative Y agrees with the front neckline. Added model-specific 88x312 front-left-leg canvases in `prints.json`, reaching thigh/calf without touching the opposite leg.
- Added fixture-only `pants_leg` for `pants|both`; `both` retains the base shirt. Existing six diagnostic targets are reused; independent equipment is untouched.
- **Static:** installed-model/UV inspection **112/112 passed**, artwork/mask/texture/staging regressions **234/234 passed**, complete build **22 layers + 12 patches / 56 files**, GLua **171 files / 0 failures**, edited-file diagnostics clean.
- **Live:** inspected male/female front/left captures on the unchanged preview map. The image appears on one leg; native shirt, skin and footwear remain intact. The user then selected **preserve the whole graphic: tall artwork fills the leg, wider artwork stays shorter**, rather than center-cropping to force full height. The deer therefore remains centered around the knee. This resolves fitting policy, not final visual approval of this new placement.
- User subsequently approved the single-leg placement as the catalogue template; do not repeat the resolved placement/fitting decisions.

**Filename catalogue and artwork-tone constraints:**
- **New user-requested placement scope (2026-10-05):** add optional cuff/hem-anchored single-leg artwork, e.g. flames originating at the trouser opening and extending toward the thigh, rather than centring a shorter image on the knee. Preserve the approved centred, aspect-preserving default; introduce explicit artist placement/alignment controls rather than silently stretching/cropping all art. User clarified that flip-side variants mean **both opposite left/right limbs and front/back-facing surfaces of the same limb**, for legs and arms. Inspect/calibrate each supported model's corresponding UV islands, keep text upright/readable, and generate bounded named variants visible in the Wardrobe. Not implemented or visually accepted yet.
- Implemented bounded PNG discovery, stable wearable IDs, placement/colour suffixes, `not<colour>` exclusions and a generated catalogue with a 16-slot reference-safe outfit pool. Runtime integration/cache capacity/recovery have not yet been verified live.
- Added artist-declared `_dark`/`_light` artwork tone, distinct from background colour. Tone-specific curated palettes are checked by linear-sRGB luminance against reference black/white (minimum 4.5). Exclusions, fixed colours and placements combine in any order; single-image and whole-garment repeating counterparts obey the same constraints. Conflicting/exhausted choices fail explicitly.
- **Static/build:** catalogue regressions **61/61 passed**; regenerated **40 finishes / 180 owned files**, with tone metadata and matching addon/game-root assets/manifests. Actual supplied `boardsofcanada_notblack.png` has **18 variants, zero black**. Tone-tagged fixtures prove dark artwork excludes black/charcoal and light artwork rejects white; no supplied artwork was renamed or modified.
- **Live:** generated catalogue loading/equipment and pool pinning/reuse/overflow recovery remain unverified. Procedural tie-dye, bloody/walker counterparts, representative performance and Phase F acceptance remain pending. No maps or production outputs changed.

**Exit:** A user-approved skin-like finish workflow is demonstrated end to end for at least one shirt and one pants clothing item. Artist-editable pattern/logo inputs map correctly to supported meshes; the clothing system selects and applies the appearance; lifecycle and persistence behavior are documented and verified. Supported-model/UV limits, asset provenance and any unavoidable manual steps are explicit. If the requested editor-free approach proves infeasible, present evidence and options before proceeding beyond the prototype.

**User-added preview Wardrobe:**
- User selected **window model only**, with no live-character, inventory or saved-appearance mutation. Added preview-admin Wardrobe in the Tab radial menu and dev UI bridge, using the normal exclusive/transient-window lifecycle and eligibility-based closure.
- Left grid lists all registered shirt/pants finishes, with search/filter and actual texture/print swatches. Generated icon metadata reuses calibrated male/female canvases and stitches split-back prints; no per-icon models or render targets. Right model supports independent shirt/pants selection, male/female, rotation and native resets.
- **Static/build:** GLua **172 files / 0 failures**, catalogue/icon regressions **74/74**. Latest inputs produce **38 generated finishes / 174 owned files**, plus the two fixed prototypes in the grid. The user-supplied Boards of Canada input now declares `_dark`; it selects the lighter contrast palette.
- **Live:** initial human review rejected stock white panel backgrounds/side-on camera. Corrected explicit panel colours, search/rotation/status visibility and front camera. Revised captured pixels show generated white Boards of Canada shirt and olive deer pants, **40 entries / zero icon errors / composition applied**. Full interactive/filter/rotation/close review and Phase F acceptance remain pending.
- Final female capture also shows the selected generated outfit; live survivor shirt/pants selections remain empty. Close clears window selections and releases the cursor (`cursorVisible=false`); reopening returns the native model. In-engine post-catalogue suites pass **static data 18/18, inventory 51/51**. Full interactive search/filter/rotation/reset and human acceptance remain pending; no items granted or saved appearance changed.
- **User acceptance:** the user called the Wardrobe excellent and requested continued Alpha work. Preserve its current approved layout/direction.

**Outfit pool gate and original fabric library:**
- **Follow-up corrections requested 2026-10-05:** the user rejected the small catalogue and pixelated dye, requested hundreds of choices and a centred CHEST preset, and supplied visible full-back/repeating-back seam failures. These supersede the earlier fabric approval as complete quality acceptance. Expanded source plan now has 206 fabrics plus 44 image finishes (250 generated choices); per-texel dye replaces 8x8 fills. Pure fabric checks 608/608, filename/icon checks 81/81, GLua 173/0 failures. Full staging is underway; torso mesh seam inspection and corrected live review remain required. Do not claim these reported back-seam issues accepted.
- **Corrective implementation:** fresh torso inspection resolves actual seam vertex pairs, including the curved/vertically-offset female chart. Back fabrics, full prints and repeats now sample continuous model-space artwork through those triangles, with bounded two-texel bleed and alpha-correct interpolation. Flat back-print icons avoid invalid rectangular stitching; Wardrobe resolves icon materials on first paint and labels distinct fabric treatments. Physical seam checks **38/38**, rebuilt prototype **248/248**, current filename/icon **84/84**, model inspection **112/112**. Added PNGs include `_black_chest` and `_pink_chest`; pink is now recognised, and chest is upper-middle torso rather than full-front. Latest 13-family plan: **150 image + 206 fabric = 356 finishes**, plus two prototypes; combined budget raised to 384. Complete staging and live/human verification are pending; no inventory changes or map builds.
- **Publication/live follow-through:** built/staged **356 finishes / 1344 owned files**. Built fabric checks **2754/2754**, built image/icon/ownership checks **1901/1901**. First fresh load exposed the shared loader's old 256 cap; matched its bounded finish/item limit to 384, retained the sixteen-target pool, reran GLua **173/0**, and reloaded the same confirmed preview. Fresh in-engine static data **18/18** and inventory **51/51** now pass. Actual sunset Wardrobe capture has **358 entries**, applied composition, no encountered icon errors and native live survivor garment strings. Human inspection of new dye/chest/back/full/repeat on both sexes is the next gate, not accepted yet. No equipment grants, deaths or persistent appearance changes.
- **Human follow-up:** user selected the successful visual-review option but corrected CHEST size/height with a pink-shirt screenshot: the 76x54 graphic was too small and high. Enlarged it to **120x90 at Y=772**, centred independently on both sexes, preserving uncropped aspect fitting and distinction from the full-front print. Exact preset/parser checks **84/84**. Rebuild/reload and final chest review are pending; retain the user's dye/back feedback without claiming the revised chest is accepted.
- **Combined-shirt addition:** user clarified that front-and-back means one shirt carrying the same artwork on both sides. Added `front_back` to each shirt-image palette alongside existing placed/repeat variants, using fitted front artwork and seam-projected back artwork. Pants-only families remain unchanged. Focused parser/icon checks **85/85**, GLua **173/0**; prototype checks explicitly require visible artwork on BOTH sides. Plan **181 image + 206 fabric = 387 finishes**, 389 with prototypes; generator/shared runtime caps now match at 512. Rebuild includes the enlarged/lowered chest; unchanged fabrics are reused only when the full design hash and built/content/installed VTF/VMT hashes match. Build/live/visual follow-through remains pending.
- **Final current-artwork publication:** user confirmed PNG additions were finished after successive builds detected changing inputs. Final **20 image families / 355 image finishes + 206 fabrics = 561 generated finishes, 563 Wardrobe entries / 2166 owned files**. Bounded image allowance now 32; generator/shared finish cap 640, pool still 16. Reused unchanged image/fabric layers only after content-key and built/content/installed hash checks. Built catalogue **3361/3361**, fabrics **2754/2754**, prototype **264/264** including both-side assertions, GLua **173/0**, whitespace clean. Same confirmed preview reloaded; static **18/18**, inventory **51/51**. Actual enlarged pink-chest capture shows applied placement with native live selections and no encountered icon errors. Final human larger-chest/combined-shirt review pending; no grants, deaths or saved appearance writes.
- **Subsequent user direction:** enlarged CHEST approved; remove combined front/back, raise back images slightly, use colourful defaults for untagged shirt artwork while retaining explicit light/dark contrast rules (confirmed), and raise pants artwork onto the thigh with an opposite-leg choice. Full back raised 3 model units, small-back preset raised 12 UV pixels. Seven default shirt colours; `pants_leg` remains the stable left-side ID and new `pants_leg_right` uses independently inspected opposite-thigh UVs. Both 88x144 canvases are raised to male Y=40/female Y=20 and labelled left/right thigh in Wardrobe. Current 20-family plan **584 image + 206 fabric = 790 finishes / 792 entries**, +229 versus previous 561; caps32images/896finishes, pool16 unchanged. Parser/icon **85/85**, actual left/right male/female geometry **118/118**, GLua **173/0**. Build and new back/thigh visual review are pending; cuff anchoring and rear-facing limbs are still separate unfinished scope.
- Actual preview client pool tests initially exposed empty engine getter values immediately after local overrides: the allocator could treat an owned outfit as unpinned. Pin applied clothing state directly; expose effective owned submaterials for gore capture and keep immutable material records on live copied limbs. Failed builds now retry instead of caching failure permanently.
- **Live-client regressions 5/5 passed:** shared outfits, independent native restoration, male/female layouts, pending/live gore references, sixteen simultaneous distinct outfits, seventeenth native overflow, released-slot recovery, build-failure retry and fixture cleanup. This is actual client composition/reference behavior; real sever-animation visuals and generated-item persistent equipment remain separate.
- Added original deterministic stripe/check/tie-dye library in `assets/clothing/fabrics.json`: six shirts and four subdued pants, separately bounded rather than multiplying all artwork by all fabrics. Original procedural rendering reuses the existing mask/inner-shirt/texture pipeline.
- **Static/build:** fabric pixels/configuration/staging **141/141**, filename/icon **74/74**, unchanged prototype **234/234**, GLua **173 files / 0 failures**. Latest build **48 generated finishes / 206 owned files**, plus two prototypes = **50 Wardrobe entries**. Post-generation static-data/inventory suites **18/18 and 51/51**.
- **Visual iteration:** ocean/sunset Wardrobe captures rendered correctly; user requested more recognisable spiral/ring tie-dye. Tightened radial cycles around the calibrated front torso and added artist-controlled UV centre. Revised sunset capture shows the requested spiral. Await human confirmation of revised fabric appearance; no Phase F acceptance is implied.
- **User acceptance:** the user approved the revised spiral fabric direction. Preserve the tighter torso-centred spiral rather than returning to the rejected broad colour wash.
- **Generated-item live persistence:** saved exact four-item inventory baseline, granted only sunset tie-dye shirt `6ac35e13601c890001` and olive deer pants `6ac35e13a5e18a0002`, equipped slots 5/6 and reloaded the same preview map. Exact instance IDs, garment selections and slots survived; original weapons/armour fields and attributes were unchanged. Dressed dossier pixels verified. Independently removed shirt, then pants, after exact identity/container/count checks; original inventory/model restored with zero owned overrides.
- The pants-only dossier capture exposed render-target clipping when a cache miss built from `DModelPanel.LayoutEntity` during VGUI paint. Moved scoreboard composition to `PreRender`; a new exact one-pants probe showed the native shirt restored without the black/clipped rectangle. Removed that probe too and reverified every original equipment field/attribute. No death tests or backpack loss in this continuation.
- **Next:** cuff-anchored and left/right/front/back leg/arm calibration, original bloody counterparts and inspected group03 walker integration; representative performance/animation/seam/gore review remains required. No maps or production outputs changed. Temporary generated equipment changes were reversed and the exact live inventory/appearance restored.
- **Cuff extension published and accepted:** separate `pants_cuff`/`pants_cuff_right` bottom-aligned 88x344 canvases reach inspected front lower-calf UVs (Y384 bottom) without changing existing thigh presets/identities. `_pants_cuff` restricts placed graphics to these two sides; default pants additionally retain both thighs and repeat. Separate source presets avoid rehashing existing approved print families. Published660image+206fabric=866finishes/868Wardrobe/3482ownedfiles; caps896/pool16 unchanged. Artwork fitting25/25, actual topology134/134, prototype306/306, parser/icon90/90, published7319/7319 (includes exact preservation of all790priorfinish/itemdefinitions and ownedfiles), fabrics2754/2754, GLua175/0. Fresh preview launcher reload: static18/18/distribution9/9/clientpool5/5. User deployed existing survivor into `zz_preview_817d995084d3` and approved cuff placement on male/female left/right variants; exact female-right snapshot confirms applied window-only cuff selection and no icon errors. The subsequent left snapshot captured the male model after browsing, so it is not female-left screenshot evidence; female-left acceptance is the user's explicit review. Live equipped clothes/inventory were not changed. Workshop audit6659files/7packs/1505exclusions/387blockers; no new GMA build or upload. Rear-facing legs/arms, bloody/walker work and full Phase F visual/performance acceptance remain incomplete.

- **Next rear-limb scope decision:** user chose **explicit artist filename tags only** for rear-facing leg/arm variants, not adding them to every eligible image or raising the 896-finish budget. Independently calibrate supported rear charts and keep ordinary/default catalogue identities unchanged; do not silently replace existing front/outer-limb styles. Rear placement implementation and visual approval remain pending.
- **Rear-limb implementation and placement accepted:** added `_pants_back_left`, `_pants_back_right`, `_arm_back_left`, `_arm_back_right`; each restricts the single graphic to the named anatomical rear limb and retains its whole-garment repeat. Separate `rear_limbs.json` owns independently inspected male/female rectangles/signatures (48x144 rear thigh, 24x48 rear upper arm). Planner/icons, model-specific build/hash inputs, Wardrobe labels and diagnostics are wired. Existing20image-family/866finish/868entry plan and896cap unchanged; there are no rear-tagged source PNGs, so no extra rear wearable entries were published. Parser106/106, actual topology170/170, prototype370/370, published catalogue7335/7335, GLua175/0; editor diagnostics/whitespace clean. Reloaded confirmed preview `zz_preview_817d995084d3`; user approved all eight model-family/side/limb placements with temporary deer fixtures, then fixtures were removed. No saved inventory/equipment changes. This accepts rear placement, not glyph-by-glyph text, all-animation/gore/performance or full Phase F.
- **Walker inspection prerequisite:** extended mounted inspector with explicit model groups and separate reports; default survivor report and guides remain unchanged. All15group03player bodies inspected:2048-square sheets, distinct body-vertex counts/UV fingerprints versus correspondinggroup01bodies. Walker inspection48/48 verifies metadata and isolation. Do not apply1024survivormasks to these uncalibrated charts. Currentmounted search cannot resolvegroup02player/male_01; that separate attempt failed explicitly and is not verified. Existingwalker selection/bloodyoverrides unchanged. **Next:** original bloody layers/counterparts, independentgroup03calibration and actual walker/sever/corpse lifecycle/performance. No maps regenerated, Workshop uploads or asset cleanup.
- **Offline bloody-counterpart implementation (game closed, 2026-10-05):** user explicitly chose shared original blood overlays over existing finishes, not duplicate bloody item definitions or increased budgets. Added editable `blood.json`, deterministic original soft irregular stain/droplet generator, builder and exhaustive regression. Three1024DXT5/11mip layers (male/female shirt, shared pants), six stagedfiles/4,195,578bytes; masks preserve native skin/shoes/inner shirt, backs reuse inspected physical projection. Blood32/32 checks every pixel of each mask, raw-pixel determinism, bounded partial coverage, alpha/mips/compression and exact staging. Preview-only Wardrobe blood toggle/compositor/cache distinction uses existing sixteen slots, defaults off, fails explicitly for missing overlays and retries rather than clean success fallback. No new items, saved blood state or automatic gameplay/walker changes. Existing866finish/868entry catalogue passes5753/5753; GLua175/0/editor diagnostics clean. Client pool suite now includes blood/clean sharing, restoration, retry and invalid-flag cases; **new cases and toggle/render appearance unrun while the game is closed**, not covered by prior5/5.
- **Independent walker calibration groundwork:** mounted inspector now writes group03male_03/female_01 independently named2048charts and full physical/UV body-triangle diagnostics, always `garmentMasksVerified=false`. Wrong-group requests reject before writes; survivor1024charts/report unchanged. Survivor170/170 and walker56/56 pass serially. An initial parallel isolation check raced the blood builder's survivor-report refresh; serial rerun passed, not a claimed compatibility fix. No survivor masks stretched onto walker sheets. Packaging fixtures47/47 (including six blood companions in one clothing shard/native GMA verification); actual read-only audit6681files/7packs/1505exclusions/387releaseblockers unchanged. No fullGMArebuild/upload or map generation. **Next:** live blood toggle/pool/seam acceptance, actual gore/corpse/limb checks, independentgroup03garment-mask calibration and walker variety integration; retain existing native bloody overrides until verified. Phase F remains unaccepted.

**Citizen-only integration and individual randomisation (2026-10-05):**

- The user explicitly prohibited artist/catalogue clothing on rebels. Group03
  calibration is no longer a rollout target; its diagnostics remain research,
  while native mounted rebel blood/material behavior is preserved.
- Engine `util.GetModelMeshes` confirmed alternate shirt atlases among citizens.
  Independent physical-triangle matching, robust upright affine fitting and
  clipped per-model transfers retain unmatched native neckline charts. Calibration
  passes **80/80**. A generated ~5.3 MB transfer manifest reuses existing catalogue
  and blood layers; no per-model/finish texture multiplication.
- The user reviewed and approved **all fifteen group01 citizens** (nine male,
  six female), including chest/back/repeat/leg artwork, blood and native restoration.
  The user also approved actual citizen walker, corpse and detached-piece visuals.
  Wardrobe has all fifteen model choices and remains window-only.
- The initial implementation shared one outfit per model/cell. The user requested
  independent full-catalogue randomisation instead and approved **96 shared targets**
  (~384 MiB maximum RGBA storage, created lazily, plus source/material memory).
  Each spawn now has a unique persistent seed; ticketed walkers use their stable
  ticket identity/profile/source cell/model/catalogue revision. Blood refresh does
  not reroll clothing. All eligible shirts and pants, including original fabrics,
  participate; deterministic coverage tests reach every garment.
- Corpse snapshots and pending/live severed pieces retain immutable outfit
  selections and reference-safe copied materials. No player wearable grants,
  saved appearance changes or inventory writes are introduced by outfit assignment.
- `build_clothing_catalogue.ps1 -PoolOnly` publishes 192 native-inheriting pool
  patches while retaining all **866 finish/item definitions and existing textures**.
  Ownership grows only by 160 tiny VMTs: **3642 files**, 868 Wardrobe entries,
  unchanged 896-finish limit. Catalogue/preservation checks **8035/8035**,
  packaging fixtures **48/48**, GLua **175 files / 0 failures**.
  Actual package audit: **6842 files / 7 packages / 1505 exclusions / 387 blockers**.
- Fresh preview live checks passed **Gore 16/16**, **static 18/18**, **inventory
  51/51**, and **client pool 9/9**. The first 96-slot stress run passed but froze
  the client and logged a render-queue flush. The test now spreads capacity and
  citizen steps across frames; its fresh rerun again passed **9/9**. Runtime
  composition also uses a **2 ms soft per-frame budget**, allowing one cold build
  to exceed it but not batching another behind that build.
- Real same-model crowd: **15 male_03 walkers, 15 independently selected outfits,
  all bloody**. Its later client capture contained 14 walkers, one dressed corpse
  and seven copied limb models with 15 distinct materials; do not misreport the
  total applied-entity count of 22 as 22 outfit targets. A clean subsequent mixed
  crowd verified **15 dressed walkers / 15 citizen models / 15 composites /
  96 capacity / zero pending**.
- Mixed-crowd cold builds measured **16.807 ms mean / 21.452 ms maximum**. The
  capture-free warm run recorded **600 frames / 10 seconds / 60.00 FPS**;
  equipped-clothing hook **0.02034 ms/frame**, max **0.4482 ms**. This is one
  representative warm observation, not worst-case cold/horde acceptance.
  The native-control attempt copied a stale report before its delayed completion,
  used a different model mix and removed probes before completion; it is **not a
  valid matched comparison**. No IMesh optimization is claimed.
- Owned crowd/quality probes were removed/restored. Survivor remained alive,
  health100, preview `zz_preview_817d995084d3`, persisted cell22,0. No map generation,
  production promotion, uploads, commits or broad cleanup. Phase F still requires
  explicit whole-phase user acceptance; Phase G/H and release deferrals remain.

## Phase G — Integrated Preview, Visual Review, And Acceptance

### Pre-integration distribution gate (requested 2026-10-05)

- Read-only in-flight audit: content **4.75 GB / 4.42 GiB**; materials
  **3.016 GiB**, maps **1.149 GiB**, models **0.218 GiB**. Clothing
  **3073.65 MiB**, of which last-published-manifest-owned assets were
  **1423.12 MiB**, unowned hash files **1612.51 MiB** (includes active build
  outputs; not all established stale), prototype/other **39.35 MiB**.
- Root cause: full 1024-square DXT5 sheets per finish/model family, plus
  temporary old/new coexistence and interrupted-build orphans. Typical VTF
  **1,398,360 bytes / 11 mips / format15**; latest790finish plan up to
  **1573 layers / 2097.7 MiB** before deduplication. Maps mix preview/city;
  broad recursive content shipping is not acceptable.
- User's approximately4GB Workshop-per-addon ceiling recorded. Official
  creation documentation does not establish that numeric limit; packed,
  compressed-upload and extracted sizes must be tracked separately.
  Initial recommended shard target **1 GiB raw**, with installed uploader
  limits verified before publishing.
- Recommended next bounded task, after the current clothing build: release
  inventory/ownership audit, safe orphan reporting, size-budget enforcement
  and deterministic **Core / Common Content / Clothing Content shards /
  World Content shards covering city AND preview**. Preview ships as a
  player-accessible sandbox, explicitly confirmed by the user. Preserve paths and original sources;
  build isolated allowlisted packages. One virtual file owner, companion/
  dependency closure, mandatory-pack/version checks, clear missing-pack errors.
- Exclude development outputs/bridge inputs/unowned hashes/uncleared artwork;
  root audio path `sound`, not `sounds`; native Walker DLL separate server
  installation. Collection/server mounting and client downloads are distinct.
  Test without loose development files masking missing assets.
- **Implementation authorized and landed (2026-10-05):** profile-aware
  allowlisted inventory and report-only orphan/exclusion audit; deterministic
  byte-budget shards; isolated SHA256-verified staging; bundled-gmad packing
  with extract/hash verification; strict release gates and full ownership/
  payload/metadata/GMA size reports. Current default inventory **6347 files /
  7 shards**, each under1GiB: Core, Common, 3 Clothing, 2 World.
- Packaged-only startup marker/version/file-size diagnostics in both realms,
  client Workshop content requests and server/client character-deployment
  gate implemented. Loose developer behavior retained. Audio and music registry
  staged together under canonical `sound`; original `sounds` source unchanged.
  Core Workshop ID is configured, not the old hardcoded source ID.
- **Static/automated:** packaging fixture checks37/37 including actual gmad
  round trips, both launchers/worlds and byte-identical unchanged content
  markers across core-only updates; GLua175/0. Latest790finish catalogue
  published3178owned files; built catalogue5124/5124, fabrics2754/2754,
  prototype266/266. Raised back/new thigh/palette human review still pending.
- **Live loose-preview regression:** same confirmed `zz_preview_817d995084d3`
  reloaded; final distribution8/8 (including actual GAME file-size probe
  and independent content-revision compatibility),
  music10/10, static18/18, inventory51/51.
  This is not a clean mounted-package/client-download acceptance.
- Audit reports **376 missing navmeshes**, legacy city runtime profile identity
  absent, no city skyline manifest, unassigned7Workshop IDs and uncleared
  artwork/common provenance. Strict release remains blocked; do not regenerate
  production automatically. No source/installed deletion, relocation or publication.
  Seven real development GMAs were packed, extracted and independently
  checked **6414/6414** at `generated/workshop/b89bee899d6e`; raw staged
  **3,737,841,516 bytes**, GMA total **3,738,385,682 bytes**. Each actual GMA
  remains under1GiB. Final audit excludes1505files/480,176,180bytes;612unowned
  clothing files408.13MiB remain untouched. Only this task's obsolete offline
  package baseline was cleaned after preserving its report. Compressed upload
  size and clean mounted/download/deployment acceptance remain unverified.
  See [Workshop distribution planning](readme.md#workshop-distribution-planning).
- **Launcher/ID follow-up:** user accepts engineering as sufficient to continue
  development; no immediate publication is required. Both launcher BSPs now
  belong to Core, allowing content diagnostics before entering city/sandbox.
  Client launcher checks real Workshop subscription/download/mount states and
  offers Content Addons/Open Workshop/Recheck through its existing navigation.
  Mounted-file/revision readiness, not subscription alone, gates deployment;
  no automatic subscription. Refresh does not repeatedly retrigger autoload.
- Settings now use `pending:<pack-id>` temporary labels, emitted separately
  from actionable IDs. Never send placeholders to Steam or substitute invented
  numeric IDs. Strict release still rejects them. Documented private minimal
  owned-payload reservation, record Steam-assigned IDs, rebuild with actual IDs,
  update the same items, then visibility/clean-download acceptance. The
  builder is not an uploader; new asset domains require ownership/allowlists.
- Latest source fixture count46/46 (including pending-to-real-ID strict-release
  staging/descriptor/manifest round trip) and live distribution9/9, music10/10,
  static18/18 pass; GLua175/0. User reviewed and approved Content Addons,
  Recheck/Back navigation in the loose preview installation. This is not
  actual published-ID/subscription/download/mount acceptance. Earlier
  seven-GMA output remains historical validation, not a latest-source release.

Status: **ACCEPTED — user confirmed on 2026-10-05 that existing integrated results and earlier skybox reviews are sufficient, and explicitly requested proceeding directly to Phase H without repeated checks or regeneration.**

The steps below retain the original integration checklist for historical context.
No additional Phase G build, inspection or matched capture was performed by this
acceptance. Previously uncaptured collision/baked-light/neighbour-view and
performance checks remain evidence limits, not outstanding milestone gates.
Separate Workshop rights/IDs/navmesh/production-export/clean-mount release
blockers remain deferred and are not cleared by this development acceptance.

1. Regenerate the preview manifest and template plan from the agreed stable seed, rebuild only affected recipes and skybox models, and stage the preview only after focused checks pass.
   - Validate the updated launcher rooms with `bin/test_launcher_parity.ps1`, resolving intentional versus accidental differences first, then explicitly run `bin/build_launchers.ps1 -WorldProfile preview`. The city build does not update launchers automatically. Verify both preview BSP staging hashes and test the launcher scene/deployment flow after a safe reload; leave production city untouched.
2. Review the compiled report, required-cell coverage, visibility budgets, skybox model report, and matched performance captures. Correct failures before requesting visual review.
3. Test in a running preview client at central, outskirts, and edge cells; review skyscraper distribution, skyline visibility, shoreline/waves, each cardinal world edge, and corner joins. Include the applicable snow/weather state and verify the world map still captures the playable cell.
4. Review the sign/billboard and clothing workflow prototypes alongside the world changes; verify the documented artist paths reproduce the accepted examples.
   - Carry-over explicitly authorized when accepting Phase E: inspect the sign zoo in Hammer/game for static collision and baked spotlight appearance, then inspect actual authored tile placement and neighbouring-cell skybox rendering. Preserve separate prototype approvals; successful compilation is not visual acceptance.
5. Record automated, compiler, runtime, and user visual-acceptance results separately. Keep any untested items explicit and any prototype-only outcomes clearly distinguished from production-ready tooling.

**Exit:** Preview artifacts derive from current source inputs, required structural/model checks pass, no regression is observed in bounds-dependent systems, the artist workflow prototypes reproduce their accepted examples, and the user accepts the integrated results.

## Improvements

- The new skyscraper buildings should be properly integrated into the game world with the center of the city having more collections skyscrapers and the outskirts having fewer skyscrapers
    - The idea is that in the skybox you can see these skyscrapers and get a sense of the city's layout and density.
    - Consider changing skybox so its larger and always renders cells with skyscrapers so we get a nice city skyline silhouette in the skybox
    - tile_skyscraper is not a landmark and is just a regular building type.
- Since we have shores around the world. I have decided that I would like to give a unique "world edge" border for each side of the map. Also, can you improve the shorelines as they kind of look weird and there is also no waves? Spend a good time figuring out how to improve the shorelines. Anyway, on the North side of the map, I would like to render hilly terrain, then on the east side, i would like to render mountains, then, on the south side, i would like to render flat lands. 
    - You should be able to see the mountains from the skybox no matter where you are in the city, to help orient yourself and get a sense of the world's layout.


## Promoted Research

- Sign and billboard asset authoring is now in Phase E.
- Artist-friendly shirt/pants authoring, including whether it can avoid a model editor, is now in Phase F.
- The target is a skin-like texture finish on actual supported human meshes: editable shirt and pants patterns/logos connected to clothing items and applied when those items are equipped.
- These are in-scope research and prototype phases. Any technical or asset-provenance blocker must be reported with evidence and options rather than silently dropping the goal or claiming a complete workflow.


## Additions

- New tile_skyscraper buildings. They are very tall so we will have to determine appropriate size of the containing skybox for the cell as well as the positon of the skybox currently will have to be tweaked to support these new super high tiles.


## Bugs

No bugs have been confirmed for this milestone yet. Add verified findings here with reproduction context; keep hypotheses labeled as such.

## Phase H — Optional User-Selectable Sky Palettes

Status: **ACTIVE — expanded licensed catalogue and custom palettes implemented/user-reviewed; visual slot editor implemented. Broader palette/lifecycle/performance acceptance remains. No maps rebuilt for this work.**

**Additional automatic variants and Phase H continuation (2026-10-06):**
- Added six profiles: Cloud prelude, Terrassee horizons, World's End horizons,
  Cloudbound, Neon twilight (stylized) and Alien embers (stylized). Eighteen
  built-ins now use all eight newly added sets except John Tron, explicitly
  excluded from automatic membership at the user's request. John Tron remains
  available individually/custom; Neon uses Cinematic silver-blue night, Alien
  uses Moonlit clouds. All six extra Tropospheric cloudy sets are represented.
  Existing profile IDs/assignments, saved selection, assets and lighting unchanged.
- Regression checks require exact new membership, deterministic four-state
  resolution, availability, custom-copy eligibility and exclusion of John Tron.
  Isolated context matrix covers the 0.45/0.7 light boundaries, clear/rain/snow
  and storm intensity 0.25/0.251; restores real atmosphere/skyline owners after
  the fixture even on assertion failure. This is not visual weather acceptance.
- GLua 180/0; fresh renderer 7/7, catalogue/context/materials 78/78 and browser
  9/9. First browser command was correctly rejected because the user had opened
  Options; its old result was not counted as fresh. After approved UI closure,
  rerun timestamp 1791244976 confirms 9/9 with the expanded catalogue.
- Human confirmed **the new variants and the ten-second aerial preview/return
  look right**. This supersedes the prior pending aerial-render review, not all
  cardinal/context/launcher/den/performance gates.
- Actual fresh-load persistence verified for the user's custom "Test" palette:
  independently captured selected `custom_1` / dusk `imported_mr53` before and
  after approved `changelevel zz_preview_817d995084d3`; six meshes/12 triangles
  render afterward, no reported failure. Custom store SHA256 remains
  `7D8367D2FD62FA50F16A36185E818ECDADDD2DA89985D0AA25F40D25D6E43251`.
  Captures `alpha310-h-custom-before`/`alpha310-h-custom-after` retain evidence;
  user's custom selection is left active, not replaced with an earlier default.
- Phase H remains active. Live weather changes and day/night/fog coherence,
  launcher/den/map-capture integration and representative performance remain.
  No production changes, regeneration, extra texture copies or Workshop upload.

**Live H integration and authored inspection direction (2026-10-06):**
- User restored Default for consistency; independent snapshot confirms
  `default`, no active entry, zero meshes/triangles, Options/browser closed.
  User authorized temporary Natural/weather/travel checks with restoration.
- Actual rain in preview logical22,0 (`zz_preview_817d995084d3`) correctly
  retains `natural_dusk` at scenery light0.582; weather reports rain/storm0.55.
  User confirmed rain/fog/horizon coherence and refreshed world-map Level view/
  camera return. Clear restoration retains the same dusk entry.
- User confirmed normal den entry/exit, first-person camera, dry interiors and
  Options. Independent return snapshot confirms Natural on the original city
  map. These are human flow confirmations, not instrumented snapshots inside
  the den. Launcher independently loaded `zn_preview_start`, character slot2
  Jim; user confirmed all Options work, except the requested preview redesign.
- Profiling gap fixed: `PostDraw2DSkyBox` now included in the existing hook
  profiler. GLua180/0. Actual warm Natural dusk sample:9.954s/198frames,
  19.89FPS, palette draw CPU0.04866ms/frame (396calls, max0.1461ms), prepare
  CPU0.00332ms/frame. Before/after camera and workload matched: origin
  (-358.57,244.1881,130.2658), forward(0.0937,0.9889,-0.1149), clear/no snow,
  sky detail2/props0.7/fires on;20models/139props/30fires. No comparable native
  draw sample yet; earlier53.25/59.64FPS samples omitted this draw hook and
  had different cameras. No performance improvement/regression or GPU-cost
  claim is established. Saved session `alpha310-h-natural-draw-profile.json`.
- **Paused at user's request for authored preview-area work.** User clarified
  the new area is **launcher-only**, not shared city-cell/den templates. Add a `point_camera`
  named **`Preview_skybox`**. User chose camera-only movement to the authored
  position/angles, never survivor teleportation. This supersedes the procedural
  upward sweep **in the launcher only**; city cells keep their existing sky
  and current camera-only preview. No new city-cell area is required.
  New launcher marker consumption/availability/error handling and authored
  live checks are not implemented yet. Do not generate maps before the authored
  source is ready/approved or infer that the old preview satisfies this direction.
- Temporary weather hold released and verified independently: automatic1,
  manual0, clear seasonal weather. Original deadline had expired during checks,
  so normal schedule rolled the next spell. No hold remains.
- Client was left at preview launcher when the user paused; do not assume the
  Default selection or original gameplay location has already been restored.
  Restore/verify Default and existing slot2 Jim to logical22,0 (raw22,12),
  safe-zone none when the user is ready. Do not use refill/origin-reset helpers.
- **Options section persistence and launcher Tools (2026-10-06).** Options
  sections now default closed and remember each open/closed state through
  `zombiesim_options_section_<id>` cookies (`OnToggle`). Preview-launcher-only
  **TOOLS** is a launcher tab: the left column switches to Wardrobe, Item Atlas,
  Map Atlas, Sky browser and Content Status plus BACK. The two atlas views and
  Content Status render on the right side of the same launcher frame rather than
  in a separate hub window. Back/Escape always returns to the main menu and
  closes any open view. Wardrobe and the Sky browser keep their existing windows
  and sit below a horizontal rule, separate from the right-panel tools.
  Tools are read-only: no item grants, equipment changes or survivor teleports.
  Map Atlas images are staged PNGs, not live 3D renders. Static: GLua181/0,
  diff check clean. Live after fresh reload: Tools4/4 and browser/Options10/10;
  the user confirmed the tab layout and behaviour.
- **Game versioning and Content Status (2026-10-06).** New single-source
  `data_static/version.json` (Alpha 3.1.0, in development, Phase H) and shipped
  `changelog.json` (3.1.0 back to 1.0; pre-2.6 entries inferred from Git, with a
  data-only flag and no UI label; highlights ordered `+`, `?`, `-`). `ZM_Version` (`sh_version.lua`) loads both and reads the local Git
  commit. Content Status is now sectioned: banner, health, version/source,
  distribution, world, registry counts and a changelog with green `+`, red `-`
  and yellow `?` markers. Packaging ships both files in core, stamps the game
  version into the manifest/report and blocks release until the status is
  `released`. Static: GLua182/0, packaging51/51. Live: Tools4/4 with
  version/changelog/marker/history assertions; the user approved the layout,
  and the coloured markers await review. Follow-up art pass: changelog versions
  are underlined, highlights are grouped under ADDED/CHANGED/REMOVED subheadings
  and atlas cards widen to fill each row.
- **Clothing item swatches (2026-10-06).** Clothing items no longer show the
  generic box model. `ZM_ItemIcons:GetClothingIcon` (moved from the Wardrobe,
  which now shares it, with cached results) crops the real garment layer.
  `DrawClothing` draws a fabric swatch with shirt/pants and repeat badges plus a
  placement tag at 72px or larger. `DrawOverride` covers inventory, loot,
  crafting and trading; `Attach` refuses clothing; atlas cards/inspector draw it
  directly. Static: GLua182/0. Live after reload: Tools5/5, including per-style
  male/female swatch resolution. The user approved the swatches.
- **Options changelog button (2026-10-06).** `cl_changelog.lua` (`ZM_Changelog`)
  now owns the changelog renderer/fonts shared by Content Status. A VIEW
  CHANGELOG button sits below all Options sections: in game it opens a
  Changelog window (Options stays open, Escape closes only the window); the
  launcher Options page toggles a right-side panel instead, closed by
  BACK/Escape. Static: GLua183/0. Live after reload: Tools6/6 (window and
  launcher side panel paths), browser/Options10/10. Visual review is pending.

**Visual palette editor and additional supplied skies (2026-10-06):**
- User retained four states: Day, Overcast, Dusk and Night. The left side now
  has clickable preview slots; the right grid shows individual sky thumbnails
  plus native-map sky, never automatic palette cards during editing. Clicking
  a sky changes only the active draft slot. Save & use commits; Cancel/Escape
  discards the draft and restores the browsing search/filter.
- Edit selected is enabled for all built-in/custom automatic palettes. At the
  user's choice, built-ins create personal copies; existing custom palettes edit
  in place. Original built-in definitions and saved choices remain untouched by
  draft assignments. No state dropdowns remain in the editor.
- Earlier expanded browser/custom editor was explicitly user-approved. Latest
  expansion adds nine supplied sets (Prelude, Terrassee, World's End, Alien red,
  John Tron, Plain sky, Sky 1, Waporvave and MR 53). User confirmed the author
  instructed copying the supplied licence into each pack; configuration records
  this provenance rather than claiming independently verified authorship for
  those copied README packs. MR 53's former exclusion is superseded by that
  specific permission, not blanket licence clearing. UT assets remain removed.
- Current catalogue: 82 individual skies, twelve built-in automatic palettes,
  95 cards before custom profiles; 36 imported sets, 432 material files,
  391.48 MiB and 36 byte-preserved standalone licence files. The package builder
  retains the READMEs in common content at `data_static/sky_licences`, a location
  verified through bundled gmad; the trial `licenses/` location was rejected by
  gmad's whitelist and only this task's exact trial README files were removed.
- Static: GLua 180/0, asset checks 2383/2383, package fixtures 50/50 including
  README ownership and archive round-trip.   fresh actual-client renderer 7/7, browser/UI/inspection 9/9 and incremental
  catalogue/materials 76/76. UI tests cover visual assignment/cancellation,
  built-in copy creation, custom edit-in-place and isolated disk reload.
- Initial aerial starts ran too early after arrival; waited for user-confirmed
  unpause instead of retrying stale-heartbeat requests. Fresh checks exposed
  deferred parent-removal cleanup; browser now ends inspection synchronously
  before removal and restores cursor ownership to other visible UI. Both
  inspection lifecycle cases subsequently pass. A client screenshot also
  exposed a partially hidden Night slot; slots now resize to fit all four at
  ordinary window heights, retaining scrolling for small screens.
- Actual package audit: 7316 files / seven packages / 1505 report-only exclusions /
  387 existing publication blockers. No maps rebuilt, uploads, inventory changes
  or unowned-asset deletion.
- Final fresh editor suite remains 9/9 after responsive sizing. Human confirmed
  **all four slots are visible and the picker works/is clearer**. Final actual
  capture `alpha310-visual-palette-editor-final` has 83 individual/native cards,
  zero thumbnail errors/pending work, preserved saved choice and no custom profile
  creation during the probe. New skies' full six-face appearance and real
  ten-second aerial rendering still need human review. Do not treat this as
  Phase H acceptance.

**Sky browser and Options follow-up (2026-10-06; supersedes dropdown/preview-only controls below):**
- User chose automatic palettes **plus saved individual skies** and requested
  thumbnail cards instead of the dropdown. `cl_sky_browser.lua` now owns a
  secondary window over the shared launcher/radial Options surface: twelve
  responsive cards, selected state, apply-on-click/local persistence, Back/X/
  Escape paths and parent-removal cleanup through the existing UI registry.
  Nine individual entries include the reviewed mounted candidate; it remains
  excluded from automatic palettes. Fixed skies are labelled cosmetic overrides,
  with a context-mismatch warning; no BSP relighting or weather changes.
- Original thumbnails share the renderer's gradient curve; mounted/native-map
  thumbnails reference a mounted face, with an honest labelled placeholder
  when the map manages its sky without a usable face. No extra render targets,
  per-card scene renders, extracted assets or generated maps.
- Options now has nine collapsible headers, with weather/radiation/camera/
  advanced horizon/server fine-tuning initially collapsed. All bound controls,
  precision, presets and server-edit guards remain. Removed the clipboard tuning
  utility from normal Options, not its diagnostic API. Replaced the technical
  engine-audio readout with a friendly Audio notice directing players to
  Garry's Mod Options > Audio; no engine volume writes.
- Fixed sky bridge registrations accidentally nested in the clothing-pool
  command; all sky test/preview commands now exist on a clean load.
  `zombiesim_dev_ui options|sky` and VGUI-aware capture diagnostics support review.
- Static: **177 GLua files / 0 failures**, edited UI files have no editor errors.
  Fresh actual-client renderer **7/7**, browser/Options **5/5**. Tests verify all
  choice IDs, unchanged individual resolution across contexts, gradient endpoints,
  mounted seams/materials, all31 convar controls, audio ownership, responsive
  widths, card selection/saved convar/default reset, parent cleanup and restoration
  of the original cosmetic selection. Initial UI control-retention test used a
  nonexistent getter; corrected to the verified Derma child binding field, then
  reran successfully after a fresh preview reload.
- Human: user confirmed **looks good; selection and closing work**, including
  browser Back, grouped Options, selecting/reopening and restored camera/mouse
  control. This accepts the requested UI follow-up, **not all of Phase H**.
- Still pending: actual archived-choice survival across fresh map loads,
  automatic context/weather transitions, launcher/den/map-capture behaviour,
  dusk/night/storm/snow visual coherence and profiling. Keep F/G accepted and
  Workshop publication deferred; no new world-build or clothing gates.

**Phase H prototype and seam correction (2026-10-05):**
- User selected saved Default/Natural/Cinematic palettes that choose compatible
  contexts, with individual-sky development previews. `cl_sky_palettes.lua` is
  sent/included in the client realm; the existing shared Options panel now has
  a saved palette dropdown and Restore map sky button. Default remains unchanged.
- Eight original procedural day/dusk/night/overcast entries use a bounded
  single1536-triangle mesh, native fog at the horizon and palette-specific zenith.
  Context uses existing baked-light scenery level and weather; it changes no
  server weather, gameplay lighting, reflections or map recipes. Old meshes
  are destroyed on replacement. Only the selected backdrop is drawn.
- `PostDraw2DSkyBox` renders behind the existing3Dskybox with depth writes
  disabled, using the documented origin-centred camera pattern. References:
  [sky hook](https://wiki.facepunch.com/gmod/GM:PostDraw2DSkyBox),
  [mesh vertices](https://wiki.facepunch.com/gmod/Structures/MeshVertex).
  User reviewed Natural daylight and confirmed correct layering/appearance.
- VPK inventory confirmed complete mounted `sky_day03_06c` faces. A development-only
  mounted candidate references native textures in place through six bounded
  UnlitGeneric face meshes; no Valve assets extracted/copied or imported files
  staged. It remains outside automatic palette membership pending broader
  compatibility review.
- First mounted preview exposed reversed side correspondence/top rotation.
  In-memory DXT5 edge comparison established ft-right/lf-left, lf-right/bk-left,
  bk-right/rt-left, rt-right/ft-left and matching top-edge directions. Corrected
  mapping passed geometric-edge regression and user rotation review.
- User then supplied a screenshot clarifying a remaining **tiny seam**, not a
  rotation issue. Kept orientation unchanged; face UVs now sample edge texel
  centres at half-texel insets rather than wrapping boundaries. Fresh confirmed
  preview reload, live suite **5/5**, GLua **176 files / 0 failures**; the user
  explicitly confirmed **the seam is gone**. No shader/texture asset alteration.
- Commands: `zombiesim_dev_sky_palette <entry>|restore` (preview admin,
  temporary120-second local override), `zombiesim_dev_test_sky_palettes`
  (actual mesh/material/edge/sampling checks; result in DATA sky_palette_tests.json).
  Screenshot metadata now includes skyPalette active entry/meshes/triangles/draws
  and errors. Natural capture verified1536triangles/positive draws; mounted
  capture verified6meshes/12triangles/positive draws.
- Still unverified: automatic context changes, persisted Options/reopening/reset
  across fresh loads, launcher/den/map-capture behavior, dusk/night/storm/snow
  coherence and profile cost. Procedural membership/appearance beyond reviewed
  daytime and final mounted eligibility remain Phase H gates, not accepted F/G
  work to repeat. Workshop release remains separate/deferred.

**Supplied-asset assessment:**
- Inspected all **202 VTF faces** in `assets\skybox`: the six-face `mr_53` sunset, six-face `sky_night01` moon/cloud set, and 190 faces in the UT2004 conversion collection. Local inspection sheets/metadata are session artifacts, not release assets.
- `mr_53`: warm peach/orange horizon, pink/red clouds, cool violet-blue upper sky and dark mountain silhouettes. Good cinematic dusk candidate; the baked mountain horizon must not duplicate or contradict the cardinal terrain.
- `Sky_Night01`: near-black/blue-green clouds, silver moonlight and a dark lower hemisphere. Six named faces and source art are present. Its README permits use/modification in games/mods and requires permission for resale of textures/packs; preserve its licence and attribution rather than interpreting it as permission for every distribution method.
- UT candidates span realistic and stylized looks: blue daylight/mountains (`1`-`6`, `Barren`, `Osiris`), soft warm haze (`BR_Bahera`, `osirisMT`), grey winter/storm (`glacial1024`, `SNOW`, `ICEFLOW`), orange/gold dusk (`EF`, `Chasm`, `Pain`, `sierra1024`), violet/space night (`Anubis`, `Kalendra`, `MilkyWay`, `TOR...B`), green/apocalyptic cloud (`ges`), and very dark clouds (`SepSky`). These are candidates, not approved/ready-to-ship material names.
- Several collections contain fewer than six faces, noncanonical directional names, half-height side faces, tiny bottom placeholders or built-in terrain/structures. `gross`, `cube_bross`, `Cube_Shot` and parts of `halfsky` contain indoor/cave/industrial or architectural scenery; exclude these from the normal outdoor palette. `ty_greekSky` and `LH_SkyBox` bake water/coastlines; avoid conflicting with the west ocean and other world edges.
- UT README explains conversion but supplies no usage licence. No licence/author documentation was found with `mr_53`. Keep those as reference/private inspection inputs until rights/provenance are verified; user-supplied files are not automatically authorized for redistribution. Do not package or commit imported copyrighted texture copies without appropriate permission.

**Proposed palette structure:**
- **Development/publication separation reaffirmed (2026-10-05):** user
  confirmed continuing Phase H (not reopening accepted Phase G). Workshop
  release is a separate future task; do not block ordinary development on
  final IDs, publication or clean-download acceptance. Existing packaging,
  ownership, byte budgets, launcher readiness and pending-ID handling remain
  in place for that future task. Free distribution is not blanket third-party
  asset permission: retain provenance flags and exclude imports without
  verified permission; do not mark them cleared merely because release is free.
- **Source decision accepted (2026-10-05):** use mounted game skies plus
  original procedural palettes for the first selector. Keep supplied imports
  with unresolved permission excluded from staging and distribution. Mounted
  assets are referenced in place, never extracted/copied into the addon;
  diagnose any required game mount explicitly. This decision does not yet
  approve palette membership, control design or procedural visual results.
- **Default / atmosphere-matched:** preserve existing maps and behavior.
- **Natural:** clear blue, warm hazy day, grey overcast, restrained dusk and moonlit night.
- **Cinematic:** richer warm sunset, violet twilight and silver-blue night, with compatible daylight/overcast fallbacks.
- **Fantasy / space (optional):** nebulae, planets and stylized coloured clouds; opt-in, not the default world's art direction.
- Within a palette, select an available compatible sky by the cell's current atmosphere/light context; allow explicit single-sky preview during development. Missing/unlicensed/incomplete entries remain excluded, not silently advertised as working skies. Final labels, membership and single-sky-versus-palette controls need user agreement in this phase.

1. Verify provenance, full six-face availability, face orientation/seams, VTF dimensions/flags, lower hemisphere and material resolution for each proposed entry. Build an allowlisted original/licensed sky catalogue with source/credit/licence metadata; normalize through an asset pipeline, never hand-edit packaged/generated outputs.
2. Prototype **client-local cosmetic selection** behind a default-off/default-map option, not global server `sv_skyname` changes or extra map recipes. The documented `GM:PostDraw2DSkyBox` hook is a possible backdrop integration point; verify rendering order, depth, cubemap orientation and sky masks in GMod before promising the implementation. Keep native/default sky intact until a valid selection is ready; report missing materials explicitly.
   - Reference inspected: [GM:PostDraw2DSkyBox](https://wiki.facepunch.com/gmod/GM:PostDraw2DSkyBox). [GM:PreDrawSkyBox](https://wiki.facepunch.com/gmod/GM:PreDrawSkyBox) is specifically a 3D-skybox hook and is not evidence of a general 2D sky replacement API. No runtime sky setter API was verified in this investigation.
3. Keep runtime selection distinct from baked BSP sun/light_environment/lightmaps and reflections. A changed backdrop cannot relight a daytime BSP as night. Define compatible sky choices and fog/skyline/cloud presentation so mountains, silhouettes, combat activity, weather and snow stay coherent without changing authoritative weather or survival behavior.
4. Add validated persisted client Options controls shared by launcher and radial menu, including default/reset/preview. No server-controlled gameplay changes, unsupported convar tricks, or mandatory UT2004 ownership requirement.
5. Keep texture residency bounded; use a single selected six-face set, avoid per-frame material construction, and profile the actual sky rendering path. Stage only eligible chosen original/licensed materials to the root for local development; distribution is a separate gate.
6. Run focused static/catalogue checks, then review day/dusk/night, light/dark fog, weather, all cardinal horizons/corners, den entry/exit, launcher, map capture, and fresh-load/reset behavior in a running client. Confirm the selected sky is personal to that client and does not create new recipe/BSP variants.

**Exit:** The user accepts a licensed, coherent, optional sky-palette selector; default skies and baked gameplay lighting remain unchanged, client choices persist/reset correctly, and visual/performance checks pass. Imported reference sets with unresolved rights or incompatible/incomplete faces are not shipped.
