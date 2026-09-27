# Alpha 2.8 Phase A Design Contract

## Purpose

This document defines the implementation contract for the first scope lock of Alpha 2.8. It is meant to stop exploratory feature work before any weapon, ammo, food, profession, implant, credit, or trading code is added.

The contract is intentionally minimal but explicit: every feature below has a stable data model, source-of-truth owner, validation bounds, and behavior rules.

## Scope and Non-Goals

In scope for Phase A:

- stable item and instance schema definitions
- weapon-to-ammo mapping rules
- food quality and spoilage rules
- recipe and transaction semantics
- profession delivery model
- implant and credit separation
- mastercrafting and trading scope boundaries

Out of scope for the initial implementation:

- real-money purchases
- online player-to-player trading
- broad CSS catalog import without first-batch validation
- speculative mechanics without explicit data validation and save rollback rules

## Source of Truth and Ownership

- Static item and loot configuration remains authoritative under content/data_static/.
- Runtime inventory, equipment state, and den transactions remain server-authoritative.
- The client may send intent only; it never chooses outcomes for item generation, inventory mutation, or rewards.
- No new data path may be introduced in parallel with existing inventory or persistence services. All new flows must reuse or extend the current item-definition and inventory transaction model.

## Stable Data Model

### Item definitions

Each item definition must have:

- itemId: stable lowercase identifier
- name: editable display name
- entityClass: one of generic, entity, or weapon
- thumbnail: asset path token, without implicit runtime guessing
- value: cash value model
- maxStack: bounded stack limit
- minLevel / maxLevel: item progression bounds
- levelRequirement: optional alias for use requirements where relevant
- rarity: explicit value used for drop tables and loot balance
- modelClass or weaponClass: explicit runtime mapping
- type: one of supported item categories, with only the supported data fields for that category

### Item instances

Item instances are distinct from item definitions and must only contain runtime state:

- instanceId
- itemId
- count or stack quantity
- level
- quality
- mastercraft flag
- createdAt / updatedAt
- durability or charge values when applicable

The definition remains immutable; the instance is the only mutable runtime object.

### Validation rules

- IDs must be stable and lowercase alphanumeric strings.
- Weapon definitions must declare a valid SWEP class and a supported weapon type.
- Item value, stacks, and level ranges must be bounded.
- Invalid definitions are not silently accepted; the last known-good static data remains active until the new data validates.

## Weapon and Ammo Contract

### Weapon identity

Each weapon has exactly one:

- SWEP class
- ammo item id
- firing mode set (semi-auto or automatic)
- level band and rarity band

No weapon may derive its ammo or class dynamically from untrusted strings.

### Ammo lifecycle

Ammo is stored as inventory items and not as hidden global ammo pools. The server owns all live ammo state.

Rules:

- a weapon can only consume the ammo type explicitly assigned to it
- clip and reserve state are server-owned runtime state
- inventory sync occurs at save boundaries and on cell/den transitions, not per shot
- a failed save or failed mutation must not create or destroy ammo
- reload, empty-clip, partial reload, and invalid weapon swaps must all use one canonical state transition path
- death and reconnect use the same authoritative restore logic

### Firing modes

- semi-auto weapons consume one round per trigger action
- automatic weapons consume rounds continuously while the trigger is held
- fire cadence and round cost are server-owned and validated
- a rare automatic 9mm pistol is treated as a separate item, not as a hidden mode override on the base pistol

### High-caliber and special ammo

Special ammo is a follow-up after the standard ammo model is proven stable.

The initial contract is:

- standard ammo items are required first
- special ammo may be added only after the base inventory sync and state transitions are passing tests
- special ammo is optional, not hidden behavior layered onto all weapons

## Food and Spoilage Contract

### Food categories

Food items are split by quality and preparation state:

- raw scavenged food
- raw but preserved food
- cooked food
- medical/utility consumables with explicit use rules

### Spoilage model

