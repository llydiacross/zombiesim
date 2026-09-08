# Preview Gamemode Plan

## Purpose

`zn_preview` is the test-focused ZombieSim profile. It must remain a normal playable world: players load the preview runtime index, spawn through the usual safe-zone flow, and use the same cell transition logic as the city profile. Preview adds controlled developer tools around that gameplay loop; it does not fork the core rules or bypass the world manifest.

The initial preview experience has two visible additions:

- A preview-tools pane in the world map for selecting and jumping to any logical cell.
- A radial quick menu on Tab that opens Inventory, Scoreboard, or Options instead of the default scoreboard.
- A preview admin console for controlled player-attribute and player-record inspection/editing.

## Locked Decisions

- Preview map teleport is a single-human-player test-session action. The server rejects it when more than one human player is connected or map-batch maintenance is active. A future group transition must be designed as an atomic, separately confirmed action; it is not an implicit fallback.
- Preview player attributes are isolated from city data. The persistence migration changes attribute identity from SteamID to SteamID plus profile, copies legacy attribute rows into `city`, and creates preview records from an explicit preview baseline on first use. Preview edits never mutate city attributes.
- The Preview Data Console reads and edits preview records only in its initial release. City inspection and editing are out of scope for a preview testing tool and require a later, separately authorized maintenance feature.
- Every editable record has a monotonically increasing revision and update timestamp. An accepted mutation writes the record and its persistent audit event in one SQLite transaction before any live-player state changes.
- Preview capabilities are server-issued. The client receives a capability bitmask for display, but the server independently validates every request.
- The Tab radial menu is player-facing and ships in both `preview` and `city`. Preview administration is never a radial destination.
- The first teleport targets ordinary city-cell maps only. A safe-zone cell may be selected for diagnostics, but jumping directly into a standalone den is deferred until its own arrival semantics are specified.

## Scope And Guardrails

### Profile Gate

- Treat preview mode as `ZM_World.ActiveProfile == "preview"`, selected by `zn_preview` or a `zn_world_profile` entity.
- Create preview UI only after the active world data is loaded.
- Never show preview tools in the `city` profile, including after a player moves between a den and a cell map.
- Keep server authority separate from the UI gate. A manually invoked client console command or forged network request must not unlock preview actions in city.

### Authority And Session Safety

- Gate all preview tooling behind a server-owned `zombiesim_preview_tools_enabled` convar as well as the active preview profile. The capability defaults to disabled on dedicated/public deployments and is explicitly enabled for local test servers.
- Use capability tiers: preview diagnostics require an admin capability; teleport requires a preview operator capability; player-data writes require a preview data-admin capability. The initial policy maps diagnostics/operator to `IsAdmin()` and data-admin to `IsSuperAdmin()`, with server configuration reserved for a later integration with an established admin system.
- The server validates the active profile, caller permission, requested cell, and resolved map path before changing anything.
- A cell jump uses the real cell map transition path; it must not simply move the player with `SetPos`.
- Record the requested logical cell coordinates through `Player:SetWorldCell` before changing level. This uses the existing safe-zone clearing, persistence, replication, and atmosphere update path.
- A Garry's Mod `changelevel` affects the entire server session. The initial implementation permits teleport only when the requester is the sole connected human, and its confirmation must state that constraint.
- Reject requests while a server-wide preview transition lock is active. The lock spans confirmation acceptance through the new map's world-profile initialization; it is not merely a per-requester debounce.
- Require a staged target BSP, a valid manifest map path, and an inactive map-maintenance batch before accepting a jump. Debug teleport intentionally permits valid blocked cells so inaccessible maps can be tested.
- Never expose raw SQL execution, database paths, database credentials, or an unrestricted table browser to game clients. The preview data tools use purpose-built server APIs with an allowlist of readable fields and editable fields.
- Every persisted edit is attributable: persist acting admin, target SteamID, profile, field changes, old values, new values, timestamp, request id, revision, and result in an append-only audit table.

### Persistence Model

