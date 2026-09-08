# Physics Upgrade Plan

## Decision

Treat VPhysics Jolt (Volt) as an optional server and client engine capability, not as a gamemode dependency. Gameplay must remain correct on stock Garry's Mod VPhysics; Jolt enables denser and longer-lived visual physics only after an explicit compatibility probe passes.

Volt replaces the engine `IPhysics` implementation through a VPhysics binary and CPU-dispatch wrapper. It is not an addon Lua API. Its published feature set includes ragdolls, constraints, touch callbacks, prop damage/breaking, wheeled vehicles, player controllers, and multithreaded high-object simulation. Known gaps include breakable constraints and raycast vehicles, and upstream warns that engine branches can have undiscovered compatibility problems.

## Principles

- Keep combat damage, loot, XP, hit validation, and zombie death state server-authoritative and independent of the physics backend.
- Use the same gameplay outcome on stock physics and Jolt. Jolt changes fidelity, density, and visual persistence, not rules or rewards.
- Give every enemy drop to a dedicated persistent loot-bag entity, separate from decorative ragdolls and detached limb entities.
- Never require a player to install engine replacements to join an ordinary server. Server operators opt in; clients without compatible assets receive conventional death effects.
- Begin with zombie death ragdolls. Do not couple dismemberment to the first physics milestone.
- Measure active physics objects and cleanup behavior before raising gore or ragdoll limits.

## Capability Contract

Create a server-owned `ZM_Physics` service with one replicated capability snapshot:

```lua
{
    backend = "stock" | "jolt",
    ragdolls = boolean,
    dismemberment = boolean,
    debrisBudget = number,
    reason = string
}
```

### Detection

1. Add a server convar such as `zombiesim_physics_mode` with `auto`, `stock`, and `jolt` values.
2. `stock` always selects the conservative profile.
3. `auto` performs a capability probe owned by a future native helper module. It must identify the loaded VPhysics provider/version, not infer Jolt from a client convar or a Lua file name.
4. `jolt` must fail closed to stock when the probe is unavailable, mismatched, or the startup smoke test fails.
5. Replicate only the resolved profile to clients using a versioned net message. Clients use it for effects and UI only; they never decide the server profile.

### Stock Profile

- One brief corpse ragdoll or static corpse prop per zombie, capped per cell and globally.
- No client-critical detached limbs, high-count debris, or physics-driven damage.
- Deterministic cleanup by age, distance, and active-count ceiling.
- Enemy rewards are stored in `zn_loot_bag`; player death inventory uses a separately marked recovery bag.

### Jolt Profile

- Higher server-controlled active ragdoll and debris budgets, tuned per map/cell population.
- Optional impact impulse, collision sound, drag/settling behavior, and short-lived detached cosmetic limbs.
- Dynamic budget reduction when measured active physics count or frame/tick budget is exceeded.
- All physics objects remain non-authoritative cosmetic representations; their removal cannot destroy loot bags or block navigation.

## Loot Bag Entity

Create a server-owned `zn_loot_bag` entity for all enemy drops before adding dismemberment. A bag represents the reward, while the zombie body only represents the death animation and visual aftermath.

### Contract

- At most one bag is created for a zombie death, after the server resolves XP and the loot table.
- The bag owns a server-side, versioned loot record; item contents are never attached to, inferred from, or stored in a ragdoll.
- It records source type, death time, originating logical cell, owner/party access policy, and an optional expiry timestamp.
- It has a stable interaction prompt, a compact world model, and a compass/map marker only when the design calls for one.
- It is collision-safe: it cannot block transition triggers, doors, paths, or a survivor's movement. It may use light visual settling, but must not depend on physics to remain reachable.
- The interaction request validates distance, line of sight where appropriate, access policy, and that the bag has not already been claimed.
- Empty bags are removed immediately; expired bags are removed by the same server cleanup service that maintains zombie and cosmetic-object limits.

### Death Sequence

