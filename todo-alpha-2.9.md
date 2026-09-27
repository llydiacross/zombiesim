# Alpha 2.9 (Hud Weapon & Ammo Display Transitions, Fog, Skyboxes, Post Processing Effects, Dismemberment)

## HUD Ammo and Ammo Display

- Take a look at https://www.gameuidatabase.com/gameData.php?id=2191&autoload=92004
- Specifically the component which shows the weapon and the ammo
- Please copy exactly that for us for the current weapon and ammo display
- Above that, but in smaller rectangular boxes which display other equipped  and their respective ammo counts.
- when you have that weapon selected, the box is bigger to indicate it is the active weapon, then it shrinks back to the smaller size when it is no longer active.

- Each bullet should be represented visually in the ammo display, allowing players to quickly gauge their remaining ammunition at a glance.
- Only do this for the current clip, as just like the image, the total amount of reserve ammo goes next to the picture of the weapon

## Requirements and small fixes

 - In dens, I was thinking of making it so you are actually first person. So for dens we need to make the player have a first person camera.

 - Transition the camera perspective on transition between first person and top down views, ensuring a more immersive experience.

 - Implement den entrances that allow players to enter and exit dens seamlessly. 

 - Fix border transition gates as they are not working and do nothing

## Add Skyboxes to the cells

 - In the den, there is such a thing as drawing the skybox in a custom fashion in gmod I am sure. I was wondering when you are in a den, we could draw a unique skybox using lua that reflects the environment outside the den, enhancing the immersive experience.

 - Theorise how to take advantage of propper to generate convincing set of skybox models for the different environments to be put in each cell. This will help create a more immersive and visually appealing game world.

## Better Fog

- I want the fog to be really misty like Silent Hill, creating a dense and eerie atmosphere that enhances the sense of immersion and tension in the game world.
- See what source can do for us in terms of fog density, color, and behavior to achieve the desired misty effect.
- Is there anyway to expand further than what source will let us do?
- Experiment with different fog textures and particle effects to enhance the misty atmosphere and create a more immersive environment.
- Note: A fog wall needs to be added around the cell particularly in the transition gates to sort of hide the abrupt changes in the environment and maintain the immersive foggy atmosphere. Kind of like how Civilization games use fog of war to obscure unexplored areas.

## Cinematic Cell Transitions

- Since we are fixing cell transitions, I would like the transitions to be more cinematic, incorporating smooth camera movements, dynamic lighting changes, and possibly brief cutscenes to enhance the player's sense of immersion and continuity between different cells. 
- The initial idea was for the player to pres e on the transition gate, and then the camere will point to the direction they are about to enter and the player will begin walking forward as the camere stays there but slowly glides upwards, creating a cinematic effect that emphasizes the transition between cells.
- Then, it fades to black, garrysmod loading screen (can we some how figure out how to do the non abrumptive level change and make level changes seamless and smooth for the player) and then seamlessly transition to the new cell without breaking immersion.
- It keeps black, and then when the player spawns, the black then fades out gradually, revealing the new cell and maintaining the cinematic and immersive experience.

## Film Grail Effects and noise

- Implement film grain effects to give the game a more cinematic and atmospheric feel, enhancing the overall visual experience.

## Percicipation

- Implement dynamic weather effects, such as rain, snow, and fog, to create a more immersive and realistic game environment.
- Ensure that precipitation interacts with the environment and player actions, such as leaving wet footprints or causing surfaces to become slippery.
- Experiment with particle systems to achieve visually appealing and believable precipitation effects.

## Ambient Soundscapes

- Implement Source Soundscape system to manage and play ambient sounds, ensuring they are spatially accurate and responsive to the game environment.
- Experiment with layering different ambient sounds to create a rich and evolving soundscape that reflects the changing conditions and events within the game world.

## Dismemberment

- If you are familiar with the dismemberment mod for garrysmod, but it would be very nice to some how integrate dismemberment mechanics into our game, allowing for more realistic and visceral combat experiences. Limbs should be able to be severed and react physically to the environment, adding a layer of depth and intensity to combat scenarios. Blood decals and particle effects should accompany dismemberment events to enhance the visual impact and realism. 

- Increase the variety and realism of dismemberment effects, ensuring that different types of attacks result in appropriate severing and visual feedback. This could include varying blood splatter patterns, limb physics, and environmental interactions to create a more dynamic and immersive combat experience.

- Gore effects should be enhanced to provide a more visceral and impactful experience. This includes realistic blood splatter, body part physics, and environmental interactions that respond dynamically to combat events.

- Note: if a zombie is dismembered their piece is not lootable only the main body it comes from is lootable.

## Other improvements

- Den NPCS added to compass
- Make the waypoint snap to the coordinal directions (N, S, E, W) for easier navigation, if the transition gate is the one for the waypoint it should be yellow instead of the default color.