- The current backend is Garry's Mod SQLite through `gamemode/utils/sql.lua`; this is a MySQL-like management interface, not a requirement to migrate the game to MySQL.
- Migrate `player_attributes` to a SteamID-plus-profile primary key. Preserve each legacy row as the player's `city` attributes, then create a separate `preview` row from a server-defined baseline when it is first required.
- `player_data` already has a SteamID-plus-profile identity. Add `Revision` and `UpdatedAt` columns to it and to profile-scoped attributes with additive, checked schema migrations.
- Add a persistent `preview_audit_log` table with a stable event schema. Record data changes in the same SQLite transaction as their record revision update; rollback both on failure.
- Use compare-and-swap updates: the client supplies the revision it read, the server writes only when it still matches, then increments it. A conflict returns the current server record for explicit reload/merge.
- Centralize typed field specifications, clamping, and validation in a server-side repository service. Its setters return `true` or `false, error`, rather than silently dropping failed `sql.Query` results.
- All accepted online-player writes persist first, then update the live entity, normalize derived state such as maximum stamina and current stamina, replicate NW values, and send the owning-client refresh signal.
- Do not use the UI to alter world-generation JSON, schema definitions outside approved migrations, or unknown database tables. Those remain file/build workflow changes with source control review.

## Feature 1: Preview Map Tools

### User Flow

1. A preview operator loads `zn_preview` on an enabled single-human test server and opens the existing world map with `zombiesim_map`.
2. The map retains its existing layer, places, inspector, render-mode, selection, and waypoint features.
3. A third sidebar tab, `PREVIEW`, appears only for preview admins.
4. Selecting a cell on the map updates the cell inspector and the preview pane's destination summary.
5. The pane provides direct grid-coordinate inputs as an alternative to clicking the map.
6. The operator chooses `Teleport`, confirms the one-player map transition, and receives a result message.

### Pane Contents

Keep this as a compact utility pane in the existing map sidebar, not a second full-screen window:

- Current logical world cell and resolved map name.
- Selected logical cell, world coordinates, grid coordinates, recipe map name, and safe-zone/landmark summary.
- Integer X and Y inputs using logical world coordinates. Invalid or out-of-range coordinates show an inline error and disable teleport.
- `Focus selected` and `Focus player` controls; use the map's existing focus behavior.
- `Teleport` control, disabled until a valid ordinary city cell is selected, its BSP is staged, the map batch is idle, exactly one human is connected, and the server reports preview-operator eligibility.
- Confirmation modal showing the cell coordinate, resolved map path, and single-human-session requirement before sending the request.
- A small result/status line for accepted, rejected, or failed requests. It should never claim that a map transition succeeded until the next map has loaded.

### Map Integration

- Extend [gamemode/cl_world_map.lua](gamemode/cl_world_map.lua) rather than creating a competing map frame. It already owns selected cells, cell inspection, map-to-cell hit testing, profile-aware persistence, and focus controls.
- Add a narrow preview-only sidebar view alongside `LAYERS` and `PLACES`.
- Keep selections profile-scoped through the existing persistent-state helpers. Do not retain a preview cell when a city profile loads.
- Make the panel resilient when the world index, selected cell, local player, or rendered material is unavailable.

### Client/Server Contract

- Introduce a dedicated network message such as `ZM.RequestPreviewTeleport`; do not overload normal gameplay transition messages. Register an authoritative capabilities message and a transition-status message alongside it.
- Client payload is one unsigned cell id bounded by the loaded world grid. Prefer the id from `ZM_World:GetCellById` because it identifies the exact exported logical cell without client-side map-name inference.
- Server response includes a request id, success/rejection code, message, requested cell id, resolved map path, and current capability state for UI status.
- Server handler validates the preview profile, enabled capability, operator permission, one-human-session condition, inactive map batch, transition lock, manifest cell, ordinary-city-cell target, and staged BSP. It resolves coordinates with `GetWorldCoordinates`, resolves the map with `GetMapPath`, then calls `SetWorldCell` before queueing the server-wide transition.
- Add a short server-side request cooldown and one server-wide transition lock. Do not rely on a confirmation dialog or client state to serialize requests.
- Log each accepted preview teleport with the admin identity, source coordinates, target coordinates, and target map to make test sessions reproducible.

### Initial Diagnostics In The Pane

Ship only high-value read-only diagnostics with the teleport tool:

- Active profile, runtime-index path, grid dimensions, and loaded-map name.
- Player logical coordinates, selected cell id, and resolved recipe map name.
- Cell environment, district, radiation, danger, transport summary, and route summary, reusing existing inspector data.
- Recipe-sharing count from `ZM_World:GetCellsForMap` so testers can see when multiple logical cells use one BSP.
- A world-integrity row showing the active profile, loaded runtime-index path, current map, expected map, transition-lock state, and staged-target status.

Leave entity inspection, live spawn controls, AI controls, standalone-den teleporting, and arbitrary console execution out of the first pass. They need explicit testing contracts and should not accumulate accidentally in a general debug panel.

## Feature 2: Preview Player And Data Console

### Purpose

