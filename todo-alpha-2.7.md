# Alpha 2.7: Items, Loot, Enemies, and Bosses

## Source of Truth / Working Rules

- This file is the authoritative task tracker for active Alpha 2.7 work.
- Treat this document as the source of truth for current Alpha 2.7 milestones, status, and next actions.
- Historical notes in `docs/todo-alpha-2.6.md`, `docs/alpha_2_plan.md`, `docs/alpha_2_test_log.md`, older local TODOs, and prior agent notes are context only unless their content is explicitly copied here and updated.
- Complete phases in dependency order unless a phase explicitly identifies independent work. Update this file as work is completed; do not infer completion from code or historical plans alone.
- The Alpha 2.7 prototype is the design brief, not an implementation specification where it contains contradictions or unresolved policy. Record and resolve those decisions before dependent implementation.

## Phase A: Design and Scope (Complete)

- Read `docs/item_and_loot_system_prototype.md` and digest its complete scope.
- Create this phased master implementation plan and archive the Alpha 2.6 tracker as `docs/todo-alpha-2.6.md`.
- Review the prototype critically. Resolve the following before they become implicit implementation rules:
  - Separate player level, item level, cell danger, enemy danger eligibility, and loot rarity. The examples use cell danger both as world progression and as item-level uplift, but provide no agreed formula or caps.
  - Define the meaning and bounds of `minAttributes`/`maxAttributes`. The prototype describes these once as attribute counts and elsewhere as maximum attribute values; these are separate concepts and need separate schema fields.
  - Define stat units and directions per attribute. “More firing speed,” “reload speed,” “range,” and “mobility” can mean either a larger numeric value or a shorter time/lower penalty; no generic scale can safely apply to all weapon classes.
  - Define enemy spawn semantics independently of loot weights. The examples call percentages “rarity,” include min/max values in apparently reversed directions, and do not specify whether each eligible enemy is rolled independently, whether one is selected, or how total spawn probability is capped.
  - Distinguish weighted selection from probability thresholds. Loot-table weights are relative to the current table total, while `entity_loot`'s second value is described as a chance; they are not the same quantity and must use separate, clearly named fields.
  - Define loot-group composition and overrides: order, duplicate-item behavior, recursive-cycle detection, override merge depth, and whether nested groups form one combined pool or sequential rolls.
  - Define boss uniqueness/cooldown ownership, persistence, map-marker replication, and what happens when the world profile changes or a boss is unloaded. “Random cell” and `maxActiveWorldCount` require a server-authoritative world scope.
  - Resolve the loot refresh rule. “Loot does not respawn” conflicts with a hard five-minute timer before a cell can generate spots again. Choose whether the timer refreshes eligible spot locations, spot availability, or the loot contents, and define persistence/restart behavior.
  - Resolve death and inventory semantics against the GDD: the GDD describes carried items being lost on death and a recoverable body, while the prototype's loot popup accepts items into inventory without specifying carried-versus-saved state. Do not silently persist a new permanent inventory model.
  - Keep multiplayer authority server-side. Clients may request interactions, but must not choose loot, item attributes, boss state, currency, or inventory outcomes.
  - Treat workshop item/class registration as a later extension point with validation and trust boundaries; do not execute arbitrary addon-supplied static data or Lua as part of JSON loading.
  - Scope the initial vertical slice to the requested test content: `itemBandage`, `weaponMeleeCrowbar` / `weapon_zn_melee_crowbar`, and `weaponHandgun9mm` / `weapon_zn_handgun_9mm`. Armor, clothing, crafting, market services, currency, and broad content catalogs remain separate follow-up scope unless promoted here.

## Phase B: Data Contracts and Runtime Registries (Not Started)

- Define valid JSON schemas and examples for item definitions, loot groups, entity-loot rules, enemy definitions, environment/cell enemy spawn groups, and boss spawn definitions. Add recipes only if a crafting slice is explicitly approved.
- Place shipped runtime data under `content/data_static/`; keep schemas, authoring guidance, and validation fixtures in developer-owned locations. Preserve the repository's existing content/output boundary.
- Define normalization and validation contracts: required fields, defaults, bounds, stable IDs, supported item/enemy types, referenced SWEP/entity classes, model paths, icons, and profile compatibility.
- Build a server-owned data loader with deterministic load order, actionable diagnostics, safe reload semantics, and no partial registry replacement on invalid data.
- Resolve loot group references and overrides into validated runtime pools. Detect missing references, duplicate/cyclic group composition, invalid item IDs, and impossible/empty rolls; retain source paths in diagnostics.
- Add the first admin/developer commands: reload static data and validate all registries. Commands must report errors without mutating a previously valid live registry.
- Acceptance: valid fixtures normalize predictably; malformed JSON, bad bounds, missing references, cycles, and bad model/class references fail with useful diagnostics; reload failure leaves the previous registry available.

