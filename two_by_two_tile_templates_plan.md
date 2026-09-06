# Centered 2x Tile Templates: Implementation Plan

## Goal

Allow a tile template whose filename ends in `_2x.vmf` to occupy a 2-by-2 area of the existing 5-by-5 cell grid while producing one centered `func_instance` in the generated cell VMF.

Example: `buildings/tile_commercial_plaza_2x.vmf` occupies four normal tile spaces, not four instances.

`-v1` through `-v5` remain recipe-variation suffixes. The `2x` suffix is reserved exclusively for a template footprint.

## Placement Contract

- A normal template has footprint `1x1`, an integer `(tileX, tileY)` anchor, and one instance at that tile's center.
- A `_2x.vmf` template has footprint `2x2`; its anchor is the top-left grid coordinate of the occupied area.
- The source VMF's authored origin remains at its geometric center.
- The generator places the one instance at the geometric midpoint of its occupied 2x2 block.
- Do not alter source VMFs or model offsets to compensate for generator placement.

For a cell-grid center `C` and tile width `W`, a 2x anchor `(X, Y)` has origin:

```
originX = (X + 0.5 - C) * W
originY = (C - Y - 0.5) * W
```

This is the only builder-side coordinate change required for a centered 2x template.

## Data Model Changes

Extend each `tilePlacement` record with explicit footprint data:

```
tileX, tileY          # top-left anchor
footprintWidth         # 1 or 2
footprintHeight        # 1 or 2
template, rotationYaw, role
```

Default missing footprint values to `1`. This keeps existing plans readable during a controlled migration, though the planner should immediately emit the explicit fields for all new plans.

Add one planner helper:

```
Get-TemplateFootprint(templatePath) -> { width = 1|2; height = 1|2 }
```

Initially, detect `_2x.vmf` case-insensitively at the end of the basename. Do not infer size from other filename text. Future `3x` support can generalize this helper without changing placement consumers.

## Planner Changes

File: `bin/plan_cell_templates.ps1`

1. Keep the existing 5-by-5 `$placements` coordinate map as the occupancy source of truth.
2. Add a helper that tests whether all coordinates of a proposed footprint are in bounds and currently eligible terrain/building slots.
3. Add a helper that reserves every occupied coordinate, but emits one placement record anchored at the top-left coordinate.
4. Process transport reservations first, exactly as today. A 2x building or decoration must never replace a road, motorway, bridge, ramp, or other transport tile.
5. During building/decor placement, consider a 2x candidate only when all four spaces are available. Otherwise fall back to the current 1x1 selection logic.
6. Reserve the accepted 2x footprint before continuing the placement loop, so later buildings/decorations cannot overlap it.
7. Use the placement seed when choosing both the anchor and the 2x template, preserving deterministic output and meaningful `-vN` layouts.
8. Keep landmarks conservative initially: use 2x templates only when explicitly selected by the landmark policy. Do not let a generic 2x building replace an existing landmark selection.
9. Recipe identity already incorporates final `tilePlacements`; a 2x footprint will therefore naturally create a distinct recipe whenever its placement differs.

Recommended first scope: generic buildings and decorations only. Add 2x roads, bridges, ramps, and special transport pieces later as separate topology work.

## Builder Changes

File: `bin/build_cell_vmfs.ps1`

1. Read `footprintWidth` and `footprintHeight`, defaulting each to `1`.
2. Keep the current coordinate formula for 1x1 placements.
3. For a 2x footprint, add half of a tile width in X and subtract half of a tile width in Y from the anchored 1x1 origin formula.
4. Keep one emitted `func_instance` per placement record.
5. Replace the fixed validation of exactly 25 `func_instance`s with structural validation:
   - every placement emits one instance;
   - all occupied coordinates are in bounds;
   - no occupied coordinates overlap;
   - total covered grid area is 25.

The generated VMF will contain fewer than 25 instances whenever it uses one or more 2x templates. That is expected.

## Selection Rules

- A 2x candidate may only be anchored where `(X, Y)`, `(X+1, Y)`, `(X, Y+1)`, and `(X+1, Y+1)` fit within the 5-by-5 cell.
- Never place it over non-terrain, road, motorway, bridge, ramp, carpark, or landmark roles unless a later feature explicitly permits that role.
- Prefer anchors that have already been chosen for building density, then reserve their neighbouring eligible tile. This avoids making the map denser merely because a 2x template exists.
- If no valid 2x footprint exists, retain the existing 1x1 behavior.
- A 2x template should count as four covered tiles for occupancy but one placement for VMF output.

## Filename Discovery

No change is needed to the tile-template directory structure. `_2x.vmf` files will be found by the existing recursive template discovery.

The filtering policy must explicitly allow desired `_2x` families wherever it currently selects generic buildings, commercial assets, decorations, or landmarks. This prevents an incidental filename from becoming eligible simply because it exists.

## Validation Plan

1. Add one known 2x test template in a non-production test/dev template location.
2. Generate a small preview plan with a deterministic seed.
3. Assert that the plan contains one 2x placement record with a `2x2` footprint and no overlapping coordinates.
4. Build into `maps/src_preview`, never production `maps/src` during the first review.
5. Assert the recipe's instance count equals its placement-record count, not 25.
6. Open the generated recipe in Hammer and verify that the template is centered across exactly four tile spaces.
7. Regenerate using the same seed and compare plans to confirm byte-stable deterministic output.
8. Confirm that all roads, ramps, bridges, landmarks, and cell borders remain unchanged around the 2x placement.
9. Run the existing preview recipe audit and ensure every cell covers exactly 25 tile coordinates.

## Risks And Guardrails

- Rotation: a square 2x footprint remains 2x2 at every yaw. Rectangular future footprints will need width/height swapping at 90 and 270 degrees.
- Existing builder validation assumes 25 instances. It must be changed before any 2x template can be used.
- The planner must reserve all four coordinates atomically. Partial reservation would cause overlap and malformed recipes.
- Do not modify authored source template origins to solve placement. Correct the generated instance origin instead.
- Do not broaden this into variable-size map cells. `_2x` describes a footprint inside the existing 5-by-5 recipe grid only.

## Estimated Scope

The first 2x building/decor implementation is a contained planner-plus-builder change: approximately two new helpers, a placement-record extension, a reservation step, and replacement of the fixed 25-instance validator. It should be developed and reviewed entirely through the isolated preview pipeline before applying it to production generation.