Provide a compact, operational admin screen for creating deterministic preview test characters, inspecting preview-only saved state, and correcting records during testing. It should feel like a database administration tool - searchable tables, field-level editing, explicit saves, audit visibility, and record snapshots - while remaining a game UI backed by narrow server endpoints.

Open the console from the preview map pane and a preview-only console command. It is not a radial-menu destination because it is an administrative tool rather than a normal player action.

### Player Attribute Editor

- Start with the local player and connected-player list; add offline preview-record lookup by exact SteamID after the online flow is stable.
- Present base attributes in a two-column editable grid: Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, and Mechanics.
- Use numeric input controls with an explicit configured minimum and maximum per field. Reject non-integers, out-of-range values, unknown field names, and malformed SteamIDs on the server.
- Show derived values affected by the draft, beginning with maximum stamina. Clearly distinguish saved values, unsaved draft values, and live entity values.
- Support `Apply`, `Revert`, and a named preset selector such as `Fresh character`, `Combat`, `Crafting`, and `Survival`. Presets are server-defined data, displayed before application, and recorded as their resolved field changes.
- Applying updates a preview-scoped attribute record only. For an online target it persists first, updates the target's in-memory `Attributes`, clamps derived survival state, updates network values, and sends the owner the existing attribute refresh message. Do not require the target to reconnect.
- Put destructive reset actions behind a confirmation that names the target, preview profile, selected baseline, and any snapshot that can restore the previous record.

### Player Data Editor

- Show one record per SteamID in the preview profile with filterable columns: SteamID, XP, level, max level, difficulty, skill points, cell coordinates, current safe-zone id, health, stamina, hunger, thirst, revision, update time, and online status.
- Keep reads paginated and filtered server-side. Initial filters are exact SteamID and connected-player state; all results are constrained to preview profile server-side.
- Edit only allowlisted data fields through typed controls. Coordinate edits must resolve to a valid preview cell; safe-zone ids must resolve to the preview runtime index.
- When editing an online player, persist first, then update the live entity, normalized survival state, network values, client data refresh, and atmosphere profile together. Do not silently edit a database row while leaving gameplay state stale.
- When editing an offline player, persist only the preview record and label it `saved, not live`.
- Include a row detail view with explicit `Save changes`, `Discard draft`, and `Reload from server` actions. Do not save per keystroke.
- Add `Create snapshot` and `Restore snapshot` actions. A restore always shows a field-level diff and confirmation; initial bulk editing and arbitrary SQL remain out of scope.

### Administration UI Layout

- Use a single resizable `DFrame` with `PLAYERS`, `ATTRIBUTES`, `PROGRESSION`, `SNAPSHOTS`, and `AUDIT` tabs. Use dense table rows for scanning; do not nest card panels inside cards.
- The Players tab provides search, online status, and a selected-target header marked `PREVIEW DATA`.
- The Attributes and Progression tabs edit the selected target's preview-scoped record and show its record revision, saved state, and current draft.
- The Snapshots tab manages named preview snapshots for the selected player and supports an explicit compare-before-restore flow.
- The Audit tab is an append-only, persisted view of preview-tool mutations, with filtering by actor, target, action, and request id.
- Add a clear read-only/disabled state for a non-admin, city profile, missing database, unavailable target, concurrent edit, or pending map transition.
- Use existing ZombieSim Derma styling and make keyboard navigation, Esc-to-close, and narrow-resolution layouts deliberate test cases.

### Server Contracts And Concurrency

- Use separate messages for player-record search, record read, attribute update, player-data update, preset application, snapshot operation, and audit-page query. Each handler validates the server-issued data-admin capability before processing its payload.
- Keep request payloads small and bounded: paginated query filters, a SteamID target, a required preview profile supplied by the server rather than the client, an expected revision, and an allowlisted field-change table with bounded string lengths and numeric ranges. Serialize fields explicitly rather than using unbounded `net.WriteTable` payloads.
- Return a record revision with each read. Reject saves when the target changed since the UI loaded it, then return the current server record for explicit reload/merge rather than silently overwriting another admin's work.
- Perform one validated SQLite transaction for each accepted edit: compare revision, write the updated record, increment revision, append its audit event, and commit. Report database errors to the requester and leave the live entity unchanged when persistence fails.
- Provide a server console fallback for high-priority recovery, using the same validation and audit helper as the UI. Do not create a parallel, less-safe write path.

### Backend Evolution

