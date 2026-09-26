# Alpha 2.8

## New Features

# CSS Weapons

 - Since gmod includes all the Counter-Strike: Source weapon models, we can utilize them in our game.
 - Using all the available css weapon models, add the corresponding weapons to the item database and add them to the crafting groups.
 - Use reasoning to scale the rarity of each CSS weapon based on its suspected real world and also in game to counter strike power and realistic availability. Also the wepeaons should use the correct attributes. 

# Ammo Types

 - Right now the weapons do not have specific ammo types assigned to them and just have an infinite pool of ammo. The idea is that the ammo you have is stored in your inventory and each weapon consumes the corresponding ammo type when fired. To keep this optimized,  when you enter exit a cell, your player's ammo should be synchronized with the inventory, adding or removing ammo as necessary, not updating after each shot.

 - Introduce the many different ammo types corresponding to the CSS weapons, ensuring that each weapon consumes the correct type of ammo from the player's inventory. For instance 9mm ammo for pistols, 5.56mm for rifles, and so on.

 - Add variant high caliber ammo types for weapons that require them, such as .50 BMG for sniper rifles and other heavy weapons and explosive or armor-piercing rounds as a special ammo type ontop of the standard ammo types which can be used ontop of the regular ammo when needed. There will be some sort of UI to select the desired ammo type before firing.

 - Introduce the concept of automatic and non automatic firing modes for weapons, ensuring that each weapon behaves according to its real-world counterpart. Automatic weapons should consume ammo continuously while the trigger is held, whereas non-automatic weapons should consume ammo per shot. Integrate an automatic 9mm pistol as a rare level 15+ drop.

 - Make it so you can find oil in all types of barrels. Water in all types of water barrels.
 - Add lots and lots of food options and scale them based on rarity, nutritional value, and spoilage rate to create a more realistic survival experience. The level of the food gets greater the more damage and higher greater food has better nutritional value and slower spoilage rater and also affects the player's overall health and stamina recovery. So great food is processed and made through a factory before the apocalypse. While bad food might be spoiled or rotten food just found while scavenging. Maybe a tin of beans is mid tier food and actually perversed meat is high tier food. Also can we add cultivated lab grown meat as a super high tier food option.

## Recipe Definitions

 - Implement recipie definition data_static structure to store and manage all crafting recipes efficiently as mentioned in docs/item_and_loot_system_prototype.md
 - Introduce a crafting system that allows players to combine various ingredients and materials to create food, ammo, and other essential items. The crafting system should take into account the rarity and quality of the ingredients, affecting the final product's effectiveness and value.

## Jobs items

 - Being a farmer, depending what level you are. You will produce fresh produce which will appear in your inventory everyday as long as you visit a den.
  - Depending if you are level 0,5 you could for instance produce basic crops like potatoes and carrots, while higher levels might allow you to grow more advanced or rare crops like tomatoes, strawberries, or exotic herbs.
