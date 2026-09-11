
# Alpha 2.6

- Fix tile rotations and build zoo script
 - We messed up the logic on the rotatations, currently the entities are placed on the northen edge but set as south and I think the algorithm is completely backwards by accident
 - This was because 2aa and 2aa were in reverse compared to everything else throwing us off.
 - All buildings won't work now as it says:
    + FullyQualifiedErrorId : Tile direction marker in 'C:\Program Files (x86)\Steam\ 
   steamapps\common\GarrysMod\garrysmod\gamemodes\zombiesim\tiletemplates\buildings\  
  tile_commercial_2a_2x.vmf' must sit at the midpoint of its north edge.
 

 
# Alpha Test 3


- Skybox tiles (in tiletmplates/skybox) which are 16th in size and can be used to generate a convincing skybox which makes sense with the most information we can retrieve from a generated cell. We do know which direction the roads should go, so we can draw a road in the skybox on the edges where one would expect it to be. That's all that's really important, then we can randomize the skybox based on density and its environment (if its dense, put more buildings in the skybox)
- Add a ring of fog around the skybox so you can't look down the road and break the illusion of this being a world pieced together from tiles.
- Everything in the new skybox tile needs to be func_detail

