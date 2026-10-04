# Introduction

Based upon Dead Frontier In Gmod.

- Each map is a "cell" which makes up the entire city. The further you go into the city, the harder the enemies, greater the loot. Rarer loot also drops in further regions.
- Based off of dead frontier
- Top Down third person, zombie survival looter in gmod
- Players start at the den (x 0, y 0) in the city and can venture further
- The city is a grid of cells
- Each cell is just a .vmf file containing a map, a map is made up of a cunk
- When you go trigger a transition by walking down to road to the next map, if you are going north and you are at say for instance (x 0, y 0), your new map position will be (x 0, y 1). 
- A small map contains 5x5 chunks, (a chunk is 640*640 hammer units wide), a large map 50x50, and an extremely large map 100x100.
- The maps are made up of prefabs to speed up the development, a prefab is a chunk wide.
- These prefabs can be buildings, roads, anything really, they are 640*640 units wide the size of a chunk and are made by hand
- would be cool to have an algorithm that can generate cities

# Z-Nation

A gmod gameemode based on the game Dead Frontier. The game is a top down third person zombie survival looter in gmod. Players start at the den (x 0, y 0) in the city and can venture further into the city. Each map is a "cell" which makes up the entire city. The further you go into the city, the harder the enemies, greater the loot. Rarer loot also drops in further regions.

# The Survivor

The launcher presents three survivor slots for each world profile. Creating a survivor selects a citizen appearance and profession, distributes ten starting points, and begins at that profile's origin safe zone. Selecting a different slot changes the saved progression, inventory, credits and location independently; the currently loaded survivor cannot be deleted. Existing saves are intended to become slot 1 and require an appearance choice before deployment. The menu's geographic globe is fictional presentation, not a real-world mapping of the generated city. In-engine migration and presentation acceptance for Alpha 2.8.5 remain outstanding.

 - The Survivor is made up on stats. Here are the base RPG style stats. The stats are as follows:
   - Strength: Affects melee damage and carry weight
   - Agility: Affects movement speed and dodge chance
   - Intelligence: Affects crafting and skill usage
   - Endurance: Affects health and stamina

- The type of weapon you can use is based on your base stats along as weapon stats. Machinegun stats, Shutgun stats, and Sniper stats are based on your base stats. For example, if you have a low strength stat, you will not be able to use a machinegun effectively. If you have a low agility stat, you will not be able to use a shotgun effectively. If you have a low intelligence stat, you will not be able to use a sniper rifle effectively.

- Player at the start of the game can choose a previous job which will give them a starting stat bonus. For example, if you choose the job of "Soldier", you will start with a higher strength stat. If you choose the job of "Engineer", you will start with a higher intelligence stat. If you choose the job of "Athlete", you will start with a higher agility stat. If you choose the job of "Medic", you will start with a higher endurance stat.

- There are also stats for crafting, medicine and scavenging and armor repariring. These stats are based on your base stats. For example, if you have a high intelligence stat, you will be able to craft better items. If you have a high endurance stat, you will be able to heal better. If you have a high agility stat, you will be able to scavenge better. Having a high medicine stat will allow you to heal with better medicine as you will know how to use it better. Having a high scavenging stat will allow you to find better loot as you will know where to look for it.

- Players can sell their skills (eg, if they are a doctor) on the dens market to make money. For instance, if you are a doctor, you can sell your services to other players for a fee. If you are a mechanic, you can sell your services to other players for a fee for instance to repair their armour. If you are a scavenger, you can sell your services to other players for a fee. If you are a soldier, you can sell your services to other players for a fee. If you are an engineer, you can sell your services to other players for a fee. If you are an athlete, you can sell your services to other players for a fee.

- Armour and weapon repairing as well as crafting requires a certain level of skill to do. For example, if you have a high intelligence stat, you will be able to repair armour and weapons better. If you have a high endurance stat, you will be able to repair armour and weapons better. If you have a high agility stat, you will be able to repair armour and weapons better. If you have a high strength stat, you will be able to repair armour and weapons better. Level caps are dependent on the item.