- Being a doctor. Depending on what level you are. You will be able to provide medical assistance to other players, with higher levels granting access to more advanced medical treatments and equipment. You can get medical items added to your inventory every day as long as you visit a den, for instance if you are level 0,5 you might receive basic medical supplies like bandages and painkillers, while higher levels could grant access to more advanced items like surgical kits and rare medicines like morphone and Agent-X a super high tier medical item which instantly heals a player.
- Being a mechanic. Depending on what level you are. You will be able to repair and maintain vehicles, with higher levels granting access to more advanced tools and parts. You can get mechanical items added to your inventory every day as long as you visit a den, for instance if you are level 0,5 you might receive basic components like copper wire, screws, and nuts, scrap metal, duct tape, glue, and other common repair materials, while higher levels could grant access to more advanced items like engine parts and rare mechanical components.
- Being a hunter. Depending on what level you are. You will be able to hunt wildlife for food and resources, with higher levels granting access to more advanced hunting equipment and techniques. You can get hunting items added to your inventory every day as long as you visit a den, for instance if you are level 0,5 you might receive basic hunting gear like a bow and arrows or a small game trap, while higher levels could grant access to more advanced items like rifles, traps for larger game, and rare hunting tools.
- Being a scavenger. Depending on what level you are. You will be able to find valuable items and resources in the environment, with higher levels granting access to more advanced scavenging techniques and locations. You can get scavenged items added to your inventory every day as long as you visit a den, for instance if you are level 0,5 you might find basic supplies like canned food and scrap materials, while higher levels could grant access to rare items like weapons, high-quality tools, and unique collectibles.
- Being a chef. Depending on what level you are. You will be able to prepare meals that provide various benefits to players, with higher levels granting access to more advanced cooking techniques and rare ingredients. You can get cooking items added to your inventory every day as long as you visit a den, for instance if you are level 0,5 you might receive basic ingredients like vegetables and spices, while higher levels could grant access to rare ingredients and advanced cooking tools. Players will be able to also come to you to get their cood cooked, which has more nutritional value and provides better buffs compared to uncooked food items.
- More on cooked and uncooked items: All food items found are "uncooked" Unless they are not to be cooked. you take the item to a chef to cook that item, the chef has to be a higher level or same level as the food item. The chef cooks the item for you and you get back a cooked version of the item. The benefit of this is that its also valued more since you had to pay the chef and also it has higher nutritional value and provides better buffs compared to uncooked food items.

- As a police officer, your natural weapon attributes will be higher compared to other jobs when you start a new character, reflecting your training and experience in handling firearms and other law enforcement tools. Depending on your level, you will have access to better weapons, tactical gear, and specialized skills.  You do not get any special items added to your inventory daily like other jobs, but your combat effectiveness and access to law enforcement resources make up for it.

- As an army soldier, your natural weapon attributes and combat skills will be higher compared to other jobs when you start a new character, reflecting your military training and experience. You do not get any special items added to your inventory daily like other jobs, but your combat effectiveness and access to military resources make up for it such as greater proficiency with machine guns and you also have a higher strength and endurance compared to other jobs.

