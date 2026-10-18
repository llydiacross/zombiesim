# Alpha 3.3

These are the things I have already done

# Additions

- Added new skyscraper buildings for radiatioactive zones, various new buildings added. Improvements to the current buildings
- Added new textures for billboard signs along with new data for evacuation signs, stage new billboard/signs
- Added new clothing textures, stage new clothing

# Changes

- Some of the buildings have been renamed to better reflect their density and purpose as well as that a bunch of edits have been made to improve their appearance and functionality.

This is what the plan is for the upcoming updates and changes.

# Upcoming Updates and Changes


## Better Fog (least priority)

- Figure out a way to improve fog.
 - Fog right now kind of just masks the skybox and makes it look opaque and is genuinelly not that convincing. I think this is due to how source does its fog implementation. I would like the fog to possibly instead be volumetric, possibly faked in the skybox so instead of a kind of an overcasting fog there is just kind of a dim layer of fog and then you can see the skyscrapers pop out of the fog layer from a distance. 
 - Think of the simplest way to achieve this effect and consider if it could be achived already with current source fog implementation
 - Sometimes, Fog doesn't always align with the skybox model, leading to visual inconsistencies that need to be addressed.
 - Furthermore, what can happen is kind of a "double fog seam efffect" when traversing through the cell and you are looking at the skybox, kind of breaking the illusion of fog as it appears there are two fogs overlapping each other.

 ## Prefab Editor System (top priority)

- I would like to create a system which will allow me to position props and other elements to create prefabs that can then be reused. The idea is that this system which i am envisioning will probably be accessible via the main menu, loads you into gm_flatgrass where you enter an editor that gives you a 640 grid tile to place down props onto. Using this I will make the blockcade configurations that you place on the roads. Also we can use this system to create transition gates that replace your current system of just placing a car, with a re-defined set piece dependent on the environment
- This system would allow you to position the props, save them as a name, and them some how that prefab can then be used by the system in areas such as the transition gate and in blockades. This feature would also allow us to create car patterns for the motorway so that traffic can be more dynamically generated and varied, enhancing the overall realism and immersion of the environment and I don't have to place it all down in hammer. Since the editor is making the user place the props on a 640 by 640 tile it should be easy to place this down into our own with out any issues other than figuring out the rotation but we will use the same oritentation rules as twe do for the tiles
- This system would allow the user to place props which are lootable, and non lootable, and possibly even override the loot group for specific props, giving more control over the distribution and availability of loot within the game environment. Maybe you can make this prefab for instance always output a lootable prop?
- You should be able to move the props around, rotate them, and adjust their properties within the prefab editor to achieve the desired layout and appearance.
- It should contain basic settings such as the prefab's name, description, and any relevant metadata that helps identify and categorize the prefab within the editor. Also options to snap props to the grid for precise placement. Or rotate them at fixed increments for better alignment. Or rotate them freely. 
- The Prefab Editor System should be really two parts, one is the editor its self, the other is the explorer to see and manage the existing prefabs, allowing users to browse, search, and organize their prefabs efficiently.
- Various tags could be transitionGate (used to replace the "red car" prop we place down now)
 - transitionGate Motorway (special transition gates for motorway)
 - Radioactive (for radiative zones)
 - Take advantage of the current elemental tag system
- When requesting prefabs, you could for instance in hammer use a "Generic" tag to filter and find prefabs that match the desired category.
- If a prefab fails to load, simply error in console and do not fall back to a default prefab.
- Generic tags might include
  - bodys (for piles of bodies or corpses)
  - ammoCache (for caches of ammunition)
  - medicalCache (for caches of medical supplies)
  - weaponCache (for caches of weapons)
  - ambulance
  - policeCar
  - fireTruck
  - roadDetail (for details and props related to roads)
- Take authority of the positioning and rotation from the hammer entity in hammer of the preset if spawned in hammer
- Prefabs some how are "tagged" for their use, so for instance if you make a road blockade, or a transition gate, it is tagged that way and then used by the system to automatically place the appropriate prefabs in the correct context within the game environment.
  - Note: This does mean that determanistically each player might not have the same preset if they were to customize their game. This is okay, as everyone should have the same when we launch anyway, and modding through this system is okay.
