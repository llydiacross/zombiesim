# ZombieSim Agent Guide

ZombieSim is an installed Garry's Mod gamemode. It combines realm-specific Lua gameplay code with a PowerShell pipeline that generates and compiles reusable Source VMF recipe maps.

## Active Task Tracker

- **Expensive-work batching preference, 2026-10-12:** continue Alpha3.1.5 with
  fast source edits, focused fixtures and bounded live checks. Ask before any
  considerable process, including preview/world regeneration, VBSP/VVIS/VRAD,
  navmesh generation, full material/Satellite generation or other large staged
  jobs. Bundle those expensive activities into one later approved pass where
  dependencies allow; do not start them opportunistically.

- **Phase D acceptance deferred / Phase E source work authorized, 2026-10-12:**
  user explicitly chose to defer Phase D's expensive output batch and continue
  source-only Phase E implementation. Do not infer Phase D acceptance or run
  its complete preview materials/wireframes, navmesh refresh or576-cell
  two-variant Satellite capture. Phase E source edits and focused fast fixtures
  are authorized; bundle expensive integration work later after asking.

- **Phase E accepted / Phase F active, 2026-10-12:**
  movement scales are0.675/0.765 with stamina unchanged. Searchable activation is
  halved once, active centres use deterministic priority and320-unit 3D spacing,
  and new body generations use1-2 while unexpired legacy generations retain2-4.
  Loot cells track content-hashed map filenames; a changed known fingerprint
  atomically backs up and resets only that profile/logical cell once, while old
  metadata-less rows are baselined unchanged. Matching old-map backups can be
  restored with their old spot rows. Fresh movement5/5, loot12/12,
  loot-spots18/18, enemy14/14, boss5/5, foliage16/16 and GLua266/0 pass.
  Fault-injected reset failure retains old rows and commits no backup. The user
  initial live review found no searchable loot because the new revision helpers
  were accidentally nested inside the first loot replacement and therefore
  absent on a real fingerprinted cold start. Helpers now load at file scope; the
  first fixture covers that exact path. Fresh loot-spots19/19 passes, live cell423
  exposes7 active spots from79 candidates, and the user confirmed highlighting
  and searching work. Phase E is accepted. Phase F server snapshots are active;
  defer client thumbnail rendering until isolation/idempotence is proven.

- **Phase F first server snapshot slice, 2026-10-12:** owner/profile-filtered
  character listings now include decoded appearance, worn shirt/pants, selected
  weapon visual, validated city/den/start location and a stable presentation
  revision while stripping internal character IDs. Two-call fixtures prove source
  character/data/inventory/weapon rows unchanged and slots isolated. Fresh
  characters11/11, inventory51/51 and GLua266/0 pass. Add explicit den/corrupt/
  appearance-required cases before beginning the bounded client thumbnail cache.

- **Phase F accepted / Phase G prototype gate active, 2026-10-12:**
  snapshots now cover city/den/start/corrupt location, clothing, selected weapon
  and stable revision without exposing ids or mutating source rows. Client cards
  bound three visible panels/one in-flight build, retry transient clothing
  failures, release materials/models/queues and restore the page after fixtures.
  Aspect-aware renderer-v2 framing fixes torso/head cropping; icon-model fallback
  displays Jim's crowbar without a SWEP. A live fixture exposed forged profession
  fallback and wrote `Valid Test` to slot1; strict `GetKnown` validation and an
  explicit-owner test writer fix the cause. Both fixture rows were transactionally
  removed and slot1 is empty; no cleanup command remains. Fresh characters12/12,
  inventory51/51, professions12/12, cards2/2 and GLua268/0 pass. Direct captures
  show Jim full-body/clothed with crowbar, CITY15,5, empty slots1/3 and unchanged
  Earth before/after cleanup. The user accepted Phase F on this evidence; no
  second real survivor or legacy slot was fabricated, and that unavailable
  comparison remains a validation limit. Phase G begins at its prototype gate:
  settle the exact Earth/distress asset source, then build only one Earth and one
  selected-cell city example before appearance/performance approval and broader
  polish. Do not substitute the Phase H supplied logo.

