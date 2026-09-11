# Alpha 2 Plan

## Goal

Alpha 2 turns the existing abstract Walker simulation into a controlled, testable source of in-level zombies. It also fixes the world-map population label so the displayed count is live data rather than part of a generated image.

The release is complete when the preview world can materialize a small, configurable number of server-authoritative NextBots from the active cell, return or remove their virtual population correctly, and demonstrate stable behavior under repeatable tests.

## Current Baseline

The following work already exists and is the Alpha 2 starting point:

- `walker_core` imports the profile runtime JSON, maintains a deterministic population total, moves virtual hordes across the world graph, and supports noise attractors.
- The optional native module runs one worker at 4 Hz and exposes API v3 status, ticket summaries, and worker-safe checkpoint operations to `gamemode/sv_walker_sim.lua`.
- The preview world-map `WALKER` mode visualizes native horde summaries. It is a visualization, not a second simulation.
- The core ticket state machine is exposed through the server-only host. The active-cell controller materializes bounded ticket-backed NextBots and records terminal outcomes.
- `cl_world_map.lua` renders one profile-scoped live `POPULATION <count>` label in window chrome; generated overview artwork no longer contains static Population or Seed labels.
- Materialization verifies usable navigation per loaded map and rejects unsafe placements without altering virtual population.

Do not reimplement world routing, virtual population, horde movement, or attraction in Lua. The native worker remains the single authority for the virtual world.

## Scope And Non-Goals

### In Scope

- Explain the Walker architecture, state ownership, configuration, diagnostics, and testing workflow in a durable player/developer document.
- Expose the existing native spawn-ticket lifecycle safely to the server Lua host.
- Add one server-authoritative zombie NextBot entity and a bounded active-cell materialization controller.
- Implement basic chase, attack, target loss, and stuck recovery behavior using Garry's Mod navigation.
- Bound NPC pathfinding and spawning so virtual population cannot create an unbounded server load.
- Thoroughly test the worker, ticket lifecycle, NextBot lifecycle, AI behavior, and population accounting.
- Replace the static Population and Seed map-image label with a live population count placed in the world-map window chrome.
- Keep a test and issue log that records observed failures, reproduction steps, and the selected fix or deferral.

### Explicitly Deferred To Alpha 2.5 Or Later

- Cross-map player transition presentation, interactable transition brushes, and zombie portal entities.
- Tile FGD expansion for building orientation and road-connection markers.
- Loot, XP, combat balance, special zombie types, and population changes caused by gameplay systems beyond death/despawn accounting.
- Unbounded city-wide NextBot simulation. Off-map zombies remain virtual hordes.

## Architecture Decisions

### State Ownership

| Concern | Owner | Rule |
| --- | --- | --- |
| World graph, virtual hordes, reservations, and population | `walker_core` worker | Native state is changed only through its command queue. |
| Ticket snapshots and commands | GMod native adapter | Publish immutable snapshots to Lua; enqueue Lua requests for the next worker tick. |
| Spawn position validation, NPC entity lifetime, combat death, and despawn timing | Server Lua | Lua never decrements or restores population directly. |
| Rendering and map display | Client Lua | The client receives summaries only and has no authority over tickets or NPCs. |

Ticket and horde identifiers are `uint64_t` in the core. Do not pass them through Lua as a single number, because Lua numbers cannot retain every 64-bit integer exactly. Follow the existing horde-summary convention and expose ids as `idLow` and `idHigh` unsigned 32-bit halves, or as a validated decimal string. The server entity registry must use the same exact representation.

The materializer must use this sequence for every zombie:

1. Ask the worker for a bounded number of tickets for the active logical cell.
2. Read reserved ticket summaries from a published snapshot.
3. Convert the ticket local coordinates to a candidate position in the loaded cell.
4. Validate a nav area, floor, hull clearance, line-of-sight safety, and distance from players.
5. Spawn `zn_walker_zombie` only after validation succeeds.
6. Acknowledge the ticket only after the entity is valid and has stored its ticket id.
7. Resolve a materialized ticket as `killed` when the zombie dies, or as `despawned` when the controller removes it without death.
8. Reject an unusable ticket and allow expired reservations to return naturally.

