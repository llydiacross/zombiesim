# Item, Loot and enemy/boss prototype

A plan for a new json data_static powered system for use in the item system and loot system and enemy definition system and also notes on how we might scale the weapons found in the game using attributes. With the minimum level of an item giving pretty poor attributes, and the maximum level of an item giving very good attributes. Also contains notes on how to implement game stage scalable enemy spawning so that is as customizable as possible.

# item_definitions.json

- types of items
  - generic entity item (wood, scraps, stuff used in crafting recepies)
  - entity item (a usable item such as a health item, or a food item)
  - weapon item (an equippable item which can be used as a SWEP)
  - armour item (an equippable item which can be used as armour to protect the player)
  - clothing item (an equippable item which can be used as clothing for the player)

## some item properties might include

 - statRequirements:
  - required attribute stats to use the item
- minLevel - the minimum level this item can be, also acts as the requiredLevel to use it
- maxLevel - the max level this item can scale too 
- name
- name of the item
- value 
  - the default value of an item

- attributes


   - Damage (for all weapons) 
   - Range (for all weapons and melee weapons) 
   - Firing Speed (for bullet weapons)
   - Swiftness (for melee weapons)
   - Crushing (for melee weapons)
   - Reload Speed (for all weapons)
   - Clip Size (for bullet weapons)
   - Durability (for armour only)
   - Protection (for armour only)
   - Mobility (for armour only)
   - Radiation Resistance (for armour only)

- if the item is a bullet weapon or armour etc etc, it will have different stats

- it works out which attributes to use and are applicable through the type key (bullet_weapon, melee_weapon)

  - Note: The attributes needs to be generated for item weapon and armor item in the game depending on its current level using its minLevel and its maxLevel so the level of an item will need to be decided first with the maximum level of the item being roughly translated to equal the highest possible attributes relative to the maxAttribute value with (1 or 2) missing. If the item is mastercrafted, then the attributes will always be equal the max attribute level no matter what level it is
  - For instance, if a weapon like the crowbar has the lowest level being 10, and a max level of 32, for each maybe 5/10% of the distance it takes to reach the maxLevel of the current item, it should increment each of valid attributes a little bit based on the level of the item you find. Also, when you find attributes they should VERY rarely all equal the same number. for instance, 6 damage, 6 ranage or 6 firing speed, it should be 5, 4, 3, only max out the attributes if it is master crafted, but even still they should VERY RARELY be matching attributes as these are a super special type of mastercraft.
  - Note: These would never be defined by hand in the item_definitions them selves
  - The attributes need to affect the areas of the weapon or armour they specify in game in garrysmod, more damage means the weapon is better. The weapons only get scaled by the attributes, level is only important for allowing more attributes to appear with higher values, but its really the attributes which balance the weapons.

- minAttributes: used in scaling the weapon, the minimim possible attribute count for this weapon, defaults to 2
- maxAttributes: the maximum possible attribute stats this weapon might have, defaults to 32. 
- mastercraft (bool): if the weapon is master crafted (the attributes will be and are the best possible for that weapon)
- iconThumbnail
- type: what type of item this is (used to generate attributes, by default if it is omitted no attributes will be generated)
  - bullet_weapon
  - melee_weapon
  - heavy_armour
  - light_armour

## Pseudo Json Example

