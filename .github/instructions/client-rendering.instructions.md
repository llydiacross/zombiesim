---
name: "ZombieSim Client Rendering"
description: "Use when drawing meshes (mesh.Begin, IMesh/Mesh()), creating or changing materials (CreateMaterial, VMT keyvalues, shaders), using textures, or adding render hooks in ZombieSim client GLua — weather, puddles, snow cover, particles, beams, screen effects, and other world-space visuals."
applyTo:
  - "gamemode/cl_*.lua"
  - "gamemode/**/cl_*.lua"
---

# Client Rendering: Meshes, Materials, and Textures

These rules come from real failures in this repository, including a game crash, invisible geometry, lost textures, and garbage-collection stalls. Check the [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/) `mesh`, `IMesh`, `render`, and `cam` pages and the [VDC shader pages](https://developer.valvesoftware.com/wiki/Category:Shaders) before you use an unfamiliar parameter.

## Meshes

- Never call `mesh.Begin` with a primitive count of 0. Check the count first and skip the whole pass. A Lua error between `mesh.Begin` and `mesh.End` leaves the renderer corrupted and has crashed the game. Keep code that can error, such as nil lookups and table walks, outside the Begin/End block.
- Use a static `IMesh` (`Mesh()` with `mesh.Begin(imesh, MATERIAL_TRIANGLES, n)` or `BuildFromTriangles`) for geometry that rarely changes. Use immediate `mesh.Begin` for per-frame geometry, and batch it into one Begin per material per frame rather than one per object.
- Keep each `IMesh` well below 65,535 vertices. Split large surfaces into spatial chunks so each chunk can be rebuilt and culled on its own, and call `:Destroy()` on every replaced or stale `IMesh`.
- `IMesh:Draw` does not frustum-cull. Add your own per-chunk distance or view-direction culling before drawing many chunks.
- Draw static world-space `IMesh` geometry in `PreDrawTranslucentRenderables` inside `cam.PushModelMatrix(Matrix())` / `cam.PopModelMatrix()`. Skip the depth and skybox passes using the hook's first two arguments, the depth flag and the skybox flag. Drawn from `PostDrawOpaqueRenderables`, the snow cover failed depth tests and showed only against the sky.
- Lift ground overlays slightly along the surface normal to avoid z-fighting. Snow uses 4 units; puddles use about 2.
- Check triangle winding against the view direction. If you need double-sided translucent overlays, set `$nocull` instead of guessing at the winding.
- Rebuilding meshes creates garbage. Avoid creating a new vertex table or `Color` for every vertex on every rebuild, and avoid rebuilding many chunks per frame. Reuse tables where you can. Throttle the work with a `SysTime`-budgeted queue rather than fixed counts. Do not use coroutines in hot paths: LuaJIT cannot JIT-compile yield or resume.
- When you change the format of persisted point or vertex data, bump the module's mesh-version constant (for example `snowCoverMeshVersion`). State kept in the module table survives hot reloads, and old records will fail under the new code.

## Materials

- Choose the shader by what it supports. The `Refract` shader ignores vertex alpha, so feathered edges will not work with it. For feathered or vertex-faded meshes, use `UnlitGeneric` with `$vertexcolor 1`, `$vertexalpha 1`, and either `$translucent 1` or `$additive 1`.
- Put `$basetexture` and other textures in the `CreateMaterial` keyvalues table. A texture assigned later with `SetTexture` was lost on a fresh map load and only appeared to work because hot reload re-applied it. If the texture comes from another material, still name its path in the keyvalues.
- Give every created material a versioned unique name, such as `zombiesim_atmosphere_snow_cover_v3`. `CreateMaterial` caches by name, so after changing the keyvalues, bump the suffix; otherwise the old material is reused.
- To fake reflections, use an envmap-only additive material, for example `UnlitGeneric` with `$color [0 0 0]`, `$envmap`, and `$envmaptint`. Do not render a second scene view; true planar reflections are too expensive.
- Call `render.UpdateScreenEffectTexture` or `render.UpdateRefractTexture` at most once per frame, and only when something visible actually samples the texture.
- Using `SetFloat("$alpha", value)` to fade a whole static mesh works for UnlitGeneric `IMesh` draws. Keep per-vertex alpha for shape and feathering.

## Textures and Mounted Assets

- Reference mounted Valve paths, for example `nature/snowfloor001a`, `dev/water_normal`, `environment maps/water_wasteland05`, `effects/select_ring`, and `particle/particledefault`. Find them with `vpk.exe l`. Do not extract or copy Valve content. Running `vpk.exe x` from outside the VPK folder fails silently.
- Before relying on a material, check that it resolved: `Material(path):IsError()` should be false and its texture width should be greater than 0. Report the result in the module's diagnostics.
- A generic particle with a white fill reads as "milk". Use material-appropriate assets (water splash, droplet, and streak materials for rain; snow materials for snow) and judge the look in game.

## Validation

- Add diagnostics for each render path: material and shader status, texture width, mesh and chunk counts, triangle counts, and draw counts per frame. Expose them through the module's dev status command. If something is built but `draws=0`, suspect hook choice, depth, model matrix, or culling.
- Profile new per-frame work with `zombiesim_dev_profile_hooks`. Watch for spikes and garbage, not only the average cost.
- After rendering edits, search `console.log` for `mesh.Begin`, material, and Lua errors from the module. Syntax and status checks are static evidence only. Confirm the appearance in a running client after a fresh map load (`changelevel`), not only after a hot reload.
