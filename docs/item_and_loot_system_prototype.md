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
 - if the item is a weapon or armour, these are its attribute stats

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

  - it works out which attributes to use and are applicable through the type key (bullet_weapon, melee_weapon)

  - Note: The attributes needs to be generated for item weapon and armor item in the game depending on its current level using its minLevel and its maxLevel so the level of an item will need to be decided first with the maximum level of the item being roughly translated to equal the highest possible attributes relative to the maxAttribute value with (1 or 2) missing. If the item is mastercrafted, then the attributes will always be equal the max attribute level no matter what level it is
  - For instance, if a weapon like the crowbar has the lowest level being 10, and a max level of 32, for each maybe 5/10% of the distance it takes to reach the maxLevel of the current item, it should increment each of valid attributes a little bit based on the level of the item you find. Also, when you find attributes they should VERY rarely all equal the same number. for instance, 6 damage, 6 ranage or 6 firing speed, it should be 5, 4, 3, only max out the attributes if it is master crafted, but even still they should VERY RARELY be matching attributes as these are a super special type of mastercraft.
  - Note: These would never be defined by hand in the item_definitions them selves
  - The attributes need to affect the areas of the weapon or armour they specify in game in garrysmod, more damage means the weapon is better. The weapons only get scaled by the attributes, level is only important for allowing more attributes to appear with higher values, but its really the attributes which balance the weapons.

- minAttributes: used in scaling the weapon, the minimim possible attribute count for this weapon, defaults to 2
- maxAttributes: the maximum possible attribute stats this weapon might have, defaults to 32. 
- mastercrafted: if the weapon is master crafted (the attributes will be and are the best possible for that weapon)
- iconThumbnail
- type: what type of item this is (used to generate attributes, by default if it is omitted no attributes will be generated)
 - bullet_weapon
 - melee_weapon
 - heavy_armour
 - light_armour

## Pseudo Json Example

"itemGas": {
 "entityClass": "generic", // cannot be used, only used in crafting and stuff
 "thumbnail": "itemGas" // a png in content/materials/items/
 "value": 1.59 // $1.59 per 1 unit (gallon)
 "maxStack" 300 // 300 gallons
 "unit": "gallon" // for ui purposes, defaults to none (will just show stack number)
}

// requires no doctor to apply but does give the healing item a 2x bonus if applied by a doctor
"itemBandage": {
 "entityClass": "entity", /// will look for a class/table/member in some sort of table to find and call call the use functions for "itemBandage" or use generic one
 "thumbnail": "itemBandage" // a png in content/materials/items/
 "value": 2 // $8 per 1 unit
 "maxStack" 3  // 3 bandages
}

// requires no doctor to apply 
"itemPainkiller": {
 "entityClass": "entity", // will look for a class/table/member in some sort of table to find and call call the use functions for "itemPainkiller" or use generic one
 "thumbnail": "itemPainkiller" // a png in content/materials/items/
 "minLevel": 10
 "value": 2 // $8 per 1 unit
 "maxStack" 3  // 3 bandages
}

// requires no doctor to apply 
"itemAsprin": {
 "entityClass": "entity", 
 "thumbnail": "itemAntibiotics" // a png in content/materials/items/
 "minLevel": 25 // what level you have to be to use this item, 
 "value": 2 // $8 per 1 unit
 "maxStack" 3  // 3 bandages
}

// requires a doctor to apply
"itemAntibiotics": {
 "entityClass": "entity",
"statRequirements": {
"Medical": 5 // 5 medical skill points to use this item or you can get a doctor to apply it for you at a cost for their services
},
 "thumbnail": "itemAntibiotics" // a png in content/materials/items/
 "minLevel": 25
 "value": 2 // $8 per 1 unit
 "maxStack" 3  // 3 bandages
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
 "thumbnail": "weaponMeleeCrowbar" // a png in content/materials/items/ which is used in the inventory, if not specified will just default to name of item
 "value": 200 // $200 per 1, value significantly goes up if the item is mastercrafted, value should also scale with level and attribute value
 "maxStack" 1,
 "mastercrafted": false, // this item is always master crafted if this is set to true, when the item is created/looted the item will have the attributes to the level of the maxAttribute
}

// __ the rest of the items etc __

# recipie_definitions.json
 
  // TODO: Mock up