```jsonl
"itemGas": {
 "entityClass": "generic", // cannot be used, only used in crafting and stuff
 "thumbnail": "itemGas", // a png in content/materials/items/
 "value": 1.59, // $1.59 per 1 unit (gallon)
 "maxStack": 300, // 300 gallons
 "unit": "gallon" // for ui purposes, defaults to none (will just show stack number)
}

// requires no doctor to apply but does give the healing item a 2x bonus if applied by a doctor
"itemBandage": {
 "entityClass": "entity", /// will look for a class/table/member in some sort of table to find and call call the use functions for "itemBandage" or use generic one
 "thumbnail": "itemBandage", // a png in content/materials/items/
 "value": 2, // $8 per 1 unit
 "maxStack": 3  // 3 bandages
}

// requires no doctor to apply 
"itemPainkiller": {
 "entityClass": "entity", // will look for a class/table/member in some sort of table to find and call call the use functions for "itemPainkiller" or use generic one
 "thumbnail": "itemPainkiller", // a png in content/materials/items/
 "minLevel": 10,
 "value": 2, // $8 per 1 unit
 "maxStack": 3,  // 3 bandages
}

// requires no doctor to apply 
"itemAsprin": {
 "entityClass": "entity", 
 "thumbnail": "itemAntibiotics", // a png in content/materials/items/
 "minLevel": 25,// what level you have to be to use this item, 
 "value": 2, // $8 per 1 unit
 "maxStack": 3  // 3 bandages
}

// requires a doctor to apply
"itemAntibiotics": {
 "entityClass": "entity",
"statRequirements": {
"Medical": 5 // 5 medical skill points to use this item or you can get a doctor to apply it for you at a cost for their services
},
 "thumbnail": "itemAntibiotics", // a png in content/materials/items/
 "minLevel": 25,
 "value": 2, // $8 per 1 unit
 "maxStack": 3,  // 3 bandages
}

// weapon example
// weapons can be found mastercrafted, max attributes for a weapon default to 20, these attributes scale various parameters of the weapon
"weaponMeleeCrowbar": {
 "entityClass": "weapon", // will look for a SWEP named zn_ weapon_melee_baseball_bat when equipped/used in the inventory
"statRequirements": {
"Strength": 5 // 5 strength points needed to use the bat
},
"type": "melee_weapon", // very imporant for attribute generation when creating this new item
"minLevel": 10,  // the minium level this weapon can be, this will be based on the level you currently are when you found it and also will be scaled to the danger of the cell the weapon is found, if you are level 12 and your current cell danger is 0, you will find a minimum level though, just because you might be a high level does not automatically equal a high level item, only if the cell danger is high, if the cell danger is high and your level is high, you will just find maxLevel or close to maxLevel depending on RNG
"maxLevel": 30, // the highest level this weapon can be, if you find it at level 25 for instance but your current cell danger is 0.2, you will be (1+) extra level, if you find it at level 25 and your cell danger is 0.5, you should for instance get (3+) extra level (math rounted to nearest whole number), if you find it at level 25 and your cell damage is 1, you should for instance get 5+ extra levels
 "thumbnail": "weaponMeleeCrowbar", // a png in content/materials/items/ which is used in the inventory, if not specified will just default to name of item
 "value": 200, // $200 per 1, value significantly goes up if the item is mastercrafted, value should also scale with level and attribute value
 "maxStack": 1,
 "mastercrafted": false, // this item is always master crafted if this is set to true, when the item is created/looted the item will have the attributes to the level of the maxAttribute
}
```
- the rest of the items etc...

# recipie_definitions.json
 
 - a small pseudo mock up of how recipies could potentially work

```json
{
  "recipeBandage": {
    "name": "Sterile Bandage",
    "category": "Medical",
    "craftTime": 2.0,
    "station": "none",
    "levelRequirement": 1,
    "statRequirements": {
      "Medical": 1
    },
    "ingredients": [
      { "item": "itemCloth", "count": 2 },
      { "item": "itemAlcohol", "count": 1 }
    ],
    "results": [
      { "item": "itemBandage", "count": 1 }
    ]
  },
  "recipeCrowbarMastercraft": {
    "name": "Reinforced Crowbar",
    "category": "Weapons",
    "craftTime": 10.0,
    "station": "workbench",
    "levelRequirement": 15,
    "statRequirements": {
      "Strength": 10,
      "Crafting": 5
    },
    "ingredients": [
      { "item": "weaponMeleeCrowbar", "count": 1 },
      { "item": "itemScrapMetal", "count": 10 },
      { "item": "itemGas", "count": 5 }
    ],
    "results": [
      { "item": "weaponMeleeCrowbar", "count": 1, "mastercraft": true }
    ]
  }
}
```

- Note: Setting "mastercraft": true on a craftable result (like in recipeCrowbarMastercraft) forces the generated item instance to roll max attributes, consistent with the loot system rules.   
- Note: recipeCrowbarMastercraft is just an example and usually you cannot craft a mastercraft like this and instead have to use a special entity in the den which requires a special type of credit currency to use. Will be added in the future.
- Note: You can only craft these recipies in the den via the crafting table entity which will open a crafting UI window. Will be added in the future.

