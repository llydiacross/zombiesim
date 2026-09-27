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

- Asset audit complete: the relevant CSS content is packaged inside the installed GMod VPK, not as unpacked CSS SWEP classes. The eight selected view/world model paths were confirmed in the game VPK; runtime classes remain local ZombieSim SWEPs.
- First batch implemented across pistol, SMG, rifle, shotgun, and sniper categories. Each item ID now maps to a local SWEP class, CSS model pair, ammo ID reserved for Phase C, firing mode, rarity, level band, and loot group.
- Rarity/progression uses intended in-game power, availability, and unlock level; real-world analogues are flavor/balance inputs only.
- The level-15+ automatic 9mm pistol is a separate item and local SWEP. All eight classes inherit the ZombieSim hitscan base; the M3 supports multiple pellets.
- Offline GLua syntax and item/loot JSON checks pass. Live `zn_test_inventory` passed 26 cases; after preserving the prior generic handgun/melee ordering, `zn_test_static_data` passed all 11 cases.
- After reloading the preview map, `zn_test_weapon_catalog` passed all 8 mappings, including local SWEP registration, inheritance, model paths, automatic flags, and mounted model validity.
- **Live behavior pending:** test actual representative grant/equip/fire/reload and persistence/restore through the client. The catalog test does not verify viewmodel animations, sound, aiming, impact, or a user's inventory lifecycle.
- Verify each weapon's hold type, reload/fire animation, sound, muzzle/impact behavior, top-down aiming, and damage in a live client.
- **Acceptance:** static validation catches missing assets/classes and invalid attributes; deterministic inventory/eligibility tests pass; a current game session validates the local SWEP/model mappings; and at least one representative weapon grants, equips, fires, reloads, persists, and restores correctly in game.

#### Phase B checkpoint: registry and validation gate

- The first-batch registry is documented in `docs/alpha_2.8_phase_b_registry.md` and reconciled with the implemented item IDs, classes, CSS model paths, ammo IDs, firing modes, rarity, and level bands.
- No direct CSS class names are used at runtime; all eight item definitions map to local ZombieSim SWEPs.
- Static fixtures and catalog runtime validation pass after the loot-order correction and preview-map reload. The runtime diagnostic now records current health, resolved cell, radiation intensity, and exposure time for focused environmental checks.
- **Phase B implementation gate achieved:** a representative USP completed live grant, item-instance equip, empty start, inventory reload, firing, map-boundary synchronization, and restore without duplicating rounds. The remaining animation/sound/aim/impact review is a gameplay-polish pass across the catalog, not a blocker for the ammunition lifecycle.

### Phase C: Ammunition and Firing-Mode System

- **Phase C standard-ammunition gate achieved.** Ammo IDs now resolve to real stackable inventory items; loaded rounds persist on weapon instances.
- Add stackable ammo item definitions for the Phase B weapons, with explicit weapon-to-ammo mappings (for example 9mm, 5.56mm, shotgun shells, and sniper/high-caliber ammunition as needed by the chosen batch).
- Implement server-owned clip/reserve state and transition synchronization between active weapon state and inventory. Cover initial spawn, cell/den entry and exit, death, disconnect/reconnect, weapon swap, and failed save. Select one canonical state at each boundary to prevent duplicate or lost rounds.
- Implement reload validation and consumption. Define empty-clip, partial reload, interrupted reload, ammo-capacity, weapon removal, and no-ammo behavior.
- Implement semi-automatic and automatic fire metadata with server cadence and per-shot consumption. Special explosive/AP ammo selection is a follow-up within this phase only after standard ammo invariants pass; define whether a special round replaces or supplements the standard round.
- Add focused tests for synchronization idempotence and replay resistance before enabling ammo for the full CSS catalog.
- **Acceptance:** automated tests prove exact ammo conservation over firing/reload/map-transition cycles, invalid requests cannot create shots or ammo, and automatic weapons respect cadence. Live tests cover each mode, reload, empty ammo, and transition synchronization.

#### Phase C checkpoint: standard ammunition complete

- Added `ammo9mm`, `ammo556`, `ammo762`, `ammoShells`, and `ammo50Bmg`, with static validation requiring every bullet weapon to map to an existing generic stackable ammo item.
- Reserve rounds remain backpack items. Reload completion atomically removes only the mapped ammo and persists the new per-instance clip; firing changes the live server clip, then weapon switches, saves, transitions, disconnect, and orderly shutdown synchronize it.
- New weapons begin empty. Partial/full reload, no-ammo, mismatched-ammo, failed-persistence rollback, replayed synchronization, SQLite clip restore, and exact round conservation are covered by the inventory regression suite.
- Live validation exercised semi-auto reload/fire and an automatic 9mm round at its scaled 0.117-second cadence. A map reload reconciled deferred live clip state without recreating reserve rounds. Temporary test weapons/ammo were removed afterward and the original player inventory was restored.
- Special AP/explosive selection remains explicitly optional under the Phase A contract and is not hidden behavior on standard ammunition.

### Phase D: Scavenged Resources and Food Vertical Slice

