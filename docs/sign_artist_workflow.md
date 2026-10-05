# Original signs and billboards

Alpha 3.1.0 provides six original, reusable signs. Their geometry and original
demonstration artwork are generated from ZombieSim-owned sources. Structural
materials reference mounted Source textures in place; no mounted game model or
texture is extracted, edited or redistributed.

## Build the example

From the repository root in Windows PowerShell:

```powershell
.\bin\build_sign_assets.ps1 -WorldProfile preview
.\bin\test_sign_assets.ps1
```

The build needs the installed Garry's Mod `bin\vtex.exe` and `bin\studiomdl.exe`.
It uses Windows System.Drawing to prepare opaque textures; Blender, ImageMagick
and a model editor are not required. The command compiles six small models and
two original textures (artwork and lamp lens), **not** city maps. It rejects
non-preview profiles.

The original text/colour source is
[alert_billboard.json](../assets/signs/alert_billboard.json). Geometry and UVs
are defined by [sign_assets.psm1](../bin/sign_assets.psm1); compiler invocation
and packaging belong to [build_sign_assets.ps1](../bin/build_sign_assets.ps1).
Build products and logs live in `generated\signs_preview`, not in the source
artwork directory.

## Development mounting and sign zoo

The gamemode's `content` directory is the distribution source, not a reliable
Hammer/game-root search path. Stage the current build for local development:

```powershell
.\bin\stage_sign_assets.ps1
# Or compile new artwork/models and stage in one command:
.\bin\build_sign_assets.ps1 -WorldProfile preview -StageToGame
```

Staging copies only this original sign family's compiled model files and
material wrappers/textures into the installed `garrysmod\models\zombiesim\signs`
and `garrysmod\materials\models\zombiesim\signs` directories. Every copy is
SHA256-verified; `generated\signs_preview\staging-report.json` records the files.
Mounted Valve textures remain references and are not copied. Root copies are
development conveniences, not release outputs; repeat staging after each build.
Staging alone preserves the current artwork and does not invoke a compiler.
Reload the map after changing already-loaded models/materials; restart Hammer
if its model/material preview cache still shows the old version.

Generate the complete six-variant showroom for Hammer, or build its single BSP:

```powershell
.\bin\build_sign_zoo.ps1
.\bin\build_sign_zoo.ps1 -Compile
.\bin\test_sign_zoo.ps1 -Compiled
```

Open `generated\signs_preview\zoo\zn_dev_sign_zoo.vmf` in Hammer.
Large signs stand in the north row facing south: freestanding on the west,
supported legless panel in the centre, lamp-lit billboard on the east.
The small wall sign, thin print and borderless poster mount on the south wall
facing north, in the same west-to-east order. A central spawn/viewing aisle
allows front, side, rear and wall-depth inspection. Props are direct entities
from the generated prefabs; the lamp includes its baked spotlight.

`-Compile` runs structural/staging tests, VBSP, a small portal-budget gate, then
VVIS/VRAD using the project's final static-prop lighting preset for **one map
only**, and hash-verifies its copy into
`garrysmod\maps\zn_dev_sign_zoo.bsp`. It reuses a current successful BSP when
the zoo VMF and sign models/materials are unchanged. Compiler logs, reports and
intermediates remain under `generated`; this development map is not packaged
into `content\maps`, added to a world manifest, or substituted for city recipes.
Launch manually with `map zn_dev_sign_zoo` (prefer a sandbox development session).
This is an isolated asset fixture, not a deployed ZombieSim city or safe room.
Hammer appearance, in-game static collision and baked-light appearance require
human inspection; automated compilation is not their acceptance.

## Replace the artwork

1. Build the example once. Open
   `generated\signs_preview\modelsrc\artwork-template.png` in your preferred image
   editor, or start a blank **1024 x 512** canvas.
2. Keep an editable master with layers under `assets\signs` or your licensed
   artwork source directory. The generated template is a starting point, not
   the place to keep your edited master: a default build recreates it.
3. Export a fully opaque PNG at exactly **1024 x 512**. Draw normally with the top
   of the picture at the top of the image. The panel UVs use the entire canvas;
   no rotation, mirroring, UV editor or model editing is required.
4. Build with your exported image:

   ```powershell
   .\bin\build_sign_assets.ps1 -WorldProfile preview -ArtworkPath .\assets\signs\my_billboard.png
   .\bin\test_sign_assets.ps1
   ```

   The current prototype replaces the artwork on **all instances of this
   sign family**. It does not yet produce a catalogue of independently selectable
   artwork designs or multiple artwork skins. Do not run the default build to preserve a
   custom finish: repeat the command with your source PNG.