# enemy_definitions.json

 - contains raw defnitions for enemys which we can spawn through the walkersim ticketing system or via other methods if no binary is possible
 - min rarity and max rarity are to do with spawning the enemy are scaled by the damage of the current cell
 - min danger and max danger decides the danger range this entity can spawn in
 - min loot drop chance and max loot drop chance decide the chance the entity will be lootable when killed. Max loot drop chance is the maximum chance the entity can drop loot, scaled to the cells damage. This is not a weighted randomised value, but just a randomised precentage.
 - loot group can contain one single loot_table definition or multiple
 - if the entity is a boss they will always drop loot when they are killed and also appear on the minimap/world map
  - we don't use weights for enemy spawning, instead using percentage random, since there are so many possible enemy spawns

## Pseudo Json Example

```jsonl
 "entityWalker": {
   "entity": "npc_zombiesim_walker",
   "minHealth": 19, // scale depending on danger of current cell
   "maxHealth": 30,
   "minSpeed": 1 // how fast they are,
   "maxSpeed": 1, // defaults to min speed if not present
   "minDanger": 0, // spawns in all cells over damage 0
   "maxDanger": 0.75, // spawns in all cells with damage less than 0.75
   "minRarity": 0.75, // spawn 75% of the time, min is equal to current damage of the cell
   "maxRarity": 0.20, // spawns 20% of the time in high damage cells
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005, // scales with danger of cell and acts only as a trigger for the lootGroup specified in this object and not an overrider for the loot groups settings
   "maxLootDropChance": 0.05, //  scales with danger of cell, high damage cells (or as max as the maxDanger value) will max out to 0.05 chance
   "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   // }, ["genericZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   //}]
  }

  "entityRareWalker": {
   "entity": "npc_zombiesim_walker", // can reuse the entity name
   "minHealth": 29, // scale depending on danger of current cell
   "maxHealth": 49,
   "minSpeed": 1, // how fast they are,
   "maxSpeed": 1.25, // defaults to min speed if not present
   "minDanger": 0.25, // spawns in all cells with damage above 0.25
   "maxDanger": 1, // spawns in all cells with damage below (1) (so all cells)
   "minRarity": 0.25, // spawn 25% of the time in low damage cels
   "maxRarity": 0.75, // spawn 75% of the time in high damage cells
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005, // scales with danger of cell and acts only as a trigger for the lootGroup specified in this object and not an overrider for the loot groups settings
   "maxLootDropChance": 0.25, //  scales with danger of cell, high damage cells (or as max as the maxxDanger value) will max out to 0.25
  "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   // }, ["rareZombieLoot", {
     // override? maybe if youw ant to use rareZombieLoot but make something in it more common
   //}]]
  }

 "entityRunner": {
   "entity": "npc_zombiesim_runner",
   "minHealth": 10,
   "maxHealth": 13,
   "minSpeed":  2, // how fast they are,
   "maxSpeed": 2.5,
   "minRarity": 0.25, // how common they are, max is defaulted to same Rarity as min, with low danger they are very rare
   "maxRarity": 0.15, // default walkers get less rare the more damage of a cell
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005, // scales with danger of cell
   "maxLootDropChance": 0.05, //  scales with danger of cell 
    "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   // }, ["genericZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   // }]]
  }

 "entityDog": {
   "entity": "npc_zombiesim_dog",
   "minHealth": 10,
   "maxHealth": 14,
   "minSpeed": 3.5, // how fast they are,
   "maxSpeed": 4,
   "minRarity": 0.01,
   "maxRarity": 0.1,
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.01, // scales with danger of cell
   "maxLootDropChance": 0.1, //  scales with danger of cell
    "lootGroup": "" // etc
  }
```

# enemy_spawns.json

- a mock up of different types of entities that can spawn in a cell
- each key is  made up of the value of the name in entity_definitions or an object with the key of the entity and defininig overrides

## Psedo Json Example