- Add oil and water resources. Enumerate supported barrel runtime classes and normalized model paths; verify each barrel type maps only to its intended resource, with tests for unsupported props.
- Define food fields and effects, then implement a small representative catalog before bulk content: rotten/spoiled food, ordinary canned beans, preserved meat, and high-tier lab-grown meat.
- Implement spoilage timestamps and quality-aware stack compatibility. Ensure moving, saving, loading, and depositing food preserve its freshness according to the Phase A rules.
- Implement server-side consumption with bounded nutrition, hunger/thirst, health, and stamina effects. Reject repeated or stale use requests and ensure a failed persistence operation does not grant an effect for free.
- Expand the food catalog by tier only after the data/effect loop is validated; balance value and spoilage with explicit ranges rather than item-by-item implicit exceptions.
- **Acceptance:** tests cover model matching, food effect bounds, spoilage before/after save-load and offline time, stack compatibility, and consumption rollback; live scavenging and eating works end-to-end.

#### Phase D checkpoint: resources and food slice complete

- Added `itemOil` and `itemBarrelWater`. `entity_loot.json` maps blue plastic/wooden barrels to water and oil drums, warning barrels, `de_train/barrel` (previously medical), and barrel pallets to oil across the four physics/dynamic prop classes; `barrels_map_only_to_their_resource` covers every mapping plus unsupported models, gibs, `prop_static`, and `prop_ragdoll`.
- Added the validated `food` schema with tier-bounded effects and shelf life (`ZM_StaticData.FoodTiers`) and the shared `ZM_Food` module: timestamp freshness with fresh/stale/spoiled bands, band-aware stacking that keeps the oldest timestamp, and `FoodItem` consumption with bounded effects that apply only after the removal persists.
- Representative slice (rotten food, canned beans, preserved meat, lab-grown meat) validated first; the catalog then expanded by tier: mouldy scraps (0); orange, watermelon, milk, soda, bottled water, barrel water (1); canned soup (2); military ration (3); canned hot dogs, sealed factory meal (4). `lootGenericFood` weights scale down with tier and is included in car and dumpster loot.
- Static: GLua syntax 84/0, `zn_validate_static` 0 errors/0 warnings, static-data 12/12, inventory 33/33 (five food cases: bands and bounds, band stacking, save/load/stash/offline freshness, exactly-once eating with headroom refusal, spoiled penalty and failed-save rollback), loot 12/12, loot spots 9/9, script validation 56/56.
- Live: scavenged oil from three `de_train/barrel` spots and preserved meat from a car with `zn_dev_scavenge`; ate beans and preserved meat, drank water with thirst capped at 100 and persisted; oil was refused as unusable; `createdAt` survived a map reload. Test items were removed afterward.
- Remaining: in-client visual check of the food tooltip and band marker. Known pre-existing issue: a declined spot keeps state `declined`, so re-searching and accepting it fails with "There is nothing left here."

### Phase E: Validated Recipes and Atomic Den Crafting

- Add a versioned recipe registry under `content/data_static/` with validation for IDs, ingredients, quantities, output, requirements, duration, station tags, and optional quality rules. Invalid reloads must retain the last known-good registry.
- Implement a server crafting service that verifies player state, den-map access, station identity/range, recipe eligibility, profession/skill requirements, and available ingredients. Client requests identify a recipe and count only; server owns all recipe data and output rolls.
- Make input removal and output placement atomic from the user's perspective. Handle stack splitting, inventory/stash capacity, persistence failures, duplicate submissions, and stale recipe IDs without consuming ingredients or granting duplicate results.
- Add craft-time progress and cancellation for leaving range/den, dying, disconnecting, station removal, and any additional Phase A interruption rules. Enforce a single active job per player unless queues are explicitly designed.
- Replace the current empty crafting panel with a server-fed recipe list, requirement/cost states, progress, and actionable failure feedback. Keep free-world crafting rejected.
- **Acceptance:** fixture tests cover schema failures and recipe resolution; transaction tests verify ingredients/results roll back together; exploit tests cover request replay/range/station checks; live den tests craft food and ammunition and test cancellation/full inventory.

#### Phase E checkpoint: den crafting complete

- Added `recipe_definitions.json` (`recipeVersion` 1) validated by `ZM_StaticData`: id pattern, category, station tag, craft time, level/stat/job requirements, ingredient/result stacks, weapon and mastercraft exclusions, self-loops, and food `freshness` (`new`/`inherit`). New materials `itemScrapMetal`, `itemCloth`, `itemGunpowder` (`lootGenericMaterials`, in car and scrapyard dumpster loot) and cooked `itemBeanStew`. Five workbench recipes: boiled water, bean stew, cloth bandage (Medicine 1), 9mm ammunition, and shotgun shells (level 4, WeaponCrafting 2).
- `ZM_CraftingService` gates on alive/den/station range/requirements/ingredients, runs one timed job per player, and swaps each batch's ingredients for results in one `Service:Mutate`. `ZM_ReplacePlayerAndDenStashItems` writes backpack and stash in a single SQL transaction (`ZM_ReplaceDenStashItems` is now transactional too). Ingredients are not reserved at start: cancelling costs nothing and finished batches are kept.
- The crafting window is server-fed: recipes by category, requirement and have/need states, results, a batch count, progress, cancel, and failure messages.
- Static: GLua syntax 86/0, `zn_validate_static` 0 errors/0 warnings, static-data 13/13 (new `recipes_are_validated` fixture with 16 schema failures and shipped-recipe expectations), crafting 10/10, inventory 33/33, loot 12/12, loot spots 9/9, script validation 58/58, weapon catalog passed.
- Live (den `zz_preview_den_gr`, temporary workbench from `zn_dev_goto_station`): the crafting report showed `inDen=false` while the player was on a world cell; in the den, 2 batches of 9mm turned 4 scrap + 2 gunpowder into 40 `ammo9mm`; boiled water and bean stew crafted (oil taken from the oldest stack); cancelling kept the ingredients; shotgun shells were refused at level 1 and a 3-batch boiled water request was refused for missing barrel water. Test items were removed afterward. The full-inventory and interruption paths are covered by the automated tests only.
- Remaining: in-client check of the crafting window, and authoring a `zn_crafting_station` (and `zn_den_stash`) into the den safe-zone VMFs in Hammer.
- Fix: `zn_crafting_station` used a nonexistent model (`FurnitureWorkbench001a`), so it spawned as an ERROR with no physics and could not be used. It now uses `models/props_c17/furnituretable001a.mdl`, and both den entities log an error when their model yields no physics. Live: the spawned bench has physics and a trace from the player's eyes hits it.
- Future (not scheduled to a phase): split crafting into dedicated stations — ammunition at its own station, food at a cooker, and so on. Until then every recipe uses the workbench.

