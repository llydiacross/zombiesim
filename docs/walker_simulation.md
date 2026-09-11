# Walker Simulation

## Purpose

The Walker simulation is the authoritative virtual-zombie population system. `walker_core` owns the world graph, horde movement, population totals, ticket ledger, and deterministic state hashes. Garry's Mod hosts the optional native worker; it does not recreate the simulation in Lua.

The worker is deliberately independent from in-level NPCs. A `zn_walker_zombie` planned for Alpha 2 is a temporary materialization of one virtual walker, not the population record itself.

## Components And Ownership

| Component | Location | Responsibility |
| --- | --- | --- |
| Core | `bin/walker-simulator` | Deterministic world import, horde movement, tickets, checkpoints, and snapshots. |
| Worker | `src/gmod_adapter/walker_worker.*` | Runs the core at 4 Hz and publishes synchronized immutable snapshots. |
| Native adapter | `src/gmod_adapter/module_server.cpp` | Validates Lua arguments, enqueues worker commands, and serializes snapshots to Lua tables. |
| Server host | `gamemode/sv_walker_sim.lua` | Loads the active profile, refreshes the active cell, exposes server-only diagnostics, runs the manual Phase C entity lifecycle probes, and sends preview summaries. |
| Materializer | `gamemode/sv_walker_materialization.lua` | Reconciles the bounded active entity registry against ticket snapshots and owns relevance cleanup. |

Only the worker may mutate core state. Lua calls that alter horde or ticket state enqueue work for the next worker tick; a successful call means accepted for queuing, not that the requested state is already visible. Lua reads a published snapshot and never takes a worker lock.

## Lifecycle

1. `InitPostEntity` reads the active profile runtime JSON through `ZM_World`.
2. `ZM_WalkerNative.LoadWorldJson` validates the graph and configuration.
3. `ZM_WalkerNative.Start` begins the 4 Hz worker.
4. `sv_walker_sim.lua` sets the current player cell as the active cell and refreshes it when diagnostics run.
5. The worker publishes stats, cell summaries, horde summaries, and API v3 ticket summaries after each completed tick.
6. `ShutDown` saves a native checkpoint before stopping the worker. On compatible startup, the host restores it before starting the worker; imported map-local materialized tickets are reconciled as despawned before the controller resumes. Periodic checkpoint serialization is requested and performed on the worker thread, then polled by Lua without stalling gameplay.

The preview `WALKER` map mode is read-only visualization. It receives native horde summaries and the server materialization ratio every 0.5 seconds, and does not simulate walkers on the client. It renders one stable marker for each materialized-equivalent Walker: `ceil(horde population / zombiesim_walker_population_per_zombie)`.

## Configuration

The current core configuration is passed to `LoadWorldJson` by `WalkerSim.Config` in `gamemode/sv_walker_sim.lua`:

| Setting | Current value | Meaning |
| --- | ---: | --- |
| `minimumGroupSize` | 4 | Smallest virtual horde after splitting. |
| `maximumGroupSize` | 64 | Largest virtual horde before splitting. |
| `progressPerTick` | 4 | Nominal horde movement in permille per 4 Hz tick; each horde deterministically varies by one permille to avoid synchronized movement waves. |
| `attractionDecayPermille` | 920 | Attraction retained each tick. |
| `safeZonePenalty` | 100000 | Routing penalty applied to safe zones. |
| `ticketLifetimeTicks` | 20 | Reserved ticket lifetime; currently five seconds. |
| `maximumTicketsPerRequest` | 12 | Native upper bound for one ticket request. |

Phase B also freezes the following server-only materialization settings. They will belong to `ZM_WalkerSim.MaterializationConfig`, remain out of the client protocol, and be validated before ticket requests:

| Setting | Initial value | Constraint |
| --- | ---: | --- |
| `activeZombieCap` | 64 default; 256 maximum | Must be at least 1; controller never exceeds it. |
| `requestLimitPerTick` | 4 | At least 1 and no greater than `maximumTicketsPerRequest`. |
| `materializationRadius` | 2400 | Positive Source units around an eligible player for spawning and relevance cleanup. |
| `playerExclusionRadius` | 512 | Positive and less than `materializationRadius`. |
| `minimumZombieSeparation` | 96 | Positive Source units separating live materialized zombies. |
| `placementAttemptsPerTicket` | 128 | Positive bounded number of nav-area candidates. |
| `virtualWalkersPerZombie` | 4 | Active-cell population density: one live NPC per four virtual walkers. |
| `reconcileInterval` | 0.25 | Matches the worker tick; no faster reconciliation loop. |
| `requestRetrySeconds` | 1 | Positive cooldown after a rejected or empty request. |
| `despawnGraceSeconds` | 10 | Positive delay before relevance-based despawn. |