1. Server applies lethal damage, awards XP once, and resolves the loot table.
2. Server spawns `zn_loot_bag` at a validated ground position and writes its loot record.
3. Server emits a visual death payload for the ragdoll/dismemberment system.
4. Clients render the selected stock or Jolt visual profile independently of bag pickup and persistence.
5. Cosmetic ragdolls and limbs may expire at any time. The loot bag persists under its own gameplay rules.

### Player Death

The recoverable player-death inventory described in the game design should use the same bag abstraction with a distinct `recovery` source type and map marker. This avoids two competing inventory-container systems and makes body recovery independent of ragdoll cleanup.

## Gameplay Milestones

### 1. Foundation: Zombie Lifecycle

Create a server-owned zombie abstraction before enabling physics:

- Spawn/despawn ownership, health, state, target selection, and cell association.
- Damage ingestion that records hit group, damage type, force, attacker, and lethal state.
- A death event carrying a compact, versioned visual payload: model, skin/bodygroups, transform, force, damage type, hit group, and death variant.
- A single cleanup policy for zombies, loot bags, ragdolls, limbs, and debris.

Validation: scripted zombie spawn/despawn soak test; all zombie deaths award exactly once and release every entity reference.

### 2. Stock Ragdoll Baseline

- On lethal death, create a server ragdoll using the standard Garry's Mod path.
- Apply a clamped impulse from the recorded damage force.
- Enforce a global cosmetic-ragdoll limit and a per-cell limit; remove oldest distant ragdolls first.
- Spawn `zn_loot_bag` when the resolved loot table is non-empty; never make the ragdoll the inventory container.

Validation: twenty simultaneous deaths, level transition while bags and ragdolls exist, reconnect, and pickup from a persistent bag after the visual ragdoll expires.

### 3. Damage Zones and Dismemberment

- Add explicit per-zombie model profiles mapping supported hit groups/bones to detachable limbs.
- Begin with one known zombie model and only server-validated lethal limb conditions.
- Spawn visual limbs only after the server resolves the death or dismemberment state. Replicate an event, never a client-authored result.
- Retain a stock fallback: bodygroup/submodel change, decal, and particle/sound without detached physics.
- Do not promise support for every workshop model. Unsupported models use ordinary ragdolls.

Validation: profile test matrix for every supported model, all hit groups, blast/fire/bullet damage types, and corpse cleanup limits.

### 4. Jolt Enhancement

- Enable the Jolt profile only after the stock lifecycle is stable.
- Raise physics budgets gradually with server convars, starting from values proven in a dedicated test map.
- Add collision-impact effects and short-lived limb/debris physics only when the object is inside player relevance range.
- Instrument active objects, ragdolls, debris, oldest age, cleanup count, and physics-related tick cost; emit summaries to the existing development command bridge.
- Add an administrator command to dump the resolved profile and current physics budget telemetry.

Validation: mixed combat soak, map transitions, safe-zone transitions, low-spec clients, and a 30-minute dedicated-server run with forced cleanup thresholds.

## Networking and Security

- Damage is resolved exclusively on the server. Clients may request attacks but never declare a dismemberment outcome.
- Validate every networked visual event: source entity, model profile id, event type, and bounded force values.
- Use per-client relevance/range filtering for cosmetic events rather than broadcasting dense debris globally.
- Cap event rate per zombie and per player to prevent weapon spam creating unbounded physics objects.
- Persist only loot-bag records and inventories. Never serialize decorative limb/ragdoll transforms as player state.

## Content and Map Considerations

- Test every generated recipe category and safe-zone map for ragdoll settling, transition triggers, narrow entrances, and body-blocking.
- Ragdolls, limbs, and loot bags must use collision groups that cannot prevent map transitions or trap survivors.
- Generated maps need no Jolt-specific VMF changes in the first phase. If physics surfaces are later tuned, modify authored source assets and validate preview first.
- Maintain a dedicated physics test map or developer-zoo fixture with ramps, stairs, vehicles, doors, water, transition triggers, and mass corpse scenarios.