```jsonl
// enemies which can commonly be found in each cell
"cellGenericEnemies": ["entityWalker", "entityRareWalker", "entityDog", "entityRunner"]

// special definitions for each cell based on its environment tag
"cellRadiationEnemies": ["genericEnemies", "entityMutant", "entityPosinous"]
// if a cell environment tag doesn't have one it will fall back to the cellGenericEnemies entity spawn group
```

# boss_spawns.json

- how boss spawn definitions work, they would read from enemy_defitions which entity to spawn as a boss, bosses spawn on a random cell in the world. This file in theory would allow to set certian partamers to define when and how a boss spawns, maybe a boss only spawns in radioactive cells, maybe a boss only spawns once a day, or is spawns many times. Maybe it is a rare boss, or a super rare and super dangerous boss. Also, what loot does the boss drop? This would reference the loot tables

```json
{
  "bossTank": {
    "entityDefinition": "entityBossTank",
    "spawnConditions": {
      "minCellDanger": 0.5,
      "allowedEnvironmentTags": ["industrial", "military", "radiation"],
      "maxActiveWorldCount": 1,
      "cooldownHours": 12
    },
    "mapMarker": {
      "showOnMinimap": true,
      "icon": "hud/boss_tank_icon",
      "label": "Mutation Threat: Tank"
    },
    "lootGroup": ["lootBossMeleeWeapons", "lootBossGenericLoot"]
  },

  "bossPatientZero": {
    "entityDefinition": "entityBossPatientZero",
    "spawnConditions": {
      "minCellDanger": 0.8,
      "allowedEnvironmentTags": ["hospital", "radiation"],
      "maxActiveWorldCount": 1,
      "cooldownHours": 24
    },
    "mapMarker": {
      "showOnMinimap": true,
      "icon": "hud/boss_biohazard_icon",
      "label": "High Threat: Patient Zero"
    },
    "lootGroup": ["lootBossMeleeWeapons"]
  }
}
```

# loot.json

- maybe define some generic loot tables for food items, then medical items, then weapon items, then armour items, then crafting items
- tables for rare drops, extremely rare drops, ultra rare drops (cells with higher damage will drop more ultra rare drops)
- these groups are easily reusable and can be made up of multiple other groups (this is all parsed when the data is loaded into the game)
- loot tables for different types of things in games, cars, garbage bins, ambulances, police cars, fire trucks, petrol tankers 
- the keys inside of the item to spawn are just minWeight, maxWeight, mastercraft, mastercraftChance // by default weapons and armour have a 5% rate to be mastercrafted
- maybe it would look like:
- minWeight and maxWeight make up the Weighted Pool Roll of the item. With max weight values being their probability in high damage cells, and their min weight values being their probability in low damage cells. Lower weights mean it is more rare, higher weights mean it is more common

## Recommended Weight Ranges (Rule of Thumb)

A clean standard baseline scale to use across your `loot.json` tables is a **1 to 100 relative weight scale**:

| Rarity Class | Item Weight | Expected Outcome in a Standard Table |
| --- | --- | --- |
| **Common** (Junk, Basic Ammo, Bandages) | **50 – 100** | Generates frequently; dominates low-danger areas. |
| **Uncommon** (Steel Pipe, Flashlight, Gasoline) | **20 – 49** | Moderate drops; noticeable but not everywhere. |
| **Rare** (Glock, 9mm, Shotgun) | **5 – 19** | Harder to find; usually requires high cell danger. |
| **Very Rare / Boss** (Katana, Desert Eagle) | **1 – 4** | Exciting jackpot loot; drops rarely. |


## Psedo Json Example

 // can be a group or a singular item name or an override