- As a scientist, your natural intelligence and research skills will be higher compared to other jobs when you start a new character, reflecting your academic background and expertise. Depending on your level, you will have access to better laboratory equipment, rare chemicals, and advanced research techniques. You do not get any special items added to your inventory daily like other jobs, but your ability to create potions, medicines, and other scientific items makes up for it.
 - More on scientists: A scientist can conduct experiments and research to unlock new technologies, potions, and medicines. Players can bring raw materials and ingredients to the scientist, who they pay to make the medical items. 

 - Note about professions: Players bring the items to the relevant professional (chef, scientist, doctor, etc.) to have them processed, cooked, or crafted. The professional must be at the same level or higher than the item being brought to ensure successful processing. This system encourages interaction and cooperation between players with different professions. The doctor for instance does not need to have an bandage to heal a player as the player brings them the necessary medical supplies.

 - Example scenario: If a player wants a cooked meal, they must bring the raw ingredients to a chef who is at the same level or higher than the meal's required level. The chef will then prepare the meal, and the player will receive the cooked version with enhanced nutritional value and buffs. Similarly, if a player needs a potion or an implant creating, they must bring the necessary ingredients to a scientist who meets the level requirement to create the potion or implant. This system ensures that players with different professions must collaborate to obtain advanced items and benefits.

 ## Implants

 Implants are special enhancements that can increase the odds of you finding certian loot in the world. Such as ammo items, weapons or armour or medical supplies or even more cash. They increase your rate by a percentage. So a high level implant would significantly boost your chances of finding rare and valuable items compared to a low level implant by about 20% or more, depending on the implant's level and quality.

 Implants are extremely rare and extremely valuable and can be dropped by bosses on an extremely rare circumstance or found in high damage cells in extremely dangerous areas of the game world. Players will need to be well-prepared and skilled to obtain these implants, making them highly sought-after items for enhancing their chances of finding valuable loot.

 Implants are equipped in a seperate area to the inventory as they are considered permanent enhancements to the character rather than regular items. Players must manage their implant slots carefully, as each implant occupies a specific slot and may provide unique bonuses or abilities.

 Implants can also modify the players speed, XP gain, health regeneration, and other character attributes, providing additional strategic advantages and customization options for players who invest in these rare enhancements.

 You can only have 3 implants equipped at any given time, so players must choose their enhancements wisely to maximize their character's potential and adapt to different challenges in the game world.

 ## Credits

 Credits is as special currency ontop of cash which can be used at the den to purchase rare items, implants, and other valuable resources that are not available through regular cash transactions. Players can earn credits through completing high-level missions, defeating powerful bosses, or participating in special events, making them a prestigious and sought-after form of currency in the game world. They can also be purchased with real money through the game's store, providing an additional avenue for players to acquire this valuable currency.

 Credits can be used to mastercraft rare and powerful items, including high-level weapons, armor, and implants, allowing players to significantly enhance their capabilities and gain an edge in the game world. This is through an entity known as the Mastercrafting Station, where players can exchange credits and other resources to create these exceptional items which is in the den.

 Credits can also be used to reset the players skill points back to their default state, allowing them to reallocate their points and experiment with different builds and strategies without being permanently locked into their previous choices. This would give back the amount of skill points you have previously spent, enabling players to optimize their character builds according to their evolving playstyle and the challenges they face in the game world.

 You can also change your player appearance and job using credits. 

 Credits provide players with a flexible and valuable resource that can be used to enhance their gameplay experience in various ways, from acquiring rare items and implants to customizing their character and optimizing their skill points. Managing and earning credits effectively can give players a significant advantage in the game world.

 ## Mastercrafting Station

 The Mastercrafting Station is a specialized entity located in the den where players can use credits and other resources to create rare and powerful items. This includes high-level weapons, armor, and implants that are not available through regular cash transactions. By utilizing the Mastercrafting Station, players can significantly enhance their capabilities and gain an edge in the game world. The process typically involves selecting the desired item, providing the necessary materials and credits, and then crafting the item, which will then be added to the player's inventory. When you master craft an item, it rolls a dice on exactly what attributes you get. A "Ultra Mastercraft" is when all the attributes are the highest possible they can be for that item and are displayed differently in trading outposts as they are highly ultra rare items and are considered a prestigious achievement for players who manage to obtain them.

 Players may not keep remastercrafting the same item in multipleattempts if they fail to achieve the desired attributes, meaning that the resources and credits used in the process are consumed regardless of the outcome. This adds an element of risk and strategy to the mastercrafting process, encouraging players to carefully consider their choices and manage their resources effectively.

## Trading

 Trading is an essential aspect of the game world, allowing players to exchange items, resources, and credits with one another. This can take place at designated trading outposts or through player-to-player interactions, providing a dynamic and player-driven economy. Players can trade a wide variety of items, including weapons, armor, implants, and other valuable resources, enabling them to acquire the specific items they need to enhance their gameplay experience.

 Because right now the online features for the game are not fully implemented, trading may be limited or simulated through offline mechanisms, and players should be aware that the trading system may evolve as the game progresses towards a more complete online experience.

 On preview mode, when you go to a den, instead of the trade list displaying players trade orders, the orders will instead be filled by AI-controlled traders or pre-determined trade offers, simulating a functional trading environment for players to interact with. They will be able to buy most if not all of the items available in the trading system, providing a realistic experience of trading even in the absence of a fully implemented online feature. Some rare items might not be available through AI traders and could require actual player interactions once the online features are fully implemented.

 Players should also be aware that trading strategies may differ between AI-controlled traders and real players, and the availability and pricing of items could vary significantly once the online trading system is fully operational. This encourages players to plan their trades carefully and consider the potential benefits of engaging with other players directly when the online features are available.

 Dens in high damage areas may have more valuable or rare items available for trade, reflecting the increased risk and challenge associated with these locations. Players should weigh the potential rewards against the dangers when deciding where to conduct their trading activities. But the risk of that is, lower level items and their ammo types might also not be readily available, making it necessary for players to carefully plan their inventory and resource management before venturing into these high-risk areas. For instance, 9mm ammo might not be found that much in high damage areas due to its use with lower level weapons so it could actually be more expensive in a high damage den compared to safer areas with less damage. Simulating a realistic resource driven demand economy.

