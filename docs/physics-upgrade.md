# Physics Upgrade Plan

## Decision

Build one small, backend-neutral death-effects layer. Stock Garry's Mod VPhysics is the default. A server operator can explicitly choose Jolt only after installing Volt outside this repository and validating it in a disposable Garry's Mod installation.

Volt replaces the engine's VPhysics binary; it is not a normal Lua addon. Do not make individual-player gameplay depend on whether a client has it installed. The server owns authoritative physics, loot, damage, and XP, so every player must receive the same gameplay result.

The first release needs no custom C++ module, engine patching code, automatic installer, or broad physics rewrite. It needs a loot bag, an ordinary ragdoll path, bounded cleanup, and one optional enhanced visual profile.

## Minimal Physics Profile

Use one server convar with two values:

```text
zombiesim_physics_mode stock | jolt
```

- `stock` is the default and always works.
- `jolt` is an operator opt-in. On startup, it must check that `GetConVar("vjolt_substeps")` exists on the server, then fall back to `stock` with a clear warning when it does not.
- This convar check is a guard, not a promise that every client has a matching replacement. Do not enable Jolt mode on a multiplayer server until the exact server/client setup has passed the smoke test.
- A future client-only check may use the same convar to enable extra local particles or cosmetic limb props for that client. It must never alter networked entities, loot, damage, or XP.

### Stock

- Spawn one ordinary zombie ragdoll with a clamped death impulse.
- Spawn `zn_loot_bag` for resolved loot.
- Remove visual ragdolls after a fixed lifetime and active-count limit.
- No detached limbs or physics-driven damage.

### Jolt

- Keep the exact same loot bag, damage, XP, and cleanup rules.
- Permit a higher ragdoll budget, stronger cosmetic impulse, and a small number of short-lived detached limbs for explicitly supported zombie models.
- If the Jolt guard or smoke test fails, resolve immediately to the stock profile.

## Loot Bag Entity

Create a server-owned `zn_loot_bag` entity for all enemy drops before adding dismemberment. A bag represents the reward, while the zombie body only represents the death animation and visual aftermath.

### Contract

- Spawn at most one bag after the server resolves a zombie's loot table.
- The bag owns its item table; a ragdoll or detached limb never holds loot.
- `Use` validates that the bag still exists, is in range, and has not already been emptied.
- Use a non-blocking collision group. An empty or expired bag is removed.
- Start with normal enemy bags only. Reuse the same entity for player recovery bags later rather than designing a second container system now.

### Death Sequence

1. Server resolves lethal damage and loot once.
2. Server spawns `zn_loot_bag` at a validated ground position.
3. Server creates the selected visual death effect.
4. The bag remains until collected or expired; ragdolls and limbs can disappear at any time.

## First Implementation

1. Create `zn_loot_bag` and test manual spawn, pickup, empty-bag removal, and map-transition safety. This is the only persistent gameplay entity.
2. Add one reusable death-effects helper for future zombies: create a standard ragdoll, apply a bounded impulse, and remove it after a short lifetime or when the global limit is reached.
3. Add the explicit `jolt` branch to that helper. It may add a stronger impulse and up to two short-lived visual limbs for one supported zombie model. Every other model uses the normal ragdoll.

Do not build an independent zombie framework, hit-zone framework, telemetry system, or generic model-profile registry before one real zombie and one bag can complete this path. Add them only when the first working model exposes a concrete need.

## Safety Limits

- The server decides lethal damage, XP, loot, ragdoll creation, and cleanup. Clients do not decide dismemberment.
- Loot bags, ragdolls, and limbs use non-blocking collision behavior and must never prevent transitions or movement.
- Every visual object has a short lifetime and a global cap. When the cap is full, remove the oldest visual object rather than spawning another.
- No physics object can contain loot or survive as player state.
- The first Jolt test is a disposable local/server installation: kill a small group of zombies, collect every bag, change maps, then restart. A failure means switch back to `stock`; no recovery logic is required beyond that.

## Binary Modules (Deferred)

Do not build a custom binary module for the first physics upgrade. Volt already replaces the engine `IPhysics` implementation and ships as an operator-installed game binary, so a second module would add risk without enabling the initial loot-bag/ragdoll feature.

Revisit a read-only `gm_zombiesim_physics` helper only if a proven future need cannot be met in Lua, such as reliable backend telemetry. It must be optional, use supported module interfaces, and never patch engine memory or install/replace game binaries.

## Confirmed Volt Facts

- Volt is an engine-level VPhysics replacement, not a Lua package; its wrapper selects CPU-specific binaries.
- The upstream release installs by replacing files in the Garry's Mod game root and exposes `vjolt_*` console variables, including `vjolt_substeps`.
- Volt supports ragdolls and is designed for many active objects, but upstream documents engine-branch compatibility risk. Treat `jolt` as an opt-in enhancement rather than a dependency.
