local Probe = {}
local timerName = "ZM.PrefabGuardProbe.Expiry"

local function chooseFinish(garment)
    local choices = {}
    for id, finish in pairs(ZM_Clothing.Finishes) do
        if finish.garment == garment then choices[#choices + 1] = id end
    end
    table.sort(choices)
    return choices[1]
end

function Probe:Stop()
    timer.Remove(timerName)
    self.LastEntities = {}
    if IsValid(self.Guard) then
        self.LastEntities[#self.LastEntities + 1] = self.Guard
        if IsValid(self.Guard.ZM_WeaponModel) then self.LastEntities[#self.LastEntities + 1] = self.Guard.ZM_WeaponModel end
    end
    if IsValid(self.Walker) then self.LastEntities[#self.LastEntities + 1] = self.Walker end
    if IsValid(self.Guard) then self.Guard:Remove() end
    if IsValid(self.Walker) then self.Walker:Remove() end
    self.Guard, self.Walker, self.Owner, self.PreMergeAngles, self.PreMergePosition = nil, nil, nil, nil, nil
end

function Probe:Start(target, weaponId, overrides)
    if not ZM_PrefabEditor:IsParticipant(target) or ZM_PrefabEditor:IsFixtureMap()
        or not target.ZM_PrefabEditorOrigin then
        return false, "The sole prefab-editor owner and a ready workspace are required."
    end
    if IsValid(self.Guard) or IsValid(self.Walker) or IsValid(self.Owner) then
        return false, "The guard preview is already active."
    end
    for _, entity in ipairs(self.LastEntities or {}) do
        if IsValid(entity) then return false, "The previous guard preview is still being removed." end
    end
    if not ZM_Clothing.CatalogueReady or type(ZM_Clothing.Finishes) ~= "table" then
        return false, "The clothing catalogue is unavailable for the guard preview."
    end
    if weaponId == nil or weaponId == "" then weaponId = "pistol" end
    if weaponId ~= "pistol" and weaponId ~= "smg" then return false, "Use pistol or smg for the guard preview." end
    local shirt, pants = chooseFinish("shirt"), chooseFinish("pants")
    if not shirt or not pants then return false, "The guard preview requires shirt and pants finishes." end
    local config = { name = "Guard preview", model = "models/player/group01/male_03.mdl",
        idle = "idle_all_01", weapon = weaponId, range = 1000, shirt = shirt, pants = pants }
    if overrides then
        config.damage, config.fireInterval, config.spread = overrides.damage, overrides.fireInterval, overrides.spread
    end
    local valid, problem = ZM_PrefabGuardConfig.Validate(config)
    if not valid then return false, problem end
    local guard = ents.Create("zn_prefab_guard")
    if not IsValid(guard) then return false, "Could not create the guard preview." end
    self.Guard, self.Owner, self.LastError = guard, target, nil
    guard.ZM_GuardConfig = config
    guard:SetPos(target.ZM_PrefabEditorOrigin + Vector(-160, 400, 0))
    guard:SetAngles(Angle(0, 0, 0))
    guard:Spawn()
    if not IsValid(guard) then self:Stop() return false, "Could not spawn the guard preview." end
    local walker = ents.Create("zn_walker_zombie")
    if not IsValid(walker) then self:Stop() return false, "Could not create the guard preview target." end
    self.Walker = walker
    walker:SetPos(target.ZM_PrefabEditorOrigin + Vector(160, 400, 0))
    walker:Spawn()
    if not IsValid(walker) then self:Stop() return false, "Could not spawn the guard preview target." end
    if overrides then walker.IsValidTarget = function() return false end end
    walker:SetMaxHealth(100000)
    walker:SetHealth(100000)
    timer.Create(timerName, overrides and 15 or 300, 1, function() Probe:Stop() end)
    timer.Simple(1, function()
        if Probe.Owner ~= target then return end
        if not IsValid(Probe.Guard) or not Probe.Guard.ZM_GuardReady or not IsValid(Probe.Guard.ZM_WeaponModel) then
            Probe:Stop()
            Probe.LastError = "The guard preview did not finish initialization."
            ErrorNoHalt("[ZombieSim] " .. Probe.LastError .. "\n")
        end
    end)
    return true
end

hook.Add("PlayerDisconnected", "ZM.PrefabGuardProbe", function(target)
    if target == Probe.Owner then Probe:Stop() end
end)
hook.Add("PreCleanupMap", "ZM.PrefabGuardProbe", function() Probe:Stop() end)
hook.Add("ShutDown", "ZM.PrefabGuardProbe", function() Probe:Stop() end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_guard_probe = "Starts, stops or reports an isolated editor guard preview."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    local action = arguments[1] or ""
    if action == "start" then
        local overrides
        if arguments[3] ~= nil or arguments[4] ~= nil or arguments[5] ~= nil then
            local damage, interval, spread = tonumber(arguments[3]), tonumber(arguments[4]), tonumber(arguments[5])
            if not damage or not interval or not spread or arguments[6] ~= nil then
                return false, "Use start <pistol|smg> <damage> <seconds per shot> <spread>."
            end
            overrides = { damage = damage, fireInterval = interval, spread = spread }
        end
        return Probe:Start(target, arguments[2], overrides)
    end
    if action == "stop" then
        if not ZM_PrefabEditor:IsOwner(target) or target ~= Probe.Owner then
            return false, "Only the guard-preview owner can stop it."
        end
        Probe:Stop()
        return true
    end
    if action == "orient" then
        if not ZM_PrefabEditor:IsParticipant(target) or target ~= Probe.Owner
            or not IsValid(Probe.Guard) or not IsValid(Probe.Guard.ZM_WeaponModel) then
            return false, "The active guard-preview owner and weapon are required."
        end
        if Probe.Guard.ZM_WeaponModel:IsEffectActive(EF_BONEMERGE) then
            return false, "Disable bone merge before adjusting attachment angles."
        end
        local pitch, yaw, roll = tonumber(arguments[2]), tonumber(arguments[3]), tonumber(arguments[4])
        for _, value in ipairs({ pitch, yaw, roll }) do
            if type(value) ~= "number" or value ~= value or math.abs(value) > 360 then
                return false, "Use orient <pitch> <yaw> <roll> with values between -360 and 360."
            end
        end
        if pitch == nil or yaw == nil or roll == nil or arguments[5] ~= nil then
            return false, "Use orient <pitch> <yaw> <roll> with values between -360 and 360."
        end
        Probe.Guard.ZM_WeaponModel:SetLocalAngles(Angle(pitch, yaw, roll))
        return true
    end
    if action == "merge" then
        if not ZM_PrefabEditor:IsParticipant(target) or target ~= Probe.Owner
            or not IsValid(Probe.Guard) or not IsValid(Probe.Guard.ZM_WeaponModel) then
            return false, "The active guard-preview owner and weapon are required."
        end
        local weapon = Probe.Guard.ZM_WeaponModel
        if arguments[2] == "on" and arguments[3] == nil then
            if weapon:IsEffectActive(EF_BONEMERGE) then return false, "Bone merge is already enabled." end
            Probe.PreMergeAngles, Probe.PreMergePosition = weapon:GetLocalAngles(), weapon:GetLocalPos()
            weapon:SetParent(Probe.Guard)
            weapon:AddEffects(EF_BONEMERGE)
            weapon:SetLocalPos(Vector(0, 0, 0))
            weapon:SetLocalAngles(Angle(0, 0, 0))
            return true
        end
        if arguments[2] == "off" and arguments[3] == nil then
            if not Probe.PreMergeAngles or not Probe.PreMergePosition then return false, "Bone merge is not active." end
            weapon:RemoveEffects(EF_BONEMERGE)
            weapon:SetParent(Probe.Guard, Probe.Guard.ZM_HandAttachment)
            weapon:SetLocalPos(Probe.PreMergePosition)
            weapon:SetLocalAngles(Probe.PreMergeAngles)
            Probe.PreMergeAngles, Probe.PreMergePosition = nil, nil
            return true
        end
        return false, "Use merge on or merge off."
    end
    if action == "status" then
        if not ZM_PrefabEditor:IsParticipant(target) then return false, "The editor owner is required." end
        local guard, walker = Probe.Guard, Probe.Walker
        local remaining = 0
        for _, entity in ipairs(Probe.LastEntities or {}) do
            if IsValid(entity) then remaining = remaining + 1 end
        end
        local status = {
            owner = target == Probe.Owner, guard = IsValid(guard), walker = IsValid(walker),
            ready = IsValid(guard) and guard.ZM_GuardReady == true or false,
            weapon = IsValid(guard) and IsValid(guard.ZM_WeaponModel) or false,
            sampleTime = CurTime(),
            shots = IsValid(guard) and guard.ZM_Shots or 0,
            weaponId = IsValid(guard) and type(guard.ZM_GuardConfig) == "table"
                and type(guard.ZM_GuardConfig.weapon) == "table" and guard.ZM_GuardConfig.weapon.id or nil,
            firingGesture = IsValid(guard) and guard.ZM_AttackLayer ~= nil
                and guard:IsValidLayer(guard.ZM_AttackLayer) or false,
            targetHealth = IsValid(walker) and walker:Health() or nil,
            cleanupRemaining = remaining, error = Probe.LastError
        }
        if IsValid(guard) and type(guard.ZM_GuardConfig) == "table"
            and type(guard.ZM_GuardConfig.weapon) == "table" then
            local weapon = guard.ZM_GuardConfig.weapon
            status.combat = { damage = weapon.damage, fireInterval = weapon.delay, spread = weapon.spread }
        end
        if status.weapon and status.walker then
            local weapon = guard.ZM_WeaponModel
            local angles = weapon:GetLocalAngles()
            status.weaponAngles = { p = angles.p, y = angles.y, r = angles.r }
            status.boneMerged = weapon:IsEffectActive(EF_BONEMERGE)
            if status.boneMerged then
                status.muzzleError = "Bone merge is client-side; inspect the rendered weapon."
            else
                local muzzleId = weapon:LookupAttachment("muzzle")
                local muzzle = muzzleId > 0 and weapon:GetAttachment(muzzleId) or nil
                if muzzle and muzzle.Pos then
                    local barrel = muzzle.Pos - weapon:GetPos()
                    local direction = walker:WorldSpaceCenter() - weapon:GetPos()
                    if barrel:LengthSqr() > 0 and direction:LengthSqr() > 0 then
                        status.muzzleAlignment = barrel:GetNormalized():Dot(direction:GetNormalized())
                    else
                        status.muzzleError = "The weapon muzzle or target direction is degenerate."
                    end
                else
                    status.muzzleError = "The weapon model has no available muzzle attachment."
                end
            end
        end
        if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabGuardProbe", status) end
        return true
    end
    return false, "Use start, stop, orient, merge or status."
end)