This order prevents duplicate zombies, population loss on failed spawns, and population gains from cleanup. The controller must make acknowledgment and resolution idempotent because map cleanup and entity callbacks can arrive more than once.

### Active-Cell Budget

Only the loaded cell is materialized in Alpha 2. All other cells remain in the native simulation.

- Add server configuration for a conservative active zombie cap, materialization radius, player exclusion radius, retry interval, and despawn grace period.
- Request tickets only for free slots under the active cap, with a per-tick request limit and a single outstanding request id.
- Stop requesting tickets during map shutdown, profile reload, absent navmesh, or when no eligible player is in the city cell.
- On player movement between cells, refresh the active cell before requesting tickets. Existing NPCs are resolved as despawned during cleanup unless killed.
- Do not derive ticket placement from raw grid coordinates. Use the loaded cell and its local world geometry.
- Reconcile materialization once per worker tick (0.25 seconds), not every frame. A faster Lua timer cannot observe a newer native snapshot and only adds duplicate work.

The first version should sample valid Garry's Mod nav areas near the ticket's deterministic local coordinate and then run a server-side hull trace. It must fail cleanly when the map has no usable navmesh. Authored spawn-anchor entities may be introduced later only when a specific placement problem requires them.

### Navmesh Readiness Gate

Before Phase C, use one staged `zn_preview` city-cell map to prove that the game can load a matching `.nav` asset and that `navmesh.GetAllNavAreas()` returns usable areas. Record the map, nav generation command, generated asset location, and load result in the Alpha 2 test log. Do not implement a broad auto-spawn loop until this one-map proof passes.

For Alpha 2 completion, define and validate how matching nav assets are generated and staged for every preview map that can materialize zombies. A missing or invalid navmesh is an explicit no-spawn condition, not a reason to fall back to per-NPC world pathfinding.

## Plan 0: Navmesh Availability And Validation

Plan 0 precedes Phase A. Its purpose is to prove that generated preview city maps have usable, current navigation data before the Walker design commits to NextBots.

### Existing Foundation

`gamemode/sv_map_batch.lua` builds a de-duplicated queue from the active runtime index, persists progress in `DATA/zombiesim/map_batch.json`, and resumes after map changes. `zombiesim_generate_navmeshes` uses the server-side `navmesh.BeginGeneration()`, `navmesh.IsGenerating()`, and `navmesh.Save()` APIs to generate, save, validate, record, and advance through ordinary city-cell maps automatically.

This API-driven sequence is the execution path. It avoids blind `game.ConsoleCommand` input simulation, which is unsuitable for blocked or client-only engine commands. Cubemap batching remains a separate manual workflow because it has no equivalent server Lua API.

### Deliverables

1. Provide a one-map mode in the navmesh batch workflow so an admin can select one valid, staged preview city-cell map for the initial proof without starting the full queue. Keep the existing no-argument command as the all-map maintenance workflow.
2. Add a server-only navmesh status command that reports the loaded map, active profile, matching BSP presence, matching `.nav` presence, nav-area count, and a clear pass/fail result. It must use the engine's `navmesh` API and the actual loaded map name, not infer availability from the runtime JSON alone.
3. Write the status result to a structured `DATA/zombiesim` diagnostic file so a map transition does not erase the evidence.
4. Define a per-profile navmesh validation manifest containing the required ordinary city-cell maps, the profile/runtime-index revision, validation time, and each map's area count. Safe-zone maps are excluded because Alpha 2 never materializes zombies there.
5. Invalidate the profile validation manifest whenever its staged BSP set or runtime-index revision changes. A fresh map build must not silently reuse an old navmesh validation result.
6. Once `navmesh.Save()` completes, record the nav-area count and whether the mounted `.nav` file is immediately visible, then advance automatically. A non-empty in-memory mesh is sufficient to continue the generation queue; a missing file remains an explicit persistence warning that blocks Plan 0 acceptance until reload verification passes. The operator should be able to resume, inspect status, retry a failed map, or cancel without corrupting completed entries.

### One-Map Proof