```jsonl
 "entityPetrolTankerLoot": ["lootGenericCarLoot", { "lootGenericMeleeWeapons": {
  // override this wepaon
  "weaponMeleeCrowbar": {
      "minWeight": 30, // the Weight in more low damage cells, 30
      "maxWeight": 5, // the Weight in high damage cells, 2 = uncommon
      "mastercraft": false,
      "mastercraftChance": 0.5 // greater mastercraft chance if found
  }
}}]

// will be a combination of both loot groups
"lootGenericWeapons": ["lootGenericHandguns", "lootGenericMeleeWeapons"]

// key is the name of the loot group/table,
"lootGenericHandguns": {
  // key is the item name in item definition
 "weaponHandgun9mm": {
     "minWeight": 25, // more common in low damage cells
     "maxWeight": 10, // a bit less common in high damage cells
 },
 "weaponHandgunGlock": {
     "minWeight": 20, // less common in high damage cells
     "maxWeight": 30 // more common in high damage cells
 },
 "weaponHandgunDesertEagle": {
     "minWeight": 2,
     "maxWeight": 5 // more common in high damage cells
 },
 "weaponHandgunTec9": {
     "minWeight": 2,
     "maxWeight": 10 // more common in high damage cells
 },
 "weaponHandgunSilenced9mm": {
     "minWeight": 2,
     "maxWeight": 15 // very common in high damage cells
 }
}
```

A generic loot table for melee weapons

```jsonl
"lootGenericMeleeWeapons": {
    // key is the item name in item definition
 "weaponMeleeSteelPipe": {
     "minWeight": 45
 },
 "weaponMeleeTireIron": {
     "minWeight": 40
 }, 
 "weaponMeleeCrowbar": {
     "minWeight": 35
 },
 "weaponMeleeSledgehammer": {
     "minWeight": 30
 },
"weaponMeleeCattleProd": {
     "minWeight": 30
 },
 "weaponMeleeKatana": {
     "minWeight": 5,
     "maxWeight": 10, // very uncommon
 },
 "weaponMeleeBroadSword": {
     "minWeight": 5
 },
}
```

and for instance loot from a boss is always mastercrafted so we can define loot groups for bosses

```jsonl
"lootBossMeleeWeapons": {
 "weaponMeleeSteelPipe": {
     "minWeight": 5,
     "mastercraft": true // item is mastercrafted
 },
 "weaponMeleeTireIron": {
     "minWeight": 5,
      "mastercraft": true // item is mastercrafted
 }, 
 "weaponMeleeCrowbar": {
     "minWeight": 5,
      "mastercraft": true // item is mastercrafted
 },
 "weaponMeleeSledgehammer": {
     "minWeight": 5,
    "mastercraft": true // item is mastercrafted
 },
"weaponMeleeCattleProd": {
     "minWeight": 10,
   "mastercraft": true // item is mastercrafted
 },
 "weaponMeleeKatana": {
     "minWeight": 5,
   "mastercraft": true // item is mastercrafted
 },
 "weaponMeleeBroadSword": {
     "minWeight": 5,
   "mastercraft": true // item is mastercrafted
 },
}

// then in generic car loot
"lootGenericCarLoot": {
"itemGas": {
  "minWeight": 5,
  "minCount": 1, // defaults to 1
  "maxCount": 2 // defaults to 1
 },
"itemFlashlight": {
  "minWeight": 5
 },
// a singualr item name as specified in item_definitions.json
"itemBandage": {
  "minWeight": 1,
  "maxCount": 3

 },
 "itemPainkiller": {
  "minWeight": 1,
  "maxCount": 1
 },
 "itemAsprin": {
  "minWeight": 1,
  "maxCount": 2
 },
}
```

- In Lua, your parser should explicitly handle maxWeight = item.maxWeight or item.minWeight so single-weight entries don't break the Lerp function.
- Ensure your Lua parser uses a similar fallback for counts (item.maxCount = item.maxCount or item.minCount or 1).   

# entity_loot.json

- would essentially allow us to define special props or entities which can be looted... might look like this
- loot does not "respawn" and instead each cell gets a hard 5 minute timer before that cell can generate loot spots again
- In entity_loot.json, the probability weights (e.g., [["lootGroup1"], 80]) act as the threshold chance for whether a container model turns into an active loot spot upon map initialization.   

## Pseudo Json Example

