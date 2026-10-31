local Contract = include("prefabs/sh_contract.lua")
local EditorMap = include("prefabs/sh_editor_map.lua")(Contract)
local PrefabLoot = include("prefabs/sv_loot.lua")(ZM_StaticData)
local ParticleCatalog = include("prefabs/sh_particle_catalog.lua")(file, util, Contract)
local function validateContent(document)
    local ok, problem = PrefabLoot.Validate(document)
    if not ok then return false, problem end
    ok, problem = ParticleCatalog.Validate(document)
    if not ok then return false, problem end
    return ZM_PrefabGuardConfig.ValidateDocument(document)
end
local Storage = include("prefabs/sv_storage.lua")(file, util, Contract, util.IsValidModel, validateContent)
ZM_PrefabEditor = ZM_PrefabEditor or {}
local Editor = ZM_PrefabEditor
Editor.OpenedId, Editor.OpenedIds = nil, {}

local sessionPath = "zombiesim/prefab_editor_session.json"
local sessionPendingPath = "zombiesim/prefab_editor_session.pending.json"
local sessionBackupPath = "zombiesim/prefab_editor_session.backup.json"
local requestMessage = "ZM.PrefabEditorRequest"
local responseMessage = "ZM.PrefabEditorResponse"
local maximumPayload = 60000
Editor.EditorMapSession = game.GetMap() ~= "zn_preview_start" and file.Exists(sessionPath, "DATA")

util.AddNetworkString(requestMessage)
util.AddNetworkString(responseMessage)

local function reply(target, action, success, message, value, requestId)
    local encoded = ""
    if value ~= nil then encoded = util.TableToJSON(value, false) end
    if type(encoded) ~= "string" or #encoded > maximumPayload then
        success, message, encoded = false, "Prefab response is too large to send.", ""
    end
    net.Start(responseMessage)
        net.WriteString(action)
        net.WriteBool(success)
        net.WriteString(message or "")
        net.WriteString(encoded)
        net.WriteString(requestId or "")
    net.Send(target)
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function readSession()
    if not file.Exists(sessionPath, "DATA") then return nil, "No prefab editor session exists." end
    local contents = file.Read(sessionPath, "DATA")
    local session = type(contents) == "string" and util.JSONToTable(contents) or nil
    if type(session) ~= "table" or session.schemaVersion ~= 1 or session.profile ~= "preview"
        or type(session.owner) ~= "string" or not string.match(session.owner, "^%d+$")
        or (session.fixture ~= nil and type(session.fixture) ~= "boolean")
        or (session.openId ~= nil and not Contract.IsValidId(session.openId))
        or (session.map ~= nil and not EditorMap.IsValidName(session.map))
        or (session.previousMap ~= nil and not EditorMap.IsValidName(session.previousMap))
        or (session.cellId ~= nil and (not EditorMap.IsValidCellId(session.cellId)
            or not EditorMap.IsValidTile(session.tileX) or not EditorMap.IsValidTile(session.tileY)))
        or (session.cellId == nil and (session.tileX ~= nil or session.tileY ~= nil))
        or (session.previousCellId ~= nil and (not EditorMap.IsValidCellId(session.previousCellId)
            or not EditorMap.IsValidTile(session.previousTileX) or not EditorMap.IsValidTile(session.previousTileY)))
        or (session.previousCellId == nil and (session.previousTileX ~= nil or session.previousTileY ~= nil)) then
        return nil, "Prefab editor session is invalid; inspect " .. sessionPath .. " before continuing."
    end
    if session.transferToken ~= nil then
        local valid = EditorMap.ValidateRequest({ map = session.map, cellId = session.cellId,
            token = session.transferToken, openIds = session.openIds })
        if not valid or session.fixture == true or not session.previousMap or not finite(session.transferSequence)
            or session.transferSequence < 1 or session.transferSequence ~= math.floor(session.transferSequence) then
            return nil, "Prefab editor map-switch session is invalid; inspect " .. sessionPath .. " before continuing."
        end
    elseif session.openIds ~= nil then
        local valid = EditorMap.ValidateRequest({ map = session.map, cellId = session.cellId,
            token = "session", openIds = session.openIds })
        if not valid or session.fixture == true then
            return nil, "Prefab editor open-tab session is invalid; inspect " .. sessionPath .. " before continuing."
        end
    end
    return session
end