### Phase F: Profession Foundation and Daily Den Deliveries

- Reconcile canonical job IDs and current persisted `Job` behavior with Farmer, Doctor, Mechanic, Hunter, Scavenger, Chef, Police Officer, Army Soldier, and Scientist. Define starting bonuses and profession skills without conflating job identity with level/stat values.
- Implement an idempotent daily reward planner with persisted claim records, explicit day/time basis, per-job/level reward tables, bounds, and inventory-full policy. Repeated den visits, map changes, reconnects, and profile switches must not duplicate rewards.
- Start with Farmer, Doctor, and Mechanic reward tables to exercise food, medical, and crafting resources. Add Hunter, Scavenger, and Chef after the shared delivery service is stable. Police and Soldier receive only agreed combat/stat bonuses; Scientist gets research/service behavior rather than accidental daily grants.
- Implement chef cooking as a station service: the food owner supplies items, the chef's level/skill gates the service, and the operation atomically exchanges the agreed fee/inputs for a cooked result. Apply the same explicit ownership/payment/ingredient rules to scientist research and medical services.
- **Acceptance:** tests cover reward bands, exact-once claims, profile isolation, job changes, full capacity, and failed saves; live den checks verify daily delivery and a player-to-professional service flow.

#### Phase F checkpoint: professions and deliveries

- Decisions (user): the day boundary is midnight UTC on the server clock; rewards are banded by player level; jobs are set only by admin/dev command; services use the full customer→professional flow, where the customer supplies the items and pays a cash fee, and self-service is allowed at fee 0.
- Added `profession_definitions.json` (`professionVersion` 1) with Civilian (the default) plus the nine professions, aliases (Medic, Police, Soldier), stat bonuses (at most 5 per attribute, 6 total), services, and level-banded deliveries. Farmer, Doctor, Mechanic, Hunter, Scavenger, and Chef have deliveries; Police Officer and Army Soldier have stat bonuses only; Scientist has research only. `ZM_StaticData` validates the professions, recipe jobs (the hard-coded job list is gone), `cooksInto`, `medical`, and service recipes. There are 17 new items (produce, game bird, spices, four medical tiers, mechanic parts) and two Scientist research recipes.
- `ply:GetStat` adds the profession bonus at runtime; stored stats are unchanged, and stamina now reads through `GetStat`. `GetJobRole` returns the canonical id.
- `ZM_ProfessionService`:
  - A delivery is granted with a `profession_claims` row (primary key steamid+profile+day) in the same transaction as the items. `ZM_CommitWrites` and `Service:Mutate(..., { extraSteps })` let one save cover the items, the stash, the cash, and the claim.
  - Claims are keyed by day, not job, so a same-day job change gives nothing. Missed days are not accrued. A delivery that does not fit is refused, retried every 60 s, and notified once per day.
  - The cook, treat, and research services check the den, range, job, provider level, fee, and cash. They exchange the inputs, results, and fee in one transaction. Offers expire after 60 s and are cancelled on death, disconnect, or job change.
  - The client has a Services window (`zn_services`, and a button in the crafting window) and an accept/decline prompt.
- Static: GLua syntax 91/0, `zn_validate_static` 0 errors/0 warnings, static-data 15/15 (new `professions_are_validated` and `cooking_and_medical_items_are_validated` fixtures plus service-recipe cases), professions 12/12, crafting 10/10, inventory 33/33, loot 12/12, loot spots 9/9, enemies 10/10, script validation 62/62, weapon catalog passed.
- Live (den `zz_preview_den_gr`, one client):
  - As a Farmer, the first claim delivered 4 potatoes and 2 carrots, and a repeat was refused.
  - `zn_dev_advance_day 1` allowed exactly one new claim; offset 0 restored the day.
  - Self-service as Chef cooked 2 potatoes into baked potatoes; as Scientist, researched 2 painkillers; as Doctor at 40 HP, treated twice for +23 HP each (15 × 1.5).
  - Test items, claims, health, and the Civilian job were restored afterward.
- Follow-up: den NPCs that act as professionals are scheduled in Phase I, alongside the NPC traders.
- Remaining: in-client check of the Services window, and a two-player offer/accept/fee flow (only one client was available, so the two-player path is covered by the automated tests only).

### Phase G: Implants and Loot/Character Modifiers