5. Keep your source image and layered master. Do not edit the generated TGA, VTF,
   SMD, QC, generated model, skybox manifest or compiled BSP.

The compiler retains mipmaps. Finished artwork through `-ArtworkPath` must be
opaque and exactly 1024 x 512. Layered inputs below can have arbitrary dimensions
and transparent foregrounds. Use large text and strong contrast. The headline is
intended to read from approximately 256-512 Hammer units; the small footer is a
close-up detail, not a skyline label.

## Image layers and JSON settings

Set `imagePath` and `backgroundImagePath` directly in
[alert_billboard.json](../assets/signs/alert_billboard.json). Relative paths in
JSON resolve from that JSON's directory; command-line paths resolve from your
working directory. `-ImagePath` and `-BackgroundImagePath` override JSON values.
An explicit empty argument disables the corresponding configured layer.

```powershell
# Image preserved in full, centered with a 32-pixel safe border.
.\bin\build_sign_assets.ps1 -ImagePath .\assets\signs\cs80.jpg

# Full-bleed background, cropped to cover the panel without stretching.
.\bin\build_sign_assets.ps1 -BackgroundImagePath .\assets\signs\cs80.jpg

# Transparent logo/graphic over an independently editable background.
.\bin\build_sign_assets.ps1 -ImagePath .\assets\signs\logo.png -BackgroundImagePath .\assets\signs\background.jpg
```

PNG/JPEG artwork is resampled without changing its aspect ratio: the foreground
uses **contain** inside a 960 x 448 safe area, and the background uses **cover**
across the full 1024 x 512 panel. Alpha is composited onto the configured
`background` colour, producing an opaque compiler-ready image. Either layer is
optional. With no layers, the JSON text/colour design is used. When either image
layer is provided, it replaces the generated text design; bake any desired text
into your source graphic. `-ArtworkPath` is the separate finished-panel route
and cannot be combined with image layers.

The supplied `cs80.jpg` was used only as user-provided test artwork. Its
redistribution rights are not established by this test; return to original
artwork or confirm permission before shipping that image or its generated VTF.

Set each structural material independently in the JSON:

```json
"materials": {
  "legs": {
    "baseTexture": "metal/metalwall021a",
    "normalMap": "metal/metalwall018a_normal"
  },
  "rim": {
    "baseTexture": "metal/metalwall017a",
    "normalMap": ""
  },
  "back": {
    "baseTexture": "metal/metalwall025a",
    "normalMap": ""
  }
}
```

These are **texture virtual paths**, without `materials/` or `.vtf`, not complete
brush VMT names. The build verifies each referenced texture exists, then makes a
model-compatible `VertexLitGeneric` wrapper. Optional normal maps use the same
UVs. Choose textures and normals that match each other; arbitrary brush shaders,
water, multi-texture blends or material proxies are not automatically converted.
Mounted paths remain references; original addon textures can also be resolved
from `content\materials`. Long steel faces tile at 64 model units rather than
stretching one texture across a post.

Use `-DefinitionPath` to build from a separately maintained JSON with the same
schema. This still updates the same six prototype model paths; it is not yet
a multi-artwork catalogue. Do not edit generated VMTs or the runtime catalog.

## Self-lit artwork versus physical lamps

`selfLit` selects self-lit artwork for all variants except the lamp-lit billboard.
`selfIllumBrightness` (0-1, default 0.85) controls its tint. For a normally lit
panel set `selfLit` to `false`, or override it for a build:

```powershell
.\bin\build_sign_assets.ps1 -SelfLit $false
```

Only the artwork is self-illuminated. Legs, backing and rims remain scene-lit.
Self-illumination makes the panel readable in darkness; it does not cast light
onto nearby geometry, imply bloom, or bypass fog.

The **illuminated** variant instead has an ordinary lit panel, an overhead lamp
housing and a glowing lens. Its generated Hammer prefab includes a `light_spot`
aimed onto the panel. Insert the **whole prefab as entities** into the
authored tile; placing only the model does not create light. The static light
needs a normal affected-map VRAD build. This avoids adding many expensive
runtime projected lights to city maps. Nearby skybox detail draws the lamp model
and its glowing lens but deliberately does not recreate its map light.

## Place it in Hammer

All paths below are under `models/zombiesim/signs/`:

| Variant | Model | Origin and size |
| --- | --- | --- |
| Freestanding | `alert_billboard.mdl` | Ground between the posts; 272 wide, 296 high |
| Legless panel | `alert_billboard_panel.mdl` | Panel's bottom midpoint; 272 wide, 144 high |
| With real lamp | `alert_billboard_illuminated.mdl` | Ground between posts; 272 wide, 306 high; lamp reaches 62 units toward the viewer |
| Small wall sign | `alert_billboard_wall.mdl` | Back-plane centre on the wall; 104 wide, 56 high, protrudes 8 units toward local south |
| Thin framed print | `alert_billboard_print.mdl` | Back-plane centre on the wall; 272 wide, 144 high, 2-unit backing plus 0.3-unit trim |
| Borderless poster | `alert_billboard_poster.mdl` | Centre on the wall; image only, 256 wide, 128 high, front at local Y=-0.1; no collision |

All fronts face local south (-Y). The small sign's artwork is 96 x 48 units; it
uses the same 2:1 artwork without remapping. The legless panel has no posts and
is suitable for separately authored supports or a facade.

The print retains the large panel's 256 x 128 artwork area inside a thin frame.
The poster uses that image area alone: two front-facing triangles, no bezel,
backing, posts, or physics hull. It is intended to sit just outside a wall,
not float as a double-sided object. In Hammer set its `solid` to `0` (the generated
prefab already does this), and offset the origin at least 0.5 units off the wall
to avoid depth fighting. For a full-bleed picture use `backgroundImagePath` or
a finished `-ArtworkPath` canvas: a foreground-only `imagePath` still includes
the artwork's safe-margin background, even though the poster has no physical rim.

Large billboards and the legless panel have stepped bevels, a recessed inner
gasket, hex fasteners, a deeper backing and rear stiffeners. Freestanding models
also have post collars and broad foot plates. The original artwork rectangle,
cardinal facing and lamp position are preserved. No transparent glass cover is
added, avoiding unwanted reflections or another overlay draw.

Measured render geometry:

| Variant | Triangles |
| --- | ---: |
| Freestanding | 398 |
| Legless panel | 206 |
| Lamp-lit billboard | 424 |
| Small wall sign | 62 |
| Thin framed print | 62 |
| Borderless poster | 2 |

The regression bounds each model below 1,000 triangles and checks actual sloped
bezel normals. This is a geometry budget, not a frame-time measurement; many
separate sign instances still have draw and material costs.

Reusable VMFs are emitted at `generated\signs_preview\prefabs`. Open the desired
VMF in Hammer and copy its entity selection into the **authored** tile, or save
that entity selection as a Hammer prefab. Keep the illuminated variant's
`prop_static` and `light_spot` together when moving/rotating them. Do **not**
introduce a nested `func_instance` inside the tile for these prefabs: the current
skybox prop collector reads the tile's direct prop entities, not nested prefab
instances. The VMF is a generated placement helper, not a file to hand-edit.

Add a `prop_static` with:

```text
model: models/zombiesim/signs/alert_billboard.mdl
skin: 0
angles: 0 0 0
```

For the freestanding model, the origin is at ground height between the posts. At zero yaw the artwork faces
**local south (-Y)**, matching south-facing building frontage. The model spans
X = -136 to +136, Y = approximately -15 to +24 and Z = 0 to 296; the artwork itself
is 256 x 128 units, from Z = 160 to 288. It fits inside a standard 640-unit tile.
Place its origin inside the tile's footprint and keep the panel/posts clear of
doors, paths and neighbouring walls.

Positive Source yaw rotates counter-clockwise: yaw 0 faces south, 90 east,
180 north and 270 west. A parent tile instance rotates both the position and
facing. The artwork is on the front only; the rear uses the configured backing
panel. The freestanding collision mesh has five convex parts (panel, two posts
and two foot plates), leaving
the space between the posts open.

Edit **authored** tile VMFs, not generated city recipes. Adding the prop to a
tile requires the normal preview regeneration, affected-recipe compilation and
skybox refresh; identify affected recipes and obtain approval for any substantial
build first. Artwork-only changes using the same model/material paths do not
require a city BSP rebuild. A clean preview map reload may be needed to discard
cached models/materials when reviewing a changed asset.

## Skybox and distribution

The existing skybox builder reads the model, origin, angles and skin from the
authored prop and transforms them through the tile instance. The default detail
pattern already includes `billboard`, so no new renderer or runtime sign registry
is needed. A project-specific `detailPropPattern` override must also match the
model name. Nearby detail props must be enabled to see it in the skybox;
distant tower silhouettes deliberately do not include billboards.

Distributable files are:

- all six `content\models\zombiesim\signs\alert_billboard*.mdl`, `.vvd`, `.dx90.vtx`
  sets, and `.phy` for the five solid variants (the poster deliberately has none),
  plus other VTX variants produced by the installed compiler;
