
# Alpha 2.6 Fixes

# Phase A

- Fix/finish tile rotation entity and build zoo script giving an error that tile rotation entitys are not in the correct position
- I think I messed up the logic on the rotatations when it comes to tile rotations on buildings with a code edit that I did which I can't remember which line. I think I flipped the orientation of north/south in the code when checking with the tile position entity. I am not sure if that change persisted
- Check that each tile template is using the tile direction entity correctly and in the right positon.  For instance, if the tile direction entity is set to south the position for a 1x tile sound be 0,-320, and for a 2x tile it should be 0,-640. If the entity is set to north then the position for a 1x tile should be 0,320 and for a 2x tile it should be 0,640. If the entity is set to east then the position for a 1x tile should be -320,0 and for a 2x tile it should be -640,0. If the entity is set to west then the position for a 1x tile should be 320,0 and for a 2x tile it should be 640,0. The height the entity is from the floor shouldn't matter.
- Now what ever direction the tile is in in hammer shouldn't matter as it should rotate the tile using the tile direction entity to a road or motorway or path it is next too
- Verify that the tile direction entity is being used correctly and that the building is being rotated to align with the direction of a road if it is next to one.
- change nomenclature with "authored-local tile edge" to just "local tile edge" as well as authored entrance edge to just "tile edge" and explain in the description the building will be rotated so this entity is aligned with the road if it is next to one. This will be a more clear and consistent terminology for the tile edge entities.
- Update docs accordingly so this is clear for developers how they set up their tiles


# Phase B

- Make sure the new tile_park and tile_leisure, tile_petrolstation, tile_hospital and tile_laboratory tiles from tiletemplates/buildings folder for our various landmarks are implemented and working.
- Fix an error where if a road bridge is next to a border piece, the border piece is just a normal road instead of a road bridge
- Make sure new decoration pieces are being used in tiletemplates/decorations
- Rebuild a brand new preview world and zoos for testing purposes

# Phase C

- Thumbnails for maps are not working because garrysmod doesn't like maps which are in a sub folder, so we will need to add a new prefix to the filename after zn which is the name of the current profile. The individual puzzle maps will also appear in the menu which is unintentional after we do this so we will need to filter them out from the menu display into other so we will remove the zn_ from the beginning of their filenames as that is now reserved for the loader maps and instead use a different prefix for the puzzle maps such as zz. Make sure the map thumbs match that new maps name.
- Perform a smoketest of the production world being generated so we can see how many puzzle pieces the actual game will produce and how long it takes to compile and do all nav generations in a huge smoke test of the game in production setting.


# Alpha 2.7 Item, Loot and enemy/boss definitions.

# Phase A

- See item_and_loot_system_prototype.md and create a master plan of implementation for the system I have drafted splitting the implementation into phases with reducing as much token usage as possible in mind. 
- Please base the structore of the json files based on the Pseudo json code I have given you.
- Please expand on areas I have left thin or where logic doesn't seem to make sense and also clarify the implementation where you are unsure and also look out for anything I might have missed when theorising my implementation when making your plan. Define this all in a new md documment called item_and_loot_system_plan.md in the /docs folder