1. Build and stage the current preview profile with the normal preview pipeline, then launch `zn_preview` on a local server with the development command bridge available.
2. Select one ordinary staged city-cell map through `zombiesim_generate_navmeshes <mapName>`. Do not use a launcher or safe-zone map for the proof.
3. Let the batch change level and wait for it to call the server navmesh generation and save APIs automatically.
4. Run `zombiesim_navmesh_status`. It passes only when the loaded map and active profile match the requested target, the matching `.nav` file is visible to the game, and `navmesh.GetNavAreaCount()` reports at least one usable area.
5. Persist the diagnostic, mark the map complete only after the automatic pass, and reload the same map once to prove the saved navmesh is loaded rather than only resident in memory.
6. Record the full command sequence, map name, area count, diagnostic path, and any failure in `docs/alpha_2_test_log.md`.

### Full Preview Coverage

After the one-map proof, process every unique ordinary city-cell BSP in the active preview runtime index. The final validation manifest must contain every required city-cell map exactly once and no stale profile revision.

For each map, the batch must stop on a failed generation, save call, zero-area result, wrong loaded map, or profile mismatch. A missing immediately mounted file records a persistence warning but does not stop the generation queue; reload verification determines whether that map has durable coverage. Rebuild or restage of preview maps invalidates coverage and requires affected maps to be regenerated before Alpha 2 automatic spawning is enabled.

### Plan 0 Acceptance

- A local admin can start, inspect, resume, retry, and cancel a one-map navmesh job without affecting the full queue.
- A generated preview city-cell map loads with a saved, non-empty navmesh after a level reload.
- The diagnostics and validation manifest identify the exact profile, runtime revision, map, and nav-area count that passed.
- Full preview coverage lists every staged ordinary city-cell map once; safe zones are explicitly excluded.
- Restaging changed preview BSPs invalidates prior navmesh coverage instead of allowing stale navigation data to pass.
- The automated navmesh workflow remains independent of the development command bridge; it relies only on the server-side `navmesh` API.

## Delivery Phases

### Phase A: Freeze The Contract And Documentation

1. Create `docs/walker_simulation.md` as the detailed reference for the native core, worker lifecycle, data flow, horde movement, tickets, configuration, diagnostics, known limitations, and build/test commands.
2. Reduce the Walker section in `readme.md` to the essential install/build/run commands and link to the detailed reference.
3. Define the Alpha 2 materialization settings and ticket API before adding any entity code. Include ownership, thread-safety, request bounds, and all terminal ticket states.
4. Create `docs/alpha_2_test_log.md` with columns for date, profile/seed, map, build, reproduction steps, expected result, actual result, evidence, severity, and resolution.

Acceptance: a developer can explain why a NextBot is not the source of truth for population, identify every ticket state, and use the documented commands to inspect the live worker.

### Phase B: Expose Native Spawn Tickets

1. Extend `WalkerWorker` and `module_server.cpp` with narrow Lua methods for requesting spawn tickets, reading ticket summaries, acknowledging a successful spawn, rejecting a failed spawn, and resolving a materialized ticket. Export ticket state symbolically and encode all 64-bit ticket and horde ids exactly.
2. Keep all mutation commands queued to the worker. Lua reads only a published immutable snapshot protected by the adapter's existing synchronization.
3. Add `ZM_WalkerSim` wrapper methods in `gamemode/sv_walker_sim.lua`; validate cell ids, ticket ids, request ids, and integer limits on the server before calling native code.
4. Add admin-only diagnostics for pending, reserved, materialized, expired, rejected, killed, and despawned ticket totals. Do not expose ticket control to clients.
5. Extend the existing C++ ticket-lifecycle tests. They already cover reservation, acknowledgement, rejection, expiry, kill, and despawn; add duplicate acknowledgement/resolution, request-id replay, capacity-bound, exact-id encoding, and terminal-ticket retention tests.
6. Bound terminal-ticket retention. The current core retains every terminal ticket in its snapshot, so define a finite tombstone/history policy that preserves idempotence and diagnostics without allowing a long-running server's snapshots or checkpoints to grow forever.

Acceptance: a server-console test can reserve one ticket, acknowledge it, resolve it as killed or despawned, and observe the expected cell/horde summaries without changing total population incorrectly.

### Phase C: Implement The Zombie NextBot

