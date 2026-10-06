# Clothing finish prototype

This is the Alpha 3.1.0 Phase F clothing workflow. All fifteen group01 citizens
(`male_01`-`male_09`, `female_01`-`female_06`) now have independently measured
garment transfers and explicit human visual approval. Rebels are deliberately
excluded from catalogue clothing and retain their mounted native bloody
appearance. Full Phase F performance/lifecycle acceptance remains separate.

## Citizen catalogue outfits

Each citizen walker selects a shirt and pants independently from the entire
eligible catalogue, including artist prints and original fabrics. The current
catalogue contains 866 finishes; this is not a sixteen-outfit shortlist.
An individual spawn keeps a unique random seed, and Walker ticket identities
keep repeated materialization stable for the same model/profile/cell/revision.
Refreshing blood does not reroll an outfit. Corpse packets and queued/live
severed pieces retain their original selection. These are networked cosmetics,
not wearable grants or saved player appearance changes.

The user approved **96 shared outfit render targets**, replacing the original
sixteen-slot budget. Targets are created on demand and remain engine-resident
for the map/session: up to approximately **384 MiB of RGBA colour storage**,
plus source textures, materials and the legacy prototype targets. Identical
outfits share composites; live players, UI models, corpses and pending/live
limb copies pin their slots. At full capacity, new distinct outfits explicitly
stay native and retry after references release; pinned appearances are never
overwritten. The catalogue still has its independent 896-finish cap.

`textureCapacity` in [catalogue.json](../assets/clothing/catalogue.json) must
match `ZM_Clothing.TextureCapacity`. Refresh only generated pool patches and
ownership metadata without rebuilding or changing garment textures/identities:

```powershell
.\bin\build_clothing_catalogue.ps1 -PoolOnly
.\bin\test_clothing_catalogue.ps1 -ValidateBuilt -PreviousCatalogue '.\generated\clothing_preview\catalogue\pool_previous_catalogue.json'
```

The generator emits 192 tiny native-inheriting VMT patches for 96 targets.
Published ownership is now 3642 files; all 866 finish definitions, item IDs,
icons and existing source textures are retained. Pool-only publication verifies
the existing two catalogue copies, validates ownership and hash-checks all
staged payloads before publishing. It does not prune unowned assets.

Citizen transfers reuse the original 1024-square catalogue and blood layers,
not new textures per model/finish. Engine mesh inspection confirmed alternate
shirt atlases on several citizens; robust upright affine fitting and
per-triangle clipping preserve unmatched native neckline charts. The generated
transfer manifest is approximately 5.3 MB. Rebuild it through the owners:

```powershell
.\bin\inspect_clothing_citizen_calibration.ps1
.\bin\test_clothing_citizen_calibration.ps1
.\bin\build_clothing_citizen_calibration.ps1 -StagePreview
```

The default manifest is preview-only. `-EnableRuntime` is an explicit rollout
gate, already approved for these fifteen measured models; never apply it to
rebels or an unreviewed model set. Wardrobe's citizen dropdown remains window-only.

Normal entity composition uses a **2 ms soft per-frame work budget**. One cold
build can exceed that budget, but another is not batched behind it. The actual
pool suite also advances capacity and citizen fixtures one step per frame,
rather than creating 96 targets and thousands of atlas draw calls in one
frame. Its JSON first reports `running: true`, then the final pass/fail summary;
bridge dispatch alone is not completion.

For harmless preview-admin crowd checks, `zn_gore_probe crowd` uses all fifteen
models; `zn_gore_probe crowd male_03` repeats one model with independently
selected outfits. Append `native` for a matched native-clothing control.
Probes do not attack, reward kills, or acquire Walker tickets; they expire after
120 seconds. Use `zn_gore_probe off` for owned cleanup. Profile without taking
a screenshot during the measurement. Earlier cold builds measured 21-36 ms
and the background client ran near 20 FPS; neither is 60-FPS acceptance.

## Editable source

[prototype.json](../assets/clothing/prototype.json) describes independent outer-shirt, inner-shirt and pants artwork:

- `regions`: `[x, y, width, height]` rectangles on the 1024-square UV sheet. The origin is the top-left. Pixels outside the mask remain transparent.
- `color`, `stripeColor`, `stripeSpacing`, `stripeWidth`: procedural fabric colours and horizontal texture-space stripes.
- `pattern`: `solid`, `stripes` or `checker`. Checker squares alternate `color`/`stripeColor` in both axes; `stripeSpacing` sets the square size and `stripeWidth` applies only to stripes. The current shirt preview uses repeating checks. UV seams still need mesh-specific review.
- `image`: optional original/licensed **1024x1024** image relative to `assets/clothing`. It is layered over the fabric without resizing, then clipped to the garment mask.
- `logo`: optional original/licensed image, or text, positioned in UV coordinates. An image takes precedence over text and is fitted to the explicitly configured rectangle.
- `shirt.innerShirt`: `mode` is `native` (default, retain the mounted inner shirt), `color` (use its independent colour) or `image` (use a 1024-square UV-aligned image over that colour). Per-model-family UV `polygons` exclude this region from outer fabric, stripes, logos and prints. The jacket and inner shirt remain one SHIRT item, not separate equipment slots.

The male and female neckline charts differ. The inspector writes diagnostic `.neckline.json` and `.sleeves.json` triangle/UV landmark reports beside the guides. These are calibration evidence, not a universal automatic garment classifier. Prototype support remains limited to the two inspected models.

Use the generated `uv_male_03.png` and `uv_female_01.png` wireframe guides under `generated/clothing_preview` and numbered in-game calibration fixtures before editing masks or logo placement. The user approved the initial torso/sleeve/pants mask and repeated-image prototype direction for equipment integration; this does not approve new meshes or every future artwork seam. Hands and footwear use other chart regions and must remain transparent. A straight texture-space stripe need not stay straight across the model's UV seams.