- Define implant definitions, acquisition tables, three-slot equipment state, persistence, removal/replacement rules, and effect caps. Keep implants out of ordinary inventory slots if the finalized contract treats them as persistent character enhancements.
- Implement one server-owned modifier aggregation service for loot odds, movement, XP, regeneration, and other approved effects. Define stacking and caps per effect; replicate only read-only summaries to clients.
- Add a small implant test set and controlled rare boss/high-danger acquisition sources. Loot modifiers may change only their documented loot probabilities and must not bypass activation, eligibility, or boss policies.
- **Acceptance:** tests cover slots, equip/remove, persistence, profile isolation, stacking/caps, and deterministic effect application; live play confirms UI summaries match authoritative effects.

#### Phase G checkpoint: implants and modifiers

- Decisions (user): implants are inventory items that a Doctor installs in the den; there are three typed slots (Neural, Ocular, Dermal), and each implant fits one type; a removed or replaced implant goes back to the customer's backpack. Implants survive death (assumed, because they are permanent enhancements); a character reset clears them.
- Decisions (implementation):
  - An effect's value is interpolated between the authored `[min, max]` by the instance level across the item's `minLevel..maxLevel`.
  - Effects from all installed implants add up per effect, and each sum is clamped to a cap in `ZM_StaticData.ImplantEffects`. There is also a per-implant limit.
  - Loot effects multiply entry weights by `1 + bonus` for entries whose item `lootCategory` matches. They apply only to the searcher's loot-spot rolls and the killer's enemy drops. They never apply to boss loot, activation chance, drop chance, or counts, and the implants category is never boosted.
  - `xpGain` scales positive XP awards (rounded). `moveSpeed` scales walk/run speed from a stored base. `healthRegen` is HP per minute on a 1 s tick that carries fractions.
- Data: `implant` and `lootCategory` item fields. Every item gets a derived `lootCategory` (weapons, ammo, medical, food, cash, materials, implants, other); the bandage and cash bundle set it explicitly. Six implants (two per slot, levels 1–50), a `lootImplants` group (weight 0–0.05 by danger) in the generic zombie and car loot, boss-only implant entries in `lootBossRewards`, and the Doctor `implant`/`extract` services.
- `ZM_ImplantService` stores installed implants in `player_implants` (steamid+profile+slot), not in the inventory. Install and extract run in one `Service:Mutate` with a `playerImplants` commit step plus any fee, so the backpack, implant rows, and cash change together. The provider's level must be at least the implant's level; extraction needs a free backpack slot. The Services window shows the slots and capped effects; `zn_implants` reports them and `zn_dev_clear_implants` deletes them.
- Static: GLua syntax 94/0, `zn_validate_static` 0 errors/0 warnings (61 items, 6 implants), static-data 16/16 (new `implants_and_loot_categories_are_validated` fixture and shipped loot-category/implant expectations), implants 9/9, professions 12/12, crafting 10/10, inventory 33/33, loot 12/12, loot spots 9/9, enemies 10/10, bosses 5/5, weapon catalog passed.
- Live (den `zz_preview_den_gr`, one client, as Doctor, self-service):
  - Installed a level-1 Regeneration Mesh; at 50 HP, health rose to 51 after one minute (1 HP/min).
  - After a map reload the implant was still installed.
  - Installing the Myofiber Weave replaced it and returned the mesh to the backpack. Walk/run speed went from 200/320 to 206/329.6, and back to 200/320 after extraction.
  - The first live run found that float-stored speeds made the base recapture drift; the comparison now uses a tolerance.
  - Test items, the job, and health were restored afterward.
- Known gap: `ZM_Bosses:OnBossKilled` is not called anywhere yet, so boss rewards (including the boss implant entries) are not delivered. This predates Phase G.
- Remaining: an in-client look at the implant panel and the install/extract choices in the Services window; the death→respawn speed reapply path (covered by the `PlayerSpawn` hook, not yet exercised live); a two-player paid install.

### Phase H: Credits and Mastercrafting Service

- Implement profile-scoped credits as an in-game currency with bounded values, transactional updates, and a clear audit/debug path. Do not implement purchases with real money in Alpha 2.8.
- Define mastercrafting costs, eligible items, generated attributes, ultra-mastercraft odds/definition, identity/replacement behavior, and whether all resources are spent on every attempt. Enforce the no-repeat-attempt rule through server persistence rather than client UI state.
- Add a den-only mastercraft station and UI. Server validates item ownership, station/range, cost, materials, and one-use request identity; the client cannot submit attribute scores or outcomes.
- Add skill-point reset and appearance/job changes only if the credit contract and existing progression/appearance APIs support them; otherwise document them as deferred, not implicit station features.
- **Acceptance:** tests cover cost deduction, failed-save rollback, replay, attribute bounds/distributions, ultra-mastercraft probability, and item identity; live tests complete an ordinary and a controlled test mastercraft attempt.

#### Phase H checkpoint: credits and mastercrafting (static only)

