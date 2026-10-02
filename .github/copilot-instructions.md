# ZombieSim Copilot Instructions

ZombieSim is an installed Garry's Mod gamemode with realm-specific GLua gameplay, a PowerShell pipeline for Source VMF world generation, and an isolated C++ Walker simulator. Work from the repository root unless a command below specifies another directory.

## Start Here

- Read [AGENTS.md](../AGENTS.md) for the active milestone, repository-specific asset boundaries, detailed validation rules, and environment constraints.
- Read [readme.md](../readme.md) for supported in-game, build, staging, test, and Walker commands.
- Read [docs.md](../docs.md) for generator behavior and [docs/gdd.md](../docs/gdd.md) before changing progression or survival behavior.
- Treat the active Alpha tracker named in `AGENTS.md` as authoritative. Do not infer unfinished work from historical trackers or checkpoints.
- Honor explicit user deferrals and tracker constraints. In particular, distinguish implementation completion from static verification, live verification, visual review, and explicitly deferred work.
- When asked to continue milestone work, read the latest relevant checkpoint as well as the active tracker, then resume at the first unfinished acceptance item. Preserve explicit deferrals and do not repeat completed work unless new evidence shows a regression.
- Follow the active tracker's phase order. Run each phase's relevant static/automated checks as changes land and fix failures before taking on more feature work; do not save these checks for final integration.

## Architecture

- `gamemode/init.lua` and `sv_*.lua` are server-side; `cl_init.lua` and `cl_*.lua` are client-side; `shared.lua` and `sh_*.lua` run in both realms. Send client/shared files with `AddCSLuaFile` and include server code on the server.
- Gameplay services are server-authoritative. Shared static registries load definitions from `content/data_static/`; persistence is server-only through the SQL helpers. Keep related writes atomic and retain profile scoping.
- `ZM_World` owns runtime world-data and map resolution; `ZM_SafeZones` owns safe-zone lookup. Use these APIs rather than reconstructing coordinates, profiles, or map paths locally.
- `ZM_Util` (`gamemode/utils/server.lua`) provides shared server command helpers. New gameplay test suites should use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`) rather than duplicating test-runner and reporting logic.
- The Walker simulator in `bin/walker-simulator` is an independent C++ population system. Its worker owns simulation state; GLua consumes published snapshots and queues commands. Keep this project isolated from Lua gameplay and generated world assets.
- Authored VMFs and templates are source assets. `generated/` contains build products and diagnostics; `content/` contains distributable addon files. Never hand-edit generated manifests, plans, VMFs, BSPs, navmeshes, runtime exports, or map materials.

## Build and Test

Run PowerShell commands from the repository root.

### GLua syntax

After any Lua change, run:

```powershell
.\bin\test_glua_syntax.ps1
```

This is a syntax check using Garry's Mod's GLua parser; it does not verify realms, Garry's Mod API behavior, or runtime flows.

### Focused world-generation regressions

Use only the relevant focused scripts for the change. For example, building frontage changes require both:

```powershell
.\bin\test_building_frontage.ps1
.\bin\test_multi_tile_templates.ps1
```

For planner or VMF-generation changes, follow the preview workflow and validation gates in [AGENTS.md](../AGENTS.md) and [readme.md](../readme.md). Check the active tracker for any world-generation freeze or approval requirement first. Do not regenerate maps for Lua-only changes.

### Walker simulator

From `bin/walker-simulator`:

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
ctest --preset test-mingw-debug --output-on-failure
```

### In-game service suites

Run the relevant `zn_test_*` command in an admin console or through the development command bridge. For example, run just the inventory suite with:

```text
zn_test_inventory
```

Available suites include `zn_test_static_data`, `zn_test_weapon_catalog`, `zn_test_inventory`, `zn_test_loot`, `zn_test_loot_spots`, `zn_test_enemies`, `zn_test_bosses`, `zn_test_crafting`, `zn_test_implants`, `zn_test_professions`, `zn_test_mastercraft`, and `zn_test_trading`. Each command runs that suite's cases, writes its result under Garry's Mod `DATA` at `data/zombiesim/`, and emits a structured bridge report.