- **Phase H accepted / Phase I active, 2026-10-12:**
  user approved Natural Earth public-domain base art after licence review.
  `build_launcher_earth.ps1` pins the reviewed source and owns five layers plus
  one shipped notice: day, generated night lights/clouds/distress/rim. Static
  low/high Earth pairs are960/3968 triangles; one presentation owner switches
  Earth/city/hidden. The city example resolves Jim's exact preview15,5 skyline
  model with one model/marker/label; active-slot default is read-only. High,
  close, low and city direct captures exist. GLua271/0, presentation server3/3,
  client2/2, characters12/12 and packaging62/62 pass; launcher notices pass
  while whole launcher6/7 retains the unrelated changelog-order failure. Reject
  the first cold full-layer sample (384.70ms hook); warmed high is0.0264ms/hook,
  ~1.03KiB/frame and16.64ms median, but p95/p99 are49.59/52.00ms and matched
  city median is49.97ms under background throttling. This is operation evidence,
  not performance acceptance. The user then reported severe live lag while
  otherwise approving the presentation. The city owner was reparsing the full
  world and skyline JSON every rendered frame: a focused control measured
  399.38ms and12.04MiB/frame. Profile-cached assets and a selection/revision-keyed
  model cache reduce that same hook to0.0856ms and1.71KiB/frame; focused client
  tests pass3/3 and repeated Earth/city switches retain one asset load. High/
  normal Earth/layer3 is restored. The user confirmed both Earth and city are
  smooth in the foreground and accepted the remaining presentation. Phase G is
  accepted; the background-throttled samples remain scoped evidence rather than
  a clean60FPS measurement. Phase H now has an explicit page-to-state owner and
  exactly four Home actions: Play, Tools, Settings and Exit. Play opens survivor
  selection without deploying; Content Addons/Credits moved under Settings.
  Fresh launcher presentation4/4 and GLua271/0 pass; direct capture confirms the
  new Home composition. Phase H camera choreography, card-grid layout, manual
  Earth controls and human visual acceptance remain open.
  The next Phase H slice adds timer-free4.5-second Home-to-Play and3-second
  Play-to-Home presentation handoffs in the existing sole render hook. The user
  rejected both a crossfade-only handoff and skyline geometry attached to the
  globe. The approved direction is staged: Earth alone zooms1x->3.6x toward the
  selected coordinates, fades out, then a separate grounded sunset horizon fades
  in. Its bounded3x3 logical-cell cluster currently owns12 dark silhouette models,
  a warm backlight sun, haze and a ground plane. Mid-flight Back/page changes
  retain current weights/zoom without stale timers. Fresh presentation server3/3,
  client5/5 and GLua271/0 pass; horizon hook0.1395ms/frame,4.52KiB/frame. Human
  horizon/choreography review, selection retarget and resize/cancel remain open.
  The exact supplied transparent288x128 `logo.png` is now staged once under the
  launcher UI materials and replaces the temporary Home text heading. It retains
  its aspect/transparency inside bounded breathing/grunge framing; material
  dimensions are covered by the focused client suite. Fresh direct capture,
  presentation5/5, GLua271/0 and packaging62/62 pass. Human logo/framing approval
  remains a Phase H visual gate.
  The user then replaced the preview launcher's enclosed starfield brushes with
  real `tools/toolsskybox` windows around the authored scale16 3D-skybox room.
  Source now adds the map-owned `launcher_presentation_skybox` marker beside its
  `sky_camera`; server status sends that anchor/scale, and the sole presentation
  hook transforms Earth, the skyline cluster, sun, haze, ground, marker and label
  into the engine skybox pass. Launchers without the marker retain the prior
  world-space path, so the unchanged city launcher is not opted in accidentally.
  GLua271/0 and diff checks pass. The preview launcher BSP has not been rebuilt;
  actual skybox placement, transition appearance and performance remain live
  gates, and the expensive-work batching preference still applies.
  The user approved the skybox-backed Earth after the isolated preview launcher
  passed VBSP/VVIS/VRAD and a full Source-cache-clearing restart. Fresh client
  presentation6/6 passes; the sole hook measures0.0356ms and1.26KiB/frame with a
  0.1186ms maximum in the five-second sample. The user next requested that normal
  launcher presentation hide the authored preview water and look more like
  space, while sky inspection must retain its water and selected-sky behavior.
  The first runtime full-sphere mask was rejected after an actual1.1FPS warm
  sample; it was removed completely. The replacement is source-owned: only the
  29 water faces across 3D-skybox brushes4048-4056 are nodraw, while the six
  main-world inspection-water faces remain unchanged. Home/Play use approved
  `imported_tropo_night_2` through the existing cached sky-palette meshes;
  inspection still owns its selected sky/fog. Preview launcher
  VBSP/VVIS/VRAD passes and both staged BSPs hash
  `5A9CE06B755EE2B7B85C855A7446AA1A9716BB0A4E1D63C1C01F615638DC7242`.
  Fresh client presentation7/7 and GLua271/0 pass. Human no-water/space review
  remains open because the user reported rising paged memory during the check.
  The user then rejected the scale-only globe zoom, missing city marker, floating
  skyline treatment and cluttered survivor-card layout. Phase H now has one
  continuous descent value: a pulsing geographic marker follows the same Earth
  rotation, the marked globe grows and drops past the view, a bounded atmospheric
  veil owns the scene handoff, and a separate destination resolves through that
  veil.   The destination is a cached1344-triangle enlarged rolling-terrain mesh plus a
  96-triangle road cross with the existing bounded12-model skyline cluster seated
  at terrain height and rendered with its authored materials. A far ridge keeps
  the ground boundary out of frame, and the atmosphere-covered handoff swaps from
  the approved night sky to matching daylight before the destination appears. It
  is no longer a flat black silhouette. The Play UI is now one three-slot horizontal selector
  plus one selected-survivor dossier rather than three vertically interleaved
  cards. Ruled metadata, a bordered/backgrounded286px portrait, explicit equipped
  weapon stack, face-safe headroom and subordinate Delete action reduce clutter
  without changing explicit Deploy ownership. Each equipped weapon has a labelled
  icon box; the old posed model and duplicate equipped strip are removed. Fresh
  GLua271/0, client presentation8/8, character cards2/2 and characters12/12 pass.
  A five-second city sample measured59.74FPS,
  0.08345ms/4.91KiB per presentation-hook frame, two diorama meshes,12 city
  models and -147.98KiB retained Lua heap. Marker/descent/diorama/card appearance
  then received human approval in the running preview launcher. The subsequent
  enlarged daylight destination, smoother veil handoff and multi-weapon boxes
  also received explicit human approval. Keep this choreography, grounded
  destination and card treatment. The remaining Phase H lifecycle/manual-control
  gates are separate; Phase H remains unaccepted.
  Home now owns a transparent right-viewport Earth control surface: left-drag
  rotates, the wheel zooms within camera-distance-derived0.72x-1.65x bounds, and
  Reset View returns to the saved city anchor without changing gameplay data.
  Input is unavailable during transitions and outside Home; page/inspection/
  frame ownership changes release capture and smoothly return zoom to1x. Fresh
  GLua271/0 and launcher presentation10/10 pass. The user approved drag, zoom,
  Reset View and Play/Back mouse cleanup in the running launcher. Resize and
  Tools/browser/credits/appearance round-trip cleanup remain unverified.
  Create Back now walks prior wizard steps and returns from its first editable
  step to the survivor grid rather than Home; legacy appearance cancel also
  returns to the grid. Page switches release Earth input synchronously. The
  focused client lifecycle case covers these owners without creating, deleting
  or deploying a survivor.
  The user then approved Settings/Back, Tools/Back, Create cancel and Credits
  exit with normal mouse/camera restoration. Request ownership now remembers
  its initiating page: content failure retains the survivor-grid Back target,
  while a timeout returns to the grid instead of Home. Fresh launcher
  presentation11/11 and GLua271/0 pass. Typed-delete cancel, actual server
  failure, Exit confirmation and both-profile availability remain open.
  Tools visibility is now separate from preview-only action availability. The
  city launcher exposes Item Atlas, Content Status and Sky Browser; Map Atlas
  remains disabled because its inspection path is still preview-hardcoded, and
  Wardrobe retains its preview-admin guard. Actual-client profile tests pass1/1
  in city and1/1 after the verified return to `zn_preview_start`/preview. The
  broader both-profile Settings/admin review remains open.
  The user also approved typed-delete dialog cancel and Exit-to-GMod cancel:
  both return to the correct launcher page with normal mouse/camera ownership.
  No survivor was deleted and disconnect confirmation was not executed.
  Empty-grid rendering and explicit server rejection are now fixture-covered:
  three empty slots expose Create only, and rejection/timeout retain their
  initiating grid and reason. Launcher presentation12/12 and GLua271/0 pass.
  A five-second daylight-destination operation sample measured0.21527ms and
  9.15KiB per presentation-hook frame (1.454ms max;34.25KiB retained heap).
  Its19.74FPS process average is background/unmatched and is not performance
  acceptance or a regression comparison; Earth presentation was restored.
  The user accepted Phase H with the explicitly retained limits: destructive
  delete/disconnect confirmation, live city Settings, resolution-change review
  and matched foreground performance were not required to repeat or fabricate.
  Proceed to Phase I integration planning. Do not start the complete preview
  closure, navmesh, Satellite capture, city rebuild or publication until the
  user separately approves the bundled expensive work.
  Phase I's previously retained launcher-suite failure is resolved: current
  3.1.5 and archived3.1.0 changelog highlights now follow the required
  additions/limits/fixes grouping, including removal of one accidental leading
  space and stale “planned Earth-to-city” wording. Fresh launcher Tools8/8
  passes; this is data-order cleanup, not new historical claims.

- **Paged-memory investigation, 2026-10-12:** pausing stops the observed commit
  growth, narrowing it to active frame/tick work. Two early idle windows rose
  6.44MiB and12MiB, but a matched settled60-second run then rose only2.47MiB,
  entirely in the first10seconds before plateauing; working set fell8.13MiB.
  Development-only profiler GC boundaries show114KiB retained Lua heap across
  2101frames, with bounded23 client entities, zero city models, one sphere, six
  palette meshes and zero card entries. Ten Earth/city cycles incurred one
  approximately9MiB Source model/material cache admission, then private commit
  remained exactly2373.67MiB for every cycle; handles were unchanged and retained
  Lua heap was76.3KiB. This is evidence of allocator/cache high-water behavior,
  not an idle or launcher-cycle live-object leak. It is not proof that every
  deployed gameplay subsystem is leak-free; representative long gameplay remains
  a separate diagnostic if growth continues outside the launcher.

- **Phase C accepted / Phase D active, 2026-10-12:** the user confirmed blocked
  red and waypoint-yellow arrows render correctly and that all tested gate
  entries and exits work after the motorway arrival correction. This completes
  the remaining Phase C live colour, travel, arrival and regression review.
  Phase C is accepted on the accumulated static, compiled-map and live evidence;
  earlier `Phase C is not accepted` notes below are historical and superseded.
  Proceed to Phase D full-footprint minimap, world artwork and revision-matching
  Satellite capture. Production rebuilds and publication remain separately
  gated, and the deferred safe-zone entrance/detail walls remain untouched.

- **Phase D full-footprint projection, 2026-10-12:** audit found the Level/
  minimap capture still used an old camera/FOV-derived ~3206-unit span while
  revision-matching world capture already used the authoritative5760 pitch.
  `world_capture/sh_contract.lua` now owns local-map span/projection; city
  captures use `ZM_World:GetCellBounds().neighbourPitch`, den span remains
  independent, and cache version11 invalidates cropped captures. Offline
  capture client7/7 and server7/7 cover centre,+/-1600,+/-2240,+/-2880, all
  cardinals, asymmetric coast/land extents and den isolation; GLua266/0.
  Fresh `zz_preview_a0e68fbdcfc2-edge2` reload retained preview with no recent
  Lua/capture error. User confirmed the fresh Level/map-texture view shows the
  complete outer footprint and player/loot/door/gate-arrow markers remain
  aligned. Current-cell Level/minimap projection is accepted; stitched world
  previews, fresh Satellite imagery and den capture remain Phase D gates.

- **Phase D artwork/HUD source pass, 2026-10-12:** respecting the expensive-work
  batching preference, no world/material generation, compilation, navmesh or
  Satellite job ran. Cell artwork now consumes matching generated layout
  metadata in an authoritative9x9 frame: inset5x5 core, actual border/outer
  placements and water for omitted ocean bands. Wireframes use neighbourPitch/2
  rather than1640; static HUD texture projection and cross-cell compass use the
  authoritative pitch, while den map view retains its old independent height.
  New focused artwork fixture passes core/environment, border route, outer edge
  and west-ocean cases. Tuned-plan dry run validates311 layouts; wireframe dry
  run validates576 cells at5760 span. Capture client7/7/server7/7 and GLua266/0
  pass. The multi-tile suite was stopped when it exceeded the quick-check
  window; rerun it in the later approved validation batch. Fresh generated/
  stitched/wireframe materials, navmeshes and Satellite imagery remain pending.