# enemy_definitions.json

 - contains raw defnitions for enemys which we can spawn through the walkersim ticketing system or via other methods if no binary is possible
 - min rarity and max rarity are to do with spawn selection are scaled by the damage of the current cell
 - min danger and max danger decides the danger range this entity can spawn in
 - min loot drop chance and max loot drop chance decide the chance the entity will be lootable when killed. Max loot drop chance is the maximum chance the entity can drop loot, scaled to the cells damage. 
 - loot group can contain one single loot_table definition or multiple
 - if the entity is a boss they will always drop loot when they are killed and also appear on the minimap/world map


## Pseudo Json Example

 "entityWalker": {
   "entity": "npc_zombiesim_walker",
   "minHealth": 19, // scale depending on danger of current cell
   "maxHealth": 30,
   "minSpeed": 1 // how fast they are,
   "maxSpeed": 1, // defaults to min speed if not present
   "minDanger": 0, // spawns in all cells over damage 0
   "maxDanger": 0.75, // spawns in all cells with damage less than 0.75
   "minRarity": 0.75, // spawn 75% of the time, min is equal to current damage of the cell
   "maxRarity" 0.20, // spawns 20% of the time in high damage cells
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005 // scales with danger of cell and acts only as a trigger for the lootGroup specified in this object and not an overrider for the loot groups settings
   "maxLootDropChance": 0.05 //  scales with danger of cell, high damage cells (or as max as the maxDanger value) will max out to 0.05 chance
   "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   }, ["genericZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   }]]
  }

  "entityRareWalker": {
   "entity": "npc_zombiesim_walker", // can reuse the entity name
   "minHealth": 29, // scale depending on danger of current cell
   "maxHealth": 49,
   "minSpeed": 1 // how fast they are,
   "maxSpeed": 1.25, // defaults to min speed if not present
   "minDanger": 0.25, // spawns in all cells with damage above 0.25
   "maxDanger": 1, // spawns in all cells with damage below (1) (so all cells)
   "minRarity": 0.25, // spawn 25% of the time in low damage cels
   "maxRarity" 0.75 // spawn 75% of the time in high damage cells
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005 // scales with danger of cell and acts only as a trigger for the lootGroup specified in this object and not an overrider for the loot groups settings
   "maxLootDropChance": 0.25 //  scales with danger of cell, high damage cells (or as max as the maxxDanger value) will max out to 0.25
   "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["rareZombieLoot", {
    // custom loot group if wanted
   }, ["rareZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   }]]
  }


 "entityRunner": {
   "entity": "npc_zombiesim_runner",
   "minHealth": 10,
   "maxHealth": 13,
   "minSpeed":  2 // how fast they are,
   "maxSpeed": 2.5,
   "minRarity": 0.25, // how common they are, max is defaulted to same rarity as min, with low danger they are very rare
   "maxRarity" 0.15 // default walkers get less rare the more damage of a cell
   "modelVariants": [
    // zombie model variants
   ], 
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.005 // scales with danger of cell
   "maxLootDropChance": 0.05 //  scales with danger of cell 
      "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   }, ["genericZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   }]]
  }


 "entityDog": {
   "entity": "npc_zombiesim_dog",
   "minHealth": 10,
   "maxHealth": 14,
   "minSpeed": 3.5 // how fast they are,
   "maxSpeed": 4,
   "modelVariants": [
    // zombie model variants
   ], 
 "minRarity": 0.01,
 "maxRarity": 0.1,
   "boss": false, // if this entity is a boss or not
   "minLootDropChance": 0.01 // scales with danger of cell
   "maxLootDropChance": 0.1 //  scales with danger of cell
      "lootGroup": "" // would reference a loot group to use for this entity, could be a singular loot group or multiple. Maybe looks like this? ["genericZombieLoot", {
    // custom loot group if wanted
   }, ["genericZombieLoot", {
     // override? maybe if youw ant to use genericZombieLoot but make something in it more common
   }]]
  }

# entity_loot.json

- would essentially allow us to define special props or entities which can be looted... might look like this

## Pseudo Json Example

{
  // works for all props, static, dynamic, physics, also override or multiplayer
  "prop": {
    // the mdls name eg car_01 etc etc
    "<model name>":  [["lootGroup1", "LootGroup2"], 0.5] // key 0 = the loot groups to use, array or string, key 1 = probability
  },
  //specific physics entity, also works for override_multiplayer etc etc
  "prop_physics": {
    // the mdls name eg car_01 etc etc
    "<model name>":  [["lootGroup1", "LootGroup2"], 0.5] // key 0 = the loot groups to use, array or string, key 1 = probability
  }
}

