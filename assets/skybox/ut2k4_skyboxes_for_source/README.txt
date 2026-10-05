A box full of fantastical skyboxes.

I didn't bother to fully prepare all skyboxes.
View the skyboxes in VTFEdit, choose one that you like, then follow these steps:
1. Rename the file with an UP, DN, BK, FT, LF, RT ending. This helps source recognize on which side of the sky to place the texture.
2. Create a .vmt with same filename, and enter this as content:
sky
{
	$basetexture "skybox/(FILENAME here, WITHOUT extension. Example: EF_DN)"
	$nofog 1
	$nomip 1
	$ignorez 1

}
This features all settings expected of a skyboxes. The textures must be placed in the "skybox" folder.
3. Some skies are only half height. If you want to use one, export it as a .tga (highest image quality), open it in editor, and add the missing lower half. Then import into VTFEdit again and overwrite the original .vtf in 2048x2048.

For reference, see the ready-made "EF" textures.