# Fixing Walkers

- Walkers are broken because we need to regenerate the preview world, restage the vmfs and rerun through navmesh and then see if walkers work and haven't regressed. Do this last after all of your changes

## Implementation Plan

### Phase A: Design Contracts and Scope Lock

- Audit Alpha 2.7 runtime contracts first: item definitions/static-data validation, inventory and death/den persistence, SWEP bases, player stats/jobs, den-only stash/crafting entities, and cash persistence. Reuse established services rather than introducing parallel data paths.
- Define bounded schemas and stable IDs for CSS weapons, ammo, special ammo, food, ingredients/materials, recipes, daily profession rewards, implants, credits, and trader offers. Specify stack limits, levels, quality, rarity, value, model/class references, and migration behavior.
- Resolve progression units and formulas before implementation: player level versus item level versus cell danger; weapon stats and firing modes; food nutrition/spoilage; recipe quality inheritance; profession levels; implant effect stacking; and credit/cash separation.
- Specify ammo lifecycle precisely: clip and reserve ownership, when ammo is synchronized with inventory, reload and weapon-switch behavior, death loss, den persistence, reconnect, and handling of full/invalid stacks. The intended transition sync must not create or destroy ammo through retries.
- Specify food lifecycle: which foods can be eaten raw, nutrition and stamina/health effects, spoilage clock and offline-time behavior, and how cooking changes quality, nutrition, value, and item identity.
- Specify recipe transaction behavior: station tags, ingredients, quantity, duration, interruption conditions, requirements, result placement, quality inheritance, and atomic rollback on persistence failure.
- Specify profession delivery cadence, date/time basis, reward caps, offline accrual, job-change behavior, and full-inventory handling. Specify whether professions own a service station and who supplies/pays for service ingredients.
- Specify implant slots and caps; define credit earning/spending and transaction persistence. Exclude real-money purchases and online player trading from initial implementation pending a separate security/platform design.
- **Acceptance:** decisions are recorded here or linked to focused design documents; every field has bounds and semantics; no implementation silently chooses unresolved gameplay policy.

### Phase A — Contract Lock Started (2026-09-26)

The initial contract for Alpha 2.8 is now recorded and will be used as the authority before any CSS weapon or recipe code lands.

- Data model policy: item IDs are stable, definition-backed, and immutable; item instances only carry generated state such as level, quality, stack count, charges, mastercraft flag, and timestamp metadata. No runtime code may invent IDs or mutate static definitions after load.
- Weapon and ammo contract: each weapon maps to exactly one ammo item and one firing mode definition; ammo is stored as stackable inventory rows, while live clip/reserve state remains server-owned until a save boundary. No weapon can silently share an ammo pool or auto-create ammo in a retry path.
- Progression contract: player level, item level, and cell danger are separate values. The effective item level is computed by a bounded formula, not by ad hoc UI logic. Weapon stats and food effects are derived from decided ranges before implementation so balancing is deterministic and testable.
- Food contract: raw foods are the default unless the recipe explicitly creates a cooked item with a new identity and quality tags. Spoilage is stored as a timestamp-based freshness value that is preserved across save/load and offline time accumulation.
- Recipe contract: recipes are versioned, server-owned, and validated before use. A recipe can only consume ingredients on success, and can only create a single authoritative result set with atomic inventory rollback if the save fails.
- Profession contract: job rewards are daily and idempotent, keyed by profile and claimed day. The service is denied when inventory is full, and it can never create duplicate reward claims during reconnects or map transitions.
- Implant and credit contract: implants remain outside normal inventory slots, with a strict cap of three equipped implants. Credits are profile-scoped, distinct from cash, and only supported as a server-side den currency in this phase. Real-money purchase and live player trading stay out of scope.
- Scope boundary: this phase locks the data and behavior contracts only. It does not implement CSS weapon classes, ammo consumption logic, or trader UIs before the schema and validation rules are approved.

