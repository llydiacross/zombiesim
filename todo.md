
# Alpha 2.6 Fixes

# Phase A

- Fix tile rotations and build zoo script
 - We messed up the logic on the rotatations, currently the entities are placed on the northen edge but set as south and I think the algorithm is completely backwards by accident
 - Basically, all buildings are facing south with their entrance on the south edge. This applies or decoration pieces as well
 - This was because 2aa and 2aa were in reverse compared to everything else throwing us off.
 - All buildings won't work now as it says:
    + FullyQualifiedErrorId : Tile direction marker in 'C:\Program Files (x86)\Steam\ 
   steamapps\common\GarrysMod\garrysmod\gamemodes\zombiesim\tiletemplates\buildings\  
  tile_commercial_2a_2x.vmf' must sit at the midpoint of its north edge.
 - The entity should be equal to which edge the building entrance to the building is facing in order to ensure it is correctly placed next to a road
 - If a tile doesn't have a tile direction marker, just assume it is north
- change nomenclature with "authored-local tile edge" to just "local tile edge" as well as authored entrance edge to just "local tile edge" and explain in the description the building will be rotated to align with the local tile edge.
- Update docs accordingly so this is clear and consistent with the new terminology.

# Phase B

- Thumbnails for maps are not working because garrysmod doesn't like maps which are in a sub folder, so we will need to add a new key to the filename which is a unique abbreviated ID of the current profile. The individual puzzle maps will also appear in the menu which is unintentional after we do this so we will need to filter them out from the menu display into other so we will remove the zn_ from the beginning of their filenames as that is now reserved for the loader maps and instead use a different prefix for the puzzle maps such as zz. Make sure the map thumbs match that new maps name.
- Perform a smoketest of the production world being generated so we can see how many puzzle pieces the actual game will produce and how long it takes to compile and do all nav generations in a huge smoke test of the game in production setting.

# Alpha Test 3


- Skybox tiles (in tiletmplates/skybox) which are 16th in size and can be used to generate a convincing skybox which makes sense with the most information we can retrieve from a generated cell. We do know which direction the roads should go, so we can draw a road in the skybox on the edges where one would expect it to be. That's all that's really important, then we can randomize the skybox based on density and its environment (if its dense, put more buildings in the skybox)
- Add a ring of fog around the skybox so you can't look down the road and break the illusion of this being a world pieced together from tiles.
- Everything in the new skybox tile needs to be func_detail