- **Preview variety/rebuild side task, 2026-10-12:** user approved a future
  48x48 city (preview stays24x24), neighbour-aware recipe variants,
  and excluding aaa straight-wall pieces immediately beside road/motorway
  corridors in both rings. Full preview regeneration is authorized using all
  current authored edge walls/renames. Only the new safe-zone detail placement
  and design plan remain deferred; this supersedes the older committed-only
  tile restriction for this rebuild. Work is isolated under
  `generated/preview_variety_tuned_20261012`; production rebuild/publication
  remain unauthorized. User rejected the initial eight-variant495-map pool as
  too large and requested tuning with neighbour avoidance retained. Its
  compiler/continuation processes were stopped; do not resume/stage that build
  under `generated/preview_variety_20261012`. New policy caps candidates at4,
  retains infrequent base layouts unless adjacency requires an alternative,
  and scales frequent pools by ceil(uses/15). Tuned preview311 recipes plus3
  dens (314maps);11720 assertions pass; all1104 cardinal pairs differ in
  filenames and actual tile layouts.387/576 cells retain their base layout.
  Current-source build complete:VBSP/VVIS/VRAD314/314, no failures/incomplete;
  portals314/314, compiled818gates/818arrivals, skyline311recipes/runtime576cells.
  Tuned full-layout checks13896 assertions pass. Staged with GMod closed and
  verified4264 content/engine paths;16 original backups verified in extended
  Phase B restoration ledger. Old captures preserved/incompatible. Launched
  `zn_preview_start` for fresh review; deployed gameplay/visual acceptance pending.
  Edge corner VMX renamed to match its VMF, byte-identical content preserved.
  Phase C is not accepted; production/publication remain untouched.

- **Development-environment lag finding, 2026-10-12:** the staged tuned preview
  reproduced severe stalls with growing non-paged kernel memory (FMic/Irp tags
  to1.77GiB). A matched same-map/cell/weather A/B isolated the trigger to GMod
  Lua autorefresh watching this in-place development tree (120815 files;
  `generated` alone72859files/30.5GiB). Normal launch:45.23FPS, frame p95
  54.16ms, pool growing. Documented `-disableluarefresh` launch flag:56.34FPS,
  p9520.73ms, pool stable ~0.55GiB. Client Lua hooks were identical
  (4.17 vs4.18ms/frame), and the same gamemode file I/O ran in both, so
  ZombieSim runtime code is not the allocation owner. Released players are not
  expected to reproduce it: `generated/` is gitignored/outside the release
  allowlist and packaging ships mounted `.gma` archives rather than loose
  watched files. This is architectural reasoning plus the A/B, **not** a
  measured clean packaged-install run, and the owning Windows filter/driver
  remains unidentified; user chose to record it rather than test further.
  Launch defaults, Steam preferences and gameplay code are unchanged. Treat
  autorefresh-enabled samples as unrepresentative of player performance; use
  watcher-free matched runs for any future performance acceptance.

- **Phase C motorway arrival fix, 2026-10-12:** live travel showed gate arrivals
  placing the survivor inside the motorway concrete central reservation.
  `bin/transition_gates.psm1` writes every `<SIDE>_ENTRANCE` landmark on the
  cell axis (cross-axis 0), and `tiletemplates/roads/tile_motorway.vmf` has a
  median barrier at x-8..8, z40..48. Phase C had moved the arrows onto the
  carriageways but never the arrival. Fixed at runtime in `sv_transitions.lua`
  (`ResolveGateArrivalPosition`), not in the generator, so no map rebuild was
  needed: motorway arrivals trace the right-hand carriageway at lateral160,
  384 inward -128 past the arrows - and validate the player hull before
  placing. Ordinary roads, den exits, unsupported surfaces and an obstructed
  carriageway keep the authored landmark. User requested and approved this
  placement, including spawning behind the arrows. Measured motorway section:
  carriageways x-256..-16 and16..256 (centres+/-136), outer walls+/-264..280.
  Arrows, arrival yaw,160u/s walk and fade timing are unchanged. Offline
  server transition markers8/8 (two new cases), client10/10, GLua266/0; live
  reload republished both gates as motorway pairs and the user confirmed the
  corrected arrival in `zz_preview_a0e68fbdcfc2-edge2`. The authored landmarks
  themselves are still median-centred, so a future generator correction remains
  open; the runtime fix is the current contract. Phase C is not accepted.

- **Phase C continuation, 2026-10-11:** user deferred newly authored safe-zone
  entrance/detail walls and their new design plan; preserve those working assets.
  Isolated committed `7d7f8501` tiles under `generated/phase_c_live_20261011`
  keep them out of gate regeneration. Fresh outer2306/client markers10/server6/
  catalogue2 pass; original Phase B backups2074/2074 verify. Full isolated
  preview retains576 cells/187 recipes, no logical recipe mapping changes,
  190 VMFs including dens, zero missing. VBSP190/190 and all portal budgets pass;
  skyline187 recipes complete. Compiled gate check186 maps/484 gates/484 arrivals
  passes. Isolated VVIS/VRAD running, export follows successful completion;
  not staged or live accepted. GMod was closed at the status probe.
  Preserve completed captures; new gate geometry requires a new capture revision,
  so old Satellite must remain compatibility-gated after staging.

- **Imported assets and notices side task, 2026-10-10:** user-confirmed creator
  permission covers the five exact supplied GameBanana archives; no independent
  license text was supplied. Added hammer/machete/spanner/Lewis and radiation-suit
  HEV Gordon/hands, preserving saved appearance. Approved hammer-only world
  derivation and mounted CSS sleeve substitution; no archive Lua installed.
  `bin/import_assets.py` now owns all six imported sources and 1768 files through
  `content/data_static/imported_assets.json`; original CS 1.6/machete credits
  remain. Missing CS 1.6 ZIP uses verified retained ownership, not a fresh archive
  validation. Arsenal55 ranged/four melee; quartermaster32 offers.
  Options Third Party Licenses follows Changelog and displays35 sky/six asset
  records with original text and explicit permission-only notices. Shared scroll
  sizing includes both footer buttons and bottom padding in launcher/gameplay.
  GLua265/0, offline9 pass/one missing-source skip; fresh imported server3/3,
  client5/5, catalogue55/0, effects20/20, static18/18, inventory51/51, loot12/12,
  trading14/14. Fresh notice content/lifecycle/measured padding case passes;
  whole launcher suite6/7 retains an unrelated changelog source-order assertion
  failure (3.1.5/3.1.0 highlights). User confirmed corrected launcher footer
  fully visible. Packaging61/61; report-only audit8367 files/six packages/
  707 existing release blockers. User also approved notice readability,
  scrolling and closing back to launcher Options. Human weapon
  appearance/manual firing remain unverified. No Phase C acceptance or upload.

- **Weapon side task, 2026-10-10:** the approved arsenal now contains 24 CSS
  firearms, 24 CS 1.6 variants and six HL2 ranged weapons. CS 1.6 is loot-only
  at exactly 1/100 counterpart weight; fixed +25% damage/+20% range and
  capacity/15% faster firing and reloads compose with random/mastercraft
  scales. Keep these independent item IDs and existing offers intact.
  Offline weapons6/6, GLua257/0, packaging59/59; fresh preview catalogue54/0,
  effects20/20, static18/18, inventory51/51, loot12/12 and trading14/14 pass.
  Actual isolated crossbow projectile damage/lifetime tests pass; human
  weapon/hands/audio appearance and survivor firing remain unverified.
  Explosives, alternate fire, gravity gun and recoverable bolts are excluded.
  This side task does not accept Phase C or authorize publication.

- **Next milestone: Alpha 3.2 CSM**, designated by the user on 2026-10-10.
  Follow [the CSM implementation tracker](docs/csm-implementation.md) after
  completing Alpha 3.1.5. Do not start CSM during the current milestone or skip
  its projector/lighting feasibility gates. Production rebuilds and publication
  remain separately gated.

- **Fixture-review preference:** when the user chooses to inspect fixtures,
  open the exact requested VMFs in the installed Hammer++ for them; do not
  merely provide paths or ask them to find the files. Identify which opened
  fixture covers each review case. Preserve unsaved editor work and do not
  treat opening a fixture as visual acceptance.