```jsonl
{
  // works for all props, static, dynamic, physics, also override or multiplayer
  "prop": {
    // the mdls name eg car_01 etc etc
    "<model name>":  [["lootGroup1", "LootGroup2"], 80] // key 0 = the loot groups to use, array or string, key 1 = weighted probability to be lootable, uses the same weighted range as loot
  },
  //specific physics entity, also works for override_multiplayer etc etc
  "prop_physics": {
    // the mdls name eg car_01 etc etc
    "<model name>":  [["lootGroup1", "LootGroup2"], 80] // key 0 = the loot groups to use, array or string, key 1 = weighted probability
  }
}
```

# Lua side utils and files

- Please spread out the implementation of gmod side code between files such as sh_items, sv_items, sh_loot_tables, etc etc
- Need various lua files to parse the various json objects we have created inside the gamemode data_static and easily iterate or retrieve valid information. Certian definition files such as lootand enemy_spawns and boss_spawns need to be first be parsed in game and them the data presented in an easily accessible way since for instance in loot tables their definitions can request references to other loot as well as reference another loot table and override specific values inside of that loot table so the data in .json needs to be parsed and populated when it is read so it can reflect the real data in game. This will make it extremely easy to make complex loot tables just in .json as well as enemy spawns and boss spawns.
- API Should be easy to use for each of the .json definitions, Also for instance, easy functions to give the player items or for an entity to get loot for the player
- The system designed should be easy to integrate into various areas of the game where neccesary
- Current Inventory code should be expanded now and given proper UI now that the player can find items
- Might need to implement a verification system in game to check loot are referenceing groups that exist when they are?
- Loot tables might also need to verify items exist they are trying to reference
- the same two above points might also apply to enemy_spawns.json and boss_spawns.json
- will also need to add console commands to easily test the systems in game

# Notes

Please read the following headings and keep the following bullet points in mind

- Create weaponMeleeCrowbar use weapon_zn_melee_crowbar for testing melee weapon item implementation and loot spawns
- Create weaponHandgun9mm use weapon_zn_handgun_9mm for testing bullet weapon item implementation and loot spawns
- Create itemBandage and use the implementation examples below the header Entity Base Classes to build a usable item

## Generic Base Classes for entity items and weapon items

Define some lua base classes to handle implementations of entity items and weapon items

When we load our game, before the player spawns. We need to load our the classes for each of the items which are not just SWEPS in the game which use them, these can just be written in lua files and all contained under a global which we can just reference in run time and create a new tables from that wheen needed. We should also allow addons to possibly register items and weapons into the game through the workshop system.

Once all lua is loaded, we can then read the data in static through a util library in various areas of our game.

## Entity Base Classes

Entity items are not actually real world gmod entities but are items which contain a consumption purpose such as healing or feeding or replenishing the thirst of the player. The default base class needs to check that the player can use the item, for instance if they meet level and stat requirements. 

- A standard base table for consumable items.
- An item defines a new item table for that item, ed: itemBandage

### itemBandage Implementation Example
gamemode/items/item_bandage.lua 

```lua
-- Create the itemBandage table by inheriting from GenericItem
local itemBandage = table.copy(ZM_EntityClasses.GenericItem)
itemBandage.__index = itemBandage

-- Configuration defaults for itemBandage
itemBandage.BaseHealAmount = 25

--- Custom check for itemBandage usage
function itemBandage:CanUse(ply, itemData)
    -- Run base level and stat checks first
    local canUse, reason = ZM_EntityClasses.GenericItem.CanUse(self, ply, itemData)
    if not canUse then return false, reason end

    -- Prevent healing if health is already full
    if ply:Health() >= ply:GetMaxHealth() then
        return false, "Health is already full."
    end

    return true, ""
end

--- Server-side consumption logic for itemBandage
function itemBandage:OnUse(ply, itemData, targetPly)
    local target = targetPly or ply

    if not IsValid(target) or not target:Alive() then
        return false
    end

    -- Base healing output
    local healAmount = self.BaseHealAmount

    -- Doctor Bonus Logic:
    -- If applied by a player with Medical skill >= 5 or Doctor role, double the efficacy
    local userMedicalStat = ply:GetStat("Medical") or 0
    if userMedicalStat >= 5 or ply:GetJobRole() == "Doctor" then -- do we have job roles on player yet? if not this should be a networked PlayerData value which is also stored in sql for the player, it should default to civilian
        healAmount = healAmount * 2
        if SERVER then
            ply:ChatPrint("[Medical] Doctor application bonus applied! (+100% Healing)")
        end
    end

    -- Apply health increase up to max health cap
    local currentHealth = target:Health()
    local maxHealth = target:GetMaxHealth()
    local newHealth = math.min(currentHealth + healAmount, maxHealth)
    target:SetHealth(newHealth) -- does this need to be on server side?

    -- Sound & VFX feedback
    target:EmitSound("items/medshot4.wav", 75, 100)

    if SERVER then
        local healedDiff = newHealth - currentHealth
        ply:ChatPrint("[Item] Restored " .. healedDiff .. " HP.")
    end

    return true
end

-- Register the class in the global EntityClasses registry
ZM_EntityClasses["itemBandage"] = itemBandage
```