## Rollout Gates

1. Ship zombie lifecycle and stock ragdoll baseline behind `zombiesim_physics_mode stock`.
2. Add bounded dismemberment with stock visual fallback.
3. Build and run the Jolt capability probe on supported server environments.
4. Enable `auto` only after parity tests show no gameplay divergence from stock mode.
5. Keep a kill switch that immediately resolves to the stock profile on startup or after a configured error threshold.

## Binary Modules

### Scope

A native Garry's Mod binary module can safely provide narrowly scoped capability detection, telemetry, profiling, or bespoke simulation helpers exposed through a small Lua API. It should not replace an engine DLL, reach into undocumented memory, or depend on private ABI assumptions for routine gamemode features.

Volt itself is an engine VPhysics replacement. Its upstream GMod branch has branch-specific `GAME_GMOD` interface overrides and the project states that the required GMod/CS:GO-derived headers cannot be redistributed. Building or distributing a modified VPhysics binary therefore has a materially different support, licensing, compatibility, and update burden from an ordinary GMod Lua binary module.

### Module Boundaries

Proposed `gm_zombiesim_physics` responsibilities:

- `GetBackendInfo()` returns a read-only backend identifier/version or `unknown`.
- `RunPhysicsSmokeTest()` creates and cleans up a bounded test scenario at server startup or on administrator demand.
- `GetTelemetry()` returns active-object and timing counters collected from supported public interfaces.
- Optional future helper: deterministic, self-contained cosmetic fragment simulation that does not patch engine interfaces.

Keep this module optional. Lua must behave correctly when it is absent and should use `pcall(require, "zombiesim_physics")` only during one-time capability initialization.

### Build and Distribution Plan

1. Establish supported targets first: current 64-bit Windows dedicated/server client environment and any required Linux server target.
2. Obtain the current official Garry's Mod module SDK/toolchain and document exact branch, compiler, architecture, and ABI requirements in a separate build repository.
3. Start with a read-only diagnostic module. Its first acceptance test is detecting itself and returning a fixed version string; it must not touch physics.
4. Add backend identification only through supported interfaces or clear operator-provided configuration. If a reliable API is unavailable, report `unknown` and choose stock mode.
5. Create CI builds, symbol-stripped release artifacts, version manifests, checksums, and server startup validation.
6. Test each binary against the currently supported GMod branch after game updates. Pin releases, retain rollback binaries, and never auto-install into Garry's Mod's `bin` directory.

### Volt Evaluation Harness

Do not build ZombieSim around Volt until a separate disposable test installation passes:

- Stock baseline versus Volt comparison on the exact GMod branch and architecture.
- Physics smoke map: ragdolls, constraints, triggers, props, doors, player movement, vehicles used by the gamemode, and map transitions.
- Soak scenarios: large zombie deaths, map changes, safe-zone entry/exit, reconnects, and server restarts.
- Compatibility audit of current Volt limitations: no breakable constraints and incomplete/janky raycast vehicles.
- Crash recovery and rollback: remove/restore the replacement only while the game is stopped; restart and run the smoke map before admitting players.

Do not distribute or modify Volt binaries in this gamemode repository. Keep any engine-binary evaluation in a separate operator-managed project with its upstream license and release process reviewed first.

## Reference Findings

- Volt exposes an `IPhysics` implementation and creates `JoltPhysicsEnvironment` instances; it is beneath Lua-level gameplay code.
- Its wrapper chooses `vphysics_jolt_sse2`, `vphysics_jolt_sse42`, or `vphysics_jolt_avx2` according to CPU support.
- The project implements Source collision interfaces, ragdoll constraints, object callbacks, physics tracing, surface properties, and simulation settings, which explains why it can substitute VPhysics instead of simply adding a Lua feature.
- The upstream build guide targets Source SDK 2013/Alien Swarm with C++20. Windows guidance references Visual Studio 2022 and the Windows 11 SDK; this does not establish a supported GMod module build pipeline.