1. After the navmesh readiness gate passes, add `entities/entities/zn_walker_zombie/` with explicit server, client, and shared files. The server owns health, damage, target choice, navigation, and ticket cleanup.
2. Store immutable spawn metadata on creation: ticket id, horde id, source cell id, materialization time, and whether the ticket has been acknowledged.
3. Implement a small state machine: idle/search, pursue, attack, target-lost, and stuck recovery. Keep all target selection server-side.
4. Choose living players in the loaded cell as targets. Use sight/range checks first, then a short-lived last-known position; do not ask the native worker for per-NPC pathing.
5. On lethal damage, call the controller once to resolve the ticket as killed before normal entity removal. On intentional cleanup, resolve once as despawned. A failed acknowledgment or unexpected removal must be logged and reconciled by the controller.
6. Start with standard model, health, movement, and melee values as configurable development settings. Balance and loot remain outside Alpha 2.

Acceptance: one manually requested zombie spawns on a valid nav area, pursues a player, attacks only in range, dies without duplicating resolution, and is never recreated from the same ticket.

### Phase D: Materialization Controller

1. Add a server-only controller module, for example `gamemode/sv_walker_materialization.lua`, included from `init.lua` after `sv_walker_sim.lua`.
2. Maintain the active entity registry by exact ticket id and a bounded request state. Reconcile it against the native ticket snapshot once every 0.25 seconds, rather than every frame.
3. For each free slot, select a reserved ticket from the active cell, derive a candidate point, and validate it before creating the NextBot.
4. Reject immediately when no valid point can be found after the configured bounded attempts. Log the reason: no navmesh, blocked hull, player exclusion, unavailable entity, or native command failure.
5. Despawn entities that are outside the active relevance range for the configured grace period, when the active profile/cell changes, and at shutdown. Do not despawn a zombie solely because its horde moves while its ticket is materialized.
6. Provide development-only console commands to inspect controller state and request a small deterministic ticket batch. They must use the same production ticket path, not a parallel spawn path.

Acceptance: a preview session maintains the configured cap, never creates duplicate ticket ids, returns failed/despawned virtual population correctly, and leaves no materialized tickets after a clean map shutdown.

### Phase E: AI And Pathfinding Performance

1. Use NextBot navigation only inside the loaded map. Virtual horde routing remains the native graph's responsibility.
2. Stagger expensive work by entity id: target selection, path recomputation, and stuck checks must not all execute in the same frame.
3. Recompute a path only when the target changes, the target has moved meaningfully, the route becomes invalid, or a bounded refresh interval elapsed.
4. Reuse the current path between refreshes; apply a cooldown after failed paths and use a short local fallback rather than retrying continuously.
5. Cap active NPCs before raising AI complexity. Profile 1, then a small group, then the configured cap while observing server frame time, worker tick duration, dropped ticks, and path failures. Capture a zero-NPC baseline first and set the host-specific performance budget in the test log before increasing the cap above one.
6. Add deterministic test modes where target behavior and ticket batches are controlled, so regressions can be reproduced without relying on a random horde layout.

Acceptance: the configured cap does not cause unbounded path recalculations, the native worker remains at its expected tick rate without growing dropped ticks, and stuck zombies recover or despawn cleanly rather than consuming continuous path work.

### Phase F: Dynamic World-Map Population Label

1. Remove Population and Seed from the generated map-label artwork in `bin/generate_world_cells.ps1`. Preserve only static world identity in generated materials, then regenerate and stage the preview material outputs.
2. Add a compact profile-scoped `ZM.WalkerPopulation` server-to-client message for the live population count. Full horde snapshots remain preview-only; city clients must not receive preview horde data merely to render a count.
3. Make `cl_world_map.lua` draw a single live `POPULATION <count>` label in the map window's top-left chrome, not at `mapX`, `mapY`, or inside the map texture. The client accepts a count only when its profile matches the active world profile.
4. Until a valid population update arrives, display an explicit unavailable/loading state rather than a misleading static count.
5. Render the label consistently in default, satellite, map, and walker views. The walker overlay may retain horde visualization, but must not create a second population label.
5. Ensure the population text is sized and positioned from the containing panel dimensions so it never overlaps the map graphic, sidebar, or resize controls.

Acceptance: changing the live Walker population updates one label in the intended window position across render modes; generated map images contain no static Population and Seed text.

### Phase G: Checkpoint Persistence, Verification And Release Evidence

Implement the detailed contract in [walker_checkpoint_persistence_plan.md](walker_checkpoint_persistence_plan.md) before collecting final release evidence.

