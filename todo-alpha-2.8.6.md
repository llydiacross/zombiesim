# Todo List for Alpha 2.8.6

## Features to Implement

- I have changed how safezone cells work. please check the celltemplates/ and instead of having a safezone for each environment now there is just a safezone for each landmark, cell_safezone is the default safezone for all landmarks unless otherwise specified. 

- I have created a new savezone called cell_safezone in safezones/cell_safezone.vmf it should include all the npcs along with the bank and the player stash. This should be the default safezone.

- Please change the current implement to no longer take an environment parameter and instead rely on the landmark-specific safezone configuration.

- Rename "The Evac Zone" to "The Storm Drain" as cell_safezone at 0,0 should now be the Storm Drain.

- In tiletemplates/safezones there is now entrance_safezone_3x that should be used for cell_safezone entrances.

- 3x3 tiles may take up border tiles

- These entrances are placed in the cell the safezone is in, always place them next to aroad.

- In the case of 0,0, place the entrance_safezone_2x next to the t-section in the middle

- If the tile is 3x3, place it in the corner, taking up a bit of the border