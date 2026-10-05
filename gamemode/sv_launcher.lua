// Launcher requests never accept an owner or profile from the client.
ZM_Launcher = ZM_Launcher or {}
local Launcher = ZM_Launcher

util.AddNetworkString("ZM.LauncherStatus")
util.AddNetworkString("ZM.LauncherRequest")

local autoload = CreateConVar("zombiesim_dev_autoload_character", "0", FCVAR_ARCHIVE,
    "Developer-only launcher slot autoload (0 disables).")
local actions = { list = true, create = true, appearance = true, select = true, delete = true,
    credits_start = true, credits_stop = true }
local dancers = { "dancing_gman", "dancing_alyx", "dancing_barney", "dancing_kleiner" }
local smilePresets = {
    ["models/gman.mdl"] = { smile = 1, left_corner_puller = 0.9, right_corner_puller = 0.9,
        left_cheek_raiser = 0.6, right_cheek_raiser = 0.6 },
    ["models/alyx.mdl"] = { smile = 1, left_corner_puller = 0.9, right_corner_puller = 0.9,
        left_cheek_raiser = 0.7, right_cheek_raiser = 0.7, jaw_drop = 0.12 },
    ["models/barney.mdl"] = { smile = 1, left_corner_puller = 0.9, right_corner_puller = 0.9,
        left_cheek_raiser = 0.7, right_cheek_raiser = 0.7, jaw_drop = 0.12 },
    ["models/kleiner.mdl"] = { smile = 1, left_corner_puller = 0.9, right_corner_puller = 0.9,
        left_cheek_raiser = 0.7, right_cheek_raiser = 0.7, jaw_drop = 0.12 }
}

local function findMarker(name)
    return ents.FindByName(name)[1]
end

local function sendPose(camera)
    net.WriteBool(IsValid(camera))
    if not IsValid(camera) then return end
    net.WriteVector(camera:GetPos())
    net.WriteAngle(camera:GetAngles())
    net.WriteFloat(tonumber(camera:GetInternalVariable("FOV")) or 90)
end

local function sendCreditsFog(camera)
    net.WriteFloat(IsValid(camera) and (tonumber(camera:GetInternalVariable("fogStart")) or 2048) or 2048)
    net.WriteFloat(IsValid(camera) and (tonumber(camera:GetInternalVariable("fogEnd")) or 4096) or 4096)
    net.WriteFloat(IsValid(camera) and (tonumber(camera:GetInternalVariable("fogMaxDensity")) or 1) or 1)
    local color = IsValid(camera) and tostring(camera:GetInternalVariable("fogColor") or "") or ""
    local red, green, blue = string.match(color, "(%d+)%s+(%d+)%s+(%d+)")
    net.WriteUInt(tonumber(red) or 0, 8)
    net.WriteUInt(tonumber(green) or 0, 8)
    net.WriteUInt(tonumber(blue) or 0, 8)
end

function Launcher:PoseSmiles()
    for _, name in ipairs(dancers) do
        local dancer = findMarker(name)
        if IsValid(dancer) and dancer:GetClass() == "prop_ragdoll" then
            dancer:SetFlexScale(1)
            for flex, weight in pairs(smilePresets[string.lower(dancer:GetModel() or "")] or {}) do
                local id = dancer:GetFlexIDByName(flex)
                if id and id >= 0 then
                    local minimum, maximum = dancer:GetFlexBounds(id)
                    dancer:SetFlexWeight(id, math.Clamp(weight, minimum or 0, maximum or 1))
                end
            end
        end
    end
end

hook.Add("InitPostEntity", "ZombieSim.Launcher.Smiles", function()
    if not ZM_World.LauncherMapProfiles[game.GetMap()] then return end
    timer.Simple(1, function()
        if ZM_Launcher then ZM_Launcher:PoseSmiles() end
    end)
    timer.Create("ZombieSim.Launcher.Smiles", 2, 0, function() Launcher:PoseSmiles() end)
end)

function Launcher:SendStatus(target, action, success, message)
    if not IsValid(target) then return end
    local rows, rowError = ZM_CharacterService:List(target, true)
    local camera = findMarker("menu_camera")
    if not IsValid(camera) then
        ErrorNoHalt("[ZombieSim] Launcher is missing menu_camera\n")
    end
    net.Start("ZM.LauncherStatus")
        net.WriteString(action or "list")
        net.WriteBool(success ~= false and rows ~= nil)
        net.WriteString(message or rowError or "")
        net.WriteString(util.TableToJSON(rows or {}, false) or "[]")
        net.WriteBool(target.ZM_LauncherState == "deploying")
        sendPose(camera)
        local creditsCamera = findMarker("credits_camera")
        sendPose(creditsCamera)
        sendCreditsFog(creditsCamera)
        local marker = findMarker("menu_globe")
        net.WriteBool(IsValid(marker))
        if IsValid(marker) then net.WriteVector(marker:GetPos()) end
        net.WriteString(ZM_World.ActiveProfile or "")
        for _, name in ipairs(dancers) do
            local dancer = findMarker(name)
            net.WriteString(name)
            net.WriteUInt(IsValid(dancer) and dancer:EntIndex() or 0, 16)
        end
    net.Send(target)