1. Extend `WalkerWorker` with worker-thread-safe checkpoint export at a tick boundary and import while `GraphReady`. Preserve the core's existing format/version, graph revision, seed, configuration-hash, and checksum validation; reject export/import in invalid lifecycle states.
2. Bump the optional module to API v3 and expose bounded server-only checkpoint export/import methods. Rebuild and install the Win64 module after the native contract changes.
3. Add profile-scoped checkpoint storage, periodic state-hash-driven saves, orderly-shutdown saves before worker stop, startup restore before worker start, and status diagnostics. The implemented host store is the server SQLite `walker_checkpoints` table because large `DATA` file writes did not produce readable artifacts in this environment.
4. During restore, reconcile imported materialized tickets as despawned before enabling the controller. Do not reconstruct pre-transition NextBots; preserve killed tickets and horde movement state as the native source of truth.
5. Run the C++ build and test presets from `bin/walker-simulator` after every native contract change. Core coverage includes killed-ticket checkpoint round-trip, corrupt checkpoint rejection, and deterministic continued simulation; worker lifecycle handling is exercised through the API v3 live validation.
6. Run `zombiesim_walker_smoke` after rebuilding the optional module, then validate live worker startup with `zombiesim_walker_status`, `zombiesim_walker_cell`, and `zombiesim_walker_noise`.
7. In `zn_preview`, first prove the staged navmesh on one selected city-cell map. Then test no-navmesh handling, one zombie, a small group, cap saturation, failed spawn placement, forced cleanup, death, active-cell refresh, profile switch, and game shutdown.
8. Prove one killed zombie remains removed after both `changelevel` and a local server restart, while horde location/progress and attractors resume from the persisted checkpoint. Confirm imported materialized tickets become despawned before the controller creates new entities.
9. Verify that each test records the native tick, graph hash, state hash, population, horde count, ticket counts, active NPC count, controller error count, checkpoint byte length, save/restore result, and checkpoint error in the test log.
10. Review all open issues in `docs/alpha_2_test_log.md`; fix release blockers, document accepted limitations, and link reproduction evidence before calling Alpha 2 complete.

Acceptance: complete. A killed Walker reduced preview population from `81,000` to `80,999`; compatible `changelevel` and full local restart both restored that population, reconciled imported materialized tickets, and resumed active-cell materialization with zero worker API errors or dropped ticks.

## Required Invariants

- One materialized NextBot maps to exactly one acknowledged ticket.
- A ticket can reach one terminal outcome only: rejected, expired, killed, or despawned.
- Failed entity creation never removes virtual population.
- Only a killed entity permanently reduces the simulated population; a despawned entity returns to its horde.
- The client never requests, acknowledges, rejects, or resolves tickets.
- Active NPC count remains at or below the configured cap under all retry and failure paths.
- Worker commands never mutate native state directly from the game thread outside the synchronized queue.
- Ticket ids and horde ids retain their exact value across the native-to-Lua boundary and in the entity registry.
- Terminal ticket history is bounded while duplicate commands remain harmless during its documented retention window.
- A map without a valid staged navmesh never materializes a NextBot.
- Compatible checkpoint restore preserves native horde motion and terminal ticket outcomes across a map change or server restart; map-local NextBots are reconciled as despawned before new materialization begins.

## Implementation Order

1. Complete Plan 0 and accept its one-map proof plus full preview coverage process. The discovered invalid generated navmesh remains a documented deferred generator defect.
2. Complete Phase A and agree the ticket/API contract.
3. Implement and unit-test Phase B before adding any NextBot.
4. Build a manually driven Phase C zombie and prove its ticket cleanup.
5. Add Phase D automated materialization at a cap of one, then raise it gradually.
6. Add Phase E pathfinding controls and profile performance before increasing the cap again.
7. Ship Phase F independently once its in-game placement is verified.
8. Complete Phase G checkpoint persistence and close or document every entry in the Alpha 2 test log.

This order keeps the first gameplay entity small and reversible: ticket accounting is proven before automated spawning, and server load is measured before scale is introduced.

## Alpha 2 Closure

Alpha 2 is complete for the preview profile. Advanced zombie sensory behavior, animation, combat balance, and broader Romero-style behavior tuning are explicitly deferred to Alpha 3.