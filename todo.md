# Alpha Test 1

- Detailed implementation plan: [alpha_test_1_implementation_plan.md](alpha_test_1_implementation_plan.md)

- The world border

 Take a look at the new folder in cellstemplates called borders, the idea here is that we are going to generate the world border for each cell, this will then be loaded in as a func_instance template into the map

  - make a celltemplate border for all possible puzzle pieces, reuse as much as possible to keep total map files down
  - Use template_border_s for the basis, copy that vmf, then place func instances around the border and use the tiles found in tiletemplates/borders

  - The wall for the border tiles is on the east side of the block, so when placing a wall tile the east side must be facing the map, the corners are on the east (south) bottom side as well

# Alpha 2

- Skybox tiles (in tiletmplates/skybox) which are 16th in size and can be used to generate a convincing skybox which makes sense with the most information we can retrieve from a generated cell. We do know which direction the roads should go, so we can draw a road in the skybox on the edges where one would expect it to be. That's all that's really important, then we can randomize the skybox based on density and its environment (if its dense, put more buildings in the skybox)
- Add a ring of fog around the skybox so you can't look down the road and break the illusion of this being a world pieced together from tiles.
- Everything in the new skybox tile needs to be func_detail


# Alpha Test 2

- Create zombie AI next bot behavior
- Optimize zombie AI pathfinding