- Keep UI services behind repository functions such as `ZM_QueryPreviewPlayers`, `ZM_GetPreviewPlayerRecord`, `ZM_UpdatePreviewPlayerRecord`, and `ZM_CreatePreviewSnapshot`; do not couple VGUI code to `sql.Query`.
- These functions initially wrap the existing SQLite helpers. A future MySQL migration can provide the same service interface without changing clients or relaxing authorization.
- Any actual MySQL support needs a separate deployment plan covering a server-only driver, connection secrets outside the addon, prepared statements, migrations, backups, connection recovery, and least-privilege database credentials.

## Feature 3: Tab Radial Quick Menu

### Interaction

- Override the gamemode scoreboard show/hide hooks only after the preview tools work. Tab opens a centered radial menu in both profiles; it is a player-facing replacement for the default scoreboard, not a preview capability.
- The player holds Tab to display three equally sized wedges: `Inventory`, `Scoreboard`, and `Options`.
- Mouse direction highlights one wedge; releasing Tab activates the highlighted destination. Releasing without a highlighted wedge or pressing Escape closes the menu without action.
- The menu captures the cursor only while visible, closes when the player dies or the game UI takes focus, and preserves normal keyboard input after it closes.
- Add a console command for opening the radial menu during testing, but do not make it the primary player flow.

### Destination Contracts

- `Inventory`: open the future inventory frame. Until an inventory UI exists, show a deliberate unavailable state rather than a blank panel or a placeholder implementation.
- `Scoreboard`: open a dedicated scoreboard frame. It replaces the default scoreboard behavior; player list, ping, health/status, and role data are specified when that frame is implemented.
- `Options`: open a ZombieSim options frame for client preferences such as map layers, HUD choices, and future accessibility controls. Persist client-only preferences with cookies or convars, never the server player-data table.
- Each destination is a named `Open`/`Toggle` API. The radial menu dispatches to these APIs and does not own the screens' data or layout.

### Implementation Shape

- Add a focused client module, for example `gamemode/cl_quick_menu.lua`, and include/distribute it from `cl_init.lua` and `init.lua`.
- Register `GM:ScoreboardShow` and `GM:ScoreboardHide` in the quick-menu module so the replacement is isolated from HUD and map code.
- Use a custom painted `DPanel` with deterministic wedge hit testing and explicit mouse capture. Avoid a row of buttons disguised as a radial menu.
- Use the existing `ZombieSim` Derma skin and palette. The radial menu should be legible over gameplay without looking like a separate application.
- Provide `ZM_Inventory:Open`, `ZM_Scoreboard:Open`, and `ZM_Options:Open` ownership points before connecting the final actions. Modules that do not yet exist remain planned dependencies rather than silent failures.
- Add a small shared UI coordinator that owns exclusive modal focus and screen-clicker state. World map, preview console, confirmation dialogs, radial menu, and future frames register with it and close transient UI after a new map profile loads.

## Phased Delivery

### Phase 0: Data Isolation, Capability, And UI Foundations

- Add a small shared `ZM_Preview` capability API, server-owned enablement convar, capability bitmask response, and server-side authorization helpers.
- Build additive SQLite migrations for profile-scoped attributes, record revisions, update timestamps, and persistent preview audit events. Copy legacy attributes into `city`; use an explicit preview baseline on first preview load.
- Refactor persistence through typed repository services with checked query results, compare-and-swap revisions, transaction-backed audit writes, and live-state synchronization only after commit.
- Add a shared client UI coordinator for exclusive modal ownership, cursor state, and cleanup after profile/map reload.
- Validate `zn_preview` selects the preview runtime index and capability state, while `zn_start` exposes neither preview controls nor preview data.

### Phase 1: Read-Only Preview Map Pane

- Add the conditional `PREVIEW` sidebar tab to the existing world map.
- Display current/selected cell diagnostics and coordinate inputs.
- Reuse map selection, focus, world lookup, and inspector formatting without changing normal map controls.
- Include world-integrity and target-BSP status rows.
- Test invalid cells, a missing runtime index, a city-profile switch, disabled tooling, each capability tier, and narrow screen sizes.

### Phase 2: Authoritative Cell Teleport

- Add the confirmation dialog and request/response flow.
- Implement server-side target resolution and transition-state updates through `SetWorldCell` and one server-wide transition lock.
- Reject a second human player, active map batch, invalid/stale manifest, unstaged BSP, standalone-den target, unauthorized requester, repeated request, and city-profile request.
- Test valid world-edge, shared-recipe, safe-zone-cell, and blocked-cell targets in a one-human session. Test every rejection path in a two-human session without changing player persistence.
- Verify the destination map loads with the requested logical coordinates and matching atmosphere, HUD, world map location, and persistent player data.

### Phase 3: Read-Only Player Console

