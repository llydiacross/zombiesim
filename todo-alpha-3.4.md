# Alpha 3.4 - Continuation of Alpha 3.3

**Restructured (user, 2026-11-02):** the world viewer, new-tile wiring and
generation changes that were started as Alpha 3.4 now close Alpha 3.3 as its
[Phase J](todo-alpha.3.3.md). Alpha 3.4 continues the unfinished Alpha 3.3
work, led by the player structure system. Phase letters are kept from Alpha
3.3 so existing references remain valid. Compiling, staging, navmesh, Cell
Health and Satellite work still need separate approval.

Carried limits from Alpha 3.3 (not claimed): A2 multiplayer, normal-world
prefab scaling, real-cell gate set piece/prefab loot and guard runtime; Phase
B/C performance and multiplayer; D3 dancer head tracking; deferred
editable-prop ground shadows; Phase G weather/radiation/Low sampling and the
photosensitivity prompt.

## Phase E - Player structures and claims

**Design gate:** settle claim ownership scope, overlap/collision and shared
permissions, construction materials/recipes, recovery of existing contents on
expiry/reclaim/destruction, damage rules, door/key access, and how airtightness
and front doors are identified. Do not choose these silently or conflate a
wireframe preview with a completed structure.

**Decisions (user, 2026-11-02):**

- **Ownership:** a survivor owns each claim; that account's other survivors
  get friend-level access.
- **Sharing:** owners may add friends to a claim.
- **Claim tokens:** cost 25 survivor credits at den traders and can also be
  quest rewards (no quests are wired yet).
- **Expiry:** after 30 days without a visit, storage contents stay in their
  boxes, and anyone may salvage the structure and loot them.
- **Construction-mode protection:** zombie immunity reaches 640 units
  (one tile) beyond the claim.
- **Materials:** building uses existing scrap/wood/metal loot items.
- **Damage:** zombies and other players (PvP raiding) can damage structures.
- **First slices:** claim eligibility, token and claimed-tile boundary come
  first. Then a small visual prototype of 64-unit foundations and walls, kept
  for review before any catalogue.

**Token decisions (user, 2026-11-02):** the claim token is a tradable
backpack item; claims are unlimited per survivor, tokens being the only
limit; the 30-day expiry resets whenever the owner or a friend stands on or
near the claimed tiles.

Still open: PvP rules (when raiding is allowed, and offline protection), door
keys, airtightness and AI attack behavior.

**Claim eligibility source slice (2026-11-02, user-approved export):** the
runtime exporter now emits per-cell `claimTiles` (centred `[x, y]` offsets,
east +X/north +Y, range -2..2) from revision-2 layouts via
`bin/claim_tiles.psm1`. A tile qualifies only with exactly one 1x1 emitting,
self-owned placement of role `terrain`/`decoration` from `terrain/` or
`decorations/`; roads, borders, buildings, motorway-occupied and multi-tile
slots never qualify. A cell without the list has nothing claimable; empty
cells never carry it. `ZM_World` validates it at load and adds
`GetClaimTiles`, `IsClaimableTile` and `GetCoreTileAt`. A temporary v2
export gave 571 cells with claim tiles (5 empty), 5,094 tiles across 412
recipes. Fixtures: claim tiles 15/15, world Lua claim/empty 6/6, GLua 399/0.
The installed runtime JSON is unchanged; the data reaches the game only with
the next approved preview staging.

**Claim token and service source slice (2026-11-02):** `itemClaimToken`
(tradable backpack item, stack 10) is sold by the General Trader for 25
credits (stock 3-5). `gamemode/sv_claims.lua` (`ZM_ClaimService`) owns claims;
`utils/sql.lua` adds `player_claims` (profile, logical cell id, tile, owner
survivor, owner account, created/last-visit) and `claim_friends` (per owning
survivor, Steam accounts). Claiming removes one token through the inventory
transaction with the claim insert as an extra step, so a failed save keeps
the token and writes no claim. Claims require a loaded survivor in the loaded
city cell (not a den or safe-zone cell), an exported claimable tile and
standing within 1.5 tiles of its centre. An active claim blocks others; a
lapsed one (30 days since the last visit) is replaced. Visits by the owner,
the owner's other survivors or listed friends within 1.5 tiles refresh only
active claims (timer every 15 s, per-player throttle 60 s); a lapsed claim is
never revived. Commands `zn_claim_tile [x y]`, `zn_claim_status`,
`zn_claim_friend_add`/`_remove` act on the caller and are not admin-gated.
Offline fixtures (real `sql.lua` writers on SQLite) pass 8/8 plus world
claim tiles 4/4; GLua 401/0. The native `zn_test_claims` suite (throwaway
profile, temporarily faked world/safe-zone lookups) is written but not yet
run in game. No structure contents exist yet, so salvage/reclaim content
handling remains with the storage-box item below.