- **Active milestone: [Alpha 3.1.5](todo-alpha.3.1.5.md).** The user authorized
  implementation on 2026-10-06 after adding the edge tiles. Phase 0 is accepted:
  nine edge sources inventoried, current 179-recipe baseline and verified
  restoration copies retained, focused launcher baseline captured. User carried
  coast/gate photographs and full quality/cold-warm baseline into A/B/G; do not
  reopen Phase 0 for those limits. Preserve approved source overhangs.
  **Phases A/B/C are accepted; Phase D is in progress**, then follow Phases E-I in order. Shared bounds,
  deterministic outer-ring generation and layout metadata are implemented but
  disabled in normal settings. Isolated checks: outer edges 519 assertions,
  GLua 184/0, border showcase/entrances pass, ten VBSP/portal fixtures pass,
  BSP entity checks retain 287 corrected dynamic props, live bounds 6/6 in the
  preview launcher. Human confirmed north-facing straights and NW-opening
  corners, and approved class-only correction of 15 incompatible new-edge
  trees/signs; original brush/prop placement and overhangs are unchanged.
  User accepted both land/coast Hammer fixtures on 2026-10-06 after the agent
  opened them in Hammer++; the user closed the editor windows after review.
  User subsequently accepted both enlarged land/coast in-game geometry
  reviews in Sandbox. Two isolated BSPs completed VVIS/VRAD without failures;
  temporary runtime copies were removed after verified return to
  `zn_preview_start`/preview. Before/after city and preview survivor persistence
  snapshots match exactly; live bounds remain 6/6. This is geometry acceptance,
  not integrated ZombieSim pursuit, loot, skyline or gate acceptance.
  **Phase A is accepted**; the user authorized Phase B on 2026-10-06,
  carrying integrated pursuit/loot/gate checks into later phases. Generated
  fixture sources/zoos are under `generated/outer_edges`; no enlarged maps,
  skyline or runtime exports staged. Gates/transition-road blocking geometry
  still require the planned Phase C migration. Preview-first; production
  city rebuilds and Workshop publication require separate approval. The supplied
  logo, exact globe asset clearance and live baseline gaps are explicit gates,
  not permission to guess. No phase is accepted solely by static checks.
- Phase B source/isolation checks now pass: shared 5760 pitch, schema-2
  plan/bounds/coast compatibility, recursive source hashes and complete model
  companion caches. User explicitly retained the original procedural beach
  beyond the 2240 coast edge; do not replace it with a water-only strip.
  Six isolated skyline fixtures: 177 assertions, manifest/tower/height pass,
  VBSP/portals 417/1317 maximum; installed legacy manifest 179 recipes still
  passes. GLua186/0, fresh isolated geometry8/8, packaging57/57.
  `generated/skybox_edges` contains models/room/VMFs/reports; none staged.
  Fresh expanded renderer visuals and matched performance remain Phase B
  gates. Launcher reloads verified logic only, not renderer appearance.
- **Phase B accepted 2026-10-09:** user confirmed the edges worked perfectly and
  accepted remaining live/review gates on accumulated in-game review. Do not
  reopen historical dense/coast/bridge/snow/tower/fire checks or matched
  performance merely to fill gaps. Uncaptured cases are retained limits, not
  fabricated test evidence or a performance verdict. Proceed with Phase C
  gate/arrival/road-arrow migration; it is not pre-accepted. Temporary expanded
  preview assets remain ledger-owned for continuation; return/restoration
  obligations and production/publication gates remain unchanged. This acceptance
  supersedes the earlier Phase B pending/unaccepted notes below.
- **Phase C runtime arrows 2026-10-10:** single arrows are visible after a
  controlled two-sided/depth-tested material correction. User requested two
  motorway arrows at the annotated carriageways rather than the median.
  Each motorway arrow has its own server surface trace at+/-160 lateral,
  256 inward; ordinary roads retain one96 inward. World-data classification
  waits for GM profile initialization and cleanup republishes. Offline client8/8,
  server6/6, GLua200/0 and fresh actual-client8/8 pass. Preview15,5 capture shows
  N/S pairs on deck36 and E/W singles on bridge196. User approved revised-pair
  placement; live colours/range and integrated travel remain gates. No new Phase C maps or
  generated runtime exports staged; temporary Phase B restoration remains due.
- **Phase C map-arrow integration 2026-10-10:** HUD minimap (live/texture) and
  satellite/Level view use dynamic clipped projections of the same gate anchors
  and colours, not baked capture arrows. World-map window/waypoint diamond are
  unchanged. Offline/fresh actual-client10/10, GLua200/0, editor diagnostics and
  human review of both views pass. Actual yellow/red state and integrated travel
  remain unverified; Phase C is not accepted.
- **Captured-world side task 2026-10-10:** user authorized the resumable preview
  capture/import pipeline and combined navmesh/capture maintenance before
  returning to Alpha 3.1.5. See `docs/world-capture.md`. Player Atlas now refers
  to existing illustrated Satellite assets; old layered Atlas is retired only
  from the selector. New Satellite is complete captured imagery, never a partial
  or stale collection. Map/Level, Walkers, Wireframe and launcher Map Atlas stay
  separate. Cubemap native command is Lua-blocked; do not bypass via aliases,
  exec or RCON. Actual capture capability/adjacency/restoration and composite
  nav checks remain gates, not accepted merely by fixture tests.
- **Capture pilot verified 2026-10-10:** revision4 now uses skyline-owner camera
  height4992 with native sky/capture-scoped coast; prior black buffers rejected.
  Seven logical cells/14 outputs plus separate Storm Drain2/2 pass; composite
  generated/saved/reloaded1313 NAV areas before two captures. Survivor restoration
  verified at preview15,5. Partial256px tiles/3072px overview staged with explicit
  incomplete manifest,1.81MB encoded/75.5MiB estimated RGBA; Satellite remains
  disabled. Client6/6,server6/6,importer5/5,atmosphere17/17,GLua208/0.
  User approved pilot imagery and authorized full preview capture rollout;
  full-world completion/import remains pending.
  active Alpha3.1.5 Phase C remains unaccepted.
- **Phase C first source boundary 2026-10-09:** bounds-driven expanded gates now
  use+/-2208, with corresponding inward arrival landmarks. Canonical road/bridge
  deck extraction yields36/196 and lifts elevated triggers/barricades/arrivals
  by160; no authored tile edits. Expanded old blocking transition-road variants
  become ordinary straight roads; bridge/core/coast/other-border transforms are
  protected. Isolated outer2306, original border/entrance suites and13 VBSP/portal
  fixtures pass. Nothing newly staged; arrows and integrated travel remain next.
  Phase C is not accepted. Running assets still belong to the Phase B ledger.
- **Coast clarification 2026-10-07:** the requested fixture is the Storm Drain
  grid `(0,12)` / logical `(0,0)`, not the SE authored water-corner fixture.
  Omit new outer scenery only along the west 3D-skybox ocean; preserve all old
  border and water-corner tiles. `skyboxOceanSides` drives omission/renderer
  attachment separately from `waterBorderSides`. West recipes use
  `-oceanw-edge2`; expanded preview187 recipes vs unchanged legacy179.
  Exact Storm Drain has21 unchanged border pieces,23 outer pieces,zero west
  outer pieces. West skybox shoreline attaches at-2240, not-2880; its640-unit
  band fills the gap while retaining the approved beach. Skyline275 assertions/
  eight recipes, outer1158/exact old source transforms, original border/entrance
  suites and VBSP/portals474/1517 pass. New no-gap live case not run
  because game closed; expanded visual review remains pending. Do not stage
  or treat earlier SE-corner review as approval of this corrected coast.
- **Physical coast shell correction 2026-10-09:** the Hammer black strip was
  traced to uniform shell expansion: the floor and sky wall still reached 3072
  past the west border even though outer tiles were omitted. The shell now
  consumes `skyboxOceanSides` and retains the original 2240 ocean boundary.
  Land-facing clearance, clips, ceiling, old border/core instances and beach
  remain unchanged. Earlier renderer-coordinate checks did not prove the
  physical connection. Fresh outer regression1796/skyline331 assertions and
  eight VBSP/portal fixtures pass (max474/1517; Storm Drain363/1109).
  Existing sky_day01_01 texture-size/flags diagnostic is unchanged from the
  retained baseline. Corrected fixture opened separately in Hammer++ under
  `generated/coast_shell_fix/skyline/src`; original window preserved.
  User confirmed the black strip is gone in the corrected Hammer fixture.
  Integrated beach/ocean renderer appearance remains unverified.