```powershell
.\bin\inspect_clothing_models.ps1 -UvGuideModels @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')
.\bin\build_clothing_prototype.ps1
.\bin\test_clothing_prototype.ps1
```

The complete builder creates three base layers (model-family-specific shirts and shared pants), sixteen shirt-print layers, four left/right thigh layers, four left/right cuff-up layers, eight rear-limb layers, three repeated-image layers, one flat back-print icon and twelve native material patches under `generated/clothing_preview/prototype`, then hash-checks 90 scoped VTF/VMT files in each staging destination (addon content and the installed game root). Six patches belong to diagnostic fixtures and six to equipment, so changing a zoo style cannot overwrite an equipped survivor's texture. Do not edit generated outputs. No model or BSP compile is involved.

## Image-placement presets

[prints.json](../assets/clothing/prints.json) uses the supplied `deer.png` for eight reusable shirt styles. Left/right mean **the wearer's** left/right, not the camera's:

| Style | Intended placement |
| --- | --- |
| `chest` | Centred upper-middle torso logo; 120x90 canvas at UV Y=772, smaller than `front_full` |
| `chest_left` | Small left-chest badge |
| `chest_right` | Small right-chest badge |
| `arm_left` | Outer left upper sleeve |
| `arm_right` | Outer right upper sleeve |
| `back_small` | Small upper-back/shoulder-blade print |
| `front_full` | Large centre-front torso print |
| `back_full` | Large centre-back torso print |

Each style has a logical print canvas `size` and model-family-specific `uv`/`source` pieces. Artwork is fitted into the canvas with its aspect ratio preserved, centred and transparent around the image; it is not stretched to fill the rectangle. `back_full` now projects that fitted canvas through the inspected torso triangles into both back UV islands, across a 16-unit-wide / 20-unit-high model-space area from height 60 down to 40. Its old rectangular pieces are diagnostic reference only, not the rendering mapping. The small-back badge stays within one island. Outer-shirt clipping remains in effect for every print, including the inner-shirt exclusion. The corrected back needs fresh visual acceptance on both supported meshes; this is not a guarantee of seamless fit on uninspected models.

For focused placement iteration, `.\bin\build_clothing_prototype.ps1 -PrintStyles @('back_small')` rebuilds the base garments, selected model-family print variants and material patches only. Run a complete build before a clean-artifact acceptance check; a focused build deliberately does not refresh other print presets.

Replace `image` with another original/licensed file under `assets/clothing`, then rebuild. Adjust `size` and the calibrated pieces for different print sizes/positions. These are UV-placement presets, not automatic model-unwrapping or guarantees of seamless fit on unverified meshes. The deer file is user-supplied development artwork; release/redistribution rights remain to be confirmed.

## Live preview

After confirming the active preview profile/map, reload that same map to load changed Lua and invalidate engine-cached materials. Do not rely on Lua autorefresh or send `lua_*` through the bridge.

```powershell
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_uv on female both'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_capture clothing_front front'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_capture clothing_back back'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_uv on female both chest_left'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_capture deer_chest neckline'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_uv on male both back_full'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_clothing_capture deer_back back'
```

Replace `female` with `male` for `male_03`. Replace `both` with `shirt` or `pants` to check that the other garment stays native. The optional fourth argument selects a print style (`base` restores the original ZM text prototype); print styles require `shirt` or `both`. The first fixture is stock; the second has the selected finish. Capture angles are `front`, `back`, `left`, `right` and a close-up `neckline`. The capture command orbits only the development camera. It does not teleport the player, change appearance, write inventory, or alter persisted data.

Captures and rendering metadata are written asynchronously under Garry's Mod `DATA` at `data/zombiesim/screenshots`. Inspect front, back, both sides, neck, cuffs, waist, hem and shoes; check text orientation and any visible seams. Bridge acknowledgement alone does not establish rendering or image creation.

Fixtures are non-solid, owned by the player and expire after 300 seconds. Remove them with `zombiesim_dev_clothing_uv off`. Failed placement leaves the existing pair in place.

## Runtime composition and provenance

The client makes a bounded, lazy 1024-square runtime composite for each selected model family/garment combination: no more than six render targets, approximately 24 MiB of RGBA colour storage. Switching print styles rebuilds the existing target rather than allocating a target for every print. Mounted/native and original VTF textures have their own engine-managed storage in addition to those targets. This diagnostic supports one current style per model-family/garment combination, not simultaneous differently styled fixtures sharing that combination. Builds occur only on first request or a style change, not every frame. Capture metadata reports build time, style, native shader/normal reference, dimensions and applied material.

The mounted body texture is read in memory, never exported as addon artwork. Transparent garment pixels retain its RGB and tint-mask alpha. Opaque original artwork replaces RGB and clears only that garment's alpha tint mask, following the user's decision to retain artist colours independently of character tint. Unchanged clothing retains native tint. The final material uses `Patch` inheritance to keep native normal/phong/rim references and the complete proxy chain; no Valve shader definition or artwork is copied into distributable content.

`Entity:GetSubMaterial` prioritises server values even when a client-side override renders. Diagnostics therefore distinguish `appliedMaterial` from `serverReportedOverride`; an empty server value is not proof that the displayed finish failed. Cleanup returns these diagnostic fixtures to the owning server's appearance.

References:

- [VDC Patch](https://developer.valvesoftware.com/wiki/Patch); live page was blocked, so the [2025-02-07 archived documentation](https://web.archive.org/web/20250207122905/https://developer.valvesoftware.com/wiki/Patch) was consulted for include/replace semantics. Actual GMod texture/shader resolution is checked before applying a finish.
- [CreateMaterial](https://wiki.facepunch.com/gmod/Global.CreateMaterial): Lua tables cannot preserve repeated instances of one proxy type. Patch inheritance avoids that limitation.
- [render.OverrideBlend](https://wiki.facepunch.com/gmod/render.OverrideBlend), [render.OverrideAlphaWriteEnable](https://wiki.facepunch.com/gmod/render.OverrideAlphaWriteEnable), [Entity:GetSubMaterial](https://wiki.facepunch.com/gmod/Entity:GetSubMaterial), [Entity:SetSubMaterial](https://wiki.facepunch.com/gmod/Entity:SetSubMaterial).

## Remaining acceptance

Visual approval of this prototype does not accept Phase F. The fixed-finish equipment section below records implemented SHIRT/PANTS items, server-authoritative equip/unequip, atomic persistence, appearance loading, UI previews, corpse propagation and supported-model validation. The automatic catalogue, bloody/walker compatibility and representative performance acceptance remain separate unfinished work. Existing armour and weapon slots remain untouched.

The user has also specified the later automatic catalogue: every eligible image directly in `assets/clothing` should generate filename-based shirt and pants families (for example `deer_tshirt` and `deer_pants`), with both placed-image and repeating-fabric outcomes for every image, not a suffix that forces one interpretation. Generate original bloody counterparts as well. This catalogue and the bloody overlays are **not implemented by the current seven-print fixture prototype**. Define deterministic IDs, eligible artwork versus diagnostic inputs, bounded output combinations, registry/equipment ownership, regeneration/pruning and rights checks before rollout. Zombie use requires inspecting the actual walker model/material UVs and preserving the existing gore/blood lifecycle; group01 survivor verification does not establish group03 walker compatibility.

The catalogue must also support an optional recognised trailing background colour: `deer_black.png` fixes the garment background to black; `deer.png` produces a small curated colour selection. The artwork family and colour constraint are separate, so they must not collide with another family's generated IDs. Publish supported colour tokens and handling for unrecognised suffixes rather than guessing arbitrary words. Procedural fabric choices must include deterministic stripes, checks and tie-dye with artist-editable palettes; pants should remain predominantly solid/subdued with restrained optional creative variants. These catalogue refinements are recorded requirements, not implemented behavior of the current `prints.json` builder.

### Filename placement and image repetition contract

Artists may also specify optional placement tokens for front, back, either arm or pants, combined with a background colour. The filename parser is still pending; examples of the intended naming convention are `deer_front.png`, `deer_back_black.png`, `deer_arm_left.png`, `deer_arm_right_black.png` and `deer_pants_black.png`. Parse recognised suffix tokens separately from the remaining artwork name, including multiword placements such as `arm_left`; preserve unrecognised words as artwork identity and detect ambiguous/colliding output names explicitly. Names without placement tags retain the curated placement variants.

The user clarified that "checkered" means **the supplied image repeats across both X and Y**, not merely alternating procedural colour squares. A deer repeat should contain many deer motifs tiled across the garment, with aspect ratio/transparency retained, editable tile scale and spacing, and clipping that preserves skin, shoes and the independently controlled inner shirt. Procedural coloured checks remain an optional fabric treatment, not proof that repeating-image generation is implemented.

The user explicitly chose that placement tags restrict **only the single graphic**. The repeating-image counterpart still covers the whole applicable garment: an arm-tagged graphic appears on that arm, while its repeating counterpart tiles across the shirt; a pants-tagged family repeats across pants, not onto the shirt. Colour restrictions apply to both counterparts. Generated items remain cosmetic; this filename contract does not change equipment slots.

### Implemented repeated-image preview

`prints.json` now contains independent `repeat.shirt` and `repeat.pants` settings:
`motifSize`, `spacing` and `offset` are two-element pixel coordinates. Motifs fit
inside the specified size without stretching; their original transparent pixels
show the fabric beneath. Size must be 8-1024 pixels, spacing 0-1024, and each
non-negative offset must be smaller than the corresponding size-plus-spacing
period. The motif is fitted once and copied at integer positions, avoiding small
resampling differences between repetitions.

Use `.\bin\build_clothing_prototype.ps1 -PrintStyles repeat` for the three base
layers, three repeated-image layers and twelve native patches. A complete build
now generates twenty-two layers and twelve patches, staging 56 scoped VTF/VMT files,
including the two model-specific single-leg pants layers described below.
`.\bin\test_clothing_prototype.ps1` checks both-axis coverage, exact combined
fabric/motif periods, transparent mask exclusions, inter-motif spacing, VTF
dimensions/alpha and staging hashes, alongside the existing seven single prints.

After a confirmed preview reload, select `repeat` with any finish:

```text
zombiesim_dev_clothing_uv on male shirt repeat
zombiesim_dev_clothing_uv on female pants repeat
zombiesim_dev_clothing_uv on female both repeat
```

Shirt repeats cover torso and sleeves while retaining the independent inner
shirt. Pants repeats cover the pants mask only. The existing six runtime targets
are reused; choosing this style does not allocate additional per-style targets.
This implements actual image repetition for the prototype, **not** automatic
filename discovery, clothing items, tie-dye or bloody/zombie catalogue wiring.
Male/female live captures show many deer motifs; final seam/style approval
was approved by the user for proceeding into equipment integration. Phase F is
not accepted solely on this prototype approval.

## Fixed-finish equipment

The two initial cosmetic items are `itemPrototypeShirt` (Teal Check Shirt) and
`itemPrototypePants` (Olive Stripe Pants). Both select the original base artwork
from `prototype.json`, not the user-supplied deer print. Rebuilding that editable
source and reloading the confirmed preview changes their visible finish.

The server validates `{ garment, finish }` on clothing definitions. Garments
occupy SHIRT slot 5 and PANTS slot 6; weapons 1-3 and ARMOR slot 4 are unchanged.
The registered `prototype` finish is currently the only wearable finish.
Arbitrary client image paths and per-instance material names are not accepted.
Items remain cosmetic and confer no protection or combat statistics.

Inventory drag/drop, double-click and context actions equip or unequip the
appropriate garment. Replacement returns the old garment to the incoming
garment's backpack slot. Selection is published only after persistence succeeds.
Existing profile/character-scoped item rows store the item ID and equipped slot;
no new per-instance schema is needed. Equipped clothes retain the existing
equipped-item death-loss policy. Unequipping one garment restores only that
garment's native appearance/tint and retains the other garment.

The compositor reuses six lazily built equipment textures, separate from the six
diagnostic textures (up to 24 MiB each group, excluding source textures). It
retains native shader/proxies/normals and artist colour on opaque artwork.
Scoreboard previews use the same finish selection. The server stores a single
clothing-selection packet on the death ragdoll before backpack loss; the client
waits for that packet and scans the verified client class `class C_HL2MPRagdoll` independently of whether
the source player is still present. This prevents later re-equips or delayed
visibility changing corpse appearance. Actual corpse/preview rendering is now
live-verified. The server class `hl2mp_ragdoll` does not select these client
entities; the exact client name came from an in-engine probe, not an assumed
Source SDK/GMod equivalence. See the documented [player ragdoll class](https://wiki.facepunch.com/gmod/Player:GetRagdollEntity)
and [creation behavior](https://wiki.facepunch.com/gmod/Player:CreateRagdoll);
the installed base gamemode's `DoPlayerDeath` creates the normal death ragdoll.
Existing severed-limb code copies source submaterials; group03 zombie catalogue
compatibility is still separate pending work.

Preview admin commands use the existing inventory owner:

```text
zn_give_item itemPrototypeShirt
zn_give_item itemPrototypePants
zn_equip_item itemPrototypeShirt
zn_equip_item itemPrototypePants
zn_inventory
```

`zn_inventory` reports model compatibility and current clothing selections.
Captured screenshot JSON includes `equippedClothing` diagnostics. Unsupported
models may own/equip these cosmetics but remain visually native, as the tooltip
states. Do not expand the supported list without mesh/mask verification.

Current verification: garment/patch regressions 234/234, GLua 171 files with no
failures, in-engine static-data suite 18/18 and inventory suite 51/51. The
inventory suite includes an immutable death-snapshot case without killing a
real player. A supported male survivor was temporarily equipped, reloaded and
independently restored to native clothing; the exact original inventory was
verified after removing only the two test items. The user confirmed the real
six-slot Inventory layout and clothing controls. Final-VGUI screenshots now show
the actual Inventory and male/female dressed scoreboard previews, rather than
inferring visual success from valid-window flags. Ordinary UI captures use
[PostRenderVGUI](https://wiki.facepunch.com/gmod/GM:PostRenderVGUI); explicit
world-camera captures retain their original path and the queue captures at most
once per frame. Two queued Inventory captures used consecutive distinct frames.

A temporary, non-persisted female model demonstrated both garments, pants-only
with native shirt, and fully native restoration. An unsupported male_01 retained
native clothing with both cosmetics still equipped. The original male_03 model,
skin/bodygroups and equipped weapons/armour were restored and verified.

The user explicitly authorized real death tests on the development survivor.
The first death lost the original 17 backpack stacks under the existing policy;
these have not been restored. Equipped weapons/armour remained unchanged. The
actual corpse rendered the teal shirt/olive pants, and a further actual death
retained that finish after both garments were moved out of equipment: the
player selection was empty while the corpse's immutable packet and pixels
remained dressed. All three temporary garment pairs are removed; the survivor
is alive, native and on the original preview map.

Single-survivor five-second profiles measured the clothing scan at 0.0098 ms/frame
native and 0.0170 ms/frame equipped (max 0.150/0.140 ms; about 0.028/0.044 KiB
positive allocation per frame). Both runs were approximately 20 FPS, so these
are focused cost observations, not 60-FPS or crowd/performance acceptance.
Additional wearable finishes now use the user-approved bounded 96-slot outfit pool, with
reference checks for players, UI models, corpses and queued/live gore copies.
Its actual capacity/reuse/recovery regression passes; broader performance acceptance remains pending. The six legacy
equipment textures remain only for the fixed-finish fallback.

## Single-image pants placement prototype

The user selected a large graphic down one leg rather than a small thigh or
back-pocket badge. `prints.json` now has `pantsLeg` with an 88x312 artist canvas
and independent male/female placements on the front of the wearer's left leg.
The mounted-model inspector exports leg-height triangle landmarks; the
inspection suite verifies populated front thigh/calf geometry and that this
canvas does not reach the other anatomical leg (112/112 checks overall).

Build just this prototype with `.\bin\build_clothing_prototype.ps1 -PrintStyles pants_leg`.
After a confirmed preview reload:

```text
zombiesim_dev_clothing_uv on male pants pants_leg
zombiesim_dev_clothing_uv on female pants pants_leg
```

`both` retains the base shirt; `shirt` alone rejects this pants-only style.
The same six diagnostic targets are reused, with native shader/skin/shoes and
equipment targets untouched. Complete artwork regressions now pass 234/234.
Male/female live captures show the image on only the selected leg and the
unchanged native shirt/footwear.

The user selected whole-image fitting without cropping or stretching. A tall
source can use the full thigh-to-calf canvas; a wider image such as the deer is
centered and occupies only part of its height. Do not stretch or center-crop
wide artwork to force it down the whole leg. The user subsequently approved this
single-image placement as the catalogue template. This does not accept all of Phase F.

## Filename-driven catalogue

Implemented placement extension: separate left/right cuff-anchored leg artwork
(flames rising from the trouser opening toward the thigh). Rear-facing leg/arm
variants remain queued and need independent UV calibration.
The current centred/aspect-preserving placement remains the default; this
request does not authorize globally stretching or cropping artwork.

Put eligible PNGs directly in `assets/clothing`. Run
`.\bin\build_clothing_catalogue.ps1 -PlanOnly` to inspect the generated plan without
staging, or `.\bin\build_clothing_catalogue.ps1` to generate and hash-check artwork,
wearable definitions and development game-root copies. Run
`.\bin\test_clothing_catalogue.ps1` for focused parser/planner regressions.
[catalogue.json](../assets/clothing/catalogue.json) owns palettes and output budgets.
Diagnostic `uv_probe.png` and filenames starting with `__` are excluded.

Optional underscore-separated suffixes can be combined in any order:

| Suffix | Meaning |
| --- | --- |
| `_chest`, `_front`, `_back`, `_arm_left`, `_arm_right` | Restrict single-image shirt placement; chest is a centred upper-chest logo, front is a large torso graphic |
| `_arm_back_left`, `_arm_back_right` | Restrict single-image shirt artwork to the rear of the named upper arm |
| `_pants_back_left`, `_pants_back_right` | Restrict single-image pants artwork to the rear of the named thigh |
| `_pants` | Generate pants only, with left/right thigh and left/right cuff-up prints |
| `_pants_cuff` | Restrict placed graphics to left, right and both-legs cuff-up prints |
| `_sleeve_cuff` (or `_sleeves`) | Restrict shirt artwork to left, right and both-arms sleeve prints rising from the hem, bottom-aligned like `_pants_cuff` |
| `_repeating` | Also generate the whole-garment X/Y repeat, even for placed artwork |
| `_notrepeating` | Never generate a repeat; untagged artwork keeps only its placed variants |
| `_black`, `_white`, or another configured colour | Fix the garment background colour |
| `_notblack`, `_notgrey`, or another `not<colour>` | Exclude that named background from single and repeated variants |
| `_dark` | The **artwork layer** is dark; use contrasting lighter backgrounds |
| `_light` | The **artwork layer** is light; use contrasting darker backgrounds |

Repeat rule: any placement suffix (`_chest`, `_front`, `_back`, arm, rear-limb, `_pants`, `_pants_cuff` or `_sleeve_cuff`) produces only placed images and no repeat. `_repeating` restores the repeat for placed artwork (for example `acidril_back_repeating.png`); `_notrepeating` removes it from untagged artwork. Using both is rejected. Rebuilding removes no-longer-listed staged `catalog_*` materials and unused `generated/clothing_preview/catalog_*` build caches (also pruned before building, keeping only previously published prefixes). Saved inventories keep removed item IDs flagged rather than deleted.

`_sleeve_cuff` uses [sleeve_cuffs.json](../assets/clothing/sleeve_cuffs.json): a 112x200 bottom-aligned canvas centred on the outer arm face and ending at the hem (male UV Y1012, female Y990), independently calibrated per arm and sex from `.arms.json` inspection landmarks. Art is fitted to the canvas width, so a tall portrait PNG (for example 600x1000) climbs most of the way up the sleeve; author flames with their base at the bottom of the PNG. `sleeve_cuff_both` and `pants_cuff_both` draw the same canvas on both limbs using the unchanged per-limb rectangles (Wardrobe labels `both sleeve hems` / `both cuff-up`).

An untagged image generates both garments from their original curated palettes.
The combined `front_back` variant was removed at the user's request. Separate
front-only, chest and back-only choices remain. Untagged artwork uses yellow,
blue, orange, red, teal, green and pink shirt backgrounds. Explicit colours
and `_light`/`_dark` rules retain their existing constraints; no artwork-tone
declaration is inferred from an untagged image. Pants keep their subdued palette.
Single-image pants now offer both `pants_leg` (wearer's left, existing stable
ID) and `pants_leg_right` (wearer's right). Both fit the entire artwork in
an 88x144 thigh canvas, raised from the previous 88x312 knee/calf-centred
canvas: male Y=40, female Y=20. Model-specific X positions come from inspected
front-thigh UV landmarks, not an assumed mirror offset. Wardrobe labels are
`left thigh` and `right thigh`. Separate `pants_cuff` and `pants_cuff_right`
choices use an 88x344 canvas with its bottom at UV Y384 on each model family.
[pants_cuffs.json](../assets/clothing/pants_cuffs.json) owns their independent
left/right UV rectangles and explicit `bottom` alignment. They preserve image
aspect and transparency, without cropping or stretching. Wide art stays short
at the opening; tall art extends toward the thigh. Author flames with their
base at the PNG's bottom; transparent padding at the bottom remains padding.
Existing thigh identities/presets and centred fitting remain unchanged.
The separate configuration avoids invalidating every existing print-layer
hash. Wardrobe labels are `left cuff-up` and `right cuff-up`.

Use `.\bin\build_clothing_prototype.ps1 -PrintStyles pants_cuff,pants_cuff_right`
and, after a confirmed preview reload,
`zombiesim_dev_clothing_uv on male pants pants_cuff` (or `female`,
`pants_cuff_right`). Exact fitted-pixel anchoring/aspect and inspected anatomical
UV coverage are automated checks; true hem appearance still requires human
review in a deployed survivor. The current plan is **660 image + 206 fabric =
866 finishes / 868 Wardrobe entries**, within the unchanged 896-finish cap and
sixteen-target pool.

### Artist-tagged rear limbs

Rear placements are explicit opt-in only: `deer_arm_back_left_white.png`,
`deer_arm_back_right_white.png`, `deer_pants_back_left_olive.png` or
`deer_pants_back_right_olive.png`. Tags compose with the existing colours,
exclusions and artwork tones. Left/right always mean the wearer's anatomical
side, not the camera's. Each family generates its one selected rear placement
plus the corresponding whole-garment repeat; it never silently replaces an
existing outer-arm or front-leg style. Ordinary images retain the 866-finish
plan and 896-finish cap.

[rear_limbs.json](../assets/clothing/rear_limbs.json) owns independently
inspected male/female rear charts: 48x144 rear thigh and 24x48 rear upper-arm
canvases. Both use centred, whole-image, aspect-preserving fitting; the image
top points physically up the limb. Their separate signature input leaves
existing print-layer hashes unchanged. No rear cuff-up placement is implied.

Build diagnostic layers with
`.\bin\build_clothing_prototype.ps1 -PrintStyles pants_back_left,pants_back_right,arm_back_left,arm_back_right`.
After a confirmed preview reload/deployment, use
`zombiesim_dev_clothing_uv on male pants pants_back_left` or
`zombiesim_dev_clothing_uv on female shirt arm_back_right`.
Fixtures are temporary and do not equip clothing. Rear-tagged source PNGs
appear as `left/right rear thigh` or `left/right rear arm` choices in Wardrobe
after the ordinary catalogue builder runs. No tagged PNGs currently exist,
so implementing these controls does not add wearable entries automatically.
Rear placement checks pass170/170, prototype pixels/staging370/370,
parser/planner/icons106/106, actual published catalogue7335/7335 and GLua175/0.
After a fresh preview-cell reload, the user approved all eight male/female
rear thigh/upper-arm placements using temporary deer-art fixtures. Fixtures
were removed afterward; live inventory/equipment remained untouched. This is
placement acceptance, not a glyph-by-glyph text test or all-animation review.

### Walker compatibility inspection

Run `.\bin\inspect_clothing_models.ps1 -ModelGroups group03` for a separate
read-only mounted-model report, then
`.\bin\test_clothing_walker_inspection.ps1` after the survivor inspection suite.
The fifteen group03 player bodies use **2048x2048** sheets with different
body-vertex counts and UV fingerprints from group01. This does not prove every
pixel is incompatible, but it rules out treating the survivor charts as
verified walker charts. No group03 runtime support or bloody catalogue is
enabled by inspection. Group03 male_03/female_01 now have separately named
2048-square guides and full physical/UV triangle exports:
`uv_group03_male_03.png` and `uv_group03_female_01.png`, with corresponding
`.bodytriangles.json`. These diagnostics do not approve garment masks.
The walker inspection suite passes56/56, including chart separation, all
finite/bounded body triangles, and rejection of wrong-group requests before
writes. Run chart-generating commands serially when checking output isolation;
the blood builder also refreshes the survivor inspection.

The current mounted search paths do not resolve `models/player/group02/male_01.mdl`;
group02 inspection fails explicitly rather than pretending it was verified.
Existing walker model selection is unchanged. Preserve the current
server-owned bloody overrides and client gore/corpse material-copy lifecycle
while separately designing original bloody layers and group03 calibration.

### Original shared bloody counterparts

The user selected shared overlays, not duplicate bloody item IDs or hundreds
of new full sheets. [blood.json](../assets/clothing/blood.json) owns the seed,
stain/droplet counts, colour and maximum opacity. All stain shapes are original
procedural artwork: irregular soft-edged patches with clustered droplets,
not copies of mounted Valve/GMod blood textures. Existing garment masks clip
the overlays; native inner shirts, skin and shoes remain excluded. Shirt
backs use the same inspected physical projection as the clean fabric.

Build offline with `.\bin\build_clothing_blood.ps1`, then run
`.\bin\test_clothing_blood.ps1`. Three shared1024-square DXT5 layers (male/female
shirt and common pants), six VTF/VMT files, cover all existing866finishes.
They stage to the existing content/installed-material locations and belong
to packaging's fixed-clothing group. They are not catalogue-owned files or
new wearable definitions, and do not change persistence or stats.
Blood checks32/32 include every pixel of all three masks, deterministic raw
pixels, bounded partial coverage, alpha/mips/compression, invalid settings,
and exact staging hashes.

The client compositor adds these overlays only over selected garments, keyed
separately from clean outfits within the shared 96-slot pool. Missing
overlays fail explicitly and can retry; no clean-looking success fallback is
used. Wardrobe has a window-only **BLOOD PREVIEW: OFF/ON** button, off whenever
the window opens. Native garment buttons still restore that garment; no
inventory, survivor appearance or gameplay blood state is changed.

The client pool suite includes blood/clean sharing, restoration, retry and
invalid-input cases. Live tests pass 9/9; the user approved blood toggling,
all fifteen citizen transfers, and actual citizen walker/corpse/detached-piece
appearance. Close dressed windows and remove crowd probes before the isolated
capacity case. Group03 walkers retain native mounted bloody overrides by
explicit user direction, not as a pending catalogue integration target.
Phase F is not accepted solely by these individual visual approvals.

Publication is complete:866finishes/3482ownedfiles; exact preservation and
built-output checks7319/7319, fabrics2754/2754, prototype306/306, topology134/134,
fitting25/25 and GLua175/0. Fresh live static18/18/distribution9/9/clientpool5/5.
The user approved male/female left/right cuff placement in the Wardrobe after
preview deployment. This accepts the cuff placement extension, not Phase F's
remaining rear-limb, bloody/walker, animation/gore or performance gates.
Untagged shirts include the chest preset alongside the existing left-chest,
front-full and back-full choices. `_front_full`/`_front-full` and `_back_full`
also alias `_front` and `_back`; `_CHEST` is accepted case-insensitively.
Every applicable family has single-image and X/Y repeating counterparts. Tags
are case-insensitive; spaces/hyphens normalize to underscores and `gray` aliases
`grey`, including exclusions. Tone is an artist declaration, not pixel analysis:
`_dark` does not request dark fabric.

For example, `boardsofcanada_dark.png` never generates black/charcoal backgrounds.
`boardsofcanada_dark_front_notgrey.png` generates white/tan front-shirt graphics
and their repeating counterparts. `deer_light_pants.png` uses charcoal/olive/navy
pants. `_notblack` alone excludes black specifically, not charcoal.

Tone-specific palettes remain curated and bounded. Their RGB values are checked
using linear-sRGB luminance against reference black (`dark`) or white (`light`),
with a configurable minimum ratio of 4.5. This selects background contrast; it
does not guarantee that every pixel of supplied artwork meets that ratio or
that in-game lighting cannot obscure it. Explicit colours still must meet the
tone rule: `deer_dark_black.png` and `deer_light_white.png` fail rather than silently
changing the artist's requested colour. Duplicate/conflicting tones, duplicate
exclusions, contradictory colours, and an exhausted palette also fail explicitly.
Unrecognized suffix words remain part of the artwork name.

The initial development catalogue build staged 40 finishes and 180 owned files;
the actual Boards of Canada family has 18 finishes and zero black backgrounds.
The generated catalogue and 16-slot reference-safe outfit pool still require
live integration/cache acceptance. These assets are not release-cleared; supplied
image redistribution rights remain unverified.

### Back-seam correction

The reported full-back fabric stripe and disorderly repeats came from treating
nonadjacent UV charts as one rectangular texture. The male centre seam joins
approximately X=4 and X=461; the female seam is curved and vertically offset.
`inspect_clothing_models.ps1` now writes `.torso.json` with actual triangle
positions/UVs. Builders refresh this inspection before producing clothing.
`clothing_back_projection.psm1` uses these triangles to sample a continuous
model-space back canvas for fabrics and an orderly X/Y tile for repeated motifs.
Both sides therefore sample the same artwork coordinates at the physical seam.
Two-texel edge bleed prevents filtering revealing bare cloth; interpolation
respects alpha, garment clipping and the native inner shirt.

Full-back Wardrobe swatches use a separate flat preview layer rather than
incorrectly stitching rectangular crops of the warped model texture. Icon
materials resolve on first visible paint, not eagerly for hundreds of entries.
Previously visited source textures may remain engine-cached; the 16-slot
runtime composite limit does not bound source-texture memory.

Run `.\bin\test_clothing_back_projection.ps1` after inspection to check actual
male/female seam pairs, motif phase, full-print coverage and clipping. Run the
prototype and fabric regressions after rebuilding; static continuity is not
human acceptance of the rendered model.

Parser/planner regressions pass 61/61, including tone/background compatibility,
suffix order, exclusions and single/repeat counterparts on both garments.
The catalogue was regenerated with tone metadata; all staged asset copies and
the two manifest copies matched. No in-game tone-variant visual check is claimed.

## Preview Wardrobe

Open **WARDROBE** from the Tab radial menu in an admin preview session, or run
`zombiesim_dev_wardrobe` in the client console. The development bridge accepts
`zombiesim_dev_ui wardrobe` and `zombiesim_dev_wardrobe` too.
The window is unavailable outside the preview profile and closes if its
preview/admin eligibility disappears.

The left-hand grid contains all registered shirt/pants items whose finish is
available, including the fixed prototypes. Search by artwork/colour/placement,
filter by garment, and click a tile to dress the model on the right.
Swatches sample the actual generated VTF layer, using the calibrated print canvas;
split-back UV pieces are stitched into one icon. Repeated prints show a garment
crop. These are print/fabric swatches, not full garment model renders; they add
no per-item render targets. Labels/tooltips retain the exact item's identity.

Choose the supported male/female model, use the rotation slider to inspect it,
or restore either garment independently with **NATIVE SHIRT/PANTS**. **NATIVE**
restores both. Selections affect only the window's client model, never the live
survivor, inventory, network equipment or saved appearance. Closing removes the
model and releases its outfit-pool reference through the normal transient-window
lifecycle. The Wardrobe does not initiate AFK protection; it only preserves an
already-active AFK menu session while open.

For repeatable window-only development checks:

```powershell
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_wardrobe select itemClothingDeerPantsOlivePantsLeg'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_wardrobe model female'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_capture wardrobe_review'
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_dev_wardrobe close'
```

An initial live capture exposed default white panels and a side-on camera.
Explicit dark panel painting, readable controls/status and a front-facing camera
correct those issues. The revised live capture shows the generated Boards of
Canada white front shirt and olive deer pants on the window model, with 40
registered entries, no icon failures and a successful composition. A subsequent
female capture verifies the same generated combination and unchanged live
survivor selections. Closing clears the window selections and returns
`cursorVisible=false`; reopening restores a native window model. After catalogue
integration, in-engine static data passes 18/18 and inventory passes 51/51.
Broader interactive filter/rotation/reset review remains separate from these
captured results.

The user subsequently approved the Wardrobe as excellent. This accepts its
presentation/direction, not every remaining Phase F clothing or gore requirement.

## Original fabric library

[fabrics.json](../assets/clothing/fabrics.json) retains the original ten named
finishes and expands them to **206 fabrics: 146 shirts and 60 pants**.
Fourteen colourways each offer plain, pinstripe, Breton/rugby stripes,
gingham/buffalo checks and spiral/ring/cloud/marble dye shirts; pants offer
plain, pinstripe, fine-weave and microcheck treatments with restrained accents.
The original ocean/sunset/forest dyes and subdued brown wash keep their IDs.
These do not
multiply every supplied image by every fabric. The combined catalogue retains
the global output budget; fabric settings have a separate bounded limit.

Each entry owns its stable `id`, garment, colour label, pattern, base/accent RGB,
stripe spacing/width and optional `tieDye` settings. Dye uses a deterministic
analytic field, not external artwork or runtime texture work:
`palette` has 2-5 colours, `center` is the UV origin of the spiral, `scale` is
32-512 pixels per radial cycle, `strength` blends against the base, and `seed`
sets the phase. Optional `style` selects `spiral` (default), `rings`, `cloud` or
`marble`. A compiled C# build-time renderer evaluates every texel on the
1024-square canvas, interpolates dye smoothly and adds fine original textile
grain; it no longer paints constant-colour 8x8 blocks. This improves detail
without enlarging the existing client render-target pool or running dye maths
in game. `expansion` owns the colour list and shirt/pants treatments; its
deterministic IDs do not depend on array order. The separate fabric limit is
216 and the combined image/fabric limit is 896, with at most 32 image inputs (raised to include the newly
supplied PNGs and colourful default shirts); exceeding either fails. Pink is a recognised
background token, including `_pink_chest`.
The tighter shirt defaults centre the spiral on the verified
front torso canvas. The user requested recognisable spiral/rings rather than
the first broad wash; the revised live model now shows that pattern.
Pants dye strength is limited to 0.2; the shipped brown wash stays within three
RGB levels of its base in sampled pixels. UV island seams still require visual
review, particularly when the front pattern meets sleeves or split-back islands.

Regenerate with `.\bin\build_clothing_catalogue.ps1`. Run
`.\bin\test_clothing_fabrics.ps1 -ValidateBuilt` after generation: it verifies
deterministic pixels, palette/seed controls, masks, native inner-shirt exclusions,
VTF dimensions/alpha, exact item routing and installed-copy hashes.
Earlier results were **141/141 fabric**, **74/74 filename/icon** and **234/234 prototype**
checks, with **48 generated finishes / 206 owned files** and 50 Wardrobe items.
The follow-up expansion passes **608/608 pure fabric**, **84/84 filename/icon**,
**38/38 back projection** and **248/248 rebuilt prototype** checks. The current
artist inputs plan 150 image finishes plus 206 fabrics (356 generated choices,
358 including prototypes), within the 384 combined limit. Full staging checks
and fresh model review remain separate.
Publication now stages **356 finishes / 1344 owned files**; built fabric checks
pass **2754/2754**, built image/icon/ownership checks **1901/1901**. The shared
loader's former 256 cap initially rejected the expansion; it now enforces the
same 384 finish/item cap while retaining sixteen composite targets. After a
fresh confirmed preview reload, static data passes **18/18**, inventory
**51/51**, and the actual sunset Wardrobe shows 358 entries, applied clothing,
no encountered icon failures and unchanged native live survivor selections.
Human review of the corrected dye/chest/back models is still required.
The subsequent enlarged/lowered chest and combined front/back update includes
the user's final 20 PNG families: **561 generated finishes / 563 Wardrobe
entries / 2166 owned files**. Built catalogue checks **3361/3361**, fabrics
**2754/2754**, prototype **264/264** (including artwork on both surfaces),
and fresh live static-data/inventory **18/18 / 51/51** pass.
The runtime and builder enforce matching 640-finish limits; the composite pool
remains sixteen. Human review of the revised chest/combined shirts is pending.
The user approved the enlarged chest, then requested raised back placement,
colourful defaults, removal of combined shirts, and raised left/right thigh
variants. These supersede the preceding combined-shirt totals: the current
source plans **584 image + 206 fabric = 790 finishes / 792 Wardrobe choices**.
The increase is **229 over the previous 561**, all from image placements/
backgrounds; the independent original fabric library remains 206.
Final staging and new back/thigh visual review remain pending.
Live ocean and revised sunset finishes render on the Wardrobe model. The user
approved the earlier spiral direction, then requested higher detail and more
choices and reported back-seam failures. Remaining Phase F lifecycle work and
overall phase acceptance are distinct.

## Outfit pool regression

Run `zombiesim_dev_test_clothing_pool` in a preview-admin client, or invoke it
through the development bridge. Close dressed windows and leave live clothing
native before the isolated full-capacity case. The suite runs in `PreRender`,
owns/removes all its invisible client fixtures and writes
`data/zombiesim/clothing_pool_tests.json`; bridge acknowledgement only dispatches
the asynchronous client run, so inspect that fresh result file.

The shared suite runner tests identical-outfit sharing, independent restoration,
male/female isolation, queued/live gore-reference pinning, sixteen simultaneous
outfits, native overflow, recovery after a pin releases, retry after a deliberately
failed composition and cleanup. **5/5 live-client cases pass**. The intentional
failure and capacity warning are expected test diagnostics, not new unhandled
Lua exceptions; they may trigger GMod's script-error notification.

Fresh client overrides can read back empty through `GetSubMaterial`. Clothing
now pins its own applied state immediately, supplies its effective owned
submaterial to gore capture, and retains the immutable copied material list on
live limbs. These tests exercise the actual compositor and reference collector;
they do not establish visual acceptance of a real sever animation.
Failed builds are no longer cached permanently.

A reversible generated-equipment test subsequently equipped the sunset fabric
shirt and olive single-leg deer pants on the supported survivor. The exact
instances, slots and published selections survived a same-preview-map reload;
original weapons/armour were preserved. The generated shirt and pants were
independently removed after scoped identity checks and the original four-item
inventory/model was reverified. The first pants-only dossier image exposed a
paint-time render-target clipping bug; scoreboard clothing now composes in
`PreRender`, not `DModelPanel.LayoutEntity`. A second pants-only real-item probe
showed the native shirt correctly and was also cleaned exactly. No survivor
was killed and no additional backpack loss occurred in these checks.
