# Alpha 2.9.2 — Client Performance and Quality Presets

Status: **COMPLETE** (started and accepted 2026-10-02). Promoted from the "Post-Alpha 2.9" section of the archived [Alpha 2.9 tracker](docs/todo-alpha-2.9.md), which keeps the full research notes.

User report (2026-10-02): frame rate was a solid 60 and dips to 58-59 during Phase E weather. This milestone reduces the cost of those systems and, where possible, makes them configurable (low/medium/high) for weaker or stronger hardware. Lua-only: no world generation or map builds are in scope.

## Baseline

Measured with `zombiesim_dev_profile_hooks 15` (`gamemode/cl_dev_profiler.lua`, writes `data/zombiesim/hook_profile.json`), snow at full cover, `zz_preview_8e9b52d6d08e` cell 13,1, 15 s.

- 881 frames at 58.7 fps average.
- Frame time: p50 16.59 ms, p95 20.19 ms, max 52.61 ms.
- All wrapped Lua hooks: 2.609 ms/frame.
- About 254 KB of Lua allocation per frame.

The averages stay near the 60 fps vsync cap, so the dips are spikes and garbage-collection pauses rather than steady cost.

| Hook | Avg ms/frame | Max ms |
| --- | --- | --- |
| Think `ZM.Atmosphere.SnowCover` | 1.308 | 44.47 |
| HUDPaint `ZM.PlayerCompass` | 0.309 | — |
| HUDPaint `PlayerWeaponHud` | 0.132 | 14.75 |
| RenderScreenspaceEffects `ColourCorrection` | 0.124 | 13.06 |
| HUDPaint `PlayerMinimap` | 0.113 | — |
| HUDPaint `CustomCrosshair` | 0.095 | — |
| PreDrawTranslucentRenderables snow draw | 0.086 | — |
| Think `WeaponEffects` | 0.074 | 19.25 |

## Ranked Plan

- [x] 1. **Cut snow-trail and stage re-bake garbage.** Implemented 2026-10-02 in `gamemode/cl_atmosphere.lua`, awaiting re-profile:
  - Each chunk keeps pooled vertex tables (one `Vector` and one `Color` per grid point) and a triangle list that is built once. A re-bake now rewrites these in place instead of allocating about 1,536 vertex tables and `Color` objects per chunk.
  - A coverage stage change re-bakes only the chunks whose patch range it actually changes.
  - The footprint refill only marks a point dirty when its depth crosses one of 12 steps, or when it clears.
  - `markSnowPointDirty` no longer allocates a table per call.
  - Fresh footprints go into an urgent queue ahead of background re-bakes.
  - Re-bakes stop after 1.5 ms of frame time, or after the existing per-frame count.
  - The snow mesh version is bumped to 8, so the cover re-samples once on load.
- [x] 2. **Per-chunk culling for the snow `IMesh:Draw`.** Implemented 2026-10-02, awaiting re-profile and visual check:
  - Each chunk stores a bounding sphere.
  - The draw skips chunks behind the camera or outside the view cone. The cone comes from `render.GetViewSetup()`, widened by 6°; orthographic views skip the cone test.
  - Chunks beyond the fog end are culled only when the world fog is fully opaque.
  - `zombiesim_atmosphere_status` diagnostics now report chunks drawn, culled and rebuilt, plus the fog cull distance.