- **Phase B live review 2026-10-09:** full matching576-cell/187-recipe preview
  temporarily staged with verified backups/ledger under
  `generated/phase_b_live_preview`. All190 maps VBSP/VVIS/VRAD and portal
  budgets pass. User approved saved-cell outer/neighbour appearance at logical
  `(22,2)` and the actual corrected Storm Drain west beach/ocean join at
  `(0,0)`. Fresh bounds6/6 and geometry9/9 pass; dense/bridge/snow and matched
  performance remain gates. Lag investigation explicitly stopped by user;
  do not resume it unsolicited or claim a root cause. Jim currently at Storm
  Drain; authorized return target logical22,2/grid22,14, no safe zone.
  Temporary assets must be restored/verified after review; production unchanged.
- **Current-cell edge fires 2026-10-09:** user chose six stable cosmetic fires
  on actual outer-edge buildings, not only neighbouring sky models. Extraction
  now marks rooftop anchors by authored `edges` provenance; core/border roofs
  and wrecks remain separate. Normal-world rendering reuses existing flames
  and smoke at full size under the existing fire toggle, with no damage, sound
  or dynamic lights. GLua186/0, skyline612 assertions/eight recipes and full
  manifest187 recipes pass; old manifest fields are exactly unchanged.
  Only the regenerated preview skyline manifest was staged with GMod closed;
  original backup and ledger hashes verified. Fresh Storm Drain client draws
  six fires from20 edge roofs (24 flame/glow quads,52 smoke quads in capture);
  geometry10/10 and user flame/smoke appearance approval pass. Toggle and
  cross-cell lifecycle checks remain unverified. Phase B remains in progress;
  Jim is still at Storm Drain and temporary restoration remains outstanding.
- Alpha 3.1.0 development is complete: the user
  accepted final Phase H and the milestone on 2026-10-06 after a bounded fresh
  launcher check. [docs/todo-alpha-3.1.0.md](docs/todo-alpha-3.1.0.md) archives
  its evidence and validation limits. Do not reopen accepted phases or infer
  work from historical pending lists.
- Final live checks: renderer 8/8, catalogue/materials 78/78 and
  browser/flight/fog/cleanup 15/15. Human confirmed smooth automatic tour,
  replacement night, soundtrack fade, blackout and return. The captured
  Coastal tour is scoped CPU operation evidence, not a matched/GPU benchmark.
  Final preference/audio/return-state capture was rejected because no connected
  preview admin was available; retain that limit separately from human review.
  User subsequently confirmed Default restored and returned to their survivor.
- Workshop release remains separately deferred: rights/IDs, navmeshes,
  production export/skyline and clean mounts/downloads. Version status is
  `in development` for Alpha 3.1.5, not `released`; no production rebuild/upload
  is authorized. Preview remains the default for approved iteration.

### Archived Alpha 3.1.0 chronology

The notes below record earlier decisions and evidence. Their pending/active
wording is superseded by the final acceptance above, not a current task list.

- The user accepted Alpha 3.0 on 2026-10-04; [docs/todo-alpha-3.0.md](docs/todo-alpha-3.0.md) archives its implementation, regression/live evidence and retained validation limits. Its uncaptured checks are historical limitations, not new Alpha 3.1.0 work.
- Alpha 3.1.0 Phase E is accepted; the user carried remaining sign integration into Phase G. Phase F Wardrobe and revised spiral fabric direction are approved. Filename/fabric catalogue builds; actual client pool regressions pass 5/5 after fixing owned-material pins and failed-build retries. Generated equipment survives reload and independent restoration with exact original inventory cleanup; scoreboard composition moved to PreRender after a verified clipping regression. Cuff-anchored/opposite-limb/front-back calibration, real gore visuals, bloody/walker variants and representative performance remain pending; Phase F is not accepted. Optional client-local sky palettes are Phase H; settle imported provenance and baked-light compatibility before staging/distribution.
- Clothing follow-up: the user subsequently requested hundreds of fabrics, smooth high-detail dye, centred `_chest` artwork and fixes for visible full-back/repeating-back seams. Source now expands to 206 fabrics, supports pink/chest and uses inspected torso-triangle back projection. Physical continuity checks pass 38/38 and rebuilt prototype checks 248/248. Full expanded catalogue staging and fresh human visual review are the immediate gate; do not carry the earlier spiral approval forward as approval of these new outputs.
- Latest clothing direction supersedes combined front/back shirts: user approved enlarged/lowered chest, requested removing combined shirts, raising back prints, colourful untagged backgrounds (explicit light/dark rules unchanged), and raised left/right thigh prints. Published790finishes/792Wardrobe/3178owned files, matching896finish caps and unchanged16target pool. Both thigh placements pass actual topology checks118/118; built catalogue5124/5124, fabrics2754/2754, prototype266/266 and fresh preview static18/18/inventory51/51 pass. Human review of the newest back/thigh/palette outputs remains pending. Do not repeat earlier accepted chest/dye/back-fix questions; review only the newest placement/palette changes.
- Distribution work is authorized within Alpha3.1.0 before further large content expansion. **Both city and preview ship; preview is the player sandbox.** `workshop-settings.json` and `bin/build_workshop_packages.ps1` own allowlisted inventory, report-only exclusions/orphans, byte-budget shards and isolated staging/GMA verification. Never delete reported unowned assets automatically or migrate the installed development tree. Strict release is blocked by missing navmeshes, legacy city export/no city skyline manifest, rights clearance and final Workshop IDs; no production rebuild/publication is authorized by packaging work. Packaged manifests/markers enforce compatibility and deployment gates; loose development remains unchanged. Clean package mounts/downloads and human visual checks remain separate acceptance gates.
- Launcher Content Addons/Recheck/Back UI is user-approved in loose preview. Core owns both launcher BSPs. Settings use safe `pending:<package-id>` labels, never fake numeric Steam IDs; real IDs are assigned by creating private Workshop items, then rebuilding/updating those same items. Builder does not upload. Subscription/download/mount states are distinct and mounted compatibility gates deployment, not subscription alone. Fixtures46/46/live distribution9/9 pass; actual published-ID and clean-mount acceptance still deferred until publication.
- Cuff-up extension is published and user-reviewed on male/female left/right sides:866finishes/868Wardrobe/3482ownedfiles. Separate bottom-aligned `pants_cuff`/`pants_cuff_right` presets preserve all790priorfinish/itemdefinitions and ownedfiles; `_pants_cuff` permits artist opt-in restrictions. Artwork25/25, topology134/134, prototype306/306, published7319/7319, fabrics2754/2754, GLua175/0; fresh live static18/18/distribution9/9/pool5/5. Package audit6659files/7packs remains within shard budgets;387releaseblockers unchanged. Rear-facing limbs, bloody/walker integration and representative animation/gore/performance remain unfinished; cuff review is not Phase F acceptance.
- Rear-limb artist tags and placements now implemented/user-approved for all eight male/female left/right rear thigh/upper-arm combinations. No rear-tagged PNGs currently; default866finishes/896cap unchanged. Parser106/106,topology170/170,prototype370/370,published7335/7335,GLua175/0. Temporary live fixtures removed,inventory/equipment untouched. Next is bloody/walker integration: mountedgroup03inspection48/48 shows2048sheets/differentUVfingerprints, so survivor1024charts are not approved there. Separategroup03report preserves defaultinspection; group02player path failed lookup and is unverified. Preserve existing gore overrides/material copies and unsupported-model appearance. Phase F remains unaccepted.
- Offline Phase F continuation: user chose shared original blood overlays, not duplicateitems/budget expansion. `build_clothing_blood.ps1` stages3sharedlayers/6files (~4MiB); exhaustiveblood32/32, survivor170/170, independentlynamedgroup03charts/fullbodytriangles56/56, catalogue5753/5753, packaging47/47, GLua175/0. Preview-onlyWardrobeBLOODtoggle and clean/bloodypoolkeys implemented; newclientpoolcases/render/gore acceptance **not run: game closed**. Group03diagnostics remain mask-unapproved; existingnativewalkerblood unchanged. Run chart writers serially for isolation checks. Actualaudit6681files/7packs/387releaseblockers; no maps/uploads/inventory changes. Phase F still needs live blood/gore/performance and independently calibrated walker clothing.
- [docs/todo-alpha-2.9.2.md](docs/todo-alpha-2.9.2.md) archives the completed client performance and quality-presets milestone (accepted 2026-10-02); its baseline and validation remain useful for Alpha 3.0 comparisons.
- Current Phase F evidence supersedes the closed-game/group03 next steps above:
  the user approved blood preview, all fifteen independently calibrated group01
  citizens and actual citizen walker/corpse/detached-piece appearance. **Never
  apply catalogue clothing to rebels**; preserve their native mounted blood.
  Engine mesh transfers pass80/80; no per-model catalogue texture duplication.
  The user subsequently chose independent full-catalogue outfits per zombie,
  not a shared outfit per model/cell, and approved96 shared targets (~384MiB
  maximum RGBA storage plus source/material memory). Individual/ticket identities
  preserve outfits through blood refresh and immutable corpse/limb copies.
  Pool-only publication retains866finishes/868Wardrobe, now3642ownedfiles;
  catalogue8035/8035, packaging48/48, GLua175/0. Live Gore16/16, static18/18,
  inventory51/51, clientpool9/9; the enlarged stress test initially froze/flushed
  the renderer, so capacity/citizen tests now run across frames and passed9/9 again.
  Runtime composition uses a2ms soft frame budget; individual cold builds can
  exceed it. Verified15same-model independent outfits and15mixed-model composites.
  One clean warm mixed-crowd run measured60FPS/0.02034ms clothing-hook average;
  cold builds16.807ms mean/21.452ms max and a failed/stale native-control comparison
  remain validation limits. Actualaudit6842files/7packs/387blockers. Owned probes
  removed, quality restored, survivor alive at preview22,0.