- Maybe you could even include the ability to load a preview of a tile for instance the road straight so you can align your prefabs accurately with the existing environment.
- Eventually, this system will take dominance over just placing prop dynamic and stuff in hammer, and we will develop a hammer entity that we can use to reference these prefabs and spawn them into the world where we want in hammer. For instance, I can edit the motorway pieces so they include this prefab spawning entity for the purpose of crashed cars and other things like that
- Obviously, well have no way to preview what kind of entitys will be spawned around the point of origin set in hammer, so the artist will have to know beforehand what the prefab contains and plan accordingly.
- Prefabs can overlap over prefabs. They are simply just a group of props that are grouped together and spawned in at the same time. Editable within the prefab editor, allowing for adjustments and refinements before being used in the game environment.
- Prefabs could be rigged to be randomly decided when you join a cell. This would allow motorway car patterns to change per cell. It would need to be the same for all players so it would be determinstic based on a shared seed or some other consistent factor.
- Prefabs could also take advantage of garrysmod features and include things such as dynamic lights, particle effects, and maybe even you can place down NPC's. 
- Note: On NPCS right now we don't have NPCS who are not traders, these NPCS are different from traders as they are considered "guards" or "patrols" that protect certain areas or follow specific behaviors within the game environment so they act more like the half life 2 rebel AI and just shoot any zombies that come close to them as needed. They have names above their heads and you cannot talk to them directly.
- The NPCS would just stand there and you can set the animation and also the clothing they are wearing, referencing with our clothing system already
- Through the prefab system, we will be able to also create detail to be placed into the world, like piles of bodies, broken down albumances, abandoned vehicles, and other environmental storytelling elements that enhance the immersion and realism of the game environment.
- This will allow for a more dynamic and visually rich environment, where the world feels lived-in and responsive to the player's actions and the ongoing narrative.

## Structure building system

- Create a set of tiles to be used for constructing various structures within the game environment.
- Ensure that these tiles are modular and can be easily combined to form different types of buildings.
- Consider including both interior and exterior tiles to allow for complete building construction.
- Implement a system for snapping tiles together to maintain alignment and consistency in the game world.
- Tiles should be based on the tile of a cell, which is 640 units in size. So if we divide that by 10, the base foundation size should be 64 units, and everything else for our structure system should be based off of that, so a half tile would be 32 units. A wall would be 16 units in thickness as it is 64 / 4. 
- We can generate a variety of complex pieces which the player can use to construct unique and diverse buildings within the game environment. We should also include triangle-shaped pieces to allow for more architectural variety and creativity.
- The textures we should use are wood, stone, metal, and concrete to provide a variety of visual styles for the structures.
- The theming and general art style is post apocalyptic, reflecting a world that has undergone significant devastation and is now in a state of decay and ruin. So the structures should look like shantys, makeshift shelters, and remnants of once-functional buildings, emphasizing the harsh and deteriorated environment.
- Take textures from source which are already pre existing and create the models using these textures and create a set of modular building pieces for each texture group.
- Maybe we can define the texture groups in a json file so they are editable, incase we want to generate a new stucture piece in the future. Such as Marble, Granite, or other material types.
- How the building will work is, you will place down a foundation piece, and then using a system similar to rust, using snapping points on the foundation and other building pieces, you can attach walls, floors, roofs, and other structural elements to construct your building. This system ensures that all pieces align correctly and maintain structural integrity within the game world.
- I would like it so first you place down the basically a wireframe version of the foundation or piece you would like to build, then by pressing E you can "add wood to it" and then once it has enough wood, it fades from wireframe into the structure. 
- Structure pieces have a health dependent on the materials used and can be damaged or destroyed by player actions or environmental factors. This adds an element of strategy and realism to the building system, as players must consider the durability of their structures and maintain them over time.