Server admins can change `zombiesim_walker_active_cap` and `zombiesim_walker_population_per_zombie` in the Tab radial menu's Options panel. The panel reads the authoritative server values and applies both settings together; non-admin players can view but not change them.

## Ticket Contract: Native API v3

API v3 retains the Phase 2 worker and ticket surface, and adds server-only checkpoint export/import plus nonblocking periodic export request/poll. A host rejects an incompatible module version rather than guessing at a partial contract.

All identifiers are exact unsigned 64-bit values represented in Lua as two unsigned 32-bit fields: `idLow` and `idHigh`. Neither ticket nor horde identifiers may be sent as a single Lua number. `requestId` uses the same pair form and is generated by the server controller.

| Lua function | Arguments | Result | Semantics |
| --- | --- | --- | --- |
| `RequestSpawnTickets` | `cellId`, `maximumCount`, `requestIdLow`, `requestIdHigh` | `true` or `false, error` | Queues a bounded reservation request. Replaying the same request id is harmless. |
| `GetTicketSummaries` | none | array or `nil, error` | Returns a synchronized published snapshot only; it never mutates core state. |
| `AcknowledgeTicket` | `ticketIdLow`, `ticketIdHigh` | `true` or `false, error` | Queues a transition from reserved to materialized after entity creation succeeds. |
| `RejectTicket` | `ticketIdLow`, `ticketIdHigh` | `true` or `false, error` | Queues a transition from reserved to rejected after placement fails. |
| `ResolveTicket` | `ticketIdLow`, `ticketIdHigh`, `killed` | `true` or `false, error` | Queues resolution of a materialized ticket as killed or despawned. |

Each ticket summary has `TicketIdLow`, `TicketIdHigh`, `HordeIdLow`, `HordeIdHigh`, `CellId`, `LocalU`, `LocalV`, `State`, and `ExpiresAtTick`. `State` is one of `reserved`, `materialized`, `rejected`, `expired`, `killed`, or `despawned`; the adapter also publishes totals by state through diagnostics.

### State Transitions

| State | Entered by | Population effect |
| --- | --- | --- |
| `reserved` | Accepted request | Remains virtual but unavailable to another reservation. |
| `materialized` | Acknowledgement after entity creation | Population total is unchanged. |
| `rejected` | Failed placement before acknowledgement | Reservation returns to the virtual horde. |
| `expired` | Worker after the reservation deadline | Reservation returns to the virtual horde. |
| `killed` | Lethal materialized entity resolution | Permanently removes one virtual walker. |
| `despawned` | Intentional materialized entity cleanup | Returns one walker to its source horde. |

Terminal commands are idempotent within the retained ticket-history window. The Phase B implementation must bound terminal history while keeping duplicate acknowledgement and resolution harmless during that documented window.

## Materialization Rules

The Phase D controller requests tickets only for the active logical cell and only while slots are available. Its population target is `ceil((ambient + reserved + materialized) / virtualWalkersPerZombie)`, capped by the server's active NPC limit. It runs at the worker's 0.25-second cadence, keeps one outstanding request, and uses an exact `ticketIdHigh:ticketIdLow` registry to prevent duplicate entities. It converts `LocalU` and `LocalV` to a local candidate, samples nearby loaded nav areas, validates floor, hull clearance, player exclusion, separation from existing Walker zombies, line-of-sight safety, and the configured player relevance radius, then creates the entity. It acknowledges only after a valid entity records its exact ticket id. Checkpoint metadata persists the next request identifier so a restored controller does not replay an already fulfilled native request.

No valid loaded navmesh, map shutdown, profile change, absent eligible player, failed entity creation, or invalid placement is a no-spawn condition. Lua rejects unusable reservations and removes zombies that remain outside the relevance radius for the configured grace period; it never alters virtual population directly. On shutdown it saves a native checkpoint before the worker stops; compatible state persists across level changes and restarts.