- The user subsequently **accepted Phases F and G on 2026-10-05**, explicitly
  confirming existing checks/earlier skybox reviews are sufficient and asking
  to proceed directly to **Phase H**. Do not repeat Phase G regeneration or
  visual checks merely to close historical checklist entries. Uncaptured
  cold/lifecycle/matched-performance and sign integration checks remain
  validation limits, not pending phase gates; no new checks are implied by
  acceptance. Workshop release rights/IDs/navmesh/production export/clean-mount
  blockers remain deferred. Phase H source eligibility and palette/control
  decisions must be settled before changing the optional client sky renderer.
- Phase H's first-selector source choice is approved: mounted game skies plus
  original procedural palettes; uncleared imports remain excluded. Reference
  mounted paths without extracting/copying assets. Palette/control design and
  actual renderer appearance remain separate implementation decisions.
- Phase H prototype now uses `cl_sky_palettes.lua`: saved Default/Natural/
  Cinematic Options, original context gradients and temporary individual
  preview commands. Default remains native; no BSP relighting or server weather
  changes. Natural daytime layering is user-reviewed. Mounted `sky_day03_06c`
  remains a development candidate, referenced in place. Measured texture-edge
  matching corrected side/top mapping; a subsequent tiny seam was fixed with
  half-texel UV insets without changing rotation. User confirmed seam gone
  after fresh reload; live5/5, GLua176/0. Do not repeat accepted F/G checks.
  Phase H still needs context/persistence/reset/launcher/den/capture/weather/
  performance review and final palette membership. Publication stays deferred.
- Phase H UI follow-up supersedes the dropdown/preview-only restriction:
  user chose automatic palettes plus locally saved individual skies. The
  thumbnail browser offers12cards, context warnings and parent-safe Back/X/
  Escape cleanup; mounted sky remains outside automatic palette membership.
  Options has9collapsible sections and a friendly engine-owned audio notice;
  existing controls/precision/presets/server guards retained. Fresh GLua177/0,
  renderer7/7, browser/Options5/5; user confirmed grid/grouped Options, saved
  selection/reopening and restored mouse/camera control look/work correctly.
- Latest Phase H palette UI replaces state dropdowns with four clickable
  preview slots on the left and individual/native thumbnail choices on the
  right. Built-in Edit creates a personal copy; custom Edit retains its ID.
  Draft assignment/cancel never changes the saved choice. Expanded browser and
  revised editor are user-approved: all four slots visible and picker works. The catalogue
  now has82individuals/12built-ins/36imports,432materialfiles/391.48MiB;
  supplied-author permission specifically clears the additional nine sets
  including MR53. Retain original README files in `data_static/sky_licences`
  and common packages. Assets2383/2383, packagefixtures50/50, GLua180/0;
  fresh renderer7/7, UI/inspection9/9 and materials76/76 pass. Deferred parent
  cleanup is fixed; ordinary editor heights show all four slots. New full-cube
  appearance/aerial-render human review remains; no map builds/publication or F/G redo.
- Latest H continuation adds six automatic variants (18built-ins total), using
  all new sets except John Tron at the user's explicit request; keep that sky
  individual/custom only. User approved variants and real aerial preview/return.
  Fresh renderer7/7, browser9/9, catalogue/context78/78, GLua180/0. Isolated
  weather/light boundaries pass; real weather visuals are not thereby accepted.
  Actual selected custom "Test" (`custom_1`/dusk `imported_mr53`) survives preview
  changelevel with six meshes and byte-identical store. Leave user's custom
  selection active. H still needs live weather/context, launcher/den/map-capture
  and representative performance; do not reopen F/G or deferred publication.
- H live continuation: user confirmed rain/Level-view return, normal den
  first-person/Options round trip and launcher Options. Profiler now includes
  PostDraw2DSkyBox; warm Natural draw CPU0.04866ms/frame is scoped operation
  evidence, not native/GPU comparison. User paused to author a **launcher-only**
  preview area in Hammer with point_camera `Preview_skybox`: camera-only
  position/angles, no survivor teleport; replaces launcher upward sweep only,
  not implemented yet. City cells retain their existing sky/current preview;
  do not add areas or rebuild city templates for this request.
  Weather scheduling restored/verified auto1/manual0. Client remains at preview
  launcher; when ready restore/verify Default and slot2 Jim at logical22,0
  (raw22,12), safe-zone none. Do not move them or rebuild maps while paused.
  Options sections default closed and persist each section's open/closed state.
  The preview-launcher-only TOOLS tab is user-approved. Its left column offers
  Wardrobe, Item/Map Atlas, Sky browser and Content Status. Atlases and Content
  Status use the right side of the launcher frame, not a hub window. Tools are
  read-only; Back/Escape always returns to the main menu, and the window tools
  sit below a rule. Live tests pass: Tools4/4 and browser/Options10/10.
  `content/data_static/version.json` is the single version source; update it
  (and the matching `changelog.json` entry, marked `+`/`-`/`?`) whenever a
  milestone, phase or release status changes. Packaging blocks release until
  its status is `released`. Pre-2.6 changelog entries are reconstructed guesses.
  Full H is not accepted: fresh-load archived persistence, automatic weather/
  context, launcher/den/map-capture and visual/performance gates remain.
- Clothing repeat rules (2026-10-06): placed art has no repeat unless
  `_repeating`; `_notrepeating` suppresses it; new `_sleeve_cuff`/`_sleeves`
  hem placement (`sleeve_cuffs.json`). Published698finishes/2994ownedfiles;
  builder prunes unreferenced caches and unowned staged `catalog_*` files. Static
  suites pass. Follow-up: sleeve canvas is now 112x200 (flames climb from the hem);
  new two-piece `sleeve_cuff_both`/`pants_cuff_both`. Published735finishes/
  3142ownedfiles; static suites pass, live pool9/9; human review pending.
- Launcher follow-up (2026-10-06): user confirmed perfect 3D-sky alignment,
  added invisible G-Man support and saved both launcher scenes. Preserve those
  authored edits. Launcher-only sky inspection now takes off from its authored
  island camera into an eased banking flight; shared pose/PVS, obstruction
  checks and render-scoped selected-sky haze are implemented. Main menu/credits,
  city/den sweep, gameplay weather and baked lighting remain unchanged. Static
  GLua183/0 and mocked-engine Lua flight/fog3786assertions pass; game closed,
  so new live browser cases, route clearance/PVS and motion/haze/performance
  review remain pending. No maps rebuilt; Phase H still unaccepted.
- Latest launcher continuation: user approved flight/haze appearance but reports
  lag. Launcher flight now replaces the main RenderScene (no second panel scene)
  and excludes the menu globe. Automatic profiles tour their four existing
  Day/Overcast/Dusk/Night slots over20seconds; individuals retain10seconds,
  saved choice/serverweather unchanged. GLua183/0 and71mocked tour/render tests
  pass; fresh live tour and matched performance remain pending. User closed
  game and authorized both latest authored launcher builds: preview/city
  VBSP/VVIS/VRAD and staged hashes pass. No world-cell maps regenerated; Phase H
  remains unaccepted.
