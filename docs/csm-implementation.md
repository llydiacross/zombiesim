# Alpha 3.2 - ZombieSim cascaded shadows implementation tracker

## Status and scope

**Planning only. No CSM renderer, map changes or dependencies are implemented
by this document.** The user requested a source investigation of
[Xenthio/RealCSM](https://github.com/Xenthio/RealCSM) and a future-agent plan for
ZombieSim's own implementation.

The authoritative milestone remains [Alpha 3.1.5](../todo-alpha.3.1.5.md):
Phases A/B are accepted and Phase C is in progress. On 2026-10-10 the user
designated this plan as **Alpha 3.2, the next milestone after Alpha 3.1.5**.
Complete Alpha 3.1.5 first. This scheduling decision does not insert CSM into
the current milestone, reopen accepted reviews, authorize production rebuilds
or authorize Workshop publication. Retain the Phase 0 feasibility and
lighting-policy decisions before implementation.

Preserve the approved launcher flight, skies/palettes, fog, weather,
post-processing, clothing/gore and current-cell edge fires. CSM must not become
a second day/night, weather, fog or camera owner.

### Executive recommendation

Build a **small, optional, client-side projected-light cascade service**, not
an embedded copy of the addon. Begin disabled, on an existing preview map,
with one light and a fixed map-matching sun direction. Prove the actual GMod
branch supports the required caster/receiver combinations before investing in
three cascades, dynamic masks or map relighting.

There are two independent feasibility gates:

1. Orthographic projected shadows must work on the geometry ZombieSim uses.
   The GMod wiki explicitly warns about failures on non-static props and most
   map brushes. Upstream's use of the API is not proof it works on our branch.
2. Projected lights add light; they do not, by themselves, subtract baked
   sunlight or its baked shadows. A visually acceptable overlay and a genuine
   replacement of baked direct sunlight are different projects. Do not promise
   replacement-quality shadows until a reversible lighting experiment proves it.

If either gate fails, stop with evidence and request a scope decision. Do not
quietly ship brighter lighting under the name "CSM", replace materials, remove
baked ambient light or require an undocumented engine hack.

## 1. Research baseline and evidence rules

Upstream was inspected at commit
[`81cf47b8f90016f22b59b6aa9faae0134492040c`](https://github.com/Xenthio/RealCSM/commit/81cf47b8f90016f22b59b6aa9faae0134492040c),
author date 2026-06-02. All upstream links below are pinned to that revision.
The source, rather than its historical TODO list, is the implementation
reference. In particular, the README still lists frustum subdivision as
unfinished, whereas the code contains an optional frustum-placement path.

Evidence labels used here:

- **Source:** directly observed code/defaults at the pinned revision.
- **Documented:** public API documentation or the explicitly identified SDK
  branch; not an actual ZombieSim engine test.
- **Candidate:** proposed improvement requiring a focused test or matched
  measurement. It is not an established performance win.
- **Gate:** unresolved behavior that blocks the dependent implementation.

No RealCSM runtime/GPU comparison was performed for this research. No new
ZombieSim live probe, asset staging or map compile was performed.

## 2. How RealCSM works

### 2.1 It is multiple projected lights, not a custom native CSM shader

The central implementation is
[`edit_csm/cl_init.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/edit_csm/cl_init.lua).
An admin-spawnable server editor entity supplies networked settings; each
client creates its own `ProjectedTexture` objects. These are engine flashlight
projectors with:

- Shadows enabled per light where configured.
- Orthographic extents instead of a perspective spotlight cone.
- A shared sun orientation and a position lifted toward the sun.
- Constant attenuation: quadratic/linear zero, constant one.
- Projection textures that partition light contribution between cascades.
- Per-light depth range, depth/slope bias, filter and brightness settings.

GMod owns shadow-map allocation, caster rendering, filtering and application to
receivers. GLua arranges the lights and their projection masks. This is not a
new material shader, a Lua-rendered depth atlas, screen-space shadowing or
global illumination.

Crucially, the masks partition **projected illumination**, not simply a shadow
texture sampled by a single sun shader. Black regions prevent a projector
adding light; they do not darken an already sunlit lightmap.

### 2.2 Startup, realms and network plumbing

| Source | Responsibility |
| --- | --- |
| [Shared autorun](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/autorun/realcsm_shared.lua) | Sends modules, registers network names, derives a full-load event from the first non-forced `SetupMove` after joining. |
| [Server autorun](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/autorun/realcsm_server.lua) | Optional editor auto-spawn after full load/cleanup, prop wakeups, join-time depth-resolution cap, optional sun broadcasts and StormFox2 integration. |
| [Client autorun](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/autorun/realcsm_client.lua) | Receives lighting/sky-camera messages, optional NikNaks loading, first-run/setup/changelog UI and Sandbox tool menus. |
| [Editor shared definition](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/edit_csm/shared.lua) | Editable/networked sun color, intensity, sizes, time/orientation, height, near/far depth, static-light and RTT controls. |
| [Editor server implementation](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/edit_csm/init.lua) | Removes competing editor entities, initializes defaults, broadcasts sky-camera position, toggles `light_environment`, supports duplication and optional legacy player-shadow entity. |
| [Base editor](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/base_edit_csm.lua) | Editor/entity framework; not the shadow renderer. |

The server sky-camera message contains a position, not a complete per-view
transform/scale contract. It is broadcast during editor initialization;
future integration must explicitly support clients joining after initialization.
The optional sun-broadcast helper likewise is not a durable world-state store.

Do not import Sandbox auto-spawning, map cleanup requests, donation/setup
popups or StormFox setting changes into ZombieSim.

### 2.3 Light allocation and settings

[`convars.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/convars.lua)
defines the client/server controls. Important source defaults:

| Control | Source behavior/default |
| --- | --- |
| Enabled/update | Both 1; this does not itself spawn the editor on every server. |
| Cascade count | 3. Count 1 creates index 1 only; count 2 omits index 1 and uses indices 2/3. The table can be sparse. |
| Half-extents | Near 128, mid 1024, far 8192, optional further 65536, multiplied by size scale. Full box width is twice the half-extent. |
| Further cascade | Off by default; created separately by a settings transition. |
| Projection textures | Near uses `mask_center`; outer cascades normally `mask_ring`; optional terminal `mask_end` provides harsh cutoff. |
| Texel snapping | On by default. |
| Shadow skipping | Near/mid/far intervals all 0: disabled by default. |
| Shadow filter/bias | Filter 0.08, depth bias 0.000035, slope bias 2, distance bias 0. |
| Frustum placement / runtime masks | Both off by default. |
| Automatic depth range / skybox lamp / sun occlusion | All off by default. |
| Spread / first-person proxy | Both off by default; configured spread sample count is 7. |
| Depth-format experiment | 16 by default; optional attempted D24 upgrade. |

Do not infer semantics from names alone. The main loop treats
`csm_farshadows=1` as "super performance": it requests far shadows **off** on
a value transition. Creation initially enables that projector's shadows, and
the cached comparison state can prevent the default value being applied until
it changes. Treat actual light state, not the checkbox name, as evidence.
The old `perfmode`/`singlecascade` names remain in settings/UI, while allocation
is driven by `csm_cascade_count`; do not assume an alias is fully wired.

### 2.4 Sun direction and brightness

The update path resolves sun direction from server-supplied information,
`util.GetSunInfo`, optional BSP metadata through NikNaks, a `shadow_control`
fallback or manual time/orientation/altitude. It rotates an offset toward the
sun and aims the lights in the opposite direction.

[`util.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/util.lua)
contains time-of-day color/intensity/sky/fog interpolation.
[`niknaks_suninfo.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/niknaks_suninfo.lua)
reads `light_environment` from the BSP entity lump, including pitch,
LDR/HDR light values and ambient values, caching the result.

The main loop uses stored raw intensity divided by 128 and an additional
0.125 factor for LDR. Optional StormFox appearance multiplies intensity/color.
The BSP reader's comments still discuss an older divisor of 400; its LDR
parser linearizes RGB, while its explicit HDR override path constructs RGB
differently. **These are upstream implementation choices, not a proven
universal conversion for ZombieSim.** Calibrate HDR/LDR paths against our
compiled maps and actual projected-light response before choosing a conversion.

`env_sun` describes the visible sun; it is not automatically authoritative for
the sunlight baked by `light_environment`. A saved sky image or automatic
palette slot does not change a BSP's baked lighting.

### 2.5 Default placement and texel snapping

The normal path follows `GetViewEntity():GetPos()`, offsets the lights toward
the sun, and assigns concentric orthographic boxes.

For half-extent `H` and depth resolution `R`, the shadow-texel world spacing is:

```text
texelSpacing = 2 * H / R
lightX = dot(position, sunRight)
lightY = dot(position, sunUp)
snappedX = round(lightX / texelSpacing) * texelSpacing
snappedY = round(lightY / texelSpacing) * texelSpacing
```

The default path uses a shared coarsest active cascade grid, optionally
multiplied by `csm_skip_snapmult`, to keep masks aligned. This helps stability
but sacrifices near-light placement precision. At 1024 depth resolution,
half-extent 8192 gives a 16-unit grid; further 65536 gives a 128-unit grid.
Do not assume all-cascade coarse snapping is the best quality tradeoff.

### 2.6 Optional view-frustum placement

[`frustumplacement.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/frustumplacement.lua)
implements:

1. Split distances blending logarithmic and linear terms:
   `split(i) = lambda * n * (f/n)^(i/N) + (1-lambda) * (n+(f-n)*i/N)`.
2. Eight camera-frustum corners per depth slab.
3. Projection of those corners onto the sun-right/up axes.
4. A light-space AABB, rounded up to a power-of-two square half-extent.
5. Optional quantized light roll and forward slack bias.
6. Position snapping against depth-texel and mask-pixel spacing.
7. Assignment of projector position, angle and orthographic extents.
8. Optional dynamic mask repaint.

The main loop activates this only with runtime masks on, more than one
cascade and spread off. Its current call uses near 7, far capped at 4000 and
lambda 1.0, rather than the helper's default lambda 0.8. It samples entity eye
position/angles and player FOV, not necessarily the final `CalcView` output.

**Limit:** fitting to camera-depth slabs does not install a shader that chooses
a cascade by receiver camera depth. Actual contribution still comes from
projected 2D masks and light depth volumes. Test coverage on layered geometry,
not just the eight corner calculations.

The corner routine treats its FOV as vertical; the occlusion module's frustum
routine treats its FOV as horizontal. Both consume player FOV. This source
inconsistency needs a projection-convention test, not a guessed aspect-ratio
fix. Verify actual view bounds at 4:3, 16:9 and ultrawide.

### 2.7 Runtime masks and blending

[`cascademasks.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/cascademasks.lua)
allocates 1024-square RGBA targets named with editor entity index/cascade.
A shared soft template draws smoothstep edge rings; default edge fraction is
0.10 and default ring count 64. Outer masks paint their own coverage, then
black-tint the preceding mask's texture into the overlapping rectangle using
alpha blending. The outermost mask has no outer fade.

`SuggestGrid` derives spacing from the outermost half-extent divided across
1024 mask pixels. `Refresh` repaints/binds each mask whenever called; only the
soft template has a settings-keyed rebuild cache.

Important follow-up tests:

- RGB illumination and RT alpha are not interchangeable. Verify the resulting
  sampled light weights on the GPU; do not infer correctness solely from
  comments calling alpha "coverage".
- Clamping an overlapping UV destination rectangle while drawing the entire
  inner texture can rescale, rather than crop, partially overlapping masks.
- Square `half` metadata drives masks even when asymmetric `hx/hy` projection
  is requested. That combination needs explicit compatible metadata or rejection.
- Static-mask refresh derives centers from the unsnapped base position, while
  projector placement can be snapped/pinned. Masks must use the committed
  projector transform, not an independently recomputed desired position.
- Three/four cascades, disjoint/partial overlap and nested holes all require
  sample-weight checks. A two-cascade screenshot is insufficient.

### 2.8 Filtering, depth range and update skipping

The loop sets per-light depth/slope bias, optional cascade-distance filter
scaling, near/far Z, constant attenuation and calls `Update`.

[`depthrange.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/depthrange.lua)
uses one brush-only downward trace to estimate height above ground, then
derives depth variation across the orthographic footprint. It clamps a
near-horizontal sun denominator, adds safety slack and caches for two seconds.
This is an estimate, not complete caster bounds: towers, overhangs, off-camera
casters and large camera moves can invalidate it. The caller's sun-change
invalidation occurs after requesting the cached range.

Where `SetSkipShadowUpdates` exists, upstream uses elapsed time, position and
sun-angle thresholds. When skipping in the default placement path, it pins the
light to its last shadow-rendered position to avoid reprojecting old depth from
a new transform. That is a useful invariant.

However, frustum placement has already assigned its transforms before this
skip logic, and the loop skips its later `SetPos` when frustum placement is
active. The default-path pin therefore is not a complete frustum-path solution.
Dynamic casters can also move without camera/sun motion: an elapsed deadline
still matters. Any future cache must keep **position, angles, extents, depth
range, masks and rendered shadow generation** consistent.

### 2.9 Optional softness through multiple lights

[`spread.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/spread.lua)
produces angular offsets using hardcoded disc packing, a Vogel/golden-angle
distribution or the legacy layered algorithm. The coordinator creates extra
near-region lights at indices 5+, rotates samples around the sun direction,
uses center masks and divides their brightness by the sample count.

This approximates a finite-area sun by summing multiple shadowed lights; it is
not a cheaper filter kernel. With three base lights, seven samples add five
lights: eight projectors before an optional further light or player flashlight.
Some settings can disable shadows on individual lights, but the allocation
still needs a hard total budget. Defer spread in ZombieSim.

### 2.10 Optional indoor culling

| Module | Actual role |
| --- | --- |
| [skyvis.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/skyvis.lua) | NikNaks-based, direction-independent PVS-of-PVS sky reachability; builds 64 leaves per Think. |
| [sunbake.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/sunbake.lua) | Samples sun traces per leaf, then PVS reachability to sunlit leaves; rebuilds on a bucketed sun-angle key. Additional confirmation-ray helpers exist, but the selected `leafSeesSunlit` path calls the PVS version. |
| [sunocclude.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/sunocclude.lua) | BSP point-to-leaf lookup, optional PVS/frustum filtering and three-frame hysteresis; parks lights with tiny extents and disabled shadows, then restores them. |

These are light-work culling heuristics, not GI or proof the player is outdoors.
An indoor camera can still see sunlit geometry through a window. A no-sky flag
on the current leaf does not prove all visible receivers are unlit.
Missing/unready metadata must keep lights active or explicitly disable the
optimization, not create blackouts. Fixed leaf counts do not bound frame time
when each leaf performs variable-cost PVS scans/traces.

### 2.11 Native 3D skybox lighting

[`skyboxlamp.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/skyboxlamp.lua)
currently borrows the far light (or another available light) in
`PreDrawSkyBox`, moves it into sky-camera space, disables its shadows, applies
a soft flashlight texture, then restores state in `PostDrawSkyBox`.
Optional muting parks other lights during the pass.

The file's introductory comments describe all-lamp reuse, but the actual code
borrows one lamp; additional updates depend on muting. A 1/16 scale constant
exists, but the active position/extent calculation uses traces around the
broadcast sky-camera position. Do not treat that constant as a complete
world-to-sky coordinate implementation.

Restoration averages the four orthographic extents into one square and resets
skip state to false. Thus it does not exactly round-trip asymmetric extents or
previous skip state. Borrowing shadow lights between render passes introduces
extra update work and ordering risks. This branch is unshadowed skyline
illumination, not skyline CSM.

[`skyboxfix.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/skyboxfix.lua)
changes fog-controller far Z and global `r_farz` to 80000, restoring hardcoded
-1 values. Do not adopt this override: preserve ZombieSim's existing fog and
view-distance ownership.

### 2.12 Native shadows and first-person proxies

[`rtt.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/realcsm/rtt.lua)
wraps the Entity metatable's `DrawShadow`, iterates entities, changes
`r_shadows_gamecontrol` and handles newly created entities. An experimental
translucent path installs `RenderOverride` and changes render modes.

Do not port that global wrapper. Its patched closure is guarded against
reinstallation, but a re-include creates new module-local state while retaining
the old wrapper closure. Ownership, reload and preservation of other render
overrides require a deliberate solution. Native blob-shadow policy must remain
separate from the proof that projected shadows work.

Optional first-person shadows use:

- [csm_pseudoplayer.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/csm_pseudoplayer.lua):
  client controller and transparent, bonemerged body model.
- [csm_pseudoweapon.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/csm_pseudoweapon.lua):
  world-weapon proxy following weapon/model/parent changes.
- [csm_pseudoplayer_old.lua](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/entities/csm_pseudoplayer_old.lua):
  separately enabled legacy networked controller and animation copying.

The active client proxy is hidden for death, observation, alternate view entity
or when the local player is already drawn. It changes `r_flashlightnear`,
restoring a hardcoded value. Weapon compatibility uses broad `pcall` paths.
These are not appropriate defaults for ZombieSim's camera, wardrobe and gore
systems. Defer first-person proxies until ordinary player/walker shadows pass;
do not introduce duplicate clothing composites to obtain a shadow.

### 2.13 Static lighting controls and upstream tests

The editor's non-legacy path sends client sun-on/off requests to the server,
which fires inputs on `light_environment`. That is shared map state, not a
per-client preference. The legacy path changes `r_lightstyle`,
`r_ambientlightingonly`, radiosity and reloads lightmaps. Cleanup restores some
original values, others to constants, and some restoration is conditional on
auto-spawn settings.

[`lua/tests/csgotest.lua`](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/lua/tests/csgotest.lua)
is an exploratory lightmap-alpha readback. It is not a comprehensive cascade,
cleanup, multi-client or rendering regression suite.

## 3. Engine contracts and unresolved questions

| Contract | Evidence and implementation consequence |
| --- | --- |
| Orthographic API | [SetOrthographic](https://wiki.facepunch.com/gmod/ProjectedTexture:SetOrthographic) takes `(enabled, left, top, right, bottom)`. Its raw page warns: shadows do not work for non-static props and most map brushes. **Gate:** test our installed branch and exact caster/receiver classes; do not dismiss or generalize the warning. |
| Shadow pool | [SetEnableShadows](https://wiki.facepunch.com/gmod/ProjectedTexture:SetEnableShadows) documents eight shadow-enabled projectors total, including player flashlights and map projected lights. `-numshadowtextures` can raise it, with performance cost. Do not require a launch-option change for baseline support. |
| Update timing | [Update](https://wiki.facepunch.com/gmod/ProjectedTexture:Update) applies setters; the wiki recommends `PreDrawOpaqueRenderables`. Think-time state calculation alone does not prove the light is ready for the intended render pass. Guard depth/skybox/secondary passes and verify ordering in-engine. |
| Shadow skip | [SetSkipShadowUpdates](https://wiki.facepunch.com/gmod/ProjectedTexture:SetSkipShadowUpdates) is marked recently added in 2026.04.10 and possibly Dev Branch only; cached shadows can glitch. Capability-check the method; unsupported clients must use the non-skipping path explicitly. |
| Render-target identity | [GetRenderTargetEx](https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx) gets or creates by name; names discard extensions, sizes are power-of-two. It does not document upgrading an already allocated internal shadow texture's format. Do not claim the upstream D24 attempt worked merely because `pcall` succeeded. |
| Internal target hack | Upstream attempts `_rt_shadowdepthtexture_0..7` with branch-specific numeric formats and says restart is required to undo. **Excluded** from our baseline: private names, unknown allocation timing/format behavior and no reliable rollback. |
| Lightmap reload | [RedownloadAllLightmaps](https://wiki.facepunch.com/gmod/render.RedownloadAllLightmaps) has costly static-prop update options. It is not a relighting compiler or a selective baked-shadow remover; never call per frame. |
| Actual view | [GetViewSetup](https://wiki.facepunch.com/gmod/render.GetViewSetup) distinguishes current and player view. [ViewData](https://wiki.facepunch.com/gmod/Structures/ViewData) describes origin, angles, FOV, aspect, clipping and orthographic projection. Derive one explicit view contract instead of trusting player FOV/feet for every camera. |
| Runtime sunlight | [VDC light_environment](https://developer.valvesoftware.com/wiki/Light_environment) was blocked by Anubis during research; no claim here relies on accessing that page. SDK evidence below describes a related branch, not definitive GMod behavior. |

Public SDK fallback:
[`src/game/server/lights.cpp`](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/game/server/lights.cpp)
at `b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474` implements
`light_environment` as a `CLight` subclass. Its runtime `_light` key is ignored,
untargeted lights are removed at spawn, and on/off operates through engine
lightstyles. This explains why finding/toggling an entity is not equivalent to
recomputing VRAD lighting. It does **not** establish how GMod's compiler assigns
the direct/ambient contributions of our named light, or whether its inputs can
selectively disable baked direct sunlight. Those remain isolated BSP/live gates.

Future agents should inspect the matching public VRAD implementation and
compiled BSP lightstyle data if the on/off experiment is inconclusive. Do not
install an SDK, copy Valve content or substitute SDK behavior for GMod evidence.

## 4. Improvements worth carrying into our design

| Priority | Source finding / candidate | ZombieSim action and required proof |
| --- | --- | --- |
| P0 | Client quality toggles can control shared map sunlight. | Client CSM must not send sun-toggle, prop-wakeup or cleanup requests. Any future baked-light policy is server/map-authoritative and separately approved; test two clients with different local settings. |
| P0 | Projection and baked-light feasibility are unresolved. | Single-light caster/receiver and baked-sun experiments before feature expansion. Keep off as a real native path, not "zero brightness" lights left allocated. |
| P0 | Many settings branches rebuild sparse light tables independently. | One desired configuration, one bounded allocation/reconciliation point; contiguous internal cascade records. Test rapid toggles, count changes, allocation failure and map cleanup. |
| P0 | Camera/entity and secondary-render contexts differ. | Explicit final-view input and render-pass context; test shoulder camera, level view, launcher flight and nested capture/return. No hook-order dependency between camera owners. |
| P0 | Masks, placement and cached shadow transforms can diverge. | Compute desired state, commit a coherent generation, derive masks from committed state. Freeze all dependent transforms when skipping. Test moving casters as well as camera/sun motion. |
| P1 | Shared coarse snapping loses near precision. | Candidate stable per-cascade grids with correct overlap mapping; compare shimmer, coverage and snap jumps. More frequent near updates are not automatically a performance win. |
| P1 | Runtime masks repaint every active call. | Cache by count, committed extents, relative light-space offsets and edge settings; dirty repaint only. A rigid common translation should not repaint unchanged relative masks. Count redraws in diagnostics. |
| P1 | Entity-index RT/material names can expand the cache. | Fixed versioned slots with bounded permitted sizes. Reuse targets; never create names from frames, maps, time or changing quality values. Do not claim dropping Lua references frees engine texture storage. |
| P1 | Depth estimation uses one floor trace and shared cache. | Conservative per-cascade caster/receiver depth bounds with map/view/sun/config invalidation and guard bands; test bridge decks, towers, tunnels, low sun and teleport. Optimization may reduce precision artifacts but must not clip casters. |
| P1 | Indoor culling can underestimate visible sunlight. | Initially omit it. Later use conservative view-aware visibility, active while data is absent/building, immediate activation and time-based deactivation hysteresis. Compare window/door transitions at different FPS. |
| P1 | Leaf-bake chunks have variable cost. | If adopted, use measured `SysTime` budgets, cancellation tokens and bounded work/storage. Publish through existing loading/diagnostic owners; never block deployment on optional optimization. |
| P1 | HDR/LDR conversion comments and paths differ. | One tested conversion contract tied to effective compiled lighting metadata, not magic divisors copied from comments. Match exposure/color on representative maps. |
| P1 | Cleanup resets global settings and asymmetric lamp state incompletely. | Avoid global changes; where approved, snapshot exact values and restore only still-owned writes. Round-trip all four extents, texture, shadow/skip state and depth settings. |
| P2 | Spread spends multiple shadow-map slots. | Deferred experiment only after ordinary cascades meet resource/performance budgets. No default seven-sample mode. |
| P2 | Skybox-light reuse adds pass mutations and no skybox shadows. | Keep native skyline lighting unchanged first. Evaluate separate unshadowed lighting only if requested; do not promise shadows on custom skyline meshes. |
| P2 | First-person proxies conflict with clothing/camera ownership. | Defer. Test native body/weapon/corpse/limb shadows first; use existing approved model/material identities, no duplicate catalogue pool. |

These are engineering opportunities, not a formal exploit audit or measured
claims that ZombieSim will run faster than RealCSM.

## 5. ZombieSim integration contract

### 5.1 Existing owners that must remain authoritative

| Existing surface | Integration boundary |
| --- | --- |
| [Client includes](../gamemode/cl_init.lua) / [server initialization](../gamemode/init.lua) | Explicitly send/include the service. Register callbacks only after dependencies exist; create no lamps during a module's include merely because a timer happens to fire. |
| [Third-person camera](../gamemode/cl_thirdpersoncamera.lua) | `CalcView` owns final gameplay pose. CSM consumes pose, not a new camera hook that overrides it. |
| [Sky inspection](../gamemode/cl_sky_inspection.lua) | Launcher flight replaces the main `RenderScene`; other inspection views use the skyline wrapper. Feed the actual inspection view, not the survivor's position. |
| [Skyline renderer](../gamemode/cl_skybox.lua) | `RenderClientView` already scopes skyline view basis around secondary `RenderView`. Custom skyline drawing occurs in the 3D-skybox pass and uses engine-light suppression/model-light cubes. Preserve this behavior. |
| [World map](../gamemode/cl_world_map.lua) | Orthographic level capture calls `RenderView` directly and temporarily hides players/atmosphere. Capture needs its own explicit CSM policy; `RenderScene` alone cannot cover it. |
| [Atmosphere facade](../gamemode/cl_atmosphere.lua) / [modules](../gamemode/atmosphere) | Weather, fog, screen effects, puddles, snow and capture suppression remain owned here. CSM reads approved state, never overrides fog controllers or post-processing. |
| [Sky palettes](../gamemode/cl_sky_palettes.lua) | Saved skies are presentation choices. Selecting night/dusk does not authorize runtime sun simulation or BSP relighting. |
| [Quality presets](../gamemode/cl_quality.lua) / [Options](../gamemode/cl_quick_menu.lua) | Add a scoped shadow preference only after feasibility. Preserve current preset values and UI state; no forced changes to the user's global flashlight settings. |
| [VMF generation](../bin/build_cell_vmfs.ps1) / [settings](../generator-settings.json) | Source-first effective lighting metadata if needed; preview-only approved experiments, no hand-edited generated files. |
| [World service](../gamemode/utils/world.lua) | Use the shared read-only world-data owner and verify its current API before wiring metadata. Use `ZM_World` for profile/map resolution rather than reconstructing filenames or coordinates. |
| [Offline harness](../tests/glua/harness.py) | Pure calculations, strict fixtures, lifecycle and call-order regressions. Not GPU/engine emulation. |

**Current source warning:** the configured base
[template_border_s.vmf](../celltemplates/template_border_s.vmf) contains named
`LIGHT_ENVIRONMENT`, angles `0 0 0`, pitch `-75`, `_lightHDR "0 18 255 1"` and
`_ambientHDR "-1 -1 -1 1"`. The generator's `Set-VmfLightingProfile` currently
sets skyname, `_ambient` and `_light`, not these HDR fields or direction.
Do not assume the four JSON LDR profiles fully describe effective HDR sunlight.
Resolve the selected authored source, compiler mode and actual BSP before
exporting CSM metadata. Do not "fix" existing approved lighting in this task.
Launcher/safe-room templates need independent metadata or an explicit off path.

### 5.2 Proposed service boundaries, not a new framework

Use a small `ZM_CSM` public owner and initially three internal files:

- `gamemode/cl_csm.lua`: facade, configuration, capability state, lifecycle,
  bounded projector ownership and diagnostics.
- `gamemode/csm/cl_layout.lua`: pure light-space/split/depth/coverage
  calculations; no hooks or engine allocations.
- `gamemode/csm/cl_projectors.lua`: coherent transform application, mask
  resources and render-pass scheduling.

Add more files only when an accepted optional branch justifies them. Do not
recreate the entire addon module/entity/menu structure. Exact names are
proposals, not existing files or implemented APIs.

Expose narrow operations such as enable/reconcile, begin/end view scope,
reset/cleanup and a read-only diagnostic snapshot. Keep mutable state on the
service, never in global lamp tables or an Entity metatable patch.

State should distinguish:

```text
off
waiting_for_map_metadata
unsupported (reason)
ready
suspended_for_secondary_view
failed (reported reason; native rendering retained)
```

Use one generation token for map/config changes and asynchronous work. Reject
stale completions after disable, reload or map change. Allocate a validated
bounded lamp set, clean partial allocations on failure, and publish only a
complete usable generation. Errors must be visible in diagnostics and logged
once per changed failure, not silently represented as success.

### 5.3 Lighting metadata

Prefer our own generated/static map metadata over a required NikNaks dependency.
Reuse the existing world-data export/compatibility flow after inspecting its
current schema. Proposed payload:

- Schema revision, profile, resolved map and source/build compatibility key.
- Effective sunlight direction with an explicit Source pitch convention.
- Effective direct RGB/intensity, ambient RGB/intensity, HDR/LDR provenance.
- Explicit baked-direct-light policy and whether replacement is supported.
- Playable bounds/depth hints; sky-camera transform/scale only if a later
  skybox-light branch needs them.

Validate finite numbers, valid color/intensity ranges and matching map identity.
Metadata cannot merely repeat a profile name while ignoring authored HDR
overrides. Where metadata is unavailable, report why CSM is unavailable and
retain native lighting. Do not guess a sun from a thumbnail.

If a server message is needed, send a bounded authoritative snapshot on
join/map readiness and state changes, not per frame or per cascade. No client
network traffic is needed for camera motion, cascade matrices or local quality.
Do not change walker networking or add an always-transmitted editor entity.

### 5.4 Render-pass and camera policy

1. Identify final gameplay view origin/angles/projection from the real camera
   lifecycle. Consume it explicitly and prepare projectors for the intended
   main-world pass; do not rely on unordered hook callbacks returning values.
2. Default: CSM participates only in the main playable-world view.
3. Initial level-capture policy: suspend/remove its contribution during capture
   and restore for the next main view. Retain the existing native capture
   appearance. Confirm no stale shadow map is reprojected on return.
4. Initial city/den sky-inspection secondary views: suspend CSM unless their
   view has explicitly tested support. Preserve the existing sweep.
5. Launcher: initially off. Add support only after the authored island,
   main menu/credits, banking flight and return are independently reviewed.
6. Native 3D skybox: exclude ordinary cascades from that pass. Preserve matched
   skyline lighting, coast, custom meshes and edge-fire rendering. Engine
   projector behavior under `SuppressEngineLighting` and IMesh must be tested,
   not inferred from ordinary prop behavior.
7. Avoid an extra `RenderView` to generate shadows; engine projectors already
   own the depth work. Scope existing nested renders with guaranteed cleanup,
   explicit errors and no recursion/repeated-update loop.

### 5.5 Lighting and multiplayer policy

Keep all existing global render cvars, native shadows, server lightstyles,
weather and sky/fog values untouched during the initial prototype.

An additive prototype is an experiment, not automatically an acceptable final
look. If baked direct light cannot be selectively/reversibly controlled while
preserving ambient and native fallback, offer these decisions to the user:

- Retain native lighting and abandon replacement CSM.
- Accept a specifically reviewed optional projected-light overlay.
- Author separately approved preview lighting variants, with a defined native
  fallback and asset/package cost.

Do not assume that a map with ambient-only baking gives clients with CSM off
an acceptable equivalent image. That is a map-art decision and a multi-client
compatibility gate. Client A toggling local shadows must never change Client
B's lightmap state or shared server lighting.

### 5.6 Proposed resource and quality caps

These are conservative starting constraints, not measured final presets:

| Mode | Initial proposal |
| --- | --- |
| Off / unsupported | Zero owned projectors and no CSM update/mask work. |
| Prototype | One projector; existing engine depth resolution; no spread, skip, culling, proxies or skyline lighting. |
| Optional low shadow quality | One shadow-enabled cascade after coverage review. |
| Optional medium | Up to two shadow-enabled cascades. |
| Optional high | Up to three shadow-enabled cascades. |

Maximum baseline: **three CSM shadow-enabled projectors**, leaving nominal
room in the documented eight-light pool. This is a cap, not a guarantee of
availability when other lights/addons consume the pool. Report actual active
counts and test pool exhaustion. Do not change launch options automatically.

Keep CSM off in existing Low/Medium/High presets until the user approves both
the visual change and measured costs; adding a preference must not silently
turn it on for existing saved High users.

If dynamic masks are needed, permit at most three 1024-square cascade slots
plus one 1024-square template in the initial design: 16 MiB nominal RGBA
storage, excluding engine shadow maps/material overhead. This is a byte
calculation, not measured VRAM. Prefer original static/generated masks for
stable concentric layouts. Keep mask and depth resolutions distinct.

Do not write `r_flashlightdepthres` automatically. First test its current
value, supported range and resize behavior. If resolution changes are later
approved, explicitly explain their global effect on other projected lights
and whether a restart is required; capture/restore user values. Never register
internal shadow-target names or claim targets are freed by assigning nil.

## 6. Implementation phases and acceptance checklist

All phases below are **pending**, except this research/documentation handoff.
Within each phase: run focused static tests first, fix failures, then perform
the real engine/visual checks. Human acceptance and performance evidence are
separate from syntax or fixture success.

### Phase 0 - Approval, provenance and feasibility

- [x] User designates Alpha 3.2 as the next milestone after Alpha 3.1.5
      (2026-10-10); implementation waits for current-milestone completion.
- [ ] Confirm implementation scope and lighting-policy decisions at Alpha 3.2 start.
- [ ] Record installed GMod branch/build, architecture, GPU, HDR mode, relevant
      render cvars, projected-light addons and current map/profile.
- [ ] Agree initial overlay/replacement intent and performance budget before
      applying any lighting changes.
- [ ] Verify licence/asset/dependency decisions in section 8.
- [ ] On an existing approved preview map, create one removable shadowed
      orthographic projector with explicit diagnostics and native baseline.
- [ ] Test caster AND receiver combinations: BSP brush, static prop, dynamic
      prop, player, citizen walker, ragdoll/detached piece, custom IMesh,
      alpha-tested foliage and translucent surfaces. Record unsupported pairs.
- [ ] Test player flashlight coexistence and reaching the shadow-pool limit;
      no crashes, hidden failure or corruption after removing the probe.
- [ ] Test actual `light_environment` on/off only with separate permission,
      on an isolated preview, capturing direct/ambient/prop lighting separately.
      Restore exact state; no server lighting change from local settings.
- [ ] Decide go/no-go and fallback. A no-go is a valid result; do not bypass it.

Exit: demonstrated compatible geometry and an explicitly accepted lighting
strategy. No broad map rebuild is needed to discover whether a projector works.

### Phase 1 - Single-owner service and coherent one-light baseline

- [ ] Wire client/server includes and capability/readiness diagnostics.
- [ ] Implement bounded, idempotent lifecycle and partial-failure cleanup.
- [ ] Feed actual main-view camera and map-compatible sunlight metadata.
- [ ] Guard finite math, valid extents/depth, absent player/map data and
      unsupported APIs; surface failures instead of guessing.
- [ ] Preserve native off mode and all approved renderer/global settings.
- [ ] Add strict offline tests and actual-client tests using existing harnesses.
- [ ] Verify enable/disable/re-enable, fresh map load, cleanup, reconnect,
      death, spectating and service reload cleanup with zero orphan lights.
- [ ] Human reviews one-light lighting/shadows against the native baseline.

Exit: stable one-light behavior and exact off/restoration path, not a claim
that a full cascade renderer is accepted.

### Phase 2 - Cascades, coverage and stability

- [ ] Introduce up to three contiguous cascade records and deterministic splits.
- [ ] Begin with stable symmetric boxes; compare concentric and frustum-fitted
      layouts only after one-light behavior is accepted.
- [ ] Specify FOV/aspect/projection convention and conservative caster margins.
- [ ] Snap light-space coordinates without coverage holes; include guard bands
      after quantization and avoid unstable extent changes on small camera turns.
- [ ] Derive all masks from committed light state. Use original masks where
      sufficient; add bounded RT masks only for demonstrated need.
- [ ] Test partial-overlap cropping, alpha/RGB behavior, 1/2/3 cascade transitions,
      layer/depth coverage, low sun and far cutoff; sample contributions sum to
      the chosen intended illumination, without bright seams or missing bands.
- [ ] Baseline updates every frame; no shadow skipping until correctness passes.
- [ ] Review camera translation/rotation, standing still, zoom, shoulder view,
      bridge elevation, tall buildings and fast movement for shimmer/pop/acne.

Exit: human-approved cascade coverage and lighting, with resource counts and
static/engine test evidence. No spread/further/skyline feature expansion.

### Phase 3 - Existing view flows and scene boundaries

- [ ] Explicitly scope world-map/level captures and all secondary RenderViews.
- [ ] Verify capture appearance, main-view restoration and cache behavior.
- [ ] Test den entry/exit, city transitions, same-BSP different logical cells,
      launchers and missing map metadata. Verify destination through `ZM_World`.
- [ ] If launcher support is desired, review island/main menu/credits/flight,
      all palette tour slots, cancellation and return with unchanged camera/fog.
- [ ] Verify skyline matched lighting/coast/edge fires, rain puddles/snow,
      screen effects, clothing, gore, outlines and flashlight remain correct.
- [ ] Test two clients with different CSM settings; native client unchanged.
- [ ] UI opening/Back/X/Escape and saved preference/fresh-load restoration pass.

Exit: complete supported flow matrix and explicit off policies for unsupported
contexts. Existing approved effects are not replaced to hide shadow defects.

### Phase 4 - Measured optimization

- [ ] Obtain matched Off/one/two/three-cascade samples before tuning.
- [ ] Dirty-cache masks; verify zero repaints on unchanged relative layout.
- [ ] Add capability-gated skipping only if it provides measured benefit.
- [ ] Freeze the full committed shadow generation on skips; invalidate on
      camera, sun, extent, depth, config, map and relevant caster changes.
- [ ] Test dynamic crowds, doors, corpses and moving props while camera is still;
      avoid visibly frozen near shadows.
- [ ] Evaluate conservative culling only if cascade rendering is the measured
      bottleneck; do not require NikNaks without dependency approval.
- [ ] Budget/cancel any asynchronous precomputation and reject stale generations.
- [ ] Record costs, leaks, limits and rejected optimizations honestly.

Exit: budget met on agreed target hardware/workloads. No improvement claim from
unmatched crowd/weather/camera settings or hook timing alone.

### Phase 5 - Presets, documentation and release decision

- [ ] User approves default state and mapping into existing quality presets.
- [ ] Options explain compatibility, cost, unavailable reasons and global
      flashlight-setting implications without silently changing preferences.
- [ ] Packaging includes only cleared/owned required code/assets/licences.
- [ ] Update [README](../readme.md), [agent guide](../AGENTS.md) and the
      approved milestone tracker with static/live/visual/performance results.
- [ ] Update [version](../content/data_static/version.json) and matching
      [changelog](../content/data_static/changelog.json) only when actual
      milestone/phase/release status changes.
- [ ] Preview rollout accepted. Production variants/rebuilds and Workshop
      publication receive separate approval.

Optional later work: first-person proxies, directional culling, skybox
illumination and softness samples each require their own bounded proposal.
Native shader CSM/GI is not an implied extension of this GLua plan.

## 7. Test, diagnostic and performance specification

### 7.1 Proposed test locations and commands

Put GLua tests under `gamemode/tests`, explicit engine fixtures under
`gamemode/tests/fixtures`, and offline entry points under `tests/csm`. Reuse
[ZM_TestHarness](../gamemode/utils/test_harness.lua) and the
[offline harness guide](../readme.md#shared-offline-lua-fixture-harness); do not create a second runner
or move test files back into gameplay modules.

Proposed future files:

- `gamemode/tests/cl_csm_tests.lua`
- `gamemode/tests/fixtures/cl_csm_engine.lua`
- `tests/csm/test_client_csm.py`

Only create the files required by the accepted implementation. Suggested
future suite/status commands are `zn_test_csm` and `zombiesim_csm_status`;
they do not exist as a result of this document.

Required offline cases:

- Valid monotonic split endpoints, bounded lambda/count/depth and invalid-input
  diagnostics; zero/NaN/infinite inputs must not reach engine setters.
- Frustum corner/projection correctness at several aspect ratios, FOVs,
  orthographic capture extents and cardinal/near-horizontal sun directions.
- Conservative coverage after snap, extent change and caster-margin expansion.
- Mask transforms/cropping, 1/2/3 cascade weights and RGB/alpha contract.
- Unchanged layout produces no RT creation/repaint or allocation churn.
- Enable/disable/config/cleanup/reload orders are deterministic and idempotent.
- Failed allocation cleans every owned partial light and reports failure.
- Skip generation preserves all dependent transforms; dynamic-caster deadlines.
- Missing optional methods/dependencies follow explicit supported alternatives.
- Stale async generations cannot publish after disable or map change.
- View-scope nesting/error unwinding restores exact owned state.
- Another owner changing a cvar/render state is not overwritten on restoration.

After Lua changes, run:

```powershell
.\bin\test_glua_syntax.ps1
```

Run the focused offline CSM runner with the documented optional LuaJIT/lupa
environment, then the actual-client suite after an approved fresh same-map
reload. Never send `lua_*` commands through the development bridge. Use the
bridge for bounded registered commands/status and read the fresh report
separately. Static fixtures cannot prove shadow support, GPU weights,
render-hook ordering, pool behavior or visual appearance.

### 7.2 Diagnostic snapshot

Report at minimum:

- Enabled/preference/effective mode, lifecycle state and unavailable/failure reason.
- Map/profile/logical cell, source/build compatibility key and metadata source.
- GMod branch/HDR, optional method support and observed depth resolution.
- Current view kind/projection/origin/angles/FOV/aspect and render-pass identity.
- Desired/committed generation, per-cascade position/angle/extents/near/far,
  shadow/skip flags, update count/age and invalidation reason.
- Projector count, owned shadow count, RT slot/dimensions/estimated bytes,
  mask material validity, redraw counts and cache hits.
- Culling readiness/progress/cancellation if that optional feature exists.
- CPU update/mask/bake timings, count/max/p95 where meaningful, and limitations
  of the measurement. Do not label Lua timing "GPU shadow time".
- Owned global changes/restoration evidence, ideally none.

Avoid per-frame logs and unbounded diagnostic arrays. Expose read-only state;
do not publish a mutable projector table for other systems to modify.

### 7.3 Matched performance procedure

Use the same map/logical cell, camera path, viewport resolution, weather,
HDR/exposure, quality/sky/clothing settings, flashlight state, walker count,
visible props/corpses/effects and frame cap. Record hardware and engine branch.
Separate cold allocation/mask/bake samples from warm steady-state rendering.

For each approved mode, capture at least three repeatable warm 60-second runs
and a separately identified cold-start run. Report full-frame median/p95/p99,
Lua update/mask timings, worst rebuild spike, allocations/counts and any
available trustworthy GPU measurement. Record if GPU timings are unavailable.
Alternate the baseline/mode ordering to reduce warm-cache bias.

Agree numeric full-frame and spike budgets in Phase 0 using target hardware.
A proposed initial Lua coordination budget is <=0.5 ms mean and <=1 ms p95,
excluding engine shadow rendering; it is a starting acceptance proposal, not
an achieved result or sufficient full-frame budget. If the full-frame budget
fails, reduce cascade coverage/count or leave the feature off; do not claim
success because the Lua hook alone is fast.

Run ten enable/disable cycles and repeated scene transitions. Owned projector
counts must return to zero when off; RT/material slot counts must plateau at
the fixed pool cap rather than increase per map/toggle. Reconcile this memory
with the existing wardrobe and map-capture pools.

## 8. Licence, assets and dependencies

Upstream [LICENSE](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/LICENSE)
is BSD 3-Clause, copyright 2022 Xenthio. If adapting upstream code, retain
its copyright, conditions and disclaimer in source; reproduce them in
distribution documentation/materials for binary redistribution; do not imply
author/contributor endorsement. The
[README](https://github.com/Xenthio/RealCSM/blob/81cf47b8f90016f22b59b6aa9faae0134492040c/README.md)
credits Blueberry_pie for original work. Preserve attribution and investigate
the provenance of any selected component before redistributing it.

Preferred implementation: our own small service and original projection masks,
with RealCSM cited as the technical reference. If concrete code is adapted,
record the source file/revision and modification history rather than presenting
it as independently authored.

Asset inventory includes center/ring/end/soft mask VTFs, PNG/VMT sources,
editor/icon imagery and an XCF. Do not assume every asset has separate verified
third-party provenance merely because the repository has a root licence.
Exclude editor artwork from a gamemode renderer unless actually needed.

The repository also includes modified `d1_trainstation_02`, `gm_construct` and
`gm_construct_in_flatgrass` VMF/BSP/VMX/compiler outputs. **Do not copy or ship
these maps, Valve assets or compiler logs.** Use our own approved preview maps
and source assets for experiments.

NikNaks is optional upstream, not approved as a ZombieSim dependency. Before
adoption, separately inspect its licence/version/API/support, packaging impact
and installed-file detection. The baseline should work without it. StormFox
integration is out of scope; do not disable external weather owners.

If RealCSM or another projected-sun addon is active, report the conflict and
keep ZombieSim CSM off by default; do not remove its entities or force its
convars. Compatibility detection must avoid traversing the user's addons
directory. Absence of a known global does not prove no other projected lights
exist, so also test practical shadow-pool coexistence.

## 9. Handoff and stop conditions

Next action is **Phase 0 approval and a one-projector feasibility prototype**,
not copying the upstream tree or rebuilding the city.

Stop and ask for a decision if:

- Required geometry cannot cast/receive orthographic projected shadows.
- The requested look needs removal of baked direct sunlight that has not been
  proven selectively reversible.
- Client off/native and multiplayer behavior cannot both remain acceptable.
- Required results need private shadow-RT manipulation, a binary module,
  launch-option changes, uncleared assets or a new mandatory dependency.
- A proposal changes approved skies/fog/weather/clothing/camera presentation.
- The agreed full-frame/resource budget cannot be met.
- Production map or package publication work would be required.

Record exact maps/artifacts, source revision, current hypothesis, static
results, live results, human acceptance, rejected approaches and remaining
limits at each subsystem boundary. "Implemented", "offline tested",
"engine tested", "visually accepted" and "performance accepted" are distinct.
Do not close this tracker from syntax or fixture success alone.