## Phase C: Item Instances, Requirements, and Persistence (Not Started)

- Define the item-definition versus item-instance boundary. Instances need stable IDs and only instance-specific state such as level, generated attributes, mastercraft status, durability when supported, and stack count; definitions remain immutable.
- Define canonical stack compatibility, stack limits, unique-instance handling, item value calculation, and safe serialization/versioning before adding persistent inventory writes.
- Integrate inventory persistence with existing profile-scoped player data without changing Alpha 2.6 player/world state behavior. Add additive migrations and explicit failure handling; avoid packing unbounded inventory JSON into existing player rows.
- Add server APIs for granting, removing, counting, splitting/merging, and validating items. Mutations must be atomic from the caller's perspective and reject invalid amounts or unknown definitions.
- Define requirement checks using existing `Player.Attributes`, `Level`, and supported job data. The prototype's `GetStat` and `GetJobRole` calls are not current established APIs; implement clear adapters only after the job/role model is specified.
- Acceptance: inventory survives reconnect and profile separation; invalid writes do not consume items; stack limits and unique weapon instances are enforced; migration tests preserve existing player records.

## Phase D: Item Scaling and Weapon Vertical Slice (Not Started)

- Specify a bounded deterministic item-generation contract: input definition, rolled item level, normalized danger, mastercraft flag, and RNG seed/state produce a valid immutable instance. Keep attribute count distinct from attribute score/value.
- Decide how player level and cell danger combine to select item level, including minimum/maximum behavior, rounding, and whether a high-level player in a low-danger cell can ever receive a high-level item. Avoid the prototype's ambiguous “extra levels” examples until one formula is approved.
- Define per-type attribute ranges and gameplay mapping. Scale only supported weapon behaviors; do not expose attributes that the SWEP cannot actually apply. Define mastercraft as an explicit exceptional roll with cap behavior and probability controlled by loot data, not an item-definition boolean that accidentally makes every instance mastercrafted.
- Implement item classes/registries for consumable entity items and connect successful use to exactly-once server-side consumption. Use `itemBandage` as the first vertical slice with documented healing and failure conditions.
- Implement base weapon SWEP patterns based on existing local weapon conventions. Add and validate `weapon_zn_melee_crowbar` and `weapon_zn_handgun_9mm`; map item definitions to SWEP classes without deriving executable class paths from untrusted IDs.
- Acceptance: unit/focused tests cover bounds, repeatability for a fixed seed, min/max levels, mastercraft, eligible attributes, and non-applicable attributes; in-game tests prove the crowbar and handgun actually apply rolled values and bandage consumes only after successful use.

## Phase E: Loot Composition and Roll Engine (Not Started)

- Implement pure server-side weighted selection with danger interpolation, zero/invalid-weight handling, and documented behavior for a single-entry table. Use `maxWeight = minWeight` and `maxCount = minCount or 1` fallbacks without mutating source definitions.
- Separate relative item weights from loot-spot activation chance and enemy loot-drop chance. Name and validate each probability/weight field according to its actual semantics.
- Support composed groups and item overrides according to the Phase B contract, including predictable overrides for weights/counts/mastercraft chance and cycle-safe expansion.
- Implement danger-scaled count rolls and item-instance generation, including mastercraft chances. Ensure a boss's forced-mastercraft rule applies only to its resolved reward entries and is not inferred for unrelated loot.
- Add `zn_test_loot_roll <group> <danger>` or equivalent admin command with injectable seed, sample count, and distribution output; report both theoretical weights and observed sample distribution.
- Acceptance: deterministic tests cover endpoints, interpolation, fallback values, composition/override rules, invalid pools, distribution sanity, and no mutation of source tables.

## Phase F: Enemy Definition and Spawn Integration (Not Started)

- Define environment tag matching/fallback and spawn-group resolution. Clarify whether a spawn group is a candidate pool, independent spawn checks, or a capped set of probability rolls; enforce a configured per-cell/per-player spawn budget.
- Validate enemy definitions against registered NPC/NextBot classes and supported health/speed/stat fields. Define interpolation direction and eligibility at danger boundaries; reject reversed or out-of-range min/max values.
- Integrate with `ZM_WalkerSim` as an explicit boundary: current Walker tickets represent generic virtual population spawn tickets and do not carry an enemy-definition ID. Decide whether ticket payload/schema changes are appropriate or whether a separate server-side selector assigns the enemy class after ticket reservation.
- Preserve ticket lifecycle invariants: reject invalid materialization, acknowledge only successfully spawned entities, resolve killed/despawned tickets once, and keep optional native-module absence behavior intact.
- Route successful enemy deaths through server-authoritative XP and loot-drop APIs only after kill ownership, duplicate callbacks, and eligibility are settled.
- Acceptance: fake-ticket and native-optional tests cover enemy selection by danger/environment, no eligible candidate, cap enforcement, rejected spawn, successful kill, duplicate death callback, and despawn without reward.