### Implementation Example just for EntityClasses (Base Class & Registry Setup)
gamemode/sh_items.lua 

```lua
-- Shared container for consumable entity item logic
ZM_EntityClasses = ZM_EntityClasses or {}

-------------------------------------------------------------------------------
-- Generic Item Base Class
-------------------------------------------------------------------------------
ZM_EntityClasses.GenericItem = {}
ZM_EntityClasses.GenericItem.__index = ZM_EntityClasses.GenericItem

--- Validates if a player meets the usage requirements for an item
-- @param ply Player
-- @param itemData table Item instance/definition data
-- @return boolean canUse, string reason
function ZM_EntityClasses.GenericItem:CanUse(ply, itemData)
    if not IsValid(ply) or not ply:Alive() then
        return false, "Player is dead or invalid."
    end

    -- Check minimum level requirement
    local minLevel = itemData.minLevel or 1
    if ply:GetLevel() < minLevel then
        return false, "You do not meet the required level (" .. minLevel .. ")."
    end

    -- Check required attribute stats (e.g., Medical skill)
    if itemData.statRequirements then
        for stat, requiredValue in pairs(itemData.statRequirements) do
            local playerStat = ply:GetStat(stat) or 0
            if playerStat < requiredValue then
                return false, "Requires " .. stat .. " level " .. requiredValue .. "."
            end
        end
    end

    return true, ""
end

--- Executed when an item usage is executed (Override in derived items)
-- @param ply Player
-- @param itemData table
-- @param targetPly Player (Optional target, e.g., if a doctor applies it to someone else)
-- @return boolean success
function ZM_EntityClasses.GenericItem:OnUse(ply, itemData, targetPly)
    return true
end

--- Main entry point to attempt using an item
-- @param ply Player
-- @param itemData table
-- @param targetPly Player (Optional)
function ZM_EntityClasses.GenericItem:Use(ply, itemData, targetPly)
    local target = targetPly or ply
    local canUse, reason = self:CanUse(ply, itemData)

    if not canUse then
        if SERVER then
            ply:ChatPrint("[Item System] Cannot use item: " .. reason)
        end
        return false
    end

    if SERVER then
        local success = self:OnUse(ply, itemData, target)
        if success then
            -- Remove 1 item from inventory stack on successful consumption
            ply:RemoveInventoryItem(itemData.id or itemData.class, 1)
        end
        return success
    end

    return true
end
```

## Weapon Base Classes 

Ideally weapon base classes should base them selves off of the approritate swep base class for the type of weapon this weapon item is as we have both melee, hitscan weapons and potentially thrown projective weapons

A standard base class for hitscan weapons
A standard base class for melee weapons
A standard base class for thrown projective weapons (grenades)

All these are swep entities with the code to do our various weapon handling

Then, in lua, our weapon classes can inherit from this base class where approritate

for instance the weaponMeleeCrowbar can inheret from the melee weapon swep, creating a new swep for that weapon_zn_melee_crowbar

each weapon class name should be formatted for source, for intstance weaponMeleeCrowbar becomes weapon_zn_melee_crowbar

## How spawning will work 

When the gamemode loads, if the system is using the walkersim module, walkersim will actually tell the player in the ticket what enemy in the enemy_spawns table to use. Else, will decide what enemy to spawn based on the table.

## How looting will work