end

hook.Add("SetupPlayerVisibility", "ZombieSim.Launcher.MenuPVS", function(target)
    if not target.ZM_LauncherState then return end
    local camera = findMarker("menu_camera")
    if IsValid(camera) then AddOriginToPVS(camera:GetPos()) end
    if target.ZM_LauncherCredits and CurTime() > (target.ZM_LauncherCreditsUntil or 0) then
        target.ZM_LauncherCredits = nil
    end
    if target.ZM_LauncherCredits then
        camera = findMarker("credits_camera")
        if IsValid(camera) then AddOriginToPVS(camera:GetPos()) end
        for _, name in ipairs(dancers) do
            local dancer = findMarker(name)
            if IsValid(dancer) then AddOriginToPVS(dancer:GetPos()) end
        end
    end
end)

concommand.Add("zombiesim_launcher_flexes", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then return end
    for _, name in ipairs(dancers) do
        local dancer = findMarker(name)
        if IsValid(dancer) then
            print("[ZombieSim] " .. name .. " (" .. dancer:GetModel() .. ")")
            for id = 0, dancer:GetFlexNum() - 1 do
                local minimum, maximum = dancer:GetFlexBounds(id)
                print("  " .. dancer:GetFlexName(id) .. " [" .. tostring(minimum) .. ", " .. tostring(maximum) .. "]")
            end
        end
    end
end)

function Launcher:Select(target, slot)
    local contentReady, contentError = ZM_Distribution:CanDeploy(target)
    if not contentReady then return false, contentError end
    local characters = ZM_CharacterService
    local existing, readError = characters:GetOwnedCharacter(target, slot)
    if readError then return false, readError end
    if not existing then return false, "That character slot is empty" end
    if tonumber(existing.appearanceRequired) ~= 0 then return false, "Choose an appearance before loading this character" end
    if ZM_MapBatch and ZM_MapBatch:IsActive() then return false, "A map batch is in progress" end
    local selected, selectError = characters:Select(target, slot)
    if not selected then return false, selectError end
    target.ZM_LauncherState = "character_selected"
    target.ZM_LauncherCredits = nil
    local ready, previouslyConnected = GAMEMODE:LoadSelectedCharacter(target, ZM_World.ActiveProfile)
    if not ready then
        target.ZM_LauncherState = "menu"
        target.ZM_PersistentStateLoaded = false
        characters:ClearActive(target)
        return false, previouslyConnected
    end
    target.ZM_LauncherState = "deploying"
    if not GAMEMODE:ContinuePlayerSpawnMapTransition(target, ZM_World.ActiveProfile, previouslyConnected) then
        target.ZM_LauncherState = "menu"
        target.ZM_PersistentStateLoaded = false
        characters:ClearActive(target)
        return false, "Could not resolve or enter this character's saved map"
    end
    self:SendStatus(target, "select", true, "Deploying")
    return true
end

net.Receive("ZM.LauncherRequest", function(_, target)
    if not IsValid(target) or target.ZM_LauncherState ~= "menu" then return end
    local action = net.ReadString()
    if not actions[action] then return end
    local slot = net.ReadUInt(3)
    local raw = net.ReadString()
    if #raw > 4096 then Launcher:SendStatus(target, action, false, "Request too large") return end
    local details = util.JSONToTable(raw or "") or {}
    local characters = ZM_CharacterService
    local success, message
    if action == "credits_start" then
        success = IsValid(findMarker("credits_camera"))
        message = success and "" or "Credits camera is unavailable"
        if success then
            target.ZM_LauncherCredits = true
            target.ZM_LauncherCreditsUntil = CurTime() + 300
            Launcher:PoseSmiles()
        end
    elseif action == "credits_stop" then
        target.ZM_LauncherCredits = nil
        success = true
    elseif action == "list" then
        local rows, listError = characters:List(target)
        success, message = rows ~= nil, listError
    elseif action == "create" then
        success, message = characters:Create(target, slot, details)
    elseif action == "appearance" then
        success, message = characters:SetAppearance(target, slot, details)
    elseif action == "delete" then
        success, message = characters:Delete(target, slot, details.name)
    elseif action == "select" then
        success, message = Launcher:Select(target, slot)
    end
    if action ~= "select" or not success then Launcher:SendStatus(target, action, success, message) end
end)

hook.Add("PlayerDisconnected", "ZombieSim.Launcher.Clear", function(target)
    target.ZM_LauncherState = nil
    target.ZM_LauncherCredits = nil
end)

function Launcher:TryAutoload(target)
    if target:IsAdmin() and autoload:GetInt() >= 1 and autoload:GetInt() <= 3 then
        self:Select(target, autoload:GetInt())
    end
end