- `content\materials\models\zombiesim\signs\alert_billboard.vmt` and `.vtf`;
- `content\materials\models\zombiesim\signs\alert_billboard_lit.vmt`;
- `content\materials\models\zombiesim\signs\billboard_legs.vmt`,
  `billboard_rim.vmt` and `billboard_back.vmt` (mounted texture references only);
- `content\materials\models\zombiesim\signs\billboard_lamp.vmt` and `.vtf`;
- `content\data_static\zombiesim_signs_preview.json`, generated variant/light metadata
  for the preview bridge (not a sign source to edit).

Ship the complete model/material set through the normal addon content packaging.
Do not ship `generated\signs_preview`, compiler logs or intermediate sources.
Record licensing/provenance alongside any replacement artwork and ensure its
redistribution is permitted.

## Preview and validation

For an admin deployed in the preview profile:

```powershell
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on panel'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on illuminated'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on wall'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on print'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign on poster'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_sign off'
```

Face an open floor before `on`. The command creates a non-solid, full-sized
billboard ahead of the survivor, facing back toward them. Look up toward the
raised panel. It replaces only this player's previous billboard preview, removes
it after 180 seconds, and writes no persistent player or world data. It is a
visual probe, not proof of compiled `prop_static` collision.

`panel` previews the legless panel raised 96 units above the ground. For `wall`,
aim at a vertical wall within 320 units: the small sign is mounted on the hit
surface with its back plane toward the wall. `illuminated` adds one temporary,
shadowless `env_projectedtexture` at the lamp, genuinely lighting the panel and
nearby world. Removing/replacing the sign or expiry removes its light as well.
It is a preview aid; the static prefab's baked `light_spot` remains the normal
map-authoring path.
`print` and `poster` use the same wall-targeting path as `wall`, with their
centre/back-plane origin on the hit surface. Aim the **weapon crosshair**, not
just the orbit camera.

The focused regression checks packaged model/texture outputs, compiled bounds,
upright front UVs, appropriate collision compilation, invalid-image rejection,
and all four tile-instance rotations through the real skybox detail builder.
All six generated models are checked for packaging, bounds, collision presence/parts and
independent structural texture settings. Image-compositing tests cover cover/
contain aspect ratios, edge coverage and transparent foreground flattening.
For an end-to-end JSON override test using the supplied image:

```powershell
.\bin\test_sign_assets.ps1 -TestImagePath .\assets\signs\cs80.jpg
```

This optional mode builds all six models with temporary JSON leg/rim overrides.
It deliberately updates the prototype outputs; afterwards rebuild from your
intended JSON/image settings to restore the desired finish.
It does not establish engine collision, compiled-tile placement, skyline
readability or actual skybox rendering.

The user approved the live upright, readable, correctly lit prototype on
2026-10-05, then approved the mounted-metal/self-lit image and confirmed the
lamp casts real light. The lamp housing was subsequently slimmed in response to
the circled screenshot and explicitly approved. The user also approved the
legless panel and flush, outward-facing small wall sign.
The subsequent detailed billboard, thin framed print and borderless poster
were also explicitly approved in the running client. Compiled-tile collision,
baked spotlight lighting and an actual neighbouring-cell skybox view
remain to be checked in the integrated preview. No city recipe was changed by
the prototype.

Implementation references: the existing skybox builder documents the installed
compiler's SMD axis conversion. Compiled bounds checks use the public Source SDK
2013 [studio header layout](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/studio.h)
(file SHA `9480d15d95a73f2214dd9fd619aa5ae922f81b3c`), checked against the
installed GMod compiler's output; SDK layout is reference evidence, not a claim
that the two engine branches are identical.

Self-illumination uses the documented
[VertexLitGeneric shader parameters](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/materialsystem/stdshaders/vertexlitgeneric_dx9.cpp).
The preview light keyvalues were checked against
[env_projectedtexture.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/game/server/env_projectedtexture.cpp)
and exercised in GMod. Notably, static `light_spot` uses **negative** down-pitch
in VRAD's
[SetupLightNormalFromProps](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/public/map_utils.cpp),
whereas runtime Source `Angle` uses **positive** down-pitch. The prefab therefore
has pitch -60; the preview light has pitch +60. The SDK is a related branch,
not proof of the exact installed compiler; baked light still needs an actual
VRAD/live fixture check. The live VDC pages returned an access challenge.

## Later: generic world-detail sign library

The user requested a future collection of original, standard signs built on
this pipeline: health/medical logos, directions and arrows, building/place names,
and other generic world-detail graphics. Preserve editable/licensed source art
and make designs reusable by tile artists. This is a recorded follow-up, not
authorization to bulk-generate artwork or rewrite the current sign family.
Before implementing it, add independent output naming/design selection so many
signs coexist instead of repeatedly overwriting the six prototype paths.
