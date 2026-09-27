# Alpha 2.9 (Hud Weapon & Ammo Display Transitions, Fog, Skyboxes, Post Processing Effects, Dismemberment)

- Alpha 2.8 was accepted on 2026-09-27. Its ordinary-zombie corpse search interaction remains an explicitly deferred follow-up.
- Note: Please now keep the current world preview data untouched now for the foreseeable future as all our changes should not required a world re-generation and we will wager when to rebuild vmfs and things like that again due to how long it takes to do it (2 hours)


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

## Blood Decals

- Paired with the dismemberment system, blood decals should be dynamically generated based on the location and severity of injuries. This includes splatters from severed limbs, blood trails from wounded characters, and environmental staining that reacts to player and NPC interactions.
- Consider implementing a system for blood decals to gradually fade over time, reflecting the natural drying and cleaning processes in the game world. This can enhance realism and prevent excessive visual clutter from persistent blood effects. 

## Bullet casings

- Make sure correct bullet casings are used for each firearm, reflecting the caliber and type of ammunition being fired. This adds to the realism and consistency of the game's ballistic system.

## Muzzleflash and tracer effects

- Implement more realistic muzzleflash and tracer effects for firearms. Muzzleflashes should vary based on the type of weapon and ammunition being fired, while tracer effects should accurately represent the trajectory of bullets, enhancing both visual feedback and gameplay immersion.
- Smoke effects should accompany muzzleflashes, with density and duration varying based on the weapon and ammunition type. This adds to the visual realism and helps convey the power and impact of each shot.
- Larger caliber weapons should produce more pronounced muzzleflashes and smoke effects, reflecting the increased power and impact of each shot.

## Other improvements

- Den NPCS added to compass
- Make the waypoint snap to the coordinal directions (N, S, E, W) for easier navigation, if the transition gate is the one for the waypoint it should be yellow instead of the default color.

## Dynamic tree and foliage placement

- Implement a system for dynamically placing trees and foliage throughout the game world, ensuring that vegetation appears natural and varied. Use the texture to determine suitable locations for different types of vegetation, taking into account factors such as terrain type, slope, and lighting conditions. Do this in gmod using Lua script and not as apart of the static map compilation.

- Sometimes, a tree is highlighted yellow meaning you can harvest it with an axe or other appropriate tool to collect wood or other resources.

- Trees might also be harvest for fruits, nuts, or other natural resources depending on the tree type and season. Same as bushes. Bushes might be highlighted yellow when they can be harvested, and they may provide berries, nuts, or other resources depending on the season and bush type.

## Trash Placement

- Implement a system for dynamically placing trash and debris throughout the game world, ensuring that it appears naturally scattered. Bits of paper, broken bottles, and other small debris should be placed in a way that feels organic and responsive to the environment. They should be non collidable to the player but react physically to environmental forces, such as wind or player interactions.

## Looting from shelves

When in the shoulder mode, the players crosshair should be the indicator for what loot spot to search. The loot spot should be highlighted or outlined when the crosshair is over it, providing clear visual feedback to the player. 

## When the player goes under a block or prop

- Currently the camera snaps below the block or prop which can be disorienting for the player. Consider implementing a smoother transition or alternative camera behavior to maintain player orientation and visibility when moving under objects. 
- In top down mode, force the camera to always remain above the player, preventing it from colliding with with world geometry, except in the case where it is in orbial mode, else implement a smoother transition for the camera when moving under objects.
- Consider adding a visual indicator or outline for objects that the player is moving under to help maintain spatial awareness and prevent disorientation.
- Garrysmod has halos built in which can be used to highlight objects that the player is moving under, providing a clear visual cue and helping to maintain spatial awareness.

## More entity loot

- scrape half life 2 vpk models for additional lootable entities and props to expand the variety of items players can find throughout the game world.

- make prop_ragdoll lootable as well, allowing players to search through fallen characters. look at the ragdoll model and determine appropriate loot spots based on the ragdoll type. If its a human ragdoll, maybe there is higher chance to find weapons, ammunition, or personal items like wallets and keys. For other types of ragdolls, adjust the loot accordingly to match the context of the entity. 

## AFK Mode

- It should take a 3 second countdown to open inventory or scoreboard or options menu (cheats menu opens instantly and afks you). AFK Mode means zombies won't attack you. So you are safe to go through your inventory in peace. When you leave the AFK state, you get a couple of seconds of invulnerability to prevent immediate attacks from zombies.

# Hud Notifications

- Display notifications for important events such as leveling up, play a sound to go with it and show a visual cue on the HUD in the center of the screen below the compass and below the xp bar.
- Consider adding different types of notifications for various events, such as quest updates, achievements, or important game alerts, to keep the player informed and engaged.

## Enemy hit markers

- Add call of duty style enemy hit markers that appear on the HUD when the player successfully hits an enemy, providing immediate visual feedback. 
- Add a noise effect or sound cue to accompany the enemy hit markers, providing additional feedback to the player when they successfully hit an enemy.
- Ensure that enemy hit markers are displayed consistently across different screen resolutions and HUD layouts, maintaining clarity and visibility for all players.
- Consider adding different hit marker styles or colors based on the type of damage dealt (e.g., headshots, critical hits) to provide more detailed feedback to the player.

## XP Bar

- Add the experience bar to the hud just below the compass, it should be a solid bar that fills up as the player gains experience points, providing a clear visual representation of the player's progress towards the next level.
- Consider adding different colors or effects to the experience bar to indicate milestones or bonuses, such as a glowing effect when the player is close to leveling up.
- Optionally, display the numerical experience points and the required points for the next level alongside the bar for more precise feedback.