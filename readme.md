# Zombiesim



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
 
 # Folder Structure

 - ./tiletemplates
    - the pieces (chunks) for making the cells, usually each file is just 1 chunk wide
 - ./content
    - data read by gmod
  
  Further into content is the `maps/city` folder

  These are the maps of the city. The filename can be used to deduce which cell it is by following this table

  `zn_<identifier>_<x>_<y>_<z:optional>.bsp`

   - x and y are the coordinates of the cell in the city, z is the layer/floor of the cell, identifier is a string that can be used to identify the map, for example "downtown" or "suburbs" or commonly "city"

- ./source

 The .vmf files for the cells of the city, should match a map file in the content folder idealily.

 # Generator Settings

 Generation is controlled from [generator-settings.json](generator-settings.json). Start with the plain-language guide in [docs.md](docs.md); it explains every setting, shows the preview workflow, and marks settings that are safe to experiment with.

 For future multi-tile prefab support, see [two_by_two_tile_templates_plan.md](two_by_two_tile_templates_plan.md).
