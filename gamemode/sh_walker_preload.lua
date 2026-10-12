// Warm mounted Walker models in both realms before handing arrival control to the survivor.
ZM_WalkerPreload = {}
local Preload = ZM_WalkerPreload
local timeoutSeconds = 30
local readyKey = "ZM.WalkerModelsReady"

if SERVER then
    util.AddNetworkString("ZM.WalkerModelsReady")
    SetGlobalBool(readyKey, false)
    net.Receive("ZM.WalkerModelsReady", function(_, survivor)
        if not IsValid(survivor) or not survivor:IsPlayer() then return end
        survivor.ZM_WalkerModelsReady = true
    end)
end

function Preload:Start()
    if self.started then return end
    self.started = SysTime()
    self.index, self.valid, self.invalid = 1, 0, 0
    if CLIENT then
        self.step = ZM_Loading:Begin("Preparing Walker models")
        ZM_LoadingScreen:SetExtraHold("walkerModels", true)
    end
    local definition = scripted_ents.GetStored("zn_walker_zombie")
    self.models = definition and definition.t and definition.t.Models
    if type(self.models) ~= "table" or #self.models == 0 then
        self:Finish("fail", "Walker model catalogue unavailable")
        return
    end
end

function Preload:Finish(status, message)
    self.done, self.status = true, status
    self.seconds = SysTime() - self.started
    self.message = message or string.format("Prepared Walker models (%d ready, %d unavailable)", self.valid, self.invalid)
    if status ~= "ok" then ErrorNoHalt("[ZombieSim] " .. self.message .. "\n") end
    if SERVER then
        SetGlobalBool(readyKey, true)
    else
        if self.step then ZM_Loading:Finish(self.step, status, self.message) end
        net.Start("ZM.WalkerModelsReady")
        net.SendToServer()
    end
end

function Preload:HoldPlayer(survivor, complete)
    self:Start()
    survivor.ZM_WalkerPreloadWaiting = {
        started = SysTime(), complete = complete,
        step = ZM_Loading:Begin(survivor, "Preparing Walker models")
    }
end

function Preload:GetDiagnosticSnapshot()
    return { started = self.started ~= nil, done = self.done == true, status = self.status,
        valid = self.valid, invalid = self.invalid, seconds = self.seconds,
        message = self.message, released = self.released == true,
        serverReady = GetGlobalBool(readyKey, false) }
end

hook.Add("InitPostEntity", "ZM.WalkerPreload.Start", function()
    Preload:Start()
end)

hook.Add("Think", "ZM.WalkerPreload.Prepare", function()
    if not Preload.started then return end
    if not Preload.done then
        if SysTime() - Preload.started >= timeoutSeconds then
            Preload:Finish("warn", "Walker model preparation timed out; uncached models may load during play")
        else
            // One synchronous precache per frame: keep the loading screen updating between cold models.
            local model = Preload.models[Preload.index]
            if util.IsValidModel(model) then
                Preload.valid = Preload.valid + 1
            else
                Preload.invalid = Preload.invalid + 1
                ErrorNoHalt("[ZombieSim] Walker preload model unavailable: " .. tostring(model) .. "\n")
            end
            Preload.index = Preload.index + 1
            if Preload.index > #Preload.models then
                Preload:Finish(Preload.invalid == 0 and "ok" or "warn")
            end
        end
    end
    if CLIENT then
        local serverReady = GetGlobalBool(readyKey, false)
        if Preload.done and (serverReady or SysTime() - Preload.started >= timeoutSeconds) and not Preload.released then
            if not serverReady then
                ZM_Loading:Step("Server Walker preparation timed out", "warn")
                ErrorNoHalt("[ZombieSim] Server Walker preparation timed out.\n")
            end
            Preload.released = true
            ZM_LoadingScreen:SetExtraHold("walkerModels", false)
        end
        return
    end
    for _, survivor in ipairs(player.GetHumans()) do
        local waiting = survivor.ZM_WalkerPreloadWaiting
        if waiting then
            local ready = Preload.done and survivor.ZM_WalkerModelsReady == true
            local expired = SysTime() - waiting.started >= timeoutSeconds
            if ready or expired then
                survivor.ZM_WalkerPreloadWaiting = nil
                local status = ready and Preload.status or "warn"
                ZM_Loading:Finish(survivor, waiting.step, status,
                    ready and Preload.message or "Walker preparation timed out; continuing arrival")
                if expired and not ready then ErrorNoHalt("[ZombieSim] Survivor Walker preparation timed out.\n") end
                if survivor:Alive() then waiting.complete() end
            end
        end
    end
end)

if SERVER then
    concommand.Add("zombiesim_dev_walker_preload_status", function(survivor)
        if not ZM_Util.RequireAdmin(survivor, "zombiesim_dev_walker_preload_status") then return end
        local report = Preload:GetDiagnosticSnapshot()
        ZM_DevConsole:Report("walkerPreload", report)
        print("[ZombieSim] Walker preload: " .. util.TableToJSON(report))
    end)
    hook.Add("SetupMove", "ZM.WalkerPreload.HoldArrival", function(survivor, move)
        if not survivor.ZM_WalkerPreloadWaiting then return end
        move:SetForwardSpeed(0)
        move:SetSideSpeed(0)
        move:SetUpSpeed(0)
        move:SetButtons(0)
        move:SetVelocity(Vector(0, 0, 0))
    end)
end