The detailed contract is kept in [docs/alpha_2.8_phase_a_design_contract.md](docs/alpha_2.8_phase_a_design_contract.md) and is the implementation reference for all following phases.

### Phase B: CSS Weapon Catalog and First Playable Batch

- Asset audit complete: the relevant CSS content is packaged inside the game data files and is not available as unpacked traditional CSS SWEP classes. The runtime must map each CSS-inspired weapon family to a local ZombieSim weapon base and local SWEP implementation instead of loading stock CSS classes directly.
- Inventory CSS weapon assets actually available in the installed GMod content and verify model/viewmodel paths and animations locally.
- Select a small representative batch across pistol, SMG, rifle, shotgun, and sniper categories. Map each item ID to an explicit SWEP class, models, supported attributes, ammo type, firing mode, requirements, and loot groups.
- Establish rarity/progression from documented gameplay power, availability, and intended unlock level. Treat real-world analogues as flavor/balance inputs, not authoritative rarity facts.
- Add item definitions, SWEP classes or explicit base configurations, and validated loot entries incrementally. Include the rare level-15+ automatic 9mm pistol as a separate item/behavior, not a hidden mode change on the ordinary pistol.
- Verify each weapon's hold type, reload/fire animation, sound, muzzle/impact behavior, top-down aiming, and damage in a live client.
- **Acceptance:** static validation catches missing assets/classes and invalid attributes; generation tests cover deterministic levels/attributes and eligibility; every first-batch weapon grants, equips, fires, reloads, persists, and restores correctly in game.

#### Phase B checkpoint: registry and validation gate

- The CSS weapon family is a design reference only; the live class remains a ZombieSim base-layer SWEP.
- The first-batch registry must define item id, CSS family, local weapon base class, ammo id, firing mode, rarity, and validation state.
- No direct CSS class names are accepted in the runtime registry; the registry records the mapping from CSS-inspired content to the local SWEP architecture.
- The next step is a registry document and validation checklist before any bulk content import begins.

### Phase C: Ammunition and Firing-Mode System

- Add stackable ammo item definitions for the Phase B weapons, with explicit weapon-to-ammo mappings (for example 9mm, 5.56mm, shotgun shells, and sniper/high-caliber ammunition as needed by the chosen batch).
- Implement server-owned clip/reserve state and transition synchronization between active weapon state and inventory. Cover initial spawn, cell/den entry and exit, death, disconnect/reconnect, weapon swap, and failed save. Select one canonical state at each boundary to prevent duplicate or lost rounds.
- Implement reload validation and consumption. Define empty-clip, partial reload, interrupted reload, ammo-capacity, weapon removal, and no-ammo behavior.
- Implement semi-automatic and automatic fire metadata with server cadence and per-shot consumption. Special explosive/AP ammo selection is a follow-up within this phase only after standard ammo invariants pass; define whether a special round replaces or supplements the standard round.
- Add focused tests for synchronization idempotence and replay resistance before enabling ammo for the full CSS catalog.
- **Acceptance:** automated tests prove exact ammo conservation over firing/reload/map-transition cycles, invalid requests cannot create shots or ammo, and automatic weapons respect cadence. Live tests cover each mode, reload, empty ammo, and transition synchronization.

### Phase D: Scavenged Resources and Food Vertical Slice