- [x] Establish authoritative eligibility for a 640-unit **core** tile:
      terrain/detail only, never road, border or a tile containing another
      building/object/claim. Check all sides, occupied multi-tile buildings and
      shared BSPs; if runtime metadata is inadequate, present the minimal
      data requirement rather than generating the world without permission.
- [x] Design claim token purchase and atomic consumption/claim creation.
      Scope state by world profile, logical cell and tile, not BSP name alone.
      Support adjacent expansion only with another token. Persist a 30-day
      last-visit expiry across restarts; settle server clock/visit semantics.
      Expired structures may be salvaged by others; a new token replaces the
      prior claim and starts a fresh period. Define safe content handling
      before reclaiming and test races/replays/failures.
      Source/offline only (see slice above); live `zn_test_claims` pending.
      Structure/box content handling on reclaim moves to the storage item.
- [ ] In construction mode show the claimed-tile boundary and keep placement
      within owned tiles. Implement the requested mutual zombie/player
      non-interaction only while the player is eligible and nearby; exiting
      the mode or going far away ends protection. Agree the distance and test
      death, disconnect, multiple players and transitions.
      **Hammer as building tool (user, 2026-11-02):** supersedes the separate
      $5000 Builder's Tool. The existing Hammer (`weaponMeleeHammer`, still
      loot-findable) is also sold by the General Trader at its normal derived
      cash price, stock 0-1. Reload toggles build mode; otherwise it fights
      normally. Build speed rises linearly from 1x at hammer level 8 to 2x at
      level 30; a mastercraft (including Ultra) halves each material cost,
      rounded up, minimum 1. Base build times foundation 6 s / wall 4 s are
      provisional.
      **Source slice (2026-11-02):** `gamemode/sh_construction.lua` holds the
      shared rules; `gamemode/sv_construction.lua` owns the server toggle.
      Build mode needs a living player within 640 units of an active claim
      tile they can access in the loaded city cell; it is re-checked each
      second and ends (with a message) on leaving, losing access, switching
      or holstering the hammer, death, respawn or disconnect. While on,
      walkers/bosses do not target or hear the builder, and damage between the
      builder and zombies or other players is blocked both ways (environmental
      damage is unaffected). Build-mode swings do nothing until pieces exist.
      `gamemode/cl_construction.lua` draws the claimed-tile boundary, a HUD
      (mode, selected piece, cost, build time, controls) and a green/red
      placement ghost from the shared `AimTrace`. Not live-tested.
      **Placement prototype (2026-11-02, source/offline only):** new entity
      `zn_construction_piece` (foundation 64x64x16, wall 64x8x128; yaw folded
      into axis-aligned bounds). Hammer LMB places a blueprint snapped to the
      64-unit grid (foundations to square centres, walls to edges by view
      yaw) on world or completed pieces only, wholly inside accessible claim
      tiles; duplicates per slot and more than 12 blueprints per player are
      refused. RMB removes your own unpaid blueprint, otherwise cycles piece.
      Holding E builds: the first contribution pays the whole cost in one
      atomic backpack mutation (foundation 4 Wood + 2 Scrap, wall 3 Wood + 1
      Scrap; halved by mastercraft); gaps over 0.25 s credit nothing;
      completion waits while a player/NPC/zombie is inside. Blueprints are
      non-colliding cyan wireframes; complete pieces fade in over 1 s using
      mounted `wood/woodfloor005a` / `wood/woodwall009a` referenced in place.
      Offline construction fixtures 14/14, claim 8/8, world claim tiles 4/4,
      GLua 407/0. Unverified live: blueprint use/aim traces against
      `COLLISION_GROUP_WORLD`, texture stretching of `render.DrawBox`,
      lighting tint, networking and multiplayer. Pieces are not yet persisted.
      Live claiming also needs a staged preview runtime JSON with
      `claimTiles` (requires approval).
      **Next step (user, 2026-11-02; paused here):** stage the preview
      runtime world JSON with `claimTiles` (back up the installed file first),
      launch/reload the preview with the new Lua, then do the bounded live
      review: claim a tile, toggle build mode, place and build one foundation
      and one wall. Resume only when the user asks.
