# Walker Checkpoint Persistence Plan

## Objective

Preserve the authoritative Walker state across `changelevel` and server restart so a zombie resolved as `killed` remains removed after the next worker start. Persist only native Walker state; live NextBots remain map-local and are never serialized.

## Verified Starting Point

- `WalkerSimulator::ExportCheckpoint()` and `ImportCheckpoint()` already serialize the deterministic core state, including hordes, tickets, terminal ticket outcomes, attractors, request ids, and tick state.
- Core import validates checkpoint format, graph revision, world seed, Walker-config hash, payload length, and payload checksum.
- `walker_core_tests` already proves checkpoint round-trip determinism and corrupt-checkpoint rejection.
- `WalkerWorker` serializes checkpoints on its worker thread after a tick. Synchronous export is reserved for explicit saves/shutdown; periodic export is request/poll based and never waits on the game thread.
- API v3 exports checkpoint methods and `sv_walker_sim.lua` restores profile-scoped state before starting the worker.

## Persistence Contract

1. Checkpoints are profile-scoped in the server SQLite `walker_checkpoints` table. The opaque native checkpoint is Base64-encoded; metadata and rejection information are retained in the same row. `DATA/zombiesim/walker_checkpoint_status.json` remains the diagnostic artifact.
2. A checkpoint is accepted only when core validation confirms it belongs to the current runtime world revision, seed, and Walker configuration.
3. A successful kill is durable after its queued resolution has been applied and a later checkpoint completes.
4. Reserved tickets survive exactly as the core defines. Imported materialized tickets are not recreated as entities; they are reconciled as `despawned` before automatic materialization begins.
5. A missing, corrupt, outdated, or incompatible checkpoint starts a clean world and records the reason. It must never block map loading or overwrite the rejected artifact.
6. Persistence is server-only. Clients receive the normal read-only population and map messages only.

## Phase P1: Worker-Safe Checkpoint Operations

1. Add `ExportCheckpoint` and `ImportCheckpoint` methods to `WalkerWorker`.
2. Implement export as a worker-owned request, not a direct call from the game thread:
   - Add a monotonically increasing checkpoint request sequence, completed sequence, result buffer, error string, and condition variable under the existing worker mutex.
   - `ExportCheckpoint` queues one request and waits for the worker to service it at the end of a tick, after submitted commands have been applied and before the new snapshot is published.
   - The worker copies `WalkerSimulator::ExportCheckpoint()` into the result buffer, completes the sequence, and notifies the caller.
   - Bound the wait to a little over one worker interval. Return a clear timeout/fault/stopped error rather than blocking the game thread indefinitely.
3. Permit import only in `GraphReady` state, after `LoadWorldJson` and before `Start`. Import updates the published snapshot and clears pending commands without resetting deterministic core state.
4. Add explicit lifecycle errors for import while running, export before world load, export during stop, and checkpoint size above the configured bound.

## Phase P2: Native Module API v3

1. Bump `kWalkerApiVersion` from 2 to 3. The Lua host must require v3 rather than attempting partial persistence support.
2. Export two narrow server-only functions:
   - `ExportCheckpoint() -> checkpointBytes | false, error`
   - `ImportCheckpoint(checkpointBytes) -> true | false, error`
3. Validate the input is a non-empty byte string below a conservative maximum such as 8 MiB before calling the worker.
4. Confirm the GMod module API supports a length-aware string push for byte buffers. If raw binary strings are not safe through that interface and `file.Write`, encode/decode Base64 in native code with the same decoded-size bound.
5. Keep the new methods out of clients and preserve the existing queued mutation model.

## Phase P3: Server Checkpoint Store And Restore

1. Add `WalkerSim:LoadCheckpoint(profile)` and `WalkerSim:SaveCheckpoint(reason)` in `sv_walker_sim.lua`.
2. Use the validated profile identifier as the SQLite key and write metadata containing profile, graph revision hash, state hash, tick, saved time, byte length, save reason, and the next server ticket-request identifier.
3. Use `INSERT OR REPLACE` for one profile row; rejected checkpoints remain marked with a rejection timestamp and reason instead of being retried on every map load.
4. During `InitializeForActiveProfile`, load the world JSON, read the profile checkpoint if present, import it while the worker is `GraphReady`, then start the worker. Report restore state in `walker_status.json` and a dedicated `walker_checkpoint_status.json` diagnostic.
5. On import failure, mark the row rejected and start a clean worker. Never repeatedly retry the same bad checkpoint every map load.
6. Save periodically only after the native state hash changes, initially every two seconds, via nonblocking worker export request/poll. Also save synchronously during orderly shutdown before `native.Stop()`.

