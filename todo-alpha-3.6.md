# Alpha 3.6

# Balancing

- Zombie Corpses need to be a lootable a lot less frequently, they are far to common right now and it is very easy to get many weapons by just killing zombies. It would b give weapons a lot less frequently, give cash more frequently.
- Zombie corpses drop weapons way to commonly. Needs to drop cash way more commonly, weapons need to be an extremely very rare drop.

# Clothing and Loot

- Make sure you can actually find the clothing items in game. I have killed many zombies and searched many things and never found any clothing items.

# New Imports

- Add the new cans imported from gamebana (realistic_cans) to the loot tables
- add new paranoia vehicles
- make sure imported models in our content folder are staged to garrysmod. I can't see them in hammer. Or the prefab editor.

# New Prefabs

- Create a way to page the world and see what tags are requested. Save that data in some sort of data set for garrysmod to read inside of the prefab editor. Expand the prefab editor so when saving a preset and setting its tag, we can chose from a list of tags we have found, or create a new one.
- Since we will be rigging presets on the cell potentially, we will need a way to convert a preset from one world to the other, for instance we might have a preset in the preview world we want in the main game or vice versca, so maybe we can duplicate the preset and adjust its references to match the target world?
- Adjust the view on the left so there is no longer a table of all the presets and instead is the active one you are currently viewing. Favour the prefab explorer for finding new prefabs. Refocus UI efforts there to make it the primary interface for finding prefabs. Open that instead of abbriviating else where
- Redesign the prefab editor so the it is a tree view with each prefab being under a node that is its tag, allow the same prefab to be listed under multiple tags if needed.
- Non-tagged prefabs should still be accessible and editable, but they should be clearly marked as untagged in the tree view.
- Consider adding a search or filter functionality within the tree view to quickly locate prefabs by name or tag.

# Zombie Spawning and Navigation

- Zombies sometimes spawn in weird places, like on top of fences? Zombies should only spawn in a wide area of ground on the ground, they shouldn't spawn on top of objects or in mid-air.
- Zombies get really stuck on displacements like the one found in the epicenter.
- Zombies don't know how to go through fence gates and other things like doors or windows.
- Zombies need to have a lesser cone of vision depending on how foggy it is, or how dark it is, in the dark, zombies are basically blind, allowing stealth. Also, zombies should allow stealth opportunities for players to sneak past them without being detected. If a player is crouched and walking behind a zombie, that zombie wont notice them, zombies might not even see them either if the fog is thick or visibility is low.