# enemy_spawns.json

- a mock up of different types of entities that can spawn in a cell
- each key is  made up of the value of the name in entity_definitions or an object with the key of the entity and defininig overrides

## Psedo Json Example

// enemies which can commonly be found in each cell
"cellGenericEnemies": ["entityWalker", "entityRareWalker", "entityDog", "entityRunner"]

// special definitions for each cell based on its environment tag
"cellRadiationEnemies": ["genericEnemies", "entityMutant", "entityPosinous"]
// if a cell environment tag doesn't have one it will fall back to the cellGenericEnemies entity spawn group

# boss_spawns.json

// TODO: Mockup how boss spawn definitions work, they would read from enemy_defitions which entity to spawn as a boss, bosses spawn on a random cell in the world. This file in theory would allow to set certian partamers to define when and how a boss spawns, maybe a boss only spawns in radioactive cells, maybe a boss only spawns once a day, or is spawns many times. Maybe it is a rare boss, or a super rare and super dangerous boss. Also, what loot does the boss drop? This would reference the loot tables

# loot_tables.json

 - maybe define some generic loot tables for food items, then medical items, then weapon items, then armour items, then crafting items
 - tables for rare drops, extremely rare drops, ultra rare drops (cells with higher damage will drop more ultra rare drops)
- these groups are easily reusable and can be made up of multiple other groups (this is all parsed when the data is loaded into the game)
- loot tables for different types of things in games, cars, garbage bins, ambulances, police cars, fire trucks, petrol tankers 
- the keys inside of the item to spawn are just minRarity, maxRarity, mastercraft, mastercraftChance // by default weapons and armour have a 5% rate to be mastercrafted
- maybe it would look like:
- minRarity and maxRarity (with maxRarity scaling in factor relational to the cells current damage value)

## Psedo Json Example

 // can be a group or a singular item name or an override

 "entityPetrolTankerLoot": ["lootGenericCarLoot", { "lootGenericMeleeWeapons": {
  // override this wepaon
  "weaponMeleeCrowbar": {
      "minRarity": 0.10, // the rarity in low damage cells, spawns 10% of the time
      "maxRarity": 0.30, // the rarity in high damage cells, spawns 30% of the time
      "mastercrafted": false,
      "mastercraftChance": 0.5 // greater mastercraft chance if found
  }
},
}]

// will be a combination of both loot groups
"lootGenericWeapons": ["lootGenericHandguns", "lootGenericMeleeWeapons"]

// key is the name of the loot group/table,
"lootGenericHandguns": {
  // key is the item name in item definition
 "weaponHandgun9mm": {
     "minRarity": 0.05,
     "maxRarity": 0.1 // double the chance in high damage cells
 },
 "weaponHandgunGlock": {
     "minRarity": 0.025
 },
 "weaponHandgunDesertEagle": {
     "minRarity": 0.010
 },
 "weaponHandgunTec9": {
     "minRarity": 0.010
 },
 "weaponHandgunSilenced9mm": {
     "minRarity": 0.010
 }
}

"lootGenericMeleeWeapons": {
    // key is the item name in item definition
 "weaponMeleeSteelPipe": {
     "minRarity": 0.05
 },
 "weaponMeleeTireIron": {
     "minRarity": 0.05
 }, 
 "weaponMeleeCrowbar": {
     "minRarity": 0.025
 },
 "weaponMeleeSledgehammer": {
     "minRarity": 0.025
 },
"weaponMeleeCattleProd": {
     "minRarity": 0.010
 },
 "weaponMeleeKatana": {
     "minRarity": 0.005
 },
 "weaponMeleeBroadSword": {
     "minRarity": 0.005
 },
}

and for instance loot from a boss is always mastercrafted so we can define loot groups for bosses

"lootBossMeleeWeapons": {
 "weaponMeleeSteelPipe": {
     "minRarity": 0.05,
     "mastercraft", true // item is mastercrafted
 },
 "weaponMeleeTireIron": {
     "minRarity": 0.05,
      "mastercraft", true // item is mastercrafted
 }, 
 "weaponMeleeCrowbar": {
     "minRarity": 0.025,
      "mastercraft", true // item is mastercrafted
 },
 "weaponMeleeSledgehammer": {
     "minRarity": 0.025,
    "mastercraft", true // item is mastercrafted
 },
"weaponMeleeCattleProd": {
     "minRarity": 0.010,
   "mastercraft", true // item is mastercrafted
 },
 "weaponMeleeKatana": {
     "minRarity": 0.005,
   "mastercraft", true // item is mastercrafted
 },
 "weaponMeleeBroadSword": {
     "minRarity": 0.005,
   "mastercraft", true // item is mastercrafted
 },
}