- spoilage uses a timestamp-based freshness value
- offline time is applied deterministically at load time
- cooking creates a new item identity or a distinct quality/variant, not a mutation of the original raw item
- food stack compatibility depends on item identity and quality rules

### Consumption model

- food may provide nutrition, stamina recovery, and health recovery
- effects are bounded by explicit ranges
- a stale or invalid use request cannot grant an effect if the save or inventory mutation fails
- raw vs cooked food effects are defined separately and cannot be conflated

## Recipe and Crafting Contract

### Recipe registry

Recipes are versioned and stored under the data_static structure, not ad hoc in Lua tables.

Each recipe must define:

- recipeId
- station tag
- duration
- level requirement
- profession or stat requirement
- ingredients and counts
- output items and counts
- quality inheritance or generation policy
- atomic rollback semantics

### Transaction model

- recipe validation occurs server-side
- the client sends only recipe id and quantity intent
- ingredient removal and result creation are atomic from the player's perspective
- failed saves or stale recipe ids must not consume inputs or duplicate outputs
- crafting is den-only and rejected in free-world locations
- active craft jobs are interrupted by leaving range, dying, disconnecting, or station loss

## Profession and Delivery Contract

### Daily reward cadence

- profession rewards claim once per profile per day
- reward claims are idempotent across reconnect, re-enter den, and profile switch
- reward logic uses an explicit day boundary and is not inferred from client time
- rewards are capped and may be rejected if inventory is full

### Enforced job behavior

- profession identity, level, and stat values remain separate concepts
- a profession may grant daily resources, but it does not silently bypass item-level or station-level rules
- service roles such as chef, scientist, and doctor are explicit and can only use the approved processing flow

### Phase F decisions

- the day boundary is midnight UTC on the server clock; missed days are not accrued offline
- claims are keyed by profile and day, not job, so a same-day job change grants nothing
- a delivery that does not fit is refused and retried every 60 s with one notice per day; counts are deterministic per player, profile, and day
- deliveries are banded by player level; jobs are assigned by admin/dev command only
- profession stat bonuses are derived at runtime and never persisted
- services: the customer supplies the items and pays a whole-number cash fee; self-service costs 0 and has no prompt; the provider's level caps the item level they can work
- research is instant at service time; `craftTime` applies only at the workbench, which refuses service recipes
- cooked food keeps the raw food's freshness fraction

## Implants, Credits, and Mastercrafting

### Implants

- implants are not ordinary inventory slots
- maximum equipped implants is three
- effects are aggregated through a single server-owned modifier service
- activation and caps are defined, not inferred from UI state

### Phase G decisions

- implants are items that a Doctor installs in the den; installed implants live in `player_implants`, not in inventory slots
- there are three typed slots (Neural, Ocular, Dermal), one implant per slot; a replaced or extracted implant returns to the backpack, and extraction needs a free backpack slot
- the provider's level must be at least the implant's level; the backpack, implant rows, and fee are saved in one transaction
- implants survive death; a character reset clears them
- an effect's value is interpolated between the authored `[min, max]` by instance level; each implant has a per-effect limit, and the sum of installed implants is clamped to a per-effect cap
- loot effects multiply entry weights by `1 + bonus` for the matching item `lootCategory`, only for the searcher's loot-spot rolls and the killer's enemy drops; they never change boss loot, activation or drop chance, or counts, and never boost the implants category
- `xpGain` scales positive XP awards; `moveSpeed` scales walk and run speed; `healthRegen` is HP per minute

### Credits

- credits are profile-scoped and distinct from cash
- they flow through server-side transactions and audit entries
- credits are intended for den services and rare crafting, not for online or real-money purchase flows in this phase

### Mastercrafting

- mastercrafting requires explicit cost, station, and validation rules
- all result generation is server-owned
- UI cannot determine the outcome or bypass server validation
- the no-repeat-attempt rule is enforced through persistence, not client state

### Phase H decisions