## Phase G: World Loot Spots and Cell Lifecycle (Not Started)

- Define model matching precedence and entity coverage for `entity_loot` rules (`prop`, `prop_physics`, multiplayer variants, exact model path versus normalized path). Avoid rescanning/activating unsupported or unsafe entities.
- Discover eligible map entities server-side after map initialization, attach validated loot rules, and track spot state without changing authored map assets. Define visual indication and interaction range/line-of-sight rules.
- Implement server-authoritative interaction with a short search delay, one pending claim per spot, range/state revalidation at completion, and an opaque claim token so clients cannot supply the rolled item or replay acceptance.
- Preserve the prototype's reveal-then-accept/decline flow: roll once on the server, show the result to the claimant, grant only on acceptance, and define whether declining consumes the spot. Never reroll on UI reopen or network retry.
- Implement the agreed five-minute cell refresh semantics and persistence policy. Scope timers by logical world cell/profile, not map instance alone; account for cell transitions, map reloads, server restart, concurrent players, safe rooms, and dedicated server lifecycle.
- Acceptance: test duplicate claims, simultaneous players, stale/distant requests, decline/reopen, map cleanup, refresh boundary, and profile isolation; in-game test on real prop models.

## Phase H: Inventory and Loot User Interface (Not Started)

- Replace the placeholder inventory panel with server-synchronized inventory views for stacks and unique equipment; show item name, count/level, mastercraft marker, usable/equippable state, and supported attribute details.
- Implement the loot result window described in the prototype: item name, level, thumbnail, hover details, distinct mastercraft treatment, and accept/decline controls. The client displays a server-issued offer and cannot author its contents.
- Add empty/loading/error states and close/reconnect behavior. Ensure pending offers are resolved or invalidated safely and cannot grant twice.
- Keep Derma calls consistent with existing local patterns and verify signatures against compatible call sites before introducing new controls.
- Acceptance: exercise inventory open/refresh, item use/equip where implemented, loot accept/decline, invalidated offers, reconnect, and small-screen/frame sizing in a running client.

## Phase I: Boss Lifecycle and World Markers (Not Started)

- Define boss spawn scheduling, eligible cells, random selection, maximum active count, cooldown persistence, and the behavior when no eligible cell exists. Make all checks authoritative and profile-scoped.
- Materialize bosses independently from ordinary Walker population unless the Phase F ticket contract explicitly supports boss definitions. Track boss identity/lifecycle robustly across map transitions and entity removal.
- Implement guaranteed boss loot as a reward policy with validated groups and explicit mastercraft rules; prevent duplicate rewards from repeated death/removal callbacks.
- Add boss map markers through existing world-map APIs. Specify marker lifetime, distance/visibility policy, player permissions, icon fallback, and synchronization when bosses spawn, move, die, or despawn.
- Acceptance: tests cover cooldown and active-count persistence, invalid eligible-cell sets, profile switching, one-time rewards, and marker removal; verify marker behavior in-game.

## Phase J: Crafting, Armor, Clothing, and Extension Points (Not Started / Scope Gate)

- Reassess scope after the item/loot/enemy vertical slice. Promote each feature only when its gameplay dependencies are concrete.
- If crafting is approved, define recipe validation, atomic ingredient consumption/result grant, stations, craft time interruption, requirements, and whether mastercraft results can be authored or require a separate service/currency system. Do not implement a den crafting table or currency economy by implication from examples.
- If armor/clothing is approved, define equip slots, damage pipeline, durability/repair, mobility/radiation effects, persistence, and visual representation before adding data fields.
- If workshop registration is approved, define trusted registration APIs and collision/override policy; static JSON remains data, not executable code.
- Acceptance: phase-specific tests and design decisions are added here before implementation starts.

## Phase K: End-to-End Verification and Release Readiness (Not Started)

- Add reproducible static-data validation fixtures and focused Lua/runtime tests for registries, inventory persistence, item use/scaling, loot rolls, prop interaction, enemy lifecycle, and boss lifecycle.
- Add admin-only diagnostics for current registries, item grants, loot offers, enemy selection, and boss state with permission checks and audit-friendly output.
- Run parser/data validation and static Lua checks, then one deliberate in-game session covering the complete vertical slice: bandage use, crowbar and handgun item rolls, enemy kill/drop, prop loot accept/decline, inventory refresh, map/profile transition, and boss marker if that phase is approved.
- Review logs for duplicate grants, unresolved references, invalid classes/models/icons, stale net requests, SQLite failures, and optional Walker-module behavior.
- Record remaining visual/runtime limitations and completed evidence here; do not mark phases done based on static checks alone where in-game behavior is required.