## Phase P4: Map-Transition Materialization Reconciliation

1. Set `WalkerSim.IsShuttingDown` before removing controller entities. Their `OnRemove` handlers then record skipped teardown resolution rather than queueing commands into a worker about to stop.
2. Save the checkpoint while the worker still contains the materialized tickets. This retains all previously killed terminal tickets and avoids losing in-flight state to a shutdown race.
3. After import and worker start, keep `ZM_WalkerMaterializer` disabled until a restore-reconciliation timer observes the first published ticket snapshot.
4. For every imported ticket still in `materialized`, queue one idempotent `ResolveTicket(..., false)` command. Wait for a later snapshot showing no imported materialized tickets, then enable the controller.
5. Do not recreate a NextBot from an imported materialized ticket. Once it becomes `despawned`, normal population-targeted materialization may issue fresh tickets for the new loaded cell.
6. If restore reconciliation cannot complete before a bounded timeout, retain the controller disabled, preserve the diagnostic, and allow an admin-only retry command. This avoids duplicate population or unowned live tickets.

## Phase P5: Diagnostics And Operator Controls

1. Add `zombiesim_walker_checkpoint_status` with checkpoint path, restore/save result, profile, graph hash, state hash, tick, byte length, last save reason, and reconciliation state.
2. Add admin-only `zombiesim_walker_checkpoint_save` and `zombiesim_walker_checkpoint_clear <profile>` commands. Clearing requires an explicit profile argument and only removes that profile's SQLite row.
3. Extend `zombiesim_walker_status` with `checkpointLoaded`, `checkpointStateHash`, `lastCheckpointTick`, and `lastCheckpointError`.
4. Write `DATA/zombiesim/walker_checkpoint_status.json` after every load, save, rejection, and restore-reconciliation transition.

## Phase P6: Tests And Acceptance Evidence

1. Extend `walker_core_tests` with a killed-ticket checkpoint test: materialize one ticket, resolve it as killed, export/import, and assert the restored total population remains lower by one and the ticket remains terminal `killed`.
2. Exercise adapter/worker export, import, and lifecycle behavior through API v3 module build and live server diagnostics; a dedicated worker unit-test harness remains a future coverage improvement.
3. Rebuild both the core and Win64 module, then run the existing CTest preset and module build preset.
4. Live proof on preview:
   - Record baseline population and state hash.
   - Kill one materialized zombie and wait for its ticket to publish as `killed`.
   - Confirm the periodic checkpoint has a later tick and records the reduced population.
   - `changelevel` to a second ordinary preview cell, then confirm the restored worker retains the reduced total and the killed ticket is not rematerialized.
   - Restart the local server and repeat the same assertion.
   - Force a configuration or runtime-world revision mismatch; confirm the checkpoint is rejected safely and the original checkpoint is retained for inspection.
5. Record each outcome and artifact path in `docs/alpha_2_test_log.md` before declaring persistence accepted.

## Non-Goals

- Persisting a live NextBot, its exact animation/path, or player target across maps.
- Restoring a materialized ticket as a new entity without placement validation.
- Cross-profile checkpoint sharing.
- Attempting to recover a checkpoint after a process crash before the next periodic save.

## Implementation Order

1. P1 worker-safe export/import and tests.
2. P2 API v3 plus module rebuild.
3. P3 profile-scoped store/restore and status diagnostics.
4. P4 controller restore reconciliation.
5. P5 commands and operator documentation.
6. P6 live `killed` persistence proof across both `changelevel` and restart.

This order preserves the current invariants: the native core remains authoritative, no game-thread code mutates its state directly, and map-local NextBots never create duplicate or permanently lost walkers.

## Implementation Result

Implemented and validated on 2026-09-10. A killed ticket reduced preview population to `80,999`; the same compatible checkpoint restored across both `changelevel` and a full local Garry's Mod restart. The restored worker reported zero API errors and zero dropped ticks, and the materializer resumed from the active-cell target after reconciliation.