local function writeSession(session)
    if file.Exists(sessionPendingPath, "DATA") or file.Exists(sessionBackupPath, "DATA") then
        return false, "A previous editor session update needs recovery before switching maps."
    end
    local encoded = util.TableToJSON(session, true)
    if type(encoded) ~= "string" then return false, "Could not encode the editor session." end
    if not file.Write(sessionPendingPath, encoded) or file.Read(sessionPendingPath, "DATA") ~= encoded then
        return false, "Could not write or verify the pending editor session."
    end
    if not file.Rename(sessionPath, sessionBackupPath) then
        return false, "Could not preserve the current editor session; inspect the pending session file."
    end
    if not file.Rename(sessionPendingPath, sessionPath) then
        if not file.Rename(sessionBackupPath, sessionPath) then
            return false, "Editor session update failed; recover its backup and pending files."
        end
        return false, "Editor session update failed; the original session was restored."
    end
    if not file.Delete(sessionBackupPath) then
        ErrorNoHalt("[ZombieSim] Prefab editor: previous session backup could not be removed.\n")
    end
    return true
end

local initialSession = Editor.EditorMapSession and readSession() or nil
Editor.LoadedTransferToken = initialSession and initialSession.transferToken or nil
Editor.LoadedTransferSequence = initialSession and initialSession.transferSequence or nil
if initialSession and initialSession.openIds then
    for _, id in ipairs(initialSession.openIds) do Editor.OpenedIds[id] = true end
end

local function onlyHuman(target)
    local humans = player.GetHumans()
    return #humans == 1 and humans[1] == target
end

local function arrivedAtTransfer(session)
    return session.transferToken ~= nil and Editor.LoadedTransferToken == session.transferToken
        and Editor.LoadedTransferSequence == session.transferSequence
        and string.lower(session.map) == string.lower(game.GetMap())
end

local function resolveEditorCell(id, expectedMap)
    if not EditorMap.IsValidCellId(id) or not ZM_World:IsLoaded() or ZM_World.ActiveProfile ~= "preview" then
        return nil, "Preview world cell data is unavailable."
    end
    local cell = ZM_World:GetCellById(id)
    local mapName = cell and ZM_World:GetMapPath(cell)
    if not cell or not EditorMap.IsValidName(mapName) or
        (expectedMap and string.lower(mapName) ~= string.lower(expectedMap)) then
        return nil, "The selected preview cell or map is invalid."
    end
    if not file.Exists("maps/" .. mapName .. ".bsp", "GAME") then
        return nil, "The selected preview cell map is not mounted."
    end
    local bounds = ZM_World:GetCellBounds()
    if type(bounds) ~= "table" or not finite(bounds.tileSize) or bounds.tileSize <= 0
        or bounds.coreTileGridSize ~= 5 or not finite(bounds.playableCeiling) or bounds.playableCeiling <= 0 then
        return nil, "Preview cell tile geometry is unavailable."
    end
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    if not finite(worldX) or not finite(worldY) then
        return nil, "The selected preview cell has invalid logical coordinates."
    end
    return { cell = cell, id = id, map = mapName, x = worldX, y = worldY,
        tileSize = bounds.tileSize, ceiling = bounds.playableCeiling }
end

local function traceCellTile(target, context, tileX, tileY)
    if not EditorMap.IsValidTile(tileX) or not EditorMap.IsValidTile(tileY) then
        return nil, "Tile X and Y must be whole numbers between -2 and 2."
    end
    local x, y = tileX * context.tileSize, tileY * context.tileSize
    local trace = util.TraceLine({
        start = Vector(x, y, context.ceiling - 1), endpos = Vector(x, y, -context.ceiling),
        filter = target, mask = MASK_SOLID
    })
    if type(trace) ~= "table" or not trace.Hit or trace.HitSky or trace.StartSolid
        or not trace.HitNormal or not finite(trace.HitNormal.z) or trace.HitNormal.z <= 0
        or not trace.HitPos or not finite(trace.HitPos.x) or not finite(trace.HitPos.y)
        or not finite(trace.HitPos.z) then
        return nil, "Could not detect a solid surface at the selected tile centre."
    end
    return trace.HitPos
end

function Editor:IsEditorMap()
    return self.EditorMapSession
end

function Editor:IsOwner(target)
    if not self:IsEditorMap() or not IsValid(target) or not target:IsAdmin() then
        return false
    end
    local session = readSession()
    local fixtureMap = game.GetMap() == "zn_dev_prefab_anchor"
    local expected = session and (session.map or (session.fixture and "zn_dev_prefab_anchor" or "gm_flatgrass"))
    local current = string.lower(game.GetMap())
    local atExpected = expected and string.lower(expected) == current
        or (session and session.transferToken and string.lower(session.previousMap) == current)
    return session ~= nil and atExpected and (session.fixture == true) == fixtureMap
        and session.owner == target:SteamID64()
end