- Sky retirement (2026-10-06): user requested removing Tropospheric night1
  without diagnosis. Published35imports/420materials;81individuals/18builtins.
  Tropospheric1-3/World'sEnd night slots now use night2; other assignments and
  individual/custom-only JohnTron unchanged. Saved selections/custom slots
  migrate to night2 with custom backup; source/old loose files preserved but
  current sky ownership excludes retired materials from packaging. Catalogue
  2319/2319,GLua183/0,packaging53/53,offline migration90assertions pass.
  Fresh live removal/replacement/migration review remains pending.
- When a milestone runs, phases proceed in order and each phase gets focused static/automated checks as changes land; fix failures before advancing and record static and live results separately. A phase is accepted only on the user's confirmation; a successful map compile alone does not establish in-game acceptance.
- [docs/todo-alpha-2.9.1.md](docs/todo-alpha-2.9.1.md) archives the completed compiler-pool, preset, generation-diagnostics, portal-budget, and test-organization milestone.
- `docs/todo-alpha-2.8.6.md` remains as milestone history and source context for the safe-zone contract and Storm Drain work that landed before the current cycle.
- `docs/todo-alpha-2.8.5.md` and `docs/todo-alpha-2.8.md` are historical context only unless explicitly promoted back into the active tracker.
- When the active milestone changes, update this guide and the root tracker together; do not infer current work from historical phase labels. Archive a completed tracker in `docs/` and re-root its relative links.

## Read First

- [readme.md](readme.md) contains the supported build, staging, in-game, and Walker simulator command sequences.
- [docs.md](docs.md) is the generator reference, including profile behavior, authored tile orientation, Hammer checks, and compile diagnostics.
- [docs/gdd.md](docs/gdd.md) describes intended gameplay behavior. Consult it before changing player progression or survival systems.
- [generator-settings.json](generator-settings.json) is the authoritative configuration schema. Do not infer settings or output paths from filenames.
- [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md) describes multi-tile template work.
- `bin/walker-simulator` is the portable C++ walker project; it stays isolated from Lua and generated assets, and its behavior and commands are documented in the root README.

## Source-First Engine and API Work