- [ ] Prototype modular 64-unit foundations and snap points, 32-unit halves,
      16-unit-thick walls and triangles, with wall/floor/roof/door/window
      pieces. Use properly referenced mounted wood/stone/metal/concrete
      textures; verify asset/tool availability and rights, never copy Valve
      content. A configurable material-group source is a design option, not
      permission to generate an entire catalogue before a small visual review.
- [ ] Server validates the wireframe placement, ownership and snap relationship.
      (Placement, atomic payment and fade-in are source-wired in the prototype
      above; persistence, health, repair and destruction remain.)
      E contributes wood/materials atomically; insufficient materials, repeated
      input and interrupted sessions cannot duplicate pieces or items. Once
      complete, fade to the real structure. Persist geometry, per-material
      health, repair/damage and destruction across map reloads.
- [ ] Add storage boxes with separate persistent inventories and **no
      user-facing item-count cap**, with secure access and safe transaction/
      paging behavior. Doors fit frames, lock and support agreed keys or
      permissions; windows support barricades and curtains. Workbenches and
      other interactive furniture are explicitly out of scope.
- [ ] Define and test airtightness under missing/destroyed pieces and open
      doors/windows; muffle sound/light only for eligible enclosed occupants.
      Without curtains zombies try the front door; after repeated inaccessible
      door attempts they collectively try a wall. Coordinate this with Phase B
      perception/pathing and avoid global scans or infinite retry loops. Obtain
      human review of construction, damage, storage and multiplayer access.

## Phase F - Asset staging and targeted refactors

- [ ] Audit the user's new sign artwork/evacuation data and clothing sources,
      existing ownership/rights and builder inputs. Prepare a bounded sign and
      clothing build/staging proposal, costs and hash/ownership verification.
      Ask before expensive processing; do not overwrite edited sources or
      imply the new assets are staged until verified in the game and package.
- [x] Inventory `cl_skybox.lua` public table identities, hook ordering, render
      phases and state cleanup before splitting it into focused modules like
      atmosphere. First capture a baseline, then preserve behavior and run
      the relevant skybox/atmosphere fixtures and fresh visual review.
      Done 2026-11-01; see "Skybox module split" in Phase G.
- [ ] Inventory finite-number/vector/angle helpers by realm and semantics;
      centralize only compatible duplicates with load order and NaN guards
      retained. Similarly compare JSON readers' error and search-path behavior
      before sharing code. Do not replace different error contracts with a
      silent default or launch a project-wide refactor for its own sake.
- [ ] Map all materializer/materialization identifiers, commands, docs,
      persisted/config and external/native consumers before renaming to
      spawner/spawning. Define migration or explicit aliases only where
      required; do not break Walker tickets, diagnostics or existing settings.
- [ ] Audit the exact root `garrysmod/data_static` files, their hashes,
      provenance, read paths, current addon/package destinations and other
      owners. Report a precise migration/cleanup proposal; do not remove or
      overwrite shared files without user approval and verified restoration.

## Phase H - World-generation rules and separately approved output batch (last)

**Reported issue (user, 2026-11-01, not yet investigated):** on an ocean-coast
cell of the staged Alpha 3.3 preview, the beach meets the cell edge and
skybox ocean with a visible seam, and the underside of the beach can be
seen. Before changing anything, trace the physical connection across the
authored `edge_ocean` border, the generated map shell (floor and walls) and
the skybox shoreline/coast renderer, using the exact compiled cell. Matching
attachment coordinates do not prove continuity.

- [ ] Include the user's aesthetic 1x1 road redesign in the separately
      approved full-world recompile. Inventory the edited/new road sources,
      their instance dependencies and affected profiles, then regenerate
      matching derivatives as needed and review the new appearance. Do not
      overwrite user sources or present existing BSPs as updated; scope
      preview versus production and obtain approval before running the batch.
- [ ] Road connections: add `parking` and `dual_driveway`, wire 1x1 building
      markers to the adjacent ordinary road and resolve per-road conflicts
      (two driveways -> dual; driveway > parking > bus). Cover all four
      rotations, 1x1/multi-tile, non-road rejection and protected neighbours.
- [ ] West-ocean outer ring: place `edges/tile_edge_ocean_*` in ocean-adjacent
      outer edge slots of every west-ocean cell, move the shell and skybox
      shoreline out accordingly and verify a seamless `blendrocksand004a`
      coast join on the exact compiled fixture before rollout.
      Source: connections fixtures107/107 (no authored parking markers yet);
      ocean pool1a-9a, sea +Y, NW/SW corners, coast2880 (revision2),
      `sandfloor009a` beach and suppressed embankment. Outer-edge units1186,
      skybox geometry11/11 offline, GLua391/0. Native bounds suite, compiled
      seam fixture and visual review pending approval.
