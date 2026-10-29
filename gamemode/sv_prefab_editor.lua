local Contract = include("prefabs/sh_contract.lua")
local PrefabLoot = include("prefabs/sv_loot.lua")(ZM_StaticData)
local Storage = include("prefabs/sv_storage.lua")(file, util, Contract, util.IsValidModel, PrefabLoot.Validate)
ZM_PrefabEditor = ZM_PrefabEditor or {}
local Editor = ZM_PrefabEditor

local sessionPath = "zombiesim/prefab_editor_session.json"
local requestMessage = "ZM.PrefabEditorRequest"
local responseMessage = "ZM.PrefabEditorResponse"
local maximumPayload = 60000
Editor.EditorMapSession = (game.GetMap() == "gm_flatgrass" or game.GetMap() == "zn_dev_prefab_anchor")
    and file.Exists(sessionPath, "DATA")

util.AddNetworkString(requestMessage)
util.AddNetworkString(responseMessage)

local function reply(target, action, success, message, value)
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
    net.Send(target)
end

local function readSession()
    if not file.Exists(sessionPath, "DATA") then return nil, "No prefab editor session exists." end
    local contents = file.Read(sessionPath, "DATA")
    local session = type(contents) == "string" and util.JSONToTable(contents) or nil
    if type(session) ~= "table" or session.schemaVersion ~= 1 or session.profile ~= "preview"
        or type(session.owner) ~= "string" or not string.match(session.owner, "^%d+$")
        or (session.fixture ~= nil and type(session.fixture) ~= "boolean")
        or (session.openId ~= nil and not Contract.IsValidId(session.openId)) then
        return nil, "Prefab editor session is invalid; inspect " .. sessionPath .. " before continuing."
    end
    return session
end

local function onlyHuman(target)
    local humans = player.GetHumans()
    return #humans == 1 and humans[1] == target
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
    return session ~= nil and (session.fixture == true) == fixtureMap and session.owner == target:SteamID64()
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
        openId = openId, fixture = fixture == true }, true)
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
    local spawn = ents.FindByClass("info_player_start")[1]
    if not IsValid(spawn) then
        target:ChatPrint("[ZombieSim] gm_flatgrass has no player spawn for locating the editor workspace.")
        ErrorNoHalt("[ZombieSim] gm_flatgrass has no player spawn for locating the editor workspace.\n")
        return true
    end
    local spawnHeight = spawn:GetPos().z
    local trace = util.TraceLine({
        start = Vector(3072, 3072, spawnHeight + 1024),
        endpos = Vector(3072, 3072, spawnHeight - 1024),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not trace.Hit or trace.HitSky or trace.StartSolid or trace.HitNormal.z < 0.9 then
        target:ChatPrint("[ZombieSim] Could not find a flat prefab-editor workspace on gm_flatgrass.")
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

local function perform(target, action, text, openedId)
    if action == "begin" then return Editor:Begin(target, text) end
    if action == "recover" then
        if not IsValid(target) or not target:IsAdmin() or not onlyHuman(target)
            or game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview" then
            return false, "Session recovery requires a preview launcher admin alone."
        end
        local session, problem = readSession()
        if not session then return false, problem end
        if session.owner ~= target:SteamID64() then return false, "The editor session belongs to another admin." end
        if not file.Delete(sessionPath) then return false, "Could not clear the previous editor session." end
        if target.ZM_LauncherState == "prefab_editor_transition" then target.ZM_LauncherState = "menu" end
        return true, "Previous editor session cleared."
    end
    if action == "end" then
        if not Editor:IsOwner(target) then return false, "Only the editor owner can end the session." end
        if not file.Delete(sessionPath) then return false, "Could not close the prefab editor session." end
        game.ConsoleCommand("changelevel zn_preview_start\n")
        return true
    end
    if action == "explorer_list" or action == "explorer_preview"
        or action == "explorer_rename" or action == "explorer_delete" then
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
        local document, problem = Storage.Load(text)
        if not document then return false, problem end
        if action == "explorer_preview" then return true, "", document end
        if Editor.OpenedId == text then
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
        return true, "", { origin = { x = origin.x, y = origin.y, z = origin.z },
            documents = documents, openId = session.openId }
    elseif action == "new" then
        Editor.OpenedId = nil
        return true, ""
    elseif action == "list" then
        local documents, problem = listDocuments()
        if not documents then return false, problem end
        return true, "", documents
    elseif action == "load" then
        local document, problem = Storage.Load(text)
        if not document then return false, problem end
        Editor.OpenedId = document.id
        return true, "", document
    elseif action == "model" then
        if not Contract.IsValidModelPath(text) or not util.IsValidModel(text) then
            return false, "The selected model is invalid or unavailable: " .. tostring(text)
        end
        return true, "", { model = text, propId = "p_" .. ZM_ItemGeneration.NewInstanceId() }
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
        if openedId ~= "" and Editor.OpenedId ~= openedId then
            return false, "Open the saved prefab before changing it."
        end
        local ok, problem = Storage.Save(document, openedId ~= "" and openedId or nil)
        if ok then Editor.OpenedId = document.id end
        return ok, problem or (ok and "Prefab saved." or "Prefab save failed.")
    elseif action == "delete" then
        if Editor.OpenedId ~= text then return false, "Open the saved prefab before deleting it." end
        local ok, problem = Storage.Delete(text)
        if ok then Editor.OpenedId = nil end
        return ok, problem or (ok and "Prefab deleted." or "Prefab deletion failed.")
    end
    return false, "Unknown prefab editor request."
end

net.Receive(requestMessage, function(_, target)
    local action, text, openedId = net.ReadString(), net.ReadString(), net.ReadString()
    local ok, message, value = perform(target, action, text, openedId)
    if not ok then ErrorNoHalt("[ZombieSim] Prefab editor: " .. tostring(message) .. "\n") end
    reply(target, action, ok, message, value)
end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_editor_status = "Reports the current prefab editor session and workspace.",
    zombiesim_prefab_fixture_start = "Opens the isolated prefab anchor fixture from the preview launcher.",
    zombiesim_prefab_fixture_end = "Returns the fixture owner to the preview launcher."
}, function(caller, command)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not target then return false, "A connected admin is required." end
    if command == "zombiesim_prefab_fixture_start" then
        return Editor:Begin(target, nil, true)
    elseif command == "zombiesim_prefab_fixture_end" then
        if not Editor:IsFixtureMap() then return false, "The prefab fixture session is not active." end
        return perform(target, "end", "", "")
    end
    local status = Editor:GetStatus(target)
    if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabEditor", status) end
    ZM_Util.Reply(caller, string.format("Prefab editor: map %s; editor %s; workspace %s.",
        status.map, tostring(status.editorMap), status.origin and "ready" or "unavailable"))
    return true
end)

return Editor