- Consult the [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/) for GLua functions, hooks, realms, signatures, return values, prediction, and documented caveats before introducing or changing an unfamiliar API call. Consult the [Valve Developer Community](https://developer.valvesoftware.com/wiki/Main_Page) for Source entities, keyvalues/inputs, materials, Hammer, and compiler behavior. Do not guess API names, flags, entity behavior, or engine limitations.
- When documentation leaves a concrete question unanswered, inspect relevant public [Valve Source SDK 2013 code](https://github.com/ValveSoftware/source-sdk-2013), which includes HL2, HL2:DM, and TF2 game code and tools. It is not the complete engine source or an exact representation of Garry's Mod's engine branch. Use it as evidence with branch/version caveats, not proof of GMod behavior.
- For lighting questions such as what `light_environment` does, distinguish runtime entity behavior from VBSP/VRAD processing and baked BSP lighting; inspect the relevant game/tool implementation where available rather than inferring behavior from an entity name or keyvalue.
- Record the relevant wiki URL or SDK file/revision with a non-obvious finding. If a source is inaccessible, say so; do not claim it was verified. Use known local implementations and a small targeted in-engine probe for remaining GMod-specific uncertainty. Read public sources in place where practical; do not install another SDK, rebuild maps, or copy SDK/Valve assets into this addon merely to answer a reference question.
- Reuse established repository architecture and previously verified findings. Reading the relevant owner before editing is necessary; repeating a project-wide realm audit or prototyping documented standard APIs is not. Feature-specific decisions and uncertain behavior belong at the start of their owning phase, not in a milestone-wide research prerequisite.
- Try publicly available archives before treating an inaccessible live wiki page as a research blocker.


## Runtime Architecture

- Keep Lua realm boundaries explicit: `init.lua` and `sv_*.lua` are server-side, `cl_*.lua` is client-side, and `shared.lua` / `sh_*.lua` run in both realms. Send shared and client files with `AddCSLuaFile`, then `include` files that must execute on the server.
- Preserve the existing Lua style: `//` comments, spaced function calls, four-space indentation in server files, and tabs where an existing shared/client file already uses tabs.
- World data is accessed through `ZM_World`; safe-zone lookup is owned by `ZM_SafeZones`. Use their APIs rather than duplicating coordinate, map-path, or profile resolution logic.
- Server services share small helpers through `ZM_Util` (`gamemode/utils/server.lua`: first human, profile, whole-number checks, console replies, admin gates, command registration). New `zn_test_*` suites use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`). Alias these instead of redefining local copies.
- `cl_atmosphere.lua` is the client facade; `gamemode/atmosphere/cl_core.lua` initializes the environment, weather, puddle, snow, footstep, screen-effect, fog and diagnostic owners before registering callbacks. Preserve the shared snow/puddle deadline, public table identities, emitter ownership and existing render phases. Do not rely on separate `Think` hook ordering. `zombiesim_dev_test_atmosphere_client` runs isolated fixtures and read-only live checks; visual acceptance still requires a fresh client review. See the README's client atmosphere module reference.
- For Lua logic that can run against explicit engine fixtures, reuse `tests/glua/harness.py` and `ZM_TestHarness`; follow the README's **Shared offline Lua fixture harness** workflow. Add a focused regression alongside behavior changes when applicable. Keep mocks feature-specific and deterministic, reject unsupported calls, and never inherit live globals or use catch-all no-ops. Report offline logic, GLua syntax and actual-engine/visual results separately; LuaJIT fixtures are neither a full GLua interpreter nor proof of engine behavior.
- Work that runs behind the loading screen reports progress through `ZM_Loading` (`gamemode/sh_loading.lua`): `Step`, `Begin`/`Finish` (pending then `ok`/`warn`/`fail`/`info`), and `Reset`. Server calls take a player target; client calls are local. Use it for new load-time work, including future online services, instead of custom loading text.
- `sh_music.lua` must load before `sh_static_data.lua`, which builds its registry during include. Music uses the engine `snd_musicvolume` control; Source effects retain native `volume_sfx`/master scaling. Do not multiply master/SFX volume again on Source audio calls.
- Register network strings on the server before sending. Keep player persistence server-only through the SQL helpers and retain profile scoping.
- The future online-services API is maintained separately in the root `api/`
  Git submodule; see [`api/README.md`](api/README.md) for its current project
  behavior. It is not yet integrated with live gamemode features. Before any
  API integration, inspect that README and its repository instructions, define
  the client/server trust boundary and request contract, and keep secrets out of
  the client and source control. Steam OpenID proves browser account ownership,
  not live GMod presence; the API README requires a separate server credential
  for presence reports. Preserve the API submodule's independent history and
  any pre-existing changes; do not modify or commit API implementation work
  unless the task explicitly includes that repository. The submodule's current
  remote is GitLab (`git@gitlab.com:gcnet-uk/games/zombiesim-api`); verify
  `.gitmodules` rather than assuming a hosting provider.
- Treat raw grid coordinates as diagnostics only. Display and manipulate logical world coordinates through `ZM_World`; for a cross-map change, verify persisted `CellX`/`CellY`, safe-zone id, and resolved map path with `zombiesim_player_status` after the destination loads.
- Before changing a request involving a “map,” identify the intended surface: the world-map window, HUD minimap, satellite/level view, or Garry's Mod level transition. Locate its owning module and input binding; ask a focused question when the request does not distinguish them.
- Before adding client-side GLua or Derma calls, confirm the API signature from a compatible local call site or current Garry's Mod documentation. Validate new client scripts for syntax and exercise prompt first-run, decline/reset, and reopening paths.

## Generator And Asset Boundaries

- **CS 1.6 addon permission, 2026-10-10:** the user reports explicit creator
  permission to extract and bundle all assets from Workshop addon `2657591603`
  (archived revision `1637211535`), including its underlying Valve assets, in
  this non-commercial ZombieSim project. Retain the source credits and record
  this as user-confirmed permission, not independently verified licence text.
  Do not repeat the permission question for this exact integration unless the
  scope changes or contradictory evidence appears. This is not a blanket
  public-domain claim about Archive.org or a licence for unrelated Valve assets.

- Hand-authored tile VMFs live in `tiletemplates`; base maps, launcher VMFs (`celltemplates/launchers`), and standalone safe rooms live in `celltemplates`. Edit these source assets, not generated files in `generated/src*`.
- `content/` is distributable addon content only. Keep compiler logs/reports/intermediate BSPs and other developer outputs under `generated/`; launcher compiler output belongs in `generated/launcher_build`, while required packaged BSPs/materials remain under `content/`.
- Treat generated manifests, plans, VMFs, BSPs, staged profile maps, runtime JSON, and map materials as pipeline outputs. Regenerate them with the matching profile rather than hand-editing them.
- Every generator script must resolve settings through `bin/resolve_world_generation_profile.ps1`. Use `-WorldProfile preview` for normal iteration; it is isolated from the production `city` profile.
- Preserve canonical rotations and carpark endcap rules. `bin/carpark_endcaps.psm1` owns carpark cap selection and yaw; do not duplicate or derive it from lane role. Confirm orientation changes in Hammer.
- Before changing a placement or yaw mapping, inspect the canonical authored orientation and the exact generated `func_instance` that fails. Validate all four cardinal outputs plus any affected exceptional recipe in the developer zoo; never apply a global yaw offset from a single screenshot or recipe.
- For a visual placement report, identify the selected instance and express the intended relationship in logical tile coordinates and cardinal directions. If the screenshot does not establish whether a piece should be edge-adjacent or in-line/in-front, ask one focused clarification before changing placement logic.
- Before diagnosing or validating a generated layout, resolve its exact recipe filename from the current matching plan, rebuild that recipe from current inputs, and confirm the inspected VMF's instance name, source template, origin, and angles. Do not infer freshness or behavior from a similarly named recipe or an older zoo output.
- Do not change a native model's `ModelOffset` to correct Backrooms placement. Correct the generator's block-cell placement.
- Standalone safe-zone maps are complete templates copied unchanged. Edit `celltemplates/safezones`, not their generated copies.
- Before changing a placement, orientation, or UI layout direction, restate the intended relationship in logical coordinates and cardinal directions, including whether it is edge-adjacent, in-line, in-front, left, or right. If the visual evidence leaves that relationship ambiguous, ask one focused clarification before editing.
- Treat generated plans, VMFs, BSPs, navmesh outputs, and runtime exports as potentially stale until the current matching input is resolved and the affected output is regenerated. Validate the exact artifact that was produced, not a similarly named or previously inspected file.

## Focused Validation

Keep standalone GLua test suites in `gamemode/tests/`, with their realm prefixes
(`cl_`, `sv_`, or `sh_`). Update `include` and `AddCSLuaFile` paths when adding or
moving suites; retain dependency load order. Shared test-runner utilities stay
in `gamemode/utils/`, offline PowerShell checks in `bin/`, and static-data
fixtures in the root `tests/` folder.

Run PowerShell commands from the repository root. For changes to planning or VMF generation, use the preview pipeline and start with the fast structural check:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

- After structural tile changes, run `./bin/check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData`; inspect affected layouts in Hammer, including generated developer zoos when applicable.
- For planner yaw changes, extend and run focused regressions for the reported recipe and previously correct affected cases before broad regeneration. Building frontage changes must pass `./bin/test_building_frontage.ps1` and `./bin/test_multi_tile_templates.ps1` before refreshing the preview plan and VMFs.
- Only use `-SkipVBSP` with `-SkipRecipeRefresh` when the source VMFs are unchanged from the portal preflight. Review `generated/build_<profile>/compile-report.json` for failed or incomplete stages.
- Builds are incremental: `build_cell_vmfs.ps1` writes a generated VMF or den copy only when its content changed, and `compile_cell_vmfs.ps1` / `check_vis_budgets.ps1` recompile a map only when its BSP is missing or the VMF or any `func_instance` it references (recursively, via `bin/vmf_source_dependencies.psm1`) is newer than the build output. Before a compile, state which maps a source edit affects. Do not pass `-Force` or `-ForcePortalData` for routine rebuilds; reserve them for compiler/config changes or a deliberate clean build.
- A full VVIS/VRAD build and in-game launch are deliberate final checks. Batch related changes before launching Garry's Mod; reload `zn_preview_start` after preview staging or `zn_city_start` after city staging.
- For iterative Lua live checks, use Garry's Mod's available hot-reload workflow instead of closing and relaunching the game. When a clean map/spawn cycle is needed, `changelevel <current-map>` reloads the same map without closing the client; verify the destination and player state before interpreting the result.
- For `cl_*.lua`, camera, Derma, and map-transition changes, parsing or compilation is only static validation. Do not report behavior as verified until the affected input path has been exercised in a running client; otherwise state that an in-game check remains.
- For visual results (fades, camera motion, outlines, prompts, highlights, placement), ask the human at the running client to look and report before building automated probes. Use the bridge for state evidence such as `zombiesim_player_status`, not as a substitute for eyes.
- After any Lua change, run `./bin/test_glua_syntax.ps1` for an offline GLua syntax check. It uses the `gluac.exe` bundled with the GLua Enhanced VS Code extension (Garry's Mod's own `lua_shared.dll`), so `//`, `!=`, `&&`, and `continue` parse correctly. Stock `lua`/`luac` cannot parse GLua. This checks syntax only, not GMod APIs or realms.
- For runtime changes, use a two-part validation matrix: run the narrowest static or automated check first, then exercise the affected in-game command, input path, persistence transition, or client flow. Report static success and live success separately, and explicitly state when live verification remains.
- In long implementation sessions, create or refresh a checkpoint after each subsystem boundary and after a failed validation loop. Record the current hypothesis, exact artifact or command under test, result, and next discriminating check before moving to another subsystem.

## Environment Notes

- **Always launch Garry's Mod for the user** (requested 2026-10-12): do not ask
  them to start it. Use
  `Start-Process 'C:\Program Files (x86)\Steam\steam.exe' -ArgumentList '-applaunch','4000','-console','-disableluarefresh','+gamemode','zombiesim','+map','zn_preview_start'`
  and verify `-disableluarefresh` on the actual `gmod.exe` command line.
  Launching without it lets autorefresh watch this development tree, which
  inflates kernel non-paged memory (observed ~5.2 GiB) and causes startup
  stutter; such samples are not valid performance evidence. With
  `-disableluarefresh`, reload changed Lua via `changelevel <current-map>`.

- The repository is already under Garry's Mod. The active compiler profile resolves `vbsp`, `vvis`, and `vrad` from the game's `bin` directory.
- To find or verify a model or material, list the mounted game VPKs with the installed `GarrysMod\bin\vpk.exe l <path-to-_dir.vpk>` (for example `sourceengine\content_hl2_dir.vpk` or `garrysmod\garrysmod_dir.vpk`) and reference the mounted virtual path. Do not search the user's `addons` folder, and do not extract or copy Valve content into the addon.
- The development command bridge source is `content/data_static/consolecommands.txt`; its acknowledgement is deliberately written outside the repository to Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`.
- Send bridge requests with `./bin/invoke_dev_bridge.ps1 -Command '<cmd>'[, '<cmd>']` instead of hand-written wait loops. It returns the result JSON (exit 0) and waits for the reloaded map after `changelevel`. Exit 2 means the server heartbeat (`data/zombiesim/consolecommands.heartbeat.json`) is stale: the game is paused in the Escape menu or loading, so ask the player before resending. Exit 3 means Garry's Mod is not running; exit 4 means a ticking server ignored the request.
- For cross-map command automation or `buildcubemaps`, first run a one-command in-engine capability probe and verify its bridge acknowledgement. Confirm permissions and persistence before implementing a sequencer; retain a single-step manual command fallback.
- Never invoke `lua_*` commands (including `lua_refresh`) through the development console bridge; Garry's Mod security restrictions block that route. To reload changed Lua during a preview test, use `changelevel <current-map>` after confirming the active profile and map. Do not try alternate bridge/RCON paths for Lua execution or refresh.
- Starting `zn_preview_start` puts the client in the launcher/character main-menu flow, not in deployed gameplay. Wait for any briefings and the character menu, deploy an existing appearance-complete survivor, then enter the intended den or city cell before running gameplay/live checks. Confirm the loaded map and player state after transitions; do not treat a connected menu player as deployed.
- Scripts use `Set-StrictMode` and `$ErrorActionPreference = 'Stop'`. Retain parameter validation, path construction via `Join-Path`, and profile-driven paths. In Windows PowerShell 5.1, use `System.Diagnostics.Process` for monitored compiler processes because `Start-Process -PassThru` can expose an empty `ExitCode`.