- [ ] Anti-grid roads (user, 2026-10-31): `deadZones` is retired and replaced
      by `mapGeneration.road.antiGrid`, which breaks straight ordinary-road
      avenues longer than a deterministic per-run limit (city9-16, preview5-8)
      into T-sections or one-cell jogs, preserving origin reachability and
      leaving highways/bridges/origin avenue untouched. Source done:
      `test_road_anti_grid.ps1`103 assertions pass (preview seed1337: longest
      avenue10->8, over-8 runs13->0, 55 breaks/jogs). An isolated planner run
      with the trusted motorway plan kept every motorway cell. No preview
      output was regenerated; awaits the approved batch.
- [ ] Empty cells (user, 2026-10-31): roadless cells with no safe zone or
      landmark are not built. The plan lists them under `emptyCells` (no
      recipe/VMF/BSP); runtime exports `empty`/`emptyTerrain`/`emptyColor`,
      no map and no exits; travel/pathing refuse them; world map, catalogue,
      Cell Health, capture, importer and stitchers show one flat terrain
      tile. Fixed: the planner counted the `none` landmark sentinel as a
      landmark, and the exporter read a missing `topology`. Isolated preview:
      571 map cells, 5 empty ((23,0),(2,1),(12,2),(21,22),(22,22)), 318
      recipes (installed 336). Offline `test_world_empty_cells.py`2/2,
      GLua391/0. Live world map, travel and Cell Health remain unverified.
- [ ] Inventory actual renamed/new source files, exact `_ra_`/military tags,
      environments and fixed landmark/army-base rules. Preserve user VMF/VMX
      edits and army-only siren intent. Check all relevant selection paths,
      including skyscrapers, multi-tile buildings, variants and fixed landmarks.
- [ ] Implement the user's rule: radioactive cells select only radioactive
      buildings/skyscrapers, falling back to appropriate terrain/detail when
      none are available; army-base cells use their matching military assets.
      Other environments may use untagged buildings, with matching tagged
      assets preferred when available. Resolve overlapping radioactive/army
      tags, the precise army-base identifier, fallback weighting and landmark
      exceptions with the user before coding.
- [ ] Add focused selection/control fixtures for radiation with/without
      candidates, military, other tagged and untagged environments, renamed
      decorations, siren placement, density tiers, all building sizes and
      protected neighboring cases. Keep accepted roads and motorway placements.
- [ ] Present a single costed preview-output proposal before any plan/VMF
      refresh, compilation, full materials, skyline, navmesh/photo or staging.
      Include matching runtime maps/materials/models, two temporary skyline
      aliases, revision hashes, package coverage, capture compatibility,
      restoration and human review. Keep production city/publication gated.

## Phase I - Deferred closure and acceptance

- [ ] Review the archived Alpha 3.2 Phase F/I/J/K/L and carried 3.1.5 Phase D/I
      deliverables against current evidence. Keep unperformed maintenance,
      photo/navmesh, Satellite/wireframe, skyline/revision and integration work
      explicitly open; agree whether and when to batch it with Phase H.
- [ ] Cell Health batches remain user-started, with options unchecked by
      default. `buildcubemaps` is a manual native-console action; a persisted
      Yes is user confirmation, never engine verification. Reuse the existing
      capture queue, importer and watcher; test restoration before acceptance.
- [ ] Record focused automation, compiled/artifact checks, live paths, human
      review and retained limits separately for each phase. Do not release,
      stage production or mark either milestone fully accepted merely because
      the tracker was archived or tests passed.

## Decisions to resolve in their phase

- Prefab distribution and editor permissions; server-wide custom content and
  stable seed/anchor identity; exact always-lootable versus spacing behavior;
  supported prop/light/particle/NPC classes and Hammer integration.
- Structure claim scope, 30-day visit semantics, construction immunity
  distance, reclaim/destruction of stored items, keys/permissions, material
  costs, airtightness, curtains and AI path/attack behavior.
- Attribute migration and balance; calling-card ownership scope, default
  selections, direct-PNG naming/category rules, recipe schema and generation
  budget, supplied artwork rights and quest availability.
- Radiation/army overlap and fixed-landmark exceptions; fog acceptance criteria
  and whether any measured baseline warrants a more expensive approach.