- Add oil and water resources. Enumerate supported barrel runtime classes and normalized model paths; verify each barrel type maps only to its intended resource, with tests for unsupported props.
- Define food fields and effects, then implement a small representative catalog before bulk content: rotten/spoiled food, ordinary canned beans, preserved meat, and high-tier lab-grown meat.
- Implement spoilage timestamps and quality-aware stack compatibility. Ensure moving, saving, loading, and depositing food preserve its freshness according to the Phase A rules.
- Implement server-side consumption with bounded nutrition, hunger/thirst, health, and stamina effects. Reject repeated or stale use requests and ensure a failed persistence operation does not grant an effect for free.
- Expand the food catalog by tier only after the data/effect loop is validated; balance value and spoilage with explicit ranges rather than item-by-item implicit exceptions.
- **Acceptance:** tests cover model matching, food effect bounds, spoilage before/after save-load and offline time, stack compatibility, and consumption rollback; live scavenging and eating works end-to-end.

### Phase E: Validated Recipes and Atomic Den Crafting

- Add a versioned recipe registry under `content/data_static/` with validation for IDs, ingredients, quantities, output, requirements, duration, station tags, and optional quality rules. Invalid reloads must retain the last known-good registry.
- Implement a server crafting service that verifies player state, den-map access, station identity/range, recipe eligibility, profession/skill requirements, and available ingredients. Client requests identify a recipe and count only; server owns all recipe data and output rolls.
- Make input removal and output placement atomic from the user's perspective. Handle stack splitting, inventory/stash capacity, persistence failures, duplicate submissions, and stale recipe IDs without consuming ingredients or granting duplicate results.
- Add craft-time progress and cancellation for leaving range/den, dying, disconnecting, station removal, and any additional Phase A interruption rules. Enforce a single active job per player unless queues are explicitly designed.
- Replace the current empty crafting panel with a server-fed recipe list, requirement/cost states, progress, and actionable failure feedback. Keep free-world crafting rejected.
- **Acceptance:** fixture tests cover schema failures and recipe resolution; transaction tests verify ingredients/results roll back together; exploit tests cover request replay/range/station checks; live den tests craft food and ammunition and test cancellation/full inventory.

### Phase F: Profession Foundation and Daily Den Deliveries

- Reconcile canonical job IDs and current persisted `Job` behavior with Farmer, Doctor, Mechanic, Hunter, Scavenger, Chef, Police Officer, Army Soldier, and Scientist. Define starting bonuses and profession skills without conflating job identity with level/stat values.
- Implement an idempotent daily reward planner with persisted claim records, explicit day/time basis, per-job/level reward tables, bounds, and inventory-full policy. Repeated den visits, map changes, reconnects, and profile switches must not duplicate rewards.
- Start with Farmer, Doctor, and Mechanic reward tables to exercise food, medical, and crafting resources. Add Hunter, Scavenger, and Chef after the shared delivery service is stable. Police and Soldier receive only agreed combat/stat bonuses; Scientist gets research/service behavior rather than accidental daily grants.
- Implement chef cooking as a station service: the food owner supplies items, the chef's level/skill gates the service, and the operation atomically exchanges the agreed fee/inputs for a cooked result. Apply the same explicit ownership/payment/ingredient rules to scientist research and medical services.
- **Acceptance:** tests cover reward bands, exact-once claims, profile isolation, job changes, full capacity, and failed saves; live den checks verify daily delivery and a player-to-professional service flow.

### Phase G: Implants and Loot/Character Modifiers

- Define implant definitions, acquisition tables, three-slot equipment state, persistence, removal/replacement rules, and effect caps. Keep implants out of ordinary inventory slots if the finalized contract treats them as persistent character enhancements.
- Implement one server-owned modifier aggregation service for loot odds, movement, XP, regeneration, and other approved effects. Define stacking and caps per effect; replicate only read-only summaries to clients.
- Add a small implant test set and controlled rare boss/high-danger acquisition sources. Loot modifiers may change only their documented loot probabilities and must not bypass activation, eligibility, or boss policies.
- **Acceptance:** tests cover slots, equip/remove, persistence, profile isolation, stacking/caps, and deterministic effect application; live play confirms UI summaries match authoritative effects.