For bridge-driven checks, use `.\bin\invoke_dev_bridge.ps1 -Command '<cmd>'`; it writes a fresh `# request:` identifier to `content/data_static/consolecommands.txt` and returns the acknowledgement from Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`. Exit code 2 means the server heartbeat is stale (game paused in the Escape menu or loading): ask the player rather than waiting. Consult the README for bridge capabilities and safe development probes.

### Live GMod testing and reloads

- Never send `lua_*` commands (including `lua_refresh`) through the development console bridge. Garry's Mod security restrictions block that path; do not try alternate bridge or RCON routes for Lua execution or refresh.
- To load changed Lua during a preview test, use `changelevel <current-map>` after confirming the active profile and map. Keep production `city` untouched.
- `zn_preview_start` first opens the launcher/character main-menu flow. Wait for briefings and the character menu, deploy an existing appearance-complete survivor, and only then transition to the intended den or city cell for gameplay checks. A connected player at the launcher is not yet deployed; verify the destination and player state after transitions.
- Before changing transition/loading UI, map the full lifecycle—departure fade, arrival hold, ordinary cell travel, den entry/exit, and client/server work—to each state's title, progress/log visibility, and timing. Keep the departure and arrival states distinct where their requirements differ, and test the actual transition paths.
- When a gate appears not to change maps, compare source and destination logical cell coordinates as well as the resolved map path. Multiple cells may share a recipe BSP, so verify the persisted destination coordinates and ensure gate travel still reloads when the BSP filename is unchanged.
- When validating door or gate markers after a test suite reinitializes services or removes template-local entities, reload independently before treating published marker counts as normal live state. Check the transformed entities and published positions after the clean load; entity removal may be deferred until the end of the frame.

## Project-Specific Conventions

- Preserve existing GLua style: `//` comments, spaced function calls, and four-space indentation in server files; retain tabs in shared/client files that already use tabs.
- Register server network strings before sending messages. Keep client inputs untrusted and validate requests in the owning server service.
- Before adding client GLua or Derma calls, verify the API signature against a compatible local call site or current Garry's Mod documentation.
- Use the [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/) routinely for GLua hooks/functions, realms, prediction, signatures, and caveats, and the [Valve Developer Community](https://developer.valvesoftware.com/wiki/Main_Page) for Source entities, keyvalues/inputs, Hammer, materials, and compilers. Consult the relevant pages before relying on an unfamiliar or uncertain behavior; do not guess.
- When the wikis do not settle an engine question, inspect relevant public [Source SDK 2013](https://github.com/ValveSoftware/source-sdk-2013) HL2/HL2:DM/TF2 game or tool source. This is not the full engine source or the exact GMod branch. For `light_environment`, distinguish runtime entity code, lighting compiler processing, and baked lighting. Cite the page or SDK file/revision, note branch differences or inaccessible sources, and use a focused GMod probe only for the remaining uncertainty. Do not copy Valve source/assets into the addon or install an SDK just for routine reference.
- Reuse documented architecture and historical evidence rather than repeatedly planning broad realm/API audits. Check the actual module being changed; resolve feature-specific decisions in that feature's phase before implementation.
- For cursor, mouse-focus, crosshair, or camera changes, trace which UI or camera system owns each state instead of treating them as interchangeable. Verify dialog opening and every close path, plus den entry and exit, in a running client.
- Treat generated-world artifacts as potentially stale. Resolve the exact recipe from the current matching plan, regenerate the affected output from current source inputs when permitted, and validate the artifact produced—not a similarly named or older file.
- For placement or orientation changes, establish the intended relationship in logical tile coordinates and cardinal directions. Inspect the canonical authored orientation and the exact failing generated instance; ask for clarification if the intended adjacency or direction is ambiguous.
- Use `bin/resolve_world_generation_profile.ps1` for generator settings and default to the isolated `preview` profile for approved world-generation work. Do not change production `city` outputs during ordinary iteration.
- For mounted Garry's Mod assets, inspect VPK virtual paths with the installed `vpk.exe`; reference mounted paths instead of extracting or copying Valve content into the addon.
- Test runtime behavior in its actual context. For example, city-cell loot activation must be tested in a city cell, not a safe room. Exercise the relevant entity, input, persistence, and transition path rather than treating a service stub or syntax check as proof of live behavior.
- For client meshes, materials, textures, or render hooks, follow [client-rendering.instructions.md](instructions/client-rendering.instructions.md). It covers zero-count `mesh.Begin` crashes, static `IMesh` hook and depth placement, shader limits for vertex alpha, putting textures in the `CreateMaterial` keyvalues, and garbage from rebuilds.
- For renderer or other visual presentation changes, inspect the affected surface in a running client and check the relevant mode and option settings. A successful syntax check, build, or automated test does not verify visual appearance.
- Report validation precisely: list static/test results separately from in-game or visual checks, and state which acceptance items remain unverified or deferred. Do not mark a phase accepted solely because its automated tests pass when required live checks remain.
- Preserve unrelated user work and generated outputs. Before temporarily substituting maps or changing persistent player data for a probe, retain a safe restoration path and verify restoration afterward.
