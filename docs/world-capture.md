# Resumable preview world captures

Implementation owners:

- `gamemode/world_capture/sh_contract.lua`: revision, projection and PNG identity.
- `gamemode/sv_world_capture.lua`: durable jobs, nav sequencing and restoration.
- `gamemode/cl_world_capture.lua`: ready acknowledgement, rendering and cleanup.
- `gamemode/atmosphere/cl_fog.lua`: render-scoped fog owner.
- `gamemode/cl_skybox.lua`, `gamemode/cl_weapon_effects.lua`: transient guards;
  the weapon owner exposes its casing entities for scoped hiding.
- `gamemode/sv_map_batch.lua`: overlap guard only; existing nav-only workflow stays
  independent. `gamemode/init.lua` and `gamemode/cl_init.lua` wire the new owners.
- `bin/import_world_captures.py`: validating/downsampling/stitching importer.
- `gamemode/tests/{cl,sv}_world_capture_tests.lua` and corresponding
  `gamemode/tests/fixtures/{cl,sv}_world_capture_engine.lua`: explicit fixtures.
- `tests/world_capture/test_client.py`, `test_importer.py`, `requirements.txt`;
  `tests/glua/harness.py` adds allowlisted compilation for fixture injection.
- Existing atmosphere tests/fixture cover nested fog restoration.
- `gamemode/cl_dev_profiler.lua`: map-window screenshots wait for VGUI like
  other existing UI captures, so migration labels are included in the PNG.

The preview-only capture service visits **logical ordinary cells**, not unique
recipe names. Cells sharing a BSP still receive separate fresh loads and files.
The existing nav-only commands remain unchanged; their independent batch must
not overlap this service.

## Bounded rollout

Start from one deployed, living preview admin (one connected human). The service
rejects launcher/menu state, production profiles, missing staged BSPs, unknown
logical coordinates, active maintenance and queued transitions.

```text
zombiesim_world_capture_start current
zombiesim_world_capture_status
zombiesim_world_capture_start pilot
```

`pilot` selects a bounded 2x2 from the current cell plus a representative coast
and bridge when present (duplicates removed). Explicit selection accepts at most
eight logical `x,y` pairs:

```text
zombiesim_world_capture_start 15,5 16,5 15,6 16,6 0,0
zombiesim_world_capture_cancel
zombiesim_world_capture_retry
zombiesim_world_capture_extend 17,5 17,6
```

Retry retains successful results and resumes the unfinished variant. Extend
adds at most eight previously unqueued cells to the same revision/run; it never
automatically expands to all 576 cells. Every explicit continuation snapshots a
new restoration baseline, so intervening normal gameplay is not rolled back.
Full-world collection is separately explicit, never inferred from a bounded
selection. After the user-approved pilot, start a fresh capture-only rollout:

```text
zombiesim_world_capture_full preview 576
```

The scope and count must exactly match installed authoritative preview data.
Every logical cell is freshly loaded and captured twice, even when recipes
repeat; prior pilot results are not reused. The separate, slower combined
option is `zombiesim_world_maintenance_full preview 576`. Explicit coordinate
selections/extensions retain the eight-cell cap. Retry/cancel/status and
per-result checkpoints apply unchanged to full runs.

Monitor a known run with an attached process:

```powershell
.\bin\watch_world_capture.ps1 -RunId "<run-id>" -StagePreview
```

It reports result progress, refuses replaced/partial/failed runs, stops on
stale heartbeat or stalled progress, and validates/imports only after all
results and original restoration are verified. It never changes game state
or automatically retries a failed run. The queue itself survives monitor
termination; inspect status and resume with `zombiesim_world_capture_retry`.

## Composite nav/capture maintenance

```text
zombiesim_world_maintenance_start current
zombiesim_world_maintenance_start pilot
```

For each map, a mounted navmesh is validated or a missing one is generated using
the existing `ZM_MapBatch` spawn-seed/status helpers. Newly generated meshes must
be saved, reloaded, mounted, loaded and have usable areas **before** screenshot
capture. The persistent composite queue owns its own state; it does not borrow,
replace or delete the nav-only batch's checkpoint. Nav work is shared for cells
using the same recipe, while their captures remain logically distinct.