- Implement server-authorized player search, filtered/paginated record reads, and a read-only player detail view.
- Verify that non-admins, city-profile clients, disabled-tooling clients, invalid SteamIDs, and schema-unavailable servers receive no sensitive record data.
- Test SQLite failure handling and disconnected/connecting target players without leaving stale selection state in the UI.

### Phase 4: Attribute And Player-Data Editing

- Add preview attribute and progression drafts, server-defined presets, validation, confirmation, revision checking, persistent audit events, snapshots, and live-player synchronization.
- Add typed progression/survival edits with preview-cell and preview-safe-zone validation.
- Test online and offline preview targets, profile isolation from city, conflicts between two data admins, invalid values, database write failure, snapshot restore, and reconnect persistence.

### Phase 5: Radial Shell

- Implement Tab hold/release behavior, wedge selection, cursor lifecycle, cancellation, and controller-safe fallback behavior.
- Wire the Scoreboard wedge first because it can be delivered as a self-contained UI.
- Test the UI while the world map is open, chat is focused, a Derma dialog is open, the player is dead, and a map load is pending.

### Phase 6: Inventory, Scoreboard, And Options Screens

- Define and build the actual destination frames behind the radial APIs.
- Add client preference persistence and clear resets for options.
- Make the radial wedges available only when their destination is functional; unavailable destinations remain visible but non-activating with a concise tooltip during development.

### Phase 7: Test Scenarios And Expanded Preview Tests

- Add server-defined named test scenarios that combine a preview destination, a player preset, and an optional restorable snapshot. Store versioned shared scenarios separately from personal/ad hoc snapshots.
- Add opt-in read-only panels for transition graph inspection, portal/map build status imported from generated data, active atmosphere data, and test-session notes.
- Add automated Lua-level validation for profile gating, server request rejection, cell resolution, and radial lifecycle behavior.
- Document each tool's authority, network messages, persistence effects, and cleanup behavior in [readme.md](readme.md).

## Acceptance Criteria

- `zn_preview` reaches the same opening spawn flow as before and loads `zombiesim_world_preview.json`.
- Preview admins can select any valid logical cell from the world map and request a confirmed transition to its resolved map.
- A teleport to a cell sharing a recipe BSP still preserves the selected logical coordinates, rather than treating the BSP name as cell identity.
- Teleport is rejected without mutation unless the requester is the sole human player, the target is an ordinary staged city-cell BSP, preview tools are enabled, and map-batch maintenance is idle.
- City sessions cannot display preview teleport controls or execute preview teleport requests.
- Invalid, unauthorized, stale, or repeated teleport requests leave player coordinates and persistent data unchanged.
- Preview admins can inspect and edit only allowlisted player attributes and profile data through explicit drafts, validation, confirmations, and server responses.
- Preview attribute and player-data edits are isolated from city records and visibly identify their preview scope.
- Failed, conflicting, malformed, non-admin, or city-profile data requests reveal no unintended data and leave database rows plus live player state unchanged.
- Successful online-player edits commit their record revision and persistent audit event before they update replicated fields or refresh the owner's client view.
- Tab no longer opens the default scoreboard. Holding Tab shows a usable three-way radial menu, releasing a selected wedge opens exactly one owned destination, and cancelling leaves no cursor or focus leak.
- The normal world map, map layers, landmarks, waypoints, and city profile remain functional.

## Validation Checklist

- Run Lua syntax/diagnostic checks on every touched client, shared, and server module.
- Exercise preview and city launchers in a listen server, then repeat preview teleport authorization with a second non-admin client.
- Capture test cases in a small manual checklist: spawn, map open, map selection, coordinate lookup, cancelled jump, accepted jump, two-human rejection, map-batch rejection, invalid request, city rejection, and Tab menu lifecycle.
- Test database-console reads and writes with an online data admin, online non-admin, offline target, preview records, malformed filters, conflicting edits, validation errors, forced persistence failures, and profile isolation from city.
- Confirm the editor accurately distinguishes preview attributes, preview player data, saved state, draft state, live state, revision conflicts, and snapshot diffs.
- Test 16:9, 4:3, and narrow resolutions for the sidebar pane and radial menu.
- Confirm there are no client errors during level change and no stale Derma frames after reload.

## Open Product Decisions

- Which future diagnostics deserve their own scoped tools rather than being added to the map pane.
- Which explicit ranges and presets best support testing without hiding balance problems.
- Whether a future atomic group-transition mode should require every connected player to opt in, or allow the server owner to force it after a countdown.
- Which shared test scenarios should be versioned with the gamemode, and how long personal preview snapshots should be retained.