- When you die, you are sent back to the den and lose all your items.
- You have to make it back to the den to save your items, while you are outside of the den your items can be lost if you die. As soon as you make it back to the den, your items are saved and you can continue on your adventure. If you die outside of the den, you will lose all your items and have to start over. But you can find your body again and retrieve your items if you die outside of the den. If you die outside of the den, your body will be marked on the map and you can go back to it to retrieve your items. But if you die again before retrieving your items, they will be lost forever.

- The map will guide your way through the city, showing you how to get to further into the city for better loot. It will also mark lootable buildings on the map, and any other lootable cars or containers. The map will also mark any other players on the map, as well as any zombies or other enemies. The map will also mark any other points of interest, such as safe zones, quest locations, and other important locations. The map will also mark any other players on the map, as well as any zombies or other enemies. The map will also mark any other points of interest, such as safe zones, quest locations, and other important locations.

- The player will have a compass with the geographic information so they know which direction they are moving through the city. The player may find a GPS which adds a line to follow to a specific location on the map. The player may also find a map in the world which reveals more of the city and all the points of interest.

# Equippabe Items in the world

## Movement and stamina

Server-owned movement scales the unmodified walk speed by 0.90 and sprint speed by 0.85, then applies installed implant movement bonuses. Spawn resets and implant refreshes do not compound the reductions. Sprint drain is `60 / (1 + Agility * 0.05 + Strength * 0.03)` stamina per second (25% below the previous base 80); recovery is `5.5 * (1 + Agility * 0.05)` per second (10% above the previous base 5). Maximum stamina remains `100 + Agility * 5 + Strength * 3`. Holding sprint consumes stamina as before, including while stationary; releasing it restores stamina. At zero stamina the server caps movement to walking without removing forward or combat input.

Radiation uses a fictional game meter: cell exposure contributes 0-10 Sv and the strongest nearby radiated walker contributes up to another 10 Sv within 600 units. Groups do not stack. Above 15 combined Sv, an unprotected survivor loses 1 HP every 2 seconds with no Strength-based health floor; this can kill. At lower readings, the existing slow ambient radiation damage retains its Strength floor. Extreme exposure brings black-and-white presentation and increasingly strong cosmetic camera tremor; normal exposure has no radiation shake or postprocessing.

A Radiation Protection Suit occupies the dedicated armour slot independently of weapons, and must be worn rather than carried. It completely prevents radiation damage and radiation screen effects, while leaving the Geiger counter and meter available as warnings. It provides no immunity to ordinary combat damage. Armour follows character/profile-scoped inventory persistence and can be equipped/unequipped from the inventory.

Unprotected survivors see a soft corner vignette that scales with combined radiation, even below the extreme-effect threshold. A top-left nuclear symbol pulses more frequently at higher exposure and remains available while protected. Warning pulses stay bounded to 1.5 Hz and can be disabled independently; the meter remains available.

- Weapons
- Hats
- Implants
- Clothes
- Shoes
- Gloves
- Accessories
- Backpacks
- Goggles
- Masks
- Belts
- Rings
- Necklaces
- Bracelets
- Earrings
- Watches


# The Look of the player

Equippable clothes in a social setting can be implemented in a 2d sense very detailed, for instance we can create a 2D player atlas where you can see all of your clothes on the character, allowing for a more immersive and visually appealing experience. Kind of like how the online version of dead frontier works.

# Designing the art

In the content/materials/player folder, create layers for all the equippable items, such as weapons, hats, implants, clothes, shoes, gloves, accessories, backpacks, goggles, masks, belts, rings, necklaces, bracelets, earrings, and watches. This will allow for a modular approach to character customization, where each layer can be independently modified and combined to create a unique look for the player. 

# Online Implementation (Light MMO Speculative Implementation)

By using the node.js environment, the idea is to create a decentralized network where the server handles authoritative game logic while clients maintain a local cache for offline play. This allows for a seamless online experience with real-time interactions and trading, while still supporting offline gameplay.