Generation has a 300-second bound. Cancellation during native nav work is
checkpointed and applied at its save/reload boundary; screenshots never run
while nav generation is active.
Native `.nav` saves are mounted from Garry's Mod's `maps` directory. This
service does not copy them into distributable packages or claim publication
readiness.

`buildcubemaps` is **not** part of this Lua queue: Garry's Mod lists it in
[Blocked ConCommands](https://wiki.facepunch.com/gmod/Blocked_ConCommands).
`game.ConsoleCommand`, `RunConsoleCommand` and `Player:ConCommand` are not valid
automation routes. Use native operator console entry or separately authorized
external native-console automation; do not use aliases/exec/RCON as bypasses.

### Cubemap automation research (2026-10-10)

Read-only inventory of the currently staged preview world found **576 logical
cells but only 187 distinct ordinary BSPs**. Cubemaps are BSP-local products,
so the queue should deduplicate by exact BSP/revision, unlike world captures.
Those BSPs contain523 authored probes:38 maps have two and149 have three.
Launcher/standalone den builds are separate jobs, not implicitly included.

One inspected BSP already packs `cubemapdefault.vtf` and coordinate-named probe
VTFs. Their existence alone does not establish a completed native capture:
VBSP can generate default cubemaps. The public
[Source SDK cubemap compiler](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/utils/vbsp/cubemap.cpp)
has `CreateDefaultCubemaps`; it is compiler evidence, not GMod's runtime
`buildcubemaps` implementation. VDC runtime documentation was inaccessible
behind Anubis; exact completion markers and HDR/LDR behaviour remain unverified.

Recommended prototype after the active screenshot run:

1. Snapshot one isolated preview BSP and original survivor/map/preferences.
   Confirm the actual mounted writable BSP, rather than assuming `content/maps`
   is the file the engine modifies. Reject capture/nav/other maintenance overlap.
2. An explicitly armed external Windows driver enters `buildcubemaps` into the
   **native developer console**, not Lua. Use a harmless unique `echo` first to
   prove console focus and delivery. Never inject while the game lacks focus;
   pause on focus loss, held modifier keys, lock/minimize or user intervention.
3. Observe the real engine operation once. Derive success from fresh console
   evidence, post-build BSP pak changes and expected usable VTF content, plus
   reloaded map readiness. A heartbeat/map reload, file timestamp or echoed
   "done" is insufficient. Do not infer completion from a fixed sleep.
4. Validate required HDR/LDR modes on this installed branch. Restore any
   explicitly changed render/cheat preferences and verify restoration; do not
   automatically prescribe two builds or permanently enable cheats.
5. Only then add an opt-in cubemap stage to the maintenance scheduler:
   load -> native cubemap build/verification/reload -> NAV save/reload
   verification -> logical-cell screenshot variants -> next. Checkpoint each
   stage by source geometry/lighting/compiler revision, retain a retry/manual
   fallback and stop on timeout rather than falsely completing it.
6. Keep modified preview outputs isolated with backups and a validated staging
   path. Runtime cubemap baking can modify BSPs; production replacement,
   packaging hashes and publication are not authorized by this research.

[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)
can synthesize keystrokes, but targets the input stream rather than a nominated
application and is subject to integrity-level restrictions. Guard it with
[GetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getforegroundwindow)
and exact process identity. Successful input insertion is not successful command
execution. The initial driver would require a dedicated foreground GMod session;
it must not steal focus or type into the editor while the user works.

Do not install Mapbase or assume its `-autocubemap` feature exists in retail GMod.
Native launch-command delivery is an unverified alternative, not an implemented
solution. A dedicated server cannot substitute for the rendering client needed
to photograph reflection probes. No native-console inputs, launch options,
cheats or BSP modifications were performed during this research.

## Rendering and restoration contract

Both server and client require current preview `mapManifestSha256` **and**
`templatePlanSha256`, bounds revision, pitch, camera height, installed skyline
manifest SHA256 and capture version.
The projection is north-up (`Angle(90,90,0)`) and uses the whole authoritative
`neighbourPitch` (5760 in bounds revision 2). The camera matches the existing
Level view's `ZM_Skybox:GetPlayableCeiling()` exactly: installed skyline
`cameraOrigin[3] - 128` (4992 in the current preview), below the skybox room.
The shared revision checks the skyline profile/plan/pitch/bounds; the client
also checks the owning API before rendering. The runtime world's
`cellBounds.playableCeiling` is retained as bounds identity, not substituted for
the renderer owner's ceiling. Capture retains both native sky passes and the
coast ocean; it must not suppress `PreDrawSkyBox`.
Native orthographic sky passes do not scale their bounds, so the coast owner
also draws its existing ocean/beach mesh buffers in the ordinary capture pass
with the exact Source sky-to-world transform. This is capture-scoped,
depth-tested, and uses the same approved geometry/materials; normal rendering,
beach placement, quality preferences and skybox assets are unchanged.

`clear` disables fog only during the secondary view through the atmosphere fog
owner. `atmospheric` uses the current native cell fog/weather. Both retain lying
snow and baked lighting. The service hides players, weapons, enemies, dropped
items, weather particles, target/highlight overlays, world arrows and cosmetic
fire/weapon transients. Existing no-draw/shadow, atmosphere particle state, fog
state/culling and capture flags are restored even after render failure. No saved
quality/sky/fog preferences, cheat toggles or server weather settings are changed.

Actual client acknowledgement waits for matching map/logical cell, atmosphere
profile, server weather synchronization, loading-screen release and stable render
frames. PNG signature/dimensions/end chunk, byte length, checksum and disk
readback must match before the server advances. A sampled pixel-variation gate
also rejects constant buffers before writing or acknowledging a result.

The durable checkpoint is Garry's Mod DATA
`zombiesim/world_capture_state.json`, with a previous checkpoint and per-run
`zombiesim/world_captures/<run-id>/run.json`. Each result is checkpointed before
the next variant or `changelevel`. Original profile-scoped core values, map,
logical cell/safe-zone, position, angles, move type and frozen state are restored
and checked after returning. SQL revision/update metadata legitimately advances;
it is not claimed byte-identical. Player input/damage are blocked only during
maintenance. The service never changes inventory or equipment.

## Validate, stitch and import

Original 1024px PNGs remain in DATA for diagnostics/promotional use. Display
assets are deliberately much smaller because engine `Material()` textures cannot
be safely evicted on demand.

```powershell
python -m pip install -r tests\world_capture\requirements.txt
python bin\import_world_captures.py `
  --run "<GarrysMod DATA>\zombiesim\world_captures\<run-id>\run.json" `
  --data-root "<GarrysMod DATA>"
```

Default output is isolated `generated/world_captures_import`. Add
`--stage-preview` to publish into `content` after inspecting the pilot. The
importer requires verified survivor restoration, both authoritative hashes, the
same installed skyline manifest (`--skyline` overrides its default sibling of
`--world`) and
valid logical identities/PNG checksums. Blank or constant buffers are rejected.
It does not delete old/unowned assets.
When replacing already-loaded display textures, stage with Garry's Mod closed
and use a fresh client session for review; rewriting PNGs does not evict the
engine's cached `Material()` pixels.

Default display tiles are 256px; `--tile-size` accepts 128/256/512.
`--overview-size` defaults to 3072 and cannot exceed 4096. A full 24x24,
two-variant 256px set plus two 3072px overviews uses approximately **360 MiB RGBA**
before engine overhead; imports above a 384 MiB decoded budget are rejected.
The report also records actual encoded disk bytes. Packaging remains separately
gated: `ownedFiles` is an explicit inventory, not permission for a broad gather.
The full 576-cell default budget is 377,487,360 decoded RGBA bytes (360 MiB),
within 384 MiB; encoded size is measured after import rather than estimated.
Native atmosphere sidecars preserve each capture's context. Different baked
cell lighting and time/weather contexts can cause seams; capture never changes
global weather/time merely to equalize them.
`ZM_WorldCapture:GetInstalledRevision()` exposes validated skyline signature,
camera, pitch and capture version for UI manifest checks. Call when loading a
manifest/fresh map, not every frame; parsed skyline/hash data is cached.

Published files:

```text
content/materials/worlds/preview/captured/<clear|atmospheric>/cell_<id>.png
content/materials/worlds/preview/captured/<clear|atmospheric>/overview.png
content/data_static/world_captures_preview.json
```

The schema-1 manifest has `profile`, both authoritative hashes, `complete`,
`variants.clear` and `variants.atmospheric`. Each variant has `complete`, `atlas`
and `cells` keyed by string logical cell id. Material paths include `.png` and
omit `materials/`. Only a variant covering **every** authoritative ordinary cell
can be complete; a pilot is explicitly partial and does not enable player
Satellite. Additional metadata retains capture version, source/display hashes,
logical coordinates, native atmosphere state, dimensions and memory/disk budgets.

## Focused validation

```powershell
python -m pip install -r tests\glua\requirements.txt
python tests\world_capture\test_client.py
python tests\world_capture\test_importer.py
python tests\atmosphere\test_client_atmosphere.py
.\bin\test_glua_syntax.ps1
```

These test real modules against explicit offline fixtures, north-up stitching,
identity/hash rejection, cleanup, retry, same-BSP logical cells, nav ordering and
restoration. They do not establish engine appearance, coastline completeness,
nav-generation success or full-world capture time.

## Native-renderer gate correction (2026-10-10)

The initial implementation used the runtime bounds ceiling minus 16 (4592),
producing miniature skyroom geometry; suppressing the sky passes then made the
buffer black. Those outputs are not valid captures and must never be imported.
Direct comparison with the existing human-reviewed Level capture established a
working warm native orthographic baseline. Removing sky suppression alone did
not correct the geometry; boolean `ortho = true` alone did not either. Changing
only the camera height to the existing owner ceiling (4992) produced the correct
ordinary motorway/bridge at full 5760-unit pitch. Native sky/coast passes remain.

Capture revision 4 records and validates this skyline-derived camera and the
capture-only coast projection, rejecting earlier diagnostic runs. A successful queue or pixel-variance check
alone is not visual acceptance; inspect the bounded pilot's actual PNGs before
staging, and keep full-world collection and publication separately gated.

### Bounded live evidence

- Preview revision-4 run `preview_1791592779_142707845` completed 14 results
  across seven logical cells: `(15,5)`, `(16,5)`, `(15,6)`, `(16,6)`, Storm Drain
  `(0,0)`, west boundary `(0,-12)` and bridge `(17,-12)`. Extension retained the
  first four results without repeating them. Restored original survivor/map/
  pose/frozen/core state was verified. Start-to-final-restoration was 189 seconds,
  including the explicit continuation; it is not a full-world timing promise.
- Importer validated all PNGs/actual-client acknowledgements and staged an
  explicitly **partial** preview manifest, 256px display tiles and 3072px
  overviews: 1,812,537 encoded bytes, 79,167,488 estimated RGBA bytes.
  The original 1024px images remain in DATA. Partial variants do not enable
  Satellite; no 576-cell collection, production rebuild or upload was run.
- Composite run `preview_1791593038_1856536809` observed native generation,
  saved and freshly reloaded the preview motorway NAV, validated 1,313 mounted
  areas, then captured both variants and restored the original survivor.
  Total bounded run: 86 seconds. The generated 1,910,707-byte NAV remains in
  Garry's Mod `maps`; no nav-only checkpoint or production assets changed.
- Offline client/server fixtures, PNG importer and native syntax checks are
  separate from these actual-engine results. Human final visual acceptance,
  broader weather/snow/context coverage and full-world release remain gates.
- A separate final Storm Drain run `preview_1791593177_3894777729` verified both
  variants through the final capture-owned coast hook and restored the survivor.
  Fresh map-view status/UI screenshot shows Atlas/Satellite/Walkers/Map/
  Wireframe and correctly disables Satellite for the partial installed manifest.