- Decisions (user): a mastercraft upgrades an existing ordinary weapon in place; the price is credits only and scales with weapon level; credits come from admin/dev grants only for now (no boss credits); the station also sells a job change. Skill-point reset and appearance changes are deferred because there is no spending or appearance API.
- Decisions (implementation):
  - Credits are stored in their own `player_credits` table, so the whole-row player_data save cannot overwrite them. They are whole numbers from 0 to 1,000,000 per profile, and every change writes a `credit_ledger` row. Credits survive death and a character reset (assumed).
  - A credit step only updates the row if the stored balance still equals the expected one. A stale in-memory balance therefore fails the whole transaction.
  - Prices are in `den_service_definitions.json`: mastercraft `5 + ceil(level x 0.5)`, job change 25, ultra chance 1%.
  - A mastercraft needs an ordinary weapon with attributes in the backpack (not equipped or stashed), in a den, within 128 units of `zn_mastercraft_station`. The weapon keeps its instance id and level. It is saved in one `Service:Mutate` with the credit step and a `mastercraft_attempts` row, and that table's primary key blocks a second attempt on the same instance. Ultra means every attribute is at the maximum; it is worth 5x and shown as "(Ultra MC)".
  - Requests are quoted under a single-use, 60 s token. A confirmation consumes the token, re-checks everything, and refuses a changed price. The client sends only the action and the id.
  - A job change saves the `job` and credit steps together, then applies the job through `ZM_ProfessionService:ApplyJob`, which also cancels open offers.
- Static: GLua syntax 101/0. The new `zn_test_mastercraft` suite (9 cases: cost formula, credit bounds/ledger/profile isolation, stale-balance refusal, in-place mastercraft, failed-save rollback, quote replay/expiry/price change, eligibility gates, Ultra rate and forced Ultra, paid job change), the `den_services_are_validated` fixture, and the shipped den-service expectations are written but **have not run yet**, because Garry's Mod was not running.
- Remaining:
  - Reload `zz_preview_den_gr`, then run `zn_validate_static`, `zn_test_static_data`, `zn_test_mastercraft`, and the other suites.
  - Live: `zn_grant_credits 100`, `zn_dev_goto_mastercraft` (confirm the Combine interface model has physics), an ordinary mastercraft and a controlled one with `zn_station_confirm current <seed>`, and a paid job change.
  - The in-client station window, the confirm dialog, and the Ultra message.

### Phase I: Offline Den Trading Prototype

- Scope initial trading to deterministic AI/predefined offers in preview/local play. Keep player-to-player trade and online service authority outside this phase; do not add real-money credit purchasing.
- Define stock, offer refresh, cash/credit pricing, den danger availability, purchase/sale limits, and a low-level essential-ammo floor so progression does not make basic supplies inaccessible in safer dens.
- Implement buys/sells through atomic server-side inventory and currency transactions. Protect against stale offers, repeated requests, full inventory, stock races, map transitions, and persistence errors.
- Build den trading UI that distinguishes cash and credits and shows level, quality, ammo compatibility, stock, and total cost. Keep offer generation deterministic for fixture tests.
- **Den NPC professionals** (requested after Phase F). Add one placeable den NPC entity that can be a trader, a professional, or both, and that Hammer or the dev tools can place around the den.
  - **Entity settings:** a profession id resolved through `ZM_Professions`, a service level, and a fee table set per NPC. Validate these against the profession registry; an NPC with an unknown profession offers nothing.
  - **Services flow:** add a provider abstraction to `ZM_ProfessionService` so `CheckService` and `PerformService` accept either a player or an NPC.
    - A nearby NPC appears in the Services window's provider list, which currently says "No professionals nearby" when there are none.
    - NPCs accept automatically. There is no offer prompt and no provider-side inventory or cash row: the fee is taken from the customer and nobody is credited.
    - The NPC's configured level stands in for the player level cap.
    - Keep the same den, range, alive, and item-level checks, and the same single-transaction save.
  - **Scope:** NPCs never claim daily deliveries and never hold persistent inventory.
  - **Acceptance:** tests cover each service against an NPC provider (fee, rollback, level cap, unknown profession, out of range). Live, an NPC Chef, Doctor, and Scientist placed in `zz_preview_den_gr` each complete a service.
- **Acceptance:** tests cover price bounds, stock, purchase/sale rollback, full inventory, duplicate requests, and profile isolation; live preview checks trade across at least two den danger tiers.

#### Phase I checkpoint: den trading and NPC professionals (static only)

- Decisions (user): stock is shared by everyone in a den and resets at midnight UTC; cash buys ordinary goods and credits buy only rare offers (mastercraft weapons and implants); selling always pays cash; traders sell at 1.5x item value and buy at 0.4x; NPCs are placed only as Hammer point entities configured by keyvalues (a temporary dev spawn command exists for testing).
- Decisions (implementation):
  - `content/data_static/trade_definitions.json` holds the multipliers, a 20-unit purchase cap, a 2,500 cash daily sale limit per player, the NPC service fees, the essential-ammo floor (10 x 30 rounds of 9mm, shells, 5.56, 7.62), and three trader tables (`general`, `quartermaster`, `clinic`). The validator rejects cash offers, cash/implant buying, mastercraft or implant offers without credits, mastercraft offers of non-weapons, ammo floors that no weapon uses, and a sell multiplier at or above the buy multiplier.
  - Daily stock, level, and attributes are seeded from profile, den, trader, UTC day, offer key, and item (not danger), and only the units sold are stored (`trade_stock`). Offer keys are the 1-based offer index, so reordering a trader's offers changes that day's stock. Only weapons scale with danger (up to halfway through their level range); other goods are offered at their minimum level.
  - A buy or sell is one `Service:Mutate` plus the currency step, a compare-and-set `tradeStock` step (it fails if the sold count changed), and a `trade_ledger` row whose unique request id blocks replays. The sale limit is checked before the save and again inside the transaction. The server rebuilds the offer and refuses a stale day, price, currency, or stock; after a map change the NPC reference is gone and the request is refused.
  - Den NPCs (`zn_den_npc`, `sv_den_npcs.lua`) are providers in `ZM_ProfessionService`: they skip the offer prompt, charge their configured fee (the fee must match what the client saw), hold no inventory or cash, and their `service_level` caps item levels. The Services window lists them as `n:<entIndex>` providers; players are `p:<userId>`.