Only triggered in special world profiles with online features enabled.  Online features will enable trading as well as seeing player ghosts real time in the world and also boss encounters with other players.

Login to zombiesim services and link your steam ID. 

Our local SQL right now has an items table, we use this just as a local cache, and the authoritative source of item data will be the online service. This allows for offline play while still keeping the online inventory synchronized when connected.

We ask the server for which loot spots the player can have in its current cell. Because of the nature of the game, the server just needs to read the world data and determine the available loot spots without needing to track every player's actions in real time. The server will need to read the same loot groups as the client to ensure consistency. The shipped data in gmod is the same as the server's authoritative data, ensuring consistency between the client and server.

Since we already have the walker sim, each kill ticket can be verified by the server and then the xp for that kill can be awarded to the player accordingly. This ensures that experience points are accurately tracked and prevents cheating by relying on the server's authoritative verification. 

When the player interacts with a loot spot, the client sends a request to the server to claim the loot. The server validates the request, updates the authoritative state, and then sends the updated loot information back to the client. This ensures that all players see a consistent world state and prevents cheating by relying on the server as the source of truth.

In online play, when you die, you have to wait 30 minutes before respawning. This cooldown period helps maintain balance and prevents players from repeatedly exploiting death mechanics to gain an advantage. Also, makes the game harder and encourages strategic gameplay.

Players can have up to 3 online characters which they choose in the loading map before they enter the game world. Each character has its own inventory, experience points, and progression, allowing players to experiment with different playstyles and strategies without affecting their other characters.

# Utilizing P2P

Gmod actually already has p2p inside of it which might be able to be leveraged through steam API so ghosts can join your instance and actually play in the same level as you and also interact with the world in real time, providing a more immersive multiplayer experience without relying solely on a central server.

It would have to safely work with the steam API so players can connect to each other's instances securely and seamlessly, ensuring a smooth multiplayer experience while maintaining the integrity of the game world.

# Runtime foliage and debris

Outdoor city cells can contain server-placed, non-solid trees and berry bushes. Players press the interact key to harvest: trees require an equipped melee weapon and yield Wood; bushes yield Berries by hand. Shared harvest cooldowns are saved per profile and logical cell, so one player's harvest is visible to others and survives restarts. Trees regrow after seven days and berry bushes after one day. The server calendar controls berry availability: plentiful in spring and summer, scarce in autumn, and unavailable in winter. Prices and food effects for these new material items remain unassigned.

Nearby paper, bottles, cans, cartons and occasional tumbleweeds are client-side ambience only. Wind gusts lift paper and drive tumbleweeds, players kick debris as they move through it, and gunshots scatter debris near bullet impacts. None of it collides with players or affects gameplay, and each player can scale or disable it with the Debris amount setting.

# Zombie toughness

Zombies are hard to put down with body shots: an ordinary walker takes four to six hits from most guns, and tougher variants take more. A shot to the head always drops a walker. Bosses shrug off headshots better, taking heavy extra damage rather than dying instantly.

# Dismemberment and gore

Heavy hits can sever a zombie's forearms or legs; stronger weapons such as shotguns, rifles and melee sever more readily than pistols, and a limb usually needs some damage before it comes off. A zombie that loses its legs keeps crawling toward the player at half speed and still bites as hard. A killing headshot can burst the head off, and a heavy killing blow can split the body. Bosses can lose arms but never become crawlers. Corpses retain the regions severed while alive. Compatible rebel clothing uses mounted bloody textures without replacing the human player models or animations. Blood sprays and trails originate at the stump and detached limb cuts. Engine wall/floor stains stay until the next cell change within a finite decal budget; separate feathered pools on level ground fade after 90 seconds. Severed limbs are scenery only, never loot, and fade after a minute. Players can reduce or disable gore effects without changing how combat works; spray, queues, limbs and pools have quality-dependent caps. Bloody footsteps are not added, and weather footprints/splashes are unchanged.