- In order to place down a structure, there is a few conditions which must be met:
- One: The (tile) or part of the cell you are currently in is an empy cell that is not occupied by any other structure or object. This means there is no building there and it is just a detail tile or a terrain tile. It cannot be a road tile, or any border tiles what so ever.
- First, the player must claim the tile. Once they claim the tile, they enter construction mode and a confirmation border shows up around the tile like a box, indicating that it is now under the player's control and ready for construction and this is their land. How a player claims a tile is by using an Item called "Claim Token" on the desired tile. A claim token can be purchased by traders for credits. A claim token is used once and is consumed upon use. Once the player owns that tile, they can begin constructing structures on it. When constructing strutures, zombies do not bother the player. But they can also not bother the zombies either. If they exit the tile and go a far distance, or they leave construcion mode, the protection ends and zombies can interact with the player and the environment as usual.
- Players may only build in the tile.
- If a player is next to an empty tile adjacent to their claimed tile, they may be able to extend their construction into that tile, provided they have another claim token. This allows for gradual expansion of the player's controlled area while maintaining the integrity of the claimed land system.
- Claim tokens last for 30 days since the time the user last visited the claimed tile. After 30 days, the claim token expires, and then the structure can be tore down for scrap by other players. They cannot rebuild on that tile until a new claim token is used, when a new claim token is used, it deletes the previous claim and establishes a new 30-day period of ownership with the new owner.
- For this update, I just want to focus on the structure building and all related mechanics, leaving other aspects such as placing down workbenches, furniture and other interactive objects for future updates.
- Zombies can attack your structures, they will not usually attack your structure as when you are in a structure sound and light is muffled, making it harder for them to detect the player inside. However, if the structure is not airtight or if the player is outside, zombies will actively seek out and attack the structure. Airtightness can be compromised by missing walls, broken windows, or other structural damage, making it crucial for players to maintain their buildings to ensure maximum protection against zombie attacks.
- Players can place a storage box in their claimed tile which they can store things in. Each storage box gets a unique inventory. You can store as many items as you like. Other players can break down your door to access your storage box if they have the means to do so, adding an element of risk and strategy to how you protect your valuable items.
- Door can be placed inside of door frames and locked to prevent unauthorized access. Only players with the appropriate key or permission can unlock and open the door, adding an additional layer of security to the player's claimed tile.
- Baricades can be placed on windows to reinforce them and prevent zombies or other players from easily breaking through. This adds an additional layer of defense to the player's claimed tile, allowing them to fortify vulnerable points in their structures.
- Curtains can be placed on windows to provide privacy and block light. An important factor to keeping the player safe and unobservable by zombies from the outside. If the player doesn';t have curtains, zombies will try to attack their front door.
- Zombies will always try to attack the front door first, if the front door is not accessible to them after repeated attempts, they will collectively try to instead attack a wall. 

## Improved Zombie AI (medium priority)

- Zombies need to move around and act a lot more like zombies. Right now they just stand in place and do nothing until the player finds them. We need to develop a system where zombies can be walking around, and detecting the player based on sound, sight, and other environmental cues. This will make the game more challenging and immersive, as players will need to be more cautious and strategic in their movements and actions.
- Zombies are very slow and lumbering, making them less of an immediate threat but more of a persistent danger. Their slow movement requires players to plan their actions carefully and use the environment to their advantage, as rushing into a horde of zombies can still be fatal despite their lack of speed.
- Zombies should have a sense of territory and be able to remember areas where they have encountered players before. This will make them more strategic in their attacks and create a more dynamic and challenging gameplay experience.
- The zombies cone of vision should be limited and directional, meaning they can only see within a certain angle and distance in front of them. This will make stealth and careful movement more viable strategies for players, as approaching zombies from outside their cone of vision will reduce the likelihood of being detected.
- Zombies should also have a sense of hearing, allowing them to detect players based on noise generated by movement, actions, or environmental interactions. This will encourage players to be mindful of the sounds they make and use stealth tactics to avoid attracting zombie attention.
- Zombies should be able to communicate with each other, either through vocalizations or other means, to alert nearby zombies of the player's presence. This will create a more dynamic and challenging environment, as players will need to consider the potential for reinforcements when engaging with zombies.
- Zombies need to shuffle around the map, maybe fight eachover. Maybe they group up together.
- Add sounds for the zombies, including groans, footsteps, and attack noises, to enhance the immersive experience and provide players with auditory cues about nearby threats.
- The way that the zombie attacks right now is not very convincing as basically the animation does not sync up directly to when the zombie hits. So they can kill you very unfairly while it looks like they are just completely standing still, or their animation haven't actually triggered yet. We need to change how the zombies attack so their attacks are much more like a "swing" and you can dodge it, making combat feel more fair and responsive.
- The swing or lunge the zombie takes should fire just one attack event, ensuring that the damage is applied at the correct moment in the animation and making it possible for players to dodge or block the attack.
- Make the zombies damage a bit less but also take into account if a user has no armor, ensuring that unarmored players are still at significant risk while armored players have a better chance of surviving encounters.