- Static: GLua syntax 108/0. The `zn_test_trading` suite (14 cases: shipped data, deterministic shared stock and sold-out, price multipliers, danger gating and the essential-ammo floor, cash buy with ledger and replay, credit buy, stale day/price/currency/stock, full-backpack and failed-save rollback, sales and the daily limit, unsellable items, den/range/trader checks, NPC settings, NPC Chef/Doctor/Scientist services, NPC refusals and rollback), the `trade_is_validated` fixture, and the shipped trade expectations are written but **have not run yet**, because Garry's Mod was not running.
- Remaining:
  - Reload `zz_preview_den_gr`, then run `zn_validate_static`, `zn_test_static_data`, `zn_test_trading`, `zn_test_professions`, and the unrun Phase H suites.
  - Live: `zn_dev_spawn_den_npc Chef 10 -`, `Doctor`, and `Scientist`, each completing a service through `zn_service ... - npc`; `zn_dev_spawn_den_npc none 1 general`, then `zn_trade`, `zn_trade_buy ammo:ammo9mm 1 r1`, a replay of `r1`, and `zn_trade_sell`; repeat with `zn_dev_trade_danger 0.8` for a second danger tier (only one preview den exists).
  - Place Chef, Doctor, Scientist, and trader NPCs in the `zz_preview_den_gr` VMF in Hammer and recompile.
  - The in-client trading window, the NPC entries in the Services window, and the NPC name labels.

### Phase J: Integration, Walker Regression, and Release

- Update item/recipe/profession/ammo/implant/currency/trading documentation and schemas. Keep generated runtime exports and staged assets as pipeline outputs.
- Run GLua syntax checks, static-data validation, and all affected focused suites for inventory, weapons, ammo, food, crafting, professions, implants, currency, and trade.
- Validate the integrated slice in preview: profile persistence, map transitions, den stash/deposit, death behavior, ammo sync, food freshness, craft interruption, daily rewards, and service/economy transactions.
- **Do the Walker regression last**, after gameplay and data changes are settled: regenerate the current preview world, refresh plans and VMFs, restage the required maps, rerun the documented navmesh pipeline, then verify Walker operation in game. Inspect the exact generated reports/artifacts; do not trust stale preview files.
- Run one deliberate end-to-end session and record static versus live results separately. Only stage/validate production after preview acceptance is clear.
- **Acceptance:** automated checks pass; live checks pass or have explicit blockers; preview artifacts match current sources; known limitations and follow-ups are recorded before marking Alpha 2.8 complete.

#### Phase J checkpoint: integration (2026-09-27)

- Refactor before integration: repeated server helpers moved to `ZM_Util` (`gamemode/utils/server.lua`) and every `zn_test_*` suite except the static-data and weapon-catalog ones moved to `ZM_TestHarness` (`gamemode/utils/test_harness.lua`).
- Static: GLua syntax 110/0.
- Live, automated (preview, `zz_preview_den_gr`): `zn_validate_static` passes. All 12 suites pass: static data 18, weapon catalog, inventory 33, loot 12, loot spots 9, enemies 10, bosses 5, crafting 10, implants 9, professions 12, mastercraft 9, trading 14. This is the first live run of the Phase H and I suites. It found three problems, now fixed:
  - `bad_trade.json` set `sellMultiplier` out of range, so the "below buyMultiplier" rule never ran. The fixture now uses 1 and 1.
  - A mastercraft confirmation with the wrong token kept the pending quote, so the next confirmation spent it. Any confirmation attempt now discards the quote, as the contract states.
  - Two trading test fixtures were wrong: a crowbar below its minimum level, and too little cash for the full-backpack case.
- Live, manual through the bridge:
  - Trading: a trader NPC sold and bought, and replayed request ids for both were refused. Offers differ correctly between the Safe (0.2) and Deadly (0.8) tiers (Military Ration only when Deadly, crowbar level 12 vs 18). The essential-ammo floor is present in both. In-game trading-window buys and sells also saved with ledger rows, and cash matched in memory and SQL.
  - NPC services: Chef cook (potato to baked potato), Doctor treat (health 50 to 73), and Scientist research (herbs and water to 2 painkillers). The fees came to exactly 35 cash.
  - Credits and mastercraft: `zn_grant_credits`, a station with physics, a seeded mastercraft (6 credits, "(MC)"), a refused second attempt, and a paid job change (25). The ledger balances match.
  - Persistence: after `changelevel` of the den, the inventory (instance ids and the mastercraft flag), credits, and job were identical.