## Diagnostics

Use server-admin commands only:

```text
zombiesim_walker_smoke
zombiesim_walker_status
zombiesim_walker_cell <worldX> <worldY>
zombiesim_walker_noise <strength> <radius> [durationTicks]
zombiesim_walker_tickets
zombiesim_walker_ticket_request [count]
zombiesim_walker_ticket_ack <ticketIdLow> <ticketIdHigh>
zombiesim_walker_ticket_reject <ticketIdLow> <ticketIdHigh>
zombiesim_walker_ticket_resolve <ticketIdLow> <ticketIdHigh> <killed:0|1>
zombiesim_walker_ticket_probe
zombiesim_walker_zombie_spawn_test
zombiesim_walker_zombie_status
zombiesim_walker_zombie_kill_test
zombiesim_walker_zombie_despawn_test
zombiesim_walker_materializer_status
zombiesim_walker_materializer_request [count]
```

`zombiesim_walker_status` writes `DATA/zombiesim/walker_status.json`. `zombiesim_walker_tickets` writes ticket-state counts and summaries to `DATA/zombiesim/walker_tickets.json`; it is diagnostic-only and never sent to clients. The `ticket_*` commands are admin-only Phase B probes that use the same server wrappers as the future materializer. `zombiesim_walker_ticket_probe` performs one request, acknowledgement, and despawn sequence across worker ticks and writes its result to `DATA/zombiesim/walker_ticket_probe.json`.

`zombiesim_walker_zombie_spawn_test` is the manual Phase C path. It reserves one ticket in the active ordinary cell, chooses a nearby loaded nav area from the ticket's local coordinate, rejects placement when it lacks hull clearance, player distance, or occlusion, then spawns and acknowledges one `zn_walker_zombie`. It writes the result to `DATA/zombiesim/walker_zombie_spawn.json`. `zombiesim_walker_zombie_status` records the entity and its published ticket state in `DATA/zombiesim/walker_zombie_status.json`. The kill and despawn test commands respectively use normal lethal damage and `Remove()`, with each terminal queue result written to `DATA/zombiesim/walker_zombie_lifecycle.json`.

`zombiesim_walker_materializer_status` writes `DATA/zombiesim/walker_materializer_status.json` with enablement, active count/cap, active cell, outstanding request, and controller error count. `zombiesim_walker_materializer_request [count]` asks the active controller for up to its configured per-tick request limit; it does not create entities through a separate test path.

### Phase E AI Controls

Each live Walker performs target scans at most once every 0.5 seconds, staggered by entity id. An eligible player within 2400 units is a pursuit target even before direct line of sight is available; melee still requires both line of sight and the 64-unit attack range. Paths are reused and recomputed only when the goal moves 96 units, becomes invalid, or reaches the 0.75-second refresh interval. An invalid path or stuck event enters a two-second retry cooldown. `zombiesim_walker_zombie_status` records every active entity's state plus aggregate target scans, path computes, path failures, stuck recoveries, and attacks in `DATA/zombiesim/walker_zombie_status.json`.

## Build And Test

Run from `bin/walker-simulator`:

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
ctest --preset test-mingw-debug --output-on-failure
```

For the optional Win64 module:

```powershell
cmake --preset mingw-gmod-module-debug
cmake --build --preset build-mingw-gmod-module-debug
.\scripts\install-local-win64.ps1 -GarrysModRoot "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

After installation, run `zombiesim_walker_smoke`, load `zn_preview`, then use `zombiesim_walker_status` and `zombiesim_walker_noise`. Record each live test in [alpha_2_test_log.md](alpha_2_test_log.md).

## Known Limitations

- The GMod adapter is API v2: it exposes tickets; manual Phase C materialization remains server Lua only.
- Phase E AI controls are implemented but need live pursuit, melee, path-failure, and capped-load evidence before they are accepted.
- Walker state is discarded on `changelevel`, restart, and empty-server reconnect.
- Navigation meshes must be usable before NextBots materialize. Some generated recipes have invalid player-start placement and are excluded from the initial proof until their source templates are corrected.
- The `zn_road_connection` entity is planner metadata that currently leaks from the multi-tile commercial VMF into runtime maps. It is unrelated to Walker authority and is deferred for generator cleanup.
- Workshop uploads cannot distribute the native DLL; it is installed separately under `garrysmod/lua/bin`.