- [x] 3. (Implemented 2026-10-02; see Validation.) Replace fixed per-frame counts with a shared `SysTime()`-budgeted work queue. Use coroutines only for non-hot, one-off orchestration (LuaJIT cannot JIT `yield`/`resume`).
- [x] 4. (Implemented 2026-10-02; see Validation.) Reuse trace tables via `output` in the shelter, footstep and puddle traces.
- [x] 5. (Implemented 2026-10-02; awaiting the user's visual check, see Validation.) Batch the puddle/ripple `mesh.Begin` calls and update the refract texture once per frame.
- [x] 6. (Implemented 2026-10-02; awaiting the user's visual check, see Validation.) Investigate the 13-19 ms spikes in `PlayerWeaponHud`, `ColourCorrection` and `WeaponEffects`. Cache HUD text and layout where the compass and minimap recompute every frame.
- [x] 7. (Implemented 2026-10-02; awaiting the user's check, see Validation.) Add archived client quality presets (low/medium/high plus individual overrides), with a settings-menu entry. They cover:
  - rain particle rate;
  - puddle count;
  - ripple count;
  - snow spacing and draw distance;
  - screen effects.
- [x] 8. (Evaluated 2026-10-02: keep translucency, see Validation.) Evaluate `$alphatest` versus translucency for the snow cover.

## Validation

**Items 1-2: ACCEPTED by the user (2026-10-02).** Footprints and cover visuals are confirmed correct, with no chunk popping while turning.

**Items 1-2, static (2026-10-02):** `.\bin\test_glua_syntax.ps1` 144/144.

**Items 1-2, live run 1 (2026-10-02, 16 s, `zz_preview_2bb2eb53aa79-cp`, snow still settling at cover 0.81):**

| Measure | Baseline | Run 1 |
| --- | --- | --- |
| Average fps | 58.7 | 59.9 |
| Frame time p50 / p95 | 16.59 / 20.19 ms | 16.61 / 20.09 ms |
| Frame time max | 52.61 ms | 49.76 ms |
| All Lua hooks | 2.609 ms/frame | 2.405 ms/frame |
| Lua allocation | about 254 KB/frame | 74 KB/frame (−71%) |
| Snow Think average | 1.308 ms | 0.998 ms |
| Snow Think max | 44.47 ms | 3.72 ms |
| `PlayerWeaponHud` max | 14.75 ms | 0.47 ms |
| `ColourCorrection` max | 13.06 ms | 0.73 ms |
| `WeaponEffects` max | 19.25 ms | not in top list |

The HUD and effect spikes vanished along with the garbage, which suggests they were GC pauses landing in those hooks. While the cover settles, every stage (one every 3.75 s) still re-bakes almost every chunk, so this run's Think average reflects build-up rather than the full-cover baseline condition. The snow draw max of 20 ms is one outlier: its average is 0.119 ms over 965 calls.

A bridge snapshot afterwards, at cover 1.0, showed:
- 121 chunks, of which 34 were drawn and 87 culled;
- 209 trodden points;
- no Lua errors reported.

A full-cover re-profile is still needed for a like-for-like comparison.

**Items 1-2, live run 2 (2026-10-02, 15 s, same map, full cover 1.0, walking):**

| Measure | Baseline | Run 2 |
| --- | --- | --- |
| Average fps | 58.7 | 60.0 |
| Frame time p50 / p95 / max | 16.59 / 20.19 / 52.61 ms | 16.62 / 19.53 / 35.98 ms |
| All Lua hooks | 2.609 ms/frame | 2.166 ms/frame |
| Lua allocation | about 254 KB/frame | 80 KB/frame (−69%) |
| Snow Think average / max | 1.308 / 44.47 ms | 0.545 / 3.67 ms |
| Snow draw average | 0.086 ms | 0.101 ms (81 of 121 chunks drawn in the snapshot) |

- The remaining snow Think cost is footprint re-bakes: about 0.29 ms per chunk, with 706 trodden points.
- The refill now runs once per depth step (every 12.5 s instead of every 3 s). This cuts trodden-chunk re-bakes roughly fourfold; it is static-checked only (144/144) and not yet profiled.
- New spikes remain for item 3/6 follow-up: `Foliage.AmbientDebris` max 21.98 ms (average 0.320) and `ColourCorrection` max 18.59 ms. These are likely the remaining 80 KB/frame of garbage being collected inside them.

**Item 6, allocation pass (2026-10-02).** Implemented and static-checked (144/144); awaiting the user's visual check. Changes:

| File | Change |
| --- | --- |
| `cl_hud.lua` | Weapon entries cached per weapon (invalidated on snapshot or `instanceId` change), with reused lists and hoisted colours |
| `cl_hud.lua` | Compass and minimap entity lists refreshed every 0.5 s |
| `cl_hud.lua` | Landmark targets cached per cell |
| `cl_hud.lua` | `ZM_GetHudReservedRects` cached per frame |
| `cl_atmosphere.lua` | `GetFogSettings` memoised per frame; colour-correction tables reused |
| `cl_loot_popup.lua` | Marker spots refreshed every 0.25 s; colours hoisted |
| `cl_weapon_effects.lua` | Smoke draw allocates no per-particle colours or vectors |
| `cl_thirdpersoncamera.lua` | CalcView trace and hull tables reused |
| `cl_foliage.lua` | Debris kicker gathering, wall/ground traces, wind and the simulation use scalars, in-place vectors and double-buffered positions |

Live bridge profile, `zz_preview_c8d614da272e-v2`, clear weather, snow 0:

| Measure | Before | After first pass | After debris pass |
| --- | --- | --- | --- |
| Lua allocation | 85.7 KB/frame | 50.2 KB/frame | 46.6 KB/frame |
| `Foliage.AmbientDebris` | 33.85 KB | 16.41 KB | 6.28 KB |
| `PlayerCompass` | 5.25 KB | 1.69 KB | 1.75 KB |
| `PlayerWeaponHud` | 4.47 KB (max 30 ms) | 1.96 KB (max 0.29 ms) | 1.90 KB (max 0.55 ms) |
| `ColourCorrection` | 4.49 KB | 3.74 KB | 5.02 KB |
| `CustomThirdPersonView` | 3.37 KB | 1.47 KB | 1.44 KB |
| All Lua hooks | — | 1.16 ms/frame | 1.12 ms/frame |

- The fps in the last two runs fell to 39 and then 20 while Lua hook time stayed at 1.1 ms/frame. This suggests a client throttled while unfocused, not Lua cost; re-check with the game window focused.
- `CustomCrosshair` (about 4.7 KB) is the shared `ZM_LowTargetAim` entity scan in `sh_player.lua`. It was left unchanged so that server aim semantics are not altered.

**Items 3-5 (2026-10-02).** Static: `.\bin\test_glua_syntax.ps1` 144/144.

- **Item 3:** `getAtmosphereWorkDeadline()` in `cl_atmosphere.lua` is a shared per-frame deadline: 1.5 ms in play and 50 ms during the snow preload. It now bounds snow sampling, chunk meshing, dirty-chunk re-bakes and the puddle-site scan, whose burst is now drained as `puddleSiteDebt`. Each user always makes at least one unit of progress, and the old per-frame counts remain caps. Coroutines were not needed.
- **Item 4:** The shelter, puddle-ground and puddle-overhead traces reuse their request tables and vectors. Shelter and overhead also reuse `output` tables; the ground trace keeps its result because `findPuddleLowPoint` compares results. The footstep trace path was already table-free after items 1-2.
- **Item 5:** The puddles were already one `mesh.Begin` per pass, and nothing calls `UpdateRefractTexture`, so this pass targets allocation and vertex cost instead:
  - pooled shapes, candidates, ring vectors, drop records and colours;
  - scalar maths and a hoisted comparator;
  - the rim is drawn as `MATERIAL_QUADS` (4 instead of 6 vertices per segment, same triangle split);
  - lobes beyond 900 units use every second segment.

  The profiler JSON now reports `puddleRenderLobes` and `puddleDropRings`.

Live bridge profiles, `zz_preview_c8d614da272e-v2`:

| Measure | Before | After |
| --- | --- | --- |
| Rain: wet-surface allocation | 45.5 KB/frame | 0.4 KB/frame |
| Rain: total Lua allocation | 108 KB/frame | about 50-60 KB/frame |
| Rain: puddle mesh at the 48-lobe cap (temporary timing, removed) | about 5 ms/frame | about 3.4 ms/frame |
| Snow building, high preset: fps | ? | 60.1 |
| Snow building, high preset: frame p50 / p95 / p99 / max | ? | 16.63 / 18.68 / 21.33 / 39.51 ms |
| Snow building, high preset: all Lua hooks / allocation | ? | 1.71 ms / 44.2 KB per frame |
| Snow building, high preset: snow Think average / max | ? | 0.42 / 3.00 ms |

The snow Think max sits above the 1.5 ms budget because one sampling or meshing unit can itself take about 1.5-2 ms; it is no longer a multi-unit burst. The remaining puddle cost scales with the visible-lobe count, and the low/medium presets lower it through puddle amount.

**Item 7 (2026-10-02).** Static: `.\bin\test_glua_syntax.ps1` 145/145.

- New `gamemode/cl_quality.lua` (sent with `AddCSLuaFile`, included after `cl_skin.lua`).
- New archived convars: `zombiesim_quality_preset`, `zombiesim_atmosphere_ripple_amount`, `zombiesim_snow_detail`, `zombiesim_snow_draw_distance` and `zombiesim_screen_effects`.
- Presets also drive the existing rain density, puddle amount and debris amount settings. Values are in the readme's "Client Graphics Quality Presets" section.
- Any individual change re-derives the preset statelessly (`custom` unless the values match a preset).
- `cl_atmosphere.lua` changes:
  - ripple amount scales drop slots and the ring cap;
  - snow detail scales the cover's target points, and a change re-samples the cover in the background;
  - snow draw distance combines with the fog cull;
  - turning screen effects off skips `DrawColorModify` and grain but keeps the frost edges.
- The Options panel (`cl_quick_menu.lua`) has a preset dropdown that follows manual changes, plus sliders for ripples, snow detail and snow distance, and a weather colour-grading checkbox.
- Live bridge check: `zombiesim_quality_preset low` applied the settings. `ColourCorrection` and debris left the top hooks, and Lua hook time fell from 1.71 to 1.29 ms/frame in snow; fps was vsync-capped at 60 both times.
- The user's previous values (rain 1.8, puddles 1.5, debris 2.0) and the new settings' high values were then restored through the bridge, along with clear weather.

**Item 7: ACCEPTED by the user (2026-10-02).** Low, medium and high presets and the sliders work. Fix during the check: medium showed `custom` because the rain, puddle and debris sliders rounded 0.75 to one decimal and wrote it back; they now use two decimals. The user's client is now on the low preset.

**Item 8 (2026-10-02): keep translucency.** The cover's vertex alpha carries three effects:
- the feathered edge (`edgeAlpha`);
- gradual build-up (`coverage`);
- footprint depth (`1 - 0.72 * trodden`).

The material `$alpha` also fades the whole cover across weather changes. `$alphatest` would turn all of these into hard cut-outs and could not fade. The measured draw is only 0.07-0.12 ms/frame of Lua, with per-chunk culling from item 2 already limiting fill, so no change was made.

**Still pending:**
- the user's visual check of puddles in rain (quad rims, far-puddle LOD at 900 units), ripples, debris and the HUD;
- a snow build-up check on a fresh map load, to confirm the preload still completes behind the loading screen;
- re-profile with `zombiesim_dev_profile_hooks 15` in snow at full cover in cell 13,1;
- walk through the snow to check that footprints still appear promptly and refill;
- confirm the cover has no missing chunks at screen edges or while turning the camera.

## Acceptance

**Accepted by the user on 2026-10-02.** The user checked puddles, ripples, debris, the HUD, the presets and the fresh-load snow preload in game, and all were correct.

Final profile, 15 s, `zz_preview_c8d614da272e-v2` (not baseline cell 13,1), snow at full cover 1.0, high preset. The fps cap appears to have been off for this run.

| Measure | Baseline | Final |
| --- | --- | --- |
| Average fps | 58.7 | 107.0 |
| Frame time p50 / p95 / p99 / max | 16.59 / 20.19 / ? / 52.61 ms | 9.56 / 12.55 / 15.25 / 38.53 ms |
| All Lua hooks | 2.609 ms/frame | 1.281 ms/frame |
| Lua allocation | about 254 KB/frame | 61 KB/frame |
| Snow Think average / max | 1.308 / 44.47 ms | 0.123 / 3.34 ms |

Afterwards, the client was restored to the low preset and clear weather.

- [x] Repeat `zombiesim_dev_profile_hooks 15` in the same cell and weather. Check that:
  - the snow Think average and spikes drop measurably;
  - Lua allocation per frame drops substantially;
  - in-game fps stays at the cap at the default preset.
- [x] The user confirms visual parity at the high preset.

## Rules

- Items may land in ranked order. Each item runs its focused static checks as it lands; static and live results are recorded separately.
- An item, and the milestone, is accepted only on the user's confirmation.
- Client visuals never change authoritative state. Quality settings are client-only archived ConVars and need no persistence migration.