- Not exercised live: firing/reload ammo sync, death loss, craft interruption in a real session, and food spoilage over real time. A cross-map transition was exercised during Phase K through `zombiesim_dev_teleport_cell 0 0` into preview city cell 0 and back to the origin den; the interactive border gate remains unverified. Visual checks of every Alpha 2.8 window are deferred to the end, as agreed.
- Walker regression: the preview world, plan, and VMFs were regenerated (163 recipes, 6 stale files pruned). The portal preflight reports 66 of 168 maps over the 250-cluster budget; this is a diagnostic, not a compile failure, and there is no earlier baseline to compare against.
- Walker freshness recheck before regeneration (2026-09-27): the prior `navmesh_validation_preview.json` and `navmesh_wireframes_preview.json` identified revision `46131b60467053b45f02bbbec7840b5e62fc0636f35343053d4e2ee4c44942f7` (25 maps, updated 2026-09-10), and the saved global batch was a cancelled `city` run (184/312). Those stale reports did not verify the current preview Walker build; the fresh run below supersedes them.
- Fresh preview navmesh regression (2026-09-27): cleared only the 56 staged preview navmeshes, preserving the 177 engine-root city navmeshes; generated all 163 ordinary preview recipe maps against manifest revision `dd9d2a271f6987c3c3c2b5a2e01ec2c14799e3ddd7b3af85f15213648bcf9c3b`. The final preview validation manifest is complete (163 required, 163 results, 0 failures); every map has a positive area count, a persisted `.nav`, and the matching runtime revision. Safe-zone maps are intentionally excluded. Staged all 163 navmeshes and rebuilt the preview wireframe (576 cells rendered, 0 unavailable, 0 invalid).
- The first live Walker check exposed a profile identity bug: the native importer compared the requested profile to `world.mapDirectory`, which is intentionally empty for flat-staged maps. Runtime export now writes `world.profileId`; the native importer validates that independent field. Walker core tests pass, the rebuilt API v3 module is installed, and after restarting Garry's Mod the live module smoke passed. In city cell 0, `zombiesim_navmesh_status` reported preview revision `dd9d2a271f6987c3c3c2b5a2e01ec2c14799e3ddd7b3af85f15213648bcf9c3b`, a loaded navmesh with 633 areas, and a visible nav file. The Walker worker ran for preview at active cell 0 (tick 151); a noise probe was accepted and the worker advanced to tick 214 / 48 accepted commands with no error.
- The Phase K visibility recheck supersedes the old 250-cluster count: the current diagnostic limits are 500 clusters / 900 portals, with 17 maps still over one of those limits.

### Phase K: Mounted Asset Catalog and Semantic World Loot

- Document the installed Garry's Mod asset layout for future contributors: the Steam library's `GarrysMod\garrysmod` content directory, `garrysmod_dir.vpk` and other mounted VPKs (notably the bundled HL2/CSS archives under `GarrysMod\sourceengine`), enabled addons/mounted games, and `bin\vpk.exe`. Use `vpk.exe l <archive>` to inspect virtual paths; do not extract or copy Valve-owned game assets into addon content.
- Item icons already render the item's mounted `iconModel`/`worldModel` as a spawn icon (see `readme.md`, Item Icons). Catalog-generated items should set a reviewed `iconModel` rather than authoring PNG thumbnails.
- Build a repeatable metadata-only catalog of item-candidate assets from the installed/mounted VPKs. Record the virtual model path, source archive, asset family/tags, and whether the asset is mounted and suitable for an item. Filter out non-item assets and duplicate aliases rather than turning every model file into a gameplay item.
- Use the catalog to add stable, curated item definitions with meaningful names, categories, stack/level/value bounds, and mounted model references. Keep authored item data in `content/data_static/`; keep catalog scans and reports under `generated/`.
- Map explicitly supported world container classes and model families to semantic loot groups using `content/data_static/entity_loot.json` and the existing loot registry. Vending machines should favor drinks; ammo boxes and military containers should favor weapons/ammunition; ordinary crates should use an appropriate general-supplies group. Add more families only with reviewed contents and bounded loot policies.
- Keep loot deterministic, danger/level-aware, and server-authoritative. Unknown or unsupported props must not fall through to generic loot; verify that model/class matching cannot turn arbitrary props into valuable drops.
- Add fixture coverage for candidate deduplication, missing/unmounted models, class/model-to-group mappings, and category-specific loot eligibility. Check representative placed containers in a live preview session.
- **Acceptance:** the catalog can be regenerated from installed assets without committing extracted game files; all generated item references resolve to mounted assets; representative vending, ammo/military, and ordinary crate props yield only their intended loot families; unsupported props yield no loot; static and live checks pass.

#### Phase K checkpoint: mounted catalog and semantic loot (2026-09-27)