- Credits are stored in `player_credits` (steamid+profile), whole numbers from 0 to 1,000,000. Every change appends a `credit_ledger` row in the same transaction, and a change only lands if the stored balance still equals the expected one. Credits survive death and character resets. In Alpha 2.8 they come only from admin grants.
- Den service prices are static data (`den_service_definitions.json`): mastercraft `baseCredits + ceil(level x creditsPerLevel)`, a flat job-change price, and `ultraChance` (at most 0.25).
- A mastercraft upgrades an ordinary backpack weapon in place: same instance id and level, `mastercraft = true`, and each attribute re-rolled within one point of the maximum. An Ultra Mastercraft has every attribute at the maximum. The credits are spent whatever the roll. `mastercraft_attempts` (steamid+profile+instanceId) records the attempt in the same transaction as the item and the credits, and blocks a repeat.
- Station requests are quoted under a single-use, 60 s token. A confirmation consumes it and re-validates ownership, container, den, station range, balance, and price. The client never sends prices, attributes, or outcomes.
- The station's only extra service is a paid job change (the job and the credits are saved together). Skill-point reset and appearance changes are deferred.

## Trading Contract

Trading is intentionally constrained in this phase.

- offline AI or deterministic offer generation is allowed for preview/local play
- no real player-to-player trading is approved for Alpha 2.8
- no real-money credit store path is included in this phase
- offer generation must be deterministic enough for test fixtures and reproducible validation

### Phase I decisions

- Traders and their offers are static data (`trade_definitions.json`). Traders are den NPCs (`zn_den_npc`) placed in Hammer; the `trader` keyvalue names the table.
- A den's daily stock is shared by all players in it and resets at midnight UTC. It is regenerated from a seed of profile, den, trader, day, offer key, and item; only the units sold are stored. Offers are gated by the den entrance cell's danger, and a trader with `essentialAmmo` always stocks the common ammunition at its minimum level.
- Ordinary goods cost `ceil(value x buyMultiplier)` cash (shipped 1.5); mastercraft weapons and implants cost fixed credits. Traders pay `floor(value x sellMultiplier)` cash (shipped 0.4) for backpack items in the categories they buy, up to a daily cash limit per player. Cash and implants are never bought; equipped weapons and spoiled food are refused.
- Each buy or sell is one transaction: items, cash or credits, a compare-and-set stock change, and a ledger row with a unique client request id. The server rebuilds the offer and refuses a stale day, price, currency, or stock.
- Den NPCs can be professionals: their profession, service level (the item-level cap), and fixed fee come from keyvalues and are resolved against the registry. They accept at once, hold no inventory or cash, never claim deliveries, and their fee is taken from the customer and credited to no one.
## Canonical First-Batch Decision Set

The Phase B implementation will not begin with a full weapon catalog. The first playable batch is only a constrained set chosen to cover the essential weapon archetypes, ammo families, and server-side validation paths.

Candidate batch for the design gate:

- Pistol: `weapon_css_usp_9mm` (semi-auto)
- Auto pistol: `weapon_css_9mm_auto` (rare level 15+ drop)
- SMG: `weapon_css_mp5`
- Rifle: `weapon_css_m4a1` and/or `weapon_css_ak47`
- Shotgun: `weapon_css_m3`
- Sniper: `weapon_css_scout` or `weapon_css_awp`
- Melee fallback: existing crowbar baseline remains the valid melee reference

Ammo definitions to be validated with the first batch:

- `ammo_9mm`
- `ammo_556`
- `ammo_762`
- `ammo_shells`
- `ammo_50bmg`

These are design placeholders only until local asset validation confirms the active SWEP model and animation paths. No item is considered live until it passes the validation gate below.

## Required Validation Gate Before Phase B Starts

Before the first batch is implemented, the following checks must pass:

1. Local GMod asset existence for each SWEP class, model, and viewmodel path is confirmed in the installed game content.
2. The weapon and ammo map is recorded in one authoritative table keyed by item ID.
3. Each weapon has a single ammo item and a single firing-mode policy.
4. Every item has all required bounds: rarity, level, value, maxStack, and model mapping.
5. Inventory tests cover save/load, death loss, reconnect restore, and movement between backpack and equipped state.
6. The first-batch items are validated with static schema checks before any gameplay use is enabled.

This gate intentionally prevents silent fallback behavior such as hidden ammo generation or weapon-mode mutation during implementation.

## Authoritative First-Batch Registry

The Phase B weapon batch is intentionally limited to the following canonical items and ammo mappings. These become the source of truth once the asset validation gate is cleared.

- `weaponCssUsp9mm`
  - Weapon class: `weapon_css_usp_9mm`
  - Ammo: `ammo9mm`
  - Firing mode: semi-auto
  - Level band: 1-12
  - Rarity band: common / low-tier sidearm
  - Use: standard defensive pistol baseline

- `weaponCssAutoPistol9mm`
  - Weapon class: `weapon_css_9mm_auto`
  - Ammo: `ammo9mm`
  - Firing mode: automatic
  - Level band: 15-30
  - Rarity band: rare / boss-tier drop only
  - Use: explicit rare automatic 9mm pistol, not a mode override of the standard pistol

- `weaponCssMp5`
  - Weapon class: `weapon_css_mp5`
  - Ammo: `ammo9mm`
  - Firing mode: automatic
  - Level band: 5-18
  - Rarity band: uncommon to rare
  - Use: close-range SMG verification batch

- `weaponCssM4a1`
  - Weapon class: `weapon_css_m4a1`
  - Ammo: `ammo556`
  - Firing mode: automatic
  - Level band: 8-24
  - Rarity band: uncommon to high-value rifle
  - Use: mid-tier rifle baseline

- `weaponCssAk47`
  - Weapon class: `weapon_css_ak47`
  - Ammo: `ammo762`
  - Firing mode: automatic
  - Level band: 8-24
  - Rarity band: uncommon to high-value rifle
  - Use: alternate rifle variant if the local content package exposes it cleanly

- `weaponCssShotgunM3`
  - Weapon class: `weapon_css_m3`
  - Ammo: `ammoShells`
  - Firing mode: semi-auto or pump-style burst semantics depending on the active SWEP base
  - Level band: 4-16
  - Rarity band: common to uncommon
  - Use: close-range combat validation

- `weaponCssScout`
  - Weapon class: `weapon_css_scout`
  - Ammo: `ammo762`
  - Firing mode: semi-auto
  - Level band: 10-28
  - Rarity band: rare
  - Use: marksman rifle and sniper benchmark

- `weaponCssAwp`
  - Weapon class: `weapon_css_awp`
  - Ammo: `ammo50Bmg`
  - Firing mode: semi-auto
  - Level band: 18-35
  - Rarity band: very rare
  - Use: heavy sniper benchmark after the standard ammo model is proven

Ammo registry:

- `ammo9mm` — standard sidearm/SMG ammo
- `ammo556` — rifle ammo baseline
- `ammo762` — rifle/sniper alternative
- `ammoShells` — shotgun round category
- `ammo50Bmg` — high-caliber special ammo category, added only after base inventory sync passes

Important rule: the batch does not include all CSS content. It only defines the minimum set necessary to validate player inventory, equip/unequip semantics, ammo sync, and firing-mode behavior before the bulk content set is expanded.

## Phase A Exit Criteria

Phase A is complete when all of the following are true:

1. item IDs and instance state are formally separated
2. weapon definitions have explicit ammo mappings and firing modes
3. food freshness and cooking rules are bounded and testable
4. recipe validation and rollback semantics are written and reviewed
5. profession delivery is idempotent and inventory-safe
6. implant and credit separation is explicit
7. the first-batch CSS weapon and ammo contract is recorded and validated
8. scope boundaries are recorded and no ambiguous feature slips into implementation

This contract is the baseline for Phase B and later development; no implementation work may proceed beyond this design lock until the rules above are enforced and recorded.