function Editor:IsFixtureMap()
    local session = self:IsEditorMap() and readSession() or nil
    return game.GetMap() == "zn_dev_prefab_anchor" and session ~= nil and session.fixture == true
end

function Editor:IsParticipant(target)
    return self:IsOwner(target) and onlyHuman(target)
end

function Editor:GetStatus(target)
    local origin = IsValid(target) and target.ZM_PrefabEditorOrigin or nil
    return {
        map = game.GetMap(),
        profile = ZM_World.ActiveProfile,
        editorMap = self:IsEditorMap(),
        fixtureMap = self:IsFixtureMap(),
        owner = self:IsOwner(target),
        participant = self:IsParticipant(target),
        humanCount = #player.GetHumans(),
        persistentStateLoaded = IsValid(target) and target.ZM_PersistentStateLoaded == true or false,
        origin = origin and { x = origin.x, y = origin.y, z = origin.z } or nil
    }
end

function Editor:Begin(target, openId, fixture)
    if not IsValid(target) or not target:IsAdmin() then return false, "The prefab editor requires an admin." end
    if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview" then
        return false, "Start the prefab editor from the preview launcher."
    end
    if target.ZM_LauncherState ~= "menu" then return false, "The preview launcher is not ready." end
    if not onlyHuman(target) then return false, "The prefab editor requires no other connected players." end
    if (ZM_MapBatch and ZM_MapBatch:IsActive()) or (ZM_WorldCapture and ZM_WorldCapture:IsActive())
        or GAMEMODE.PlayerWorldMapTransitionQueued or (navmesh and navmesh.IsGenerating and navmesh.IsGenerating()) then
        return false, "Wait for the current map transition or maintenance batch to finish."
    end
    if file.Exists(sessionPath, "DATA") then
        local previous = readSession()
        if previous and previous.transferToken then return false, "A pending editor map-switch draft needs recovery." end
        return false, "A previous prefab editor session exists. Recover it before starting another."
    end
    local destination = fixture and "zn_dev_prefab_anchor" or "gm_flatgrass"
    if not file.Exists("maps/" .. destination .. ".bsp", "GAME") then return false, destination .. " is not mounted." end
    if openId and openId ~= "" then
        local document, problem = Storage.Load(openId)
        if not document then return false, problem end
    else
        openId = nil
    end
    local owner = target:SteamID64()
    if type(owner) ~= "string" or not string.match(owner, "^%d+$") then
        return false, "The prefab editor could not identify its owner."
    end
    local encoded = util.TableToJSON({ schemaVersion = 1, profile = "preview", owner = owner,
        openId = openId, fixture = fixture == true, map = destination }, true)
    if type(encoded) ~= "string" then return false, "Could not encode the prefab editor session." end
    file.CreateDir("zombiesim")
    if not file.Write(sessionPath, encoded) or file.Read(sessionPath, "DATA") ~= encoded then
        return false, "Could not save the prefab editor session."
    end
    target.ZM_LauncherState = "prefab_editor_transition"
    game.ConsoleCommand("changelevel " .. destination .. "\n")
    return true
end