### Phase H: Credits and Mastercrafting Service

- Implement profile-scoped credits as an in-game currency with bounded values, transactional updates, and a clear audit/debug path. Do not implement purchases with real money in Alpha 2.8.
- Define mastercrafting costs, eligible items, generated attributes, ultra-mastercraft odds/definition, identity/replacement behavior, and whether all resources are spent on every attempt. Enforce the no-repeat-attempt rule through server persistence rather than client UI state.
- Add a den-only mastercraft station and UI. Server validates item ownership, station/range, cost, materials, and one-use request identity; the client cannot submit attribute scores or outcomes.
- Add skill-point reset and appearance/job changes only if the credit contract and existing progression/appearance APIs support them; otherwise document them as deferred, not implicit station features.
- **Acceptance:** tests cover cost deduction, failed-save rollback, replay, attribute bounds/distributions, ultra-mastercraft probability, and item identity; live tests complete an ordinary and a controlled test mastercraft attempt.

### Phase I: Offline Den Trading Prototype

- Scope initial trading to deterministic AI/predefined offers in preview/local play. Keep player-to-player trade and online service authority outside this phase; do not add real-money credit purchasing.
- Define stock, offer refresh, cash/credit pricing, den danger availability, purchase/sale limits, and a low-level essential-ammo floor so progression does not make basic supplies inaccessible in safer dens.
- Implement buys/sells through atomic server-side inventory and currency transactions. Protect against stale offers, repeated requests, full inventory, stock races, map transitions, and persistence errors.
- Build den trading UI that distinguishes cash and credits and shows level, quality, ammo compatibility, stock, and total cost. Keep offer generation deterministic for fixture tests.
- **Acceptance:** tests cover price bounds, stock, purchase/sale rollback, full inventory, duplicate requests, and profile isolation; live preview checks trade across at least two den danger tiers.

### Phase J: Integration, Walker Regression, and Release

- Update item/recipe/profession/ammo/implant/currency/trading documentation and schemas. Keep generated runtime exports and staged assets as pipeline outputs.
- Run GLua syntax checks, static-data validation, and all affected focused suites for inventory, weapons, ammo, food, crafting, professions, implants, currency, and trade.
- Validate the integrated slice in preview: profile persistence, map transitions, den stash/deposit, death behavior, ammo sync, food freshness, craft interruption, daily rewards, and service/economy transactions.
- **Do the Walker regression last**, after gameplay and data changes are settled: regenerate the current preview world, refresh plans and VMFs, restage the required maps, rerun the documented navmesh pipeline, then verify Walker operation in game. Inspect the exact generated reports/artifacts; do not trust stale preview files.
- Run one deliberate end-to-end session and record static versus live results separately. Only stage/validate production after preview acceptance is clear.
- **Acceptance:** automated checks pass; live checks pass or have explicit blockers; preview artifacts match current sources; known limitations and follow-ups are recorded before marking Alpha 2.8 complete.

## Cross-Phase Rules

- Keep inventory, weapon firing, ammo, loot, crafting, job rewards, implants, currency, and trading outcomes server-authoritative. Client code expresses intent and displays server snapshots/results.
- Preserve Alpha 2.7 profile isolation, inventory persistence, death-loss, and den-stash semantics unless a recorded Phase A decision changes them. Persistence changes require migration, failure, rollback, and profile-isolation tests.
- Add content in bounded batches. Do not bulk-import all CSS weapons or food before the first representative vertical slice passes data validation, automated tests, and a focused live check.
- Record decisions and dependencies in this tracker before implementing any ambiguous mechanic; speculative prototype text is not by itself an implementation contract.
- For every runtime/UI change, report static validation and in-game verification separately. Regenerate current preview artifacts before world-dependent testing.