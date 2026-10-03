# Alpha 3.0

## Additions

- New Skybox System
    - Its time to speculate how we are going to implement a 3D skybox to our cells.
    - My original idea is to generate the skybox for each cell
    - This will allow us to have a more immersive environment for our cells.
    - Using propper? Proper can make our hammer levels models
    - Maybe we can make models of some of the tiles like the road tile, and stuff like that?
    - The Skybox is 16 times small I think?
    - All I want the skybox to reflect is the road layout of the cells around the current cell, use custom made skybox buildings for building placement, don't use the actual tiles.
    - Skybox is generated dynamically
    - Test create models from the tiletemplates using propper, make models of all the roads, try to put them in the skybox. See how it runs.
    - Please note that the skybox renders things a lot differently than the main world, so you may need to adjust the scale and placement of models accordingly for it to align?
    - Fog should block the view of distant skybox elements to create a more realistic depth effect.
    - Going to some how need to make sure the lighting of the skybox matches the lighting of the main world to maintain visual consistency.
    - Consider adding dynamic elements to the skybox, such as moving clouds or changing weather conditions, to enhance the immersive experience.
    - Would snow render in the skybox?
- New tile decorations added
- Added new tile_industrial buildings, check they are being placed
- Implement the new music system, I have only made one music track now and it is in content/music and my idea is that I will create a track for each safezone but also have tracks which can be played in all cells depending on the environment tag that cell is in.
    - Will need to get a list of possible music names which can occur in different safezones and environmental tags.
    - If no music is specified for a particular safezone or environmental tag, the system should fall back to a default track to ensure there is always background music playing. 
    - When you are transitoning between cells or safezones, the music should smoothly fade out, and then fade back in once you spawn, resuming that track from where it left off.
    - Music should play once every 10 minutes or so, on a random timer. It is not "dynamic" or reactive to in-game events. Only the environment you are in shapes how the music plays.
    - As mentioned, safezones get their own music, variations (just like the buildings) are symbolized by letters at the end of the music track name.
    - Decide randomly which variation of the music track to play when multiple variations are available for a safezone or environmental tag.


## Fixes & Improvements

- Improve the UI for services.
    - Currently the UI for services is quite confusing. When you press E on an NPC which has a service, on the left you should instead see the NPC's Level, and stats for instance and not your own? and also, when you press E on an NPC. You should by default have selected the NPC's service option selected. Improve this screen so it is a lot clear and better.
