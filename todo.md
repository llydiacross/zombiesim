
# Alpha 2

- 
- Skybox tiles (in tiletmplates/skybox) which are 16th in size and can be used to generate a convincing skybox which makes sense with the most information we can retrieve from a generated cell. We do know which direction the roads should go, so we can draw a road in the skybox on the edges where one would expect it to be. That's all that's really important, then we can randomize the skybox based on density and its environment (if its dense, put more buildings in the skybox)
- Add a ring of fog around the skybox so you can't look down the road and break the illusion of this being a world pieced together from tiles.
- Everything in the new skybox tile needs to be func_detail


# Alpha Test 2

- Create zombie AI next bot behavior
- Optimize zombie AI pathfinding