// then in generic car loot
"lootGenericCarLoot": {
"itemGas": {
  "minRarity": 0.05
  "minCount": 1, // defaults to 1
  "maxCount": 2 // defaults to 1
 },
"itemFlashlight": {
  "minRarity": 0.05
 },
// a singualr item name as specified in item_definitions.json
"itemBandages": {
  "minRarity": 0.1,
  "maxCount": 3

 },
 "itemPainkillers": {
  "minRarity": 0.1,
  "maxCount": 1
 },
 "itemAsprin": {
  "minRarity": 0.1,
  "maxCount": 2
 },
}

# Lua side utils and files

- Please spread out the implementation of gmod side code between files such as sh_items, sv_items, sh_loot_tables, etc etc
- Need various lua files to parse the various json objects we have created inside the gamemode data_static and easily iterate or retrieve valid information. Certian definition files such as loot_tables and enemy_spawns and boss_spawns need to be first be parsed in game and them the data presented in an easily accessible way since for instance in loot tables their definitions can request references to other loot_tables as well as reference another loot table and override specific values inside of that loot table so the data in .json needs to be parsed and populated when it is read so it can reflect the real data in game. This will make it extremely easy to make complex loot tables just in .json as well as enemy spawns and boss spawns.
- API Should be easy to use for each of the .json definitions, Also for instance, easy functions to give the player items or for an entity to get loot for the player
- The system designed should be easy to integrate into various areas of the game where neccesary
- Current Inventory code should be expanded now and given proper UI now that the player can find items
- Might need to implement a verification system in game to check loot_tables are referenceing groups that exist when they are?
- Loot tables might also need to verify items exist they are trying to reference
- the same two above points might also apply to enemy_spawns.json and boss_spawns.json
- will also need to add console commands to easily test the systems in game

# Generic Base Classes for entity items and weapon items

Define some lua base classes to handle implementations of entity items and weapon items

When we load our game, before the player spawns. We need to load our the classes for each of the items which are not just SWEPS in the game which use them, these can just be written in lua files and all contained under a global which we can just reference in run time and create a new tables from that wheen needed. We should also allow addons to possibly register items and weapons into the game through the workshop system.

Once all lua is loaded, we can then read the data in static through a util library in various areas of our game.

## Entity Base Classes

Entity items are not actually real world gmod entities but are items which contain a consumption purpose such as healing or feeding or replenishing the thirst of the player. The default base class needs to check that the player can use the item, for instance if they meet level and stat requirements.

## Weapon Base Classes 

Ideally weapon base classes should base them selves off of the approritate swep base class for the type of weapon this weapon item is as we have both melee, hitscan weapons and potentially thrown projective weapons

A standard base class for hitscan weapons
A standard base class for melee weapons
A standard base class for thrown projective weapons (grenades)

All these are swep entities with the code to do our various weapon handling

Then, in lua, our weapon classes can inherit from this base class where approritate

for instance the weaponMeleeCrowbar can inheret from the melee weapon swep, creating a new swep for that weapon_zn_melee_crowbar

each weapon class name should be formatted for source, for intstance weaponMeleeCrowbar becomes weapon_zn_melee_crowbar

# How spawning will work 

When the gamemode loads, if the system is using the walkersim module, walkersim will actually tell the player in the ticket what enemy in the enemy_spawns table to use. Else, will decide what enemy to spawn based on the table.

# How looting will work

When the gamemode loads, it will read entity_loot, then, when the map is ready, using the entity_loot data, will populate the map full of lootable spots (will just colour the prop_entity yellow if possible and draw a question mark there). Then, when you are close to the loot spot and press E, you will wait a bit and then a window will appear showing you what item you have looted (you only loot one item, but that item can be stacked.) You can accept it (that puts it in the inventory) or refuse it. 

# Notes

- Create weaponMeleeCrowbar use weapon_zn_melee_crowbar for testing melee weapon item implementation and loot spawns
- Create weaponHandgun9mm use weapon_zn_handgun_9mm for testing bullet weapon item implementation and loot spawns