When the gamemode loads, it will read entity_loot, then, when the map is ready, using the entity_loot data, will populate the map full of lootable spots (will just colour the prop_entity yellow if possible and draw a question mark there). Then, when you are close to the loot spot and press E, you will wait a bit and then a window will appear showing you what item you have looted (you only loot one item, but that item can be stacked.) You can accept it (that puts it in the inventory) or refuse it. There is a 5 minute refresh on the cell until it can spawn loot again.

For the pop up UI for the loot. It should be a window and itt show a picture of the item thumbnail in the middle along with the items name above it, the text should be gold if the item is mastercrafted and have (MC) at the end of the name. When you hover over the item. It should list its attributes. It should also show the level of the item just below the name, so the layout should be name, then on a new line level, then in the middle of the window picture of the thumbnail of the item, then below the thumbnail docked to the bottom of the window the accept or decline buttons.

## Weighted randomisation 

```lua
-- a pseudo example of how we do weighted randomisation with a loot table
function GetRandomLootItem(lootTable, cellDanger)
    local totalWeight = 0
    local evaluatedItems = {}

    -- 1. Calculate dynamic weight for each item based on cell danger
    for itemName, data in pairs(lootTable) do
        local minW = data.minWeight or 0
        local maxW = data.maxWeight or minW
        -- Lerp weight relative to cell danger (0.0 to 1.0)
        local currentWeight = Lerp(cellDanger, minW, maxW)

        if currentWeight > 0 then
            totalWeight = totalWeight + currentWeight
            table.insert(evaluatedItems, { name = itemName, weight = currentWeight })
        end
    end

    if totalWeight <= 0 then return nil end

    -- 2. Pick a random threshold within the total pool
    local roll = math.random() * totalWeight
    local counter = 0

    -- 3. Determine which segment the roll landed in
    for _, item in ipairs(evaluatedItems) do
        counter = counter + item.weight
        if roll <= counter then
            return item.name
        end
    end
end
```

## Suggested Verification Commands (Lua Console)

To ensure validation works reliably when loading your static data, implement the following testing commands during step 1:

1. `zn_reload_static`: Reloads and re-parses all `.json` files in `data_static/` without restarting the map.
2. `zn_validate_loot`: Iterates through `loot.json` and `entity_loot.json`, printing warnings for missing items, orphaned loot groups, or invalid model paths.
3. `zn_test_loot_roll <lootGroup> <cellDanger>`: Runs $1,000$ simulated rolls on a loot table at a given danger level ($0.0$ to $1.0$) and outputs the percentage distribution to the console to verify weight math.

## Recommended Folder & Script Architecture

To keep the project organized as you begin coding in Garry's Mod, structure your files inside your gamemode directory as follows:

```text
zombiesim/
├── data_static/
│   ├── item_definitions.json
│   ├── enemy_definitions.json
│   ├── enemy_spawns.json
│   ├── boss_spawns.json
│   ├── loot.json
│   └── entity_loot.json
└── gamemode/
    ├── utils/
    ├── sh_items.lua          -- JSON loader, validation, & item registry
    ├── sh_loot_tables.lua    -- Weighted selection algorithm & table composition
    ├── sv_items.lua          -- Inventory server state & database operations
    ├── sv_loot_spawner.lua   -- Map prop initialization & cell 5-min cooldown timer
    ├── entities/
    │   └── weapons/
    │       ├── weapon_zn_base_hitscan.lua
    │       ├── weapon_zn_base_melee.lua
    │       ├── weapon_zn_handgun_9mm.lua
    │       └── weapon_zn_melee_crowbar.lua
    └── vgui/
        ├── cl_inventory.lua       -- Inventory interface
        └── cl_loot_popup.lua      -- Interaction popup window (Accept / Decline) showing a picture of the item thumbnail along with the 
                                      items name, the text should be gold if the item is mastercrafted and have (MC) at the end of the name. When you hover over the item. It should list its attributes. It should also show the level of the item just below the name, so the layout should be name, then on a new line level, then the picture of the thumbnail of the item, then accept of decline
```

## Implementation Extras

- a ply:GetStat function so you can easily get the players attributes
- add "Job" to networked PlayerData and add function ply:GetJobRole()