- Added `bin/build_mounted_asset_catalog.ps1` and its shared helpers in `bin/mounted_asset_catalog.psm1`. The metadata-only scan uses `bin\vpk.exe l`, covers the installed `garrysmod` and `sourceengine` VPKs plus `mount.cfg` roots, marks disabled archives unmounted, normalizes/deduplicates virtual paths, and writes only to `generated/asset_catalog/`.
- The current installed archives produce 585 filtered catalog records across 8 VPK archives; all 585 resolve to mounted archives. Candidate records include source archive(s), model family/tags, mounted status, item suitability, and authored item/container-model reference usages. Existing reviewed item definitions are reused; no duplicate gameplay items or copied Valve assets were added.
- Added explicit, model-specific vending, HL2/CSS ammunition and military-crate, and ordinary-crate mappings. Their bounded groups contain only hydrating foods, weapons/ammunition, or food/medical/material supplies respectively. Unlisted props still have no rule and cannot fall through to generic loot.
- Added `bin/test_mounted_asset_catalog.ps1` fixtures for canonical-path deduplication, missing/unmounted assets, inventory-item suitability, all item and container model references, semantic class/model/group assignments, and category eligibility. Offline catalog checks pass (2,074 assertions); GLua syntax passes for 110 files.
- Live preview (`zn_preview_start`): `zn_validate_static` reports 61 items, 21 loot groups, and 30 entity rules with no errors or warnings; `zn_test_static_data` passes 18/18 and `zn_test_loot_spots` passes 10/10, including the new semantic-family case.
- Added the isolated developer-only `celltemplates/dev/zz_preview_loot_fixture.vmf`, based on the authored den layout and containing CSS/HL2 vending machines, an HL2 ammunition crate, a CSS military crate, an ordinary wooden crate, and an unsupported cardboard prop. It is outside the template plan and does not change gameplay maps. Its one-map VBSP, VVIS, and VRAD stages all completed successfully.
- Live city-cell check: temporarily substituted the compiled fixture for the preview recipe BSP selected for city cell 0, then used the normal `zombiesim_dev_teleport_cell 0 0` transition. `zn_loot_spots` loaded cell 0 at danger 0.5 and found exactly the five supported map props (both vending models and three crates); the cardboard prop was not a loot candidate. `zn_dev_loot_offer` ran the real BeginSearch/CompleteSearch/RespondOffer path and declined without granting inventory: vending offered `itemSodaCan` x2, an ordinary crate offered `itemRottenFood` x1, and the ammo crate offered `ammo9mm` x10. The candidate count excludes the unsupported cardboard prop. Original preview city BSPs were hash-restored, then the player returned to the origin den.
- Follow-up live probes individually confirmed the HL2 soda vending model offers `itemSodaCan` x1 and the CSS military crate offers `ammo9mm` x16; both were declined without granting inventory. The game returned to `zz_preview_den_gr`, and both staged and source preview city BSPs were verified against their original backup SHA256 before temporary build outputs were removed.
- The live probe exposed a declined-spot regression: a declined item could be re-offered but `RespondOffer` then rejected it because the spot remained in `declined` state. `CompleteSearch` now persists/reopens the same item as available before sending its next offer. Added a regression to `decline_keeps_same_item_across_reloads`; live `zn_test_loot_spots` passes 10/10 after the fix.
- Raised `compilation.visibilityBudget.maxPortalClusters` from 250 to 500 (900 portals unchanged); updated the script fallback and docs. This is a diagnostic threshold, not an engine limit.
- The current `-ListOnly` visibility report uses the new 500/900 limits and has 17 over-budget maps. For example, `zz_preview_8e9b52d6d08e` has 393 clusters (under the new cluster threshold) but 1,272 portals (over the unchanged portal threshold); no full-world VVIS/VRAD build was run.
- **Phase K accepted:** catalog regeneration and checks pass; all authored item/container model references resolve to mounted assets; representative containers were loaded and searched in an active live preview city cell and yielded only their intended loot families; unsupported props remain unmatched; static and live checks pass. No production-world regeneration or compile was needed for this data/runtime change.

### Alpha 2.8 closure status — accepted 2026-09-27

- **Accepted:** Fresh preview navmesh generation and live Walker smoke/regression on artifacts whose runtime revision matches the current preview index (see Phase J follow-up above).
- **Accepted:** The operator confirms the in-game ammo behavior works, the updated weapon tooltip is clear, and the Alpha 2.8 UI visual reviews look good.
- **Accepted:** Live development-server regression suites pass: inventory 34/34, crafting 10/10, enemies 10/10. Coverage includes ammo conservation/reload, backpack loss with stash retention, interrupted crafting without ingredient consumption, food freshness/offline aging/spoiled use, weapon-level/stat gates, and ordinary-zombie corpse-loot registration.
- **Deferred by operator, non-blocking for this milestone:** Manually kill an ordinary zombie, search its corpse, and accept or decline the offer. A follow-up fix explicitly creates a `prop_ragdoll` for ordinary walkers (the prior `BecomeRagdoll` path returned no usable corpse); the live enemy regression now verifies ragdoll creation and loot registration. The real kill/search/offer interaction is left for later.
- **Post-closure ragdoll behavior:** Walker corpses use `COLLISION_GROUP_DEBRIS` so they do not collide with players. Corpses with loot remain until looted; corpses without loot begin a five-second fade after 60 seconds. The live enemy regression verifies collision groups and lootable/nonlootable fade scheduling; see the 2026-09-27 corpse behavior entry in the test log.
- No destructive live death test was run against the operator's persistent character, and freshness/spoilage was validated through deterministic service tests rather than waiting for real time to elapse. These are the limits of the recorded evidence, not failed checks.
- **Alpha 2.8 is closed** with the ordinary-zombie corpse interaction retained as an explicit follow-up.

## Cross-Phase Rules

- Keep inventory, weapon firing, ammo, loot, crafting, job rewards, implants, currency, and trading outcomes server-authoritative. Client code expresses intent and displays server snapshots/results.
- Preserve Alpha 2.7 profile isolation, inventory persistence, death-loss, and den-stash semantics unless a recorded Phase A decision changes them. Persistence changes require migration, failure, rollback, and profile-isolation tests.
- Add content in bounded batches. Do not bulk-import all CSS weapons or food before the first representative vertical slice passes data validation, automated tests, and a focused live check.
- Record decisions and dependencies in this tracker before implementing any ambiguous mechanic; speculative prototype text is not by itself an implementation contract.
- For every runtime/UI change, report static validation and in-game verification separately. Regenerate current preview artifacts before world-dependent testing.
