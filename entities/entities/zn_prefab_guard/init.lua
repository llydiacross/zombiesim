AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local function reportReady(entity, ok, problem)
    local callback = entity.ZM_GuardReadyCallback
    entity.ZM_GuardReadyCallback = nil
    if callback then callback(entity, ok, problem) end
end

local function fail(entity, problem)
    ErrorNoHalt("[ZombieSim] Prefab guard: " .. tostring(problem) .. "\n")
    reportReady(entity, false, problem)
    if IsValid(entity) then entity:Remove() end
end

function ENT:KeyValue(key, value)
    self.ZM_GuardKeyValues = self.ZM_GuardKeyValues or {}
    self.ZM_GuardKeyValues[string.lower(key)] = value
end

function ENT:Initialize()
    if not ZM_PrefabGuardConfig or not ZM_PrefabGuardTargeting then
        fail(self, "guard services are unavailable")
        return
    end
    local settings, problem = self.ZM_GuardConfig
    if settings == nil and self:CreatedByMap() then
        settings, problem = ZM_PrefabGuardConfig.FromHammer(self.ZM_GuardKeyValues or {})
        if not settings then fail(self, problem) return end
    end
    local config
    config, problem = ZM_PrefabGuardConfig.Validate(settings)
    if not config then fail(self, problem) return end
    self.ZM_GuardConfig = config
    self.ZM_AuthoredAngles = self:GetAngles()
    self:SetModel(config.model)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
    self:SetNWString("ZM_NpcName", config.name)
    self:SetNWString("ZM_Clothing_shirt", config.shirt)
    self:SetNWString("ZM_Clothing_pants", config.pants)
    self:SetNWBool("ZM_ClothingBloody", false)
    self.ZM_NextSearchAt, self.ZM_NextShotAt = 0, 0
    timer.Simple(0, function()
        if not IsValid(self) then return end
        local idle = self:LookupSequence(config.idle)
        local combat = self:LookupSequence(config.weapon.idle)
        local attack = self:LookupSequence(config.weapon.attack)
        local attachment = self:LookupAttachment("anim_attachment_RH")
        if type(idle) ~= "number" or idle < 0 or type(combat) ~= "number" or combat < 0
            or type(attack) ~= "number" or attack < 0 or type(attachment) ~= "number" or attachment <= 0 then
            fail(self, "the selected model does not support its idle, weapon animations or hand attachment")
            return
        end
        local weapon = ents.Create("prop_dynamic")
        if not IsValid(weapon) then fail(self, "could not create the guard weapon model") return end
        self.ZM_WeaponModel = weapon
        weapon:SetModel(config.weapon.model)
        weapon:Spawn()
        if not IsValid(weapon) then fail(self, "could not spawn the guard weapon model") return end
        weapon:SetSolid(SOLID_NONE)
        weapon:SetMoveType(MOVETYPE_NONE)
        weapon:SetParent(self)
        weapon:AddEffects(EF_BONEMERGE)
        weapon:SetLocalPos(Vector(0, 0, 0))
        weapon:SetLocalAngles(Angle(0, 0, 0))
        self:DeleteOnRemove(weapon)
        self.ZM_HandAttachment = attachment
        self.ZM_AttackSequence = attack
        self:ResetSequence(idle)
        self.ZM_GuardReady = true
        reportReady(self, true)
    end)
end

function ENT:OnTakeDamage(damage)
    damage:SetDamage(0)
    return 0
end

function ENT:OnRemove()
    if not self.ZM_GuardReady then reportReady(self, false, "The guard was removed before initialization completed.") end
    if IsValid(self.ZM_WeaponModel) then self.ZM_WeaponModel:Remove() end
end

function ENT:Think()
    self:FrameAdvance()
    local now = CurTime()
    if self.ZM_GuardReady then
        local config = self.ZM_GuardConfig
        local hand = self:GetAttachment(self.ZM_HandAttachment)
        if not hand or not hand.Pos then
            fail(self, "the guard hand attachment is unavailable")
            return
        end
        if now >= self.ZM_NextSearchAt then
            local target, problem = ZM_PrefabGuardTargeting.Select(self, hand.Pos, config.range)
            if problem then fail(self, problem) return end
            self.ZM_Target = target
            self.ZM_NextSearchAt = now + 0.25
        end
        if not ZM_PrefabGuardTargeting.IsZombie(self.ZM_Target) then self.ZM_Target = nil end
        if self.ZM_Target then
            if not self.ZM_Combat then
                self.ZM_Combat = true
                self:ResetSequence(config.weapon.idle)
            end
            local angles = (self.ZM_Target:WorldSpaceCenter() - self:GetPos()):Angle()
            self:SetAngles(Angle(self.ZM_AuthoredAngles.p, angles.y, self.ZM_AuthoredAngles.r))
            if now >= self.ZM_NextShotAt then
                local fired, problem = ZM_PrefabGuardTargeting.Fire(self, hand.Pos, self.ZM_Target, config.range, config.weapon)
                self.ZM_NextShotAt = now + config.weapon.delay
                if fired then
                    self.ZM_Shots = (self.ZM_Shots or 0) + 1
                    self:EmitSound(config.weapon.sound)
                    local layer = self:FindGestureSequenceLayer(self.ZM_AttackSequence)
                    if type(layer) == "number" and layer >= 0 and self:IsValidLayer(layer) then
                        self:SetLayerCycle(layer, 0)
                    else
                        layer = self:AddGestureSequence(self.ZM_AttackSequence, true)
                    end
                    if type(layer) ~= "number" or layer < 0 then
                        fail(self, "could not play the guard firing gesture")
                        return
                    end
                    self.ZM_AttackLayer = layer
                else
                    if problem ~= "The target is unavailable or obstructed." then fail(self, problem) return end
                    self.ZM_Target = nil
                    self.ZM_NextSearchAt = now
                end
            end
        elseif self.ZM_Combat then
            if self.ZM_AttackLayer and self:IsValidLayer(self.ZM_AttackLayer) then self:RemoveLayer(self.ZM_AttackLayer) end
            self.ZM_Combat, self.ZM_AttackLayer = false, nil
            self:SetAngles(self.ZM_AuthoredAngles)
            self:ResetSequence(config.idle)
        end
    end
    local nextThink = now + 0.05
    if self.ZM_Target and self.ZM_NextShotAt > now then
        nextThink = math.min(nextThink, self.ZM_NextShotAt)
    end
    self:NextThink(nextThink)
    return true
end
