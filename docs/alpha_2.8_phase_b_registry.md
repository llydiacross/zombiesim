# Alpha 2.8 Phase B Registry

## Purpose

This registry records the first implemented CSS-inspired weapon batch. CSS provides model and balance references only; every runtime weapon is a local ZombieSim SWEP built on the ZombieSim hitscan base.

The item definitions in [content/data_static/item_definitions.json](../content/data_static/item_definitions.json) are authoritative for the mappings below. Phase C implements each `ammoId` as a stackable backpack item and persists loaded rounds on the weapon instance.

## First Batch Registry

| itemId | cssFamily | localWeaponClass | viewModel | worldModel | ammoId | firingMode | rarity | levelBand | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| weaponUsp9mm | usp | weapon_zn_usp_9mm | models/weapons/cstrike/c_pist_usp.mdl | models/weapons/w_pist_usp.mdl | ammo9mm | semi_auto | common | 1-12 | implemented; representative live test passed |
| weaponAutoPistol9mm | glock18 | weapon_zn_auto_pistol_9mm | models/weapons/cstrike/c_pist_glock18.mdl | models/weapons/w_pist_glock18.mdl | ammo9mm | automatic | rare | 15-30 | implemented; automatic cadence probe passed |
| weaponMp5 | mp5 | weapon_zn_mp5 | models/weapons/cstrike/c_smg_mp5.mdl | models/weapons/w_smg_mp5.mdl | ammo9mm | automatic | uncommon | 5-18 | implemented; catalog validation passed |
| weaponM4a1 | m4a1 | weapon_zn_m4a1 | models/weapons/cstrike/c_rif_m4a1.mdl | models/weapons/w_rif_m4a1.mdl | ammo556 | automatic | uncommon | 8-24 | implemented; catalog validation passed |
| weaponAk47 | ak47 | weapon_zn_ak47 | models/weapons/cstrike/c_rif_ak47.mdl | models/weapons/w_rif_ak47.mdl | ammo762 | automatic | uncommon | 8-24 | implemented; catalog validation passed |
| weaponShotgunM3 | m3 | weapon_zn_shotgun_m3 | models/weapons/cstrike/c_shot_m3super90.mdl | models/weapons/w_shot_m3super90.mdl | ammoShells | semi_auto | common | 4-16 | implemented; catalog validation passed |
| weaponScout | scout | weapon_zn_scout | models/weapons/cstrike/c_snip_scout.mdl | models/weapons/w_snip_scout.mdl | ammo762 | semi_auto | rare | 10-28 | implemented; catalog validation passed |
| weaponAwp | awp | weapon_zn_awp | models/weapons/cstrike/c_snip_awp.mdl | models/weapons/w_snip_awp.mdl | ammo50Bmg | semi_auto | very_rare | 18-35 | implemented; catalog validation passed |

## Implementation and Validation

- Each item resolves to an explicit local `weapon_zn_*` class; no stock CSS SWEP class is used.
- All eight local classes inherit `weapon_zn_base_hitscan`. The M3 uses a multi-pellet bullet count, and the Glock-style pistol has a separate automatic implementation.
- The new weapon items are included in weapon-category loot groups while preserving the pre-existing generic handgun/melee ordering.
- Offline GLua parsing and JSON parsing passed. The inventory regression suite passed 28 cases; after preserving the previous generic-loot ordering, the static-data suite passed 11 cases.
- `zn_test_weapon_catalog` checks item-to-class/model/ammo/mode mappings, SWEP registration, automatic flags, and mounted model validity.
- After reloading the preview map against the current source, `zn_test_weapon_catalog` passed all eight mappings and confirmed the model paths are mounted.

## Phase B Gate

Phase B's implementation gate is **complete**. A USP was granted and equipped from an item instance, began empty, consumed backpack 9mm during reload, fired in the live client, synchronized its deferred clip at a map boundary, and restored without recreating rounds. The local automatic 9mm pistol also consumed exactly one round and set its scaled 0.117-second cadence in the runtime probe. Per-weapon visual/feel acceptance (animation, sound, top-down aim, impact, and damage tuning) remains a deliberate gameplay review rather than an implementation blocker.
