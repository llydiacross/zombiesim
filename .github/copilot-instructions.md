# ZombieSim Copilot Instructions

ZombieSim is an installed Garry's Mod gamemode with realm-specific GLua gameplay, a PowerShell pipeline for Source VMF world generation, and an isolated C++ Walker simulator. Work from the repository root unless a command below specifies another directory.

## Start Here

- Read [AGENTS.md](../AGENTS.md) for the active milestone, repository-specific asset boundaries, detailed validation rules, and environment constraints.
- Read [readme.md](../readme.md) for supported in-game, build, staging, test, and Walker commands.
- Read [docs.md](../docs.md) for generator behavior and [docs/gdd.md](../docs/gdd.md) before changing progression or survival behavior.
- Treat the active Alpha tracker named in `AGENTS.md` as authoritative. Do not infer unfinished work from historical trackers or checkpoints.
- Honor explicit user deferrals and tracker constraints. In particular, distinguish implementation completion from static verification, live verification, visual review, and explicitly deferred work.

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

For bridge-driven checks, give every request a fresh `# request:` identifier in `content/data_static/consolecommands.txt`; the acknowledgement is written to Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`. Consult the README for bridge capabilities and safe development probes.

## Project-Specific Conventions

- Preserve existing GLua style: `//` comments, spaced function calls, and four-space indentation in server files; retain tabs in shared/client files that already use tabs.
- Register server network strings before sending messages. Keep client inputs untrusted and validate requests in the owning server service.
- Before adding client GLua or Derma calls, verify the API signature against a compatible local call site or current Garry's Mod documentation.
- Treat generated-world artifacts as potentially stale. Resolve the exact recipe from the current matching plan, regenerate the affected output from current source inputs when permitted, and validate the artifact produced—not a similarly named or older file.
- For placement or orientation changes, establish the intended relationship in logical tile coordinates and cardinal directions. Inspect the canonical authored orientation and the exact failing generated instance; ask for clarification if the intended adjacency or direction is ambiguous.
- Use `bin/resolve_world_generation_profile.ps1` for generator settings and default to the isolated `preview` profile for approved world-generation work. Do not change production `city` outputs during ordinary iteration.
- For mounted Garry's Mod assets, inspect VPK virtual paths with the installed `vpk.exe`; reference mounted paths instead of extracting or copying Valve content into the addon.
- Test runtime behavior in its actual context. For example, city-cell loot activation must be tested in a city cell, not a safe room. Exercise the relevant entity, input, persistence, and transition path rather than treating a service stub or syntax check as proof of live behavior.
- Report validation precisely: list static/test results separately from in-game or visual checks, and state which acceptance items remain unverified or deferred. Do not mark a phase accepted solely because its automated tests pass when required live checks remain.
- Preserve unrelated user work and generated outputs. Before temporarily substituting maps or changing persistent player data for a probe, retain a safe restoration path and verify restoration afterward.