function Editor:HandleSpawn(target)
    if not self:IsEditorMap() then return false end
    target:StripWeapons()
    target:Freeze(true)
    target:GodEnable()
    target:SetNoDraw(true)
    if not self:IsParticipant(target) then
        target:ChatPrint("[ZombieSim] Prefab editor access requires its original admin and no other players.")
        return true
    end
    target:SetNWBool("ZM.PrefabEditorActive", true)
    if self:IsFixtureMap() then
        target:Freeze(false)
        target:SetNoDraw(false)
        return true
    end
    local session, sessionError = readSession()
    if not session then
        target:ChatPrint("[ZombieSim] " .. tostring(sessionError))
        ErrorNoHalt("[ZombieSim] " .. tostring(sessionError) .. "\n")
        return true
    end
    if session.cellId ~= nil then
        if not ZM_World:IsLoaded() or ZM_World.ActiveProfile ~= "preview" then
            local loaded, problem = ZM_World:LoadProfile("preview")
            if not loaded then
                target:ChatPrint("[ZombieSim] " .. tostring(problem))
                ErrorNoHalt("[ZombieSim] " .. tostring(problem) .. "\n")
                return true
            end
        end
        local context, problem = resolveEditorCell(session.cellId, game.GetMap())
        local origin
        if context then origin, problem = traceCellTile(target, context, session.tileX, session.tileY) end
        if not origin then
            target:ChatPrint("[ZombieSim] " .. tostring(problem))
            ErrorNoHalt("[ZombieSim] " .. tostring(problem) .. "\n")
            return true
        end
        target.ZM_PrefabEditorOrigin = origin
        return true
    end
    local mapName = game.GetMap()
    local spawn = ents.FindByClass("info_player_start")[1]
    if not IsValid(spawn) then
        target:ChatPrint("[ZombieSim] " .. mapName .. " has no player spawn for locating the editor workspace.")
        ErrorNoHalt("[ZombieSim] " .. mapName .. " has no player spawn for locating the editor workspace.\n")
        return true
    end
    local spawnPosition = spawn:GetPos()
    local spawnHeight = spawnPosition.z
    local traceX, traceY = spawnPosition.x, spawnPosition.y
    local traceTop, traceBottom = spawnHeight + 64, spawnHeight - 2048
    if mapName == "gm_flatgrass" then
        traceX, traceY, traceTop, traceBottom = 3072, 3072, spawnHeight + 1024, spawnHeight - 1024
    end
    local trace = util.TraceLine({
        start = Vector(traceX, traceY, traceTop),
        endpos = Vector(traceX, traceY, traceBottom),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not trace.Hit or trace.HitSky or trace.StartSolid or trace.HitNormal.z < 0.9 then
        target:ChatPrint("[ZombieSim] Could not find a flat prefab-editor workspace on " .. mapName .. ".")
        ErrorNoHalt(string.format("[ZombieSim] Prefab workspace trace failed: spawnZ %.1f, hit %s, sky %s, startSolid %s, normalZ %.3f.\n",
            spawnHeight, tostring(trace.Hit), tostring(trace.HitSky), tostring(trace.StartSolid), trace.HitNormal.z))
        return true
    end
    target.ZM_PrefabEditorOrigin = trace.HitPos
    return true
end

hook.Add("SetupPlayerVisibility", "ZM.PrefabEditor.PVS", function(target)
    if Editor:IsOwner(target) and target.ZM_PrefabEditorOrigin then
        AddOriginToPVS(target.ZM_PrefabEditorOrigin)
    end
end)

local function listDocuments()
    local documents, problem = Storage.List()
    if not documents then return nil, problem end
    local result = {}
    for _, document in ipairs(documents) do
        result[#result + 1] = {
            id = document.id, name = document.name, description = document.description, tags = document.tags
        }
    end
    return result
end

local function listReferenceTiles()
    local names = file.Find("models/zombiesim/prefab_tile_preview/*.mdl", "GAME")
    if type(names) ~= "table" then return nil, "Could not list reference tile models." end
    table.sort(names)
    local result = {}
    for _, name in ipairs(names) do
        local hash = string.match(name, "^road_([a-f0-9]+)_v1%.mdl$")
        if not hash or #hash ~= 12 then return nil, "Unexpected reference tile model: " .. tostring(name) end
        local path = "models/zombiesim/prefab_tile_preview/" .. name
        if not util.IsValidModel(path) then return nil, "Reference tile model is unavailable: " .. path end
        result[#result + 1] = { label = "Straight road (prototype " .. hash .. ")", model = path }
    end
    return result
end

local function listEditorMaps(query, page)
    local names = file.Find("maps/*.bsp", "GAME")
    if type(names) ~= "table" then return nil, "Could not list mounted maps." end
    local recommended, custom, seen = {}, {}, {}
    for _, filename in ipairs(names) do
        local name = type(filename) == "string" and string.match(filename, "^(.+)%.bsp$") or nil
        local key = name and string.lower(name) or nil
        if name and EditorMap.IsValidName(name) and not EditorMap.IsReservedName(name) and not seen[key] then
            seen[key] = true
            if key == "gm_construct" or key == "gm_flatgrass" then recommended[#recommended + 1] = name
            else custom[#custom + 1] = name end
        end
    end
    table.sort(recommended)
    table.sort(custom)
    local filtered = {}
    for _, name in ipairs(custom) do
        if query == "" or string.find(string.lower(name), query, 1, true) then filtered[#filtered + 1] = name end
    end
    local pageSize = 48
    local pages = math.max(1, math.ceil(#filtered / pageSize))
    page = math.min(page, pages)
    local result = {}
    for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #filtered) do
        result[#result + 1] = filtered[index]
    end
    return { recommended = recommended, custom = result, page = page, pages = pages, total = #filtered }
end

local function listEditorCells(query, page)
    if not ZM_World:IsLoaded() or ZM_World.ActiveProfile ~= "preview" then
        return nil, "Preview world cell data is unavailable."
    end
    local data = ZM_World:GetData()
    if type(data) ~= "table" or type(data.cells) ~= "table" then return nil, "Preview world cells are unavailable." end
    local matches = {}
    for _, cell in ipairs(data.cells) do
        if type(cell) ~= "table" then return nil, "Preview world contains invalid cell metadata." end
        local mapName = ZM_World:GetMapPath(cell)
        local x, y = ZM_World:GetWorldCoordinates(cell)
        if not EditorMap.IsValidCellId(cell.id) or not EditorMap.IsValidName(mapName)
            or not finite(x) or not finite(y) or x ~= math.floor(x) or y ~= math.floor(y) then
            return nil, "Preview world contains invalid cell metadata."
        end
        local label = tostring(x) .. "," .. tostring(y)
        if query == "" or string.find(string.lower(label .. " " .. mapName), query, 1, true) then
            matches[#matches + 1] = { id = cell.id, x = x, y = y, map = mapName }
        end
    end
    table.sort(matches, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.id < b.id
    end)
    local pageSize = 48
    local pages = math.max(1, math.ceil(#matches / pageSize))
    page = math.min(page, pages)
    local result = {}
    for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #matches) do
        result[#result + 1] = matches[index]
    end
    return { cells = result, page = page, pages = pages, total = #matches }
end

local function validateEditorMap(name)
    if not EditorMap.IsValidName(name) or EditorMap.IsReservedName(name) then
        return false, "The selected editor map is invalid or reserved."
    end
    if not file.Exists("maps/" .. name .. ".bsp", "GAME") then return false, "The selected map is not mounted." end
    if not ZM_World:IsLoaded() then return false, "World data is unavailable for checking the selected map." end
    if ZM_World:GetUniqueProfileForMap(name) then return false, "ZombieSim world maps cannot be used as editor workspaces." end
    local cells = ZM_World:GetCellsForMap(name)
    if cells ~= nil and type(cells) ~= "table" then return false, "Could not check the selected map against world data." end
    if cells and #cells > 0 then return false, "ZombieSim world maps cannot be used as editor workspaces." end
    local data = ZM_World:GetData()
    if type(data) ~= "table" or type(data.safeZones) ~= "table" then return false, "Safe-zone map data is unavailable." end
    for _, zone in ipairs(data.safeZones) do
        local path = ZM_SafeZones:GetMap(zone.id)
        local basename = type(path) == "string" and string.match(path, "([^/]+)$") or nil
        if basename and string.lower(basename) == string.lower(name) then
            return false, "ZombieSim safe-zone maps cannot be used as editor workspaces."
        end
    end
    return true
end

local function validateDestination(name, cellId)
    if cellId ~= nil then
        local context, problem = resolveEditorCell(cellId, name)
        return context ~= nil, problem
    end
    return validateEditorMap(name)
end

local function browserOptions(text)
    local options = text ~= "" and util.JSONToTable(text) or { query = "", page = 1 }
    if type(options) ~= "table" or type(options.query) ~= "string" or #options.query > 128
        or not finite(options.page) or options.page < 1 or options.page ~= math.floor(options.page) then
        return nil, "Invalid map-browser search or page."
    end
    return { query = string.lower(options.query), page = options.page }
end

local function perform(target, action, text, openedId)
    if action == "begin" then return Editor:Begin(target, text) end
    if action == "resume" then
        if not IsValid(target) or not target:IsAdmin() or not onlyHuman(target)
            or game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
            or target.ZM_LauncherState ~= "menu" then
            return false, "Resuming a map-switch draft requires the preview launcher admin alone."
        end
        local session, problem = readSession()
        if not session then return false, problem end
        if session.owner ~= target:SteamID64() or not session.transferToken then
            return false, "No owned map-switch draft is available to resume."
        end
        local allowed, mapError = validateDestination(session.map, session.cellId)
        if not allowed then return false, mapError end
        target.ZM_LauncherState = "prefab_editor_transition"
        game.ConsoleCommand("changelevel " .. session.map .. "\n")
        return true
    end
    if action == "recover" then
        if not IsValid(target) or not target:IsAdmin() or not onlyHuman(target)
            or game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview" then
            return false, "Session recovery requires a preview launcher admin alone."
        end
        local session, problem = readSession()
        if not session then return false, problem end
        if session.owner ~= target:SteamID64() then return false, "The editor session belongs to another admin." end
        if session.transferToken then return false, "Resume the pending editor map-switch draft instead of clearing it." end
        if not file.Delete(sessionPath) then return false, "Could not clear the previous editor session." end
        if target.ZM_LauncherState == "prefab_editor_transition" then target.ZM_LauncherState = "menu" end
        return true, "Previous editor session cleared."
    end
    if action == "end" then
        if not Editor:IsOwner(target) then return false, "Only the editor owner can end the session." end
        local session, problem = readSession()
        if not session then return false, problem end
        if session.transferToken then return false, "Finish recovering the map-switch draft before leaving the editor." end
        if not file.Delete(sessionPath) then return false, "Could not close the prefab editor session." end
        game.ConsoleCommand("changelevel zn_preview_start\n")
        return true
    end
    if action == "explorer_list" or action == "explorer_preview"
        or action == "explorer_rename" or action == "explorer_delete"
        or action == "explorer_guard_weapons" then
        local launcherAdmin = IsValid(target) and target:IsAdmin()
            and game.GetMap() == "zn_preview_start" and ZM_World.ActiveProfile == "preview"
            and target.ZM_LauncherState == "menu"
        if not launcherAdmin and not Editor:IsParticipant(target) then
            return false, "Prefab explorer requires a preview launcher admin or the active editor owner."
        end
        if action == "explorer_list" then
            local documents, problem = listDocuments()
            if not documents then return false, problem end
            return true, "", documents
        end
        if action == "explorer_guard_weapons" then
            local choices, problem = ZM_PrefabGuardWeapons.List()
            if not choices then return false, problem end
            return true, "", choices
        end
        local document, problem = Storage.Load(text)
        if not document then return false, problem end
        if action == "explorer_preview" then return true, "", document end
        if Editor.OpenedIds[text] then
            return false, "Close the prefab in the editor before managing it in the explorer."
        end
        if action == "explorer_rename" then
            document.name = openedId
            local ok, saveProblem = Storage.Save(document, document.id)
            return ok, saveProblem or (ok and "Prefab renamed." or "Prefab rename failed."), ok and document or nil
        end
        local ok, deleteProblem = Storage.Delete(document.id)
        return ok, deleteProblem or (ok and "Prefab deleted." or "Prefab deletion failed."), ok and { id = document.id } or nil
    end
    if not Editor:IsParticipant(target) then return false, "Prefab editor session is not available." end
    if action == "status" then
        if not target.ZM_PrefabEditorOrigin then return false, "Prefab editor workspace is not ready." end
        local documents, problem = listDocuments()
        if not documents then return false, problem end
        local origin = target.ZM_PrefabEditorOrigin
        local session, sessionError = readSession()
        if not session then return false, sessionError end
        local currentCell
        if session.cellId ~= nil and (not session.transferToken or arrivedAtTransfer(session)) then
            local context, cellError = resolveEditorCell(session.cellId, session.map)
            if not context then return false, cellError end
            currentCell = { id = context.id, x = context.x, y = context.y,
                tileX = session.tileX, tileY = session.tileY, tileSize = context.tileSize }
        end
        return true, "", { origin = { x = origin.x, y = origin.y, z = origin.z }, cell = currentCell,
            documents = documents, openId = session.openId,
            transferToken = arrivedAtTransfer(session) and session.transferToken or nil,
            transitionTarget = session.transferToken and not arrivedAtTransfer(session)
                and string.lower(session.previousMap) == string.lower(game.GetMap()) and session.map or nil,
            openIds = session.transferToken and session.openIds or nil }
    elseif action == "maps" or action == "cells" then
        if Editor:IsFixtureMap() then return false, "Map selection is unavailable in the isolated fixture." end
        local options, optionError = browserOptions(text)
        if not options then return false, optionError end
        local maps, problem
        if action == "cells" then maps, problem = listEditorCells(options.query, options.page)
        else maps, problem = listEditorMaps(options.query, options.page) end
        if not maps then return false, problem end
        return true, "", maps
    elseif action == "cell_tile" then
        local session, sessionError = readSession()
        if not session then return false, sessionError end
        if session.cellId == nil or session.transferToken then return false, "A ready preview cell is required." end
        local request = util.JSONToTable(text)
        if type(request) ~= "table" or not EditorMap.IsValidTile(request.x) or not EditorMap.IsValidTile(request.y) then
            return false, "Tile X and Y must be whole numbers between -2 and 2."
        end
        for key in pairs(request) do
            if key ~= "x" and key ~= "y" then return false, "The tile selection contains unsupported fields." end
        end
        local context, cellError = resolveEditorCell(session.cellId, game.GetMap())
        if not context then return false, cellError end
        local origin, traceError = traceCellTile(target, context, request.x, request.y)
        if not origin then return false, traceError end
        session.tileX, session.tileY = request.x, request.y
        local written, writeError = writeSession(session)
        if not written then return false, writeError end
        target.ZM_PrefabEditorOrigin = origin
        return true, "", { x = request.x, y = request.y, origin = { x = origin.x, y = origin.y, z = origin.z } }
    elseif action == "switch_map" then
        local function reject(problem)
            return false, problem, { markerUnchanged = true }
        end
        if Editor:IsFixtureMap() or ZM_World.ActiveProfile ~= "preview" then
            return reject("Map switching requires an ordinary preview editor session.")
        end
        local request = util.JSONToTable(text)
        local valid, problem = EditorMap.ValidateRequest(request)
        if not valid then return reject(problem) end
        local session, sessionError = readSession()
        if not session then return reject(sessionError) end
        if session.transferToken then return reject("A previous editor map switch has not completed.") end
        if string.lower(request.map) == string.lower(game.GetMap()) and request.cellId == session.cellId then
            return reject("The editor is already on that map or cell.")
        end
        local allowed, mapError = validateDestination(request.map, request.cellId)
        if not allowed then return reject(mapError) end
        local requested = {}
        for _, id in ipairs(request.openIds) do
            if not Editor.OpenedIds[id] then return reject("An editor tab is no longer authorized.") end
            requested[id] = true
        end
        for id in pairs(Editor.OpenedIds) do
            if not requested[id] then return reject("The editor's open tabs changed during map switching.") end
        end
        session.previousMap = game.GetMap()
        session.previousCellId, session.previousTileX, session.previousTileY = session.cellId, session.tileX, session.tileY
        session.map, session.openId, session.openIds, session.transferToken = request.map, nil, request.openIds, request.token
        session.transferSequence = 1
        session.cellId = request.cellId
        session.tileX, session.tileY = request.cellId ~= nil and 0 or nil, request.cellId ~= nil and 0 or nil
        local written, writeError = writeSession(session)
        if not written then return false, writeError, { markerUnchanged = false } end
        game.ConsoleCommand("changelevel " .. request.map .. "\n")
        return true
    elseif action == "switch_retry" or action == "switch_return" then
        local session, problem = readSession()
        if not session then return false, problem end
        if not session.transferToken then return false, "No editor map switch is pending." end
        local current = string.lower(game.GetMap())
        local destination, cellId
        if action == "switch_retry" and not arrivedAtTransfer(session) and current == string.lower(session.previousMap) then
            destination, cellId = session.map, session.cellId
        elseif action == "switch_return" and arrivedAtTransfer(session) then
            destination, cellId = session.previousMap, session.previousCellId
            session.map, session.previousMap = session.previousMap, session.map
            session.cellId, session.previousCellId = session.previousCellId, session.cellId
            session.tileX, session.previousTileX = session.previousTileX, session.tileX
            session.tileY, session.previousTileY = session.previousTileY, session.tileY
            session.transferSequence = session.transferSequence + 1
        else
            return false, "The pending editor map switch cannot use that recovery action here."
        end
        local allowed, mapError = validateDestination(destination, cellId)
        if not allowed then return false, mapError end
        if action == "switch_return" then
            local written, writeError = writeSession(session)
            if not written then return false, writeError end
        end
        game.ConsoleCommand("changelevel " .. destination .. "\n")
        return true
    elseif action == "switch_check" then
        local session, problem = readSession()
        if not session then return false, problem end
        return true, "", { safeToResume = session.transferToken == nil }
    elseif action == "switch_complete" then
        local session, problem = readSession()
        if not session then return false, problem end
        if not session.transferToken or session.transferToken ~= text or not arrivedAtTransfer(session) then
            return false, "The editor map-switch confirmation does not match the session."
        end
        session.transferToken, session.previousMap, session.transferSequence = nil, nil, nil
        session.previousCellId, session.previousTileX, session.previousTileY = nil, nil, nil
        local written, writeError = writeSession(session)
        if not written then return false, writeError end
        Editor.LoadedTransferToken, Editor.LoadedTransferSequence = nil, nil
        return true, "Editor tabs restored."
    elseif action == "new" then
        Editor.OpenedId = nil
        return true, ""
    elseif action == "activate" then
        if text ~= "" and not Editor.OpenedIds[text] then return false, "The prefab is not open in this editor session." end
        Editor.OpenedId = text ~= "" and text or nil
        return true, ""
    elseif action == "close" then
        if not Contract.IsValidId(text) or not Editor.OpenedIds[text] then
            return false, "The prefab is not open in this editor session."
        end
        Editor.OpenedIds[text] = nil
        if Editor.OpenedId == text then Editor.OpenedId = nil end
        return true, ""
    elseif action == "list" then
        local documents, problem = listDocuments()
        if not documents then return false, problem end
        return true, "", documents
    elseif action == "load" then
        local document, problem = Storage.Load(text)
        if not document then return false, problem end
        Editor.OpenedId = document.id
        Editor.OpenedIds[document.id] = true
        return true, "", document
    elseif action == "model" then
        if not Contract.IsValidModelPath(text) or not util.IsValidModel(text) then
            return false, "The selected model is invalid or unavailable: " .. tostring(text)
        end
        return true, "", { model = text, propId = "p_" .. ZM_ItemGeneration.NewInstanceId() }
    elseif action == "particles" then
        local effects, problem = ParticleCatalog.Load()
        if not effects then return false, problem end
        return true, "", effects
    elseif action == "guard_weapons" then
        local choices, problem = ZM_PrefabGuardWeapons.List()
        if not choices then return false, problem end
        return true, "", choices
    elseif action == "references" or action == "reference" then
        local references, problem = listReferenceTiles()
        if not references then return false, problem end
        if action == "references" then return true, "", references end
        for _, reference in ipairs(references) do
            if reference.model == text then return true, "", reference end
        end
        return false, "The requested reference tile is unavailable: " .. tostring(text)
    elseif action == "save" then
        if #text > maximumPayload then return false, "Prefab document is too large to send." end
        local document = util.JSONToTable(text)
        if type(document) ~= "table" then return false, "Prefab document contains invalid JSON." end
        if openedId ~= "" and not Editor.OpenedIds[openedId] then
            return false, "Open the saved prefab before changing it."
        end
        local ok, problem = Storage.Save(document, openedId ~= "" and openedId or nil)
        if ok then Editor.OpenedId = document.id; Editor.OpenedIds[document.id] = true end
        return ok, problem or (ok and "Prefab saved." or "Prefab save failed.")
    elseif action == "delete" then
        if not Editor.OpenedIds[text] then return false, "Open the saved prefab before deleting it." end
        local ok, problem = Storage.Delete(text)
        if ok then
            Editor.OpenedIds[text] = nil
            if Editor.OpenedId == text then Editor.OpenedId = nil end
        end
        return ok, problem or (ok and "Prefab deleted." or "Prefab deletion failed.")
    end
    return false, "Unknown prefab editor request."
end

net.Receive(requestMessage, function(_, target)
    local action = net.ReadString()
    local text = net.ReadString()
    local openedId = net.ReadString()
    local requestId = net.ReadString()
    if type(requestId) ~= "string" or #requestId > 64 or not string.match(requestId, "^[%w_%-]*$") then
        ErrorNoHalt("[ZombieSim] Prefab editor: invalid request ID.\n")
        reply(target, action, false, "Invalid prefab request ID.", nil, "")
        return
    end
    local ok, message, value = perform(target, action, text, openedId)
    if not ok then ErrorNoHalt("[ZombieSim] Prefab editor: " .. tostring(message) .. "\n") end
    reply(target, action, ok, message, value, requestId)
end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_editor_status = "Reports the current prefab editor session and workspace.",
    zombiesim_prefab_cell_status = "Reports an existing preview cell's editor-map availability.",
    zombiesim_prefab_fixture_start = "Opens the isolated prefab anchor fixture from the preview launcher.",
    zombiesim_prefab_fixture_end = "Returns the fixture owner to the preview launcher."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not target then return false, "A connected admin is required." end
    if command == "zombiesim_prefab_fixture_start" then
        return Editor:Begin(target, nil, true)
    elseif command == "zombiesim_prefab_fixture_end" then
        if not Editor:IsFixtureMap() then return false, "The prefab fixture session is not active." end
        return perform(target, "end", "", "")
    elseif command == "zombiesim_prefab_cell_status" then
        if not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" or not ZM_World:IsLoaded() then
            return false, "Preview cell status requires an admin and loaded preview world data."
        end
        local x, y = tonumber(arguments and arguments[1]), tonumber(arguments and arguments[2])
        if not finite(x) or not finite(y) or x ~= math.floor(x) or y ~= math.floor(y)
            or (arguments and arguments[3] ~= nil) then return false, "Use whole logical cell X and Y coordinates." end
        local gridX, gridY = ZM_World:GetGridCoordinates(x, y)
        local cell = gridX and gridY and ZM_World:GetCell(gridX, gridY)
        local context, problem
        if cell then context, problem = resolveEditorCell(cell.id) end
        if not context then return false, problem or "The requested preview cell is unavailable." end
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabCell", { id = context.id, x = context.x, y = context.y,
                map = context.map, tileSize = context.tileSize })
        end
        return true
    end
    local status = Editor:GetStatus(target)
    if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabEditor", status) end
    ZM_Util.Reply(caller, string.format("Prefab editor: map %s; editor %s; workspace %s.",
        status.map, tostring(status.editorMap), status.origin and "ready" or "unavailable"))
    return true
end)

return Editor
