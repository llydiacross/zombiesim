# Alpha 2.8 Phase B Registry

## Purpose

This registry is the first implementation checkpoint for the CSS-inspired weapon batch. It records the authoritative mapping from CSS art and balance references to the ZombieSim local weapon architecture.

The critical rule is: CSS classes are never used as the live runtime class. They are only a content and balance reference for a local SWEP implementation built on the ZombieSim weapon base.

## Live Mapping Rule

- CSS/Source weapon family: visual and balance reference only
- Local ZombieSim SWEP class: the real runtime class used by the game
- Item definition: stable game item id bound to the local SWEP class and ammo type

## First Batch Registry

| itemId | cssFamily | localWeaponBase | ammoId | firingMode | rarity | levelBand | implementationState |
| --- | --- | --- | --- | --- | --- | --- | --- |
| weaponCssUsp9mm | usp | weapon_zn_base_hitscan | ammo9mm | semi_auto | common | 1-12 | design_locked |
| weaponCssAutoPistol9mm | auto_pistol | weapon_zn_base_hitscan | ammo9mm | auto | rare | 15-30 | design_locked |
| weaponCssMp5 | mp5 | weapon_zn_base_hitscan | ammo9mm | auto | uncommon | 5-18 | design_locked |
| weaponCssM4a1 | m4a1 | weapon_zn_base_hitscan | ammo556 | auto | uncommon | 8-24 | design_locked |
| weaponCssAk47 | ak47 | weapon_zn_base_hitscan | ammo762 | auto | uncommon | 8-24 | design_locked |
| weaponCssShotgunM3 | m3 | weapon_zn_base_hitscan | ammoShells | semi_auto | common | 4-16 | design_locked |
| weaponCssScout | scout | weapon_zn_base_hitscan | ammo762 | semi_auto | rare | 10-28 | design_locked |
| weaponCssAwp | awp | weapon_zn_base_hitscan | ammo50Bmg | semi_auto | very_rare | 18-35 | design_locked |

## Required Validation Checklist

Before any item is bulk-added or enabled in gameplay, each row above must satisfy all of the following:

1. Local asset paths for the selected model/viewmodel and sounds are confirmed in the installed game content.
2. The item id is stable and matches the data registry.
3. The local SWEP base is the actual live class used by the item.
4. The ammo id is explicitly mapped and persists through save/load boundaries.
5. Firing mode behavior matches the selected weapon archetype and is server-authoritative.
6. Loot group and rarity assignment are deterministic and level-scoped.
7. Static validation is passing before the item is enabled in a live client test.

## Phase B Gate

Phase B is complete only when this registry is accepted, static validation passes, and at least one representative item from the batch is live-tested from spawn through equip, fire, reload, and persistence.

Until then, the batch remains a design-only registry and not an active gameplay implementation.