- Fix the stash inside of the safe den from not working and showing your stash when you press E on it.
- I want to change how banks work. When you press E on the bank terminal, it opens up a new interface that allows you to deposit and withdraw money into bundles more intuitively, showing your current balance and recent transactions.
- When you hold E on an NPC, a radial menu pops up allowing you to quickly access the NPC's services or trade with them or talk to them or something else in the future.
- When you hover over an NPC, their name appears at the crosshair and a "Hold or Press E to interact" prompt is displayed, indicating that you can engage with the NPC. Make it look pretty and nice.
- Display the current cells damage level in the form of stars on the top right on the screen with the heading "DANGER"
- Increase the amount of folliage being generated in the game world. Take advantage of all types of tree models and bushes available to us, place them more complexly, on natural surfaces such as grass, dirt, and rocky areas and try to maximize our algorith to create a algorithm that can very smartly place this foliage in valid spots.
- Ensure that less empty tiles, eg just the terrain tiles are being placed in generated cells in our world as this just leads to cells with large open areas that don't really do anything.
- Below that, under the heading "RADIATION", indicate the current radiation level in the cell, using a realsitic measurement system (e.g., sieverts or rems).
- Add a giger counter effect which reacts to the current radiation level in the cell, providing both visual and auditory feedback to the player. If it is 0 or not that very high, this effect is turned off.
- Ensure that radiated zombies are spawning in the radiated zones and your giager counter reacts accordingly to the radiation of those zombies that approach you, with your screen turning gray and shaking appropriately based on the intensity of the radiation.
- Add damage indicators for the player, showing the direction and intensity of incoming damage. This should help the player understand where they are being attacked from and how severe the damage is. These should fill the edges of the screen, with the intensity of the indicator corresponding to the severity of the damage. I suggest using a red gradient that becomes more intense as the damage increases depending on the direction.
- Change how the crosshair works so it doesn't reflect your health, but stays gray when aiming at no target, and changes color or style when the crosshair is over interactable objects or enemies.
- Make the UI for trading with NPCS less cluttered and more intuitive, ensuring that players can easily understand and navigate the UI. Instead of a list of items, please use a grid of items for better visual organization and consistency. Display the item icon, and give it a golden border if it is a master craft. When you hover over the item, it shows you the stats. When you click on the item, it brings up a window where it then displays the item again, with all the stats, and then a "BUY NOW" button, also, a "BUY X5 AMOUNT" button if applicable and can afford, and a 10x if applicable and can afford. If its ammo, buy "FULL ROUND" of the magazine, or maybe "BUY X5 ROUNDS" if applicable and can afford. Also a custom field which you can set a specific amount of things you would like to buy, with + and - buttons to adjust the quantity. 
- Fix the FDG so when placing things like the bank, the stash, they use the model they will be represented by in the world. Also make sure with NPCS we can set the model they have, and that model is reflected in the FDG as well. Also if you could add their animations and other visual properties to the FDG for a more accurate preview, and be able to change their default animation (for instance, to make an NPCS Sit)
- Fix the graphical issues and glitches which occur when a player walks in a puddle. The puddle splashes look instead like graphical artifacts, and look to be drawn incorrectly. The players footsteps also look to much like milky paint, and need to use the same material as the puddles
- Rain, the player, snow, and other such things draw on the minimap
- The minimap needs to "recapture" a fresh image of the map when the atmosphere changes. Right now it does this anyway when the user opens the map anyway, but in cases for instance if the level is snowy and then turns to rain, the minimap still shows snow. Bare in mind due to our current code it takes a while for snow to fully disappear, so keep this in mind when building the system which recaptures a fresh image for our mini map.
- When looting in shoulder cam, the "looting" progress bar or any other progress indicators should that are normally above the players head are not visible (so the stanima, damage taken..). Only and only when in shoulder cam mode, we need to instead display these indicators on the HUD.
- Implement new road piece and motorway piece variations.
    - See tiletemplates/roads/tile_road.vmf
    - See tiletemplates/roads/tile_road_a.vmf
    - See tiletemplates/roads/tile_road_b.vmf
    - See tiletemplates/roads/tile_motorway.vmf
    - See tiletemplates/roads/tile_motorway_a.vmf
    - See tiletemplates/roads/tile_motorway_b.vmf
    - See tiletemplates/roads/tile_motorway_c.vmf
- Many of the tiletemplates have been improved, possible loot spots have been added to a lot of the tiles. This will require a full recompile of the preview world for the changes to reflect.
- Many tiletemplates edited to improve visual fidelity and gameplay flow, including adjustments to lighting, collision, and potential loot spawn points.
- Removed some tiletemplates so please be aware of a .vmx does not have a .vmf that is probably just because I have deleted it
- Make sure our new ragdoll placing system, our new trash placing system does not place items in the border areas of the map as that is will be inaccessible from the player, leading to cases where loot cannot be obtained.
- Zombies can sometimes drop loot if they are killed but are in the border or, positioned in such a way next to a transiton gate that pressing e to look them actually transitions the level, leaving them to lose that loot. Figure out a way to prevent loot from the player feeling cheated in these scenarios.
- Use the bloody variants for human models that are zombies.
- Improve dismemberment effects for zombies, ensuring that limbs and body parts spew blood particles realistically and make a lot more blood decals. 
    - Consider taking advantage of the puddle system to make "pools of blood" which can form, consider how to do this cheaply and efficiently without causing performance issues.
    - If you deem it possible, then add bloody footprints!
- Decrease the walk speed for the player by default by 10%. Decrease the sprint speed for the player by default by 15%. Decrease stanima cost of sprinting by 25%. Increase stanima regeneration by 10%.