## Expanded Armour

- We need to expand armour in the game so there are three types of armour: light, medium, and heavy. Light armour provides minimal protection but allows for greater mobility, medium armour offers a balance between protection and mobility, and heavy armour provides maximum protection at the cost of reduced mobility.
- We need to implement these new attributes into the current jobs, ensuring that each job has appropriate access to light, medium, or heavy armour based on their role and gameplay balance.
- Light armors also provide increased agility and stamina, allowing players to move faster and perform actions more efficiently compared to medium and heavy armors.
- Medium armors provide a balance between protection and mobility, offering moderate defense while still allowing players to move relatively freely compared to heavy armor.
- Heavy armors provide maximum protection but significantly reduce mobility, making players more resilient to damage but slower and less agile compared to those wearing light or medium armor.
- Heavy armors have more damage resistance but also have an impact on your movement speed
- Heavy armors also reduce stamina regeneration, making prolonged physical activity more challenging compared to lighter armors.
- Consider adding special abilities or bonuses for each armor type to further differentiate their gameplay impact, such as increased carrying capacity for heavy armor or faster sprinting for light armor.
- Medium armors are the best of both worlds, providing a balanced mix of protection and mobility without the extreme drawbacks of light or heavy armor.
- Light armors provide the best mobility and agility, allowing players to move quickly and perform actions efficiently, but they offer the least protection compared to medium and heavy armors.
- The better you are at light armors, the better armors you can wear and also the less mobility penalty you will suffer when wearing heavier armors. 

## Expanded Attributes

- Add missing attributes "Pistols" and "Explosives", rename "Snipers" to "Rifles". 
- Apply new attributes accordingly into the job system

## Improved Job Selector UI

- Improve the current job selector UI in the menu to make it nicer and more user friendly, using boxes to seperate each job and making it more clear which job you are choosing. Maybe we could instead lay out the jobs in a grid? So they each have an icon, then when you click on one, the right panel displays detailed information about the selected job along with a backstory for each job which I will write but just use a placeholder for now.
 - Maybe it breaks down each attribute you get into a nice table

## World Generation Rules (last)

- I have added building_ra buildings to the buildings folder with the intent that these buildings and these buildings alone are the only ones to be used in radiation zones. This same rule applies to the new skyscrapers too. I do not want normal buildings to spawn in the radiatioactive areas. Radioactive zones are to only use ra buildings. If none are available, then ra cells should place just a terrain or detail tile appropriately. 
- This rule that buildings must equal their environment tags only applies to military (army_base) cells, and radiation cells. Everything else buildings which don't have a tag may appear.
- If a tagged building is available for a specific environment, it will take priority over untagged buildings when generating the world.
- Please make sure all new building changes are staged to gmod along with associated materials and models

## Fixes

Due to our 3rd person camera system we are having issues with source culling and it thinking objects are not in the players view. This is also breaking our zombie system sometimes as zombies can seem to despawn in front of your eyes sometimes. Investigate a way to fix source culling so items props behind walls which are visible from above do not disppear and the false positive it brings to our zombie materializer
